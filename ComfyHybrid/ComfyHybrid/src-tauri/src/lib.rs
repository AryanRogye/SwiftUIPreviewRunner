use serde::{Deserialize, Serialize};
use std::{
    ffi::{c_char, c_void, CString},
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::{mpsc, Arc, Mutex},
    time::{SystemTime, UNIX_EPOCH},
};

#[derive(Default)]
struct PreviewState {
    preview_view: Option<usize>,
    library_handles: Vec<usize>,
}

#[derive(Debug, Deserialize, Clone, Copy)]
struct PreviewBounds {
    x: f64,
    y: f64,
    width: f64,
    height: f64,
}

#[derive(Debug, Serialize)]
struct CompilePreviewResponse {
    logs: Vec<String>,
}

struct PreparedPreview {
    dylib_path: PathBuf,
    logs: Vec<String>,
}

#[tauri::command]
async fn compile_preview(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<Mutex<PreviewState>>>,
    source: String,
    bounds: PreviewBounds,
) -> Result<CompilePreviewResponse, String> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = window;
        let _ = state;
        let _ = source;
        let _ = bounds;
        Err("Native SwiftUI preview hosting is only implemented on macOS.".to_string())
    }

    #[cfg(target_os = "macos")]
    {
        let state = state.inner().clone();
        let prepared = tauri::async_runtime::spawn_blocking(move || prepare_preview(source))
            .await
            .map_err(|error| format!("Preview compile task failed: {error}"))??;

        attach_preview_on_main_thread(window, state, prepared.dylib_path, bounds)?;

        let mut logs = prepared.logs;
        logs.push("Loaded preview dylib".to_string());
        Ok(CompilePreviewResponse { logs })
    }
}

#[tauri::command]
fn position_preview(
    window: tauri::WebviewWindow,
    state: tauri::State<'_, Arc<Mutex<PreviewState>>>,
    bounds: PreviewBounds,
) -> Result<(), String> {
    #[cfg(not(target_os = "macos"))]
    {
        let _ = window;
        let _ = state;
        let _ = bounds;
        Ok(())
    }

    #[cfg(target_os = "macos")]
    {
        let state = state.inner().clone();
        position_preview_on_main_thread(window, state, bounds)
    }
}

fn extract_view_name(source: &str) -> Option<String> {
    for line in source.lines() {
        let trimmed = line.trim_start();
        let Some(rest) = trimmed.strip_prefix("struct ") else {
            continue;
        };
        let Some(name) = rest.split(':').next().map(str::trim) else {
            continue;
        };

        if !name.is_empty() && rest.contains(": View") {
            return Some(name.to_string());
        }
    }

    None
}

fn prepare_preview(source: String) -> Result<PreparedPreview, String> {
    let mut logs = Vec::new();
    let view_name = extract_view_name(&source).ok_or_else(|| {
        "Could not find a SwiftUI view declaration like `struct ContentView: View`.".to_string()
    })?;

    logs.push(format!("Compiling View Body: {view_name}"));
    let package_dir = create_preview_package(&source, &view_name, &mut logs)?;
    build_preview_package(&package_dir, &mut logs)?;

    let dylib_path = package_dir
        .join(".build")
        .join("debug")
        .join("libPreviewApp.dylib");

    if !dylib_path.exists() {
        return Err(format!(
            "Built dylib not found at: {}",
            dylib_path.display()
        ));
    }

    Ok(PreparedPreview { dylib_path, logs })
}

fn create_preview_package(
    source: &str,
    view_name: &str,
    logs: &mut Vec<String>,
) -> Result<PathBuf, String> {
    let package_dir = std::env::temp_dir().join(format!("ComfyHybridPreview-{}", unique_suffix()));
    let source_dir = package_dir.join("Sources").join("PreviewApp");

    fs::create_dir_all(&source_dir)
        .map_err(|error| format!("Failed to create preview package: {error}"))?;

    fs::write(package_dir.join("Package.swift"), package_swift())
        .map_err(|error| format!("Failed to write Package.swift: {error}"))?;

    fs::write(source_dir.join(format!("{view_name}.swift")), source)
        .map_err(|error| format!("Failed to write view source: {error}"))?;

    fs::write(
        source_dir.join("PreviewFactory.swift"),
        preview_factory(view_name),
    )
    .map_err(|error| format!("Failed to write PreviewFactory.swift: {error}"))?;

    logs.push(format!("Preview package path: {}", package_dir.display()));
    Ok(package_dir)
}

fn build_preview_package(package_dir: &Path, logs: &mut Vec<String>) -> Result<(), String> {
    let output = Command::new("/usr/bin/swift")
        .args(["build", "--package-path"])
        .arg(package_dir)
        .output()
        .map_err(|error| format!("Failed to start swift build: {error}"))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    if !stdout.trim().is_empty() {
        logs.push(stdout.to_string());
    }

    if !stderr.trim().is_empty() {
        logs.push(stderr.to_string());
    }

    if !output.status.success() {
        return Err(format!(
            "swift build failed with exit code {}",
            output.status.code().unwrap_or(-1)
        ));
    }

    logs.push("swift build succeeded".to_string());
    Ok(())
}

fn package_swift() -> String {
    r#"// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PreviewApp",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PreviewApp",
            type: .dynamic,
            targets: ["PreviewApp"]
        ),
    ],
    targets: [
        .target(
            name: "PreviewApp"
        ),
    ]
)
"#
    .to_string()
}

fn preview_factory(view_name: &str) -> String {
    format!(
        r#"import SwiftUI
import AppKit

@_cdecl("makePreviewView")
public func makePreviewView() -> UnsafeMutableRawPointer {{
    let view = NSHostingView(rootView: {view_name}())
    return Unmanaged.passRetained(view).toOpaque()
}}
"#
    )
}

fn unique_suffix() -> String {
    let millis = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis())
        .unwrap_or_default();
    format!("{}-{millis}", std::process::id())
}

#[cfg(target_os = "macos")]
fn attach_preview_on_main_thread(
    window: tauri::WebviewWindow,
    state: Arc<Mutex<PreviewState>>,
    dylib_path: PathBuf,
    bounds: PreviewBounds,
) -> Result<(), String> {
    let (sender, receiver) = mpsc::channel();
    let window_for_main_thread = window.clone();

    window
        .run_on_main_thread(move || {
            let result =
                unsafe { attach_preview(&window_for_main_thread, &state, &dylib_path, bounds) };
            let _ = sender.send(result);
        })
        .map_err(|error| format!("Failed to schedule preview attach: {error}"))?;

    receiver
        .recv()
        .map_err(|error| format!("Failed to receive preview attach result: {error}"))?
}

#[cfg(target_os = "macos")]
fn position_preview_on_main_thread(
    window: tauri::WebviewWindow,
    state: Arc<Mutex<PreviewState>>,
    bounds: PreviewBounds,
) -> Result<(), String> {
    let (sender, receiver) = mpsc::channel();
    let window_for_main_thread = window.clone();

    window
        .run_on_main_thread(move || {
            let result = unsafe { position_preview_view(&window_for_main_thread, &state, bounds) };
            let _ = sender.send(result);
        })
        .map_err(|error| format!("Failed to schedule preview positioning: {error}"))?;

    receiver
        .recv()
        .map_err(|error| format!("Failed to receive preview positioning result: {error}"))?
}

#[cfg(target_os = "macos")]
unsafe fn attach_preview(
    window: &tauri::WebviewWindow,
    state: &Arc<Mutex<PreviewState>>,
    dylib_path: &Path,
    bounds: PreviewBounds,
) -> Result<(), String> {
    let handle = open_library(dylib_path)?;
    let make_preview_view = load_make_preview_view(handle)?;
    let preview_view = make_preview_view() as usize;

    {
        let mut state = state
            .lock()
            .map_err(|_| "Preview state lock was poisoned.".to_string())?;

        if let Some(old_view) = state.preview_view.take() {
            remove_from_superview(old_view);
        }

        state.preview_view = Some(preview_view);
        state.library_handles.push(handle as usize);
    }

    let parent_view = window
        .ns_view()
        .map_err(|error| format!("Could not access Tauri NSView: {error}"))?
        as usize;

    add_subview(parent_view, preview_view);
    position_preview_view(window, state, bounds)
}

#[cfg(target_os = "macos")]
unsafe fn position_preview_view(
    window: &tauri::WebviewWindow,
    state: &Arc<Mutex<PreviewState>>,
    bounds: PreviewBounds,
) -> Result<(), String> {
    let preview_view = {
        let state = state
            .lock()
            .map_err(|_| "Preview state lock was poisoned.".to_string())?;
        state.preview_view
    };

    let Some(preview_view) = preview_view else {
        return Ok(());
    };

    let parent_view = window
        .ns_view()
        .map_err(|error| format!("Could not access Tauri NSView: {error}"))?
        as usize;

    set_preview_frame(parent_view, preview_view, bounds);
    Ok(())
}

#[cfg(target_os = "macos")]
type MakePreviewView = unsafe extern "C" fn() -> *mut c_void;

#[cfg(target_os = "macos")]
const RTLD_NOW: i32 = 0x2;

#[cfg(target_os = "macos")]
const RTLD_LOCAL: i32 = 0x4;

#[cfg(target_os = "macos")]
extern "C" {
    fn dlopen(path: *const c_char, mode: i32) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dlerror() -> *const c_char;
}

#[cfg(target_os = "macos")]
unsafe fn open_library(path: &Path) -> Result<*mut c_void, String> {
    let path = CString::new(path.to_string_lossy().as_bytes())
        .map_err(|_| "Dylib path contained an interior null byte.".to_string())?;
    let handle = dlopen(path.as_ptr(), RTLD_NOW | RTLD_LOCAL);

    if handle.is_null() {
        return Err(format!("dlopen failed: {}", last_dl_error()));
    }

    Ok(handle)
}

#[cfg(target_os = "macos")]
unsafe fn load_make_preview_view(handle: *mut c_void) -> Result<MakePreviewView, String> {
    let symbol_name = CString::new("makePreviewView").expect("static symbol name has no null byte");
    let symbol = dlsym(handle, symbol_name.as_ptr());

    if symbol.is_null() {
        return Err("Could not find makePreviewView symbol".to_string());
    }

    Ok(std::mem::transmute::<*mut c_void, MakePreviewView>(symbol))
}

#[cfg(target_os = "macos")]
unsafe fn last_dl_error() -> String {
    let error = dlerror();

    if error.is_null() {
        "unknown dynamic loader error".to_string()
    } else {
        std::ffi::CStr::from_ptr(error)
            .to_string_lossy()
            .into_owned()
    }
}

#[cfg(target_os = "macos")]
unsafe fn add_subview(parent_view: usize, preview_view: usize) {
    use objc2_app_kit::NSView;

    let parent = &*(parent_view as *mut NSView);
    let preview = &*(preview_view as *mut NSView);

    preview.setAutoresizingMask(
        objc2_app_kit::NSAutoresizingMaskOptions::ViewWidthSizable
            | objc2_app_kit::NSAutoresizingMaskOptions::ViewHeightSizable,
    );
    parent.addSubview(preview);
}

#[cfg(target_os = "macos")]
unsafe fn remove_from_superview(preview_view: usize) {
    use objc2_app_kit::NSView;

    let preview = &*(preview_view as *mut NSView);
    preview.removeFromSuperview();
}

#[cfg(target_os = "macos")]
unsafe fn set_preview_frame(parent_view: usize, preview_view: usize, bounds: PreviewBounds) {
    use objc2_app_kit::NSView;
    use objc2_foundation::{NSPoint, NSRect, NSSize};

    let parent = &*(parent_view as *mut NSView);
    let preview = &*(preview_view as *mut NSView);
    let parent_height = parent.frame().size.height;
    let y = parent_height - bounds.y - bounds.height;

    preview.setFrame(NSRect::new(
        NSPoint::new(bounds.x, y),
        NSSize::new(bounds.width.max(0.0), bounds.height.max(0.0)),
    ));
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .manage(Arc::new(Mutex::new(PreviewState::default())))
        .invoke_handler(tauri::generate_handler![compile_preview, position_preview])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

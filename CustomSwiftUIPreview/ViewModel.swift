//
//  ViewModel.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/1/26.
//

import Foundation
import AppKit
import Darwin

@Observable
@MainActor
class ViewModel {
    
    var text: String = """
    
    import SwiftUI
    
    struct ContentView: View {
        @State private var isOn = true
        @State private var progress = 0.68
        
        var body: some View {
            ZStack {
                VStack(spacing: 22) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.white)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                        .shadow(radius: 20)
                    
                    Text("Comfy Preview")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    
                    Text("SwiftUI compiled from a tiny generated preview app.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                    
                    Toggle("Live Preview Mode", isOn: $isOn)
                        .toggleStyle(.switch)
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                    
                    ProgressView(value: progress)
                        .frame(width: 260)
                    
                    Button {
                        progress = progress >= 1 ? 0 : min(progress + 0.1, 1)
                    } label: {
                        Text("Cook")
                            .font(.headline)
                            .padding(.horizontal, 34)
                            .padding(.vertical, 12)
                            .background(.white)
                            .foregroundStyle(.black)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(40)
            }
        }
    }
    """
    
    var magnification: CGFloat = 1.0
    var allowEdit = true
    var vimEnabled = true
    var previewView: NSView?
    
    let ViewBodyNamePattern = /struct\s+(\w+):/
    
    var logs: [String] = []
    private var loadedLibraryHandles: [UnsafeMutableRawPointer] = []
    
    
    public func compile() {
        guard let ViewBodyName = getViewBodyName() else { return }
        previewView = nil
        logs.append("Compiling View Body: \(ViewBodyName)")
        let previewFactoryStructure = getPreviewFactoryStructure(ViewBodyName)
        logs.append("Created Preview Factory")
        let packageDotSwiftStructure = getPackageDotSwiftFile("PreviewApp")
        
        /// Now We Can Make 2 Files
        let ViewFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ViewBodyName).swift")
        logs.append("Created View File: \(ViewFile.path)")
        
        let PreviewFactoryFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreviewFactory.swift")
        logs.append("Created Preview Factory File: \(PreviewFactoryFile.path)")
        
        let PackageSwiftFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Package.swift")
        logs.append("Created Package.swift")
        
    
        /// Write To the files
        
        /// Create Package.swift file
        do {
            try write(to: PackageSwiftFile, content: packageDotSwiftStructure)
            logs.append("Wrote Package Swift File")
        } catch {
            logs.append("Error Writing To Package.swift File")
            return
        }
        
        /// Create View File
        do {
            try write(to: ViewFile, content: text)
            logs.append("Wrote To View File")
        } catch {
            logs.append("Error Writing To View File")
            return
        }
        
        /// Create Preview Factory File
        do {
            try write(to: PreviewFactoryFile, content: previewFactoryStructure)
            logs.append("Wrote To Preview Factory File")
        } catch {
            logs.append("Error Writing To Preview Factory File")
            return
        }
        
        /// Create A Temporary Directory
        let name = "PreviewApp-\(UUID())"
        let swiftUIPreviewFolder = createTempFolder(named: name)
        
        do {
            try FileManager.default.moveItem(at: PackageSwiftFile, to: swiftUIPreviewFolder.appendingPathComponent("Package.swift"))
            logs.append("Moved Package.swift Into Preview Folder")
        } catch {
            logs.append("Error Moving Package.swift into Preview Folder")
            return
        }
        
        let sourcesFolder: URL
        do {
            sourcesFolder = try self.createFolder(named: "Sources", inside: swiftUIPreviewFolder)
        } catch {
            logs.append("Error Creating Sources Folder")
            return
        }
        
        let previewAppFolder: URL
        do {
            previewAppFolder = try self.createFolder(named: "PreviewApp", inside: sourcesFolder)
        } catch {
            logs.append("Error Creating Preview App Folder")
            return
        }
        
        
        /// Move ViewFile and PreviewFactoryFile into Folder
        do {
            try FileManager.default.moveItem(at: ViewFile, to: previewAppFolder.appendingPathComponent("\(ViewBodyName).swift"))
            logs.append("Moved View File Into Preview App Folder")
        } catch {
            logs.append("Error Moving File Into Preview FOlder")
            return
        }
        
        do {
            try FileManager.default.moveItem(at: PreviewFactoryFile, to: previewAppFolder.appendingPathComponent("PreviewFactory.swift"))
            logs.append("Moved Preview Factory Into Preview App Folder")
        } catch {
            logs.append("Error Moving Preview Factory Into Preview Folder")
            return
        }
        
        logs.append("Preview package path: \(swiftUIPreviewFolder.path)")
        
        /// Build Package
        guard buildPreviewPackage(at: swiftUIPreviewFolder) else { return }
        
        let dylibURL = swiftUIPreviewFolder
            .appendingPathComponent(".build")
            .appendingPathComponent("debug")
        /// the actual dynamic library we can load in
            .appendingPathComponent("libPreviewApp.dylib")
        
        loadPreview(from: dylibURL)
    }
}

// MARK: - Build/Preview
extension ViewModel {
    /// Function Builds the Swift Package
    /// Returns true if everything goes well
    private func buildPreviewPackage(
        at packageURL: URL
    ) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        process.arguments = ["build", "--package-path", packageURL.path]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        do {
            /// Build Swift Package
            try process.run()
            process.waitUntilExit()
        } catch {
            logs.append("Failed to start swift build: \(error.localizedDescription)")
            return false
        }
        
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        if let buildLog = String(data: output, encoding: .utf8), !buildLog.isEmpty {
            logs.append(buildLog)
        }
        
        guard process.terminationStatus == 0 else {
            logs.append("swift build failed with exit code \(process.terminationStatus)")
            return false
        }
        
        logs.append("swift build succeeded")
        return true
    }
    
    private func loadPreview(from dylibURL: URL) {
        /// SwiftPM should have produced libPreviewApp.dylib at this path.
        /// If the file is missing, the build either failed earlier or SwiftPM changed
        /// the output location/name we are assuming.
        guard FileManager.default.fileExists(atPath: dylibURL.path) else {
            logs.append("Built dylib not found at: \(dylibURL.path)")
            return
        }
        
        guard let handle = dlopen(dylibURL.path, RTLD_NOW | RTLD_LOCAL) else {
            logs.append("dlopen failed: \(String(cString: dlerror()))")
            return
        }
        
        /// The generated PreviewFactory.swift exports this exact C symbol:
        /// @_cdecl("makePreviewView").
        /// dlsym finds the raw function pointer for that exported symbol inside the dylib.
        guard let symbol = dlsym(handle, "makePreviewView") else {
            logs.append("Could not find makePreviewView symbol")
            return
        }
        
        /// This type must match the generated function signature exactly:
        /// @convention(c) is required because @_cdecl exports a C-callable function.
        typealias MakePreviewView = @convention(c) () -> UnsafeMutableRawPointer
        
        /// Codex - This is unsafe by nature: if the symbol has a different signature, the app can crash.
        let makePreviewView = unsafeBitCast(symbol, to: MakePreviewView.self)
        
        let pointer = makePreviewView()
        
        // Convert the opaque retained pointer back into a real NSView.
        // takeRetainedValue balances passRetained from the generated dylib, so ARC now owns it.
        previewView = Unmanaged<NSView>.fromOpaque(pointer).takeRetainedValue()
        
        // Keep the dlopen handle alive for the lifetime of the preview.
        // If we closed/unloaded the dylib while previewView still contains Swift types from it,
        // the app would be at high risk of crashing. For this MVP, we intentionally retain
        // loaded preview libraries until the app exits.
        loadedLibraryHandles.append(handle)
        logs.append("Loaded preview dylib")
    }

}

// MARK: - Code Generation
extension ViewModel {
    /// Function Extracts the view body name
    /// lets say for example we have:
    ///
    /// struct ContentView: View {
    ///    var body: some View {
    ///        VStack {
    ///            Image(systemName: "globe")
    ///                .imageScale(.large)
    ///                .foregroundStyle(.tint)
    ///            Text("Hello, world!")
    ///        }
    ///        .padding()
    ///    }
    /// }
    ///
    /// This Will Return Back: ContentView
    public func getViewBodyName() -> String? {
        if let match = text.firstMatch(of: ViewBodyNamePattern) {
            return String(match.1)
        }
        return nil
    }
    
    /// The key part that makes it all work
    /// Function returns a string which exports the preview as an AppKit view.
    /// we pass this back as a opaque pointer through a C symbol
    /// then conversion stuff bam -> live NSView inside app
    public func getPreviewFactoryStructure(_ ViewBodyName: String) -> String {
        return """
        import SwiftUI
        import AppKit

        @_cdecl("makePreviewView")
        public func makePreviewView() -> UnsafeMutableRawPointer {
            let view = NSHostingView(rootView: \(ViewBodyName)())
            return Unmanaged.passRetained(view).toOpaque()
        }
        """
    }
    
    /// Function Generates a Package.swift string
    /// it uses a name that was given for the package name
    public func getPackageDotSwiftFile(_ PackageName: String) -> String {
        return """
        // swift-tools-version: 6.2
        // The swift-tools-version declares the minimum version of Swift required to build this package.
        
        import PackageDescription
        
        let package = Package(
            name: "\(PackageName)",
            platforms: [
                .macOS(.v15)
            ],
            products: [
                .library(
                    name: "\(PackageName)",
                    type: .dynamic,
                    targets: ["\(PackageName)"]
                ),
            ],
            targets: [
                .target(
                    name: "\(PackageName)"
                ),
            ]
        )
        """
    }
}

// MARK: - URL Stuff
extension ViewModel {
    private func createFolder(named name: String, inside parent: URL) throws -> URL {
        let folderURL = parent.appendingPathComponent(name)
        
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        return folderURL
    }
    
    private func createTempFolder(named name: String) -> URL {
        let url = FileManager
            .default
            .temporaryDirectory
            .appendingPathComponent(name)
        
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            print("Failed to create temp folder:", error)
        }
        
        return url
    }
    
    /// Function Writes to file
    private func write(to file: URL, content: String) throws {
        try content.write(to: file, atomically: true, encoding: .utf8)
    }
}

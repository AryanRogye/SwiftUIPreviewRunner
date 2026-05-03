import { useCallback, useEffect, useRef, useState } from "react";
import { invoke } from "@tauri-apps/api/core";
import Editor, { type OnMount } from "@monaco-editor/react";
import { initVimMode, type VimAdapterInstance } from "monaco-vim";
import "monaco-editor/esm/vs/basic-languages/swift/swift.contribution";
import "./App.css";

const initialSource = `import SwiftUI

struct ContentView: View {
    @State private var isOn = true
    @State private var progress = 0.68

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.indigo, .teal],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

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

                Text("SwiftUI compiled from Tauri and hosted as a live NSView.")
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
`;

type PreviewBounds = {
  x: number;
  y: number;
  width: number;
  height: number;
};

type CompilePreviewResponse = {
  logs: string[];
};

function App() {
  const editorRef = useRef<Parameters<OnMount>[0] | null>(null);
  const previewRef = useRef<HTMLDivElement>(null);
  const vimStatusRef = useRef<HTMLDivElement>(null);
  const vimModeRef = useRef<VimAdapterInstance | null>(null);
  const [logs, setLogs] = useState<string[]>([]);
  const [isCompiling, setIsCompiling] = useState(false);
  const [vimEnabled, setVimEnabled] = useState(true);

  const getPreviewBounds = useCallback((): PreviewBounds | null => {
    const preview = previewRef.current;

    if (!preview) {
      return null;
    }

    const rect = preview.getBoundingClientRect();
    return {
      x: rect.x,
      y: rect.y,
      width: rect.width,
      height: rect.height,
    };
  }, []);

  const positionPreview = useCallback(async () => {
    const bounds = getPreviewBounds();

    if (!bounds) {
      return;
    }

    await invoke("position_preview", { bounds });
  }, [getPreviewBounds]);

  const attachVimMode = useCallback(() => {
    if (!editorRef.current || !vimStatusRef.current || vimModeRef.current) {
      return;
    }

    vimModeRef.current = initVimMode(editorRef.current, vimStatusRef.current);
  }, []);

  const detachVimMode = useCallback(() => {
    vimModeRef.current?.dispose();
    vimModeRef.current = null;

    if (vimStatusRef.current) {
      vimStatusRef.current.textContent = "INSERT";
    }
  }, []);

  const handleEditorMount: OnMount = useCallback(
    (editor) => {
      editorRef.current = editor;

      if (vimEnabled) {
        attachVimMode();
      }
    },
    [attachVimMode, vimEnabled],
  );

  async function compilePreview() {
    const bounds = getPreviewBounds();

    if (!bounds) {
      setLogs((current) => ["Preview host is not mounted.", ...current]);
      return;
    }

    setIsCompiling(true);
    setLogs((current) => ["Compiling preview...", ...current]);

    try {
      const source = editorRef.current?.getValue() ?? initialSource;
      const response = await invoke<CompilePreviewResponse>("compile_preview", {
        source,
        bounds,
      });
      setLogs(response.logs);
    } catch (error) {
      setLogs((current) => [String(error), ...current]);
    } finally {
      setIsCompiling(false);
    }
  }

  useEffect(() => {
    const preview = previewRef.current;

    if (!preview) {
      return;
    }

    const observer = new ResizeObserver(() => {
      void positionPreview();
    });

    observer.observe(preview);
    window.addEventListener("resize", positionPreview);

    return () => {
      observer.disconnect();
      window.removeEventListener("resize", positionPreview);
    };
  }, [positionPreview]);

  useEffect(() => {
    if (vimEnabled) {
      attachVimMode();
    } else {
      detachVimMode();
    }

    return () => {
      detachVimMode();
    };
  }, [attachVimMode, detachVimMode, vimEnabled]);

  return (
    <main className="app-shell">
      <section className="toolbar">
        <div>
          <h1>ComfyHybrid</h1>
          <p>React editor shell with a native SwiftUI/AppKit preview host.</p>
        </div>

        <div className="toolbar-actions">
          <button
            className={vimEnabled ? "mode-button is-active" : "mode-button"}
            onClick={() => setVimEnabled((current) => !current)}
          >
            {vimEnabled ? "Vim On" : "Vim Off"}
          </button>

          <button onClick={compilePreview} disabled={isCompiling}>
            {isCompiling ? "Compiling..." : "Compile Preview"}
          </button>
        </div>
      </section>

      <section className="workspace">
        <div className="editor-pane">
          <div className="pane-header">
            <span>SwiftUI Source</span>
            <div ref={vimStatusRef} className="vim-status">
              {vimEnabled ? "NORMAL" : "INSERT"}
            </div>
          </div>
          <div className="editor-host">
            <Editor
              defaultLanguage="swift"
              language="swift"
              theme="vs-dark"
              defaultValue={initialSource}
              onMount={handleEditorMount}
              options={{
                automaticLayout: true,
                fontFamily: "SF Mono, Menlo, Consolas, monospace",
                fontSize: 13,
                lineHeight: 19,
                minimap: { enabled: false },
                padding: { top: 12, bottom: 12 },
                scrollBeyondLastLine: false,
                tabSize: 4,
                wordWrap: "on",
              }}
            />
          </div>
        </div>

        <div className="right-pane">
          <div className="preview-pane">
            <div className="pane-header">
              <span>Native Preview</span>
            </div>
            <div ref={previewRef} className="preview-host" />
          </div>

          <div className="logs-pane">
            <div className="pane-header">
              <span>Logs</span>
            </div>
            <pre>{logs.join("\n")}</pre>
          </div>
        </div>
      </section>
    </main>
  );
}

export default App;

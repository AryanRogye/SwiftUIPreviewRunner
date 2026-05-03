# AGENTS.md

Guidance for Codex and other coding agents working in this repo.

## Project Shape

CustomSwiftUIPreview is a macOS SwiftUI app that lets a user edit SwiftUI source, compile it into a temporary Swift package, and load the preview back into the host app.

## Default Workflow

- Read the relevant Swift files before editing.
- Keep changes tightly scoped to the user's request.
- Do not rewrite unrelated views or refactor broad areas unless explicitly asked.
- Preserve the preview compile/load flow unless the request is specifically about that flow.
- After Swift code changes, run:

```sh
xcodebuild -project CustomSwiftUIPreview.xcodeproj -scheme CustomSwiftUIPreview -configuration Debug build
```

- Report whether the build succeeded.

## Swift Style

- Match the existing file style.
- Use `///` comments above important functions, especially helpers that are not obvious.
- Include small examples in comments when they clarify behavior.
- Prefer comments like the ones in `CustomSwiftUIPreview/ViewModel.swift`: short, practical, and tied to what the code does.
- Avoid noisy comments that simply restate a line of code.
- Keep code ASCII unless the surrounding file already uses non-ASCII for a clear reason.

When breaking up a type into extensions:

1. The main body contains ONLY:
   - Stored properties
   - init (if custom)
   - The single public entry point that triggers the type's main job

2. Each extension must be named after a CONCEPT (what it does), 
   not a category (what it is). Prefer verb phrases.
   
3. The order of extensions should follow the narrative of how 
   the type is actually used — setup → trigger → work → output.
   In ViewModel: Workspace Setup → Build/Preview → Code Generation

- Break up long classes/structs/actors into extensions that tell a story for other people reading

## Public-Safe Paths

Never hardcode a developer-specific path such as:

```swift
"/Users/aryanrogye/..."
```

Use runtime discovery instead:

- `FileManager.default.homeDirectoryForCurrentUser`
- common Homebrew locations like `/opt/homebrew/bin` and `/usr/local/bin`
- scanning `~/.nvm/versions/node/*/bin` when looking for nvm Node installs
- fallback to `/usr/bin/env` where appropriate

This project is public, so paths should work for other users.

## Codex Integration

Codex should remain optional.

- The chat sidebar must be hideable.
- The editor, preview, logs, and compile button must keep working when chat is hidden.
- Do not make preview usage depend on Codex being installed.
- If adding Codex features, show useful errors in the UI instead of failing silently.
- Pass the current editor source to Codex as the source of truth.
- Include recent user/assistant chat history for follow-up context, but avoid unbounded prompt growth.
- Do not include local debug/status messages, such as model selection notices, as semantic chat history.

## Codex CLI Launching

When launching Codex from the app:

- Do not assume Xcode provides the same `PATH` as Terminal.
- Build a process environment that includes likely Node/Codex bin directories.
- Prefer discovering `codex` in common install locations before falling back to `/usr/bin/env codex`.
- Keep the Codex process sandboxed for this app's use case.
- Codex should return structured JSON; the app should decide whether and how to update the editor.

## SwiftUI Editing Assistant Rules

When changing the generated/editor SwiftUI source through Codex:

- Make the smallest in-place edit that satisfies the request.
- Preserve layout, state, styling, and root view names unless explicitly asked to change them.
- Do not add `@main`, `App`, `Scene`, or `WindowGroup`.
- Do not add placeholder comments like `// existing code here`.
- Do not invent unrelated features.
- Return complete Swift source when replacing the editor text.

## UI Expectations

- This is a tool UI, not a marketing page.
- Keep controls practical and compact.
- Use system icons where they make the toolbar clearer.
- Avoid hiding core preview controls behind the Codex sidebar.
- If a long-running action starts, expose visible state so the user knows something is happening.

## Git Safety

- The worktree may contain user changes.
- Do not revert user changes unless explicitly asked.
- If unrelated files are dirty, leave them alone.
- If touching a file with existing changes, read it first and preserve the user's work.

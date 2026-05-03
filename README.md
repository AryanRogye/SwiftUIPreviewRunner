# SwiftUI Preview Runner

SwiftUI playground without Xcode

Paste SwiftUI code → compiles → runs as preview app.

Xcode previews are powerful, but they are tied to Xcode projects and can feel heavy for quick UI experiments. This explores a faster feedback loop for testing small SwiftUI views in isolation.

Note: This started as a proof of concept while building another app. I'm sharing it because the core idea worked and others might find it useful or want to build on it. Not sure where it goes from here. open to ideas.

This recording is from an earlier version, before the workflow was made async. The current version now runs asynchronously, so the UI no longer blocks during execution

https://github.com/user-attachments/assets/a2ee16cb-e0dc-4835-beb9-346665d76fd6

## Codex Integration
<img width="1564" height="1001" alt="Screenshot 2026-05-02 at 7 24 06 PM" src="https://github.com/user-attachments/assets/28ee2ac4-8136-4a3e-93de-2ccda940e1b3" />

| This is crazy like mind blown 🤯 I just kept throwing crazy shit at it and it kept doing it😂

## Security Note

Previews are compiled and loaded into the host app process. Do not run untrusted Swift code with this tool.

## Tauri Integration

The preview engine can be embedded inside a Tauri app, allowing a web-based UI to control a fully native SwiftUI preview renderer.

<img width="1512" height="949" alt="Screenshot 2026-05-02 at 9 41 36 PM" src="https://github.com/user-attachments/assets/a810003d-c8aa-4c6f-bc41-5d52fb97b5b5" />


## License

MIT License. See [LICENSE](LICENSE).

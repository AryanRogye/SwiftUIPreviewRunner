# SwiftUI Preview Runner

Paste SwiftUI code → compiles → runs as preview app.

Proof of concept for in-app SwiftUI live previews without Xcode.

This recording is from an earlier version, before the workflow was made async. The current version now runs asynchronously, so the UI no longer blocks during execution

https://github.com/user-attachments/assets/a2ee16cb-e0dc-4835-beb9-346665d76fd6

## Security Note

Previews are compiled and loaded into the host app process. Do not run untrusted Swift code with this tool.

## License

MIT License. See [LICENSE](LICENSE).

//
//  CodexService.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/2/26.
//

import Foundation

enum CodexServiceError: Error, LocalizedError {
    case failedToStart(String)
    case failed(Int32, String)
    case missingOutput
    case invalidOutput(String)
    
    var errorDescription: String? {
        switch self {
        case .failedToStart(let message):
            return "Failed to start Codex: \(message)"
        case .failed(let status, let output):
            return "Codex exited with status \(status): \(output)"
        case .missingOutput:
            return "Codex did not produce a final response."
        case .invalidOutput(let output):
            return "Codex returned invalid JSON: \(output)"
        }
    }
}

actor CodexService {
    /// Sends the user's request to the local Codex CLI.
    ///
    /// The app gives Codex the current editor text, recent chat history, and
    /// the selected model. Codex returns JSON, and the app decides whether to
    /// write the returned Swift source back into the editor.
    ///
    /// Example:
    /// - prompt: "make the background yellow"
    /// - currentSwiftSource: the full SwiftUI source currently in the editor
    /// - model: `.gpt54Mini`
    func send(
        prompt: String,
        currentSwiftSource: String,
        conversationHistory: [CodexConversationMessage],
        model: CodexModel
    ) async throws -> CodexResponse {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-response-\(UUID().uuidString).json")
        
        let process = Process()
        let command = codexCommand()
        process.executableURL = command.executableURL
        process.arguments = command.argumentsPrefix + [
            "exec",
            "--model", model.rawValue,
            "--sandbox", "read-only",
            "--skip-git-repo-check",
            "--output-last-message", outputURL.path,
            "-"
        ]
        process.environment = codexEnvironment()
        
        let stdin = Pipe()
        let output = Pipe()
        process.standardInput = stdin
        process.standardOutput = output
        process.standardError = output
        
        do {
            try process.run()
        } catch {
            throw CodexServiceError.failedToStart(error.localizedDescription)
        }
        
        let instructions = codexPrompt(
            userPrompt: prompt,
            currentSwiftSource: currentSwiftSource,
            conversationHistory: conversationHistory
        )
        stdin.fileHandleForWriting.write(Data(instructions.utf8))
        try? stdin.fileHandleForWriting.close()
        
        process.waitUntilExit()
        
        let processOutput = output.fileHandleForReading.readDataToEndOfFile()
        let processOutputText = String(data: processOutput, encoding: .utf8) ?? ""
        
        guard process.terminationStatus == 0 else {
            throw CodexServiceError.failed(process.terminationStatus, processOutputText)
        }
        
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw CodexServiceError.missingOutput
        }
        
        let responseText = try String(contentsOf: outputURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let data = responseText.data(using: .utf8) else {
            throw CodexServiceError.invalidOutput(responseText)
        }
        
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard let dictionary = object as? [String: Any],
                  let message = dictionary["message"] as? String else {
                throw CodexServiceError.invalidOutput(responseText)
            }
            
            return CodexResponse(
                message: message,
                swiftSource: dictionary["swiftSource"] as? String
            )
        } catch {
            throw CodexServiceError.invalidOutput(responseText)
        }
    }
    
    /// Formats prior user and assistant messages for the next Codex prompt.
    ///
    /// We keep this as plain text instead of asking Codex CLI to resume a
    /// session because the editor source should always stay the source of truth.
    ///
    /// Example output:
    /// ```
    /// [user] make the button red
    ///
    /// [assistant] Updated the button color.
    /// ```
    private func formattedConversationHistory(_ messages: [CodexConversationMessage]) -> String {
        guard !messages.isEmpty else {
            return "No prior conversation."
        }
        
        return messages
            .map { message in
                "[\(message.role.rawValue)] \(message.content)"
            }
            .joined(separator: "\n\n")
    }
    
    /// Finds the Codex executable on the current machine.
    ///
    /// Xcode-launched apps usually do not inherit the same PATH as Terminal,
    /// so we check common install locations directly before falling back to
    /// `/usr/bin/env codex`.
    ///
    /// Example locations:
    /// - `~/.nvm/versions/node/v20.17.0/bin/codex`
    /// - `/opt/homebrew/bin/codex`
    /// - `/usr/local/bin/codex`
    private func codexCommand() -> (executableURL: URL, argumentsPrefix: [String]) {
        let candidates = nodeBinDirectories().map { "\($0)/codex" } + [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return (URL(fileURLWithPath: candidate), [])
        }
        
        return (URL(fileURLWithPath: "/usr/bin/env"), ["codex"])
    }
}

// MARK: - Enviornment Related
extension CodexService {
    /// Builds the environment used when launching Codex.
    ///
    /// This mainly fixes GUI app PATH issues. A user may have installed Codex
    /// through npm/nvm, but Xcode may launch this app without the Node bin folder
    /// in PATH. Prepending these directories lets the Codex shell script find
    /// `node`.
    ///
    /// Example:
    /// - Existing PATH: `/usr/bin:/bin`
    /// - Added PATH prefix: `~/.nvm/versions/node/v20.17.0/bin:/opt/homebrew/bin`
    private func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let binDirectories = nodeBinDirectories() + [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (binDirectories + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        
        return environment
    }
    
    /// Returns likely user-level bin directories for Node and Codex.
    ///
    /// This scans all installed nvm Node versions instead of hardcoding one
    /// developer's local path, which keeps the public app usable on other Macs.
    ///
    /// Example:
    /// - `~/.nvm/versions/node/v20.17.0/bin`
    /// - `~/.nvm/versions/node/v22.11.0/bin`
    /// - `~/.local/bin`
    private func nodeBinDirectories() -> [String] {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        let nvmNodeVersionsDirectory = "\(homeDirectory)/.nvm/versions/node"
        let nvmBinDirectories = (try? FileManager.default.contentsOfDirectory(
            atPath: nvmNodeVersionsDirectory
        ))?
            .sorted()
            .reversed()
            .map { "\(nvmNodeVersionsDirectory)/\($0)/bin" } ?? []
        
        return nvmBinDirectories + [
            "\(homeDirectory)/.local/bin",
            "\(homeDirectory)/bin"
        ]
    }

}

// MARK: - Prompt
extension CodexService {
    /// Creates the full instruction prompt sent to Codex.
    ///
    /// The current Swift source is included every time so Codex can make an
    /// edit without reading files. Recent conversation is included only as
    /// context for follow-up requests.
    ///
    /// Example:
    /// - Current source has a blue button
    /// - Recent chat says the user asked for a larger title
    /// - New request says "now make the button red"
    /// - Codex should only change the button color
    private func codexPrompt(
        userPrompt: String,
        currentSwiftSource: String,
        conversationHistory: [CodexConversationMessage]
    ) -> String {
    """
    You are embedded inside CustomSwiftUIPreview.
    
    Priority order (highest to lowest):
    1. App and runtime rules
    2. This prompt
    3. Current Swift source (source of truth)
    4. Recent conversation
    5. User request
    
    The user is editing this SwiftUI source. Preserve everything not explicitly changed:
    
    ```swift
    \(currentSwiftSource)
    ```
    
    Recent conversation:
    \(formattedConversationHistory(conversationHistory))
    
    User request:
    \(userPrompt)
    
    Return only a single JSON object:
    {
      "message": "one short sentence describing the edit or assumption made",
      "swiftSource": "complete Swift source, or null only if the request is impossible, contradictory, or unsafe"
    }
    
    Rules:
    - Target is macOS 15 and above ONLY
    - Do not modify files, run commands, or include Markdown fences.
    - Make the smallest in-place edit that satisfies the request.
    - Do not rewrite the file or introduce new types unless the request clearly requires it.
    - Do not rename the root view type.
    - Do not add unrelated improvements, cleanup, or refactors.
    - Preserve layout, state, and styling unless the user explicitly asks to change them.
    - If ambiguous but a reasonable interpretation exists, make the best-effort edit and state the assumption in `message`.
    - Return null swiftSource only when the request is impossible, contradictory, or would break the view.
    - swiftSource must be complete, valid Swift that can be used directly in the editor.
    - No @main, App, Scene, or WindowGroup.
    - All referenced symbols must be defined within the source.
    - No new imports beyond SwiftUI and Foundation unless already present.
    - No placeholder comments like "// existing code here".
    - Do not invent features not asked for.
    - If you introduce a helper type, define it in the same source.
    
    Examples of acceptable edits:
    - "make the button red" → change only the button's color modifier.
    - "add a title above the list" → insert a Text view above the List, nothing else.
    - "center the content" → adjust alignment only, do not restructure the view.
    - "make it darker" → adjust colors or materials only.
    
    Examples of unacceptable edits:
    - Rewriting ContentView from scratch when one modifier needs to change.
    - Adding a helper struct when the change fits inline.
    - Returning null swiftSource because the request is vague — attempt it instead.
    """
    }
}

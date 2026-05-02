//
//  CodexService.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/2/26.
//

import Foundation

enum CodexModel: String, CaseIterable, Identifiable, Sendable {
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .gpt54Mini:
            "GPT-5.4 Mini"
        case .gpt54:
            "GPT-5.4"
        case .gpt55:
            "GPT-5.5"
        }
    }
}

struct CodexResponse: Sendable {
    let message: String
    let swiftSource: String?
}

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
    func send(
        prompt: String,
        currentSwiftSource: String,
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
        
        let instructions = codexPrompt(userPrompt: prompt, currentSwiftSource: currentSwiftSource)
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
    
    private func codexPrompt(userPrompt: String, currentSwiftSource: String) -> String {
        """
        You are embedded inside CustomSwiftUIPreview.
        
        The user is editing this SwiftUI source:
        
        ```swift
        \(currentSwiftSource)
        ```
        
        User request:
        \(userPrompt)
        
        Return only a single JSON object with this shape:
        {
          "message": "short user-facing summary",
          "swiftSource": "complete replacement Swift source, or null if no edit is needed"
        }
        
        Rules:
        - Do not modify files.
        - Do not run commands.
        - Do not include Markdown fences.
        - If editing, swiftSource must be complete Swift source for the editor.
        - Do not include @main, App, Scene, or WindowGroup.
        - Usually define struct ContentView: View.
        """
    }
    
    private func codexCommand() -> (executableURL: URL, argumentsPrefix: [String]) {
        let candidates = [
            "/Users/aryanrogye/.nvm/versions/node/v20.17.0/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return (URL(fileURLWithPath: candidate), [])
        }
        
        return (URL(fileURLWithPath: "/usr/bin/env"), ["codex"])
    }
    
    private func codexEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let nodeBinDirectories = [
            "/Users/aryanrogye/.nvm/versions/node/v20.17.0/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin"
        ]
        
        let existingPath = environment["PATH"] ?? ""
        environment["PATH"] = (nodeBinDirectories + [existingPath])
            .filter { !$0.isEmpty }
            .joined(separator: ":")
        
        return environment
    }
}

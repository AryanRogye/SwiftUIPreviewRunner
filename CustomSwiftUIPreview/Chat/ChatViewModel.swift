//
//  ChatViewModel.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/2/26.
//

import Foundation
import MLXLMCommon
import MLXKit
import AppKit

public struct SendSwiftUIViewBodyArguments: Codable {
    public var text: String
    
    public init(text: String) {
        self.text = text
    }
}

@MainActor
@Observable
final class ChatViewModel {
    
    /**
     * All Messages
     */
    var messages: [any MessageRepresentable] = []
    
    /// Flag to know if we are currently sending a message or not
    var sendingMessage = false
    
    /// Error Related
    var error: String?
    var showError = false
    
    var lastInfo: GenerateCompletionInfo?
    
    /// Link Pattern lets us know if in a String what all of the urls are
    public static let linkPattern = #"\[([^\]]+)\]\((https?:\/\/[^\s\)]+)\)"#
    
    private var observationTask: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    private var swiftUIViewBodyWriter: ((String) -> Void)?
    private var swiftUIViewBodyReader: (() -> String)?
    private var activeToolCallCount = 0
    
    /**
     * Internal Service lets us talk to the MLX Model thats loaded
     */
    private let mlxChatService = MLXChatService()
    
    /**
     * Computed Property to know if the MLX model is
     * loaded or not
     */
    public var isLoaded: Bool {
        mlxChatService.isLoaded
    }
    
    public init() {}
    
    @MainActor
    deinit {
        if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
        if let foregroundObserver { NotificationCenter.default.removeObserver(foregroundObserver) }
    }
}

// MARK: - Editor Tools
extension ChatViewModel {
    /**
     * Gives the chat model one narrow capability:
     * replace the text inside the SwiftUI editor.
     *
     * This intentionally does not expose compile, shell, filesystem,
     * or process execution. The model can only propose source text.
     */
    public func setSwiftUIViewBodyAccess(
        reader: @escaping () -> String,
        writer: @escaping (String) -> Void
    ) {
        swiftUIViewBodyReader = reader
        swiftUIViewBodyWriter = writer
    }
}

// MARK: - Memory
extension ChatViewModel {
    public func setMemoryLimit(limitInMB: Int) {
        Task {
            /// queue if we're busy
            while sendingMessage {
                 /// 0.1 sec
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            
            self.setMLXModelMemory(limitInMB: limitInMB)
        }
    }
    
    internal func setMLXModelMemory(limitInMB: Int) {
        mlxChatService.setMLXMemory(limitInMB: limitInMB)
    }
}

// MARK: - Generation Info
extension ChatViewModel {
    
    var promptProcessingTime: TimeInterval? {
        guard let lastInfo else { return nil }
        return lastInfo.promptTime
    }
    
    var tokenGenerationTime: TimeInterval? {
        guard let lastInfo else { return nil }
        return lastInfo.generateTime
    }
    
    var generationStopReason: String? {
        guard let lastInfo else { return nil }
        return switch lastInfo.stopReason {
        case .stop:
            "Generation Stopped Because EOS/unknown stop token was encountered"
        case .length:
            "Generation stopped because the configured max token limit was reached"
        case .cancelled:
            "Generation stopped due to explicit task cancellation or early stream termination"
        }
    }
}

// MARK: - Loading Model
extension ChatViewModel {
    static let systemPrompt = """
                              You are the SwiftUI editor assistant inside CustomSwiftUIPreview.
                              
                              Your job is to help the user create or revise the SwiftUI source shown in the editor.
                              
                              Important rules:
                              - Write complete Swift source for the editor when the user asks for UI changes.
                              - Use the getCurrentSwiftUIViewBody tool when you need to inspect the current editor text before editing.
                              - Use the writeSwiftUIViewBody tool to update the editor text.
                              - Do not include Markdown code fences in tool arguments.
                              - Do not generate an @main App, Scene, WindowGroup, UIApplicationDelegate, or app lifecycle entrypoint.
                              - The preview host creates the app wrapper for you. The editor source should define a SwiftUI View, usually struct ContentView: View.
                              - Start with import SwiftUI unless the user's requested code clearly needs other available imports.
                              - Assume normal SwiftUI and project dependencies are available from the preview build environment.
                              - Do not ask to run shell commands, inspect files, compile, or execute code. You only have permission to read and write editor text.
                              - If the user asks for something unsafe or unrelated to SwiftUI source generation, answer in chat without using a tool.
                              
                              Good output shape for the editor:
                              
                              import SwiftUI
                              
                              struct ContentView: View {
                                  var body: some View {
                                      Text("Hello")
                                  }
                              }
                              """
    
    
    /**
     * Loads The Model based off the URL provided
     * sets error flags if anything goes wrong
     */
    public func load(_ url: URL) async {
        do {
            try await mlxChatService.loadModel(
                at: url,
                defaultPrompt: Self.systemPrompt
            )
            setupObserversIfNeeded()
        } catch {
            self.error = error.localizedDescription
            showError = true
        }
    }
}

// MARK: - Send Chat
extension ChatViewModel {
    
    /**
     * Function sends prompt to the loaded MLX Model
     */
    func send(_ prompt: String) {
        
        /// Make sure the model is loaded
        guard isLoaded else {
            error = "Model Not Loaded Yet"
            showError = true
            return
        }
        
        /// make sure we're not currently sending a message
        guard !sendingMessage else { return }
        
        /// Trim Prompt and making sure its not empty
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        /// set flag to true
        sendingMessage = true
        activeToolCallCount = 0
        
        /// Creates Users Message
        self.addUserMessage(trimmed)
        
        let assistantID = UUID()
        
        Task {
            /// at end set the false
            defer {
                Task { @MainActor in
                    if self.activeToolCallCount == 0 {
                        self.sendingMessage = false
                    }
                }
            }
            
            do {
                /**
                 * This removes the current assistant message you're about
                 * to stream into
                 */
                let modelMessages = messages
                    .filter { $0.id != assistantID }
                    .compactMap { $0 as? ChatMessage }
                    .filter { $0.role != .system } // Exclude debug messages
                    .map { ModelMessage(role: $0.role, content: $0.content, toolCalls: $0.toolCalls) }
                
                let _ = try await mlxChatService.getResponse(
                    messages: modelMessages,
                    tools: [
                        Self.getCurrentSwiftUIViewBodyTool,
                        Self.writeSwiftUIViewBodyTool
                    ],
                    completion: { [weak self] (snippet: String) in
                        guard let self else { return }
                        Task { @MainActor in
                            self.appendToAssistantMessage(
                                id: assistantID,
                                chunk: snippet
                            )
                        }
                    },
                    toolcallCompletionHandler: { toolcallResponse in
                        Task { @MainActor in
                            self.activeToolCallCount += 1
                            defer {
                                self.activeToolCallCount -= 1
                                if self.activeToolCallCount == 0 {
                                    self.sendingMessage = false
                                }
                            }
                            
                            do {
                                try await self.handleToolCall(toolcallResponse)
                            } catch {
                                self.error = error.localizedDescription
                                self.showError = true
                            }
                        }
                    },
                    infoCompletionHandler: { info in
                        Task { @MainActor in
                            self.lastInfo = info
                        }
                    }
                )
            } catch let e as MLXModelChatVideoModelError {
                await MainActor.run {
                    self.error = self.message(for: e)
                    self.showError = true
                    self.removeAssistantMessageIfEmpty(id: assistantID)
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    self.removeAssistantMessageIfEmpty(id: assistantID)
                }
            }
        }
    }
}

// MARK: - Tools
extension ChatViewModel {
    static let getCurrentSwiftUIViewBodyTool: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "getCurrentSwiftUIViewBody",
            "description": """
                            Read the current SwiftUI source text from the editor.
                            Use this before editing when the user refers to the existing view,
                            asks for a small change, or says things like current, this, it, or now.
                            """,
            "parameters": [
                "type": "object",
                "properties": [:] as [String: any Sendable],
                "required": []
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
    
    static let writeSwiftUIViewBodyTool: [String: any Sendable] = [
        "type": "function",
        "function": [
            "name": "writeSwiftUIViewBody",
            "description": """
                            Replace the SwiftUI editor contents with complete SwiftUI source code.
                            Use this when the user asks you to create, rewrite, or update the preview view.
                            Do not include Markdown fences. Return only valid Swift source text.
                            """,
            "parameters": [
                "type": "object",
                "properties": [
                    "text": [
                        "type": "string",
                        "description": """
                                       Complete Swift source for the preview editor. It should import SwiftUI
                                       and define one View struct, for example struct ContentView: View.
                                       """
                    ] as [String: any Sendable]
                ] as [String: any Sendable],
                "required": ["text"]
            ] as [String: any Sendable]
        ] as [String: any Sendable]
    ]
}

// MARK: - Handle Tool Calls
extension ChatViewModel {
    private func handleToolCall(
        _ response: ToolCallResponse,
        depth: Int = 0
    ) async throws {
        
        let maxDepth = 3
        
        guard depth < maxDepth else {
            return
        }
        
        let function = response.functionName
        
        /// Add the assistant's tool-call turn to the conversation history
        /// so the chat template sees: user → assistant(tool_call) → tool(result)
        let assistantToolCallMsg = ChatMessage(
            role: .assistant,
            content: "",
            toolCalls: response.rawToolCall.map { [$0] }
        )
        messages.append(assistantToolCallMsg)
        
        /// This is important because we need the id to send back the content
        /// once we get it
        let message = ToolMessage(
            functionName: response.functionName,
            arguments: response.arguments
        )
        
        messages.append(message)
        
        switch function {
        case "getCurrentSwiftUIViewBody":
            let result = getCurrentSwiftUIViewBody()
            updateToolCall(id: message.id, result: result)
            try await respondToToolResult(
                result,
                label: "current SwiftUI editor text",
                depth: depth
            )
        case "writeSwiftUIViewBody":
            let result = writeSwiftUIViewBody(arguments: response.arguments)
            updateToolCall(id: message.id, result: result)
        default:
            break
        }
    }
    
    private func respondToToolResult(
        _ response: String,
        label: String,
        depth: Int
    ) async throws {
        /// Add the tool result with proper "tool" role so the chat template
        /// sees the correct: assistant(tool_call) → tool(result) alternation.
        let toolResultMessage = ChatMessage(
            role: .tool,
            content: response
        )
        messages.append(toolResultMessage)
        
        let assistantID = UUID()
        
        let modelMessages = messages
            .filter { $0.id != assistantID }
            .compactMap { $0 as? ChatMessage }
            .filter { $0.role != .system } // Exclude debug messages
            .map { ModelMessage(role: $0.role, content: $0.content, toolCalls: $0.toolCalls) }
        
        let _ = try await mlxChatService.getResponse(
            messages: modelMessages,
            tools: [
                Self.getCurrentSwiftUIViewBodyTool,
                Self.writeSwiftUIViewBodyTool
            ],
            completion: { [weak self] (snippet: String) in
                guard let self else { return }
                Task { @MainActor in
                    self.appendToAssistantMessage(
                        id: assistantID,
                        chunk: snippet
                    )
                }
            },
            toolcallCompletionHandler: { toolcallResponse in
                Task { @MainActor in
                    self.activeToolCallCount += 1
                    defer {
                        self.activeToolCallCount -= 1
                        if self.activeToolCallCount == 0 {
                            self.sendingMessage = false
                        }
                    }
                    
                    do {
                        try await self.handleToolCall(toolcallResponse, depth: depth + 1)
                    } catch {
                        self.error = error.localizedDescription
                        self.showError = true
                    }
                }
            },
            infoCompletionHandler: { info in
                Task { @MainActor in
                    self.lastInfo = info
                }
            }
        )
    }
    
    private func getCurrentSwiftUIViewBody() -> String {
        guard let reader = swiftUIViewBodyReader else {
            return "Editor reader is not connected yet."
        }
        
        return reader()
    }
    
    private func writeSwiftUIViewBody(arguments: [String: JSONValue]) -> String {
        guard let writer = swiftUIViewBodyWriter else {
            return "Editor writer is not connected yet."
        }
        
        guard let text = arguments["text"]?.stringValue else {
            return "Missing required string argument: text."
        }
        
        writer(text)
        return "Updated the SwiftUI editor text."
    }
}

// MARK: - JSON Helpers
private extension JSONValue {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }
}

// MARK: - Observers
extension ChatViewModel {
    /**
     * Function sets up observed if their not already set
     */
    internal func setupObserversIfNeeded() {
        guard backgroundObserver == nil else { return }
        guard foregroundObserver == nil else { return }
        
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.mlxChatService.unload()
            }
        }
        
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                do {
                    try await self.mlxChatService.reload()
                } catch let e as MLXModelChatVideoModelError {
                    self.error = self.message(for: e)
                    self.showError = true
                } catch {
                    self.error = error.localizedDescription
                    self.showError = true
                }
            }
        }
    }

}

// MARK: - Helpers
extension ChatViewModel {
    /**
     * Function adds a message as a role user
     */
    private func addUserMessage(_ content: String) {
        let userMessage = ChatMessage(
            role: .user,
            content: content
        )
        messages.append(userMessage)
    }
    
    /**
     * Function Appends to assistant method if
     * the message doesnt exist yet, it creates it as we go
     * this is important
     */
    private func appendToAssistantMessage(id: UUID, chunk: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            let message = messages[index]
            if let m = message as? ChatMessage {
                m.content += chunk
                messages[index] = m
            }
        } else {
            messages.append(
                ChatMessage(
                    id: id,
                    role: .assistant,
                    content: chunk
                )
            )
        }
    }
    
    /**
     * Updates the tool call UI after it's triggered.
     *
     * Normally, a tool call just shows that it was invoked.
     * This allows us to:
     * 1. Display the initial tool call
     * 2. Wait for the async operation to complete
     * 3. Update the UI with the result afterward
     *
     * Makes the interaction feel smoother and more dynamic.
     */
    private func updateToolCall(id: UUID, result: String) {
        if let index = messages.firstIndex(where: { $0.id == id }) {
            if let toolCall = messages[index] as? ToolMessage {
                toolCall.result = result
                messages[index] = toolCall
                print("Updated Tool Call Result: \(result)")
            }
        }
    }
    
    /**
     * Removes Assistant Message If Empty
     */
    private func removeAssistantMessageIfEmpty(id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        if let m = message as? ChatMessage {
            if m.content.isEmpty {
                messages.remove(at: index)
            }
        }
    }

    /**
     * Function Handles Errors For Us
     */
    internal func message(for error: MLXModelChatVideoModelError) -> String {
        switch error {
        case .modelDoesntExist:
            return "Model Doesnt Exist"
        case .errorWhileLoadingContainer(let string):
            return "Error While Loading Container: \(string)"
        case .containerNotConfigured:
            return "Container Not Configured"
        case .cantGenerateResponseNotLoaded:
            return "Not Loaded Cant Generate Response"
        case .cantReload(let reason):
            return "Cant Reload: \(reason)"
        }
    }
}

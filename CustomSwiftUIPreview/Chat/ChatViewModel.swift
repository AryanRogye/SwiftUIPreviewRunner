//
//  ChatViewModel.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/2/26.
//

import Foundation

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
    var selectedModel: CodexModel = .gpt54Mini
    
    private var swiftUIViewBodyWriter: ((String) -> Void)?
    private var swiftUIViewBodyReader: (() -> String)?
    private let codexService = CodexService()
    
    public init() {}
}

// MARK: - Editor Access
extension ChatViewModel {
    /**
     * Gives Codex a narrow editor boundary.
     *
     * Codex returns replacement text, but this app decides when and how
     * the editor is actually updated.
     */
    public func setSwiftUIViewBodyAccess(
        reader: @escaping () -> String,
        writer: @escaping (String) -> Void
    ) {
        swiftUIViewBodyReader = reader
        swiftUIViewBodyWriter = writer
    }
}

// MARK: - Send Chat
extension ChatViewModel {
    
    /**
     * Function sends prompt to Codex.
     */
    func send(_ prompt: String) {
        /// make sure we're not currently sending a message
        guard !sendingMessage else { return }
        
        /// Trim Prompt and making sure its not empty
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        guard let currentSwiftSource = swiftUIViewBodyReader?() else {
            error = "Editor reader is not connected yet."
            showError = true
            return
        }
        
        /// set flag to true
        sendingMessage = true
        let conversationHistory = recentConversationHistory()
        
        /// Creates Users Message
        self.addUserMessage(trimmed)
        self.addSystemMessage("Using \(selectedModel.displayName)")
        
        Task {
            defer {
                Task { @MainActor in
                    self.sendingMessage = false
                }
            }
            
            do {
                let response = try await codexService.send(
                    prompt: trimmed,
                    currentSwiftSource: currentSwiftSource,
                    conversationHistory: conversationHistory,
                    model: selectedModel
                )
                
                await MainActor.run {
                    self.addAssistantMessage(response.message)
                    
                    if let swiftSource = response.swiftSource,
                       !swiftSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        self.swiftUIViewBodyWriter?(swiftSource)
                    }
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.showError = true
                    self.addAssistantMessage(error.localizedDescription)
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
    
    private func addAssistantMessage(_ content: String) {
        messages.append(
            ChatMessage(
                role: .assistant,
                content: content
            )
        )
    }
    
    private func addSystemMessage(_ content: String) {
        messages.append(
            ChatMessage(
                role: .system,
                content: content
            )
        )
    }
    
    private func recentConversationHistory(limit: Int = 12) -> [CodexConversationMessage] {
        messages
            .compactMap { $0 as? ChatMessage }
            .filter { $0.role == .user || $0.role == .assistant }
            .suffix(limit)
            .map { message in
                CodexConversationMessage(
                    role: message.role,
                    content: message.content
                )
            }
    }
}

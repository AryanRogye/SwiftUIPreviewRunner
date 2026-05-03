//
//  MessageRepresentable.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import Foundation

public protocol MessageRepresentable: Identifiable, Equatable {
    var id: UUID { get set }
}

@Observable
public class ToolMessage: MessageRepresentable, Sendable {
    public var id: UUID
    public let functionName: String
    public let arguments : [String: String]
    
    /// Result for ToolCall
    public var result: String?
    
    public static func == (lhs: ToolMessage, rhs: ToolMessage) -> Bool {
        lhs.id == rhs.id
    }
    
    public init(functionName: String) {
        self.id = UUID()
        self.functionName = functionName
        self.arguments = [:]
    }
    
    public init(id: UUID = UUID(), functionName: String, arguments: [String : String]) {
        self.id = id
        self.functionName = functionName
        self.arguments = arguments
    }
}

public enum Role: String, Equatable, Sendable {
    case user
    case assistant
    case system
}

@Observable
public class ChatMessage: MessageRepresentable, Sendable {
    
    public var id: UUID
    public let role: Role
    public var content: String
    
    public init(
        id: UUID = UUID(),
        role: Role,
        content: String
    ) {
        self.id = id
        self.role = role
        self.content = content
    }
    
    public static func == (lhs: ChatMessage, rhs: ChatMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.role == rhs.role &&
        lhs.content == rhs.content
    }
}

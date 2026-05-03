//
//  CodexModel.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/2/26.
//

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

struct CodexConversationMessage: Sendable {
    let role: Role
    let content: String
}

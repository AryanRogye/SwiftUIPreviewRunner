//
//  ChatListView.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI

struct ChatListView: View {
    
    @Bindable var chatVM: ChatViewModel
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(chatVM.messages, id: \.id) { message in
                    if let m = message as? ChatMessage {
                        ChatBubbleRow(message: m)
                    }
            if let t = message as? ToolMessage {
                ToolMessageRow(message: t)
            }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
        }
    }
}

private struct ToolMessageRow: View {
    
    let message: ToolMessage
    
    var body: some View {
        DisclosureGroup {
            ForEach(Array(message.arguments.keys.sorted()), id: \.self) { key in
                if let value = message.arguments[key] {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(key)
                            .font(.headline)
                        Text(value)
                            .textSelection(.enabled)
                    }
                }
            }
            if let result = message.result {
                VStack {
                    Text("Result:")
                    Text(result)
                }
            }
        } label: {
            HStack {
                if message.result == nil {
                    ProgressView()
                        .controlSize(.small)
                }
                
                Text(message.result == nil ? "Using \(message.functionName)" : "Used \(message.functionName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background {
                        Capsule()
                            .fill(.thinMaterial)
                    }
                
                Spacer(minLength: 48)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ChatBubbleRow: View {
    
    private struct ChatExtractedLink: Identifiable, Hashable {
        let id = UUID()
        let title: String
        let url: URL
        
        public static func extractMarkdownLinks(from text: String) -> [Self] {
            let pattern = #"\[([^\]]+)\]\((https?:\/\/[^\s\)]+)\)"#
            
            guard let regex = try? NSRegularExpression(pattern: pattern) else {
                return []
            }
            
            let nsText = text as NSString
            let matches = regex.matches(
                in: text,
                range: NSRange(location: 0, length: nsText.length)
            )
            
            return matches.compactMap { match in
                guard match.numberOfRanges >= 3 else { return nil }
                
                let title = nsText.substring(with: match.range(at: 1))
                let urlString = nsText.substring(with: match.range(at: 2))
                
                guard let url = URL(string: urlString) else {
                    return nil
                }
                
                return ChatExtractedLink(title: title, url: url)
            }
        }
    }
    
    let message: ChatMessage
    
    private var isUser: Bool {
        message.role == .user
    }
    
    private var isSystem: Bool {
        message.role == .system
    }
    
    private var extractedLinks: [ChatExtractedLink] {
        ChatExtractedLink.extractMarkdownLinks(from: message.content)
    }
    
    @State var showLinks = false
    
    var body: some View {
        VStack {
            HStack {
                if isUser {
                    Spacer(minLength: 48)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    if isSystem {
                        Text("System")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    
                    Text(message.content)
                        .font(.body)
                        .foregroundStyle(textColor)
                        .textSelection(.enabled)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(bubbleBackground)
                        }
                }
                .frame(
                    maxWidth: 300,
                    alignment: isUser ? .trailing : .leading
                )
                
                if !isUser {
                    Spacer(minLength: 48)
                }
            }
            
            if !extractedLinks.isEmpty {
                /// Click Button Show Multiple Popup To Open it
                Button {
                    showLinks = true
                } label: {
                    Image(systemName: "link")
                }
                .popover(isPresented: $showLinks) {
                    ForEach(extractedLinks, id: \.self) { link in
                        Button(link.title) { NSWorkspace.shared.open(link.url) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
    
    private var bubbleBackground: some ShapeStyle {
        if isSystem {
            return AnyShapeStyle(.thinMaterial)
        } else if isUser {
            return AnyShapeStyle(Color(hex: "#FF1395")!)
        } else {
#if os(iOS)
            return AnyShapeStyle(Color(.secondarySystemBackground))
#elseif os(macOS)
            return AnyShapeStyle(Color(nsColor: NSColor.secondaryLabelColor))
#endif
        }
    }
    
    private var textColor: Color {
        if isUser {
            return .white
        } else {
            return .primary
        }
    }
}

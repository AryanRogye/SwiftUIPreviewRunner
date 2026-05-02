//
//  ChatInputBar.swift
//  ComfyPilotUI
//
//  Created by Aryan Rogye on 4/25/26.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

public struct ChatInputBar: View {
    
    @Binding var sendingMessage : Bool
    var onTextSend: (String) -> Void
    
    @State private var text: String = ""
    @State private var isFocused = false
    
    public init(
        sendingMessage: Binding<Bool>,
        onTextSend: @escaping (String) -> Void
    ) {
        self._sendingMessage = sendingMessage
        self.onTextSend = onTextSend
    }
    
    var horizontalPadding: CGFloat {
#if os(iOS)
        isFocused ? 18 : 16
#else
        16
#endif
    }
    
    var bottomPadding: CGFloat {
#if os(iOS)
        isFocused ? 20 : 0
#else
        20
#endif
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 10) {
            plusButton
            
            textfield
                .overlay(alignment: .trailing) {
                    VStack(alignment: .center) {
                        HStack(spacing: 2) {
                            micButton
                            
                            talkToModelButton
                        }
                        .padding(.trailing, 8)
                        .padding(.bottom, 4)
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
        .animation(.bouncy, value: isFocused)
    }
    
    // MARK: - Plus Button
    private var plusButton: some View {
        Button {
            
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22))
                .frame(width: 20, height: 30)
                .contentShape(Circle())
                .padding(10)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Textfield
    private var textfield: some View {
        CustomTextView(
            text: $text,
            isFocused: $isFocused,
            onSubmit: submitText
        )
        .padding(.leading, 14)
        .padding(.trailing, 90)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial.opacity(0.2))
                .glassEffect(
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )
        }
    }
    
    // MARK: - Mic Button
    private var micButton: some View {
        Button { } label: {
            Image(systemName: "mic")
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 50, height: 50)
    }
    
    // MARK: - Talk To Model Button
    private var talkToModelButton: some View {
        Button {
            submitText()
        } label: {
            TalkToModelButton(
                showArrow: Binding(
                    get: { !text.isEmpty },
                    set: { _ in }
                )
            )
        }
        .buttonStyle(.plain)
        .frame(width: 50, height: 50)
    }
    
    private func submitText() {
        if !text.isEmpty {
            /// Send Button
            onTextSend(text)
            text = ""
        } else {
            /// Voice Button
        }
    }
}


private struct TalkToModelButton: View {
    
    let spacing : CGFloat = 2
    let width: CGFloat = 3
    @Binding var showArrow: Bool
    @Namespace var nm
    
    var body: some View {
        Circle()
            .fill(Color(hex: "#FF1395")!)
            .overlay {
                if showArrow {
                    Image(systemName: "arrow.up")
                        .fontWeight(.bold)
                        .matchedGeometryEffect(
                            id: "arrow_moving_text_size",
                            in: nm
                        )
                        .rotationEffect(
                            showArrow ? .zero : .degrees(90)
                        )
                        .shadow(
                            color: .white.opacity(0.8),
                            radius: 1
                        )
                } else {
                    HStack(spacing: spacing) {
                        Rectangle(verticalPadding: 14)
                        Rectangle(verticalPadding: 10)
                        Rectangle(verticalPadding: 12)
                        Rectangle(verticalPadding: 14)
                    }
                    .matchedGeometryEffect(
                        id: "arrow_moving_text_size",
                        in: nm
                    )
                }
            }
            .padding(10)
            .animation(.bouncy(duration: 0.5, extraBounce: 0.3), value: showArrow)
    }
    
    private func Rectangle(verticalPadding: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .frame(width: width)
            .foregroundStyle(.white)
            .padding(.vertical, verticalPadding)
    }
}


#Preview {
    ChatInputBar(sendingMessage: .constant(false)) { text in
        
    }
}

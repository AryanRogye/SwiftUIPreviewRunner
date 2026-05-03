//
//  ContentView.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/1/26.
//

import SwiftUI
import TextEditor
import AppKit

struct ContentView: View {
    
    @AppStorage("showChatSidebar") private var showChatSidebar = true
    @State private var chatVM = ChatViewModel()
    @State private var vm = ViewModel()
    @State private var editorID = UUID()
    
    var body: some View {
        VStack {
            HSplitView {
                if showChatSidebar {
                    ChatSidebar(vm: chatVM)
                        .frame(minWidth: 280)
                }
                
                ComfyTextEditor(
                    text: $vm.text,
                    magnification: $vm.magnification,
                    allowEdit: $vm.allowEdit,
                    isInVimMode: $vm.vimEnabled
                )
                .id(editorID)
                
                VSplitView {
                    PreviewHostView(previewView: vm.previewView)
                        .frame(minWidth: 360, minHeight: 320)
                    
                    List {
                        ForEach(Array(vm.logs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(minHeight: 160)
                }
                .frame(minWidth: 420)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showChatSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                }
                .help(showChatSidebar ? "Hide Chat" : "Show Chat")
                
                if showChatSidebar {
                    Picker("Codex Model", selection: $chatVM.selectedModel) {
                        ForEach(CodexModel.allCases) { model in
                            Text(model.displayName).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .disabled(chatVM.sendingMessage)
                }
                
                Button(vm.allowEdit ? "Disable Edit" : "Allow Edit") { vm.allowEdit.toggle() }
                Button(vm.vimEnabled ? "Disable Vim" : "Enable Vim") { vm.vimEnabled.toggle() }
                Button { vm.compile() } label: {
                    Image(systemName: vm.isCompiling ? "hourglass" : "play.fill")
                }
                .disabled(vm.isCompiling)
            }
        }
        .task {
            chatVM.setSwiftUIViewBodyAccess(
                reader: { vm.text },
                writer: { text in
                    vm.text = text
                    editorID = UUID()
                }
            )
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}

//
//  ContentView.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/1/26.
//

import SwiftUI
import TextEditor
import AppKit
import MLXKit

struct ContentView: View {
    
    @State private var chatVM = ChatViewModel()
    @State private var loaderService = ModelLoaderService()
    @State private var sendingMessage = false
    @State private var loading = false
    @State private var vm = ViewModel()
    
    var body: some View {
        VStack {
            HSplitView {
                ChatSidebar(vm: chatVM, sendingMessage: $sendingMessage)
                
                ComfyTextEditor(
                    text: $vm.text,
                    magnification: $vm.magnification,
                    allowEdit: $vm.allowEdit,
                    isInVimMode: $vm.vimEnabled
                )
                
                VSplitView {
                    PreviewHostView(previewView: vm.previewView)
                        .frame(minWidth: 360, minHeight: 320)
                    
                    List {
                        ForEach(vm.logs, id: \.self) { log in
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
                NavigationLink(destination: ModelsInfoView(loaderService: loaderService)) { Image(systemName: "arrow.down.circle") }
                Button(vm.allowEdit ? "Disable Edit" : "Allow Edit") { vm.allowEdit.toggle() }
                Button(vm.vimEnabled ? "Disable Vim" : "Enable Vim") { vm.vimEnabled.toggle() }
                Button { vm.compile() } label: {
                    Image(systemName: vm.isCompiling ? "hourglass" : "play.fill")
                }
                .disabled(vm.isCompiling)
            }
        }
        .task {
            if let selected = loaderService.selected {
                loadModel(model: selected)
            }
        }
        .onChange(of: loaderService.selected) { _, newValue in
            if let newValue {
                loadModel(model: newValue)
            }
        }
    }
    
    /**
     * Helper to load model once a model is selected
     */
    private func loadModel(model: MLXChatModel) {
        if loading { return }
        
        Task {
            loading = true
            defer { loading = false }
            
            await chatVM.load(model.url)
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}

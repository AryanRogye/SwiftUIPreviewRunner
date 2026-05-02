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
    
    @State private var vm = ViewModel()
    
    var body: some View {
        VStack {
            HSplitView {
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
                Button(vm.allowEdit ? "Disable Edit" : "Allow Edit") { vm.allowEdit.toggle() }
                Button(vm.vimEnabled ? "Disable Vim" : "Enable Vim") { vm.vimEnabled.toggle() }
                Button { vm.compile() } label: { Image(systemName: "play.fill") }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}

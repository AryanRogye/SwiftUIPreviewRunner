//
//  ContentView.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/1/26.
//

import SwiftUI
import TextEditor

struct ContentView: View {
    
    @State private var vm = ViewModel()
    
    var body: some View {
        VStack {
            Button("Compile") { vm.compile() }
            HSplitView {
                ComfyTextEditor(
                    text: $vm.text,
                    magnification: $vm.magnification,
                    allowEdit: $vm.allowEdit,
                    isInVimMode: $vm.vimEnabled
                )
                List {
                    ForEach(vm.logs, id: \.self) { log in
                        Text(log)
                            .textSelection(.enabled)
                    }
                }
                .frame(minWidth: 250, maxWidth: 250)
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
            }
        }
    }
}

#Preview {
    NavigationStack {
        ContentView()
    }
}

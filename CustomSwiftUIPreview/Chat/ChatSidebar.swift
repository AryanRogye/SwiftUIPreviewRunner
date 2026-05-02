//
//  ChatSidebar.swift
//  AgenticDebugging
//
//  Created by Aryan Rogye on 4/29/26.
//

import SwiftUI

struct ChatSidebar: View {
    
    @Bindable var vm: ChatViewModel
    
    var body: some View {
        VStack {
            ChatListView(chatVM: vm)
                .safeAreaInset(edge: .bottom) {
                    ChatInputBar(
                        sendingMessage: Binding(
                            get: { vm.sendingMessage },
                            set: { vm.sendingMessage = $0 }
                        )
                    ) { text in
                        vm.send(text)
                    }
                }
        }
        .frame(minWidth: 320)
    }
}

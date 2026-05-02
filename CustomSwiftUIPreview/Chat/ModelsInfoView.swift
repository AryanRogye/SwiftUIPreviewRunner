//
//  ModelsInfoScreen.swift
//  ComfyPilot
//
//  Created by Aryan Rogye on 4/24/26.
//

import SwiftUI
import MLXKit

struct ModelsInfoView: View {
    
    @Bindable var loaderService: ModelLoaderService
    @State private var modelName = ""
    
    var body: some View {
        @Bindable var loaderService = loaderService
        
        VStack(spacing: 0) {
            downloadHeader
            
            if loaderService.showContinueAlert {
                continueDownloadBanner
                    .padding(.horizontal)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            
            if loaderService.isDownloading && !loaderService.showContinueAlert {
                downloadProgress
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }
            
            Divider()
            
            if loaderService.models.isEmpty {
                ContentUnavailableView(
                    "No Models",
                    systemImage: "square.stack.3d.up.slash",
                    description: Text("Downloaded models will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(loaderService.models) { model in
                    modelRow(model)
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Models")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    loaderService.openModelFolder()
                } label: {
                    Image(systemName: "folder")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    loaderService.sync()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(loaderService.isDownloading)
            }
        }
        .alert("Error", isPresented: $loaderService.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(loaderService.error ?? "Unknown error")
        }
        .animation(.bouncy, value: loaderService.showContinueAlert)
        .animation(.bouncy, value: loaderService.isDownloading)
    }
}

private extension ModelsInfoView {
    var downloadHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Download Model")
                .font(.headline)
            
            HStack(spacing: 10) {
                TextField("Download a Model", text: $modelName)
                    .textFieldStyle(.roundedBorder)
                    .disabled(loaderService.isDownloading)
                    .onSubmit(downloadModel)
                
                Button(action: downloadModel) {
                    Label("Download", systemImage: "arrow.down.circle.fill")
                }
                .disabled(modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || loaderService.isDownloading)
            }
        }
        .padding()
    }
    
    var continueDownloadBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("\(loaderService.pendingFiles.count) files found", systemImage: "doc.on.doc")
                    .font(.headline)
                
                Spacer()
            }
            
            HStack {
                Button("Cancel", role: .cancel) {
                    loaderService.userCancelledDownload()
                }
                
                Spacer()
                
                Button {
                    loaderService.userConfirmedDownload()
                } label: {
                    Label("Continue", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
    
    var downloadProgress: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: loaderService.progress)
            
            ProgressView(value: loaderService.currentFileProgress) {
                Text(loaderService.status.isEmpty ? "Downloading..." : loaderService.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    func modelRow(_ model: MLXChatModel) -> some View {
        Button {
            loaderService.select(model)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: loaderService.selected?.id == model.id ? "checkmark.circle.fill" : "cpu")
                    .foregroundStyle(loaderService.selected?.id == model.id ? Color.accentColor : Color.secondary)
                    .frame(width: 22)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.headline)
                    
                    Text(model.url.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(loaderService.isDownloading)
    }
    
    func downloadModel() {
        let normalizedName = normalizedModelName(from: modelName)
        guard !normalizedName.isEmpty else { return }
        
        Task {
            await loaderService.download(named: normalizedName)
            if !loaderService.showError {
                modelName = ""
            }
        }
    }
    
    func normalizedModelName(from input: String) -> String {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let url = URL(string: value), url.host == "huggingface.co" {
            let pathParts = url.pathComponents.filter { $0 != "/" }
            if pathParts.count >= 2, pathParts[0] == "mlx-community" {
                value = pathParts[1]
            }
        }
        
        if value.hasPrefix("mlx-community/") {
            value.removeFirst("mlx-community/".count)
        }
        
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines))
    }
}

//
//  ViewModel.swift
//  CustomSwiftUIPreview
//
//  Created by Aryan Rogye on 5/1/26.
//

import Foundation
import AppKit

@Observable
@MainActor
class ViewModel {
    var text: String = """
        import SwiftUI 
        
        struct ContentView: View {
            var body: some View {
                VStack {
                    Image(systemName: "globe")
                        .imageScale(.large)
                        .foregroundStyle(.tint)
                    Text("Hello, world!")
                }
                .padding()
            }
        }
        """
    var magnification: CGFloat = 1.0
    var allowEdit = true
    var vimEnabled = true
    
    let ViewBodyNamePattern = /struct\s+(\w+):/
    
    var logs: [String] = []
    
    
    public func compile() {
        guard let ViewBodyName = getViewBodyName() else { return }
        logs.append("Compiling View Body: \(ViewBodyName)")
        let mainAppStructure = getMainAppStructure(ViewBodyName)
        logs.append("Created Main App Structure: \n\(mainAppStructure)")
        let packageDotSwiftStructure = getPackageDotSwiftFile("PreviewApp")
        
        /// Now We Can Make 2 Files
        let ViewFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ViewBodyName).swift")
        logs.append("Created View File: \(ViewFile.path)")
        
        let AppFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(ViewBodyName)App.swift")
        logs.append("Created App File: \(AppFile.path)")
        
        let PackageSwiftFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("Package.swift")
        logs.append("Created Package.swift")
        
    
        /// Write To the files
        
        /// Create Package.swift file
        do {
            try write(to: PackageSwiftFile, content: packageDotSwiftStructure)
            logs.append("Wrote Package Swift File")
        } catch {
            logs.append("Error Writing To Package.swift File")
            return
        }
        
        /// Create View File
        do {
            try write(to: ViewFile, content: text)
            logs.append("Wrote To View File")
        } catch {
            logs.append("Error Writing To View File")
            return
        }
        
        /// Create App File
        do {
            try write(to: AppFile, content: mainAppStructure)
            logs.append("Wrote To Main App File")
        } catch {
            logs.append("Error Writing To Main App File")
            return
        }
        
        /// Create A Temporary Directory
        let name = "PreviewApp-\(UUID())"
        let swiftUIPreviewFolder = createTempFolder(named: name)
        
        do {
            try FileManager.default.moveItem(at: PackageSwiftFile, to: swiftUIPreviewFolder.appendingPathComponent("Package.swift"))
            logs.append("Moved Package.swift Into Preview Folder")
        } catch {
            logs.append("Error Moving Package.swift into Preview Folder")
            return
        }
        
        let sourcesFolder: URL
        do {
            sourcesFolder = try self.createFolder(named: "Sources", inside: swiftUIPreviewFolder)
        } catch {
            logs.append("Error Creating Sources Folder")
            return
        }
        
        let previewAppFolder: URL
        do {
            previewAppFolder = try self.createFolder(named: "PreviewApp", inside: sourcesFolder)
        } catch {
            logs.append("Error Creating Preview App Folder")
            return
        }
        
        
        /// Move ViewFile and AppFile into Folder
        do {
            try FileManager.default.moveItem(at: ViewFile, to: previewAppFolder.appendingPathComponent("\(ViewBodyName).swift"))
            logs.append("Moved View File Into Preview App Folder")
        } catch {
            logs.append("Error Moving File Into Preview FOlder")
            return
        }
        
        do {
            try FileManager.default.moveItem(at: AppFile, to: previewAppFolder.appendingPathComponent("\(ViewBodyName)App.swift"))
            logs.append("Moved Main App Structure File Into Preview App Folder")
        } catch {
            logs.append("Error Moving Main App Structure Into Preview FOlder")
            return
        }
        
        NSWorkspace.shared.open(swiftUIPreviewFolder.appendingPathComponent("Package.swift"))
    }
}

extension ViewModel {
    /// Function Extracts the view body name
    /// lets say for example we have:
    ///
    /// struct ContentView: View {
    ///    var body: some View {
    ///        VStack {
    ///            Image(systemName: "globe")
    ///                .imageScale(.large)
    ///                .foregroundStyle(.tint)
    ///            Text("Hello, world!")
    ///        }
    ///        .padding()
    ///    }
    /// }
    ///
    /// This Will Return Back: ContentView
    public func getViewBodyName() -> String? {
        if let match = text.firstMatch(of: ViewBodyNamePattern) {
            return String(match.1)
        }
        return nil
    }
    
    /// Function returns a string which represents
    /// a swiftui lifecycle
    public func getMainAppStructure(_ ViewBodyName: String) -> String {
        return """
        import SwiftUI 
        
        @main
        struct CustomSwiftUIPreviewApp: App {
            var body: some Scene {
                WindowGroup {
                    \(ViewBodyName)()
                }
            }
        }
        """
    }
    
    /// Function Generates a Package.swift string
    /// it uses a name that was given for the package name
    public func getPackageDotSwiftFile(_ PackageName: String) -> String {
        return """
        // swift-tools-version: 6.2
        // The swift-tools-version declares the minimum version of Swift required to build this package.
        
        import PackageDescription
        
        let package = Package(
            name: "\(PackageName)",
            platforms: [
                .macOS(.v15)
            ],
            products: [
                .executable(
                    name: "\(PackageName)",
                    targets: ["\(PackageName)"]
                ),
            ],
            targets: [
                .executableTarget(
                    name: "\(PackageName)"
                ),
            ]
        )
        """
    }
}

extension ViewModel {
    private func createFolder(named name: String, inside parent: URL) throws -> URL {
        let folderURL = parent.appendingPathComponent(name)
        
        try FileManager.default.createDirectory(
            at: folderURL,
            withIntermediateDirectories: true
        )
        return folderURL
    }
    
    private func createTempFolder(named name: String) -> URL {
        let url = FileManager
            .default
            .temporaryDirectory
            .appendingPathComponent(name)
        
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
        } catch {
            print("Failed to create temp folder:", error)
        }
        
        return url
    }
    
    /// Function Writes to file
    private func write(to file: URL, content: String) throws {
        try content.write(to: file, atomically: true, encoding: .utf8)
    }
}

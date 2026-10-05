import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var imgFileHandler = IMGFileHandler()
    
    @State private var isFileSelectorOpen = false
    @State private var isDirSelectorOpen = false
    
    @State private var archive: IMGArchive?
    @State private var selectedEntry: IMGEntry.ID?
    
    var body: some View {
        Group {
            if let archive {
                VStack(alignment: .leading) {
                    Table(archive.entries, selection: $selectedEntry) {
                        TableColumn("Name", value: \.name)
                        
                        TableColumn("Offset") { entry in
                            Text(String(entry.sectorOffset))
                        }
                        
                        TableColumn("Size") { entry in
                            Text("\(entry.sectorCount) sectors")
                        }
                    }
                    .onChange(of: selectedEntry) { _, newID in
                        guard let newID, let entry =
                                archive.entries.first(where: { $0.id == newID }) else {
                            return
                        }
                    }
                }
            }
            else {
                VStack(alignment: .center, spacing: 4) {
                    Text("Ryder").font(.headline)
                    Text("Open an IMG file to start").font(.headline)
                    
                    HStack(spacing: 4) {
                        Text("Press")
                        
                        Text("⌘O")
                            .font(.system(.caption, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        
                        Text("to open")
                    }
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                }
            }
        }
        .fileImporter(
            isPresented: $isFileSelectorOpen,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }
                
                do {
                    let handleResult = try imgFileHandler.handleSelectFile(url)
                    
                    switch handleResult {
                    case .needsDIR:
                        isDirSelectorOpen = true
                        isFileSelectorOpen = false
                    case .version1(let dirURL):
                        break
                    case .version2(let openedArchive):
                        archive = openedArchive
                    }
                }
                catch {
                    print("Error handling ")
                }
            case .failure(let error):
                print("There was an error opening the file: ", error)
            }
        }
        .fileImporter(
            isPresented: $isDirSelectorOpen,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            
        }
        .focusedSceneValue(\.openIMG) {
            isFileSelectorOpen = true
        }
    }
}

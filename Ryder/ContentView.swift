import SwiftUI
import UniformTypeIdentifiers
import SceneKit

struct ContentView: View {
    @StateObject private var imgFileHandler = IMGFileHandler()
    
    @State private var isFileSelectorOpen = false
    @State private var isDirSelectorOpen = false
    @State private var isTXDSelectorOpen = false
    @State private var searchText = ""
    
    @State private var archive: IMGArchive?
    @State private var selectedEntry: IMGEntry.ID?
    @State private var previewScene: SCNScene?
    @State private var previewMessage = "Select a .dff file to preview"
    @State private var textureDictionary: RWTextureDictionary?
    @State private var textureDictionaryName: String?
    @State private var currentDFFEntry: IMGEntry?
    
    var body: some View {
        Group {
            if let archive {
                HSplitView {
                    Table(filteredEntries(in: archive), selection: $selectedEntry) {
                        TableColumn("Name", value: \.name)
                        
                        TableColumn("Offset") { entry in
                            Text(String(entry.sectorOffset))
                        }
                        
                        TableColumn("Size") { entry in
                            Text("\(entry.sectorCount) sectors")
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search IMG entries")
                    .onChange(of: selectedEntry) { _, newID in
                        guard let newID, let entry =
                                archive.entries.first(where: { $0.id == newID }) else {
                            return
                        }

                        openPreview(for: entry, in: archive)
                    }
                    .frame(minWidth: 320, idealWidth: 440, maxWidth: 520)

                    VStack(spacing: 0) {
                        HStack {
                            Text(currentDFFEntry?.name ?? "No DFF selected")
                                .lineLimit(1)

                            Spacer()

                            Text(textureDictionaryName.map { "TXD: \($0)" } ?? "No TXD loaded")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button("Open TXD...") {
                                isTXDSelectorOpen = true
                            }
                            .buttonStyle(.borderless)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .frame(height: 32)

                        Divider()

                        Group {
                            if let previewScene {
                                DFFPreview(scene: previewScene)
                            } else {
                                ContentUnavailableView(
                                    "DFF Preview",
                                    systemImage: "cube.transparent",
                                    description: Text(previewMessage)
                                )
                            }
                        }
                    }
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
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
                        print("DIR support is not implemented yet: ", dirURL.path)
                    case .version2(let openedArchive):
                        archive = openedArchive
                        selectedEntry = nil
                        previewScene = nil
                        previewMessage = "Select a .dff file to preview"
                        textureDictionary = nil
                        textureDictionaryName = nil
                        currentDFFEntry = nil
                        searchText = ""
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
        .fileImporter(
            isPresented: $isTXDSelectorOpen,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    return
                }

                do {
                    try openExternalTXD(url)
                } catch {
                    previewScene = nil
                    previewMessage = error.localizedDescription
                }
            case .failure(let error):
                previewScene = nil
                previewMessage = error.localizedDescription
            }
        }
        .focusedSceneValue(\.openIMG) {
            isFileSelectorOpen = true
        }
    }

    private func openPreview(for entry: IMGEntry, in archive: IMGArchive) {
        switch entry.name.lowercased() {
        case let name where name.hasSuffix(".dff"):
            openDFF(entry, in: archive)
        case let name where name.hasSuffix(".txd"):
            openTXD(entry, in: archive)
        default:
            previewScene = nil
            previewMessage = "\(entry.name) is not a DFF model or TXD texture dictionary"
        }
    }

    private func openDFF(
        _ entry: IMGEntry,
        in archive: IMGArchive,
        resolveTextureDictionary: Bool = true
    ) {
        currentDFFEntry = entry

        do {
            if resolveTextureDictionary {
                if let matchingTXD = matchingTXD(for: entry, in: archive) {
                    if matchingTXD.name != textureDictionaryName {
                        try loadTXD(matchingTXD, in: archive)
                    }
                } else {
                    textureDictionary = nil
                    textureDictionaryName = nil
                }
            }

            let data = try imgFileHandler.data(for: entry, in: archive)
            let model = try RWModelLoader().loadDFFData(
                data,
                textureDictionary: textureDictionary
            )
            previewScene = DFFSceneBuilder.scene(containing: model)
            previewMessage = ""
        } catch {
            previewScene = nil
            previewMessage = error.localizedDescription
        }
    }

    private func openTXD(_ entry: IMGEntry, in archive: IMGArchive) {
        do {
            try loadTXD(entry, in: archive)

            if let currentDFFEntry {
                openDFF(
                    currentDFFEntry,
                    in: archive,
                    resolveTextureDictionary: false
                )
            } else {
                previewMessage = "Loaded \(textureDictionary?.textureCount ?? 0) textures from \(entry.name)"
            }
        } catch {
            previewScene = nil
            previewMessage = error.localizedDescription
        }
    }

    private func loadTXD(_ entry: IMGEntry, in archive: IMGArchive) throws {
        let data = try imgFileHandler.data(for: entry, in: archive)
        textureDictionary = try RWModelLoader().loadTXDData(data)
        textureDictionaryName = entry.name
    }

    private func openExternalTXD(_ url: URL) throws {
        guard url.pathExtension.caseInsensitiveCompare("txd") == .orderedSame else {
            throw IMGOpenError.invalidTXDFileExtension
        }

        let hasAccess = url.startAccessingSecurityScopedResource()

        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data = try Data(contentsOf: url)
        textureDictionary = try RWModelLoader().loadTXDData(data)
        textureDictionaryName = url.lastPathComponent

        if let archive, let currentDFFEntry {
            openDFF(
                currentDFFEntry,
                in: archive,
                resolveTextureDictionary: false
            )
        }
    }

    private func matchingTXD(for entry: IMGEntry, in archive: IMGArchive) -> IMGEntry? {
        let baseName = URL(fileURLWithPath: entry.name)
            .deletingPathExtension()
            .lastPathComponent

        return archive.entries.first {
            $0.name.caseInsensitiveCompare("\(baseName).txd") == .orderedSame
        }
    }

    private func filteredEntries(in archive: IMGArchive) -> [IMGEntry] {
        guard !searchText.isEmpty else {
            return archive.entries
        }

        return archive.entries.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

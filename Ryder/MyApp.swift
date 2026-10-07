import SwiftUI

@main struct MyApp: App {
    @FocusedValue(\.openIMG) private var openIMG
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 1_200, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open .img file...") {
                    openIMG?()
                }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(openIMG == nil)
            }
        }
    }
}

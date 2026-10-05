import SwiftUI

@main struct MyApp: App {
    @FocusedValue(\.openIMG) private var openIMG
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
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

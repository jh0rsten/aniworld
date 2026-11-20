import SwiftUI

@main
struct AniworldApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: "https://aniworld.to")!)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

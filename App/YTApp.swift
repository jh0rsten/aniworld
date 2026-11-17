import SwiftUI

@main
struct YTApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: "https://aniworld.to")!)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

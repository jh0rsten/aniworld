import SwiftUI

@main
struct YTApp: App {
    var body: some Scene {
        WindowGroup {
            WebView(url: URL(string: "https://m.youtube.com")!)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

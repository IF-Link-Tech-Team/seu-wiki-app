import SwiftUI

@main
struct SEUWikiApp: App {
    @State private var profile = UserProfile()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(profile)
        }
    }
}

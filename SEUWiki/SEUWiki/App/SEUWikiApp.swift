import SwiftUI

@main
struct SEUWikiApp: App {
    @State private var profile = UserProfile()
    @State private var feedStore = FeedStore()

    init() {
        #if DEBUG
        ProfileStorage.runPersistenceSelfTest()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(profile)
                .environment(feedStore)
        }
    }
}

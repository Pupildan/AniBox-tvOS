import SwiftUI

@main
struct AniBoxApp: App {
    @StateObject private var session = Session.shared
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if session.isLoggedIn {
                    RootView()
                } else {
                    LoginView()
                }
            }
            .environmentObject(session)
            .environmentObject(settings)
            .preferredColorScheme(.dark)
        }
    }
}

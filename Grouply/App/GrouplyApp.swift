import SwiftUI

@main
struct GrouplyApp: App {
  @State private var store = DemoStore(
    persist: !ProcessInfo.processInfo.arguments.contains("--uitesting"))
  var body: some Scene {
    WindowGroup {
      RootView().environment(store).tint(GLTheme.ink)
        .preferredColorScheme(.light)
    }
  }
}

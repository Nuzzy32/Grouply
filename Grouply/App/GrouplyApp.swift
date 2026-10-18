import SwiftUI

@main
struct GrouplyApp: App {
  @State private var store = DemoStore()
  var body: some Scene {
    WindowGroup {
      RootView().environment(store).tint(GLTheme.ink)
    }
  }
}

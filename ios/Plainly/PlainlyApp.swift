import FirebaseAppCheck
import FirebaseCore
import SwiftUI

@main
struct PlainlyApp: App {
  @State private var model: LetterViewModel

  init() {
    // Without GoogleService-Info.plist the app still runs, in a clearly
    // labelled demo mode with canned answers (see FixtureInference).
    let isConfigured = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    if isConfigured {
      #if DEBUG
        // Must be set before FirebaseApp.configure(). The debug token printed in
        // the Xcode console is registered in the Firebase console.
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
      #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
      #endif
      FirebaseApp.configure()
    }
    _model = State(initialValue: LetterViewModel(isFirebaseConfigured: isConfigured))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(model: model)
        .preferredColorScheme(.light)
    }
  }
}

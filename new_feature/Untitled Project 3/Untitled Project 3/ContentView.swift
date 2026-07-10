import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        CaptionExperimentView()
    }
}

#Preview {
    ContentView()
}

#Playground {
    _ = 1 + 2
}

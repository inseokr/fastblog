import SwiftUI
import Playgrounds

@main struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)   // dark app-wide
                .tint(Color(red: 0.23, green: 0.51, blue: 0.96))   // single blue accent
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

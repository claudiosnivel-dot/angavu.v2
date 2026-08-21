// Angavu iOS — punto d'ingresso dell'app SwiftUI.
//
// L'app è un target Xcode (fuori da `swift build`) che referenzia il package
// SwiftPM locale. Il deployment target iOS 17.0 è dichiarato in
// Config/Shared.xcconfig (fonte canonica) e in App/project.yml (spec XcodeGen).
import SwiftUI

@main
struct AngavuApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

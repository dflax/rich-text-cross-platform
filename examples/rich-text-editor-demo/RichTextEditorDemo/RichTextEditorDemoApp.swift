import SwiftData
import SwiftUI

@main
struct RichTextEditorDemoApp: App {
    var body: some Scene {
        WindowGroup {
            ConfigurationPickerView()
        }
        .modelContainer(for: StoredDocument.self)
        // To sync the SwiftData tab's documents across a user's devices via CloudKit instead of
        // keeping them local to this device, swap the line above for:
        //
        //     .modelContainer(
        //         for: StoredDocument.self,
        //         configurations: ModelConfiguration(cloudKitDatabase: .automatic)
        //     )
        //
        // and give the app an iCloud entitlement first: in Xcode, select the RichTextEditorDemo
        // target → Signing & Capabilities → "+ Capability" → iCloud → check CloudKit, then add or
        // pick a container. This needs a real Apple Developer Program membership — a free
        // personal team can't create iCloud containers. `StoredDocument`'s properties already
        // have default values at declaration, which is CloudKit-backed SwiftData's other
        // requirement (every synced attribute must be optional or have a default) — nothing else
        // about the model needs to change to turn this on.
    }
}

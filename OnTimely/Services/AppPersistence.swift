import Foundation
import SwiftData

@MainActor
enum AppPersistence {
    static func makeContainer() throws -> ModelContainer {
        // The original store used schema version 1. Include every persisted model
        // in both the container and its configuration when migrating that store.
        let schema = Schema([
            TaskItem.self,
            NoteItem.self,
            CalendarSubscription.self
        ], version: Schema.Version(2, 0, 0))

        // Retain the existing default.store URL so tasks and notes migrate in place.
        let storeURL = ModelConfiguration().url
        let configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}

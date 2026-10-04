import CryptoKit
import Foundation
import Observation
import Security
import SwiftData

struct CalendarFeedPreview: Sendable {
    let url: URL
    let feed: ImportedCalendarFeed
    let timeZoneIdentifier: String

    func upcoming(at now: Date) -> [ImportedCalendarEvent] {
        feed.events.filter { !$0.isCancelled && ($0.dueDate ?? .distantPast) > now }
    }

    func pastDueCount(at now: Date) -> Int {
        feed.events.filter { !$0.isCancelled && ($0.dueDate ?? .distantFuture) <= now }.count
    }
}

private enum CalendarLinkKeychain {
    private static var service: String { "\(Bundle.main.bundleIdentifier ?? "OnTimely").calendar-links" }

    private static func query(_ id: UUID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: id.uuidString]
    }

    static func save(_ url: URL, for id: UUID) throws {
        let data = Data(url.absoluteString.utf8)
        let existing = query(id)
        let update = SecItemUpdate(existing as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw CalendarFeedError.credentialStorage }
        var item = existing
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "OnTimely calendar subscription"
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw CalendarFeedError.credentialStorage }
    }

    static func read(_ id: UUID) throws -> URL {
        var item = query(id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let string = String(data: data, encoding: .utf8),
              let url = URL(string: string) else { throw CalendarFeedError.missingCredential }
        return url
    }

    static func remove(_ id: UUID) { SecItemDelete(query(id) as CFDictionary) }
}

@MainActor
@Observable
final class CalendarImportService {
    var isRefreshing = false
    @ObservationIgnored var onTasksChanged: (@MainActor @Sendable () async -> Void)?
    @ObservationIgnored private let store: TaskStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var lastAttempts: [UUID: Date] = [:]
    private static let refreshInterval: TimeInterval = 15 * 60

    init(store: TaskStore) {
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    func preview(link: String, timeZoneIdentifier: String) async throws -> CalendarFeedPreview {
        let url = try Self.normalizedURL(link)
        let fingerprint = Self.fingerprint(url)
        guard try !store.calendarSubscriptions().contains(where: { $0.feedFingerprint == fingerprint }) else {
            throw CalendarFeedError.alreadyConnected
        }
        let zone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let feed = try await fetch(url, timeZone: zone)
        try Task.checkCancellation()
        return CalendarFeedPreview(url: url, feed: feed, timeZoneIdentifier: zone.identifier)
    }

    func subscribe(_ preview: CalendarFeedPreview, selectedEventIDs: Set<String>) async throws -> CalendarImportResult {
        guard !isRefreshing else { throw CalendarFeedError.unavailable }
        isRefreshing = true
        defer { isRefreshing = false }
        let fingerprint = Self.fingerprint(preview.url)
        guard try !store.calendarSubscriptions().contains(where: { $0.feedFingerprint == fingerprint }) else {
            throw CalendarFeedError.alreadyConnected
        }
        let name = preview.feed.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let subscription = CalendarSubscription(feedFingerprint: fingerprint,
                                                name: name?.isEmpty == false ? name! : "ManageBac",
                                                host: preview.url.host ?? "ManageBac",
                                                timeZoneIdentifier: preview.timeZoneIdentifier)
        try CalendarLinkKeychain.save(preview.url, for: subscription.id)
        let result: CalendarImportResult
        do {
            result = try store.importCalendar(preview.feed, subscription: subscription, isNewSubscription: true,
                                              selectedEventIDs: selectedEventIDs,
                                              submissionLeadMinutes: ReminderDefaults.submissionLeadMinutes,
                                              reminderIntervalMinutes: ReminderDefaults.intervalMinutes)
        } catch {
            store.context.rollback()
            CalendarLinkKeychain.remove(subscription.id)
            throw error
        }
        lastAttempts[subscription.id] = .now
        await onTasksChanged?()
        return result
    }

    /// Network refreshes are separate from the frequent local notification refill.
    func refreshSubscriptions(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        guard let subscriptions = try? store.calendarSubscriptions() else { return }
        for subscription in subscriptions {
            let now = Date.now
            if !force, let attempt = lastAttempts[subscription.id], now.timeIntervalSince(attempt) < Self.refreshInterval { continue }
            lastAttempts[subscription.id] = now
            do {
                let url = try CalendarLinkKeychain.read(subscription.id)
                let zone = TimeZone(identifier: subscription.timeZoneIdentifier) ?? .current
                let feed = try await fetch(url, timeZone: zone)
                // A sheet may disconnect a subscription while its fetch is in flight.
                guard try store.calendarSubscriptions().contains(where: { $0.id == subscription.id }) else { continue }
                let result = try store.importCalendar(feed, subscription: subscription,
                                                       submissionLeadMinutes: ReminderDefaults.submissionLeadMinutes,
                                                       reminderIntervalMinutes: ReminderDefaults.intervalMinutes)
                if result.added > 0 || result.updated > 0 { await onTasksChanged?() }
            } catch is CancellationError { return }
            catch {
                store.context.rollback()
                guard (try? store.calendarSubscriptions().contains(where: { $0.id == subscription.id })) == true else { continue }
                // Never surface networking diagnostics that can include the private token URL.
                let message = (error as? CalendarFeedError)?.errorDescription ?? "Calendar changes couldn’t be saved. Try refreshing again."
                try? store.recordCalendarError(subscription, message: message)
            }
        }
    }

    func disconnect(_ subscription: CalendarSubscription) throws {
        let id = subscription.id
        try store.disconnectCalendar(subscription)
        CalendarLinkKeychain.remove(id)
        lastAttempts.removeValue(forKey: id)
    }

    private func fetch(_ url: URL, timeZone: TimeZone) async throws -> ImportedCalendarFeed {
        var request = URLRequest(url: url)
        request.setValue("text/calendar, text/plain;q=0.9", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw CalendarFeedError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw CalendarFeedError.invalidCalendar }
        if http.statusCode == 401 || http.statusCode == 403 { throw CalendarFeedError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw CalendarFeedError.server(http.statusCode) }
        guard data.count <= 8 * 1024 * 1024 else { throw CalendarFeedError.tooLarge }
        try Task.checkCancellation()
        let deadlineSource: CalendarEventDeadlineSource = Self.isManageBacFeed(url) ? .start : .end
        let feed = try await Task.detached(priority: .utility) {
            try ICalendarParser.parse(data, defaultTimeZone: timeZone, eventDeadlineSource: deadlineSource)
        }.value
        try Task.checkCancellation()
        return feed
    }

    private static func normalizedURL(_ link: String) throws -> URL {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed), let scheme = components.scheme?.lowercased(),
              scheme == "webcal" || scheme == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { throw CalendarFeedError.invalidLink }
        components.scheme = "https"
        components.host = host.lowercased()
        components.fragment = nil
        guard let url = components.url else { throw CalendarFeedError.invalidLink }
        return url
    }

    private static func isManageBacFeed(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return ["managebac.cn", "managebac.com"].contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    private static func fingerprint(_ url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

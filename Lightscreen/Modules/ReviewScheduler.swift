import Foundation
import UserNotifications

/// Nudges you, gently and rarely, to tidy your library. Once every 60 days (and
/// only if you've actually got catches piling up) it speaks up in two places: a
/// macOS notification, and a banner across the top of the Library window. Both
/// say the same warm line and both lead to the same place — multi-select, ready
/// to release the ones you don't need.
///
/// The "last spoke" stamp lives in the library's settings table, so the clock
/// survives quits and relaunches.
@MainActor
final class ReviewScheduler {
    private let store: LibraryStore
    private static let stampKey = "last_review_prompt_at"
    private static let interval: TimeInterval = 60 * 24 * 60 * 60 // 60 days

    /// Called when the user taps the system notification — the app opens the
    /// Library straight into review (multi-select) mode.
    var onReviewTapped: (() -> Void)?

    init(store: LibraryStore) {
        self.store = store
    }

    /// True when it's been ≥60 days since we last prompted and there's something
    /// worth tidying. Drives the in-window banner.
    var isReviewDue: Bool {
        guard store.count() >= 1 else { return false }
        guard let last = store.dateSetting(Self.stampKey) else { return false }
        return Date().timeIntervalSince(last) >= Self.interval
    }

    /// Run once at launch. Sets the baseline on first ever run (so a brand-new
    /// library doesn't get nagged on day one), and otherwise fires the system
    /// notification if we're overdue.
    func checkAtLaunch() {
        // First run: start the clock now, say nothing.
        if store.dateSetting(Self.stampKey) == nil {
            markPromptedNow()
            return
        }
        guard isReviewDue else { return }
        requestAuthThenNotify()
    }

    /// Resets the 60-day clock to now — called when the banner is dismissed or a
    /// review session is started, so the next nudge is a full interval away.
    func markPromptedNow() {
        store.setDateSetting(Date(), forKey: Self.stampKey)
    }

    // MARK: - The system notification

    private func requestAuthThenNotify() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, _ in
            guard granted else { return }
            Task { @MainActor in self?.postNotification() }
        }
    }

    private func postNotification() {
        let content = UNMutableNotificationContent()
        content.title = "Lightscreen"
        content.body = "You have a lot of catches. Want to release some?"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lightscreen.review-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil // deliver right away
        )
        UNUserNotificationCenter.current().add(request)
    }
}

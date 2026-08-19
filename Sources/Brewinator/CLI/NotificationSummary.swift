/// The daily banner's text. Produced on every run, quiet ones included: a
/// missing banner is meant to mean "the job did not run", never "nothing
/// changed".
struct NotificationContent: Sendable, Equatable {
    let title: String
    let subtitle: String
    let body: String
}

enum NotificationSummary {
    private static let title = "Brewinator"

    /// Notification Center truncates the body mid-word; past this many the list
    /// is elided deliberately instead.
    private static let maxNamesShown = 4

    static func render(_ result: SyncResult) -> NotificationContent {
        NotificationContent(title: title, subtitle: subtitle(newItemCount: result.newItems.count), body: body(for: result))
    }

    static func renderFailure(_ error: Error) -> NotificationContent {
        NotificationContent(title: title, subtitle: "Run failed", body: String(describing: error))
    }

    private static func subtitle(newItemCount: Int) -> String {
        switch newItemCount {
        case 0: "No new release notes"
        case 1: "1 new release note"
        default: "\(newItemCount) new release notes"
        }
    }

    private static func body(for result: SyncResult) -> String {
        guard !result.newItems.isEmpty else {
            return result.outdated.isEmpty ? "Nothing outdated." : "\(result.outdated.count) outdated."
        }

        let names = result.newItems.map(\.name)
        guard names.count > maxNamesShown else { return names.joined(separator: ", ") }
        return "\(names.prefix(maxNamesShown).joined(separator: ", ")) +\(names.count - maxNamesShown) more"
    }
}

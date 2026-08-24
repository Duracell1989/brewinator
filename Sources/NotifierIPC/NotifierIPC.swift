import Foundation

/// The wire contract between `brewinator` (sender) and `BrewinatorNotify.app`
/// (receiver) over `DistributedNotificationCenter`. A name/key mismatch
/// between the two independently-compiled targets would fail silently - no
/// error, just a dropped notification - so both sides import this instead of
/// repeating the strings.
public enum NotifierIPC {
    public static let notificationName = Notification.Name("dev.b89.brewinator.notify")

    public enum Key {
        public static let title = "title"
        public static let subtitle = "subtitle"
        public static let body = "body"
        public static let openPath = "openPath"
    }
}

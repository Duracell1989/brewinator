import Foundation

@testable import Brewinator

/// Hand-written protocol fake for `AppBundleLocating` — no Moq equivalent in
/// Swift. Casks not registered resolve to nil, matching a machine where the
/// app isn't installed or ships no notes.
struct FakeAppBundleLocator: AppBundleLocating {
    private var bundles: [String: InstalledAppBundle] = [:]

    mutating func register(_ token: String, bundle: InstalledAppBundle) {
        bundles[token] = bundle
    }

    func bundle(forCask token: String, installedVersion: String) -> InstalledAppBundle? {
        bundles[token]
    }
}

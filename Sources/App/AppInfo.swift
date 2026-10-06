import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    /// Contact required by the Transitous usage policy. Set `PublitContact` in project.yml.
    static var contact: String {
        Bundle.main.infoDictionary?["PublitContact"] as? String ?? "https://github.com"
    }

    static var userAgent: String { "Publit/\(version) (iOS; +\(contact))" }

    static let sourcesURL = URL(string: "https://transitous.org/sources/")!
    static let osmCopyrightURL = URL(string: "https://www.openstreetmap.org/copyright")!
}

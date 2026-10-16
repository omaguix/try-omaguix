import Foundation

/// Stable release tags only; development and prerelease builds are not comparable.
struct AppReleaseVersion: Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard fields.count == 3,
              fields.allSatisfy({ field in
                  !field.isEmpty && field.allSatisfy({ $0 >= "0" && $0 <= "9" })
                      && (field.count == 1 || field.first != "0")
              }),
              let major = Int(fields[0]), let minor = Int(fields[1]), let patch = Int(fields[2]) else {
            return nil
        }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String { "\(major).\(minor).\(patch)" }

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

struct InstalledAppRelease: Equatable {
    let version: AppReleaseVersion?
    let label: String

    init(info: [String: Any], identity: AppIdentity) {
        // Older bundles all reported 0.4.0 (5), regardless of their release.
        // Require the build provenance introduced by #223 before comparing.
        let describe = info["TryOmarchyBuildDescribe"] as? String
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? ""
        if let parsed = AppReleaseVersion(shortVersion), describe == identity.releaseTag(parsed) {
            version = parsed
            let build = info["CFBundleVersion"] as? String
            label = "Version \(parsed)" + (build.map { " (\($0))" } ?? "")
        } else {
            version = nil
            label = describe.map { "Development build · \($0)" } ?? "Installed release unknown"
        }
    }

    static var current: Self { Self(info: Bundle.main.infoDictionary ?? [:], identity: .main) }

    /// The upstreams this build carries (scripts/app_version.py), for bug
    /// reports: Try Omarchy's base, Omarchy and the pinned Guix.
    static func upstreams(info: [String: Any]) -> String? {
        var parts: [String] = []
        if let base = info["RoguixTryOmarchyBase"] as? String,
           let describe = base.split(separator: " ").first {
            parts.append("Try Omarchy \(describe)")
        }
        if let omarchy = info["RoguixOmarchyVersion"] as? String {
            parts.append("Omarchy \(omarchy)")
        }
        if let guix = info["RoguixGuixCommit"] as? String {
            parts.append("Guix \(guix.prefix(8))")
        }
        return parts.isEmpty ? nil : "Based on " + parts.joined(separator: ", ")
    }
}

/// Where the running app's releases are published, from its identity.
extension AppIdentity {
    var releasesURL: URL { URL(string: "https://github.com/\(releaseRepository)/releases")! }
    var latestReleaseAPIURL: URL {
        URL(string: "https://api.github.com/repos/\(releaseRepository)/releases/latest")!
    }

    func releaseTag(_ version: AppReleaseVersion) -> String { releaseTagPrefix + version.description }

    /// A release's disk image is `NAME.dmg` or `NAME-vX.Y.Z.dmg`, under the
    /// current name or one that older releases published and keep.
    func releaseAssetNames(_ version: AppReleaseVersion) -> Set<String> {
        Set(([releaseDMG] + legacyReleaseDMGs).flatMap { name -> [String] in
            guard name.hasSuffix(".dmg") else {
                fatalError("Info.plist has a release disk image name without .dmg: \(name)")
            }
            return [name, "\(name.dropLast(".dmg".count))-v\(version).dmg"]
        })
    }
}

struct AppRelease: Equatable {
    let version: AppReleaseVersion
    let url: URL

    static func decode(_ data: Data, identity: AppIdentity) throws -> Self {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let prefix = identity.releaseTagPrefix
        guard !payload.draft, !payload.prerelease, payload.tagName.hasPrefix(prefix),
              let version = AppReleaseVersion(String(payload.tagName.dropFirst(prefix.count))),
              case let names = identity.releaseAssetNames(version),
              payload.assets.contains(where: { names.contains($0.name) && $0.state == "uploaded" }) else {
            throw AppReleaseError.invalidRelease
        }
        // Construct the project URL instead of opening an arbitrary URL from JSON.
        return Self(version: version, identity: identity)
    }

    init(version: AppReleaseVersion, identity: AppIdentity) {
        self.version = version
        url = identity.releasesURL.appendingPathComponent("tag/" + identity.releaseTag(version))
    }

    private struct Payload: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let state: String
        }
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }
}

enum AppReleaseError: LocalizedError {
    case invalidRelease
    case response(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRelease:
            return "GitHub did not return a published stable release with a macOS download."
        case .response(let status):
            return status == 403 || status == 429
                ? "GitHub’s request limit was reached. Try again later or open the releases page."
                : "GitHub could not complete the check (HTTP \(status))."
        }
    }
}

enum AppReleaseCheckState: Equatable {
    case idle
    case checking
    case available(AppRelease)
    case current
    /// GitHub answers 404 for a repository without any published release.
    case noRelease
    case unknownInstalledVersion(AppRelease)
    case failed(String)

    static func result(installed: InstalledAppRelease, latest: AppRelease) -> Self {
        guard let version = installed.version else { return .unknownInstalledVersion(latest) }
        return latest.version > version ? .available(latest) : .current
    }

    var message: String {
        switch self {
        case .idle: return "Check GitHub for the latest stable Mac app release."
        case .checking: return "Checking for updates…"
        case .available(let release): return "Try Omaguix \(release.version) is available. Review its release notes and macOS requirements before downloading."
        case .current: return "No newer stable release was found."
        case .noRelease: return "No stable Try Omaguix release has been published yet."
        case .unknownInstalledVersion(let release):
            return "The latest stable release is \(release.version). This build does not identify its installed release reliably, so versions cannot be compared."
        case .failed(let message): return "Couldn’t check for updates. \(message) You can still launch Omaguix."
        }
    }

    /// The release to review, or the releases page when there is none.
    func releaseURL(identity: AppIdentity) -> URL {
        switch self {
        case .available(let release), .unknownInstalledVersion(let release): return release.url
        default: return identity.releasesURL
        }
    }

    var menuTitle: String {
        if case .available = self { return "Update Available…" }
        return "Check for Updates…"
    }
}

struct AppReleasePreferences {
    private let defaults: UserDefaults
    private let identity: AppIdentity
    private static let enabledKey = "appReleaseAutomaticChecks"
    private static let lastAttemptKey = "appReleaseLastCheckAttempt"
    private static let latestVersionKey = "appReleaseLatestVersion"
    private static let lastPromptedVersionKey = "appReleaseLastPromptedVersion"

    init(defaults: UserDefaults = .standard, identity: AppIdentity = .main) {
        self.defaults = defaults
        self.identity = identity
    }

    var automaticChecks: Bool {
        get { defaults.object(forKey: Self.enabledKey) == nil || defaults.bool(forKey: Self.enabledKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.enabledKey) }
    }

    func shouldCheckAutomatically(now: Date) -> Bool {
        guard automaticChecks else { return false }
        guard let previous = defaults.object(forKey: Self.lastAttemptKey) as? Date else { return true }
        let elapsed = now.timeIntervalSince(previous)
        return elapsed < 0 || elapsed >= 24 * 60 * 60
    }

    func recordAttempt(at date: Date) { defaults.set(date, forKey: Self.lastAttemptKey) }

    var lastPromptedVersion: AppReleaseVersion? {
        get { defaults.string(forKey: Self.lastPromptedVersionKey).flatMap(AppReleaseVersion.init) }
        nonmutating set { defaults.set(newValue?.description, forKey: Self.lastPromptedVersionKey) }
    }

    var latestRelease: AppRelease? {
        get {
            guard let text = defaults.string(forKey: Self.latestVersionKey),
                  let version = AppReleaseVersion(text) else { return nil }
            return AppRelease(version: version, identity: identity)
        }
        nonmutating set { defaults.set(newValue?.version.description, forKey: Self.latestVersionKey) }
    }
}

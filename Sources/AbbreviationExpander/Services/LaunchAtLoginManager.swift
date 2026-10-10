import Foundation
import ServiceManagement

/// Protocol defining Launch At Startup management interface for unit testing and app integration.
public protocol LaunchAtLoginManaging: AnyObject {
    var isEnabled: Bool { get }
    @discardableResult
    func setEnabled(_ enabled: Bool) -> Bool
    func syncWithAppPathIfNeeded()
}

/// Centralized manager for handling macOS system startup / launch-at-login.
///
/// On macOS 13+, attempts modern `SMAppService.mainApp` registration.
/// When running on macOS 12, or in environments where `SMAppService` is unavailable
/// or restricted (e.g. ad-hoc signed or development builds), seamlessly falls back
/// to managing a standard user LaunchAgent plist (`~/Library/LaunchAgents/com.citizen.AbbreviationExpander.plist`).
public final class LaunchAtLoginManager: LaunchAtLoginManaging {
    public static let shared = LaunchAtLoginManager()

    public let bundleIdentifier: String
    public let launchAgentsDirectory: URL
    public let appPathResolver: () -> String

    public init(
        bundleIdentifier: String = AppConfig.bundleIdentifier,
        launchAgentsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true),
        appPathResolver: @escaping () -> String = { LaunchAtLoginManager.defaultAppPath }
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.launchAgentsDirectory = launchAgentsDirectory
        self.appPathResolver = appPathResolver
    }

    /// URL to the LaunchAgent property list file.
    public var plistURL: URL {
        return launchAgentsDirectory.appendingPathComponent("\(bundleIdentifier).plist")
    }

    /// Default resolution for the currently active or installed AbbrEx application bundle path.
    public static var defaultAppPath: String {
        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app") {
            return bundlePath
        }
        let standardApp = "/Applications/AbbrEx.app"
        if FileManager.default.fileExists(atPath: standardApp) {
            return standardApp
        }
        let localBuild = URL(fileURLWithPath: "build/AbbrEx.app").path
        if FileManager.default.fileExists(atPath: localBuild) {
            return localBuild
        }
        return standardApp
    }

    /// Indicates whether AbbrEx is currently configured to launch at system startup.
    public var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                return true
            }
        }
        return FileManager.default.fileExists(atPath: plistURL.path)
    }

    /// Sets whether AbbrEx should launch at system startup.
    @discardableResult
    public func setEnabled(_ enabled: Bool) -> Bool {
        if enabled {
            return enable()
        } else {
            return disable()
        }
    }

    private func enable() -> Bool {
        if #available(macOS 13.0, *) {
            do {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
                // When SMAppService succeeds, remove any old fallback LaunchAgent file
                try? FileManager.default.removeItem(at: plistURL)
                return true
            } catch {
                // Fall through to LaunchAgent fallback on error
            }
        }

        return createLaunchAgentPlist()
    }

    private func disable() -> Bool {
        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status == .enabled {
                try? SMAppService.mainApp.unregister()
            }
        }

        if FileManager.default.fileExists(atPath: plistURL.path) {
            unloadLaunchAgentIfNeeded()
            do {
                try FileManager.default.removeItem(at: plistURL)
            } catch {
                return false
            }
        }
        return true
    }

    /// Generates or refreshes the user LaunchAgent property list file.
    @discardableResult
    public func createLaunchAgentPlist() -> Bool {
        do {
            try FileManager.default.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)
            let appPath = appPathResolver()
            let plistContent: [String: Any] = [
                "Label": bundleIdentifier,
                "ProgramArguments": ["/usr/bin/open", "-a", appPath],
                "RunAtLoad": true,
                "ProcessType": "Interactive"
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Ensures that an already registered LaunchAgent plist has an up-to-date target app path.
    public func syncWithAppPathIfNeeded() {
        guard isEnabled else { return }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            _ = createLaunchAgentPlist()
        }
    }

    private func unloadLaunchAgentIfNeeded() {
        guard FileManager.default.fileExists(atPath: plistURL.path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["unload", plistURL.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }
}

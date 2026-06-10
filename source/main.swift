import AppKit
import Foundation

enum SwitchMode {
    case privateRelay
    case expressVPN
    case needsInstall
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let appName = "P- Relay to Express Switcher"
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        if mode() == .needsInstall {
            promptToInstallHelpers()
        }
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
    }

    private func buildMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Status: Checking...", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Install Helper Tools...", action: #selector(installHelpersFromMenu), keyEquivalent: "i"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Use Private Relay", action: #selector(usePrivateRelay), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Use ExpressVPN", action: #selector(useExpressVPN), keyEquivalent: "e"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Open ExpressVPN", action: #selector(openExpressVPN), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Refresh Status", action: #selector(refreshStatusAction), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func mode() -> SwitchMode {
        guard helpersInstalled else {
            return .needsInstall
        }

        return run("/bin/launchctl", ["print", "system/com.express.vpn.daemon"], quiet: true).status == 0
            ? .expressVPN
            : .privateRelay
    }

    private var helpersInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/local/sbin/expressvpn-private-relay-mode")
            && FileManager.default.isExecutableFile(atPath: "/usr/local/sbin/expressvpn-enable-mode")
    }

    private func setBusy(_ title: String) {
        statusItem.button?.title = title
        statusItem.button?.toolTip = appName
        statusItem.menu?.item(at: 0)?.title = "Status: Working..."
    }

    private func refreshStatus() {
        let currentMode = mode()
        switch currentMode {
        case .privateRelay:
            statusItem.button?.title = "P- Relay"
            statusItem.button?.toolTip = "Private Relay mode: ExpressVPN daemon is off"
            statusItem.menu?.item(at: 0)?.title = "Status: Private Relay"
            statusItem.menu?.item(withTitle: "Use Private Relay")?.state = .on
            statusItem.menu?.item(withTitle: "Use ExpressVPN")?.state = .off
        case .expressVPN:
            statusItem.button?.title = "E VPN"
            statusItem.button?.toolTip = "ExpressVPN mode: ExpressVPN daemon is on"
            statusItem.menu?.item(at: 0)?.title = "Status: ExpressVPN"
            statusItem.menu?.item(withTitle: "Use Private Relay")?.state = .off
            statusItem.menu?.item(withTitle: "Use ExpressVPN")?.state = .on
        case .needsInstall:
            statusItem.button?.title = "Setup"
            statusItem.button?.toolTip = "Install helper tools"
            statusItem.menu?.item(at: 0)?.title = "Status: Helper Tools Needed"
            statusItem.menu?.item(withTitle: "Use Private Relay")?.state = .off
            statusItem.menu?.item(withTitle: "Use ExpressVPN")?.state = .off
        }
    }

    @objc private func refreshStatusAction() {
        refreshStatus()
    }

    @objc private func installHelpersFromMenu() {
        promptToInstallHelpers()
    }

    private func promptToInstallHelpers() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Install helper tools?"
        alert.informativeText = "\(appName) needs helper tools to switch ExpressVPN's background daemon. macOS will ask for an administrator password once."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            refreshStatus()
            return
        }

        let result = installHelpers()
        if result.status == 0 {
            let done = NSAlert()
            done.messageText = "Helper tools installed."
            done.informativeText = "You can now switch modes from the menu bar."
            done.addButton(withTitle: "OK")
            done.runModal()
        } else {
            showError("Could not install helper tools.", result.output)
        }
        refreshStatus()
    }

    private func installHelpers() -> (status: Int32, output: String) {
        guard let privateHelper = Bundle.main.path(forResource: "expressvpn-private-relay-mode", ofType: nil),
              let enableHelper = Bundle.main.path(forResource: "expressvpn-enable-mode", ofType: nil) else {
            return (1, "The app bundle is missing its embedded helper scripts.")
        }

        let currentUser = NSUserName()
        let sudoersPath = "/etc/sudoers.d/expressvpn-private-relay-switch-\(currentUser)"
        let sudoersLine = "\(currentUser) ALL=(root) NOPASSWD: /usr/local/sbin/expressvpn-private-relay-mode, /usr/local/sbin/expressvpn-enable-mode"
        let script = """
        set -eu
        if [ ! -d /Applications/ExpressVPN.app ]; then echo 'ExpressVPN is not installed in /Applications.'; exit 2; fi
        install -d -o root -g wheel -m 755 /usr/local/sbin
        install -o root -g wheel -m 755 \(shellQuote(privateHelper)) /usr/local/sbin/expressvpn-private-relay-mode
        install -o root -g wheel -m 755 \(shellQuote(enableHelper)) /usr/local/sbin/expressvpn-enable-mode
        printf '%s\\n' \(shellQuote(sudoersLine)) > \(shellQuote(sudoersPath))
        chmod 440 \(shellQuote(sudoersPath))
        chown root:wheel \(shellQuote(sudoersPath))
        visudo -cf \(shellQuote(sudoersPath))
        """

        let appleScript = "do shell script \(appleScriptString(script)) with administrator privileges"
        return run("/usr/bin/osascript", ["-e", appleScript], quiet: false)
    }

    @objc private func usePrivateRelay() {
        guard ensureInstalled() else { return }
        setBusy("...")
        DispatchQueue.global(qos: .userInitiated).async {
            _ = self.run("/bin/launchctl", ["bootout", "gui/\(getuid())", "\(NSHomeDirectory())/Library/LaunchAgents/com.express.vpn.client.plist"], quiet: true)
            _ = self.run("/bin/launchctl", ["disable", "gui/\(getuid())/com.express.vpn.client"], quiet: true)
            _ = self.run("/usr/bin/osascript", ["-e", "tell application \"ExpressVPN\" to quit"], quiet: true)
            _ = self.run("/usr/bin/pkill", ["-f", "/Applications/ExpressVPN.app/Contents/MacOS/ExpressVPN"], quiet: true)
            let result = self.run("/usr/bin/sudo", ["-n", "/usr/local/sbin/expressvpn-private-relay-mode"], quiet: false)
            DispatchQueue.main.async {
                if result.status != 0 {
                    self.showError("Could not switch to Private Relay mode.", result.output)
                }
                self.refreshStatus()
            }
        }
    }

    @objc private func useExpressVPN() {
        guard ensureInstalled() else { return }
        setBusy("...")
        DispatchQueue.global(qos: .userInitiated).async {
            let result = self.run("/usr/bin/sudo", ["-n", "/usr/local/sbin/expressvpn-enable-mode"], quiet: false)
            guard result.status == 0 else {
                DispatchQueue.main.async {
                    self.showError("Could not start ExpressVPN daemon.", result.output)
                    self.refreshStatus()
                }
                return
            }

            var ready = false
            for _ in 0..<10 {
                if self.run("/bin/launchctl", ["print", "system/com.express.vpn.daemon"], quiet: true).status == 0 {
                    ready = true
                    break
                }
                Thread.sleep(forTimeInterval: 0.5)
            }

            DispatchQueue.main.async {
                if ready {
                    _ = self.run("/bin/launchctl", ["enable", "gui/\(getuid())/com.express.vpn.client"], quiet: true)
                    _ = self.run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", "\(NSHomeDirectory())/Library/LaunchAgents/com.express.vpn.client.plist"], quiet: true)
                    self.refreshStatus()
                    self.openExpressVPN()
                } else {
                    self.showError("ExpressVPN daemon did not start.", "ExpressVPN was not opened.")
                    self.refreshStatus()
                }
            }
        }
    }

    @objc private func openExpressVPN() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/ExpressVPN.app"), configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func ensureInstalled() -> Bool {
        if mode() != .needsInstall {
            return true
        }
        promptToInstallHelpers()
        return mode() != .needsInstall
    }

    private func showError(_ message: String, _ info: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = info.isEmpty ? "No additional details were provided." : info
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        + "\""
    }

    @discardableResult
    private func run(_ launchPath: String, _ arguments: [String], quiet: Bool) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, quiet ? "" : output)
        } catch {
            return (127, quiet ? "" : error.localizedDescription)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()


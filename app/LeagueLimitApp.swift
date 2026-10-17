import AppKit
import ServiceManagement

let label = "com.leaguelimit.watcher"
let home = FileManager.default.homeDirectoryForCurrentUser.path
let plistPath = "\(home)/Library/LaunchAgents/\(label).plist"
let appDir = "\(home)/Library/Application Support/league-limit"

struct Status: Decodable {
    let day: String
    let played: Int
    let limit: Int
    let reset_hour: Int
    let in_game_minutes: Int?
    let history: [String: Int]
}

@discardableResult
func run(_ path: String, _ args: [String]) -> (code: Int32, out: Data) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return (-1, Data()) }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, data)
}

/// The python interpreter and script the watcher runs, read from its LaunchAgent plist.
func watcherCommand() -> (python: String, script: String)? {
    guard let plist = NSDictionary(contentsOfFile: plistPath),
          let args = plist["ProgramArguments"] as? [String], args.count >= 2 else { return nil }
    return (args[0], args[1])
}

func watcherRunning() -> Bool {
    let r = run("/bin/launchctl", ["print", "gui/\(getuid())/\(label)"])
    return r.code == 0 && String(decoding: r.out, as: UTF8.self).contains("state = running")
}

func fetchStatus() -> Status? {
    guard let cmd = watcherCommand() else { return nil }
    let r = run(cmd.python, [cmd.script, "json"])
    guard r.code == 0 else { return nil }
    return try? JSONDecoder().decode(Status.self, from: r.out)
}

class AppDelegate: NSObject, NSApplicationDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var status: Status?
    var running = false
    var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            let s = fetchStatus()
            let r = watcherRunning()
            DispatchQueue.main.async {
                self.status = s
                self.running = r
                self.render()
            }
        }
    }

    func render() {
        guard let button = item.button else { return }
        let symbol: String
        let title: String
        if !running {
            symbol = "exclamationmark.triangle.fill"
            title = " off"
        } else if let s = status {
            if s.in_game_minutes != nil {
                symbol = "flame.fill"
            } else if s.played >= s.limit {
                symbol = "lock.fill"
            } else {
                symbol = "gamecontroller.fill"
            }
            title = " \(s.played)/\(s.limit)"
        } else {
            symbol = "questionmark.circle"
            title = ""
        }
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "League Limit")
        button.imagePosition = .imageLeading
        button.title = title
        item.menu = buildMenu()
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        func info(_ text: String) {
            let i = NSMenuItem(title: text, action: nil, keyEquivalent: "")
            i.isEnabled = false
            menu.addItem(i)
        }

        if let s = status {
            info("Today: \(s.played) of \(s.limit) game\(s.limit == 1 ? "" : "s") played")
            if let mins = s.in_game_minutes {
                info("In a game right now (\(mins) min)")
            } else if s.played >= s.limit {
                info("Limit reached. Resets at \(s.reset_hour):00")
            } else {
                info("You can still play today")
            }
            if !s.history.isEmpty {
                menu.addItem(.separator())
                info("Last 7 days")
                for (day, n) in s.history.sorted(by: { $0.key > $1.key }) {
                    info("   \(day):  \(n)")
                }
            }
        } else {
            info("Watcher isn't installed. Run install.sh")
        }

        menu.addItem(.separator())
        if running {
            info("Watcher running")
        } else {
            info("Watcher is NOT running. League isn't limited")
            menu.addItem(withTitle: "Start Watcher", action: #selector(startWatcher), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Open Log", action: #selector(openLog), keyEquivalent: "").target = self

        let login = NSMenuItem(title: "Open at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit League Limit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc func startWatcher() {
        run("/bin/launchctl", ["bootstrap", "gui/\(getuid())", plistPath])
        refresh()
    }

    @objc func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "\(appDir)/watcher.log"))
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't change login setting"
            alert.informativeText = "Add League Limit manually in System Settings > General > Login Items.\n\n\(error.localizedDescription)"
            alert.runModal()
        }
        render()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

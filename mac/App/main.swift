import AppKit
import WebKit
import ServiceManagement

/// A web view normally swallows every mouse-down, so dragging the black background
/// did nothing. Letting AppKit treat those drags as window moves fixes that; plain
/// clicks still reach the page (the menu and switches keep working).
final class DraggableWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class ClockWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var window: ClockWindow!
    var webView: WKWebView!
    var floatItem: NSMenuItem!
    var loginItem: NSMenuItem!
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        loadClock()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(reload), name: NSWorkspace.didWakeNotification, object: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // MARK: Window

    func buildWindow() {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 520)
        window = ClockWindow(contentRect: frame,
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
        window.title = "Flip Clock"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = .black
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.minSize = NSSize(width: 320, height: 200)
        window.setFrameAutosaveName("FlipClockWindow")
        window.delegate = self
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()

        webView = DraggableWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .black
        webView.allowsBackForwardNavigationGestures = false
        window.contentView = webView

        setFloating(defaults.bool(forKey: "floatOnTop"))
        window.makeKeyAndOrderFront(nil)
    }

    func loadClock() {
        guard let dir = Bundle.main.resourceURL else { return }
        webView.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
    }

    // MARK: Menu

    func buildMenu() {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Flip Clock", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        loginItem = appMenu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Flip Clock", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Flip Clock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; mainMenu.addItem(appItem)

        let viewMenu = NSMenu(title: "View")
        floatItem = viewMenu.addItem(withTitle: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "t")
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        viewMenu.addItem(.separator())
        let fs = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]
        let viewItem = NSMenuItem(); viewItem.submenu = viewMenu; mainMenu.addItem(viewItem)

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let windowItem = NSMenuItem(); windowItem.submenu = windowMenu; mainMenu.addItem(windowItem)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc func reload() { webView.reload() }

    @objc func toggleFloat() {
        let on = window.level != .floating
        setFloating(on)
        defaults.set(on, forKey: "floatOnTop")
    }

    func setFloating(_ on: Bool) {
        window.level = on ? .floating : .normal
        floatItem.state = on ? .on : .off
    }

    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert(); alert.messageText = "Couldn't change Launch at Login"
            alert.informativeText = error.localizedDescription; alert.runModal()
        }
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

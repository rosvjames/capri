import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notch: NotchController?
    var statusItem: NSStatusItem?
    var demoTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController()
        self.notch = notch
        installStatusItem()

        // Modo demostración: CAPRI_DEMO=1 abre el notch y cicla los estados.
        if ProcessInfo.processInfo.environment["CAPRI_DEMO"] == "1" {
            notch.setExpanded(true)
            demoTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak notch] _ in
                notch?.model.mode = notch?.model.mode.next ?? .idle
            }
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Capri")
        let menu = NSMenu()
        menu.addItem(withTitle: "Salir de Capri", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }
}

let args = CommandLine.arguments
if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
    let modes = AssistantMode.allCases
    let mode = args.count > i + 2 ? (modes.first { "\($0)" == args[i + 2] } ?? .idle) : .idle
    MainActor.assumeIsolated { writeSnapshot(to: args[i + 1], mode: mode) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

import AppKit
import Combine
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    var notch: NotchController?
    var statusItem: NSStatusItem?
    var demoTimer: Timer?
    let pushToTalk = PushToTalk()
    let listener = SpeechListener()
    let speaker = Speaker()
    let music = MusicWatcher()
    private var accessibilityWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController()
        self.notch = notch
        installStatusItem()
        installPushToTalk(notch)
        music.onChange = { notch.model.nowPlaying = $0 }

        // Modo demostración: CAPRI_DEMO=1 abre el notch y cicla los estados.
        if ProcessInfo.processInfo.environment["CAPRI_DEMO"] == "1" {
            notch.setExpanded(true)
            demoTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak notch] _ in
                notch?.model.mode = notch?.model.mode.next ?? .idle
            }
        }
        // CAPRI_DECIR="texto" la hace hablar al arrancar, para probar la voz sin micrófono.
        if let text = ProcessInfo.processInfo.environment["CAPRI_DECIR"] {
            speaker.speak(text)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        speaker.shutdown()
    }

    /// ⌘ derecho mantenido (o el botón Hablar) → escuchar, transcribir y responder en voz.
    /// El demo devuelve un saludo fijo para «hola Capri» y eco para el resto; aún no usa IA.
    private func installPushToTalk(_ notch: NotchController) {
        let model = notch.model, listener = listener, speaker = speaker
        speaker.onPreparing = { model.mode = .thinking }
        speaker.onStart = {
            TalkingFace.shared.reset()
            model.mode = .speaking
            notch.showWhileSpeaking()
        }
        speaker.onFinish = {
            guard model.mode == .speaking || model.mode == .thinking else { return }
            model.mode = .idle
            model.expandedAt = Date()  // el loop vuelve a empezar desde la pose en la que habló
            notch.speechEnded()
        }
        speaker.onError = { message in
            model.transcript = message
            model.mode = .idle
            notch.setExpanded(true)
        }
        model.speechLevel = { speaker.level() }
        listener.onPartial = { model.transcript = $0 }
        listener.onLevel = { model.audioLevel = $0 }
        listener.onFinal = { text in
            model.transcript = text
            model.mode = .idle
            speaker.speak(DemoReply.response(to: text))
        }
        listener.onError = { message in
            model.transcript = message
            model.mode = .idle
        }
        let begin = {
            guard model.permissions.allGranted else { return model.permissions.requestMissing() }
            speaker.stop()  // si estaba hablando, se calla para escucharte
            speaker.prepare()
            model.transcript = ""
            model.mode = .listening
            listener.start()
        }
        let end = {
            guard listener.isListening else { return }
            model.mode = .thinking  // mientras llega el texto final
            listener.stop()
        }
        pushToTalk.onStart = begin
        pushToTalk.onEnd = end
        pushToTalk.onCancel = {
            listener.cancel()
            model.transcript = ""
            model.mode = .idle
        }
        // Esc la calla o cancela la escucha (C-10). En reposo no hace nada.
        pushToTalk.onEscape = {
            guard model.mode != .idle else { return }
            Logger(subsystem: "com.rosvjames.capri", category: "atajo").notice("Esc: se cancela \(String(describing: model.mode), privacy: .public)")
            listener.cancel()
            speaker.stop()
            model.mode = .idle
        }
        model.toggleTalk = {
            if speaker.isBusy { return speaker.stop() }
            listener.isListening ? end() : begin()
        }
        // Los monitores de teclado solo reciben eventos con accesibilidad: se (re)instalan al concederla.
        accessibilityWatch = model.permissions.$states
            .map { $0[.accessibility] == .granted }
            .removeDuplicates()
            .sink { [pushToTalk] granted in granted ? pushToTalk.start() : pushToTalk.stop() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = MenuBarIcon.make()
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
    let expanded = !args.contains("colapsado")
    let elapsed = args.first { $0.hasPrefix("t=") }.flatMap { Double($0.dropFirst(2)) } ?? 0
    MainActor.assumeIsolated { writeSnapshot(to: args[i + 1], mode: mode, expanded: expanded, elapsedMs: elapsed, withoutPermissions: args.contains("sinpermisos")) }
    exit(0)
}
if let i = args.firstIndex(of: "--icon"), args.count > i + 1 {
    writeIconPreview(to: args[i + 1])
    exit(0)
}
if args.contains("--timing-check") {
    printExposureSchedule()
    exit(0)
}
if let i = args.firstIndex(of: "--gallery"), args.count > i + 1 {
    MainActor.assumeIsolated { writeGallery(to: args[i + 1]) }
    exit(0)
}

// Si el proceso de voz muere, escribirle debe dar un error (LocalQwen lo maneja), no cerrar Capri.
signal(SIGPIPE, SIG_IGN)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()

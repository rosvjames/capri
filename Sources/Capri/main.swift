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
    let ducker = AudioDucker()
    let spotifyAccount = SpotifyAccount()
    var bubble: SpotifyBubbleController?
    lazy var conversation = Conversation(actions: ActionRunner(music: music))
    private var accessibilityWatch: AnyCancellable?
    private var duckingWatch: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController()
        self.notch = notch
        installStatusItem()
        installPushToTalk(notch)
        music.onChange = { [spotifyAccount] song in
            let changed = song?.trackID != notch.model.nowPlaying?.trackID
            notch.model.nowPlaying = song
            guard changed else { return }
            // Me gusta de la canción nueva (solo con la sesión de Spotify iniciada).
            notch.model.liked = nil
            guard let id = song?.trackID else { return }
            spotifyAccount.isSaved(id) { saved in
                if notch.model.nowPlaying?.trackID == id { notch.model.liked = saved }
            }
        }
        let bubble = SpotifyBubbleController(account: spotifyAccount, remote: music.spotify)
        self.bubble = bubble
        bubble.onVisibilityChange = { notch.bubbleChanged($0) }
        notch.model.toggleBubble = {
            let anchor = notch.bubbleAnchor
            bubble.toggle(centerX: anchor.centerX, top: anchor.top)
        }
        notch.model.toggleLike = { [spotifyAccount] in
            guard let id = notch.model.nowPlaying?.trackID else { return }
            let target = !(notch.model.liked ?? false)
            notch.model.liked = target  // se ve al instante; si falla, vuelve
            spotifyAccount.setSaved(id, target) { saved in
                guard notch.model.nowPlaying?.trackID == id else { return }
                notch.model.liked = saved ?? !target
            }
        }
        music.onArtwork = { notch.model.artwork = $0 }
        notch.model.musicCommand = { [music] in music.spotify.send($0) }
        music.onClock = { notch.model.clock = $0 }
        music.onRepeat = { notch.model.repeating = $0 }
        notch.model.refreshPlayback = { [music] in music.refreshPlayback() }
        notch.model.seek = { [music] seconds in
            music.spotify.seek(to: seconds)
            // Se muestra el salto en seguida; la lectura siguiente lo confirma.
            if let clock = notch.model.clock {
                notch.model.clock = PlaybackClock(position: seconds, duration: clock.duration, at: Date(), playing: clock.playing)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { music.refreshPlayback() }
        }
        notch.model.toggleRepeat = { [music] in
            music.spotify.toggleRepeat { if let value = $0 { notch.model.repeating = value } }
        }
        music.start()

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
        // CAPRI_PREGUNTAR="texto" hace como si se lo hubieras dicho: precarga los modelos como al pulsar ⌘,
        // espera lo que tardarías en hablar y entonces piensa la respuesta y la dice.
        // Varias preguntas separadas por | se hacen cada 20 s en la misma sesión, como en el uso normal.
        if let questions = ProcessInfo.processInfo.environment["CAPRI_PREGUNTAR"]?.components(separatedBy: "|") {
            for (i, text) in questions.enumerated() {
                let start = DispatchTime.now() + Double(i) * 20
                DispatchQueue.main.asyncAfter(deadline: start) { [speaker, conversation] in
                    speaker.prepare()
                    conversation.warmUp()
                }
                DispatchQueue.main.asyncAfter(deadline: start + 3) { [listener] in
                    Logger(subsystem: "com.rosvjames.capri", category: "escucha").notice("pregunta simulada")
                    listener.onFinal(text)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        speaker.shutdown()
    }

    /// ⌘ derecho mantenido (o el botón Hablar) → escuchar, transcribir y responder en voz.
    /// La respuesta la piensa el modelo local (`Conversation`); con CAPRI_LLM=demo, eco sin IA.
    private func installPushToTalk(_ notch: NotchController) {
        let model = notch.model, listener = listener, speaker = speaker, conversation = conversation
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
        // Antes de callarla: al detener la voz llega onFinish, que abriría la franja de la respuesta anterior.
        let clearStrip = {
            model.copyable = nil
            model.showsStrip = false
        }
        listener.onPartial = { model.transcript = $0 }
        listener.onLevel = { model.audioLevel = $0 }
        listener.onFinal = { text in
            model.transcript = text
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return speaker.speak("No te escuché.")
            }
            model.mode = .thinking
            // La primera frase empieza a sonar mientras el modelo escribe el resto.
            var started = false
            conversation.ask(text, onSentence: { sentence in
                if !started {
                    started = true
                    speaker.begin()
                }
                speaker.add(sentence)
            }, completion: { result in
                switch result {
                case .success(let reply):
                    model.copyable = reply.copyable
                    speaker.end()
                case .failure(let error):
                    let message = (error as? BrainError)?.spoken ?? "No pude pensar una respuesta. Inténtalo de nuevo."
                    if started {
                        speaker.add(message)
                        speaker.end()
                    } else {
                        speaker.speak(message)
                    }
                }
            })
        }
        listener.onError = { message in
            model.transcript = message
            model.mode = .idle
        }
        let begin = {
            guard model.permissions.allGranted else { return model.permissions.requestMissing() }
            clearStrip()
            speaker.stop()  // si estaba hablando, se calla para escucharte
            conversation.cancel()
            speaker.prepare()
            conversation.warmUp()
            model.transcript = ""
            // Primero el micrófono y después el cambio de estado, que pone en marcha la atenuación: crear su
            // dispositivo de audio reconfigura el audio del Mac y, si coincide con abrir el micrófono, el
            // formato que se lee puede no ser el real.
            listener.start()
            guard listener.isListening else { return }
            model.mode = .listening
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
            conversation.cancel()
            clearStrip()
            speaker.stop()
            model.mode = .idle
        }
        model.toggleTalk = {
            if speaker.isBusy { return speaker.stop() }
            listener.isListening ? end() : begin()
        }
        // Mientras Capri escucha, piensa o habla, las demás apps suenan más bajo; al volver al reposo, como antes.
        duckingWatch = model.$mode
            .map { $0 != .idle }
            .removeDuplicates()
            .sink { [ducker] busy in busy ? ducker.duck() : ducker.release() }
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
    MainActor.assumeIsolated { writeSnapshot(to: args[i + 1], mode: mode, expanded: expanded, elapsedMs: elapsed, withoutPermissions: args.contains("sinpermisos"),
                                       music: args.contains("musica"),
                                       strip: args.contains("franja2") ? "brew install node\nnode -v\nnpm -v"
                                           : args.contains("franja") ? "docker run --name web -p 8080:80 nginx" : nil,
                                       section: args.contains("asistente") ? .assistant : nil) }
    exit(0)
}
if let i = args.firstIndex(of: "--icon"), args.count > i + 1 {
    writeIconPreview(to: args[i + 1])
    exit(0)
}
// --preguntar "texto" ["seguimiento"…] imprime las respuestas, en la misma conversación, sin voz ni ventana.
if let i = args.firstIndex(of: "--preguntar") {
    // Las acciones se hacen de verdad ("abre Safari" lo abre). Lo que suena se lee de Spotify si ya hay permiso.
    let music = MusicWatcher()
    music.start()
    let conversation = Conversation(actions: ActionRunner(music: music))
    var questions = args[(i + 1)...].filter { !$0.hasPrefix("--") }[...]
    func next() {
        guard let question = questions.popFirst() else { exit(0) }
        let start = Date()
        print("\n> \(question)")
        conversation.ask(question, onSentence: { sentence in
            print(String(format: "[%.2f s] ", Date().timeIntervalSince(start)) + sentence)
        }, completion: { result in
            switch result {
            case .success(let reply):
                if let copyable = reply.copyable { print("[copiar]\n\(copyable)") }
            case .failure(let error): print("error: \(error.localizedDescription)")
            }
            print(String(format: "(completa en %.2f s)", Date().timeIntervalSince(start)))
            next()
        })
    }
    next()
    dispatchMain()
}
// --entender "frase"… imprime qué acción reconoce la vía rápida, sin hacerla; "—" si la frase iría al modelo.
if let i = args.firstIndex(of: "--entender") {
    let apps = AppCatalog()
    for sentence in args[(i + 1)...] {
        let action = QuickCommands.match(sentence, apps: apps)
        let app = { if case .openApp(let name)? = action { apps.find(name)?.url.path ?? "" } else { "" } }()
        print("\(sentence) → \(action.map { String(describing: $0) } ?? "—") \(app)")
    }
    print(SpokenTime.time(Date()), SpokenTime.date(Date()), SpokenTime.context())
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

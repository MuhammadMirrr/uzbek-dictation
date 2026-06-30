import SwiftUI
import AVFoundation
import AppKit
import Carbon.HIToolbox
import ApplicationServices

// MARK: - Whisper (rubaiSTT) yadrosi

final class Whisper {
    static let shared = Whisper()
    private var loaded = false
    private let q = DispatchQueue(label: "rubai.whisper")

    private func modelPath() -> String? {
        if let p = Bundle.main.path(forResource: "ggml-rubaistt", ofType: "bin") { return p }
        let fb = NSHomeDirectory() + "/rubai-stt/models/ggml-rubaistt.bin"
        return FileManager.default.fileExists(atPath: fb) ? fb : nil
    }

    func transcribe(_ samples: [Float], done: @escaping (String) -> Void) {
        q.async {
            if !self.loaded {
                guard let mp = self.modelPath(), rubai_load(mp) == 0 else {
                    DispatchQueue.main.async { done("") }; return
                }
                self.loaded = true
            }
            let threads = Int32(max(4, ProcessInfo.processInfo.activeProcessorCount - 2))
            var text = ""
            samples.withUnsafeBufferPointer { buf in
                if let c = rubai_transcribe(buf.baseAddress, Int32(buf.count), threads) {
                    text = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    rubai_free_str(c)
                }
            }
            DispatchQueue.main.async { done(text) }
        }
    }

    func unload() { q.async { if self.loaded { rubai_unload(); self.loaded = false } } }
    var isLoaded: Bool { loaded }
}

// MARK: - Mikrofon (16kHz mono float32)

final class Recorder {
    private var engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 16000, channels: 1, interleaved: false)!
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    func start(_ cb: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: cb(begin())
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                DispatchQueue.main.async { cb(ok ? self.begin() : false) }
            }
        default: cb(false)
        }
    }

    private func begin() -> Bool {
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        // Har yozishda YANGI engine — login'da/qurilma o'zgarganda qotib qolgan
        // (jim, "musiqa") holatdan saqlaydi.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let hw = input.outputFormat(forBus: 0)
        guard hw.sampleRate > 0 else { return false }
        converter = AVAudioConverter(from: hw, to: target)
        input.installTap(onBus: 0, bufferSize: 4096, format: hw) { [weak self] buf, _ in
            guard let self = self, let conv = self.converter else { return }
            let ratio = self.target.sampleRate / hw.sampleRate
            let cap = AVAudioFrameCount(Double(buf.frameLength) * ratio) + 1024
            guard let out = AVAudioPCMBuffer(pcmFormat: self.target, frameCapacity: cap) else { return }
            var fed = false; var err: NSError?
            conv.convert(to: out, error: &err) { _, s in
                if fed { s.pointee = .noDataNow; return nil }
                fed = true; s.pointee = .haveData; return buf
            }
            if let ch = out.floatChannelData {
                let n = Int(out.frameLength)
                self.lock.lock()
                self.samples.append(contentsOf: UnsafeBufferPointer(start: ch[0], count: n))
                self.lock.unlock()
            }
        }
        engine.prepare()
        do { try engine.start() } catch { return false }
        isRecording = true
        return true
    }

    func stop() -> [Float] {
        guard isRecording else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRecording = false
        lock.lock(); let s = samples; lock.unlock()
        return s
    }
}

// MARK: - Suzuvchi overlay oyna (fokusni o'g'irlamaydi)

final class Overlay {
    private var panel: NSPanel?
    private let icon = NSTextField(labelWithString: "")
    private let label = NSTextField(labelWithString: "")
    private let W: CGFloat = 300
    private let H: CGFloat = 56

    func show(_ text: String, recording: Bool) {
        if panel == nil {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: W, height: H),
                            styleMask: [.nonactivatingPanel, .borderless],
                            backing: .buffered, defer: false)
            p.level = .floating
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.backgroundColor = .clear
            p.isOpaque = false
            p.hasShadow = true

            // HUD orqa fon (blur)
            let bg = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: W, height: H))
            bg.material = .hudWindow
            bg.blendingMode = .behindWindow
            bg.state = .active
            bg.wantsLayer = true
            bg.layer?.cornerRadius = 14
            bg.layer?.masksToBounds = true

            // ikona — vertikal markazda
            icon.font = .systemFont(ofSize: 20)
            icon.isBezeled = false; icon.isEditable = false; icon.drawsBackground = false
            icon.alignment = .center
            icon.frame = NSRect(x: 16, y: (H - 26) / 2, width: 26, height: 26)

            // matn — vertikal markazda
            label.font = .systemFont(ofSize: 14, weight: .semibold)
            label.textColor = .labelColor
            label.isBezeled = false; label.isEditable = false; label.drawsBackground = false
            label.alignment = .left
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: 50, y: (H - 18) / 2, width: W - 66, height: 18)

            bg.addSubview(icon)
            bg.addSubview(label)
            p.contentView = bg
            panel = p
        }
        icon.stringValue = recording ? "🔴" : "✍️"
        label.stringValue = text
        if let scr = NSScreen.main {
            let f = scr.visibleFrame
            panel!.setFrameOrigin(NSPoint(x: f.midX - W / 2, y: f.minY + 140))
        }
        panel!.orderFrontRegardless()
    }

    func hide() { panel?.orderOut(nil) }
}

// MARK: - Matnni faol input'ga kiritish (clipboard + ⌘V)

enum Inserter {
    static func insert(_ text: String) {
        NSLog("[rubai] insert: len=\(text.count) AXTrusted=\(AXIsProcessTrusted())")
        guard !text.isEmpty else { NSLog("[rubai] insert: matn bo'sh, to'xtatildi"); return }
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        // ⌘V yuborish (Accessibility ruxsati kerak)
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
        NSLog("[rubai] ⌘V yuborildi (down=\(down != nil) up=\(up != nil))")
        // eski clipboard'ni qaytarish
        if let old = old {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pb.clearContents(); pb.setString(old, forType: .string)
            }
        }
    }
}

// MARK: - Hotkey sozlamasi (UserDefaults'da saqlanadi)

struct HotKeyConfig {
    var keyCode: UInt32          // virtual key code (masalan kVK_ANSI_D)
    var carbonModifiers: UInt32  // controlKey | optionKey | ...
    var label: String            // ekranda ko'rsatiladigan tugma nomi, masalan "D"

    static let `default` = HotKeyConfig(keyCode: UInt32(kVK_ANSI_D),
                                        carbonModifiers: UInt32(controlKey | optionKey),
                                        label: "D")

    // Ekranda ko'rinishi, masalan "⌃⌥D"
    var displayString: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + label
    }
}

enum HotKeyStore {
    private static let d = UserDefaults.standard
    static func load() -> HotKeyConfig {
        guard d.object(forKey: "hk.keyCode") != nil else { return .default }
        return HotKeyConfig(keyCode: UInt32(d.integer(forKey: "hk.keyCode")),
                            carbonModifiers: UInt32(d.integer(forKey: "hk.mods")),
                            label: d.string(forKey: "hk.label") ?? "?")
    }
    static func save(_ c: HotKeyConfig) {
        d.set(Int(c.keyCode), forKey: "hk.keyCode")
        d.set(Int(c.carbonModifiers), forKey: "hk.mods")
        d.set(c.label, forKey: "hk.label")
    }
}

// NSEvent modifier'larini Carbon maskasiga o'girish
func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
    var m: UInt32 = 0
    if flags.contains(.control) { m |= UInt32(controlKey) }
    if flags.contains(.option)  { m |= UInt32(optionKey) }
    if flags.contains(.shift)   { m |= UInt32(shiftKey) }
    if flags.contains(.command) { m |= UInt32(cmdKey) }
    return m
}

// keyDown hodisasidan tugmaning ko'rinadigan nomini olish
func keyLabel(for event: NSEvent) -> String {
    let special: [UInt16: String] = [
        UInt16(kVK_Space): "Space", UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Escape): "⎋", UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Home): "↖", UInt16(kVK_End): "↘", UInt16(kVK_PageUp): "⇞", UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
    ]
    if let s = special[event.keyCode] { return s }
    if let c = event.charactersIgnoringModifiers, !c.isEmpty,
       c.rangeOfCharacter(from: .controlCharacters) == nil {
        return c.uppercased()
    }
    return "Key\(event.keyCode)"
}

// MARK: - Global hotkey (Carbon) -> Notification

extension Notification.Name { static let rubaiHotkey = Notification.Name("rubaiHotkey") }

private func hotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ ud: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: .rubaiHotkey, object: nil)
    return noErr
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private var installed = false

    // Hodisa qabul qiluvchini bir marta o'rnatib, hozirgi sozlamani qo'llaydi
    func install() {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let s1 = InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, nil, nil)
            NSLog("[rubai] hotkey handler o'rnatildi: \(s1) (0 = OK)")
            installed = true
        }
        apply(HotKeyStore.load())
    }

    // Eski tugmani bekor qilib, yangisini ro'yxatdan o'tkazadi
    func apply(_ c: HotKeyConfig) {
        if let r = ref { UnregisterEventHotKey(r); ref = nil }
        let id = EventHotKeyID(signature: OSType(0x52535454), id: 1) // 'RSTT'
        let s = RegisterEventHotKey(c.keyCode, c.carbonModifiers, id,
                                    GetApplicationEventTarget(), 0, &ref)
        NSLog("[rubai] hotkey ro'yxatdan o'tkazildi \(c.displayString): \(s) (0 = OK)")
    }
}

// MARK: - Sozlamalar oynasi (yangi tugmani yozib olish)

final class SettingsWindow {
    private var window: NSWindow?
    private var monitor: Any?
    private var recordButton: NSButton!
    private var hintLabel: NSTextField!
    private var current: HotKeyConfig
    private var recording = false
    var onChange: ((HotKeyConfig) -> Void)?

    init(_ c: HotKeyConfig) { current = c }

    func update(_ c: HotKeyConfig) { current = c; refreshButton() }

    func show() {
        if window == nil { build() }
        stopRecording()
        refreshButton()
        NSApp.activate(ignoringOtherApps: true)
        window!.center()
        window!.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "RubaiSTT — Sozlamalar"
        w.isReleasedWhenClosed = false
        let v = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 180))

        let title = NSTextField(labelWithString: "Diktovka tugmasi")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        title.frame = NSRect(x: 24, y: 134, width: 312, height: 20)
        v.addSubview(title)

        recordButton = NSButton(title: current.displayString, target: self, action: #selector(toggleRecord))
        recordButton.bezelStyle = .rounded
        recordButton.font = .systemFont(ofSize: 18, weight: .medium)
        recordButton.frame = NSRect(x: 24, y: 84, width: 312, height: 40)
        v.addSubview(recordButton)

        hintLabel = NSTextField(labelWithString: "Tugmani o'zgartirish uchun bosing.")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .secondaryLabelColor
        hintLabel.frame = NSRect(x: 24, y: 56, width: 312, height: 16)
        v.addSubview(hintLabel)

        let reset = NSButton(title: "Standartga qaytarish (⌃⌥D)", target: self, action: #selector(resetDefault))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 24, y: 16, width: 312, height: 28)
        v.addSubview(reset)

        w.contentView = v
        window = w
    }

    private func refreshButton() {
        recordButton.title = recording ? "Tugmani bosing…" : current.displayString
        hintLabel.stringValue = recording
            ? "Kamida bitta modifier (⌃ ⌥ ⌘ ⇧) + tugma. Bekor qilish: ⎋"
            : "Tugmani o'zgartirish uchun bosing."
    }

    @objc private func toggleRecord() {
        if recording { stopRecording() } else { startRecording() }
        refreshButton()
    }

    @objc private func resetDefault() {
        stopRecording()
        current = .default
        refreshButton()
        onChange?(current)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self else { return event }
            // ⎋ — bekor qilish
            if event.keyCode == UInt16(kVK_Escape) {
                self.stopRecording(); self.refreshButton(); return nil
            }
            let mods = carbonModifiers(from: event.modifierFlags)
            // Kamida bitta modifier shart (aks holda oddiy tugma global qotib qoladi)
            guard mods != 0 else {
                self.hintLabel.stringValue = "Kamida bitta modifier (⌃ ⌥ ⌘ ⇧) kerak!"
                return nil
            }
            let cfg = HotKeyConfig(keyCode: UInt32(event.keyCode),
                                   carbonModifiers: mods,
                                   label: keyLabel(for: event))
            self.current = cfg
            self.stopRecording()
            self.refreshButton()
            self.onChange?(cfg)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let rec = Recorder()
    private let overlay = Overlay()
    private let hotkey = HotKey()
    private var idleTimer: Timer?
    private var hkConfig = HotKeyStore.load()
    private var dictateItem: NSMenuItem!
    private lazy var settings: SettingsWindow = {
        let s = SettingsWindow(hkConfig)
        s.onChange = { [weak self] cfg in self?.applyHotKey(cfg) }
        return s
    }()

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar (Dock'da yo'q)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "rubaiSTT")
        let menu = NSMenu()
        dictateItem = NSMenuItem(title: "Diktovka  (\(hkConfig.displayString))", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(dictateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Sozlamalar…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Accessibility ruxsatini ochish", action: #selector(openAX), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Chiqish", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        hotkey.install()
        NotificationCenter.default.addObserver(self, selector: #selector(toggle), name: .rubaiHotkey, object: nil)

        // Accessibility tekshiruvi (kerak bo'lsa so'raydi)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    // Yangi hotkey'ni qo'llab, saqlab, menyuni yangilaydi
    private func applyHotKey(_ cfg: HotKeyConfig) {
        hkConfig = cfg
        HotKeyStore.save(cfg)
        hotkey.apply(cfg)
        dictateItem.title = "Diktovka  (\(cfg.displayString))"
        settings.update(cfg)
    }

    @objc private func openSettings() { settings.show() }

    @objc private func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggle() {
        NSLog("[rubai] toggle fired, isRecording=\(rec.isRecording)")
        if rec.isRecording {
            let samples = rec.stop()
            NSLog("[rubai] stopped, samples=\(samples.count) (\(Double(samples.count)/16000.0)s)")
            overlay.show("Matnga o'girilmoqda…", recording: false)
            Whisper.shared.transcribe(samples) { [weak self] text in
                NSLog("[rubai] transcription natija: '\(text)' (uzunlik=\(text.count))")
                self?.overlay.hide()
                Inserter.insert(text)
                self?.scheduleIdleUnload()
            }
        } else {
            rec.start { [weak self] ok in
                NSLog("[rubai] record start ok=\(ok)")
                self?.overlay.show(ok ? "Yozilmoqda… (yana \(self?.hkConfig.displayString ?? "⌃⌥D"))" : "Mikrofonga ruxsat yo'q",
                                   recording: ok)
                if !ok { DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self?.overlay.hide() } }
            }
        }
    }

    private func scheduleIdleUnload() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in
            Whisper.shared.unload()   // 3 daqiqa ishlatilmasa RAM bo'shaydi
        }
    }

    @objc private func quit() { rubai_unload(); NSApp.terminate(nil) }
    func applicationWillTerminate(_ n: Notification) { rubai_unload() }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()

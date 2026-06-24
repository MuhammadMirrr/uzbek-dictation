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

// MARK: - Global hotkey (Carbon) -> Notification

extension Notification.Name { static let rubaiHotkey = Notification.Name("rubaiHotkey") }

private func hotkeyHandler(_ next: EventHandlerCallRef?, _ event: EventRef?, _ ud: UnsafeMutableRawPointer?) -> OSStatus {
    NotificationCenter.default.post(name: .rubaiHotkey, object: nil)
    return noErr
}

final class HotKey {
    private var ref: EventHotKeyRef?
    func register() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let s1 = InstallEventHandler(GetApplicationEventTarget(), hotkeyHandler, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x52535454), id: 1) // 'RSTT'
        // ⌃⌥D
        let s2 = RegisterEventHotKey(UInt32(kVK_ANSI_D), UInt32(controlKey | optionKey), id,
                            GetApplicationEventTarget(), 0, &ref)
        NSLog("[rubai] hotkey register: handler=\(s1) hotkey=\(s2) (0 = OK)")
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let rec = Recorder()
    private let overlay = Overlay()
    private let hotkey = HotKey()
    private var idleTimer: Timer?

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory) // menu-bar (Dock'da yo'q)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "rubaiSTT")
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Diktovka  (⌃⌥D)", action: #selector(toggle), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Accessibility ruxsatini ochish", action: #selector(openAX), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Chiqish", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        hotkey.register()
        NotificationCenter.default.addObserver(self, selector: #selector(toggle), name: .rubaiHotkey, object: nil)

        // Accessibility tekshiruvi (kerak bo'lsa so'raydi)
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

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
                self?.overlay.show(ok ? "Yozilmoqda… (yana ⌃⌥D)" : "Mikrofonga ruxsat yo'q",
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

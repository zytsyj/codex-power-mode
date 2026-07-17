import AppKit
import Foundation

private struct PowerState: Decodable {
    let combo: Int?
    let bestCombo: Int?
    let score: Int?
    let mode: String?
    let addedLines: Int?
    let removedLines: Int?
    let verifications: Int?
}

private struct PowerEvent: Decodable {
    let type: String
    let addedLines: Int?
    let removedLines: Int?
    let addedChars: Int?
    let removedChars: Int?
    let category: String?
    let success: Bool?
    let state: PowerState?
}

private struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var life: CGFloat
    let maxLife: CGFloat
    let radius: CGFloat
    let color: NSColor
}

private struct Shockwave {
    let center: CGPoint
    var radius: CGFloat
    var life: CGFloat
    let maxLife: CGFloat
    let width: CGFloat
    let color: NSColor
}

@MainActor
private final class PowerModeView: NSView {
    private var particles: [Particle] = []
    private var shockwaves: [Shockwave] = []
    private var timer: Timer?
    private var state = PowerState(combo: 0, bestCombo: 0, score: 0, mode: "idle", addedLines: 0, removedLines: 0, verifications: 0)
    private var eventText = "POWER MODE ONLINE"
    private var flashAlpha: CGFloat = 0
    private var dangerAlpha: CGFloat = 0
    private var shake: CGFloat = 0
    private var shakePhase: CGFloat = 0
    private let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.environment["CODEX_POWER_MODE_REDUCED_MOTION"] == "1"
    private let edge = ProcessInfo.processInfo.environment["CODEX_POWER_MODE_EDGE"] ?? "top-right"

    override var isOpaque: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    func handle(_ event: PowerEvent) {
        if let nextState = event.state { state = nextState }
        eventText = describe(event)
        flashAlpha = reducedMotion ? 0 : 0.24

        guard !reducedMotion else {
            needsDisplay = true
            return
        }

        switch event.type {
        case "edit":
            let added = event.addedLines ?? 0
            let removed = event.removedLines ?? 0
            let addedChars = event.addedChars ?? added * 24
            let primary = removed > added ? NSColor.systemPink : NSColor.systemPurple
            shake = min(8, 1.5 + CGFloat(added + removed) * 0.12)
            shockwave(color: primary, power: min(1.8, 0.8 + CGFloat(added + removed) / 30))
            burst(color: primary, count: max(18, min(130, added * 3 + removed * 4)), power: 1.0)
            replayTyping(characters: addedChars, lines: added)
            if removed > 0 { deletionSparks(lines: removed) }
        case "verification":
            let passed = event.success == true
            let color: NSColor = passed ? .systemGreen : .systemRed
            shockwave(color: color, power: passed ? 1.8 : 1.1)
            burst(color: color, count: passed ? 140 : 88, power: passed ? 1.35 : 0.9)
            if passed {
                shake = 4
            } else {
                dangerAlpha = 0.38
                shake = 10
            }
        case "turn-stop" where event.state?.mode == "victory":
            shockwave(color: .systemGreen, power: 2.2)
            burst(color: NSColor.systemGreen, count: 180, power: 1.55)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.shockwave(color: .systemPurple, power: 2.0)
                self?.burst(color: .systemPurple, count: 180, power: 1.5)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in
                self?.shockwave(color: .systemCyan, power: 1.8)
                self?.burst(color: .systemCyan, count: 180, power: 1.45)
            }
        default:
            break
        }
        needsDisplay = true
    }

    private func describe(_ event: PowerEvent) -> String {
        switch event.type {
        case "edit": return "CODE SURGE  +\(event.addedLines ?? 0)  −\(event.removedLines ?? 0)"
        case "verification": return "\((event.category ?? "CHECK").uppercased()) \(event.success == true ? "PASSED" : "FAILED")"
        case "turn-stop": return event.state?.mode == "victory" ? "MISSION COMPLETE" : "AWAITING VERIFICATION"
        case "connected": return "POWER MODE ONLINE"
        default: return event.type.uppercased()
        }
    }

    private func hudOrigin(size: CGSize) -> CGPoint {
        let margin: CGFloat = 42
        switch edge {
        case "top-left": return CGPoint(x: margin, y: bounds.height - size.height - margin)
        case "bottom-left": return CGPoint(x: margin, y: margin)
        case "bottom-right": return CGPoint(x: bounds.width - size.width - margin, y: margin)
        case "center": return CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        default: return CGPoint(x: bounds.width - size.width - margin, y: bounds.height - size.height - margin)
        }
    }

    private func codingOrigin() -> CGPoint {
        CGPoint(
            x: bounds.width * CGFloat.random(in: 0.28...0.76),
            y: bounds.height * CGFloat.random(in: 0.24...0.72)
        )
    }

    private func replayTyping(characters: Int, lines: Int) {
        let pulses = max(4, min(32, max(lines, characters / 22)))
        for index in 0..<pulses {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.028) { [weak self] in
                self?.typingPulse(index: index)
            }
        }
    }

    private func typingPulse(index: Int) {
        guard !reducedMotion else { return }
        let origin = codingOrigin()
        let color: NSColor = index.isMultiple(of: 4) ? .systemPurple : .systemCyan
        for _ in 0..<Int.random(in: 4...8) {
            let life = CGFloat.random(in: 22...48)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: 1.4...5.8), dy: CGFloat.random(in: -2.8...3.6)),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.1...3.1),
                color: color
            ))
        }
        needsDisplay = true
    }

    private func deletionSparks(lines: Int) {
        let count = min(90, max(12, lines * 6))
        let origin = codingOrigin()
        for _ in 0..<count {
            let life = CGFloat.random(in: 28...62)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: -6.5 ... -1.2), dy: CGFloat.random(in: -4...4)),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.2...3.8),
                color: .systemPink
            ))
        }
    }

    private func shockwave(color: NSColor, power: CGFloat) {
        guard !reducedMotion else { return }
        let life: CGFloat = 34
        shockwaves.append(Shockwave(
            center: codingOrigin(),
            radius: 8,
            life: life,
            maxLife: life,
            width: 2.2 * power,
            color: color
        ))
    }

    private func burst(color: NSColor, count: Int, power: CGFloat) {
        let hudSize = CGSize(width: 320, height: 170)
        let origin = hudOrigin(size: hudSize)
        let center = CGPoint(x: origin.x + hudSize.width * 0.54, y: origin.y + hudSize.height * 0.5)
        for _ in 0..<min(count, 220) {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 1.7...7.5) * power
            let life = CGFloat.random(in: 42...98)
            particles.append(Particle(
                position: center,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed + 1.2),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.5...4.5),
                color: color
            ))
        }
    }

    private func tick() {
        if !particles.isEmpty {
            for index in particles.indices {
                particles[index].position.x += particles[index].velocity.dx
                particles[index].position.y += particles[index].velocity.dy
                particles[index].velocity.dy -= 0.065
                particles[index].velocity.dx *= 0.992
                particles[index].life -= 1
            }
            particles.removeAll { $0.life <= 0 }
        }
        if !shockwaves.isEmpty {
            for index in shockwaves.indices {
                shockwaves[index].radius += 5.4
                shockwaves[index].life -= 1
            }
            shockwaves.removeAll { $0.life <= 0 }
        }
        flashAlpha = max(0, flashAlpha - 0.012)
        dangerAlpha = max(0, dangerAlpha - 0.009)
        shake = max(0, shake * 0.88 - 0.04)
        shakePhase += 1
        if !particles.isEmpty || !shockwaves.isEmpty || flashAlpha > 0 || dangerAlpha > 0 || shake > 0 { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        context.setBlendMode(.screen)
        for wave in shockwaves {
            let progress = wave.life / wave.maxLife
            context.setStrokeColor(wave.color.withAlphaComponent(progress * 0.8).cgColor)
            context.setLineWidth(wave.width * progress)
            context.strokeEllipse(in: CGRect(
                x: wave.center.x - wave.radius,
                y: wave.center.y - wave.radius,
                width: wave.radius * 2,
                height: wave.radius * 2
            ))
        }
        for particle in particles {
            context.setFillColor(particle.color.withAlphaComponent(min(1, particle.life / min(24, particle.maxLife))).cgColor)
            context.fillEllipse(in: CGRect(
                x: particle.position.x - particle.radius,
                y: particle.position.y - particle.radius,
                width: particle.radius * 2,
                height: particle.radius * 2
            ))
        }
        context.setBlendMode(.normal)

        if flashAlpha > 0 {
            context.setFillColor(NSColor.white.withAlphaComponent(flashAlpha).cgColor)
            context.fill(bounds)
        }
        if dangerAlpha > 0 {
            let inset = bounds.insetBy(dx: 2, dy: 2)
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(dangerAlpha).cgColor)
            context.setLineWidth(10)
            context.stroke(inset)
        }
        drawHUD()
    }

    private func drawHUD() {
        let size = CGSize(width: 320, height: 170)
        let baseOrigin = hudOrigin(size: size)
        let offset = reducedMotion ? CGPoint.zero : CGPoint(
            x: sin(shakePhase * 2.31) * shake,
            y: cos(shakePhase * 1.73) * shake * 0.55
        )
        let origin = CGPoint(x: baseOrigin.x + offset.x, y: baseOrigin.y + offset.y)
        let rect = CGRect(origin: origin, size: size)
        let mode = (state.mode ?? "idle").uppercased()
        let modeColor: NSColor = mode == "DANGER" ? .systemRed : mode == "VICTORY" ? .systemGreen : .systemCyan

        let path = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 20)
        NSColor.black.withAlphaComponent(0.58).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawText("CODEX POWER MODE", at: CGPoint(x: origin.x + 22, y: origin.y + 138), font: .monospacedSystemFont(ofSize: 11, weight: .semibold), color: NSColor.white.withAlphaComponent(0.7), tracking: 2.1)
        drawText(mode, at: CGPoint(x: origin.x + 22, y: origin.y + 108), font: .monospacedSystemFont(ofSize: 13, weight: .bold), color: modeColor, tracking: 2.7)
        drawText("\(state.combo ?? 0)", at: CGPoint(x: origin.x + 20, y: origin.y + 44), font: .systemFont(ofSize: 54, weight: .black), color: .white)
        drawText("COMBO", at: CGPoint(x: origin.x + 128, y: origin.y + 73), font: .monospacedSystemFont(ofSize: 11, weight: .medium), color: NSColor.white.withAlphaComponent(0.45), tracking: 1.5)
        drawText(eventText, at: CGPoint(x: origin.x + 22, y: origin.y + 20), font: .monospacedSystemFont(ofSize: 10, weight: .medium), color: NSColor.white.withAlphaComponent(0.62), tracking: 0.8)
        drawText("BEST \(state.bestCombo ?? 0)   SCORE \(state.score ?? 0)", at: CGPoint(x: origin.x + 188, y: origin.y + 21), font: .monospacedSystemFont(ofSize: 9, weight: .regular), color: NSColor.white.withAlphaComponent(0.42))
    }

    private func drawText(_ text: String, at point: CGPoint, font: NSFont, color: NSColor, tracking: CGFloat = 0) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .kern: tracking
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: point)
    }
}

private final class EventStream: NSObject, URLSessionDataDelegate {
    private let url: URL
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = ""
    private var stopped = false
    var onEvent: (@MainActor (PowerEvent) -> Void)?

    init(url: URL) { self.url = url }

    func start() {
        stopped = false
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 86_400
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        stopped = true
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer += chunk.replacingOccurrences(of: "\r\n", with: "\n")
        while let boundary = buffer.range(of: "\n\n") {
            let frame = String(buffer[..<boundary.lowerBound])
            buffer.removeSubrange(buffer.startIndex..<boundary.upperBound)
            let payload = frame.split(separator: "\n")
                .filter { $0.hasPrefix("data:") }
                .map { $0.dropFirst(5).trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
            guard let json = payload.data(using: .utf8), let event = try? JSONDecoder().decode(PowerEvent.self, from: json) else { continue }
            Task { @MainActor [weak self] in self?.onEvent?(event) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !stopped else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.start() }
    }
}

@MainActor
private final class CodexWindowTracker {
    private weak var panel: NSPanel?
    private var timer: Timer?
    private var lastFrame = CGRect.zero
    private let bundleIdentifier = "com.openai.codex"
    private let followWhenInactive = ProcessInfo.processInfo.environment["CODEX_POWER_MODE_FOLLOW_WHEN_INACTIVE"] == "1"

    init(panel: NSPanel) {
        self.panel = panel
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    private func refresh() {
        guard let panel else { return }
        guard followWhenInactive || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier else {
            panel.orderOut(nil)
            return
        }
        guard let frame = codexWindowFrame(), frame.width > 400, frame.height > 300 else {
            panel.orderOut(nil)
            return
        }
        if !frame.equalTo(lastFrame) {
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
            lastFrame = frame
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    private func codexWindowFrame() -> CGRect? {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return nil }
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates = rawWindows.compactMap { info -> CGRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == Int(application.processIdentifier) else { return nil }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0 else { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return cocoaFrame(fromQuartz: quartzFrame)
        }
        return candidates
            .filter { $0.width > 400 && $0.height > 300 }
            .max { ($0.width * $0.height) < ($1.width * $1.height) }
    }

    private func cocoaFrame(fromQuartz frame: CGRect) -> CGRect {
        let mainTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CGRect(x: frame.origin.x, y: mainTop - frame.origin.y - frame.height, width: frame.width, height: frame.height)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private var stream: EventStream?
    private var tracker: CodexWindowTracker?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { NSApp.terminate(nil); return }

        let panel = NSPanel(
            contentRect: CGRect(origin: screen.frame.origin, size: CGSize(width: 900, height: 700)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.contentView = PowerModeView(frame: CGRect(origin: .zero, size: CGSize(width: 900, height: 700)))
        window = panel
        tracker = CodexWindowTracker(panel: panel)

        let endpoint = environment["CODEX_POWER_MODE_URL"] ?? "http://127.0.0.1:4737/api/stream"
        guard let url = URL(string: endpoint), let view = panel.contentView as? PowerModeView else { return }
        let client = EventStream(url: url)
        client.onEvent = { [weak view] event in view?.handle(event) }
        client.start()
        stream = client
    }

    func applicationWillTerminate(_ notification: Notification) { stream?.stop() }
}

@main
private struct PowerModeOverlayApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

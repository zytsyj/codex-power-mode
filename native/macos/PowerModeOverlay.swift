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

@MainActor
private final class PowerModeView: NSView {
    private var particles: [Particle] = []
    private var timer: Timer?
    private var state = PowerState(combo: 0, bestCombo: 0, score: 0, mode: "idle", addedLines: 0, removedLines: 0, verifications: 0)
    private var eventText = "POWER MODE ONLINE"
    private var flashAlpha: CGFloat = 0
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
            let primary = removed > added ? NSColor.systemPink : NSColor.systemPurple
            burst(color: primary, count: max(18, min(150, added * 5 + removed * 3)), power: 1.0)
            if added > 0 { burst(color: NSColor.systemCyan, count: min(80, added * 3), power: 0.68) }
        case "verification":
            let passed = event.success == true
            burst(color: passed ? NSColor.systemGreen : NSColor.systemRed, count: passed ? 120 : 72, power: passed ? 1.3 : 0.85)
        case "turn-stop" where event.state?.mode == "victory":
            burst(color: NSColor.systemGreen, count: 180, power: 1.55)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in self?.burst(color: .systemPurple, count: 180, power: 1.5) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.36) { [weak self] in self?.burst(color: .systemCyan, count: 180, power: 1.45) }
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
        flashAlpha = max(0, flashAlpha - 0.012)
        if !particles.isEmpty || flashAlpha > 0 { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        context.setBlendMode(.screen)
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
        drawHUD()
    }

    private func drawHUD() {
        let size = CGSize(width: 320, height: 170)
        let origin = hudOrigin(size: size)
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
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private var stream: EventStream?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = ProcessInfo.processInfo.environment
        let displayIndex = Int(environment["CODEX_POWER_MODE_DISPLAY"] ?? "0") ?? 0
        let screens = NSScreen.screens
        guard !screens.isEmpty else { NSApp.terminate(nil); return }
        let screen = screens[min(max(displayIndex, 0), screens.count - 1)]

        let panel = NSPanel(
            contentRect: screen.frame,
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
        panel.contentView = PowerModeView(frame: CGRect(origin: .zero, size: screen.frame.size))
        panel.orderFrontRegardless()
        window = panel

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

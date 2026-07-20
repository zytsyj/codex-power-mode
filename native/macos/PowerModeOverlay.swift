import AppKit
import Foundation

private struct PowerState: Decodable {
    let phase: String?
    let status: String?
    let momentum: Int?
    let bestMomentum: Int?
    let confidence: Int?
    let riskLevel: String?
    let currentActivity: String?
    let completion: String?
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
    let phase: String?
    let state: PowerState?
}

private struct Particle {
    var position: CGPoint
    var velocity: CGVector
    var life: CGFloat
    let maxLife: CGFloat
    let radius: CGFloat
    let color: NSColor
    var target: CGPoint? = nil
    var square = false
}

private struct Shockwave {
    let center: CGPoint
    var radius: CGFloat
    var life: CGFloat
    let maxLife: CGFloat
    let width: CGFloat
    let color: NSColor
}

private struct ScanBeam {
    let origin: CGPoint
    let length: CGFloat
    var life: CGFloat
    let maxLife: CGFloat
    let color: NSColor
}

@MainActor
private final class PowerModeView: NSView {
    private var particles: [Particle] = []
    private var shockwaves: [Shockwave] = []
    private var scanBeams: [ScanBeam] = []
    private var timer: Timer?
    private var state = PowerState(phase: "observe", status: "ready", momentum: 0, bestMomentum: 0, confidence: 0, riskLevel: "low", currentActivity: "Waiting for Codex activity", completion: nil, addedLines: 0, removedLines: 0, verifications: 0)
    private var eventText = "POWER MODE ONLINE"
    private var flashAlpha: CGFloat = 0
    private var dangerAlpha: CGFloat = 0
    private var shake: CGFloat = 0
    private var shakePhase: CGFloat = 0
    private var hudExpandedUntil = Date.distantPast
    private var hudWasExpanded = false
    private let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || ProcessInfo.processInfo.environment["CODEX_POWER_MODE_REDUCED_MOTION"] == "1"
    private let arcadeMode = ProcessInfo.processInfo.environment["CODEX_POWER_MODE_PRESET"] == "arcade"
    private let hudScale: CGFloat = {
        guard let raw = ProcessInfo.processInfo.environment["CODEX_POWER_MODE_SCALE"], let value = Double(raw) else { return 1.3 }
        return CGFloat(min(1.6, max(0.75, value)))
    }()
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
        if event.type == "connected" {
            needsDisplay = true
            return
        }
        let duration: TimeInterval = event.type == "permission-request" || (event.type == "verification" && event.success != true) ? 8 : event.type == "turn-stop" ? 3.2 : 2.2
        hudExpandedUntil = Date().addingTimeInterval(duration)
        flashAlpha = reducedMotion ? 0 : 0.24

        guard !reducedMotion else {
            needsDisplay = true
            return
        }

        switch event.type {
        case "activity-start":
            if event.phase == "observe" {
                scan(color: .systemCyan)
            } else if event.phase == "verify" {
                charge(color: .systemGreen, count: arcadeMode ? 100 : 58)
            } else {
                directionalSparks(color: .systemPurple, count: arcadeMode ? 48 : 26)
            }
        case "permission-request":
            shockwave(color: .systemYellow, power: 1.0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.shockwave(color: .systemYellow, power: 0.8)
            }
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
                fragments(color: .systemRed, count: arcadeMode ? 120 : 72)
                dangerAlpha = 0.38
                shake = 10
            }
        case "turn-stop" where event.state?.completion == "verified":
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
        case "activity-start": return event.phase == "observe" ? "READING CONTEXT" : event.phase == "verify" ? "BUILDING EVIDENCE" : "STARTING TOOL"
        case "permission-request": return "WAITING FOR YOUR APPROVAL"
        case "edit": return "CHANGE APPLIED  +\(event.addedLines ?? 0)  −\(event.removedLines ?? 0)"
        case "verification": return "\((event.category ?? "CHECK").uppercased()) \(event.success == true ? "PASSED" : "FAILED")"
        case "turn-stop": return event.state?.completion == "verified" ? "COMPLETED WITH EVIDENCE" : "VERIFICATION RECOMMENDED"
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
        let base = max(4, min(32, max(lines, characters / 22)))
        let pulses = arcadeMode ? min(44, Int(Double(base) * 1.45)) : base
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

    private func scan(color: NSColor, echo: Bool = true) {
        guard !reducedMotion else { return }
        let origin = CGPoint(x: bounds.width * 0.17, y: bounds.height * CGFloat.random(in: 0.28...0.72))
        let life: CGFloat = 52
        scanBeams.append(ScanBeam(origin: origin, length: bounds.width * 0.55, life: life, maxLife: life, color: color))
        if arcadeMode && echo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in self?.scan(color: color.withAlphaComponent(0.7), echo: false) }
        }
    }

    private func directionalSparks(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let origin = codingOrigin()
        for _ in 0..<count {
            let life = CGFloat.random(in: 24...52)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: 2.2...7.4), dy: CGFloat.random(in: -3.2...3.2)),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.0...2.8),
                color: color
            ))
        }
    }

    private func charge(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let target = codingOrigin()
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 70...190)
            let life = CGFloat.random(in: 38...58)
            particles.append(Particle(
                position: CGPoint(x: target.x + cos(angle) * distance, y: target.y + sin(angle) * distance),
                velocity: .zero,
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.0...2.5),
                color: color,
                target: target
            ))
        }
    }

    private func fragments(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let origin = codingOrigin()
        for _ in 0..<count {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 2.5...8.5)
            let life = CGFloat.random(in: 28...58)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: cos(angle) * speed, dy: sin(angle) * speed),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.8...4.2),
                color: color,
                square: true
            ))
        }
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
        let scaledCount = arcadeMode ? Int(Double(count) * 1.55) : count
        for _ in 0..<min(scaledCount, 280) {
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
        let particleBudget = arcadeMode ? 560 : 280
        let shockwaveBudget = arcadeMode ? 18 : 10
        let scanBudget = arcadeMode ? 8 : 4
        if particles.count > particleBudget { particles.removeFirst(particles.count - particleBudget) }
        if shockwaves.count > shockwaveBudget { shockwaves.removeFirst(shockwaves.count - shockwaveBudget) }
        if scanBeams.count > scanBudget { scanBeams.removeFirst(scanBeams.count - scanBudget) }
        if !particles.isEmpty {
            for index in particles.indices {
                if let target = particles[index].target {
                    particles[index].velocity.dx = (target.x - particles[index].position.x) * 0.075
                    particles[index].velocity.dy = (target.y - particles[index].position.y) * 0.075
                } else {
                    particles[index].velocity.dy -= 0.065
                    particles[index].velocity.dx *= 0.992
                }
                particles[index].position.x += particles[index].velocity.dx
                particles[index].position.y += particles[index].velocity.dy
                particles[index].life -= 1
            }
            particles.removeAll { $0.life <= 0 }
        }
        if !scanBeams.isEmpty {
            for index in scanBeams.indices { scanBeams[index].life -= 1 }
            scanBeams.removeAll { $0.life <= 0 }
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
        let hudIsExpanded = Date() < hudExpandedUntil
        if hudIsExpanded != hudWasExpanded {
            hudWasExpanded = hudIsExpanded
            needsDisplay = true
        }
        if !particles.isEmpty || !shockwaves.isEmpty || !scanBeams.isEmpty || flashAlpha > 0 || dangerAlpha > 0 || shake > 0 || hudIsExpanded { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        context.setBlendMode(.screen)
        for beam in scanBeams {
            let progress = 1 - beam.life / beam.maxLife
            let head = beam.origin.x + beam.length * progress
            let alpha = sin(progress * .pi) * 0.7
            context.setStrokeColor(beam.color.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(1.5)
            context.move(to: CGPoint(x: head - 120, y: beam.origin.y))
            context.addLine(to: CGPoint(x: head, y: beam.origin.y))
            context.strokePath()
            context.move(to: CGPoint(x: head, y: beam.origin.y - 16))
            context.addLine(to: CGPoint(x: head, y: beam.origin.y + 16))
            context.strokePath()
        }
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
            let rect = CGRect(x: particle.position.x - particle.radius, y: particle.position.y - particle.radius, width: particle.radius * 2, height: particle.radius * 2)
            if particle.square { context.fill(rect) } else { context.fillEllipse(in: rect) }
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
        let expanded = Date() < hudExpandedUntil
        let baseSize = expanded ? CGSize(width: 258, height: 64) : CGSize(width: 60, height: 60)
        let size = CGSize(width: baseSize.width * hudScale, height: baseSize.height * hudScale)
        let baseOrigin = hudOrigin(size: size)
        let offset = reducedMotion ? CGPoint.zero : CGPoint(
            x: sin(shakePhase * 2.31) * shake,
            y: cos(shakePhase * 1.73) * shake * 0.55
        )
        let screenOrigin = CGPoint(x: baseOrigin.x + offset.x, y: baseOrigin.y + offset.y)
        let phase = (state.phase ?? "observe").uppercased()
        let phaseColor: NSColor = phase == "RECOVER" ? .systemRed : phase == "VERIFY" || (phase == "COMPLETE" && state.completion == "verified") ? .systemGreen : phase == "WAIT" ? .systemYellow : phase == "ACT" ? .systemPurple : .systemCyan
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: screenOrigin.x, y: screenOrigin.y)
        context.scaleBy(x: hudScale, y: hudScale)
        let origin = CGPoint.zero

        if phase == "WAIT" { drawWaitSignal(around: origin, color: phaseColor) }
        if phase == "RECOVER" { drawRecoverSignal(around: origin, color: phaseColor) }

        let coreRect = CGRect(x: origin.x, y: origin.y, width: 60, height: 60)
        let core = NSBezierPath(ovalIn: coreRect)
        NSColor(calibratedWhite: 0.035, alpha: 0.88).setFill()
        core.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        core.lineWidth = 2
        core.stroke()

        let momentum = min(100, max(0, state.momentum ?? 0))
        let progress = CGFloat(momentum) / 100
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: origin.x + 30, y: origin.y + 30), radius: 29, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = 2.5
        arc.lineCapStyle = .round
        phaseColor.setStroke()
        arc.stroke()

        let value = "\(momentum)"
        drawText(value, at: CGPoint(x: origin.x + (value.count > 2 ? 11 : 17), y: origin.y + 24), font: .systemFont(ofSize: 25, weight: .black), color: .white)
        drawText("POWER", at: CGPoint(x: origin.x + 17, y: origin.y + 11), font: .monospacedSystemFont(ofSize: 5.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.58), tracking: 1.0)
        if phase == "COMPLETE" && state.completion == "verified" { drawCompleteSignal(around: origin) }
        if expanded {
            let copyRect = CGRect(x: origin.x + 69, y: origin.y + 2, width: 189, height: 56)
            let copy = NSBezierPath(roundedRect: copyRect, xRadius: 12, yRadius: 12)
            NSColor(calibratedWhite: 0.025, alpha: 0.86).setFill()
            copy.fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            copy.lineWidth = 1
            copy.stroke()
            drawText(phase, at: CGPoint(x: origin.x + 82, y: origin.y + 40), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: phaseColor, tracking: 1.2)
            drawText(String(eventText.prefix(25)), at: CGPoint(x: origin.x + 82, y: origin.y + 22), font: .systemFont(ofSize: 11, weight: .semibold), color: .white)
            drawText("CONF \(state.confidence ?? 0)%  ·  \((state.riskLevel ?? "low").uppercased()) RISK", at: CGPoint(x: origin.x + 82, y: origin.y + 8), font: .monospacedSystemFont(ofSize: 6.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.58), tracking: 0.55)
        }
        context.restoreGState()
    }

    private func drawWaitSignal(around origin: CGPoint, color: NSColor) {
        let oscillation = reducedMotion ? 0 : sin(shakePhase * 0.095)
        let pulse = 0.62 + (oscillation + 1) * 0.19
        let reach = 4 + (oscillation + 1) * 2
        color.withAlphaComponent(pulse).setStroke()
        let gates = NSBezierPath()
        gates.move(to: CGPoint(x: origin.x - reach + 4, y: origin.y + 11))
        gates.line(to: CGPoint(x: origin.x - reach, y: origin.y + 11))
        gates.line(to: CGPoint(x: origin.x - reach, y: origin.y + 49))
        gates.line(to: CGPoint(x: origin.x - reach + 4, y: origin.y + 49))
        gates.move(to: CGPoint(x: origin.x + 56 + reach, y: origin.y + 11))
        gates.line(to: CGPoint(x: origin.x + 60 + reach, y: origin.y + 11))
        gates.line(to: CGPoint(x: origin.x + 60 + reach, y: origin.y + 49))
        gates.line(to: CGPoint(x: origin.x + 56 + reach, y: origin.y + 49))
        gates.lineWidth = 2
        gates.lineCapStyle = .round
        gates.lineJoinStyle = .round
        gates.stroke()

        color.withAlphaComponent(1 - pulse * 0.45).setFill()
        for y in [CGFloat(4), CGFloat(56)] {
            let marker = NSBezierPath()
            marker.move(to: CGPoint(x: origin.x + 30, y: origin.y + y))
            marker.line(to: CGPoint(x: origin.x + 33, y: origin.y + y + 3))
            marker.line(to: CGPoint(x: origin.x + 30, y: origin.y + y + 6))
            marker.line(to: CGPoint(x: origin.x + 27, y: origin.y + y + 3))
            marker.close()
            marker.fill()
        }
    }

    private func drawRecoverSignal(around origin: CGPoint, color: NSColor) {
        let oscillation = reducedMotion ? 0 : sin(shakePhase * 0.075)
        let rotation = oscillation * 7
        let center = CGPoint(x: origin.x + 30, y: origin.y + 30)
        color.withAlphaComponent(0.72 + oscillation * 0.16).setStroke()
        for (index, angles) in [(14.0, 62.0), (88.0, 139.0), (166.0, 224.0), (252.0, 333.0)].enumerated() {
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let segment = NSBezierPath()
            segment.appendArc(
                withCenter: center,
                radius: 35 + direction * oscillation * 1.5,
                startAngle: CGFloat(angles.0) + rotation * direction,
                endAngle: CGFloat(angles.1) + rotation * direction
            )
            segment.lineWidth = 2
            segment.lineCapStyle = .square
            segment.stroke()
        }

        color.withAlphaComponent(0.48).setStroke()
        let seam = NSBezierPath()
        seam.move(to: CGPoint(x: origin.x + 19 + oscillation, y: origin.y + 11))
        seam.line(to: CGPoint(x: origin.x + 28, y: origin.y + 25))
        seam.line(to: CGPoint(x: origin.x + 25, y: origin.y + 31))
        seam.line(to: CGPoint(x: origin.x + 40 - oscillation, y: origin.y + 50))
        seam.lineWidth = 1.4
        seam.lineCapStyle = .square
        seam.stroke()
    }

    private func drawCompleteSignal(around origin: CGPoint) {
        let center = CGPoint(x: origin.x + 30, y: origin.y + 30)
        let rotation = reducedMotion ? 0 : shakePhase * 0.18
        let colors: [NSColor] = [.systemGreen, .systemPurple, .systemCyan]
        for (index, color) in colors.enumerated() {
            let start = CGFloat(index) * 120 + rotation
            let ribbon = NSBezierPath()
            ribbon.appendArc(withCenter: center, radius: 35, startAngle: start + 4, endAngle: start + 112)
            ribbon.lineWidth = 2
            ribbon.lineCapStyle = .round
            color.withAlphaComponent(0.9).setStroke()
            ribbon.stroke()
        }

        let check = NSBezierPath()
        check.move(to: CGPoint(x: origin.x + 46, y: origin.y + 14))
        check.line(to: CGPoint(x: origin.x + 50, y: origin.y + 10))
        check.line(to: CGPoint(x: origin.x + 58, y: origin.y + 20))
        check.lineWidth = 2.4
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(calibratedRed: 0.78, green: 1, blue: 0.9, alpha: 1).setStroke()
        check.stroke()
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

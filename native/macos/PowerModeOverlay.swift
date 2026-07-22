import AppKit
import ApplicationServices
import Foundation
import QuartzCore

private func resolvedHudPlacementBounds(viewBounds: CGRect, visibleBounds: CGRect?, safeMargin: CGFloat = 12) -> CGRect {
    var available = viewBounds
    if let visibleBounds {
        let intersection = viewBounds.intersection(visibleBounds)
        if !intersection.isNull, intersection.width >= 48, intersection.height >= 48 {
            available = intersection
        }
    }
    let inset = available.insetBy(dx: safeMargin, dy: safeMargin)
    return inset.width > 0 && inset.height > 0 ? inset : available
}

private enum TrackedWindowTarget: Equatable {
    case hidden
    case codex
    case frontmost
}

private func trackedWindowTarget(codexIsFrontmost: Bool, inactiveBehavior: String) -> TrackedWindowTarget {
    if codexIsFrontmost { return .codex }
    switch inactiveBehavior {
    case "stay": return .codex
    case "follow": return .frontmost
    default: return .hidden
    }
}

private func idleGraceIsActive(now: Date, settledAt: Date?, delay: TimeInterval) -> Bool {
    guard let settledAt, delay > 0 else { return false }
    return now < settledAt.addingTimeInterval(delay)
}

private func isUsableCaretBounds(_ bounds: CGRect) -> Bool {
    guard !bounds.isNull,
          bounds.origin.x.isFinite, bounds.origin.y.isFinite,
          bounds.width.isFinite, bounds.height.isFinite,
          bounds.width >= 0, bounds.height >= 0 else { return false }
    // Chromium commonly exposes a collapsed insertion range as a zero-width
    // rectangle. CGRect.isEmpty rejects that valid caret even when its height
    // is the exact editor line height.
    return bounds.width > 0 || bounds.height > 0
}

private func runPlacementGeometrySelfTest() {
    let view = CGRect(x: 0, y: 0, width: 900, height: 700)
    precondition(resolvedHudPlacementBounds(viewBounds: view, visibleBounds: nil) == CGRect(x: 12, y: 12, width: 876, height: 676))
    precondition(
        resolvedHudPlacementBounds(viewBounds: view, visibleBounds: CGRect(x: -100, y: 0, width: 700, height: 650))
            == CGRect(x: 12, y: 12, width: 576, height: 626)
    )
    precondition(
        resolvedHudPlacementBounds(viewBounds: view, visibleBounds: CGRect(x: 880, y: 680, width: 40, height: 40))
            == CGRect(x: 12, y: 12, width: 876, height: 676)
    )
    precondition(trackedWindowTarget(codexIsFrontmost: true, inactiveBehavior: "hide") == .codex)
    precondition(trackedWindowTarget(codexIsFrontmost: false, inactiveBehavior: "hide") == .hidden)
    precondition(trackedWindowTarget(codexIsFrontmost: false, inactiveBehavior: "stay") == .codex)
    precondition(trackedWindowTarget(codexIsFrontmost: false, inactiveBehavior: "follow") == .frontmost)
    let settledAt = Date(timeIntervalSince1970: 1_000)
    precondition(!idleGraceIsActive(now: settledAt, settledAt: settledAt, delay: 0))
    precondition(idleGraceIsActive(now: settledAt.addingTimeInterval(1.9), settledAt: settledAt, delay: 2))
    precondition(!idleGraceIsActive(now: settledAt.addingTimeInterval(2), settledAt: settledAt, delay: 2))
    precondition(isUsableCaretBounds(CGRect(x: 120, y: 240, width: 0, height: 19)))
    precondition(!isUsableCaretBounds(.zero))
    fputs("HUD placement, inactive behavior, and auto-hide self-test passed\n", stdout)
}

@MainActor
private func runEnergyRenderQA(directory: String) {
    let destination = URL(fileURLWithPath: directory, isDirectory: true)
    try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    let tiers = [45, 170, 340, 580, 820, 960, 999]
    let variants: [(name: String, preset: String, reduced: Bool)] = [
        ("focus", "focus", false),
        ("arcade", "arcade", false),
        ("reduced", "focus", true)
    ]
    func writeFrame(host: CALayer, filename: String) {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 180,
            pixelsHigh: 180,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        host.render(in: context.cgContext)
        NSGraphicsContext.restoreGraphicsState()
        let file = destination.appendingPathComponent(filename)
        if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: file, options: .atomic) }
    }
    func renderFrame(variant: (name: String, preset: String, reduced: Bool), dark: Bool, phase: String, momentum: Int, completion: String? = nil, filename: String) {
        let preferences = PowerModePreferences(environment: [:])
        preferences.setPreset(variant.preset)
        if variant.reduced { preferences.toggleReducedMotion() }
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        host.backgroundColor = (dark ? NSColor(calibratedWhite: 0.055, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).cgColor
        let renderer = OrbLayerRenderer(hostLayer: host, preferences: preferences)
        renderer.layout(in: CGRect(x: 44, y: 44, width: 92, height: 92))
        let completionJSON = completion.map { ",\"completion\":\"\($0)\"" } ?? ""
        let stateJSON = "{\"phase\":\"\(phase)\",\"status\":\"working\",\"momentum\":\(momentum),\"bestMomentum\":999,\"currentActivity\":\"Semantic QA\",\"sessionId\":\"qa\"\(completionJSON)}"
        guard let state = try? JSONDecoder().decode(PowerState.self, from: Data(stateJSON.utf8)) else { return }
        renderer.apply(
            state: state,
            presentation: (phase: phase, status: "working", momentum: momentum, idle: false, settled: false, returning: false, settledAt: nil),
            label: phase.uppercased()
        )
        renderer.setVisible(true, animated: false)
        writeFrame(host: host, filename: filename)
    }
    func renderTierTransitionFrame(variant: (name: String, preset: String, reduced: Bool), dark: Bool, from previous: Int, to next: Int, filename: String) {
        let preferences = PowerModePreferences(environment: [:])
        preferences.setPreset(variant.preset)
        if variant.reduced { preferences.toggleReducedMotion() }
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        host.backgroundColor = (dark ? NSColor(calibratedWhite: 0.055, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).cgColor
        let renderer = OrbLayerRenderer(hostLayer: host, preferences: preferences)
        renderer.layout(in: CGRect(x: 44, y: 44, width: 92, height: 92))
        func state(_ momentum: Int) -> PowerState? {
            let json = "{\"phase\":\"act\",\"status\":\"working\",\"momentum\":\(momentum),\"bestMomentum\":999,\"currentActivity\":\"Tier transition QA\",\"sessionId\":\"qa\"}"
            return try? JSONDecoder().decode(PowerState.self, from: Data(json.utf8))
        }
        guard let previousState = state(previous), let nextState = state(next) else { return }
        renderer.apply(state: previousState, presentation: (phase: "act", status: "working", momentum: previous, idle: false, settled: false, returning: false, settledAt: nil), label: "ACT")
        renderer.apply(state: nextState, presentation: (phase: "act", status: "working", momentum: next, idle: false, settled: false, returning: false, settledAt: nil), label: "ACT")
        renderer.setVisible(true, animated: false)
        writeFrame(host: host, filename: filename)
    }
    for variant in variants {
        for dark in [false, true] {
            let theme = dark ? "dark" : "light"
            for momentum in tiers {
                renderFrame(variant: variant, dark: dark, phase: "act", momentum: momentum, filename: "\(variant.name)-\(theme)-\(momentum).png")
            }
            for phase in ["observe", "act", "verify", "wait", "recover", "complete"] {
                for momentum in [45, 580, 960] {
                    renderFrame(
                        variant: variant,
                        dark: dark,
                        phase: phase,
                        momentum: momentum,
                        completion: phase == "complete" ? "verified" : nil,
                        filename: "matrix-\(variant.name)-\(theme)-\(phase)-\(momentum).png"
                    )
                }
            }
            for completion in ["verified", "unverified", "cancelled", "no-change"] {
                renderFrame(
                    variant: variant,
                    dark: dark,
                    phase: "complete",
                    momentum: 820,
                    completion: completion,
                    filename: "complete-\(variant.name)-\(theme)-\(completion).png"
                )
            }
            for crossing in [(from: 580, to: 820, label: "overload"), (from: 820, to: 960, label: "critical"), (from: 960, to: 999, label: "peak")] {
                renderTierTransitionFrame(
                    variant: variant,
                    dark: dark,
                    from: crossing.from,
                    to: crossing.to,
                    filename: "transition-\(variant.name)-\(theme)-\(crossing.label).png"
                )
            }
            for cursorSample in [(effect: "spark", count: 12, label: "spark"), (effect: "neon", count: 12, label: "neon"), (effect: "neon", count: 20, label: "neon-milestone")] {
                let preferences = PowerModePreferences(environment: [:])
                preferences.setPreset(variant.preset)
                preferences.setCursorEffect(cursorSample.effect)
                if variant.reduced { preferences.toggleReducedMotion() }
                let host = CALayer()
                host.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
                host.backgroundColor = (dark ? NSColor(calibratedWhite: 0.055, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).cgColor
                let typing = TypingFeedbackRenderer(hostLayer: host, preferences: preferences)
                typing.layout(in: host.bounds, beside: CGRect(x: 120, y: 60, width: 60, height: 60))
                typing.emitCursorEffect(at: CGPoint(x: 90, y: 90), count: cursorSample.count)
                writeFrame(host: host, filename: "cursor-\(variant.name)-\(theme)-\(cursorSample.label).png")
            }
        }
    }
    fputs("Rendered native Energy and semantic QA frames to \(directory)\n", stdout)
}

private struct PowerState: Decodable {
    let sessionId: String?
    let sessionSource: String?
    let phase: String?
    let status: String?
    let momentum: Int?
    let bestMomentum: Int?
    let energyUpdatedAt: String?
    let combo: Int?
    let bestCombo: Int?
    let comboStatus: String?
    let comboHoldUntil: String?
    let comboExpiresAt: String?
    let comboBrokenAt: String?
    let comboRelinkedAt: String?
    let verificationReward: String?
    let confidence: Int?
    let riskLevel: String?
    let currentActivity: String?
    let completion: String?
    let turnStoppedAt: String?
    let lastActivityAt: String?
    let lastFailureAt: String?
    let evidence: [String]?
    let addedLines: Int?
    let removedLines: Int?
    let verifications: Int?
    let mixedConversationCount: Int?
}

private struct PowerEvent: Decodable {
    let type: String
    let timestamp: String?
    let preview: Bool?
    let sessionId: String?
    let sessionSource: String?
    let addedLines: Int?
    let removedLines: Int?
    let addedChars: Int?
    let removedChars: Int?
    let category: String?
    let success: Bool?
    let phase: String?
    let toolGroup: String?
    let inputCombo: Int?
    let state: PowerState?
    let sessionTransition: SessionTransition?
}

private struct SessionTransition: Decodable {
    let previousSessionId: String
    let currentSessionId: String
}

private struct OverlaySettings: Codable, Equatable {
    var schemaVersion = 1
    var preset = "focus"
    var edge = "smart"
    var scale = 1.15
    var reducedMotion = false
    var inactiveBehavior = "hide"
    var autoHideDelay = 2.0
    var enabled = true
    var idleBehavior = "hide"
    var language = "auto"
    var activitySource: String? = "focused"
    var effectIntensity: String?
    var showCombo: Bool?
    var typingCombo: Bool?
    var cursorEffect: String?
    var positionX: Double?
    var positionY: Double?
    var endpoint = "http://127.0.0.1:4737/api/stream"
}

@MainActor
private final class PowerModePreferences {
    private(set) var settings: OverlaySettings
    private let fileURL: URL?
    var onChange: (() -> Void)?

    init(environment: [String: String]) {
        fileURL = environment["CODEX_POWER_MODE_CONFIG_PATH"].map { URL(fileURLWithPath: $0) }
        if let fileURL,
           let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(OverlaySettings.self, from: data),
           decoded.schemaVersion == 1 {
            settings = decoded
        } else {
            settings = OverlaySettings(endpoint: environment["CODEX_POWER_MODE_URL"] ?? "http://127.0.0.1:4737/api/stream")
        }
        if settings.idleBehavior == "always" { settings.idleBehavior = "orb" }
    }

    var isChinese: Bool {
        if settings.language == "zh-CN" { return true }
        if settings.language == "en" { return false }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }

    func setPreset(_ value: String) { mutate { $0.preset = value } }
    func setIdleBehavior(_ value: String) { mutate { $0.idleBehavior = value } }
    func setAutoHideDelay(_ value: Double) {
        guard [0.0, 2.0, 6.0].contains(value) else { return }
        mutate { $0.autoHideDelay = value }
    }
    func setLanguage(_ value: String) { mutate { $0.language = value } }
    func setActivitySource(_ value: String) {
        guard ["focused", "global", "mix"].contains(value) else { return }
        mutate { $0.activitySource = value }
    }
    func setEffectIntensity(_ value: String) {
        guard ["low", "normal", "high"].contains(value) else { return }
        mutate { $0.effectIntensity = value }
    }
    func setEdge(_ value: String) {
        let supported = ["smart", "top-right", "top-left", "bottom-right", "bottom-left", "center"]
        guard supported.contains(value) else { return }
        mutate { $0.edge = value; $0.positionX = nil; $0.positionY = nil }
    }
    func setScale(_ value: Double) { mutate { $0.scale = min(1.6, max(0.75, value)) } }
    func toggleEnabled() { mutate { $0.enabled.toggle() } }
    func toggleReducedMotion() { mutate { $0.reducedMotion.toggle() } }
    func setInactiveBehavior(_ value: String) {
        guard ["hide", "stay", "follow"].contains(value) else { return }
        mutate { $0.inactiveBehavior = value }
    }
    func toggleCombo() { mutate { $0.showCombo = !($0.showCombo ?? true) } }
    func toggleTypingCombo() { mutate { $0.typingCombo = !($0.typingCombo ?? false) } }
    func setCursorEffect(_ value: String) {
        guard ["off", "spark", "neon"].contains(value) else { return }
        mutate { $0.cursorEffect = value }
    }
    func setPosition(x: Double, y: Double) { mutate { $0.positionX = x; $0.positionY = y } }
    func resetPosition() { mutate { $0.positionX = nil; $0.positionY = nil; $0.edge = "smart" } }

    private func mutate(_ update: (inout OverlaySettings) -> Void) {
        update(&settings)
        save()
        onChange?()
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder.pretty.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            fputs("Codex Power Mode could not save settings: \(error)\n", stderr)
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
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
private final class OrbLayerRenderer {
    private let preferences: PowerModePreferences
    private let container = CALayer()
    private let halo = CALayer()
    private let body = CALayer()
    private let core = CALayer()
    private let inner = CAGradientLayer()
    private let sheen = CAGradientLayer()
    private let tierAura = CAShapeLayer()
    private let signatureBackdrop = CAShapeLayer()
    private let signature = CAShapeLayer()
    private let stageShell = CAShapeLayer()
    private let tierNodes = CAShapeLayer()
    private let ticks = CAShapeLayer()
    private let energyTrack = CAShapeLayer()
    private let energyRing = CAShapeLayer()
    private let phaseRailBackdrop = CAShapeLayer()
    private let phaseRail = CAShapeLayer()
    private let beatRing = CAShapeLayer()
    private let comboTrack = CAShapeLayer()
    private let comboRing = CAShapeLayer()
    private let mixOrbit = CAShapeLayer()
    private let typingOrbit = CAShapeLayer()
    private let semantic = CATextLayer()
    private let value = CATextLayer()
    private let activity = CATextLayer()
    private let comboValue = CATextLayer()
    private let typingValue = CATextLayer()
    private let connectionDot = CALayer()
    private let emitter = CAEmitterLayer()
    private let energyEffects = CALayer()
    private let semanticEffects = CALayer()
    private let comboEffects = CALayer()
    private var comboAnimationGeneration = 0
    private var lastComboSignature = ""
    private var lastComboCount = 0
    private var lastComboStage = "idle"
    private var lastEnergyTier = 0
    private var lastEnergyValue = 0
    private var lastEnergyMotionSignature = ""
    private var phase = "idle"
    private var completionStyle: String?
    private var rhythmGeneration = 0
    private var reducedMotion = false
    private var arcade = false
    private var intensity: Float = 1

    init(hostLayer: CALayer, preferences: PowerModePreferences) {
        self.preferences = preferences
        container.bounds = CGRect(x: 0, y: 0, width: 92, height: 92)
        container.masksToBounds = false
        hostLayer.addSublayer(container)

        halo.frame = CGRect(x: 4, y: 4, width: 84, height: 84)
        halo.cornerRadius = 42
        halo.shadowRadius = 16
        halo.shadowOpacity = 0.28
        halo.shadowOffset = .zero
        container.addSublayer(halo)

        body.frame = container.bounds
        body.masksToBounds = false
        container.addSublayer(body)

        core.frame = CGRect(x: 10, y: 10, width: 72, height: 72)
        core.cornerRadius = 36
        core.backgroundColor = NSColor(calibratedWhite: 0.035, alpha: 0.95).cgColor
        core.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        core.borderWidth = 1
        core.shadowColor = NSColor.black.cgColor
        core.shadowOpacity = 0.32
        core.shadowRadius = 10
        core.shadowOffset = CGSize(width: 0, height: -3)
        body.addSublayer(core)

        inner.frame = CGRect(x: 15, y: 15, width: 62, height: 62)
        inner.cornerRadius = 31
        inner.type = .radial
        inner.startPoint = CGPoint(x: 0.38, y: 0.72)
        inner.endPoint = CGPoint(x: 1, y: 0)
        inner.locations = [0, 0.55, 1]
        inner.borderWidth = 0.6
        body.addSublayer(inner)

        sheen.frame = CGRect(x: 15, y: 15, width: 62, height: 62)
        sheen.cornerRadius = 31
        sheen.colors = [NSColor.clear.cgColor, NSColor.white.withAlphaComponent(0.2).cgColor, NSColor.clear.cgColor]
        sheen.locations = [0.28, 0.5, 0.72]
        sheen.startPoint = CGPoint(x: 0, y: 0.75)
        sheen.endPoint = CGPoint(x: 1, y: 0.25)
        sheen.opacity = 0.1
        body.addSublayer(sheen)

        tierAura.frame = body.bounds
        tierAura.fillColor = NSColor.clear.cgColor
        tierAura.lineCap = .round
        body.addSublayer(tierAura)

        stageShell.frame = body.bounds
        stageShell.fillColor = NSColor.clear.cgColor
        stageShell.lineCap = .round
        stageShell.lineJoin = .round
        body.addSublayer(stageShell)

        tierNodes.frame = body.bounds
        tierNodes.fillColor = NSColor.clear.cgColor
        tierNodes.lineCap = .round
        body.addSublayer(tierNodes)

        signatureBackdrop.frame = body.bounds
        signatureBackdrop.fillColor = NSColor.clear.cgColor
        signatureBackdrop.lineCap = .round
        signatureBackdrop.lineJoin = .round
        signatureBackdrop.opacity = 0
        body.addSublayer(signatureBackdrop)

        signature.frame = body.bounds
        signature.fillColor = NSColor.clear.cgColor
        signature.lineCap = .round
        signature.lineJoin = .round
        signature.lineWidth = 1.6
        signature.opacity = 0
        body.addSublayer(signature)

        configureRing(ticks, radius: 42, width: 1)
        ticks.opacity = 0
        configureRing(comboTrack, radius: 43.5, width: 2.6)
        comboTrack.strokeColor = NSColor.white.withAlphaComponent(0.06).cgColor
        configureRing(comboRing, radius: 43.5, width: 2.8)
        comboRing.lineCap = .round
        comboRing.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        configureRing(mixOrbit, radius: 46, width: 1.2)
        mixOrbit.lineDashPattern = [2, 7]
        mixOrbit.opacity = 0
        configureRing(typingOrbit, radius: 39.5, width: 2)
        typingOrbit.lineCap = .round
        typingOrbit.lineDashPattern = [3, 4]
        typingOrbit.opacity = 0
        configureRing(energyTrack, radius: 35.5, width: 2.2)
        energyTrack.strokeColor = NSColor.white.withAlphaComponent(0.09).cgColor
        configureRing(energyRing, radius: 35.5, width: 3.2)
        energyRing.lineCap = .round
        energyRing.transform = CATransform3DMakeRotation(-.pi / 2, 0, 0, 1)
        configureRing(phaseRailBackdrop, radius: 32.2, width: 3.8)
        phaseRailBackdrop.lineCap = .round
        phaseRailBackdrop.opacity = 0
        configureRing(phaseRail, radius: 32.2, width: 1.45)
        phaseRail.lineCap = .round
        phaseRail.opacity = 0
        configureRing(beatRing, radius: 39.5, width: 1.4)
        beatRing.opacity = 0
        beatRing.lineCap = .round

        configureText(semantic, frame: CGRect(x: 36, y: 68, width: 20, height: 14), size: 9.5, weight: .bold)
        configureText(comboValue, frame: CGRect(x: 28, y: 59, width: 36, height: 11), size: 7.5, weight: .bold)
        configureText(typingValue, frame: CGRect(x: 14, y: 75, width: 64, height: 10), size: 6.4, weight: .bold)
        typingValue.opacity = 0
        configureText(value, frame: CGRect(x: 14, y: 35, width: 64, height: 29), size: 24, weight: .bold)
        configureText(activity, frame: CGRect(x: 12, y: 23, width: 68, height: 12), size: 7.2, weight: .semibold)

        connectionDot.frame = CGRect(x: 75, y: 70, width: 5, height: 5)
        connectionDot.cornerRadius = 2.5
        connectionDot.backgroundColor = NSColor.systemOrange.cgColor
        connectionDot.opacity = 0
        container.addSublayer(connectionDot)

        emitter.frame = container.bounds
        emitter.emitterPosition = CGPoint(x: 46, y: 46)
        emitter.emitterShape = .point
        emitter.renderMode = .additive
        container.insertSublayer(emitter, below: body)
        for effects in [energyEffects, semanticEffects, comboEffects] {
            effects.frame = container.bounds
            effects.masksToBounds = false
            container.insertSublayer(effects, above: beatRing)
        }
        updatePreferences()
    }

    private func configureRing(_ layer: CAShapeLayer, radius: CGFloat, width: CGFloat) {
        layer.frame = container.bounds
        layer.path = CGPath(ellipseIn: CGRect(x: 46 - radius, y: 46 - radius, width: radius * 2, height: radius * 2), transform: nil)
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = width
        layer.strokeStart = 0
        layer.strokeEnd = 1
        container.addSublayer(layer)
    }

    private func configureText(_ layer: CATextLayer, frame: CGRect, size: CGFloat, weight: NSFont.Weight) {
        layer.frame = frame
        layer.alignmentMode = .center
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer.font = NSFont.monospacedSystemFont(ofSize: size, weight: weight)
        layer.fontSize = size
        layer.foregroundColor = NSColor.white.cgColor
        layer.truncationMode = .end
        container.addSublayer(layer)
    }

    func layout(in rect: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        container.position = CGPoint(x: rect.midX, y: rect.midY)
        let scale = min(rect.width / 92, rect.height / 92)
        container.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        CATransaction.commit()
    }

    func updatePreferences() {
        arcade = preferences.settings.preset == "arcade"
        reducedMotion = preferences.settings.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        intensity = preferences.settings.effectIntensity == "high" ? 1.35 : preferences.settings.effectIntensity == "low" ? 0.62 : 1
    }

    func setConnected(_ connected: Bool) {
        connectionDot.opacity = connected ? 0 : 1
    }

    func setVisible(_ visible: Bool, animated: Bool = true) {
        let target: Float = visible ? 1 : 0
        guard container.opacity != target else { return }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = container.presentation()?.opacity ?? container.opacity
        animation.toValue = target
        animation.duration = animated && !reducedMotion ? 0.24 : 0
        container.opacity = target
        container.add(animation, forKey: "visibility")
    }

    func apply(state: PowerState, presentation: (phase: String, status: String, momentum: Int, idle: Bool, settled: Bool, returning: Bool, settledAt: Date?), label: String, event: PowerEvent? = nil) {
        updatePreferences()
        let nextPhase = presentation.phase
        let color = phaseColor(phase: nextPhase, state: state)
        CATransaction.begin()
        CATransaction.setAnimationDuration(reducedMotion ? 0 : event?.sessionTransition != nil ? 0.78 : 0.36)
        halo.backgroundColor = color.withAlphaComponent(nextPhase == "idle" ? 0.025 : 0.065).cgColor
        halo.shadowColor = color.cgColor
        inner.colors = [color.withAlphaComponent(0.18).cgColor, color.withAlphaComponent(0.055).cgColor, NSColor.clear.cgColor]
        inner.borderColor = color.withAlphaComponent(0.18).cgColor
        let nextEnergyTier = energyTier(presentation.momentum)
        let stageColor = energyStageColor(tier: nextEnergyTier, phaseColor: color)
        energyRing.strokeColor = stageColor.cgColor
        if event?.sessionTransition != nil, !reducedMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.72
            value.add(fade, forKey: "session-value-crossfade")
        }
        energyRing.strokeEnd = energyStageProgress(presentation.momentum)
        value.string = "\(presentation.momentum)"
        activity.string = label
        let activityColor = color.blended(withFraction: 0.48, of: .white) ?? .white
        activity.foregroundColor = activityColor.withAlphaComponent(nextPhase == "idle" ? 0.48 : 0.96).cgColor
        semantic.string = phaseGlyph(nextPhase, completion: state.completion)
        semantic.foregroundColor = color.cgColor
        CATransaction.commit()
        updateEnergyStyle(presentation.momentum, color: stageColor)
        updateEnergyStageShape(tier: nextEnergyTier, color: stageColor)
        updateMixOrbit(state, color: color)
        if nextEnergyTier != lastEnergyTier, event?.sessionTransition == nil {
            animateEnergyTierChange(from: lastEnergyValue, to: presentation.momentum, color: stageColor)
        }
        lastEnergyTier = nextEnergyTier
        lastEnergyValue = presentation.momentum
        updateCombo(state, color: color, event: event)
        let semanticPhaseChanged = phase != nextPhase || completionStyle != state.completion
        if semanticPhaseChanged {
            phase = nextPhase
            completionStyle = state.completion
            updateCoreSignature(nextPhase, completion: state.completion, color: color)
            animateSemanticPhase(nextPhase)
            animateCorePhase(nextPhase)
            animateRhythmEntry(nextPhase, color: color)
        }
        updateSemanticContrast(phase: nextPhase, tier: nextEnergyTier, color: color)
        if let event {
            if event.sessionTransition != nil { animateSessionTransition(color: color) }
            animateEventRhythm(event, phase: nextPhase, color: color)
            animateCoreEvent(nextPhase)
            playSemanticChoreography(phase: nextPhase, color: color)
            emitFeedback(for: event, phase: nextPhase, color: color)
        }
        if semanticPhaseChanged {
            animateSemanticReveal(phase: nextPhase, tier: nextEnergyTier)
        }
    }

    private func updateEnergyStyle(_ momentum: Int, color: NSColor) {
        let width: CGFloat = momentum >= 900 ? 4.8 : momentum >= 700 ? 4.35 : momentum >= 450 ? 3.9 : momentum >= 250 ? 3.5 : momentum >= 100 ? 3.15 : 2.7
        energyRing.lineWidth = width
        energyRing.shadowColor = color.cgColor
        energyRing.shadowOpacity = momentum >= 700 ? 0.68 : momentum >= 250 ? 0.46 : 0.24
        energyRing.shadowRadius = momentum >= 900 ? 9 : momentum >= 700 ? 7 : momentum >= 250 ? 5 : 3
    }

    private func energyStageProgress(_ momentum: Int) -> CGFloat {
        let value = max(0, min(999, momentum))
        let tier = energyTier(value)
        let bounds: [(Int, Int)] = [(0, 0), (1, 99), (100, 249), (250, 449), (450, 699), (700, 899), (900, 998), (999, 999)]
        let range = bounds[tier]
        guard range.1 > range.0 else { return value >= range.1 && value > 0 ? 1 : 0 }
        return CGFloat(value - range.0) / CGFloat(range.1 - range.0)
    }

    private func energyTierPalette(_ tier: Int) -> (primary: NSColor, secondary: NSColor) {
        let palettes: [(NSColor, NSColor)] = [
            (.systemGray, .white),
            (NSColor(calibratedRed: 0.28, green: 0.76, blue: 0.95, alpha: 1), NSColor(calibratedRed: 0.30, green: 0.52, blue: 1.00, alpha: 1)),
            (NSColor(calibratedRed: 0.34, green: 0.86, blue: 0.70, alpha: 1), NSColor(calibratedRed: 0.72, green: 1.00, blue: 0.48, alpha: 1)),
            (NSColor(calibratedRed: 0.58, green: 0.53, blue: 1.00, alpha: 1), NSColor(calibratedRed: 0.24, green: 0.90, blue: 1.00, alpha: 1)),
            (NSColor(calibratedRed: 0.94, green: 0.42, blue: 0.92, alpha: 1), NSColor(calibratedRed: 0.54, green: 0.30, blue: 1.00, alpha: 1)),
            (NSColor(calibratedRed: 1.00, green: 0.55, blue: 0.20, alpha: 1), NSColor(calibratedRed: 1.00, green: 0.22, blue: 0.62, alpha: 1)),
            (NSColor(calibratedRed: 1.00, green: 0.26, blue: 0.36, alpha: 1), NSColor(calibratedRed: 1.00, green: 0.78, blue: 0.18, alpha: 1)),
            (NSColor(calibratedRed: 0.36, green: 1.00, blue: 0.62, alpha: 1), NSColor(calibratedRed: 0.92, green: 1.00, blue: 0.98, alpha: 1))
        ]
        return palettes[max(0, min(palettes.count - 1, tier))]
    }

    private func energyStageColor(tier: Int, phaseColor: NSColor) -> NSColor {
        let accent = energyTierPalette(tier).primary
        return phaseColor.blended(withFraction: tier >= 5 ? 0.94 : tier >= 3 ? 0.86 : 0.76, of: accent) ?? accent
    }

    private func polygonPath(center: CGPoint = CGPoint(x: 46, y: 46), radius: CGFloat, sides: Int, rotation: CGFloat = -.pi / 2) -> CGPath {
        let path = CGMutablePath()
        for index in 0..<sides {
            let angle = rotation + CGFloat(index) * 2 * .pi / CGFloat(sides)
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func updateEnergyStageShape(tier: Int, color: NSColor) {
        let palette = energyTierPalette(tier)
        let nodeCounts = [0, 1, 3, 5, 8, 10, 14, 16]
        let coreBorders: [CGFloat] = [1, 1, 1.15, 1.3, 1.55, 1.85, 2.2, 2.6]
        let shellWidths: [CGFloat] = [0, 0.9, 1.1, 1.3, 1.65, 1.95, 2.25, 2.7]
        let haloRadii: [CGFloat] = [10, 12, 14, 16, 19, 22, 26, 30]
        let coreFrame = CGRect(x: 10, y: 10, width: 72, height: 72)
        core.frame = coreFrame
        core.cornerRadius = coreFrame.width / 2
        core.borderWidth = coreBorders[tier]
        core.borderColor = palette.secondary.withAlphaComponent(tier >= 5 ? 0.76 : 0.4).cgColor
        inner.frame = coreFrame.insetBy(dx: 5, dy: 5)
        inner.cornerRadius = inner.frame.width / 2
        inner.colors = [
            palette.secondary.withAlphaComponent(0.12 + CGFloat(tier) * 0.035).cgColor,
            color.withAlphaComponent(0.07 + CGFloat(tier) * 0.025).cgColor,
            NSColor.clear.cgColor
        ]
        inner.locations = tier >= 6 ? [0, 0.36, 1] : tier >= 3 ? [0, 0.48, 1] : [0, 0.6, 1]
        sheen.colors = [
            NSColor.clear.cgColor,
            palette.secondary.withAlphaComponent(tier >= 5 ? 0.42 : 0.24).cgColor,
            NSColor.white.withAlphaComponent(tier >= 6 ? 0.32 : 0.16).cgColor,
            NSColor.clear.cgColor
        ]
        sheen.locations = [0.18, 0.42, 0.57, 0.82]
        stageShell.opacity = tier == 0 ? 0 : 1
        stageShell.strokeColor = palette.secondary.withAlphaComponent(tier >= 5 ? 0.96 : 0.68).cgColor
        stageShell.lineWidth = shellWidths[tier]
        switch tier {
        case 2: stageShell.lineDashPattern = [2, 7]
        case 3: stageShell.lineDashPattern = [9, 7]
        case 4: stageShell.lineDashPattern = [15, 4]
        case 5: stageShell.lineDashPattern = [7, 2]
        case 6: stageShell.lineDashPattern = [2, 2]
        default: stageShell.lineDashPattern = nil
        }
        stageShell.path = CGPath(ellipseIn: CGRect(x: 18, y: 18, width: 56, height: 56), transform: nil)
        stageShell.shadowColor = palette.secondary.cgColor
        stageShell.shadowOpacity = tier >= 5 ? 0.9 : tier >= 3 ? 0.56 : 0.24
        stageShell.shadowRadius = tier >= 6 ? 12 : tier >= 4 ? 7 : 3
        tierAura.opacity = tier == 0 ? 0 : Float(0.12 + Double(tier) * 0.075)
        tierAura.path = CGPath(ellipseIn: CGRect(x: 13.5, y: 13.5, width: 65, height: 65), transform: nil)
        tierAura.strokeColor = color.withAlphaComponent(tier >= 5 ? 0.82 : 0.5).cgColor
        tierAura.lineWidth = 0.7 + CGFloat(tier) * 0.13
        switch tier {
        case 1: tierAura.lineDashPattern = [1, 12]
        case 2: tierAura.lineDashPattern = [2, 8]
        case 3: tierAura.lineDashPattern = [5, 7]
        case 4: tierAura.lineDashPattern = [11, 4]
        case 5: tierAura.lineDashPattern = [5, 2]
        case 6: tierAura.lineDashPattern = [1, 2]
        case 7: tierAura.lineDashPattern = [3, 1]
        default: tierAura.lineDashPattern = nil
        }
        tierAura.shadowColor = color.cgColor
        tierAura.shadowOpacity = tier >= 5 ? 0.72 : 0.3
        tierAura.shadowRadius = tier >= 6 ? 8 : 4
        tierNodes.opacity = tier == 0 ? 0 : 1
        tierNodes.path = energyTierNodePath(count: nodeCounts[tier], radius: 31.8, tier: tier)
        tierNodes.strokeColor = palette.secondary.withAlphaComponent(tier >= 5 ? 0.96 : 0.72).cgColor
        tierNodes.lineWidth = tier >= 6 ? 2.4 : tier >= 4 ? 1.8 : 1.35
        tierNodes.shadowColor = palette.secondary.cgColor
        tierNodes.shadowOpacity = tier >= 5 ? 0.9 : 0.42
        tierNodes.shadowRadius = tier >= 6 ? 7 : 3
        ticks.opacity = tier >= 3 ? Float(min(0.92, 0.22 + Double(tier) * 0.1)) : 0
        ticks.strokeColor = palette.secondary.withAlphaComponent(0.72).cgColor
        ticks.lineDashPattern = tier >= 6 ? [1, 3] : tier >= 4 ? [3, 5] : [2, 8]
        halo.shadowRadius = haloRadii[tier]
        halo.shadowOpacity = tier >= 6 ? 0.62 : tier >= 4 ? 0.42 : 0.26
        halo.backgroundColor = color.withAlphaComponent(tier >= 5 ? 0.12 : tier >= 3 ? 0.075 : 0.04).cgColor
        halo.shadowColor = color.cgColor
        sheen.opacity = Float(0.06 + Double(tier) * 0.032)
        updateEnergyTierMotion(tier: tier)
    }

    private func energyTierNodePath(count: Int, radius: CGFloat, tier: Int) -> CGPath {
        let path = CGMutablePath()
        guard count > 0 else { return path }
        for index in 0..<count {
            let angle = -.pi / 2 + CGFloat(index) * 2 * .pi / CGFloat(count)
            let size: CGFloat = tier >= 6 && index.isMultiple(of: 2) ? 3.2 : tier >= 4 ? 2.5 : 2
            let center = CGPoint(x: 46 + cos(angle) * radius, y: 46 + sin(angle) * radius)
            path.addEllipse(in: CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size))
        }
        return path
    }

    private func updateEnergyTierMotion(tier: Int) {
        let signature = "\(tier)|\(arcade)|\(reducedMotion)"
        guard signature != lastEnergyMotionSignature else { return }
        lastEnergyMotionSignature = signature
        stageShell.removeAnimation(forKey: "energy-stage-spin")
        tierAura.removeAnimation(forKey: "energy-tier-breath")
        tierNodes.removeAnimation(forKey: "energy-node-orbit")
        guard tier > 0, !reducedMotion else { return }
        let spinDurations: [CFTimeInterval] = [0, 12, 9, 6.8, 4.7, 3.4, 2.35, 5.6]
        let speed = arcade ? 0.72 : 1.0
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = tier == 5 ? Double.pi * 2 : 0
        spin.toValue = tier == 5 ? 0 : Double.pi * 2
        spin.duration = spinDurations[tier] * speed
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        stageShell.add(spin, forKey: "energy-stage-spin")
        let nodeOrbit = CABasicAnimation(keyPath: "transform.rotation.z")
        nodeOrbit.fromValue = tier == 6 ? Double.pi * 2 : 0
        nodeOrbit.toValue = tier == 6 ? 0 : Double.pi * 2
        nodeOrbit.duration = spinDurations[tier] * (tier == 7 ? 1.35 : 1.8) * speed
        nodeOrbit.repeatCount = .infinity
        nodeOrbit.isRemovedOnCompletion = false
        tierNodes.add(nodeOrbit, forKey: "energy-node-orbit")
        let breath = CAKeyframeAnimation(keyPath: "opacity")
        breath.values = tier >= 6 ? [0.42, 1, 0.3, 0.88, 0.42] : tier == 5 ? [0.34, 0.9, 0.46, 0.76, 0.34] : [0.2, min(0.86, 0.34 + Double(tier) * 0.1), 0.2]
        breath.keyTimes = tier >= 5 ? [0, 0.18, 0.42, 0.64, 1] : [0, 0.46, 1]
        breath.duration = (tier == 7 ? 2.4 : max(0.82, 4.4 - Double(tier) * 0.52)) * speed
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: tier >= 5 ? .easeInEaseOut : .easeOut)
        tierAura.add(breath, forKey: "energy-tier-breath")
    }

    private func updateMixOrbit(_ state: PowerState, color: NSColor) {
        let conversations = state.mixedConversationCount ?? 0
        guard conversations > 1 else {
            mixOrbit.opacity = 0
            mixOrbit.removeAnimation(forKey: "mix-orbit")
            return
        }
        mixOrbit.opacity = min(0.9, Float(0.45 + Double(conversations) * 0.09))
        mixOrbit.strokeColor = color.withAlphaComponent(0.82).cgColor
        mixOrbit.shadowColor = color.cgColor
        mixOrbit.shadowOpacity = 0.5
        mixOrbit.shadowRadius = 4
        guard mixOrbit.animation(forKey: "mix-orbit") == nil, !reducedMotion else { return }
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = Double.pi * 2
        spin.duration = arcade ? 2.8 : 4.4
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        mixOrbit.add(spin, forKey: "mix-orbit")
    }

    private func energyTier(_ momentum: Int) -> Int {
        if momentum <= 0 { return 0 }
        if momentum < 100 { return 1 }
        if momentum < 250 { return 2 }
        if momentum < 450 { return 3 }
        if momentum < 700 { return 4 }
        if momentum < 900 { return 5 }
        if momentum < 999 { return 6 }
        return 7
    }

    private func animateEnergyTierChange(from previousValue: Int, to nextValue: Int, color: NSColor) {
        let previous = energyTier(previousValue)
        let next = energyTier(nextValue)
        guard previousValue > 0, nextValue > 0, previous != next, !reducedMotion else { return }
        let rising = next > previous
        let crossings = max(1, abs(next - previous))
        let palette = energyTierPalette(next)
        let tierStrength = CGFloat(next) / 7
        let oldProgress = energyStageProgress(previousValue)
        let newProgress = energyStageProgress(nextValue)
        var ringValues: [CGFloat] = [oldProgress]
        for _ in 0..<crossings {
            let boundary: CGFloat = rising ? 1 : 0
            let reset: CGFloat = rising ? 0 : 1
            ringValues.append(contentsOf: [boundary, boundary, reset, reset])
        }
        ringValues.append(newProgress)
        let ring = CAKeyframeAnimation(keyPath: "strokeEnd")
        ring.values = ringValues
        ring.keyTimes = (0..<ringValues.count).map { NSNumber(value: Double($0) / Double(max(1, ringValues.count - 1))) }
        ring.duration = rising
            ? min(2.35, 0.9 + Double(crossings) * 0.18 + Double(next) * 0.055 + (arcade ? 0.12 : 0))
            : min(1.55, 0.72 + Double(crossings) * 0.15)
        ring.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        energyRing.add(ring, forKey: rising ? "stage-fill-reset" : "stage-drain-restore")
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        let compression = 0.92 - Double(tierStrength) * 0.08
        let breakthrough = 1.22 + Double(tierStrength) * 0.15 + (arcade ? 0.055 : 0)
        pulse.values = rising ? [1, 1.06, compression, compression, breakthrough, 0.94, 1.09, 1] : [1, 0.84, 1.1, 0.9, 1]
        pulse.keyTimes = rising ? [0, 0.12, 0.23, 0.31, 0.47, 0.62, 0.8, 1] : [0, 0.22, 0.5, 0.76, 1]
        pulse.duration = ring.duration
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.add(pulse, forKey: "energy-tier-body")
        let ringWidth = energyRing.presentation()?.lineWidth ?? energyRing.lineWidth
        let ringImpact = CAKeyframeAnimation(keyPath: "lineWidth")
        ringImpact.values = rising ? [ringWidth, ringWidth + 1.5, ringWidth + 3.4 + CGFloat(next) * 0.45, ringWidth + 1.2, ringWidth] : [ringWidth, ringWidth + 2.4, 1.2, ringWidth]
        ringImpact.keyTimes = rising ? [0, 0.23, 0.47, 0.66, 1] : [0, 0.3, 0.52, 1]
        ringImpact.duration = pulse.duration
        energyRing.add(ringImpact, forKey: rising ? "tier-ring-impact" : "tier-ring-collapse")
        let flareCount = rising ? min(arcade ? 7 : 5, 2 + crossings + next / 2) : 2
        for index in 0..<flareCount {
            let flare = CAShapeLayer()
            flare.frame = energyEffects.bounds
            flare.path = CGPath(ellipseIn: CGRect(x: 9, y: 9, width: 74, height: 74), transform: nil)
            flare.fillColor = NSColor.clear.cgColor
            flare.strokeColor = (rising ? (index.isMultiple(of: 2) ? color : palette.secondary) : NSColor.systemOrange).cgColor
            flare.lineWidth = rising ? CGFloat(2.4 + Double(next) * 0.5 - Double(index) * 0.25) : 2.4
            flare.lineDashPattern = rising ? nil : [4, 5]
            flare.shadowColor = flare.strokeColor
            flare.shadowOpacity = rising ? 0.95 : 0.58
            flare.shadowRadius = rising ? CGFloat(5 + next) : 3
            energyEffects.addSublayer(flare)
            let group = CAAnimationGroup()
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = rising ? [0.68, 0.62, 0.9, 1.7 + Double(index) * 0.22] : [1.24, 1.08, 0.82]
            scale.keyTimes = rising ? [0, 0.22, 0.38, 1] : [0, 0.42, 1]
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = rising ? [0, 0.9, 1, 0] : [0, 0.72, 0]
            opacity.keyTimes = rising ? [0, 0.22, 0.4, 1] : [0, 0.34, 1]
            group.animations = [scale, opacity]
            group.beginTime = CACurrentMediaTime() + ring.duration * 0.29 + Double(index) * (arcade ? 0.065 : 0.09)
            group.duration = rising ? min(1.95, 1.08 + Double(crossings) * 0.14 + Double(next) * 0.045) : min(1.2, 0.68 + Double(crossings) * 0.12)
            group.timingFunction = CAMediaTimingFunction(name: rising ? .easeOut : .easeInEaseOut)
            flare.add(group, forKey: rising ? "energy-breakthrough" : "energy-vent")
            DispatchQueue.main.asyncAfter(deadline: .now() + ring.duration * 0.29 + group.duration + Double(index) * 0.09 + 0.08) { [weak flare] in flare?.removeFromSuperlayer() }
        }
        if rising {
            let seal = CAShapeLayer()
            seal.frame = energyEffects.bounds
            seal.path = CGPath(ellipseIn: CGRect(x: 15, y: 15, width: 62, height: 62), transform: nil)
            seal.fillColor = NSColor.clear.cgColor
            seal.strokeColor = palette.secondary.cgColor
            seal.lineWidth = 1.25 + CGFloat(next) * 0.18
            seal.lineDashPattern = next >= 6 ? [2, 2] : next >= 4 ? [8, 4] : nil
            seal.shadowColor = palette.secondary.cgColor
            seal.shadowOpacity = next >= 5 ? 1 : 0.72
            seal.shadowRadius = CGFloat(4 + next)
            energyEffects.addSublayer(seal)
            let establish = CAAnimationGroup()
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 0, 0.72, 1, 1]
            draw.keyTimes = [0, 0.18, 0.46, 0.68, 1]
            let establishScale = CAKeyframeAnimation(keyPath: "transform.scale")
            establishScale.values = [0.72, 0.72, 1.14 + Double(tierStrength) * 0.08, 0.98, 1]
            establishScale.keyTimes = [0, 0.18, 0.52, 0.78, 1]
            let establishOpacity = CAKeyframeAnimation(keyPath: "opacity")
            establishOpacity.values = [0, 0, 1, 0.72, 0]
            establishOpacity.keyTimes = [0, 0.18, 0.48, 0.78, 1]
            let establishRotation = CABasicAnimation(keyPath: "transform.rotation.z")
            establishRotation.fromValue = next >= 5 ? -Double.pi * 0.45 : -Double.pi * 0.18
            establishRotation.toValue = 0
            establish.animations = [draw, establishScale, establishOpacity, establishRotation]
            establish.beginTime = CACurrentMediaTime() + ring.duration * 0.42
            establish.duration = 0.78 + Double(next) * 0.055 + (arcade ? 0.12 : 0)
            establish.timingFunction = CAMediaTimingFunction(name: .easeOut)
            seal.add(establish, forKey: "energy-tier-establish")
            DispatchQueue.main.asyncAfter(deadline: .now() + ring.duration * 0.42 + establish.duration + 0.08) { [weak seal] in seal?.removeFromSuperlayer() }
        }
    }

    func updateTypingCombo(count: Int, progress: CGFloat, pulse: Bool = false) {
        guard count > 0 else {
            typingOrbit.opacity = 0
            typingValue.opacity = 0
            typingValue.string = ""
            return
        }
        let color = NSColor(calibratedRed: 0.24, green: 0.88, blue: 1.00, alpha: 1)
        typingOrbit.opacity = 1
        typingOrbit.strokeColor = color.cgColor
        typingOrbit.shadowColor = color.cgColor
        typingOrbit.shadowOpacity = 0.66
        typingOrbit.shadowRadius = count >= 20 ? 8 : 4
        typingOrbit.strokeEnd = progress
        typingValue.opacity = 1
        typingValue.foregroundColor = color.cgColor
        typingValue.string = "INPUT ×\(count)"
        guard pulse, !reducedMotion else { return }
        let hit = CAKeyframeAnimation(keyPath: "transform.scale")
        hit.values = count % 10 == 0 ? [1, 1.26, 0.94, 1] : [1, 1.1, 1]
        hit.duration = count % 10 == 0 ? 0.34 : 0.16
        typingValue.add(hit, forKey: "typing-hit")
        typingOrbit.add(hit, forKey: "typing-orbit-hit")
    }

    func playTypingInjection(count: Int) {
        guard count > 0 else { return }
        guard !reducedMotion else { return }
        let absorb = CAKeyframeAnimation(keyPath: "transform.scale")
        absorb.values = [1, 0.86, count >= 20 ? 1.36 : 1.22, 0.95, 1]
        absorb.keyTimes = [0, 0.36, 0.58, 0.82, 1]
        absorb.duration = 0.82
        body.add(absorb, forKey: "typing-absorb")
        playBeatRing(color: NSColor.systemCyan, delay: 0.32, duration: 0.72, power: count >= 20 ? 1.45 : 1.12)
    }

    private func updateCombo(_ state: PowerState, color: NSColor, event: PowerEvent?) {
        guard preferences.settings.showCombo == true else {
            lastComboSignature = "hidden"
            lastComboCount = 0
            comboRing.removeAllAnimations()
            comboRing.strokeEnd = 0
            comboTrack.opacity = 0
            comboValue.string = ""
            return
        }
        let now = Date()
        let count = state.combo ?? 0
        let parsedExpires = parseDate(state.comboExpiresAt)
        let brokenAt = parseDate(state.comboBrokenAt) ?? parsedExpires
        if count <= 0 || parsedExpires == nil || parsedExpires! <= now {
            let lostIsVisible = brokenAt.map { now < $0.addingTimeInterval(3.2) } ?? false
            let lostSignature = lostIsVisible ? "lost|\(state.comboBrokenAt ?? state.comboExpiresAt ?? "")" : "idle"
            guard lostSignature != lastComboSignature else { return }
            lastComboSignature = lostSignature
            if lostIsVisible {
                playComboBreak()
            } else {
                comboRing.removeAllAnimations()
                comboRing.strokeEnd = 0
                comboTrack.opacity = 0
                comboValue.string = ""
            }
            lastComboCount = 0
            lastComboStage = lostIsVisible ? "lost" : "idle"
            return
        }
        let expires = parsedExpires!
        let hold = parseDate(state.comboHoldUntil) ?? now
        let totalDuration = max(0.1, expires.timeIntervalSince(hold))
        let progress = now < hold ? 1 : max(0, min(1, expires.timeIntervalSince(now) / totalDuration))
        let nextStage = state.comboStatus == "reward" || state.comboStatus == "complete"
            ? "reward"
            : progress <= 0.25 ? "critical" : comboStageName(count)
        let signature = "\(count)|\(state.comboStatus ?? "")|\(state.comboHoldUntil ?? "")|\(state.comboExpiresAt ?? "")|\(nextStage)"
        guard signature != lastComboSignature else { return }
        let grew = count > lastComboCount && event?.sessionTransition == nil
        let crossedStage = grew && nextStage != lastComboStage && !["critical", "reward"].contains(nextStage)
        let relinked = state.comboRelinkedAt.flatMap { parseDate($0) }.map { abs(now.timeIntervalSince($0)) < 1.6 } ?? false
        lastComboSignature = signature
        comboAnimationGeneration &+= 1
        let generation = comboAnimationGeneration
        comboTrack.opacity = 1
        comboRing.opacity = 1
        comboValue.opacity = 1
        comboRing.lineDashPattern = nil
        comboValue.foregroundColor = NSColor.white.cgColor
        comboValue.string = "\(count)×"
        let stageColor: NSColor = state.comboStatus == "reward" || state.comboStatus == "complete" ? .systemGreen : color
        comboRing.strokeColor = stageColor.cgColor
        comboRing.shadowColor = stageColor.cgColor
        comboRing.shadowOpacity = 0.46
        comboRing.shadowRadius = 3
        comboRing.removeAllAnimations()
        comboRing.strokeEnd = 0
        let delay = max(0, hold.timeIntervalSince(now))
        let remainingDuration = max(0.1, expires.timeIntervalSince(now))
        let currentProgress = now < hold ? 1 : max(0, min(1, expires.timeIntervalSince(now) / totalDuration))
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = currentProgress
        animation.toValue = 0
        animation.beginTime = comboRing.convertTime(CACurrentMediaTime(), from: nil) + delay
        animation.duration = now < hold ? totalDuration : remainingDuration
        animation.fillMode = .both
        animation.isRemovedOnCompletion = false
        comboRing.add(animation, forKey: "combo-decay-\(generation)")
        if grew { playComboGrowth(color: stageColor, strong: crossedStage) }
        if relinked { playComboRelink(color: .systemCyan) }
        if nextStage == "critical" && lastComboStage != "critical" { playComboDanger() }
        lastComboCount = count
        lastComboStage = nextStage
    }

    private func comboStageName(_ count: Int) -> String {
        if count < 5 { return "ignition" }
        if count < 10 { return "linked" }
        if count < 20 { return "accelerated" }
        if count < 40 { return "heated" }
        return "extreme"
    }

    private func playComboGrowth(color: NSColor, strong: Bool) {
        guard !reducedMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = strong ? [1, 1.19, 0.96, 1] : [1, 1.08, 1]
        pulse.keyTimes = strong ? [0, 0.35, 0.7, 1] : [0, 0.45, 1]
        pulse.duration = strong ? 0.58 : 0.28
        comboRing.add(pulse, forKey: "combo-growth")
        comboValue.add(pulse, forKey: "combo-value-growth")
        let wave = CAShapeLayer()
        wave.frame = comboEffects.bounds
        wave.path = CGPath(ellipseIn: CGRect(x: 1.5, y: 1.5, width: 89, height: 89), transform: nil)
        wave.fillColor = NSColor.clear.cgColor
        wave.strokeColor = color.cgColor
        wave.lineWidth = strong ? 3.8 : 2.2
        wave.shadowColor = color.cgColor
        wave.shadowOpacity = strong ? 0.9 : 0.58
        wave.shadowRadius = strong ? 8 : 4
        comboEffects.addSublayer(wave)
        let group = CAAnimationGroup()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.9
        scale.toValue = strong ? 1.32 : 1.14
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]
        opacity.keyTimes = [0, 0.22, 1]
        group.animations = [scale, opacity]
        group.duration = strong ? 0.62 : 0.34
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        wave.add(group, forKey: "combo-growth-wave")
        DispatchQueue.main.asyncAfter(deadline: .now() + group.duration + 0.05) { [weak wave] in wave?.removeFromSuperlayer() }
    }

    private func playComboRelink(color: NSColor) {
        guard !reducedMotion else { return }
        let close = CAKeyframeAnimation(keyPath: "lineDashPhase")
        close.values = [24, 10, 0]
        close.duration = 0.52
        close.timingFunction = CAMediaTimingFunction(name: .easeOut)
        comboRing.add(close, forKey: "combo-relink-close")
        playComboGrowth(color: color, strong: true)
    }

    private func playComboDanger() {
        guard !reducedMotion else { return }
        comboRing.strokeColor = NSColor.systemOrange.cgColor
        comboRing.shadowColor = NSColor.systemRed.cgColor
        comboRing.shadowOpacity = 0.82
        comboRing.shadowRadius = 7
        let warning = CAKeyframeAnimation(keyPath: "opacity")
        warning.values = [1, 0.28, 1, 0.28, 1]
        warning.keyTimes = [0, 0.18, 0.36, 0.62, 1]
        warning.duration = 0.9
        warning.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        comboRing.add(warning, forKey: "combo-danger-double-pulse")
        comboValue.add(warning, forKey: "combo-danger-value")
    }

    private func playComboBreak() {
        comboAnimationGeneration &+= 1
        comboTrack.opacity = 1
        comboRing.removeAllAnimations()
        comboRing.strokeColor = NSColor.systemRed.cgColor
        comboRing.shadowColor = NSColor.systemRed.cgColor
        comboRing.shadowOpacity = 0.78
        comboRing.shadowRadius = 7
        comboRing.lineDashPattern = [8, 6]
        comboRing.strokeEnd = 0.72
        comboValue.string = "×"
        comboValue.foregroundColor = NSColor.systemRed.cgColor
        guard !reducedMotion else { return }
        comboRing.opacity = 0
        comboValue.opacity = 0
        let group = CAAnimationGroup()
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0.65, 0]
        opacity.keyTimes = [0, 0.18, 0.52, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [1, 1.14, 0.94, 1.3]
        scale.keyTimes = [0, 0.22, 0.58, 1]
        group.animations = [opacity, scale]
        group.duration = 0.72
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        comboRing.add(group, forKey: "combo-break")
        comboValue.add(group, forKey: "combo-break-value")
    }

    private func animateSessionTransition(color: NSColor) {
        guard !reducedMotion else { return }
        let handoff = CAKeyframeAnimation(keyPath: "transform.scale")
        handoff.values = [1, 0.74, 0.74, 1.06, 1]
        handoff.keyTimes = [0, 0.32, 0.54, 0.8, 1]
        handoff.duration = 0.78
        handoff.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.add(handoff, forKey: "session-handoff")
        let ring = CAKeyframeAnimation(keyPath: "opacity")
        ring.values = [1, 0.18, 0.18, 1]
        ring.keyTimes = [0, 0.34, 0.58, 1]
        ring.duration = 0.78
        energyRing.add(ring, forKey: "session-handoff-energy")
        playComboGrowth(color: color, strong: false)
    }

    private func animateSemanticPhase(_ phase: String) {
        semantic.removeAllAnimations()
        guard !reducedMotion else { return }
        let animation: CAAnimation
        switch phase {
        case "observe":
            let breathe = CAKeyframeAnimation(keyPath: "opacity")
            breathe.values = [0.5, 1, 0.72, 0.72, 0.5]
            breathe.keyTimes = [0, 0.2, 0.38, 0.82, 1]
            breathe.duration = arcade ? 1.65 : 2.4
            breathe.repeatCount = .infinity
            animation = breathe
        case "act":
            let drive = CAKeyframeAnimation(keyPath: "transform.translation.x")
            drive.values = [0, -2, 4.5, 0, 0]
            drive.keyTimes = [0, 0.12, 0.3, 0.48, 1]
            drive.duration = arcade ? 0.72 : 1.05
            drive.repeatCount = .infinity
            animation = drive
        case "verify":
            let lock = CAKeyframeAnimation(keyPath: "transform.scale")
            lock.values = [1, 0.78, 1.16, 1, 1]
            lock.keyTimes = [0, 0.16, 0.36, 0.52, 1]
            lock.duration = arcade ? 0.95 : 1.32
            lock.repeatCount = .infinity
            animation = lock
        case "wait":
            let pulse = CAKeyframeAnimation(keyPath: "opacity")
            pulse.values = [0.34, 1, 0.34, 1, 0.34, 0.34]
            pulse.keyTimes = [0, 0.1, 0.2, 0.32, 0.44, 1]
            pulse.duration = arcade ? 1.45 : 2.05
            pulse.repeatCount = .infinity
            animation = pulse
        case "recover":
            let repair = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            repair.values = [0, -0.2, 0.14, -0.08, 0, 0]
            repair.keyTimes = [0, 0.1, 0.22, 0.34, 0.48, 1]
            repair.duration = arcade ? 0.92 : 1.3
            repair.repeatCount = .infinity
            animation = repair
        default:
            let settle = CABasicAnimation(keyPath: "transform.scale")
            settle.fromValue = 1.26
            settle.toValue = 1
            settle.duration = arcade ? 0.48 : 0.72
            animation = settle
        }
        semantic.add(animation, forKey: "semantic-phase")
    }

    private func updateCoreSignature(_ phase: String, completion: String?, color: NSColor) {
        signature.removeAllAnimations()
        phaseRail.removeAnimation(forKey: "phase-dash")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signatureBackdrop.path = coreSignaturePath(phase, completion: completion)
        signature.path = coreSignaturePath(phase, completion: completion)
        signature.strokeColor = color.withAlphaComponent(phase == "idle" ? 0.28 : 0.82).cgColor
        signature.shadowColor = color.cgColor
        signature.shadowOpacity = phase == "idle" ? 0.1 : arcade ? 0.72 : 0.42
        signature.shadowRadius = arcade ? 4.5 : 2.5
        signature.lineWidth = phase == "complete" ? (arcade ? 2.15 : 1.8) : (arcade ? 1.9 : 1.55)
        signature.lineDashPattern = phase == "complete" && completion == "unverified" ? [4, 3]
            : phase == "complete" && completion == "cancelled" ? [8, 5]
            : nil
        signature.opacity = phase == "idle" ? 0.36 : 1
        phaseRail.opacity = phase == "idle" ? 0 : 0.88
        phaseRail.strokeColor = color.withAlphaComponent(0.92).cgColor
        phaseRail.shadowColor = color.cgColor
        phaseRail.shadowOpacity = arcade ? 0.72 : 0.46
        phaseRail.shadowRadius = arcade ? 4 : 2.4
        phaseRail.lineWidth = phase == "wait" || phase == "recover" ? 1.8 : 1.45
        phaseRail.lineDashPattern = phase == "observe" ? [3, 5]
            : phase == "act" ? [14, 3]
            : phase == "verify" ? [7, 3]
            : phase == "wait" ? [2, 7]
            : phase == "recover" ? [5, 3]
            : phase == "complete" ? [18, 2]
            : nil
        signatureBackdrop.lineDashPattern = signature.lineDashPattern
        phaseRailBackdrop.lineDashPattern = phaseRail.lineDashPattern
        CATransaction.commit()
        guard !reducedMotion, phase != "idle" else { return }
        let animation: CAAnimation
        switch phase {
        case "observe":
            let rotate = CABasicAnimation(keyPath: "transform.rotation.z")
            rotate.fromValue = 0
            rotate.toValue = CGFloat.pi * 2
            rotate.duration = arcade ? 2.6 : 3.8
            rotate.repeatCount = .infinity
            animation = rotate
        case "act":
            let drive = CAKeyframeAnimation(keyPath: "transform.translation.x")
            drive.values = [-2, 3.5, 0, 0]
            drive.keyTimes = [0, 0.3, 0.5, 1]
            drive.duration = arcade ? 0.72 : 1.05
            drive.repeatCount = .infinity
            animation = drive
        case "verify":
            let lock = CAKeyframeAnimation(keyPath: "transform.scale")
            lock.values = [1.08, 0.88, 1.02, 1.02]
            lock.keyTimes = [0, 0.28, 0.52, 1]
            lock.duration = arcade ? 0.95 : 1.32
            lock.repeatCount = .infinity
            animation = lock
        case "wait":
            let gate = CAKeyframeAnimation(keyPath: "opacity")
            gate.values = [0.42, 1, 0.46, 0.9, 0.42, 0.42]
            gate.keyTimes = [0, 0.1, 0.2, 0.32, 0.44, 1]
            gate.duration = arcade ? 1.45 : 2.05
            gate.repeatCount = .infinity
            animation = gate
        case "recover":
            let repair = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            repair.values = [-0.11, 0.075, -0.045, 0, 0]
            repair.keyTimes = [0, 0.2, 0.38, 0.56, 1]
            repair.duration = arcade ? 0.92 : 1.3
            repair.repeatCount = .infinity
            animation = repair
        default:
            let finish = CAKeyframeAnimation(keyPath: "transform.scale")
            finish.values = [0.76, 1.16, 0.96, 1]
            finish.keyTimes = [0, 0.46, 0.72, 1]
            finish.duration = arcade ? 0.88 : 1.08
            animation = finish
        }
        signature.add(animation, forKey: "signature-phase")
        if ["observe", "act", "recover"].contains(phase) {
            let dash = CABasicAnimation(keyPath: "lineDashPhase")
            dash.fromValue = 0
            dash.toValue = phase == "act" ? -34 : -16
            dash.duration = phase == "act" ? 0.72 : 1.6
            dash.repeatCount = .infinity
            phaseRail.add(dash, forKey: "phase-dash")
        }
    }

    private func updateSemanticContrast(phase: String, tier: Int, color: NSColor) {
        let highEnergy = tier >= 5
        let peakEnergy = tier >= 7
        let active = phase != "idle"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signature.strokeColor = color.withAlphaComponent(active ? 0.98 : 0.28).cgColor
        signature.lineWidth = phase == "complete"
            ? (arcade ? 2.65 : 2.2)
            : (arcade ? 2.35 : 1.95)
        signature.shadowColor = color.cgColor
        signature.shadowOpacity = active ? (highEnergy ? 1 : arcade ? 0.72 : 0.48) : 0.1
        signature.shadowRadius = highEnergy ? (peakEnergy ? 7 : 5.5) : arcade ? 4.5 : 2.8
        signatureBackdrop.strokeColor = NSColor.black.withAlphaComponent(highEnergy ? 0.74 : 0.5).cgColor
        signatureBackdrop.lineWidth = signature.lineWidth + (highEnergy ? 3.6 : 2.5)
        signatureBackdrop.opacity = active ? 1 : 0.2
        phaseRail.strokeColor = color.cgColor
        phaseRail.lineWidth = phase == "wait" || phase == "recover" ? (highEnergy ? 2.55 : 2.05) : (highEnergy ? 2.1 : 1.7)
        phaseRail.shadowOpacity = active ? (highEnergy ? 0.95 : arcade ? 0.72 : 0.46) : 0
        phaseRail.shadowRadius = highEnergy ? 5.5 : arcade ? 4 : 2.4
        phaseRailBackdrop.strokeColor = NSColor.black.withAlphaComponent(highEnergy ? 0.68 : 0.42).cgColor
        phaseRailBackdrop.lineWidth = phaseRail.lineWidth + (highEnergy ? 3.1 : 2.3)
        phaseRailBackdrop.opacity = active ? 0.9 : 0
        semantic.shadowColor = NSColor.black.cgColor
        semantic.shadowOpacity = active ? (highEnergy ? 0.95 : 0.62) : 0
        semantic.shadowRadius = highEnergy ? 3.5 : 2
        CATransaction.commit()
    }

    private func animateSemanticReveal(phase: String, tier: Int) {
        guard !reducedMotion, phase != "idle" else { return }
        let duration: CFTimeInterval = (arcade ? 0.82 : 1.02) + (tier >= 5 ? 0.12 : 0)
        for (index, layer) in [tierAura, stageShell, tierNodes, energyRing].enumerated() {
            let base = layer.presentation()?.opacity ?? layer.opacity
            let duck = CAKeyframeAnimation(keyPath: "opacity")
            duck.values = [base, base, base * 0.38, base * 0.38, base * 0.76, base]
            duck.keyTimes = [0, 0.12, 0.24, 0.48, 0.72, 1]
            duck.duration = duration
            duck.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.012
            duck.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(duck, forKey: "semantic-energy-duck")
        }
        let revealScale = CAKeyframeAnimation(keyPath: "transform.scale")
        revealScale.values = [0.7, 0.7, arcade ? 1.3 : 1.22, 0.96, 1.06, 1]
        revealScale.keyTimes = [0, 0.14, 0.4, 0.62, 0.8, 1]
        let revealOpacity = CAKeyframeAnimation(keyPath: "opacity")
        revealOpacity.values = [0, 0.18, 1, 1, 0.92, 1]
        revealOpacity.keyTimes = [0, 0.12, 0.34, 0.58, 0.78, 1]
        let reveal = CAAnimationGroup()
        reveal.animations = [revealScale, revealOpacity]
        reveal.duration = duration
        reveal.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.18, 1)
        signature.add(reveal, forKey: "semantic-reveal")
        signatureBackdrop.add(reveal, forKey: "semantic-backdrop-reveal")

        let railDraw = CAKeyframeAnimation(keyPath: "strokeEnd")
        railDraw.values = [0, 0, 0.42, 1, 1]
        railDraw.keyTimes = [0, 0.16, 0.36, 0.62, 1]
        let railPulse = CAKeyframeAnimation(keyPath: "transform.scale")
        railPulse.values = [0.88, 0.88, 1.16, 0.98, 1]
        railPulse.keyTimes = [0, 0.16, 0.44, 0.7, 1]
        let railReveal = CAAnimationGroup()
        railReveal.animations = [railDraw, railPulse]
        railReveal.duration = duration
        railReveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        phaseRail.add(railReveal, forKey: "semantic-rail-reveal")
        phaseRailBackdrop.add(railReveal, forKey: "semantic-rail-backdrop-reveal")

        let glyphReveal = CAKeyframeAnimation(keyPath: "transform.scale")
        glyphReveal.values = [0.5, 0.5, arcade ? 1.55 : 1.38, 0.92, 1]
        glyphReveal.keyTimes = [0, 0.18, 0.44, 0.72, 1]
        glyphReveal.duration = duration
        glyphReveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        semantic.add(glyphReveal, forKey: "semantic-glyph-reveal")
    }

    private func coreSignaturePath(_ phase: String, completion: String? = nil) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: 46, y: 46)
        switch phase {
        case "observe":
            for start in stride(from: CGFloat(12), to: 360, by: 90) {
                path.addArc(center: center, radius: 25, startAngle: start * .pi / 180, endAngle: (start + 58) * .pi / 180, clockwise: false)
            }
            path.addEllipse(in: CGRect(x: 41, y: 41, width: 10, height: 10))
        case "act":
            for offset in [CGFloat(0), 8] {
                path.move(to: CGPoint(x: 15 + offset, y: 34))
                path.addLine(to: CGPoint(x: 27 + offset, y: 46))
                path.addLine(to: CGPoint(x: 15 + offset, y: 58))
            }
            path.move(to: CGPoint(x: 57, y: 39))
            path.addLine(to: CGPoint(x: 73, y: 39))
            path.addLine(to: CGPoint(x: 80, y: 46))
            path.addLine(to: CGPoint(x: 73, y: 53))
            path.addLine(to: CGPoint(x: 57, y: 53))
        case "verify":
            for (x, y, dx, dy) in [(21.0, 21.0, 1.0, 1.0), (71.0, 21.0, -1.0, 1.0), (21.0, 71.0, 1.0, -1.0), (71.0, 71.0, -1.0, -1.0)] {
                let px = CGFloat(x), py = CGFloat(y), sx = CGFloat(dx), sy = CGFloat(dy)
                path.move(to: CGPoint(x: px + sx * 11, y: py))
                path.addLine(to: CGPoint(x: px, y: py))
                path.addLine(to: CGPoint(x: px, y: py + sy * 11))
            }
        case "wait":
            for x in [CGFloat(22), 70] {
                path.move(to: CGPoint(x: x, y: 25))
                path.addLine(to: CGPoint(x: x, y: 67))
            }
            path.move(to: CGPoint(x: 22, y: 31))
            path.addLine(to: CGPoint(x: 29, y: 31))
            path.move(to: CGPoint(x: 63, y: 31))
            path.addLine(to: CGPoint(x: 70, y: 31))
            path.move(to: CGPoint(x: 22, y: 61))
            path.addLine(to: CGPoint(x: 29, y: 61))
            path.move(to: CGPoint(x: 63, y: 61))
            path.addLine(to: CGPoint(x: 70, y: 61))
        case "recover":
            for (start, end) in [(10.0, 64.0), (91.0, 145.0), (172.0, 226.0), (253.0, 326.0)] {
                path.addArc(center: center, radius: 26, startAngle: CGFloat(start) * .pi / 180, endAngle: CGFloat(end) * .pi / 180, clockwise: false)
            }
            path.move(to: CGPoint(x: 31, y: 23))
            path.addLine(to: CGPoint(x: 39, y: 36))
            path.addLine(to: CGPoint(x: 35, y: 43))
            path.addLine(to: CGPoint(x: 49, y: 61))
        case "complete":
            switch completion {
            case "verified":
                path.addArc(center: center, radius: 26, startAngle: 0.12, endAngle: 5.7, clockwise: false)
                path.move(to: CGPoint(x: 58, y: 28))
                path.addLine(to: CGPoint(x: 64, y: 34))
                path.addLine(to: CGPoint(x: 76, y: 21))
            case "unverified":
                path.addArc(center: center, radius: 26, startAngle: 0.35, endAngle: 5.2, clockwise: false)
                path.move(to: CGPoint(x: 46, y: 27))
                path.addLine(to: CGPoint(x: 46, y: 47))
                path.addEllipse(in: CGRect(x: 44, y: 53, width: 4, height: 4))
            case "cancelled":
                path.addArc(center: center, radius: 26, startAngle: 0.3, endAngle: 2.55, clockwise: false)
                path.addArc(center: center, radius: 26, startAngle: 3.45, endAngle: 5.7, clockwise: false)
                path.move(to: CGPoint(x: 34, y: 34))
                path.addLine(to: CGPoint(x: 58, y: 58))
                path.move(to: CGPoint(x: 58, y: 34))
                path.addLine(to: CGPoint(x: 34, y: 58))
            default:
                path.addEllipse(in: CGRect(x: 20, y: 20, width: 52, height: 52))
                path.move(to: CGPoint(x: 34, y: 46))
                path.addLine(to: CGPoint(x: 58, y: 46))
            }
        default:
            path.addEllipse(in: CGRect(x: 22, y: 22, width: 48, height: 48))
        }
        return path
    }

    private func animateCorePhase(_ phase: String) {
        inner.removeAnimation(forKey: "inner-phase")
        sheen.removeAnimation(forKey: "sheen-phase")
        core.removeAnimation(forKey: "core-light")
        guard !reducedMotion, phase != "idle" else {
            sheen.opacity = phase == "idle" ? 0.045 : 0.1
            return
        }
        sheen.opacity = 0.1
        let innerScale = CAKeyframeAnimation(keyPath: "transform.scale")
        let innerOpacity = CAKeyframeAnimation(keyPath: "opacity")
        let sheenX = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let sheenOpacity = CAKeyframeAnimation(keyPath: "opacity")
        let times: [NSNumber]
        let duration: CFTimeInterval
        switch phase {
        case "observe":
            innerScale.values = [1.04, 0.93, 0.93, 1.02, 1.04]
            innerOpacity.values = [0.58, 0.94, 0.76, 0.62, 0.58]
            sheenX.values = [-8, 3, 3, -5, -8]
            sheenOpacity.values = [0.05, 0.26, 0.14, 0.07, 0.05]
            times = [0, 0.2, 0.4, 0.74, 1]
            duration = arcade ? 1.65 : 2.4
        case "act":
            innerScale.values = [1, 0.95, 1.035, 1, 1]
            innerOpacity.values = [0.62, 0.78, 0.92, 0.66, 0.62]
            sheenX.values = [-12, -8, 12, 4, -12]
            sheenOpacity.values = [0.04, 0.1, 0.3, 0.08, 0.04]
            times = [0, 0.12, 0.32, 0.5, 1]
            duration = arcade ? 0.72 : 1.05
        case "verify":
            innerScale.values = [1.07, 0.9, 0.9, 1.015, 1.07]
            innerOpacity.values = [0.56, 0.9, 0.96, 0.68, 0.56]
            sheenX.values = [-5, 0, 0, 5, -5]
            sheenOpacity.values = [0.04, 0.16, 0.34, 0.08, 0.04]
            times = [0, 0.16, 0.36, 0.56, 1]
            duration = arcade ? 0.95 : 1.32
        case "wait":
            innerScale.values = [1, 1.045, 1, 1.045, 1, 1]
            innerOpacity.values = [0.5, 0.9, 0.54, 0.82, 0.5, 0.5]
            sheenX.values = [0, 2, 0, 2, 0, 0]
            sheenOpacity.values = [0.03, 0.2, 0.04, 0.16, 0.03, 0.03]
            times = [0, 0.1, 0.2, 0.32, 0.44, 1]
            duration = arcade ? 1.45 : 2.05
        case "recover":
            innerScale.values = [1, 0.9, 1.04, 0.96, 1, 1]
            innerOpacity.values = [0.46, 0.82, 0.58, 0.76, 0.52, 0.46]
            sheenX.values = [0, 8, -6, 4, 0, 0]
            sheenOpacity.values = [0.03, 0.26, 0.08, 0.2, 0.05, 0.03]
            times = [0, 0.12, 0.26, 0.4, 0.56, 1]
            duration = arcade ? 0.92 : 1.3
        default:
            innerScale.values = [0.92, 1.08, 1]
            innerOpacity.values = [0.88, 1, 0.62]
            sheenX.values = [-10, 10, 0]
            sheenOpacity.values = [0.05, 0.42, 0.08]
            times = [0, 0.48, 1]
            duration = arcade ? 0.88 : 1.08
        }
        for animation in [innerScale, innerOpacity, sheenX, sheenOpacity] { animation.keyTimes = times }
        let innerGroup = CAAnimationGroup()
        innerGroup.animations = [innerScale, innerOpacity]
        innerGroup.duration = duration
        innerGroup.repeatCount = phase == "complete" ? 1 : .infinity
        innerGroup.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.78, 0.2, 1)
        inner.add(innerGroup, forKey: "inner-phase")
        let sheenGroup = CAAnimationGroup()
        sheenGroup.animations = [sheenX, sheenOpacity]
        sheenGroup.duration = duration
        sheenGroup.repeatCount = phase == "complete" ? 1 : .infinity
        sheenGroup.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.78, 0.2, 1)
        sheen.add(sheenGroup, forKey: "sheen-phase")
        let light = CAKeyframeAnimation(keyPath: "shadowOpacity")
        light.values = phase == "wait" ? [0.28, 0.48, 0.28, 0.42, 0.28, 0.28] : [0.28, 0.42, 0.31, 0.28]
        light.keyTimes = phase == "wait" ? [0, 0.1, 0.2, 0.32, 0.44, 1] : [0, 0.24, 0.52, 1]
        light.duration = duration
        light.repeatCount = phase == "complete" ? 1 : .infinity
        core.add(light, forKey: "core-light")
    }

    private func animateCoreEvent(_ phase: String) {
        guard !reducedMotion else { return }
        let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
        let scaleY = CAKeyframeAnimation(keyPath: "transform.scale.y")
        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        let times: [NSNumber]
        let duration: CFTimeInterval
        switch phase {
        case "observe":
            scaleX.values = [1, 0.94, 0.94, 1.025, 1]
            scaleY.values = [1, 0.94, 0.94, 1.025, 1]
            translation.values = [0, 0, 0, 0, 0]
            rotation.values = [0, -0.025, 0.02, 0, 0]
            times = [0, 0.18, 0.42, 0.72, 1]
            duration = arcade ? 0.76 : 0.98
        case "act":
            scaleX.values = [1, 0.87, 1.18, 0.96, 1.06, 1]
            scaleY.values = [1, 1.09, 0.88, 1.04, 0.97, 1]
            translation.values = [0, 3, -4.5, 1.5, 0, 0]
            rotation.values = [0, 0.035, -0.025, 0.012, 0, 0]
            times = [0, 0.12, 0.3, 0.48, 0.67, 1]
            duration = arcade ? 0.62 : 0.84
        case "verify":
            scaleX.values = [1, 0.86, 0.86, 1.08, 1.08, 1]
            scaleY.values = [1, 0.86, 0.86, 1.08, 1.08, 1]
            translation.values = [0, 0, 0, 0, 0, 0]
            rotation.values = [0, -0.035, 0.035, 0, 0, 0]
            times = [0, 0.13, 0.34, 0.53, 0.7, 1]
            duration = arcade ? 0.82 : 1.04
        case "wait":
            scaleX.values = [1, 1.055, 1, 1.045, 1, 1]
            scaleY.values = [1, 1.055, 1, 1.045, 1, 1]
            translation.values = [0, 0, 0, 0, 0, 0]
            rotation.values = [0, 0, 0, 0, 0, 0]
            times = [0, 0.12, 0.23, 0.36, 0.48, 1]
            duration = arcade ? 1.05 : 1.35
        case "recover":
            scaleX.values = [1, 0.86, 1.09, 0.92, 1.03, 1]
            scaleY.values = [1, 1.07, 0.9, 1.05, 0.98, 1]
            translation.values = [0, -3.5, 3, -1.8, 0.7, 0]
            rotation.values = [0, -0.14, 0.1, -0.055, 0.018, 0]
            times = [0, 0.14, 0.3, 0.46, 0.66, 1]
            duration = arcade ? 0.82 : 1.06
        default:
            scaleX.values = [1, 0.82, 1.22, 0.96, 1.06, 1]
            scaleY.values = [1, 0.82, 1.22, 0.96, 1.06, 1]
            translation.values = [0, 0, 0, 0, 0, 0]
            rotation.values = [0, -0.025, 0.02, 0, 0, 0]
            times = [0, 0.18, 0.48, 0.7, 0.84, 1]
            duration = arcade ? 0.9 : 1.16
        }
        for animation in [scaleX, scaleY, translation, rotation] { animation.keyTimes = times }
        let group = CAAnimationGroup()
        group.animations = [scaleX, scaleY, translation, rotation]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.18, 0.82, 0.18, 1)
        body.add(group, forKey: "body-event")
        let flash = CAKeyframeAnimation(keyPath: "opacity")
        flash.values = phase == "complete" ? [0.08, 0.62, 0.18, 0.1] : [0.08, 0.3, 0.1]
        flash.keyTimes = phase == "complete" ? [0, 0.45, 0.74, 1] : [0, 0.36, 1]
        flash.duration = duration
        sheen.add(flash, forKey: "sheen-event")
    }

    private func animateRhythmEntry(_ phase: String, color: NSColor) {
        guard !reducedMotion, phase != "idle" else { return }
        rhythmGeneration &+= 1
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = phase == "complete"
            ? [0.96, 0.88, 1.14, 1.02, 1]
            : [1, 0.94, 1.045, 1]
        scale.keyTimes = phase == "complete"
            ? [0, 0.2, 0.48, 0.7, 1]
            : [0, 0.22, 0.62, 1]
        scale.duration = phase == "complete" ? (arcade ? 0.88 : 1.08) : (arcade ? 0.5 : 0.72)
        scale.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.add(scale, forKey: "rhythm-entry")
        playBeatRing(color: color, delay: phase == "complete" ? 0.34 : 0.14, duration: phase == "complete" ? 0.74 : 0.46, power: phase == "complete" ? 1.22 : 1)
    }

    private func animateEventRhythm(_ event: PowerEvent, phase: String, color: NSColor) {
        guard !reducedMotion, event.type != "connected" else { return }
        rhythmGeneration &+= 1
        let generation = rhythmGeneration
        let values: [CGFloat]
        let times: [NSNumber]
        let duration: CFTimeInterval
        switch phase {
        case "observe":
            values = [1, 0.965, 0.965, 1.035, 1]
            times = [0, 0.18, 0.42, 0.72, 1]
            duration = arcade ? 0.76 : 0.98
        case "act":
            values = [1, 0.93, 1.085, 0.985, 1.035, 1]
            times = [0, 0.12, 0.3, 0.47, 0.66, 1]
            duration = arcade ? 0.62 : 0.84
        case "verify":
            values = [1, 0.94, 0.94, 1.075, 1.075, 1]
            times = [0, 0.13, 0.34, 0.53, 0.7, 1]
            duration = arcade ? 0.82 : 1.04
        case "wait":
            values = [1, 1.055, 1, 1.055, 1, 1]
            times = [0, 0.12, 0.23, 0.36, 0.48, 1]
            duration = arcade ? 1.05 : 1.35
        case "recover":
            values = [1, 0.9, 1.055, 0.95, 1.02, 1]
            times = [0, 0.14, 0.3, 0.46, 0.66, 1]
            duration = arcade ? 0.82 : 1.06
        default:
            values = [1, 0.91, 1.13, 1.02, 1]
            times = [0, 0.18, 0.48, 0.72, 1]
            duration = arcade ? 0.9 : 1.16
        }
        let beat = CAKeyframeAnimation(keyPath: "transform.scale")
        beat.values = values
        beat.keyTimes = times
        beat.duration = duration
        beat.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        container.add(beat, forKey: "event-rhythm-\(generation)")

        let ringDelay: CFTimeInterval = phase == "act" ? 0.18 : phase == "verify" ? 0.42 : phase == "complete" ? 0.4 : 0.12
        playBeatRing(color: color, delay: ringDelay, duration: phase == "complete" ? 0.76 : 0.5, power: phase == "complete" ? 1.25 : 1)
        if phase == "wait" {
            playBeatRing(color: color, delay: 0.42, duration: 0.42, power: 0.86)
        }
    }

    private func playBeatRing(color: NSColor, delay: CFTimeInterval, duration: CFTimeInterval, power: CGFloat) {
        beatRing.strokeColor = color.cgColor
        beatRing.shadowColor = color.cgColor
        beatRing.shadowOpacity = Float(0.28 * power)
        beatRing.shadowRadius = 4 * power
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, min(1, 0.8 * power), 0]
        opacity.keyTimes = [0, 0.16, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.88, 1, 1.15 * power]
        scale.keyTimes = [0, 0.18, 1]
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.beginTime = beatRing.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        beatRing.add(group, forKey: "beat-ring-\(rhythmGeneration)-\(delay)")
    }

    private func playSemanticChoreography(phase: String, color: NSColor) {
        guard !reducedMotion, phase != "idle" else { return }
        semanticEffects.sublayers?.forEach { $0.removeFromSuperlayer() }
        switch phase {
        case "observe": playObserveCapture(color: color)
        case "act": playActDrive(color: color)
        case "verify": playVerifyConvergence(color: color)
        case "wait": playWaitGates(color: color)
        case "recover": playRecoverFragments(color: color)
        case "complete": playCompleteRings()
        default: break
        }
    }

    private func makeParticle(size: CGSize, color: NSColor, square: Bool = false) -> CAShapeLayer {
        let layer = CAShapeLayer()
        let boost: CGFloat = arcade ? 1.5 : 1
        layer.bounds = CGRect(origin: .zero, size: CGSize(width: size.width * boost, height: size.height * boost))
        layer.path = square
            ? CGPath(roundedRect: layer.bounds, cornerWidth: 0.45, cornerHeight: 0.45, transform: nil)
            : CGPath(ellipseIn: layer.bounds, transform: nil)
        layer.fillColor = color.cgColor
        layer.shadowColor = color.cgColor
        layer.shadowOpacity = arcade ? 0.9 : 0.62
        layer.shadowRadius = arcade ? 4.5 : 2.8
        layer.compositingFilter = "screenBlendMode"
        layer.opacity = 0
        semanticEffects.addSublayer(layer)
        return layer
    }

    private func animateParticle(_ layer: CALayer, positions: [CGPoint], opacity: [Float], keyTimes: [NSNumber], duration: CFTimeInterval, delay: CFTimeInterval, scales: [CGFloat]? = nil, rotations: [CGFloat]? = nil) {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.values = positions.map { NSValue(point: $0) }
        position.keyTimes = keyTimes
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacity
        fade.keyTimes = keyTimes
        var animations: [CAAnimation] = [position, fade]
        if let scales {
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = scales
            scale.keyTimes = keyTimes
            animations.append(scale)
        }
        if let rotations {
            let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            rotation.values = rotations
            rotation.keyTimes = keyTimes
            animations.append(rotation)
        }
        let group = CAAnimationGroup()
        group.animations = animations
        group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.78, 0.2, 1)
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "semantic-path")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.08) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }

    private func animateParticleAlongPath(_ layer: CALayer, path: CGPath, opacity: [Float], keyTimes: [NSNumber], duration: CFTimeInterval, delay: CFTimeInterval, scales: [CGFloat], rotatesWithPath: Bool = false) {
        let position = CAKeyframeAnimation(keyPath: "position")
        position.path = path
        position.calculationMode = .paced
        if rotatesWithPath { position.rotationMode = .rotateAuto }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacity
        fade.keyTimes = keyTimes
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = scales
        scale.keyTimes = keyTimes
        let group = CAAnimationGroup()
        group.animations = [position, fade, scale]
        group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 0.72, 0.18, 1)
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "semantic-curve")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.08) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }

    private func playObserveCapture(color: NSColor) {
        let count = max(6, Int((arcade ? 15 : 8) * intensity))
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + CGFloat(index % 2) * 0.17
            let radius: CGFloat = arcade ? 82 : 62
            let start = CGPoint(x: 46 + cos(angle) * radius, y: 46 + sin(angle) * radius)
            let end = CGPoint(x: 46 + cos(angle) * 8, y: 46 + sin(angle) * 8)
            let tier = index % 5
            let particleSize: CGFloat = tier == 0 ? 4.4 : tier <= 2 ? 2.8 : 1.9
            let particleColor = tier == 0 ? NSColor.white : tier == 1 ? NSColor.systemCyan : color
            let dot = makeParticle(size: CGSize(width: particleSize, height: particleSize), color: particleColor)
            let tangent = CGPoint(x: -sin(angle), y: cos(angle))
            let curve = CGMutablePath()
            curve.move(to: start)
            curve.addCurve(
                to: end,
                control1: CGPoint(x: start.x + tangent.x * (arcade ? 32 : 22), y: start.y + tangent.y * (arcade ? 32 : 22)),
                control2: CGPoint(x: 46 + cos(angle + 0.72) * 27, y: 46 + sin(angle + 0.72) * 27)
            )
            animateParticleAlongPath(dot, path: curve, opacity: [0, 1, 0.86, 0], keyTimes: [0, 0.12, 0.72, 1], duration: arcade ? 0.98 : 1.08, delay: Double(index) * 0.024, scales: [0.55, 1.15, 0.72, 0.16])
        }
    }

    private func playActDrive(color: NSColor) {
        let count = max(7, Int((arcade ? 18 : 9) * intensity))
        for index in 0..<count {
            let volley = index / 6
            let lane = CGFloat(index % 6) - 2.5
            let start = CGPoint(x: 39, y: 46 + lane * 4.2)
            let recoil = CGPoint(x: 45, y: 46 + lane * 4.2)
            let end = CGPoint(x: -32 - CGFloat(index % 4) * 14, y: 46 + lane * 10)
            let tier = index % 6
            let streak = makeParticle(
                size: CGSize(width: tier == 0 ? 15 : tier <= 2 ? 9 : 5.5, height: tier == 0 ? 2.2 : 1.45),
                color: tier == 0 ? NSColor.white : tier == 1 ? NSColor.systemCyan : color,
                square: true
            )
            let curve = CGMutablePath()
            curve.move(to: start)
            curve.addQuadCurve(to: recoil, control: CGPoint(x: 48, y: start.y - lane))
            curve.addCurve(
                to: end,
                control1: CGPoint(x: 28, y: start.y + lane * 1.8),
                control2: CGPoint(x: end.x + 28, y: end.y - lane * 2.4)
            )
            let volleyDelay = Double(volley) * (arcade ? 0.14 : 0.18) + Double(tier) * 0.016
            animateParticleAlongPath(streak, path: curve, opacity: [0, 1, 0.86, 0], keyTimes: [0, 0.18, 0.7, 1], duration: arcade ? 0.58 : 0.72, delay: volleyDelay, scales: [0.55, 1.16, 0.82, 0.24], rotatesWithPath: true)
        }
    }

    private func playVerifyConvergence(color: NSColor) {
        let lanes = arcade ? 10 : 5
        for index in 0..<lanes {
            let lane = CGFloat(index) - CGFloat(lanes - 1) / 2
            let start = CGPoint(x: -26 - CGFloat(index % 3) * 10, y: 46 + lane * 8)
            let align = CGPoint(x: 20, y: 46 + lane * 5)
            let lock = CGPoint(x: 46, y: 46)
            if index < (arcade ? 5 : 3) {
                let track = CAShapeLayer()
                track.frame = semanticEffects.bounds
                let path = CGMutablePath()
                path.move(to: start)
                path.addLine(to: align)
                path.addLine(to: lock)
                track.path = path
                track.fillColor = NSColor.clear.cgColor
                track.strokeColor = color.withAlphaComponent(0.72).cgColor
                track.lineWidth = arcade ? 1.8 : 1.15
                track.lineCap = .round
                track.shadowColor = color.cgColor
                track.shadowOpacity = arcade ? 0.75 : 0.4
                track.shadowRadius = arcade ? 4 : 2
                semanticEffects.addSublayer(track)
                let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
                draw.values = [0, 1, 1]
                draw.keyTimes = [0, 0.64, 1]
                let fade = CAKeyframeAnimation(keyPath: "opacity")
                fade.values = [0, 1, 0]
                fade.keyTimes = [0, 0.62, 1]
                let group = CAAnimationGroup()
                group.animations = [draw, fade]
                group.duration = arcade ? 0.9 : 1.06
                group.beginTime = track.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.035
                group.fillMode = .both
                group.isRemovedOnCompletion = false
                track.add(group, forKey: "evidence-track")
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.035 + group.duration + 0.08) { [weak track] in track?.removeFromSuperlayer() }
            }
            let evidence = makeParticle(size: CGSize(width: index.isMultiple(of: 2) ? 4.2 : 3, height: index.isMultiple(of: 2) ? 4.2 : 3), color: index.isMultiple(of: 3) ? NSColor.white.withAlphaComponent(0.9) : color, square: true)
            animateParticle(evidence, positions: [start, align, align, lock, lock], opacity: [0, 0.94, 1, 1, 0], keyTimes: [0, 0.28, 0.44, 0.72, 1], duration: arcade ? 0.9 : 1.06, delay: Double(index) * 0.028, scales: [0.7, 1.18, 1, 0.58, 0.2])
        }
    }

    private func playWaitGates(color: NSColor) {
        for side in [-1, 1] {
            let gate = makeParticle(size: CGSize(width: 3, height: 44), color: color, square: true)
            let outside = CGPoint(x: side < 0 ? -12 : 104, y: 46)
            let near = CGPoint(x: side < 0 ? 6 : 86, y: 46)
            let pulse = CGPoint(x: side < 0 ? 10 : 82, y: 46)
            animateParticle(gate, positions: [outside, near, pulse, near, pulse, near], opacity: [0, 0.72, 1, 0.62, 0.9, 0], keyTimes: [0, 0.12, 0.22, 0.36, 0.48, 1], duration: arcade ? 1.05 : 1.35, delay: 0, scales: [0.72, 1, 1.08, 1, 1.05, 1])
        }
    }

    private func playRecoverFragments(color: NSColor) {
        let count = max(7, Int((arcade ? 16 : 8) * intensity))
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2
            let distance: CGFloat = arcade ? 74 : 58
            let center = CGPoint(x: 46, y: 46)
            let broken = CGPoint(x: 46 + cos(angle) * distance, y: 46 + sin(angle) * distance)
            let held = CGPoint(x: 46 + cos(angle + 0.12) * (distance - 6), y: 46 + sin(angle + 0.12) * (distance - 6))
            let shard = makeParticle(size: CGSize(width: index.isMultiple(of: 3) ? 6 : 3.8, height: index.isMultiple(of: 3) ? 6 : 3.8), color: index.isMultiple(of: 4) ? NSColor.white.withAlphaComponent(0.82) : color, square: true)
            let curve = CGMutablePath()
            curve.move(to: center)
            curve.addCurve(
                to: broken,
                control1: CGPoint(x: 46 + cos(angle - 0.7) * 28, y: 46 + sin(angle - 0.7) * 28),
                control2: CGPoint(x: broken.x - sin(angle) * 14, y: broken.y + cos(angle) * 14)
            )
            curve.addCurve(
                to: center,
                control1: held,
                control2: CGPoint(x: 46 + cos(angle + 0.8) * 24, y: 46 + sin(angle + 0.8) * 24)
            )
            animateParticleAlongPath(shard, path: curve, opacity: [0.68, 1, 0.82, 0], keyTimes: [0, 0.3, 0.68, 1], duration: arcade ? 1.08 : 1.24, delay: Double(index % 4) * 0.025, scales: [0.42, 1.08, 0.88, 0.18], rotatesWithPath: true)
        }
    }

    private func playCompleteRings() {
        let colors: [NSColor] = arcade ? [.systemGreen, .systemPurple, .systemCyan] : [.systemGreen]
        for (index, color) in colors.enumerated() {
            let ring = CAShapeLayer()
            ring.frame = semanticEffects.bounds
            ring.path = CGPath(ellipseIn: CGRect(x: 10, y: 10, width: 72, height: 72), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = color.cgColor
            ring.lineWidth = arcade ? 3.2 : 1.8
            ring.shadowColor = color.cgColor
            ring.shadowOpacity = arcade ? 0.9 : 0.55
            ring.shadowRadius = arcade ? 8 : 5
            ring.opacity = 0
            semanticEffects.addSublayer(ring)
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.95, 0.5, 0]
            opacity.keyTimes = [0, 0.12, 0.48, 1]
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.68, 0.92, 1.38, arcade ? 2.15 : 1.7]
            scale.keyTimes = [0, 0.12, 0.48, 1]
            let group = CAAnimationGroup()
            group.animations = [opacity, scale]
            let delay = 0.22 + Double(index) * 0.13
            group.beginTime = ring.convertTime(CACurrentMediaTime(), from: nil) + delay
            group.duration = arcade ? 0.82 : 0.96
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            group.fillMode = .both
            group.isRemovedOnCompletion = false
            ring.add(group, forKey: "complete-wave")
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + group.duration + 0.08) { [weak ring] in ring?.removeFromSuperlayer() }
        }
    }

    private func emitFeedback(for event: PowerEvent, phase: String, color: NSColor) {
        guard !reducedMotion, event.type != "connected" else { return }
        guard phase == "act" || phase == "complete" else {
            emitter.emitterCells = nil
            return
        }
        let cell = CAEmitterCell()
        cell.name = "spark"
        cell.contents = particleImage()
        cell.color = color.cgColor
        let baseRate: Float = event.type == "turn-stop" ? 105 : 48
        cell.birthRate = baseRate * intensity * (arcade ? 1.25 : 1)
        cell.lifetime = arcade ? 0.62 : 0.46
        cell.lifetimeRange = 0.18
        cell.velocity = phase == "act" ? 76 : 54
        cell.velocityRange = 28
        cell.emissionRange = phase == "act" ? .pi / 3 : .pi * 2
        cell.emissionLongitude = phase == "act" ? .pi : 0
        cell.scale = 0.058
        cell.scaleRange = 0.025
        cell.alphaSpeed = -1.25
        emitter.emitterCells = [cell]
        emitter.setValue(cell.birthRate, forKeyPath: "emitterCells.spark.birthRate")
        let burstLength = phase == "act" ? (arcade ? 0.24 : 0.17) : (arcade ? 0.2 : 0.13)
        DispatchQueue.main.asyncAfter(deadline: .now() + burstLength) { [weak emitter] in
            emitter?.setValue(0, forKeyPath: "emitterCells.spark.birthRate")
        }
        let impact = CABasicAnimation(keyPath: "transform.scale")
        impact.fromValue = event.type == "turn-stop" ? 0.9 : 0.96
        impact.toValue = 1
        impact.duration = arcade ? 0.32 : 0.46
        container.add(impact, forKey: "event-impact")
    }

    private func particleImage() -> CGImage? {
        let size = 8
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(NSColor.white.cgColor)
        context.fillEllipse(in: CGRect(x: 1, y: 1, width: 6, height: 6))
        return context.makeImage()
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func phaseGlyph(_ phase: String, completion: String?) -> String {
        if completion == "verified" { return "✓" }
        if completion == "unverified" { return "!" }
        if completion == "cancelled" { return "×" }
        switch phase {
        case "observe": return "◌"
        case "act": return "›"
        case "verify": return "✓"
        case "wait": return "Ⅱ"
        case "recover": return "↻"
        case "complete": return "✓"
        default: return "·"
        }
    }

    private func phaseColor(phase: String, state: PowerState) -> NSColor {
        if state.completion == "cancelled" { return .systemOrange }
        if state.completion == "unverified" { return .systemYellow }
        switch phase {
        case "act": return NSColor(calibratedRed: 0.60, green: 0.45, blue: 0.91, alpha: 1)
        case "verify": return NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.61, alpha: 1)
        case "wait": return NSColor(calibratedRed: 0.91, green: 0.66, blue: 0.29, alpha: 1)
        case "recover": return NSColor(calibratedRed: 0.90, green: 0.35, blue: 0.45, alpha: 1)
        case "complete": return state.completion == "verified" ? NSColor(calibratedRed: 0.30, green: 0.80, blue: 0.61, alpha: 1) : NSColor(calibratedRed: 0.30, green: 0.74, blue: 0.86, alpha: 1)
        case "idle": return NSColor(calibratedWhite: 0.68, alpha: 1)
        default: return NSColor(calibratedRed: 0.30, green: 0.74, blue: 0.86, alpha: 1)
        }
    }
}

@MainActor
private final class TypingFeedbackRenderer {
    private let preferences: PowerModePreferences
    private let root = CALayer()
    private let comboGlow = CATextLayer()
    private let comboValue = CATextLayer()
    private let lifetimeTrack = CALayer()
    private let lifetimeFill = CALayer()
    private let effects = CALayer()
    private var comboAnchor = CGPoint.zero
    private let lifetimeDuration: TimeInterval = 2

    init(hostLayer: CALayer, preferences: PowerModePreferences) {
        self.preferences = preferences
        root.masksToBounds = false
        effects.masksToBounds = false
        root.addSublayer(effects)
        for label in [comboGlow, comboValue] {
            label.bounds = CGRect(x: 0, y: 0, width: 124, height: 62)
            label.alignmentMode = .center
            label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            label.font = NSFont.monospacedSystemFont(ofSize: 34, weight: .black)
            label.fontSize = 34
            label.string = ""
            root.addSublayer(label)
        }
        comboGlow.foregroundColor = NSColor(calibratedRed: 0.18, green: 0.88, blue: 1, alpha: 0.28).cgColor
        comboGlow.shadowColor = NSColor.systemCyan.cgColor
        comboGlow.shadowOpacity = 1
        comboGlow.shadowRadius = 14
        comboValue.foregroundColor = NSColor.white.cgColor
        comboValue.shadowColor = NSColor.systemCyan.cgColor
        comboValue.shadowOpacity = 0.9
        comboValue.shadowRadius = 5
        lifetimeTrack.bounds = CGRect(x: 0, y: 0, width: 80, height: 3)
        lifetimeTrack.cornerRadius = 1.5
        lifetimeTrack.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
        root.addSublayer(lifetimeTrack)
        lifetimeFill.bounds = lifetimeTrack.bounds
        lifetimeFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        lifetimeFill.position = CGPoint(x: -40, y: 1.5)
        lifetimeFill.cornerRadius = 1.5
        lifetimeFill.backgroundColor = NSColor.systemCyan.cgColor
        lifetimeFill.shadowColor = NSColor.systemCyan.cgColor
        lifetimeFill.shadowOpacity = 0.9
        lifetimeFill.shadowRadius = 4
        lifetimeTrack.addSublayer(lifetimeFill)
        setVisible(false)
        hostLayer.addSublayer(root)
    }

    func layout(in bounds: CGRect, beside hud: CGRect) {
        root.frame = bounds
        effects.frame = bounds
        let placeLeft = hud.midX > bounds.midX
        let proposedX = placeLeft ? hud.minX - 66 : hud.maxX + 66
        comboAnchor = CGPoint(
            x: min(bounds.maxX - 70, max(bounds.minX + 70, proposedX)),
            y: min(bounds.maxY - 44, max(bounds.minY + 44, hud.midY))
        )
        comboGlow.position = comboAnchor
        comboValue.position = comboAnchor
        lifetimeTrack.position = CGPoint(x: comboAnchor.x, y: comboAnchor.y - 27)
    }

    func update(count: Int, progress: CGFloat, pulse: Bool = false) {
        guard count > 0, progress > 0 else { setVisible(false); return }
        let label = "×\(count)"
        comboGlow.string = label
        comboValue.string = label
        setVisible(true)
        animateLifetime(progress: progress, refill: pulse)
        guard pulse, !(preferences.settings.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        let hit = CAKeyframeAnimation(keyPath: "transform.scale")
        hit.values = count % 10 == 0 ? [1, 1.38, 0.9, 1.08, 1] : [1, 1.14, 0.96, 1]
        hit.duration = count % 10 == 0 ? 0.38 : 0.16
        comboValue.add(hit, forKey: "typing-combo-hit")
        comboGlow.add(hit, forKey: "typing-combo-glow-hit")
    }

    private func animateLifetime(progress: CGFloat, refill: Bool) {
        if !refill, lifetimeFill.animation(forKey: "typing-lifetime") != nil { return }
        let presentedScale: CGFloat
        if let presentation = lifetimeFill.presentation() {
            presentedScale = presentation.transform.m11
        } else {
            presentedScale = progress
        }
        let current = max(0.001, presentedScale)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lifetimeFill.transform = CATransform3DMakeScale(0.001, 1, 1)
        lifetimeFill.backgroundColor = NSColor.systemRed.cgColor
        CATransaction.commit()
        let scale = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scale.values = refill ? [current, 1, 1, 0.001] : [progress, 0.001]
        scale.keyTimes = refill ? [0, 0.07, 0.12, 1] : [0, 1]
        let color = CAKeyframeAnimation(keyPath: "backgroundColor")
        color.values = [
            NSColor.systemCyan.cgColor,
            NSColor.systemCyan.cgColor,
            NSColor.systemOrange.cgColor,
            NSColor.systemRed.cgColor
        ]
        color.keyTimes = [0, 0.62, 0.84, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, color]
        group.duration = refill ? lifetimeDuration : lifetimeDuration * Double(progress)
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        lifetimeFill.add(group, forKey: "typing-lifetime")
    }

    func emitCursorEffect(at point: CGPoint?, count: Int) {
        guard let point,
              preferences.settings.cursorEffect != "off",
              !(preferences.settings.reducedMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) else { return }
        let neon = (preferences.settings.cursorEffect ?? "spark") == "neon"
        let arcade = preferences.settings.preset == "arcade"
        let milestone = count == 5 || count == 10 || count == 20 || count == 40 || count == 80 || count == 120 || count == 200
        let color: NSColor = count >= 40 ? .systemYellow
            : count >= 20 ? NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.72, alpha: 1)
            : count >= 10 ? NSColor(calibratedRed: 0.62, green: 0.38, blue: 1, alpha: 1)
            : .systemCyan
        let secondary = neon ? NSColor.systemCyan : NSColor.white
        let glyph = CAShapeLayer()
        glyph.frame = effects.bounds
        let glyphPath = CGMutablePath()
        if neon {
            glyphPath.move(to: CGPoint(x: point.x, y: point.y - 10))
            glyphPath.addLine(to: CGPoint(x: point.x, y: point.y + 10))
            glyphPath.move(to: CGPoint(x: point.x + 3, y: point.y - 7))
            glyphPath.addLine(to: CGPoint(x: point.x + 3, y: point.y + 7))
        } else {
            glyphPath.move(to: CGPoint(x: point.x - 5, y: point.y - 5))
            glyphPath.addLine(to: CGPoint(x: point.x, y: point.y + 2))
            glyphPath.addLine(to: CGPoint(x: point.x + 5, y: point.y - 5))
        }
        glyph.path = glyphPath
        glyph.fillColor = NSColor.clear.cgColor
        glyph.strokeColor = color.withAlphaComponent(neon ? 0.96 : 0.84).cgColor
        glyph.lineWidth = neon ? 2.2 : 1.6
        glyph.lineCap = .round
        glyph.lineJoin = .round
        glyph.shadowColor = color.cgColor
        glyph.shadowOpacity = 1
        glyph.shadowRadius = neon ? 8 : 4
        effects.addSublayer(glyph)
        let glyphScale = CAKeyframeAnimation(keyPath: "transform.scale")
        glyphScale.values = neon ? [0.72, 1.18, 0.94] : [0.64, 1.26, 1]
        glyphScale.keyTimes = [0, 0.42, 1]
        let glyphFade = CAKeyframeAnimation(keyPath: "opacity")
        glyphFade.values = [1, 0.86, 0]
        glyphFade.keyTimes = [0, 0.46, 1]
        let glyphPulse = CAAnimationGroup()
        glyphPulse.animations = [glyphScale, glyphFade]
        glyphPulse.duration = neon ? 0.42 : 0.28
        glyphPulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        glyph.add(glyphPulse, forKey: neon ? "caret-neon" : "caret-spark-glyph")
        DispatchQueue.main.asyncAfter(deadline: .now() + glyphPulse.duration + 0.03) { [weak glyph] in glyph?.removeFromSuperlayer() }

        if milestone {
            let milestoneRing = CAShapeLayer()
            milestoneRing.frame = effects.bounds
            milestoneRing.path = CGPath(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18), transform: nil)
            milestoneRing.fillColor = NSColor.clear.cgColor
            milestoneRing.strokeColor = color.cgColor
            milestoneRing.lineWidth = arcade ? 2.4 : 1.7
            milestoneRing.lineDashPattern = neon ? [5, 3] : nil
            milestoneRing.shadowColor = color.cgColor
            milestoneRing.shadowOpacity = 1
            milestoneRing.shadowRadius = arcade ? 9 : 6
            effects.addSublayer(milestoneRing)
            let milestoneScale = CABasicAnimation(keyPath: "transform.scale")
            milestoneScale.fromValue = 0.62
            milestoneScale.toValue = arcade ? 2.65 : 2.1
            let milestoneFade = CABasicAnimation(keyPath: "opacity")
            milestoneFade.fromValue = 1
            milestoneFade.toValue = 0
            let milestonePulse = CAAnimationGroup()
            milestonePulse.animations = [milestoneScale, milestoneFade]
            milestonePulse.duration = arcade ? 0.5 : 0.42
            milestonePulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
            milestoneRing.add(milestonePulse, forKey: "cursor-combo-milestone")
            DispatchQueue.main.asyncAfter(deadline: .now() + milestonePulse.duration + 0.03) { [weak milestoneRing] in milestoneRing?.removeFromSuperlayer() }
        }

        let particleCount = neon
            ? (milestone ? (arcade ? 8 : 6) : (arcade ? 4 : 3))
            : (milestone ? (arcade ? 6 : 4) : (arcade ? 3 : 2))
        for index in 0..<particleCount {
            let spark = CALayer()
            let length: CGFloat = neon ? (milestone ? 6 : 4.5) : (milestone ? 7 : 5)
            spark.bounds = neon
                ? CGRect(x: 0, y: 0, width: length * 0.62, height: length * 0.62)
                : CGRect(x: 0, y: 0, width: 1.5, height: length)
            spark.cornerRadius = neon ? length * 0.31 : 0.75
            spark.position = point
            let particleColor = index.isMultiple(of: 3) ? secondary : color
            spark.backgroundColor = particleColor.cgColor
            spark.shadowColor = particleColor.cgColor
            spark.shadowOpacity = 1
            spark.shadowRadius = neon ? 6 : 3
            effects.addSublayer(spark)
            let phase = CGFloat(count % 7) * 0.11
            let angle: CGFloat = neon
                ? (-.pi / 2 + CGFloat(index) * .pi / CGFloat(max(1, particleCount - 1)) + phase * 0.3)
                : (.pi * 0.18 + CGFloat(index) * .pi * 0.64 / CGFloat(max(1, particleCount - 1)) + phase)
            let distance = (neon ? CGFloat(15 + index % 3 * 4) : CGFloat(9 + index % 3 * 3)) * (milestone ? 1.35 : 1)
            let move = CABasicAnimation(keyPath: "position")
            move.fromValue = point
            move.toValue = CGPoint(x: point.x + cos(angle) * distance, y: point.y + sin(angle) * distance)
            if !neon { spark.setAffineTransform(CGAffineTransform(rotationAngle: angle - .pi / 2)) }
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = neon ? 1 : 0.86
            scale.toValue = neon ? 0.18 : 0.42
            let group = CAAnimationGroup()
            group.animations = [move, fade, scale]
            group.duration = neon ? (milestone ? 0.5 : 0.38) : (milestone ? 0.36 : 0.26)
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            spark.add(group, forKey: neon ? "cursor-neon-particle" : "cursor-spark")
            DispatchQueue.main.asyncAfter(deadline: .now() + group.duration + 0.03) { [weak spark] in spark?.removeFromSuperlayer() }
        }
    }

    func inject(to target: CGPoint, count: Int) {
        guard count > 0 else { return }
        let source = comboAnchor
        let color = NSColor.systemCyan
        for layer in [comboGlow, comboValue, lifetimeTrack] {
            let collapse = CAAnimationGroup()
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1, 1.18, 0.12]
            scale.keyTimes = [0, 0.36, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [1, 1, 0]
            fade.keyTimes = [0, 0.4, 1]
            collapse.animations = [scale, fade]
            collapse.duration = 0.24
            collapse.timingFunction = CAMediaTimingFunction(name: .easeIn)
            layer.opacity = 0
            layer.add(collapse, forKey: "typing-collapse")
        }
        lifetimeFill.removeAnimation(forKey: "typing-lifetime")
        let convergence = CAShapeLayer()
        convergence.frame = effects.bounds
        convergence.path = CGPath(ellipseIn: CGRect(x: source.x - 28, y: source.y - 28, width: 56, height: 56), transform: nil)
        convergence.fillColor = NSColor.clear.cgColor
        convergence.strokeColor = color.cgColor
        convergence.lineWidth = count >= 20 ? 3.5 : 2.2
        convergence.shadowColor = color.cgColor
        convergence.shadowOpacity = 1
        convergence.shadowRadius = 8
        effects.addSublayer(convergence)
        let converge = CAAnimationGroup()
        let convergeScale = CABasicAnimation(keyPath: "transform.scale")
        convergeScale.fromValue = 1.35
        convergeScale.toValue = 0.16
        let convergeFade = CAKeyframeAnimation(keyPath: "opacity")
        convergeFade.values = [0, 1, 0]
        convergeFade.keyTimes = [0, 0.28, 1]
        converge.animations = [convergeScale, convergeFade]
        converge.duration = 0.28
        converge.timingFunction = CAMediaTimingFunction(name: .easeIn)
        convergence.add(converge, forKey: "typing-converge")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) { [weak convergence] in convergence?.removeFromSuperlayer() }
        let streamCount = min(18, max(7, count / 2))
        for index in 0..<streamCount {
            let particle = CALayer()
            let size: CGFloat = count >= 20 ? 5 : 3.5
            particle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            particle.cornerRadius = size / 2
            particle.position = source
            particle.backgroundColor = color.cgColor
            particle.shadowColor = color.cgColor
            particle.shadowOpacity = 1
            particle.shadowRadius = 5
            particle.opacity = 0
            effects.addSublayer(particle)
            let path = CGMutablePath()
            let jitter = CGFloat(index - streamCount / 2) * 2.4
            path.move(to: CGPoint(x: source.x, y: source.y + jitter))
            path.addCurve(
                to: target,
                control1: CGPoint(x: source.x + (target.x - source.x) * 0.28, y: source.y + 72 + jitter),
                control2: CGPoint(x: source.x + (target.x - source.x) * 0.72, y: target.y - 58 - jitter)
            )
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path
            move.duration = 0.48 + Double(index) * 0.018
            move.timingFunction = CAMediaTimingFunction(name: .easeIn)
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 1, 0.18]
            fade.keyTimes = [0, 0.12, 0.72, 1]
            let group = CAAnimationGroup()
            group.animations = [move, fade]
            group.beginTime = CACurrentMediaTime() + 0.18 + Double(index) * 0.008
            group.duration = move.duration
            particle.add(group, forKey: "typing-energy-stream")
            let cleanupDelay = 0.22 + Double(index) * 0.008 + group.duration
            DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak particle] in particle?.removeFromSuperlayer() }
        }
    }

    private func setVisible(_ visible: Bool) {
        let opacity: Float = visible ? 1 : 0
        comboGlow.opacity = opacity
        comboValue.opacity = opacity
        lifetimeTrack.opacity = opacity
        if !visible {
            lifetimeFill.removeAnimation(forKey: "typing-lifetime")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            lifetimeFill.transform = CATransform3DMakeScale(0.001, 1, 1)
            CATransaction.commit()
        }
    }
}

@MainActor
private final class PowerModeView: NSView {
    private let preferences: PowerModePreferences
    private var orbRenderer: OrbLayerRenderer!
    private var typingRenderer: TypingFeedbackRenderer!
    private let usesCompositorRenderer = true
    private var particles: [Particle] = []
    private var shockwaves: [Shockwave] = []
    private var scanBeams: [ScanBeam] = []
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var state = PowerState(sessionId: nil, sessionSource: nil, phase: "observe", status: "ready", momentum: 0, bestMomentum: 0, energyUpdatedAt: nil, combo: 0, bestCombo: 0, comboStatus: "idle", comboHoldUntil: nil, comboExpiresAt: nil, comboBrokenAt: nil, comboRelinkedAt: nil, verificationReward: nil, confidence: 0, riskLevel: "low", currentActivity: "Waiting for Codex activity", completion: nil, turnStoppedAt: nil, lastActivityAt: nil, lastFailureAt: nil, evidence: [], addedLines: 0, removedLines: 0, verifications: 0, mixedConversationCount: nil)
    private var eventText = "POWER MODE ONLINE"
    private var flashAlpha: CGFloat = 0
    private var dangerAlpha: CGFloat = 0
    private var shake: CGFloat = 0
    private var shakePhase: CGFloat = 0
    private var hudExpandedUntil = Date.distantPast
    private var hudWasExpanded = false
    private var comboHoldUntil: Date?
    private var comboExpiresAt: Date?
    private var comboBrokenAt: Date?
    private var comboRelinkedAt: Date?
    private var turnStoppedAt: Date?
    private var lastActivityAt: Date?
    private var lastFailureAt: Date?
    private var semanticPhase = "observe"
    private var semanticPhaseEnteredAt = Date()
    private var comboWasAnimating = false
    private var lastComboStage: String?
    private var reducedFeedbackKind = "focus"
    private var reducedFeedbackUntil: Date?
    private var reducedFeedbackWasActive = false
    private var streamConnected: Bool?
    private var lastLiveEventAt: Date?
    private var lastLiveEventType: String?
    private var lastLiveEventSource: String?
    private var hudAlpha: CGFloat = 0
    private var lastVisualBounds = CGRect.null
    private var effectGeneration = 0
    private var positioning = false
    private var positioningHint = ""
    private var typingComboCount = 0
    private var typingComboLastAt: Date?
    private var typingComboExpiresAt: Date?
    private var dragOffset: CGPoint?
    private var dragPosition: CGPoint?
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var onPositioningFinished: (() -> Void)?
    var onTypingCharge: ((Int, String) -> Void)?
    private var reducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || preferences.settings.reducedMotion }
    private var arcadeMode: Bool { preferences.settings.preset == "arcade" }
    private var effectIntensity: CGFloat {
        switch preferences.settings.effectIntensity ?? "normal" {
        case "low": return 0.62
        case "high": return 1.42
        default: return 1
        }
    }
    private var showsCombo: Bool { preferences.settings.showCombo ?? true }
    private var hudScale: CGFloat { CGFloat(preferences.settings.scale) }
    private var edge: String { preferences.settings.edge }

    override var isOpaque: Bool { false }

    init(frame frameRect: NSRect, preferences: PowerModePreferences) {
        self.preferences = preferences
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        if let layer {
            orbRenderer = OrbLayerRenderer(hostLayer: layer, preferences: preferences)
            typingRenderer = TypingFeedbackRenderer(hostLayer: layer, preferences: preferences)
            orbRenderer.layout(in: currentHudRect())
            typingRenderer.layout(in: bounds, beside: currentHudRect())
            orbRenderer.apply(state: state, presentation: presentationSnapshot(), label: localizedOrbActivity())
            orbRenderer.setVisible(false, animated: false)
        }
        scheduleTick(highFrequency: false, dormant: true)
    }

    private func scheduleTick(highFrequency: Bool, dormant: Bool = false) {
        let activeFramesPerSecond: Double = arcadeMode ? (effectIntensity > 1.2 ? 30 : 45) : 60
        let interval: TimeInterval = highFrequency ? 1.0 / activeFramesPerSecond : dormant ? 1.0 : 0.25
        guard timer == nil || abs(timerInterval - interval) > 0.0001 else { return }
        timer?.invalidate()
        timerInterval = interval
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = highFrequency ? 0.001 : dormant ? 0.15 : 0.04
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    func preferencesChanged() {
        orbRenderer.updatePreferences()
        refreshCompositor()
        scheduleTick(highFrequency: false, dormant: true)
        if !usesCompositorRenderer { invalidateVisuals() }
    }

    override func layout() {
        super.layout()
        orbRenderer?.layout(in: currentHudRect())
        typingRenderer?.layout(in: bounds, beside: currentHudRect())
    }

    private func refreshCompositor(event: PowerEvent? = nil, now: Date = Date()) {
        guard usesCompositorRenderer, orbRenderer != nil else { return }
        let presentation = presentationSnapshot(now: now)
        orbRenderer.layout(in: currentHudRect(now: now))
        orbRenderer.setConnected(streamConnected == true)
        orbRenderer.apply(state: state, presentation: presentation, label: localizedOrbActivity(presentation), event: event)
        let typingProgress = typingComboProgress(now: now)
        typingRenderer.layout(in: bounds, beside: currentHudRect(now: now))
        typingRenderer.update(count: typingProgress > 0 ? typingComboCount : 0, progress: typingProgress)
        orbRenderer.setVisible(shouldShowHUD(now: now))
    }

    private func feedbackBounds() -> CGRect {
        let center = reactorCenter()
        let radius = 108 * min(1.4, max(0.8, hudScale))
        return CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
    }

    private func visualBounds(now: Date = Date()) -> CGRect {
        var result = currentHudRect(now: now).insetBy(dx: -18, dy: -18)
        for particle in particles {
            let radius = particle.radius + 4
            result = result.union(CGRect(
                x: particle.position.x - radius,
                y: particle.position.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        for wave in shockwaves {
            let radius = wave.radius + wave.width + 4
            result = result.union(CGRect(
                x: wave.center.x - radius,
                y: wave.center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
        for beam in scanBeams {
            let progress = 1 - beam.life / beam.maxLife
            let head = beam.origin.x + beam.length * progress
            let trail = beam.length < 0 ? head + 120 : head - 120
            result = result.union(CGRect(
                x: min(head, trail) - 4,
                y: beam.origin.y - 20,
                width: abs(head - trail) + 8,
                height: 40
            ))
        }
        if flashAlpha > 0 || dangerAlpha > 0 { result = result.union(feedbackBounds()) }
        return result.intersection(bounds)
    }

    private func invalidateVisuals(now: Date = Date()) {
        let current = visualBounds(now: now)
        let combined = lastVisualBounds.isNull ? current : lastVisualBounds.union(current)
        let damage = combined.insetBy(dx: -6, dy: -6).intersection(bounds)
        if !damage.isNull && !damage.isEmpty { setNeedsDisplay(damage) }
        lastVisualBounds = current
    }

    func historySummary() -> String {
        let record = state.verificationReward == "record" ? preferences.text("★ NEW · ", "★ 新纪录 · ") : ""
        return record + "\(preferences.text("BEST ENERGY", "最高能量")) \(state.bestMomentum ?? 0)  ·  \(preferences.text("BEST COMBO", "最高连击")) \(state.bestCombo ?? 0)×"
    }

    func activitySourceSummary() -> String {
        let source: String
        switch preferences.settings.activitySource {
        case "mix": source = preferences.text("Mix all conversations", "混合所有对话")
        case "global": source = preferences.text("Follow latest conversation", "跟随最新对话")
        default: source = preferences.text("Keep current conversation", "保持当前对话")
        }
        return "\(preferences.text("Activity source", "动态来源")): \(source)"
    }

    func positionSummary() -> String {
        guard let x = preferences.settings.positionX, let y = preferences.settings.positionY else {
            let labels = [
                "smart": preferences.text("smart · avoids side panels", "智能 · 避让侧栏"),
                "top-right": preferences.text("top right", "右上"),
                "top-left": preferences.text("top left", "左上"),
                "bottom-right": preferences.text("bottom right", "右下"),
                "bottom-left": preferences.text("bottom left", "左下"),
                "center": preferences.text("center", "中央")
            ]
            return "\(preferences.text("Position", "位置")): \(labels[preferences.settings.edge] ?? labels["smart"]!)"
        }
        let horizontal = x < 0.34
            ? preferences.text("left", "左")
            : x > 0.66 ? preferences.text("right", "右") : preferences.text("center", "中")
        let vertical = y < 0.34
            ? preferences.text("bottom", "下")
            : y > 0.66 ? preferences.text("top", "上") : preferences.text("middle", "中")
        if x >= 0.34, x <= 0.66, y >= 0.34, y <= 0.66 {
            return preferences.text("Position: center · saved", "位置：中央 · 已保存")
        }
        return preferences.isChinese
            ? "位置：\(horizontal)\(vertical) · 已保存"
            : "Position: \(vertical) \(horizontal) · saved"
    }

    func sessionSummary() -> (title: String, fullId: String?) {
        if preferences.settings.activitySource == "mix" {
            let count = state.mixedConversationCount ?? 0
            let detail = count > 0
                ? preferences.text("\(count) active", "\(count) 个活跃")
                : preferences.text("waiting for activity", "等待活动")
            return ("\(preferences.text("Mixed conversations", "混合对话")): \(detail)", nil)
        }
        guard let sessionId = state.sessionId, !sessionId.isEmpty else {
            return (preferences.text("Current session: waiting for activity", "当前会话：等待活动"), nil)
        }
        let shortId = sessionId.count > 13
            ? "\(sessionId.prefix(8))…\(sessionId.suffix(4))"
            : sessionId
        return ("\(preferences.text("Current session", "当前会话")): \(shortId)", sessionId)
    }

    func displaySummary() -> String {
        let presentation = presentationSnapshot()
        let phaseLabels = [
            "observe": preferences.text("OBSERVE", "观察"),
            "act": preferences.text("ACT", "执行"),
            "verify": preferences.text("VERIFY", "验证"),
            "wait": preferences.text("WAIT", "等待"),
            "recover": preferences.text("RECOVER", "恢复"),
            "complete": preferences.text("COMPLETE", "完成"),
            "idle": preferences.text("IDLE", "待机")
        ]
        let phase = phaseLabels[presentation.phase] ?? presentation.phase.uppercased()
        return "\(preferences.text("Current display", "当前显示")): \(phase)  ·  \(preferences.text("ENERGY", "能量")) \(presentation.momentum)"
    }

    func rawStateSummary() -> String {
        let phase = (state.phase ?? "unknown").uppercased()
        let status = (state.status ?? "unknown").uppercased()
        return "\(preferences.text("Task state", "任务原始状态")): \(phase)  ·  \(status)  ·  \(preferences.text("ENERGY", "能量")) \(state.momentum ?? 0)"
    }

    func sessionSourceSummary() -> String {
        let source = state.sessionSource ?? lastLiveEventSource
        let label = source == "desktop"
            ? preferences.text("Codex Desktop", "Codex 桌面应用")
            : preferences.text("Waiting for source", "等待来源")
        return "\(preferences.text("Task origin", "任务来源")): \(label)"
    }

    func lastEventSummary(now: Date = Date()) -> String {
        guard let lastLiveEventAt, let lastLiveEventType else {
            return preferences.text("Last real event: none since service start", "最后真实事件：服务启动后暂无")
        }
        let age = max(0, Int(now.timeIntervalSince(lastLiveEventAt)))
        let ageLabel = age < 60
            ? preferences.text("just now", "刚刚")
            : preferences.isChinese ? "\(age / 60) 分钟前" : "\(age / 60)m ago"
        return "\(preferences.text("Last real event", "最后真实事件")): \(lastLiveEventType)  ·  \(ageLabel)"
    }

    func connectionSummary(now: Date = Date()) -> String {
        guard streamConnected == true else {
            return preferences.text("Event connection: reconnecting", "事件连接：正在重连")
        }
        guard let lastLiveEventAt else {
            return preferences.text("Event connection: online · waiting for new activity", "事件连接：在线 · 等待新活动")
        }
        let minutes = max(0, Int(now.timeIntervalSince(lastLiveEventAt) / 60))
        if minutes == 0 {
            return preferences.text("Event connection: online · activity just received", "事件连接：在线 · 刚收到活动")
        }
        return preferences.isChinese
            ? "事件连接：在线 · \(minutes) 分钟前收到活动"
            : "Event connection: online · activity \(minutes)m ago"
    }

    func beginPositioning() {
        positioning = true
        positioningHint = preferences.text("DRAG HUD · EDGES SNAP", "拖动小球 · 靠边吸附")
        hudExpandedUntil = .distantFuture
        hudAlpha = 1
        refreshCompositor()
        if !usesCompositorRenderer { invalidateVisuals() }
    }

    func cancelPositioning() {
        positioning = false
        positioningHint = ""
        dragOffset = nil
        dragPosition = nil
        hudExpandedUntil = Date().addingTimeInterval(1.2)
        refreshCompositor()
        if !usesCompositorRenderer { invalidateVisuals() }
    }

    func hudContains(windowPoint: CGPoint) -> Bool {
        if dragOffset != nil { return true }
        let local = convert(windowPoint, from: nil)
        return currentHudRect().insetBy(dx: -8, dy: -14).contains(local)
    }

    override func mouseDown(with event: NSEvent) {
        guard positioning else { return }
        let point = convert(event.locationInWindow, from: nil)
        let rect = currentHudRect()
        guard rect.insetBy(dx: -8, dy: -14).contains(point) else { return }
        dragOffset = CGPoint(x: point.x - rect.minX, y: point.y - rect.minY)
    }

    override func mouseDragged(with event: NSEvent) {
        guard positioning, let dragOffset else { return }
        let point = convert(event.locationInWindow, from: nil)
        let size = currentHudRect().size
        let origin = CGPoint(x: point.x - dragOffset.x, y: point.y - dragOffset.y)
        let snapDistance: CGFloat = 30
        let placement = hudPlacementBounds()
        let minimumX = placement.minX + size.width / 2
        let maximumX = max(minimumX, placement.maxX - size.width / 2)
        let minimumY = placement.minY + size.height / 2
        let maximumY = max(minimumY, placement.maxY - size.height / 2)
        var centerX = min(maximumX, max(minimumX, origin.x + size.width / 2))
        var centerY = min(maximumY, max(minimumY, origin.y + size.height / 2))
        var horizontalSnap: String?
        var verticalSnap: String?
        if abs(centerX - minimumX) <= snapDistance {
            centerX = minimumX
            horizontalSnap = preferences.text("LEFT", "左侧")
        } else if abs(centerX - maximumX) <= snapDistance {
            centerX = maximumX
            horizontalSnap = preferences.text("RIGHT", "右侧")
        }
        if abs(centerY - minimumY) <= snapDistance {
            centerY = minimumY
            verticalSnap = preferences.text("BOTTOM", "底部")
        } else if abs(centerY - maximumY) <= snapDistance {
            centerY = maximumY
            verticalSnap = preferences.text("TOP", "顶部")
        }
        let snappedEdges = [verticalSnap, horizontalSnap].compactMap { $0 }
        positioningHint = snappedEdges.isEmpty
            ? preferences.text("DRAG HUD · EDGES SNAP", "拖动小球 · 靠边吸附")
            : preferences.text("SNAP ", "吸附 ") + snappedEdges.joined(separator: preferences.isChinese ? " · " : " ")
        dragPosition = CGPoint(x: centerX / max(1, bounds.width), y: centerY / max(1, bounds.height))
        refreshCompositor()
        if !usesCompositorRenderer { invalidateVisuals() }
    }

    override func mouseUp(with event: NSEvent) {
        guard positioning, dragOffset != nil else { return }
        dragOffset = nil
        if let dragPosition {
            preferences.setPosition(x: Double(dragPosition.x), y: Double(dragPosition.y))
            self.dragPosition = nil
        }
        cancelPositioning()
        onPositioningFinished?()
    }

    func setStreamConnected(_ connected: Bool) {
        guard streamConnected != connected else { return }
        streamConnected = connected
        eventText = connected ? preferences.text("EVENT STREAM ONLINE", "事件流已连接") : preferences.text("RECONNECTING TO POWER SERVICE", "正在重新连接")
        hudExpandedUntil = Date().addingTimeInterval(connected ? 1.8 : 3.2)
        refreshCompositor()
        scheduleTick(highFrequency: false, dormant: true)
        if !usesCompositorRenderer { invalidateVisuals() }
    }

    func handleTypingHit(count: Int, lastAt: Date, expiresAt: Date, caretScreenPoint: CGPoint?) {
        typingComboCount = count
        typingComboLastAt = lastAt
        typingComboExpiresAt = expiresAt
        hudExpandedUntil = max(hudExpandedUntil, expiresAt)
        refreshCompositor()
        typingRenderer.update(count: count, progress: 1, pulse: true)
        if let caretScreenPoint, let window {
            let windowPoint = window.convertPoint(fromScreen: caretScreenPoint)
            typingRenderer.emitCursorEffect(at: convert(windowPoint, from: nil), count: count)
        }
        scheduleTick(highFrequency: false)
    }

    private func typingComboProgress(now: Date = Date()) -> CGFloat {
        guard preferences.settings.typingCombo == true,
              typingComboCount > 0,
              let lastAt = typingComboLastAt,
              let expiresAt = typingComboExpiresAt,
              now < expiresAt else { return 0 }
        let duration = max(0.1, expiresAt.timeIntervalSince(lastAt))
        return CGFloat(max(0, min(1, expiresAt.timeIntervalSince(now) / duration)))
    }

    private func consumeTypingCombo(for event: PowerEvent) {
        guard event.preview != true,
              event.type == "activity-start",
              event.toolGroup == "prompt",
              let sessionId = event.sessionId, !sessionId.isEmpty else { return }
        consumeTypingCombo(sessionId: sessionId)
    }

    private func consumeTypingCombo(sessionId: String?) {
        guard typingComboCount > 0,
              let lastAt = typingComboLastAt,
              Date().timeIntervalSince(lastAt) <= 4,
              let sessionId, !sessionId.isEmpty else { return }
        let count = typingComboCount
        typingComboCount = 0
        typingComboLastAt = nil
        typingComboExpiresAt = nil
        typingRenderer.inject(to: reactorCenter(), count: count)
        orbRenderer.playTypingInjection(count: count)
        hudExpandedUntil = Date().addingTimeInterval(2.4)
        onTypingCharge?(count, sessionId)
    }

    func handle(_ event: PowerEvent) {
        consumeTypingCombo(for: event)
        let eventAt = event.timestamp.flatMap(isoDateFormatter.date(from:))
        let previousEnergyLevel = energyLevel(state.momentum ?? 0).name
        if let nextState = event.state {
            let nextPhase = nextState.phase ?? "observe"
            if nextPhase != semanticPhase {
                semanticPhase = nextPhase
                semanticPhaseEnteredAt = event.timestamp.flatMap(isoDateFormatter.date(from:)) ?? Date()
            }
            state = nextState
            comboHoldUntil = nextState.comboHoldUntil.flatMap(isoDateFormatter.date(from:))
            comboExpiresAt = nextState.comboExpiresAt.flatMap(isoDateFormatter.date(from:))
            comboBrokenAt = nextState.comboBrokenAt.flatMap(isoDateFormatter.date(from:))
            comboRelinkedAt = nextState.comboRelinkedAt.flatMap(isoDateFormatter.date(from:))
            turnStoppedAt = nextState.turnStoppedAt.flatMap(isoDateFormatter.date(from:))
            lastActivityAt = nextState.lastActivityAt.flatMap(isoDateFormatter.date(from:))
            lastFailureAt = nextState.lastFailureAt.flatMap(isoDateFormatter.date(from:))
        }
        let currentEnergyLevel = energyLevel(state.momentum ?? 0).name
        let energyUpgrade = energyRank(currentEnergyLevel) > energyRank(previousEnergyLevel) ? currentEnergyLevel : nil
        let triggeredRelink = eventAt.map { eventDate in
            comboRelinkedAt.map { abs(eventDate.timeIntervalSince($0)) < 0.05 } ?? false
        } ?? false
        eventText = describe(event)
        if event.type == "connected" {
            refreshCompositor(event: event)
            if !usesCompositorRenderer { invalidateVisuals() }
            return
        }
        if event.preview != true {
            lastLiveEventAt = eventAt ?? Date()
            lastLiveEventType = event.type
            lastLiveEventSource = event.state?.sessionSource ?? event.sessionSource
        }
        effectGeneration &+= 1
        let generation = effectGeneration
        let switchedSession = event.sessionTransition != nil
        if switchedSession {
            particles.removeAll(keepingCapacity: true)
            shockwaves.removeAll(keepingCapacity: true)
            scanBeams.removeAll(keepingCapacity: true)
        }
        scheduleTick(highFrequency: !reducedMotion)
        let duration: TimeInterval = event.type == "permission-request" || event.type == "edit-failure" || (event.type == "verification" && event.success != true) ? 8 : event.type == "turn-stop" ? 3.2 : 2.2
        hudExpandedUntil = Date().addingTimeInterval(duration)
        if usesCompositorRenderer {
            refreshCompositor(event: event)
            scheduleTick(highFrequency: false, dormant: true)
            return
        }
        let completion = event.state?.completion
        if reducedMotion {
            flashAlpha = 0
        } else if event.type == "turn-stop" && completion == "no-change" {
            flashAlpha = 0.04
        } else if event.type == "turn-stop" && completion == "cancelled" {
            flashAlpha = arcadeMode ? 0.16 : 0.09
        } else if event.type == "turn-stop" && completion == "unverified" {
            flashAlpha = arcadeMode ? 0.20 : 0.12
        } else if event.type == "turn-stop" && completion == "verified" {
            flashAlpha = arcadeMode ? 0.28 : 0.14
        } else {
            flashAlpha = 0.24
        }

        guard !reducedMotion else {
            reducedFeedbackKind = reducedFeedbackKind(for: event)
            reducedFeedbackUntil = Date().addingTimeInterval(event.type == "permission-request" || event.type == "edit-failure" ? 2.4 : 1.35)
            invalidateVisuals()
            return
        }

        if switchedSession {
            shockwave(color: .systemCyan, power: 0.78)
            charge(color: .systemCyan, count: arcadeMode ? 54 : 30)
            scheduleEffect(after: 0.18, generation: generation) { view in
                view.shockwave(color: .systemPurple, power: 0.62)
            }
            invalidateVisuals()
            return
        }

        switch event.type {
        case "activity-start":
            if event.phase == "observe" {
                if event.toolGroup == "prompt" {
                    focusPulse(color: .systemCyan, count: arcadeMode ? 92 : 54)
                    shockwave(color: .systemCyan, power: 0.38)
                    if arcadeMode {
                        scheduleEffect(after: 0.14, generation: generation) { view in
                            view.focusPulse(color: .systemPurple, count: 54)
                            view.shockwave(color: .systemCyan, power: 0.52)
                        }
                    }
                } else {
                    scan(color: .systemCyan, generation: generation)
                    if arcadeMode {
                        scheduleEffect(after: 0.16, generation: generation) { view in
                            view.focusPulse(color: .systemCyan, count: 42)
                        }
                    }
                }
            } else if event.phase == "verify" {
                charge(color: .systemGreen, count: arcadeMode ? 100 : 58)
                scheduleEffect(after: 0.18, generation: generation) { view in
                    view.shockwave(color: .systemGreen, power: 0.42)
                }
                if arcadeMode {
                    scheduleEffect(after: 0.34, generation: generation) { view in
                        view.charge(color: .systemGreen, count: 54)
                        view.shockwave(color: .systemGreen, power: 0.68)
                    }
                }
            } else {
                directionalSparks(color: .systemPurple, count: arcadeMode ? 48 : 26)
                if arcadeMode {
                    shockwave(color: .systemPurple, power: 0.38)
                    scheduleEffect(after: 0.12, generation: generation) { view in
                        view.directionalSparks(color: .systemPink, count: 34)
                    }
                }
            }
        case "permission-request":
            attentionGates(color: .systemYellow, count: arcadeMode ? 72 : 42)
            shockwave(color: .systemYellow, power: 0.58)
            scheduleEffect(after: 0.26, generation: generation) { view in
                view.attentionGates(color: .systemYellow, count: view.arcadeMode ? 48 : 28)
                view.shockwave(color: .systemYellow, power: 0.42)
            }
        case "edit":
            let added = event.addedLines ?? 0
            let removed = event.removedLines ?? 0
            let addedChars = event.addedChars ?? added * 24
            let primary = removed > added ? NSColor.systemPink : NSColor.systemPurple
            shake = min(8, 1.5 + CGFloat(added + removed) * 0.12)
            shockwave(color: primary, power: min(1.8, 0.8 + CGFloat(added + removed) / 30))
            burst(color: primary, count: max(18, min(130, added * 3 + removed * 4)), power: 1.0, directional: true)
            replayTyping(characters: addedChars, lines: added, generation: generation)
            if removed > 0 { deletionSparks(lines: removed) }
        case "edit-failure":
            shockwave(color: .systemRed, power: 1.15)
            fragments(color: .systemRed, count: arcadeMode ? 132 : 82)
            scheduleEffect(after: 0.18, generation: generation) { view in
                view.shockwave(color: .systemRed, power: 0.68)
            }
            dangerAlpha = 0.42
            shake = 12
            scheduleEffect(after: 0.30, generation: generation) { view in
                view.repairFragments(color: NSColor.systemPink.withAlphaComponent(0.82), count: view.arcadeMode ? 112 : 68)
            }
        case "verification":
            let passed = event.success == true
            if passed {
                switch event.state?.verificationReward {
                case "record":
                    shockwave(color: .systemYellow, power: arcadeMode ? 2.15 : 1.15)
                    charge(color: .systemYellow, count: arcadeMode ? 140 : 72)
                    shake = arcadeMode ? 6 : 2.5
                    scheduleEffect(after: 0.18, generation: generation) { view in
                        view.shockwave(color: .systemCyan, power: view.arcadeMode ? 1.55 : 0.72)
                        view.burst(color: .systemCyan, count: view.arcadeMode ? 96 : 42, power: 1.0)
                    }
                case "evidence":
                    shockwave(color: .systemGreen, power: arcadeMode ? 1.8 : 1.05)
                    charge(color: .systemGreen, count: arcadeMode ? 120 : 62)
                    scheduleEffect(after: 0.24, generation: generation) { view in
                        view.shockwave(color: .systemGreen, power: view.arcadeMode ? 0.82 : 0.48)
                    }
                default:
                    charge(color: .systemGreen, count: arcadeMode ? 64 : 34)
                    shockwave(color: .systemGreen, power: arcadeMode ? 0.88 : 0.52)
                }
            } else {
                shockwave(color: .systemRed, power: 1.1)
                burst(color: .systemRed, count: 88, power: 0.9)
                fragments(color: .systemRed, count: arcadeMode ? 120 : 72)
                dangerAlpha = 0.38
                shake = 10
                scheduleEffect(after: 0.30, generation: generation) { view in
                    view.repairFragments(color: NSColor.systemPink.withAlphaComponent(0.82), count: view.arcadeMode ? 96 : 58)
                }
            }
        case "turn-stop" where event.state?.completion == "verified":
            if arcadeMode {
                shockwave(color: .systemGreen, power: 2.2)
                burst(color: NSColor.systemGreen, count: 180, power: 1.55)
                scheduleEffect(after: 0.18, generation: generation) { view in
                    view.shockwave(color: .systemPurple, power: 2.0)
                    view.burst(color: .systemPurple, count: 150, power: 1.5)
                }
                scheduleEffect(after: 0.36, generation: generation) { view in
                    view.shockwave(color: .systemCyan, power: 1.8)
                    view.burst(color: .systemCyan, count: 120, power: 1.45)
                }
            } else {
                charge(color: .systemGreen, count: 48)
                shockwave(color: .systemGreen, power: 0.92)
            }
        case "turn-stop" where event.state?.completion == "cancelled":
            shockwave(color: .systemOrange, power: arcadeMode ? 0.92 : 0.62)
            fragments(color: .systemOrange, count: arcadeMode ? 72 : 34)
            shake = arcadeMode ? 6 : 2.5
            if arcadeMode {
                scheduleEffect(after: 0.16, generation: generation) { view in
                    view.directionalSparks(color: .systemOrange, count: 32)
                }
            }
        case "turn-stop" where event.state?.completion == "unverified":
            charge(color: .systemYellow, count: arcadeMode ? 68 : 34)
            shockwave(color: .systemYellow, power: arcadeMode ? 0.82 : 0.58)
            scheduleEffect(after: 0.24, generation: generation) { view in
                view.attentionGates(color: .systemYellow, count: view.arcadeMode ? 46 : 24)
                if view.arcadeMode { view.shockwave(color: .systemYellow, power: 0.46) }
            }
        case "turn-stop" where event.state?.completion == "no-change":
            focusPulse(color: NSColor.systemCyan.withAlphaComponent(0.58), count: arcadeMode ? 28 : 16)
            shockwave(color: .systemCyan, power: 0.24)
        default:
            break
        }
        if triggeredRelink {
            charge(color: .systemCyan, count: arcadeMode ? 72 : 34)
            shockwave(color: .systemCyan, power: arcadeMode ? 0.72 : 0.38)
        }
        if let energyUpgrade { playEnergyUpgrade(energyUpgrade, generation: generation) }
        invalidateVisuals()
    }

    private func playEnergyUpgrade(_ level: String, generation: Int) {
        switch level {
        case "awakening":
            shockwave(color: .systemCyan, power: arcadeMode ? 0.42 : 0.24)
        case "charging":
            charge(color: .systemCyan, count: arcadeMode ? 58 : 28)
            shockwave(color: .systemCyan, power: arcadeMode ? 0.72 : 0.42)
        case "driving", "high-energy":
            shockwave(color: .systemPurple, power: arcadeMode ? 1.18 : 0.68)
            charge(color: .systemPurple, count: arcadeMode ? 92 : 44)
            if arcadeMode {
                scheduleEffect(after: 0.16, generation: generation) { view in
                    view.shockwave(color: .systemCyan, power: 0.82)
                }
            }
        case "overload", "critical", "verified-peak":
            shockwave(color: .systemYellow, power: arcadeMode ? 1.72 : 0.92)
            burst(color: .systemYellow, count: arcadeMode ? 132 : 58, power: arcadeMode ? 1.18 : 0.78)
            shake = max(shake, arcadeMode ? 5.5 : 2.2)
            scheduleEffect(after: 0.18, generation: generation) { view in
                view.shockwave(color: .systemCyan, power: view.arcadeMode ? 1.28 : 0.62)
            }
        default:
            break
        }
    }

    private func reducedFeedbackKind(for event: PowerEvent) -> String {
        if event.sessionTransition != nil { return "switch" }
        switch event.type {
        case "activity-start":
            return event.phase == "verify" ? "verify" : event.phase == "act" ? "act" : "focus"
        case "input-charge": return "focus"
        case "permission-request": return "wait"
        case "edit": return "act"
        case "edit-failure": return "recover"
        case "verification":
            if event.success != true { return "recover" }
            if event.state?.verificationReward == "record" { return "record" }
            return event.state?.verificationReward == "confirmation" ? "confirmed" : "verified"
        case "turn-stop":
            switch event.state?.completion {
            case "verified": return "verified"
            case "unverified": return "caution"
            case "cancelled": return "cancelled"
            default: return "no-change"
            }
        default: return "focus"
        }
    }

    private func describe(_ event: PowerEvent) -> String {
        if event.sessionTransition != nil { return preferences.text("TASK SWITCHED", "任务已切换") }
        switch event.type {
        case "activity-start":
            if event.toolGroup == "prompt" { return preferences.text("UNDERSTANDING REQUEST", "正在理解需求") }
            return event.phase == "observe" ? preferences.text("READING CONTEXT", "正在读取上下文") : event.phase == "verify" ? preferences.text("BUILDING EVIDENCE", "正在建立验证证据") : preferences.text("STARTING TOOL", "正在执行工具")
        case "input-charge": return preferences.text("INPUT COMBO ABSORBED", "输入连击已注能") + "  ×\(event.inputCombo ?? 0)"
        case "permission-request": return preferences.text("WAITING FOR YOUR APPROVAL", "等待你的授权")
        case "edit": return preferences.text("CHANGE APPLIED", "修改已应用") + "  +\(event.addedLines ?? 0)  −\(event.removedLines ?? 0)"
        case "edit-failure": return preferences.text("CHANGE COULD NOT BE APPLIED", "修改应用失败")
        case "verification":
            let result = "\(localizedCategory(event.category)) \(event.success == true ? preferences.text("PASSED", "通过") : preferences.text("FAILED", "失败"))"
            return event.state?.verificationReward == "record" ? preferences.text("NEW BEST", "刷新纪录") + " · " + result : result
        case "turn-stop":
            switch event.state?.completion {
            case "verified": return preferences.text("COMPLETED WITH EVIDENCE", "已完成并通过验证")
            case "cancelled": return preferences.text("APPROVAL WAS NOT GRANTED", "未获得授权")
            case "no-change": return preferences.text("TURN COMPLETE — NO CODE CHANGES", "回合完成 — 无代码修改")
            default: return preferences.text("VERIFICATION RECOMMENDED", "建议进行验证")
            }
        case "connected": return preferences.text("POWER MODE ONLINE", "POWER MODE 已连接")
        default: return event.type.uppercased()
        }
    }

    private func localizedCategory(_ category: String?) -> String {
        switch category {
        case "test": return preferences.text("TEST", "测试")
        case "build": return preferences.text("BUILD", "构建")
        case "lint": return preferences.text("LINT", "检查")
        default: return preferences.text("CHECK", "验证")
        }
    }

    private func localizedPhase(_ phase: String) -> String {
        if phase != "IDLE" && state.completion == "cancelled" { return preferences.text("CANCELLED", "已取消") }
        if phase != "IDLE" && state.completion == "unverified" { return preferences.text("UNVERIFIED", "未验证") }
        switch phase {
        case "OBSERVE": return preferences.text("OBSERVE", "观察")
        case "ACT": return preferences.text("ACT", "执行")
        case "VERIFY": return preferences.text("VERIFY", "验证")
        case "WAIT": return preferences.text("WAIT", "等待")
        case "RECOVER": return preferences.text("RECOVER", "恢复")
        case "COMPLETE": return preferences.text("COMPLETE", "完成")
        case "IDLE": return preferences.text("IDLE", "待机")
        default: return phase
        }
    }

    private func localizedActivity(idle: Bool = false) -> String {
        if idle { return preferences.text("Waiting for Codex activity", "等待 Codex 活动") }
        if state.currentActivity == "Understanding request" { return preferences.text("Understanding your request", "正在理解你的需求") }
        if state.status == "needs-attention" { return preferences.text("Waiting for your approval", "等待你的授权") }
        if state.status == "failed" || state.phase == "recover" { return preferences.text("Repairing the latest failure", "正在修复最近的失败") }
        if state.completion == "verified" { return preferences.text("Latest changes are backed by evidence", "最新修改已有验证证据") }
        if state.completion == "unverified" { return preferences.text("Verification is recommended", "建议进行验证") }
        if state.phase == "verify" { return preferences.text("Building confidence in the change", "正在验证修改") }
        if state.phase == "act" { return preferences.text("Applying a scoped change", "正在执行修改") }
        if state.phase == "observe" { return preferences.text("Reading and understanding context", "正在读取并理解上下文") }
        return preferences.text("Codex is working", "Codex 正在工作")
    }

    private func localizedOrbActivity(_ presentation: (phase: String, status: String, momentum: Int, idle: Bool, settled: Bool, returning: Bool, settledAt: Date?)? = nil) -> String {
        let snapshot = presentation ?? presentationSnapshot()
        if positioning { return preferences.text("DRAG", "拖动") }
        if typingComboProgress() > 0 { return preferences.text("TYPING", "输入中") }
        if streamConnected == false { return preferences.text("RECONNECT", "重连中") }
        if snapshot.idle || snapshot.phase == "idle" { return preferences.text("IDLE", "待机") }
        if state.status == "needs-attention" || snapshot.phase == "wait" { return preferences.text("APPROVAL", "等待授权") }
        if state.status == "failed" || snapshot.phase == "recover" { return preferences.text("RECOVER", "修复中") }
        if state.completion == "verified" { return preferences.text("VERIFIED", "已验证") }
        if state.completion == "unverified" { return preferences.text("CHECK", "待验证") }
        if state.completion == "cancelled" { return preferences.text("CANCELLED", "已取消") }
        if state.completion == "no-change" { return preferences.text("DONE", "已完成") }
        if state.currentActivity == "Understanding request" { return preferences.text("THINKING", "理解需求") }
        let activity = (state.currentActivity ?? "").lowercased()
        switch snapshot.phase {
        case "observe": return activity.contains("search") ? preferences.text("SEARCH", "搜索") : preferences.text("READING", "读取上下文")
        case "act": return activity.contains("command") ? preferences.text("COMMAND", "执行命令") : preferences.text("CHANGE", "修改中")
        case "verify":
            if activity.contains("test") { return preferences.text("TESTING", "测试中") }
            if activity.contains("build") { return preferences.text("BUILDING", "构建中") }
            return preferences.text("VERIFY", "验证中")
        case "complete": return preferences.text("COMPLETE", "已完成")
        default: return preferences.text("WORKING", "工作中")
        }
    }

    private func hudOrigin(size: CGSize) -> CGPoint {
        let preferredMargin: CGFloat = 36
        let placement = hudPlacementBounds()
        let minimumX = placement.minX
        let maximumX = max(minimumX, placement.maxX - size.width)
        let minimumY = placement.minY
        let maximumY = max(minimumY, placement.maxY - size.height)
        let storedPosition = dragPosition ?? {
            guard let x = preferences.settings.positionX, let y = preferences.settings.positionY else { return nil }
            return CGPoint(x: x, y: y)
        }()
        if let storedPosition {
            let desired = CGPoint(
                x: bounds.width * storedPosition.x - size.width / 2,
                y: bounds.height * storedPosition.y - size.height / 2
            )
            return CGPoint(
                x: min(maximumX, max(minimumX, desired.x)),
                y: min(maximumY, max(minimumY, desired.y))
            )
        }
        let left = min(minimumX + preferredMargin, maximumX)
        let right = max(minimumX, maximumX - preferredMargin)
        let bottom = min(minimumY + preferredMargin, maximumY)
        let top = max(minimumY, maximumY - preferredMargin)
        switch edge {
        case "smart":
            let topInset: CGFloat = placement.height >= 640 ? 72 : preferredMargin
            let sidePanelReserve: CGFloat = placement.width >= 1_400
                ? min(420, max(300, placement.width * 0.22))
                : preferredMargin
            return CGPoint(
                x: max(minimumX, placement.maxX - size.width - sidePanelReserve),
                y: max(minimumY, placement.maxY - size.height - topInset)
            )
        case "top-left": return CGPoint(x: left, y: top)
        case "bottom-left": return CGPoint(x: left, y: bottom)
        case "bottom-right": return CGPoint(x: right, y: bottom)
        case "center": return CGPoint(x: placement.midX - size.width / 2, y: placement.midY - size.height / 2)
        default: return CGPoint(x: right, y: top)
        }
    }

    private func hudPlacementBounds() -> CGRect {
        var visibleBounds: CGRect?
        if let window, let screen = window.screen {
            let visibleInWindow = window.convertFromScreen(screen.visibleFrame)
            visibleBounds = convert(visibleInWindow, from: nil)
        }
        return resolvedHudPlacementBounds(viewBounds: bounds, visibleBounds: visibleBounds)
    }

    private func effectiveHudScale(for baseSize: CGSize) -> CGFloat {
        let placement = hudPlacementBounds()
        let safeWidth = max(1, placement.width)
        let safeHeight = max(1, placement.height)
        return min(hudScale, safeWidth / baseSize.width, safeHeight / baseSize.height)
    }

    private func hudBaseSize(expanded: Bool? = nil) -> CGSize { CGSize(width: 92, height: 92) }

    private func currentHudRect(now: Date = Date()) -> CGRect {
        let baseSize = hudBaseSize()
        let scale = effectiveHudScale(for: baseSize)
        let size = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        return CGRect(origin: hudOrigin(size: size), size: size)
    }

    private func presentationSnapshot(now: Date = Date()) -> (phase: String, status: String, momentum: Int, idle: Bool, settled: Bool, returning: Bool, settledAt: Date?) {
        let phase = state.phase ?? "observe"
        let status = state.status ?? "ready"
        let baseMomentum = min(999, max(0, state.momentum ?? 0))
        let energyUpdatedAt = state.energyUpdatedAt.flatMap(isoDateFormatter.date(from:)) ?? lastActivityAt
        let decayProgress = energyUpdatedAt.map { min(1, max(0, now.timeIntervalSince($0.addingTimeInterval(20)) / 90)) } ?? 0
        let momentum = Int((Double(baseMomentum) * (1 - decayProgress)).rounded())
        let canSettleAbandoned = ["observe", "act", "verify"].contains(phase) && status != "needs-attention" && status != "failed"
        let canSettleRecovery = phase == "recover" && status == "failed"
        let recoveryAt = lastFailureAt ?? lastActivityAt
        let effectiveStopAt = turnStoppedAt
            ?? (canSettleRecovery ? recoveryAt?.addingTimeInterval(15) : nil)
            ?? (canSettleAbandoned ? lastActivityAt?.addingTimeInterval(5 * 60) : nil)
        guard let effectiveStopAt else { return (phase, status, momentum, false, false, false, nil) }
        let finalHoldEnd = effectiveStopAt.addingTimeInterval(3)
        let disconnectedAt = comboBrokenAt ?? comboExpiresAt
        let comboEnd = disconnectedAt?.addingTimeInterval(3.2) ?? .distantPast
        let idleAt = max(finalHoldEnd, comboEnd)
        let settledAt = idleAt.addingTimeInterval(4)
        guard now >= idleAt else { return (phase, status, momentum, false, false, false, settledAt) }
        let progress = min(1, max(0, now.timeIntervalSince(idleAt) / 4))
        return ("idle", "ready", Int((Double(momentum) * (1 - progress)).rounded()), true, progress >= 1, progress < 1, settledAt)
    }

    private func shouldShowHUD(now: Date) -> Bool {
        guard preferences.settings.enabled else { return false }
        if typingComboProgress(now: now) > 0 { return true }
        if positioning || streamConnected != true { return true }
        if preferences.settings.idleBehavior != "hide" { return true }
        if state.phase == "wait" || state.status == "needs-attention" { return true }
        let presentation = presentationSnapshot(now: now)
        if presentation.phase == "recover" || presentation.status == "failed" { return true }
        if presentation.status == "working" { return true }
        if now < hudExpandedUntil { return true }
        if showsCombo {
            let combo = comboSnapshot(now: now)
            if combo.active || combo.lost { return true }
        }
        if presentation.returning { return true }
        if idleGraceIsActive(now: now, settledAt: presentation.settledAt, delay: preferences.settings.autoHideDelay) {
            return true
        }
        return false
    }

    private func reactorCenter() -> CGPoint {
        let baseSize = hudBaseSize()
        let scale = effectiveHudScale(for: baseSize)
        let scaledSize = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let origin = hudOrigin(size: scaledSize)
        return CGPoint(x: origin.x + 46 * scale, y: origin.y + 46 * scale)
    }

    private func codingOrigin() -> CGPoint {
        let center = reactorCenter()
        return CGPoint(
            x: min(bounds.maxX - 24, max(bounds.minX + 24, center.x + CGFloat.random(in: -240...140))),
            y: min(bounds.maxY - 24, max(bounds.minY + 24, center.y + CGFloat.random(in: -105...105)))
        )
    }

    private func scheduleEffect(after delay: TimeInterval, generation: Int, _ effect: @escaping (PowerModeView) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.effectGeneration == generation else { return }
            effect(self)
        }
    }

    private func replayTyping(characters: Int, lines: Int, generation: Int) {
        let base = max(4, min(32, max(lines, characters / 22)))
        let presetPulses = arcadeMode ? min(44, Int(Double(base) * 1.45)) : base
        let pulses = scaledEffectCount(presetPulses)
        for index in 0..<pulses {
            scheduleEffect(after: Double(index) * 0.028, generation: generation) { view in
                view.typingPulse(index: index)
            }
        }
    }

    private func typingPulse(index: Int) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        let color: NSColor = index.isMultiple(of: 4) ? .systemPurple : .systemCyan
        for _ in 0..<scaledEffectCount(Int.random(in: 4...8)) {
            let life = CGFloat.random(in: 22...48)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: -6.0 ... -1.8), dy: CGFloat.random(in: -2.8...3.6)),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.1...3.1),
                color: color
            ))
        }
        invalidateVisuals()
    }

    private func scan(color: NSColor, echo: Bool = true, generation: Int) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        let life: CGFloat = 58
        scanBeams.append(ScanBeam(origin: origin, length: -min(280, max(60, origin.x - 48)), life: life, maxLife: life, color: color))
        if arcadeMode && echo {
            scheduleEffect(after: 0.16, generation: generation) { view in
                view.scan(color: color.withAlphaComponent(0.7), echo: false, generation: generation)
            }
        }
    }

    private func focusPulse(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let center = reactorCenter()
        for _ in 0..<scaledEffectCount(count) {
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 52...210)
            let life = CGFloat.random(in: 40...62)
            particles.append(Particle(
                position: CGPoint(x: center.x + cos(angle) * distance, y: center.y + sin(angle) * distance),
                velocity: .zero,
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.0...2.8),
                color: color,
                target: center
            ))
        }
    }

    private func directionalSparks(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        for _ in 0..<scaledEffectCount(count) {
            let life = CGFloat.random(in: 24...52)
            particles.append(Particle(
                position: origin,
                velocity: CGVector(dx: CGFloat.random(in: -7.4 ... -2.2), dy: CGFloat.random(in: -3.2...3.2)),
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.0...2.8),
                color: color
            ))
        }
    }

    private func charge(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let target = reactorCenter()
        let source = codingOrigin()
        for index in 0..<scaledEffectCount(count) {
            let lane = CGFloat(index % 4) - 1.5
            let life = CGFloat.random(in: 38...58)
            particles.append(Particle(
                position: CGPoint(
                    x: source.x + CGFloat.random(in: -36...130),
                    y: source.y + lane * 18 + CGFloat.random(in: -3...3)
                ),
                velocity: .zero,
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.0...2.5),
                color: color,
                target: target,
                square: true
            ))
        }
    }

    private func attentionGates(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let center = reactorCenter()
        for index in 0..<scaledEffectCount(count) {
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let lane = CGFloat((index / 2) % 5) - 2
            let life = CGFloat.random(in: 30...46)
            particles.append(Particle(
                position: CGPoint(
                    x: center.x + side * CGFloat.random(in: 68...210),
                    y: center.y + lane * 11 + CGFloat.random(in: -2...2)
                ),
                velocity: .zero,
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.2...3.0),
                color: color,
                target: CGPoint(x: center.x + side * 38, y: center.y + lane * 7),
                square: true
            ))
        }
    }

    private func repairFragments(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let center = reactorCenter()
        for index in 0..<scaledEffectCount(count) {
            let side: CGFloat = index.isMultiple(of: 2) ? -1 : 1
            let lane = CGFloat((index / 2) % 4) - 1.5
            let life = CGFloat.random(in: 38...58)
            particles.append(Particle(
                position: CGPoint(
                    x: center.x + side * CGFloat.random(in: 44...190),
                    y: center.y + lane * 18 + CGFloat.random(in: -5...5)
                ),
                velocity: .zero,
                life: life,
                maxLife: life,
                radius: CGFloat.random(in: 1.2...3.2),
                color: color,
                target: center,
                square: true
            ))
        }
    }

    private func fragments(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        for _ in 0..<scaledEffectCount(count) {
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
        let count = scaledEffectCount(min(90, max(12, lines * 6)))
        let origin = reactorCenter()
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
            center: reactorCenter(),
            radius: 8,
            life: life,
            maxLife: life,
            width: 2.2 * power * (0.88 + effectIntensity * 0.12),
            color: color
        ))
    }

    private func burst(color: NSColor, count: Int, power: CGFloat, directional: Bool = false) {
        let center = reactorCenter()
        let presetCount = arcadeMode ? Int(Double(count) * 1.55) : count
        let scaledCount = scaledEffectCount(presetCount)
        let scaledPower = power * (0.88 + effectIntensity * 0.12)
        for _ in 0..<min(scaledCount, 280) {
            let angle = directional ? CGFloat.random(in: (.pi - 0.65)...(.pi + 0.65)) : CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 1.7...7.5) * scaledPower
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

    private func scaledEffectCount(_ count: Int) -> Int {
        max(1, Int((CGFloat(count) * effectIntensity).rounded()))
    }

    private func tick() {
        let now = Date()
        if usesCompositorRenderer {
            refreshCompositor(now: now)
            scheduleTick(highFrequency: false, dormant: true)
            return
        }
        let frameStep = max(0.5, min(2.5, CGFloat(timerInterval * 60)))
        let particleBudget = scaledEffectCount(arcadeMode ? 560 : 280)
        let shockwaveBudget = scaledEffectCount(arcadeMode ? 18 : 10)
        let scanBudget = scaledEffectCount(arcadeMode ? 8 : 4)
        if particles.count > particleBudget { particles.removeFirst(particles.count - particleBudget) }
        if shockwaves.count > shockwaveBudget { shockwaves.removeFirst(shockwaves.count - shockwaveBudget) }
        if scanBeams.count > scanBudget { scanBeams.removeFirst(scanBeams.count - scanBudget) }
        if !particles.isEmpty {
            for index in particles.indices {
                if let target = particles[index].target {
                    particles[index].velocity.dx = (target.x - particles[index].position.x) * 0.075
                    particles[index].velocity.dy = (target.y - particles[index].position.y) * 0.075
                } else {
                    particles[index].velocity.dy = (particles[index].velocity.dy - 0.065 * frameStep) * pow(0.982, frameStep)
                    particles[index].velocity.dx *= pow(0.975, frameStep)
                }
                particles[index].position.x += particles[index].velocity.dx * frameStep
                particles[index].position.y += particles[index].velocity.dy * frameStep
                particles[index].life -= frameStep
            }
            particles.removeAll { $0.life <= 0 }
        }
        if !scanBeams.isEmpty {
            for index in scanBeams.indices { scanBeams[index].life -= frameStep }
            scanBeams.removeAll { $0.life <= 0 }
        }
        if !shockwaves.isEmpty {
            for index in shockwaves.indices {
                shockwaves[index].radius += 5.4 * frameStep
                shockwaves[index].life -= frameStep
            }
            shockwaves.removeAll { $0.life <= 0 }
        }
        flashAlpha = max(0, flashAlpha - 0.012 * frameStep)
        dangerAlpha = max(0, dangerAlpha - 0.009 * frameStep)
        shake = max(0, shake * pow(0.88, frameStep) - 0.04 * frameStep)
        shakePhase += frameStep
        let comboTimelineEnd = (comboBrokenAt ?? comboExpiresAt ?? .distantPast).addingTimeInterval(3.2)
        let comboIsAnimating = showsCombo && now < comboTimelineEnd
        if comboIsAnimating != comboWasAnimating {
            comboWasAnimating = comboIsAnimating
            invalidateVisuals(now: now)
        }
        let currentComboStage = showsCombo ? comboSnapshot(now: now).stage : "idle"
        if let previousComboStage = lastComboStage,
           currentComboStage == "lost",
           previousComboStage != "lost",
           previousComboStage != "idle",
           !reducedMotion {
            shockwave(color: .systemRed, power: arcadeMode ? 0.78 : 0.42)
            fragments(color: .systemRed, count: arcadeMode ? 54 : 24)
            shake = arcadeMode ? 5 : 1.8
        }
        lastComboStage = currentComboStage
        let reducedFeedbackActive = reducedMotion && now < (reducedFeedbackUntil ?? .distantPast)
        if reducedFeedbackActive != reducedFeedbackWasActive {
            reducedFeedbackWasActive = reducedFeedbackActive
            invalidateVisuals(now: now)
        }
        let hasEffects = !particles.isEmpty || !shockwaves.isEmpty || !scanBeams.isEmpty || flashAlpha > 0 || dangerAlpha > 0 || shake > 0
        let comboIsDecaying = showsCombo && (comboHoldUntil.map { now >= $0 } ?? true) && now < (comboExpiresAt ?? .distantPast)
        let presentation = presentationSnapshot(now: now)
        let targetAlpha: CGFloat = shouldShowHUD(now: now) ? 1 : 0
        let previousAlpha = hudAlpha
        let fadeStep: CGFloat = reducedMotion ? 1 : 0.12 * frameStep
        hudAlpha += min(fadeStep, max(-fadeStep, targetAlpha - hudAlpha))
        let hudIsFading = abs(hudAlpha - targetAlpha) > 0.001
        let semanticIsAnimating = !reducedMotion
            && ["observe", "act", "verify", "wait", "recover"].contains(presentation.phase)
            && (presentation.status == "working" || presentation.status == "needs-attention" || presentation.status == "failed")
        // An expanded information card is static by itself. Only transient effects,
        // positioning, decaying Combo, and fades need the 60 Hz path.
        let needsHighFrequency = !reducedMotion
            && (hasEffects || positioning || comboIsDecaying || presentation.returning || hudIsFading)
        if hasEffects || positioning || comboIsAnimating || semanticIsAnimating || presentation.returning || previousAlpha != hudAlpha {
            invalidateVisuals(now: now)
        }
        // Visible Idle/orb/always-expanded HUDs still poll connection state, but do not
        // wake four times per second or redraw an identical frame.
        let dormant = !hasEffects
            && !positioning
            && !comboIsAnimating
            && !reducedFeedbackActive
            && !semanticIsAnimating
            && !presentation.returning
            && !hudIsFading
        scheduleTick(highFrequency: needsHighFrequency, dormant: dormant)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if usesCompositorRenderer { return }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)

        context.setBlendMode(.screen)
        for beam in scanBeams {
            let progress = 1 - beam.life / beam.maxLife
            let head = beam.origin.x + beam.length * progress
            let alpha = sin(progress * .pi) * 0.7
            context.setAlpha(alpha)
            context.setStrokeColor(beam.color.cgColor)
            context.setLineWidth(1.5)
            let trail = beam.length < 0 ? head + 120 : head - 120
            context.move(to: CGPoint(x: trail, y: beam.origin.y))
            context.addLine(to: CGPoint(x: head, y: beam.origin.y))
            context.strokePath()
            context.move(to: CGPoint(x: head, y: beam.origin.y - 16))
            context.addLine(to: CGPoint(x: head, y: beam.origin.y + 16))
            context.strokePath()
        }
        for wave in shockwaves {
            let progress = wave.life / wave.maxLife
            context.setAlpha(progress * 0.8)
            context.setStrokeColor(wave.color.cgColor)
            context.setLineWidth(wave.width * progress)
            context.strokeEllipse(in: CGRect(
                x: wave.center.x - wave.radius,
                y: wave.center.y - wave.radius,
                width: wave.radius * 2,
                height: wave.radius * 2
            ))
        }
        for particle in particles {
            context.setAlpha(min(1, particle.life / min(24, particle.maxLife)))
            context.setFillColor(particle.color.cgColor)
            let rect = CGRect(x: particle.position.x - particle.radius, y: particle.position.y - particle.radius, width: particle.radius * 2, height: particle.radius * 2)
            if particle.square { context.fill(rect) } else { context.fillEllipse(in: rect) }
        }
        context.setAlpha(1)
        context.setBlendMode(.normal)

        if flashAlpha > 0 {
            context.setFillColor(NSColor.white.withAlphaComponent(flashAlpha).cgColor)
            context.fillEllipse(in: feedbackBounds())
        }
        if dangerAlpha > 0 {
            let inset = feedbackBounds().insetBy(dx: 5, dy: 5)
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(dangerAlpha).cgColor)
            context.setLineWidth(6)
            context.strokeEllipse(in: inset)
        }
        if hudAlpha > 0.001 { drawHUD() }
    }

    private func drawHUD() {
        let now = Date()
        let presentation = presentationSnapshot(now: now)
        let baseSize = hudBaseSize()
        let scale = effectiveHudScale(for: baseSize)
        let size = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        let baseOrigin = hudOrigin(size: size)
        let offset = reducedMotion ? CGPoint.zero : CGPoint(
            x: sin(shakePhase * 2.31) * shake,
            y: cos(shakePhase * 1.73) * shake * 0.55
        )
        let screenOrigin = CGPoint(x: baseOrigin.x + offset.x, y: baseOrigin.y + offset.y)
        let phase = presentation.phase.uppercased()
        let phaseColor: NSColor = phase == "IDLE" ? NSColor(calibratedWhite: 0.7, alpha: 1) : state.completion == "cancelled" ? .systemOrange : state.completion == "unverified" ? .systemYellow : phase == "RECOVER" ? .systemRed : phase == "VERIFY" || (phase == "COMPLETE" && state.completion == "verified") ? .systemGreen : phase == "WAIT" ? .systemYellow : phase == "ACT" ? .systemPurple : .systemCyan
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(hudAlpha)
        context.translateBy(x: screenOrigin.x, y: screenOrigin.y)
        context.scaleBy(x: scale, y: scale)
        let origin = CGPoint.zero

        if positioning {
            let guideRect = CGRect(x: -5, y: -5, width: baseSize.width + 10, height: baseSize.height + 10)
            let guide = NSBezierPath(roundedRect: guideRect, xRadius: 13, yRadius: 13)
            let dash: [CGFloat] = [4, 3]
            guide.setLineDash(dash, count: dash.count, phase: 0)
            phaseColor.withAlphaComponent(0.7).setStroke()
            guide.lineWidth = 1.2
            guide.stroke()
            let handle = NSBezierPath(roundedRect: CGRect(x: baseSize.width / 2 - 13, y: baseSize.height - 5, width: 26, height: 3), xRadius: 1.5, yRadius: 1.5)
            phaseColor.withAlphaComponent(0.86).setFill()
            handle.fill()
        }

        if phase == "OBSERVE" {
            if state.currentActivity == "Understanding request" {
                drawUnderstandingSignal(around: origin, color: phaseColor)
            } else {
                drawObserveSignal(around: origin, color: phaseColor)
            }
        }
        if phase == "ACT" { drawActSignal(around: origin, color: phaseColor) }
        if phase == "VERIFY" { drawVerifySignal(around: origin, color: phaseColor) }
        if phase == "WAIT" { drawWaitSignal(around: origin, color: phaseColor) }
        if phase == "RECOVER" { drawRecoverSignal(around: origin, color: phaseColor) }
        if reducedMotion, now < (reducedFeedbackUntil ?? .distantPast) {
            drawReducedMotionFeedback(kind: reducedFeedbackKind, around: origin)
        }

        let haloRect = CGRect(x: origin.x + 1, y: origin.y + 1, width: 80, height: 80)
        let halo = NSBezierPath(ovalIn: haloRect)
        phaseColor.withAlphaComponent(0.075).setFill()
        halo.fill()

        let coreRect = CGRect(x: origin.x + 7, y: origin.y + 7, width: 68, height: 68)
        let core = NSBezierPath(ovalIn: coreRect)
        NSColor(calibratedWhite: 0.025, alpha: 0.91).setFill()
        core.fill()
        NSColor.white.withAlphaComponent(0.15).setStroke()
        core.lineWidth = 1
        core.stroke()

        let innerCore = NSBezierPath(ovalIn: CGRect(x: origin.x + 18, y: origin.y + 18, width: 46, height: 46))
        phaseColor.withAlphaComponent(0.075).setFill()
        innerCore.fill()
        phaseColor.withAlphaComponent(0.24).setStroke()
        innerCore.lineWidth = 1
        innerCore.stroke()

        let ticks = NSBezierPath(ovalIn: CGRect(x: origin.x + 3, y: origin.y + 3, width: 76, height: 76))
        ticks.setLineDash([1, 5], count: 2, phase: 0)
        phaseColor.withAlphaComponent(0.32).setStroke()
        ticks.lineWidth = 1
        ticks.stroke()

        let momentum = presentation.momentum
        let ranges: [(Int, Int)] = [(0, 0), (1, 99), (100, 249), (250, 449), (450, 699), (700, 899), (900, 998), (999, 999)]
        let rank = energyRank(energyLevel(momentum).name)
        let stageRange = ranges[rank]
        let progress = stageRange.1 > stageRange.0
            ? CGFloat(momentum - stageRange.0) / CGFloat(stageRange.1 - stageRange.0)
            : momentum > 0 ? 1 : 0
        let energy = energyLevel(momentum)
        let energyPulse = reducedMotion ? CGFloat(1) : 0.88 + 0.12 * sin(shakePhase * energy.rhythm)
        let tierMarks = energy.name == "charging" ? 4 : energy.name == "driving" ? 6 : energy.name == "high-energy" ? 8 : energy.name == "overload" ? 10 : energy.name == "critical" || energy.name == "verified-peak" ? 12 : 0
        if tierMarks > 0 {
            let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
            let markers = NSBezierPath()
            for index in 0..<tierMarks {
                let angle = CGFloat(index) / CGFloat(tierMarks) * .pi * 2 - .pi / 2
                let maximumEnergy = energy.name == "overload" || energy.name == "critical" || energy.name == "verified-peak"
                let innerRadius: CGFloat = maximumEnergy ? 36.5 : 37.5
                let outerRadius: CGFloat = maximumEnergy ? 41 : 40
                markers.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
                markers.line(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            }
            markers.lineWidth = energy.name == "verified-peak" ? 2 : energy.name == "critical" || energy.name == "overload" ? 1.8 : energy.name == "high-energy" ? 1.35 : 1
            markers.lineCapStyle = .round
            phaseColor.withAlphaComponent((energy.name == "verified-peak" || energy.name == "critical" ? 0.92 : energy.name == "overload" ? 0.82 : energy.name == "high-energy" ? 0.68 : 0.48) * energyPulse).setStroke()
            markers.stroke()
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 31, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = energy.lineWidth
        arc.lineCapStyle = .round
        phaseColor.withAlphaComponent(energyPulse).setStroke()
        arc.stroke()

        if ["high-energy", "overload", "critical", "verified-peak"].contains(energy.name) {
            let reserve = NSBezierPath()
            reserve.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 36.5, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
            reserve.lineWidth = ["overload", "critical", "verified-peak"].contains(energy.name) ? 1.8 : 1.1
            reserve.lineCapStyle = .round
            phaseColor.withAlphaComponent((["overload", "critical", "verified-peak"].contains(energy.name) ? 0.72 : 0.42) * energyPulse).setStroke()
            reserve.stroke()
        }

        if ["overload", "critical", "verified-peak"].contains(energy.name) {
            let chargedCore = NSBezierPath(ovalIn: CGRect(x: origin.x + 14, y: origin.y + 14, width: 54, height: 54))
            phaseColor.withAlphaComponent(0.08 + 0.06 * energyPulse).setFill()
            chargedCore.fill()
        }

        let value = "\(momentum)"
        drawText(value, at: CGPoint(x: origin.x + (value.count > 2 ? 21 : value.count > 1 ? 27 : 34), y: origin.y + 34), font: .systemFont(ofSize: 21, weight: .bold), color: .white)
        let energyLabel = localizedEnergyLevel(energy.name)
        drawText(energyLabel, at: CGPoint(x: origin.x + energyLabelOffset(energyLabel), y: origin.y + 24), font: .monospacedSystemFont(ofSize: 5.5, weight: .bold), color: phaseColor.withAlphaComponent(energy.name == "idle" ? 0.52 : 0.78), tracking: preferences.isChinese ? 0.3 : 0.65)
        if streamConnected != true {
            let connectionDot = NSBezierPath(ovalIn: CGRect(x: origin.x + 72, y: origin.y + 64, width: 6, height: 6))
            NSColor.systemOrange.setFill()
            connectionDot.fill()
        }
        if phase == "COMPLETE" {
            if state.completion == "verified" {
                drawCompleteSignal(around: origin)
            } else if state.completion == "unverified" {
                drawUnverifiedSignal(around: origin, color: phaseColor)
            } else if state.completion == "cancelled" {
                drawCancelledSignal(around: origin, color: phaseColor)
            } else if state.completion == "no-change" {
                drawNoChangeSignal(around: origin, color: phaseColor)
            }
        }
        let combo = comboSnapshot()
        if showsCombo {
            drawCombo(combo, at: origin, color: combo.active ? phaseColor : combo.lost ? .systemRed : NSColor.white.withAlphaComponent(0.34))
        }
        context.restoreGState()
    }

    private func drawReducedMotionFeedback(kind: String, around origin: CGPoint) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let style: (color: NSColor, symbol: String, dash: [CGFloat])
        switch kind {
        case "act": style = (.systemPurple, "▶", [15, 5])
        case "verify": style = (.systemGreen, "◆", [7, 4])
        case "verified": style = (.systemGreen, "✓", [])
        case "confirmed": style = (.systemGreen, "◆", [5, 5])
        case "record": style = (.systemYellow, "★", [])
        case "wait": style = (.systemYellow, "Ⅱ", [4, 7])
        case "recover": style = (.systemRed, "×", [8, 5])
        case "caution": style = (.systemYellow, "!", [7, 5])
        case "cancelled": style = (.systemOrange, "×", [10, 7])
        case "no-change": style = (.systemCyan, "–", [3, 6])
        case "switch": style = (.systemCyan, "↔", [12, 4])
        default: style = (.systemCyan, "◎", [2, 4])
        }

        let confirmation = NSBezierPath(ovalIn: CGRect(x: center.x - 42, y: center.y - 42, width: 84, height: 84))
        if !style.dash.isEmpty { confirmation.setLineDash(style.dash, count: style.dash.count, phase: 0) }
        confirmation.lineWidth = 2.8
        style.color.withAlphaComponent(0.92).setStroke()
        confirmation.stroke()

        let badgeRect = CGRect(x: origin.x + 61, y: origin.y + 59, width: 20, height: 20)
        let badge = NSBezierPath(ovalIn: badgeRect)
        NSColor(calibratedWhite: 0.025, alpha: 0.96).setFill()
        badge.fill()
        style.color.withAlphaComponent(0.95).setStroke()
        badge.lineWidth = 1.4
        badge.stroke()
        let x = style.symbol == "Ⅱ" ? origin.x + 66.1 : style.symbol == "↔" ? origin.x + 64.3 : origin.x + 66
        drawText(style.symbol, at: CGPoint(x: x, y: origin.y + 64), font: .systemFont(ofSize: 9.5, weight: .bold), color: .white)
    }

    private func drawWaitSignal(around origin: CGPoint, color: NSColor) {
        let settled = Date().timeIntervalSince(semanticPhaseEnteredAt) >= 12
        let cycleLength: CGFloat = settled ? 138 : 72
        let cycle = reducedMotion ? CGFloat(0) : shakePhase.truncatingRemainder(dividingBy: cycleLength)
        let firstBeat = max(0, 1 - abs(cycle - 8) / (settled ? 9 : 6))
        let secondBeat = max(0, 1 - abs(cycle - (settled ? 34 : 22)) / (settled ? 8 : 5)) * (settled ? 0.42 : 0.72)
        let beat = min(1, firstBeat + secondBeat)
        let pulse = reducedMotion ? CGFloat(0.82) : (settled ? 0.42 + beat * 0.34 : 0.48 + beat * 0.52)
        let reach = reducedMotion ? CGFloat(5) : (settled ? 2 + beat * 3.5 : 3 + beat * 7)
        color.withAlphaComponent(pulse).setStroke()
        let gates = NSBezierPath()
        gates.move(to: CGPoint(x: origin.x - reach + 11, y: origin.y + 16))
        gates.line(to: CGPoint(x: origin.x + 7 - reach, y: origin.y + 16))
        gates.line(to: CGPoint(x: origin.x + 7 - reach, y: origin.y + 66))
        gates.line(to: CGPoint(x: origin.x - reach + 11, y: origin.y + 66))
        gates.move(to: CGPoint(x: origin.x + 71 + reach, y: origin.y + 16))
        gates.line(to: CGPoint(x: origin.x + 75 + reach, y: origin.y + 16))
        gates.line(to: CGPoint(x: origin.x + 75 + reach, y: origin.y + 66))
        gates.line(to: CGPoint(x: origin.x + 71 + reach, y: origin.y + 66))
        gates.lineWidth = 2
        gates.lineCapStyle = .round
        gates.lineJoinStyle = .round
        gates.stroke()

        color.withAlphaComponent(1 - pulse * 0.45).setFill()
        for y in [CGFloat(5), CGFloat(71)] {
            let marker = NSBezierPath()
            marker.move(to: CGPoint(x: origin.x + 41, y: origin.y + y))
            marker.line(to: CGPoint(x: origin.x + 44, y: origin.y + y + 3))
            marker.line(to: CGPoint(x: origin.x + 41, y: origin.y + y + 6))
            marker.line(to: CGPoint(x: origin.x + 38, y: origin.y + y + 3))
            marker.close()
            marker.fill()
        }
    }

    private func drawObserveSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let heading = reducedMotion ? CGFloat(35) : shakePhase * (arcadeMode ? 0.34 : 0.19)
        let trailCount = arcadeMode ? 5 : 3
        for index in 0..<trailCount {
            let trail = CGFloat(index) * (arcadeMode ? 10 : 14)
            let sweep = NSBezierPath()
            let radius = 38.5 - (arcadeMode ? CGFloat(index % 2) * 3 : 0)
            sweep.appendArc(withCenter: center, radius: radius, startAngle: heading - trail - (arcadeMode ? 18 : 13), endAngle: heading - trail)
            sweep.lineWidth = arcadeMode ? 2.5 : 2.2
            sweep.lineCapStyle = .round
            color.withAlphaComponent(max(0.16, 0.82 - CGFloat(index) * (arcadeMode ? 0.14 : 0.23))).setStroke()
            sweep.stroke()
        }
    }

    private func drawUnderstandingSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let progress = reducedMotion ? CGFloat(0.7) : shakePhase.truncatingRemainder(dividingBy: 58) / 58
        let half = 42 - progress * 8
        color.withAlphaComponent(0.44 + progress * 0.42).setStroke()
        for angle in stride(from: CGFloat(0), to: 360, by: 90) {
            let radians = angle * .pi / 180
            let tangent = radians + .pi / 2
            let point = CGPoint(x: center.x + cos(radians) * half, y: center.y + sin(radians) * half)
            let marker = NSBezierPath()
            marker.move(to: CGPoint(x: point.x + cos(tangent) * 5, y: point.y + sin(tangent) * 5))
            marker.line(to: CGPoint(x: point.x - cos(tangent) * 5, y: point.y - sin(tangent) * 5))
            marker.lineWidth = 2.2
            marker.lineCapStyle = .square
            marker.stroke()
        }

        let focusRadius = 18 + (1 - progress) * 5
        let focus = NSBezierPath(ovalIn: CGRect(x: center.x - focusRadius, y: center.y - focusRadius, width: focusRadius * 2, height: focusRadius * 2))
        focus.lineWidth = 1
        color.withAlphaComponent(0.32 + progress * 0.28).setStroke()
        focus.stroke()
    }

    private func drawActSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let cycle: CGFloat = arcadeMode ? 30 : 50
        let progress = reducedMotion ? CGFloat(0.48) : shakePhase.truncatingRemainder(dividingBy: cycle) / cycle
        let chevronCount = arcadeMode ? 5 : 3
        for index in 0..<chevronCount {
            let spacing = CGFloat(index) * (arcadeMode ? 7 : 9)
            let x = center.x - 24 + progress * (arcadeMode ? 17 : 13) - spacing
            let alpha = max(0.18, (0.58 + progress * 0.36) - CGFloat(index) * (arcadeMode ? 0.12 : 0.18))
            color.withAlphaComponent(alpha).setStroke()
            let chevron = NSBezierPath()
            chevron.move(to: CGPoint(x: x - 7, y: center.y - 7))
            chevron.line(to: CGPoint(x: x, y: center.y))
            chevron.line(to: CGPoint(x: x - 7, y: center.y + 7))
            chevron.lineWidth = arcadeMode ? 2.4 : 2.1
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()
        }

        let nose = center.x + (arcadeMode ? 43 : 36)
        let tail = center.x + 9
        for offset in [-3.5, 3.5] as [CGFloat] {
            let rail = NSBezierPath()
            rail.move(to: CGPoint(x: tail - progress * 4, y: center.y + offset))
            rail.line(to: CGPoint(x: nose - 8, y: center.y + offset))
            rail.lineWidth = arcadeMode ? 1.6 : 1.25
            rail.lineCapStyle = .square
            color.withAlphaComponent(0.34 + progress * 0.24).setStroke()
            rail.stroke()
        }
        let spear = NSBezierPath()
        spear.move(to: CGPoint(x: nose - 10, y: center.y - 8))
        spear.line(to: CGPoint(x: nose, y: center.y))
        spear.line(to: CGPoint(x: nose - 10, y: center.y + 8))
        color.withAlphaComponent(0.72 + progress * 0.2).setStroke()
        spear.lineWidth = arcadeMode ? 2.2 : 1.8
        spear.lineCapStyle = .round
        spear.lineJoinStyle = .round
        spear.stroke()
    }

    private func drawVerifySignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let cycle: CGFloat = arcadeMode ? 44 : 64
        let progress = reducedMotion ? CGFloat(0.32) : shakePhase.truncatingRemainder(dividingBy: cycle) / cycle
        let half = 40 - progress * 11
        let arm: CGFloat = 10
        color.withAlphaComponent(0.82 - progress * 0.28).setStroke()
        for (xDirection, yDirection) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let x = center.x + CGFloat(xDirection) * half
            let y = center.y + CGFloat(yDirection) * half
            let bracket = NSBezierPath()
            bracket.move(to: CGPoint(x: x - CGFloat(xDirection) * arm, y: y))
            bracket.line(to: CGPoint(x: x, y: y))
            bracket.line(to: CGPoint(x: x, y: y - CGFloat(yDirection) * arm))
            bracket.lineWidth = 2
            bracket.lineCapStyle = .square
            bracket.lineJoinStyle = .miter
            bracket.stroke()
        }

        color.withAlphaComponent(0.34 + (1 - progress) * 0.2).setStroke()
        let crosshair = NSBezierPath()
        crosshair.move(to: CGPoint(x: center.x - 15, y: center.y))
        crosshair.line(to: CGPoint(x: center.x - 7, y: center.y))
        crosshair.move(to: CGPoint(x: center.x + 7, y: center.y))
        crosshair.line(to: CGPoint(x: center.x + 15, y: center.y))
        crosshair.move(to: CGPoint(x: center.x, y: center.y - 15))
        crosshair.line(to: CGPoint(x: center.x, y: center.y - 7))
        crosshair.move(to: CGPoint(x: center.x, y: center.y + 7))
        crosshair.line(to: CGPoint(x: center.x, y: center.y + 15))
        crosshair.lineWidth = 1
        crosshair.stroke()

        let coreSize = 5 + (1 - progress) * 4
        color.withAlphaComponent(0.56).setFill()
        let verdict = NSBezierPath()
        verdict.move(to: CGPoint(x: center.x, y: center.y - coreSize / 2))
        verdict.line(to: CGPoint(x: center.x + coreSize / 2, y: center.y))
        verdict.line(to: CGPoint(x: center.x, y: center.y + coreSize / 2))
        verdict.line(to: CGPoint(x: center.x - coreSize / 2, y: center.y))
        verdict.close()
        verdict.fill()

        if arcadeMode {
            color.withAlphaComponent(0.38 + (1 - progress) * 0.28).setStroke()
            let confirmation = NSBezierPath()
            confirmation.appendArc(withCenter: center, radius: 40, startAngle: shakePhase * 0.22, endAngle: shakePhase * 0.22 + 72)
            confirmation.appendArc(withCenter: center, radius: 40, startAngle: shakePhase * 0.22 + 120, endAngle: shakePhase * 0.22 + 192)
            confirmation.appendArc(withCenter: center, radius: 40, startAngle: shakePhase * 0.22 + 240, endAngle: shakePhase * 0.22 + 312)
            confirmation.lineWidth = 1.5
            confirmation.lineCapStyle = .round
            confirmation.stroke()
        }
    }

    private func drawRecoverSignal(around origin: CGPoint, color: NSColor) {
        let settled = Date().timeIntervalSince(semanticPhaseEnteredAt) >= 10
        let oscillation = reducedMotion ? 0 : sin(shakePhase * (settled ? 0.025 : 0.075))
        let rotation = oscillation * (settled ? 2.5 : 7)
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        color.withAlphaComponent((settled ? 0.48 : 0.72) + oscillation * (settled ? 0.08 : 0.16)).setStroke()
        for (index, angles) in [(14.0, 62.0), (88.0, 139.0), (166.0, 224.0), (252.0, 333.0)].enumerated() {
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let segment = NSBezierPath()
            segment.appendArc(
                withCenter: center,
                radius: 41 + direction * oscillation * (settled ? 0.6 : 1.5),
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

        color.withAlphaComponent(0.72).setStroke()
        for index in 0..<3 {
            let x = origin.x + 25 + CGFloat(index) * 6 - oscillation * 0.5
            let y = origin.y + 24 + CGFloat(index) * 8
            let stitch = NSBezierPath()
            stitch.move(to: CGPoint(x: x - 4, y: y + 2))
            stitch.line(to: CGPoint(x: x + 4, y: y - 2))
            stitch.lineWidth = 1.2
            stitch.lineCapStyle = .square
            stitch.stroke()
        }
    }

    private func drawCompleteSignal(around origin: CGPoint) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let rotation = reducedMotion ? 0 : shakePhase * (arcadeMode ? 0.28 : 0.055)
        if arcadeMode {
            let colors: [NSColor] = [.systemGreen, .systemPurple, .systemCyan]
            for (index, color) in colors.enumerated() {
                let start = CGFloat(index) * 120 + rotation
                let ribbon = NSBezierPath()
                ribbon.appendArc(withCenter: center, radius: 41, startAngle: start + 4, endAngle: start + 112)
                ribbon.lineWidth = 2.3
                ribbon.lineCapStyle = .round
                color.withAlphaComponent(0.94).setStroke()
                ribbon.stroke()
            }
        } else {
            let ribbon = NSBezierPath()
            ribbon.appendArc(withCenter: center, radius: 41, startAngle: rotation + 8, endAngle: rotation + 350)
            ribbon.lineWidth = 2
            ribbon.lineCapStyle = .round
            NSColor.systemGreen.withAlphaComponent(0.78).setStroke()
            ribbon.stroke()
        }

        let check = NSBezierPath()
        check.move(to: CGPoint(x: origin.x + 64, y: origin.y + 18))
        check.line(to: CGPoint(x: origin.x + 69, y: origin.y + 13))
        check.line(to: CGPoint(x: origin.x + 78, y: origin.y + 24))
        check.lineWidth = 2.6
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        NSColor(calibratedRed: 0.78, green: 1, blue: 0.9, alpha: 1).setStroke()
        check.stroke()
    }

    private func drawUnverifiedSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let ring = NSBezierPath(ovalIn: CGRect(x: center.x - 40, y: center.y - 40, width: 80, height: 80))
        ring.setLineDash([7, 5], count: 2, phase: reducedMotion ? 0 : shakePhase * (arcadeMode ? 0.24 : 0.08))
        ring.lineWidth = 2
        color.withAlphaComponent(0.72).setStroke()
        ring.stroke()

        if arcadeMode {
            let inner = NSBezierPath(ovalIn: CGRect(x: center.x - 35, y: center.y - 35, width: 70, height: 70))
            inner.setLineDash([2, 8], count: 2, phase: reducedMotion ? 0 : -shakePhase * 0.18)
            inner.lineWidth = 1
            color.withAlphaComponent(0.36).setStroke()
            inner.stroke()
        }

        let badge = NSBezierPath(ovalIn: CGRect(x: origin.x + 65, y: origin.y + 3, width: 17, height: 17))
        NSColor(calibratedWhite: 0.04, alpha: 0.94).setFill()
        badge.fill()
        color.setStroke()
        badge.lineWidth = 1
        badge.stroke()
        drawText("!", at: CGPoint(x: origin.x + 71, y: origin.y + 7), font: .monospacedSystemFont(ofSize: 10, weight: .bold), color: .white)
    }

    private func drawCancelledSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        color.withAlphaComponent(0.76).setStroke()
        for angles in [(18.0, 91.0), (132.0, 211.0), (257.0, 326.0)] {
            let segment = NSBezierPath()
            segment.appendArc(withCenter: center, radius: 40, startAngle: CGFloat(angles.0), endAngle: CGFloat(angles.1))
            segment.lineWidth = 2
            segment.lineCapStyle = .square
            segment.stroke()
        }

        let badgeRect = CGRect(x: origin.x + 65, y: origin.y + 3, width: 17, height: 17)
        let badge = NSBezierPath(ovalIn: badgeRect)
        NSColor(calibratedWhite: 0.04, alpha: 0.94).setFill()
        badge.fill()
        color.setStroke()
        badge.lineWidth = 1
        badge.stroke()
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: badgeRect.minX + 5, y: badgeRect.minY + 5))
        cross.line(to: CGPoint(x: badgeRect.maxX - 5, y: badgeRect.maxY - 5))
        cross.move(to: CGPoint(x: badgeRect.minX + 5, y: badgeRect.maxY - 5))
        cross.line(to: CGPoint(x: badgeRect.maxX - 5, y: badgeRect.minY + 5))
        cross.lineWidth = 1.7
        cross.lineCapStyle = .round
        NSColor.white.setStroke()
        cross.stroke()
    }

    private func drawNoChangeSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let settle = reducedMotion ? CGFloat(0) : 1.5 * sin(shakePhase * 0.045)
        color.withAlphaComponent(0.48).setStroke()
        let left = NSBezierPath()
        left.appendArc(withCenter: center, radius: 40 - settle, startAngle: 112, endAngle: 248)
        left.lineWidth = 1.5
        left.lineCapStyle = .round
        left.stroke()
        let right = NSBezierPath()
        right.appendArc(withCenter: center, radius: 40 - settle, startAngle: -68, endAngle: 68)
        right.lineWidth = 1.5
        right.lineCapStyle = .round
        right.stroke()

        color.withAlphaComponent(0.74).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
        color.withAlphaComponent(0.82).setStroke()
        let quietMark = NSBezierPath()
        quietMark.move(to: CGPoint(x: origin.x + 68, y: origin.y + 12))
        quietMark.line(to: CGPoint(x: origin.x + 76, y: origin.y + 12))
        quietMark.lineWidth = 1.8
        quietMark.lineCapStyle = .round
        quietMark.stroke()
    }

    private func energyLevel(_ momentum: Int) -> (name: String, lineWidth: CGFloat, rhythm: CGFloat) {
        if momentum <= 0 { return ("idle", 2.0, 0.02) }
        if momentum < 100 { return ("awakening", 2.2, 0.032) }
        if momentum < 250 { return ("charging", 2.6, 0.045) }
        if momentum < 450 { return ("driving", 3.1, 0.064) }
        if momentum < 700 { return ("high-energy", 3.65, 0.088) }
        if momentum < 900 { return ("overload", 4.2, 0.12) }
        if momentum < 999 { return ("critical", 4.7, 0.16) }
        return ("verified-peak", 5.2, 0.2)
    }

    private func energyRank(_ level: String) -> Int {
        switch level {
        case "awakening": return 1
        case "charging": return 2
        case "driving": return 3
        case "high-energy": return 4
        case "overload": return 5
        case "critical": return 6
        case "verified-peak": return 7
        default: return 0
        }
    }

    private func localizedEnergyLevel(_ level: String) -> String {
        switch level {
        case "awakening": return preferences.text("WAKE", "唤醒")
        case "charging": return preferences.text("CHARGE", "聚能")
        case "driving": return preferences.text("DRIVE", "推进")
        case "high-energy": return preferences.text("HIGH", "高能")
        case "overload": return preferences.text("OVERLOAD", "超载")
        case "critical": return preferences.text("CRITICAL", "临界")
        case "verified-peak": return preferences.text("PEAK", "峰值")
        default: return preferences.text("POWER", "能量")
        }
    }

    private func energyLabelOffset(_ label: String) -> CGFloat {
        if preferences.isChinese { return 33 }
        switch label.count {
        case 0...4: return 30
        case 5...6: return 26
        default: return 20
        }
    }

    private func comboSnapshot(now: Date = Date()) -> (count: Int, progress: CGFloat, active: Bool, lost: Bool, stage: String) {
        let count = state.combo ?? 0
        guard count > 0, let expires = comboExpiresAt, now < expires else {
            let disconnectedAt = comboBrokenAt ?? comboExpiresAt
            let lost = disconnectedAt.map { now < $0.addingTimeInterval(3.2) } ?? false
            return (0, 0, false, lost, lost ? "lost" : "idle")
        }
        guard let hold = comboHoldUntil, now > hold else {
            let stage = state.comboStatus == "reward" || state.comboStatus == "complete" ? comboRewardStage() : comboRelinkActive(now: now) ? "relinked" : comboCountStage(count)
            return (count, 1, true, false, stage)
        }
        let duration = expires.timeIntervalSince(hold)
        let remaining = expires.timeIntervalSince(now)
        let progress = CGFloat(max(0, min(1, remaining / max(0.001, duration))))
        let stage = comboRelinkActive(now: now) ? "relinked" : progress <= 0.25 ? "critical" : comboCountStage(count)
        return (count, progress, true, false, stage)
    }

    private func comboRelinkActive(now: Date) -> Bool {
        guard let relinkedAt = comboRelinkedAt else { return false }
        return now >= relinkedAt && now < relinkedAt.addingTimeInterval(1.6)
    }

    private func comboCountStage(_ count: Int) -> String {
        if count < 5 { return "ignition" }
        if count < 10 { return "linked" }
        if count < 20 { return "accelerated" }
        if count < 40 { return "heated" }
        return "extreme"
    }

    private func comboRewardStage() -> String {
        if state.verificationReward == "record" { return "record" }
        if state.verificationReward == "confirmation" { return "confirmed" }
        return "reward"
    }

    private func localizedComboStage(_ stage: String) -> String {
        switch stage {
        case "ignition": return preferences.text("IGNITE", "点火")
        case "linked": return preferences.text("LINK", "续连")
        case "accelerated": return preferences.text("ACCEL", "加速")
        case "heated": return preferences.text("HEAT", "高热")
        case "extreme": return preferences.text("EXTREME", "极限")
        case "critical": return preferences.text("BREAK", "将断")
        case "reward": return preferences.text("BOOST", "奖励")
        case "confirmed": return preferences.text("CHECK", "确认")
        case "record": return preferences.text("RECORD", "纪录")
        case "relinked": return preferences.text("RELINK", "重连")
        case "lost": return preferences.text("LOST", "断连")
        default: return preferences.text("READY", "就绪")
        }
    }

    private func drawCombo(_ combo: (count: Int, progress: CGFloat, active: Bool, lost: Bool, stage: String), at origin: CGPoint, color: NSColor) {
        guard combo.active || combo.lost else { return }
        let stageColor: NSColor = combo.stage == "critical" || combo.stage == "lost" ? .systemRed : combo.stage == "reward" || combo.stage == "confirmed" ? .systemGreen : combo.stage == "record" ? .systemYellow : combo.stage == "relinked" ? .systemCyan : color
        let criticalSpeed: CGFloat = arcadeMode ? 0.36 : 0.22
        let rhythm = reducedMotion ? CGFloat(1) : combo.stage == "critical" ? 0.52 + 0.48 * abs(sin(shakePhase * criticalSpeed)) : combo.stage == "reward" || combo.stage == "record" ? 0.72 + 0.28 * abs(sin(shakePhase * 0.12)) : combo.stage == "relinked" ? 0.7 + 0.3 * abs(sin(shakePhase * 0.16)) : 1
        let capsuleRect = CGRect(x: origin.x + 5, y: origin.y - 23, width: 72, height: 21)
        let capsule = NSBezierPath(roundedRect: capsuleRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.025, alpha: 0.92).setFill()
        capsule.fill()
        stageColor.withAlphaComponent(0.3 + 0.28 * rhythm).setStroke()
        capsule.lineWidth = combo.stage == "reward" || combo.stage == "record" ? 1.5 : 1
        capsule.stroke()

        let trackRect = CGRect(x: origin.x + 11, y: origin.y - 17, width: 60, height: 5)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.white.withAlphaComponent(0.18).setFill()
        track.fill()
        if combo.lost {
            stageColor.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: CGRect(x: trackRect.minX, y: trackRect.minY + 1, width: 24, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
            NSBezierPath(roundedRect: CGRect(x: trackRect.maxX - 24, y: trackRect.minY - 1, width: 24, height: 3), xRadius: 1.5, yRadius: 1.5).fill()
        }
        if combo.progress > 0 {
            let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: trackRect.width * combo.progress, height: trackRect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
            stageColor.withAlphaComponent(rhythm).setFill()
            fill.fill()
        }
        let countCopy = combo.lost ? "—" : "\(combo.count)×"
        let stageCopy = localizedComboStage(combo.stage)
        drawText(countCopy, at: CGPoint(x: origin.x + 11, y: origin.y - 10), font: .monospacedSystemFont(ofSize: 6.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.96), tracking: 0.2)
        drawText(stageCopy, at: CGPoint(x: origin.x + (preferences.isChinese ? 54 : stageCopy.count > 5 ? 42 : 47), y: origin.y - 10), font: .monospacedSystemFont(ofSize: 5.8, weight: .bold), color: stageColor.withAlphaComponent(0.96), tracking: preferences.isChinese ? 0.1 : 0.35)

        if combo.stage == "critical" {
            stageColor.withAlphaComponent(rhythm).setFill()
            NSBezierPath(roundedRect: CGRect(x: capsuleRect.minX - 2, y: capsuleRect.midY - 5, width: 2, height: 10), xRadius: 1, yRadius: 1).fill()
            NSBezierPath(roundedRect: CGRect(x: capsuleRect.maxX, y: capsuleRect.midY - 5, width: 2, height: 10), xRadius: 1, yRadius: 1).fill()
        } else if combo.stage == "relinked" || combo.stage == "record" {
            stageColor.withAlphaComponent(0.82 * rhythm).setFill()
            NSBezierPath(ovalIn: CGRect(x: trackRect.midX - 2.5, y: trackRect.midY - 2.5, width: 5, height: 5)).fill()
        }
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
    private let token: String
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = ""
    private var stopped = false
    private var reconnectAttempt = 0
    private var connectedAt: Date?
    private var reconnectWorkItem: DispatchWorkItem?
    private var connected: Bool?
    var onEvent: (@MainActor (PowerEvent) -> Void)?
    var onConnectionChange: (@MainActor (Bool) -> Void)?

    init(url: URL, token: String) {
        self.url = url
        self.token = token
    }

    func start() {
        stopped = false
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        buffer = ""
        connectedAt = nil
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 86_400
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        task = session?.dataTask(with: request)
        task?.resume()
    }

    func stop() {
        stopped = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
    }

    func postTypingCharge(inputCombo: Int, sessionId: String) {
        guard inputCombo > 0, !sessionId.isEmpty else { return }
        let endpoint = url.deletingLastPathComponent().appendingPathComponent("typing-charge")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "inputCombo": min(200, inputCombo),
            "sessionId": sessionId
        ])
        URLSession.shared.dataTask(with: request).resume()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if connectedAt == nil { connectedAt = Date() }
        updateConnection(true)
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
        guard !stopped, session === self.session else { return }
        updateConnection(false)
        if let connectedAt, Date().timeIntervalSince(connectedAt) >= 10 {
            reconnectAttempt = 0
        }
        connectedAt = nil
        self.task = nil
        self.session = nil
        session.finishTasksAndInvalidate()
        let delay = min(30.0, pow(2.0, Double(reconnectAttempt)))
        reconnectAttempt = min(5, reconnectAttempt + 1)
        let workItem = DispatchWorkItem { [weak self] in self?.start() }
        reconnectWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func updateConnection(_ next: Bool) {
        guard connected != next else { return }
        connected = next
        Task { @MainActor [weak self] in self?.onConnectionChange?(next) }
    }
}

@MainActor
private final class TypingComboMonitor {
    private weak var view: PowerModeView?
    private let preferences: PowerModePreferences
    private var fallbackMonitor: Any?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var count = 0
    private var lastHit = Date.distantPast
    private var cachedCaretElement: AXUIElement?
    private var requestedManualAccessibility = false
    private let comboWindow: TimeInterval = 2.0
    private let codexBundleIdentifier = "com.openai.codex"

    init(view: PowerModeView?, preferences: PowerModePreferences, startMonitoring: Bool = true) {
        self.view = view
        self.preferences = preferences
        if startMonitoring { preferencesChanged(promptForPermission: true) }
    }

    static func accessibilityDiagnostic(preferences: PowerModePreferences) -> [String: Any] {
        let monitor = TypingComboMonitor(view: nil, preferences: preferences, startMonitoring: false)
        return monitor.accessibilityDiagnosticSnapshot()
    }

    var permissionGranted: Bool { AXIsProcessTrusted() }

    func preferencesChanged(promptForPermission: Bool = true) {
        stop()
        guard preferences.settings.typingCombo == true else { return }
        if promptForPermission, !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        guard AXIsProcessTrusted() else { return }
        let eventMask = CGEventMask(1) << CGEventType.keyDown.rawValue
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, type, event, userInfo in
                guard type == .keyDown, let userInfo else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<TypingComboMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
                let flags = event.flags
                MainActor.assumeIsolated { owner.handle(keyCode: keyCode, flags: flags) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )
        if let eventTap {
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
            eventTapSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        } else {
            fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
                var flags: CGEventFlags = []
                if event.modifierFlags.contains(.command) { flags.insert(.maskCommand) }
                if event.modifierFlags.contains(.control) { flags.insert(.maskControl) }
                if event.modifierFlags.contains(.function) { flags.insert(.maskSecondaryFn) }
                Task { @MainActor in self?.handle(keyCode: Int(event.keyCode), flags: flags) }
            }
        }
    }

    func stop() {
        if let fallbackMonitor { NSEvent.removeMonitor(fallbackMonitor) }
        fallbackMonitor = nil
        if let eventTapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), eventTapSource, .commonModes) }
        eventTapSource = nil
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        count = 0
        lastHit = .distantPast
    }

    private func handle(keyCode: Int, flags: CGEventFlags) {
        guard preferences.settings.typingCombo == true, isCodexFrontmost() else { return }
        if [36, 76].contains(keyCode) { return }
        guard flags.intersection([.maskCommand, .maskControl, .maskSecondaryFn]).isEmpty,
              ![48, 51, 53, 117, 123, 124, 125, 126].contains(keyCode) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
            self?.recordTypingHit()
        }
    }

    private func recordTypingHit() {
        guard preferences.settings.typingCombo == true, isCodexFrontmost() else { return }
        let now = Date()
        count = now.timeIntervalSince(lastHit) <= comboWindow ? min(200, count + 1) : 1
        lastHit = now
        view?.handleTypingHit(
            count: count,
            lastAt: now,
            expiresAt: now.addingTimeInterval(comboWindow),
            caretScreenPoint: caretScreenPoint()
        )
    }

    private func isCodexFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == codexBundleIdentifier else { return false }
        return true
    }

    private func accessibilityDiagnosticSnapshot() -> [String: Any] {
        var result: [String: Any] = [
            "accessibilityTrusted": AXIsProcessTrusted(),
            "frontmostBundle": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        ]
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == codexBundleIdentifier else {
            result["caretElementFound"] = false
            return result
        }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        prepareCodexAccessibilityTree(application)
        RunLoop.current.run(until: Date().addingTimeInterval(0.16))
        if let element = caretElement(in: application) {
            result["caretElementFound"] = true
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String { result["role"] = role }
            let markerBounds = textMarkerCaretBounds(startingAt: element)
            let selectedBounds = selectedTextCaretBounds(for: element)
            result["markerBoundsUsable"] = markerBounds != nil
            result["selectedBoundsUsable"] = selectedBounds != nil
            if let bounds = markerBounds ?? selectedBounds {
                let point = screenPoint(for: bounds)
                result["method"] = markerBounds != nil ? "text-marker" : "selected-range"
                result["boundsX"] = bounds.origin.x
                result["boundsY"] = bounds.origin.y
                result["boundsWidth"] = bounds.width
                result["boundsHeight"] = bounds.height
                result["screenX"] = point.x
                result["screenY"] = point.y
            }
        } else {
            result["caretElementFound"] = false
        }
        var windowValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
           let focusedWindow = windowValue as! AXUIElement? {
            var queue: [(AXUIElement, Int)] = [(focusedWindow, 0)]
            var candidates: [[String: Any]] = []
            var nodes: [[String: Any]] = []
            var seen = Set<CFHashCode>()
            var visited = 0
            while !queue.isEmpty, visited < 900, candidates.count < 24 {
                let (candidate, depth) = queue.removeFirst()
                guard seen.insert(CFHash(candidate)).inserted else { continue }
                visited += 1
                let score = caretCapabilityScore(candidate)
                var node: [String: Any] = ["depth": depth, "score": score]
                var nodeRole: CFTypeRef?
                if AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &nodeRole) == .success,
                   let role = nodeRole as? String { node["role"] = role }
                var attributeNames: CFArray?
                if AXUIElementCopyAttributeNames(candidate, &attributeNames) == .success,
                   let names = attributeNames as? [String] {
                    node["relations"] = names.filter {
                        $0.localizedCaseInsensitiveContains("child") ||
                        $0.localizedCaseInsensitiveContains("content") ||
                        $0.localizedCaseInsensitiveContains("row")
                    }
                }
                nodes.append(node)
                if score > 0 {
                    var item: [String: Any] = [
                        "depth": depth,
                        "score": score,
                        "focused": elementIsFocused(candidate),
                        "marker": textMarkerCaretBounds(startingAt: candidate) != nil,
                        "range": selectedTextCaretBounds(for: candidate) != nil
                    ]
                    var candidateRole: CFTypeRef?
                    if AXUIElementCopyAttributeValue(candidate, kAXRoleAttribute as CFString, &candidateRole) == .success,
                       let role = candidateRole as? String { item["role"] = role }
                    candidates.append(item)
                }
                queue.append(contentsOf: accessibilityChildren(of: candidate).map { ($0, depth + 1) })
            }
            result["windowNodesVisited"] = visited
            result["nodes"] = nodes
            result["candidates"] = candidates
        }
        return result
    }

    private func caretScreenPoint() -> CGPoint? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier == codexBundleIdentifier else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        prepareCodexAccessibilityTree(application)
        if let cachedCaretElement,
           let cachedBounds = caretBounds(startingAt: cachedCaretElement) {
            return screenPoint(for: cachedBounds)
        }
        // Codex can replace the Chromium editor node after send, task switch,
        // or composer resize. A stale AX node must never suppress a fresh walk.
        cachedCaretElement = nil
        guard let focused = caretElement(in: application) else { return nil }
        guard let bounds = caretBounds(startingAt: focused) else {
            cachedCaretElement = nil
            return nil
        }
        return screenPoint(for: bounds)
    }

    private func prepareCodexAccessibilityTree(_ application: AXUIElement) {
        guard !requestedManualAccessibility else { return }
        requestedManualAccessibility = true
        _ = AXUIElementSetAttributeValue(application, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        _ = AXUIElementSetAttributeValue(application, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }

    private func caretBounds(startingAt element: AXUIElement) -> CGRect? {
        textMarkerCaretBounds(startingAt: element) ?? selectedTextCaretBounds(for: element)
    }

    private func caretElement(in application: AXUIElement) -> AXUIElement? {
        if let cachedCaretElement,
           elementSupportsPreciseCaretBounds(cachedCaretElement),
           caretBounds(startingAt: cachedCaretElement) != nil {
            return cachedCaretElement
        }
        var focusedValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
           let focused = focusedValue as! AXUIElement? {
            let resolved = descendantCaretElement(startingAt: focused) ?? focused
            cachedCaretElement = resolved
            return resolved
        }
        if let cachedCaretElement, elementIsFocused(cachedCaretElement) { return cachedCaretElement }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &windowValue) == .success,
              let focusedWindow = windowValue as! AXUIElement? else { return nil }
        var queue: [(AXUIElement, Int)] = [(focusedWindow, 0)]
        var supportedCandidate: (element: AXUIElement, score: Int)?
        var seen = Set<CFHashCode>()
        var visited = 0
        while !queue.isEmpty, visited < 1_400 {
            let (element, depth) = queue.removeFirst()
            guard seen.insert(CFHash(element)).inserted else { continue }
            visited += 1
            let score = caretCapabilityScore(element) + depth + (elementIsFocused(element) ? 40 : 0)
            if score >= 100,
               caretBounds(startingAt: element) != nil,
               score > (supportedCandidate?.score ?? -1) {
                supportedCandidate = (element, score)
            }
            queue.append(contentsOf: accessibilityChildren(of: element).map { ($0, depth + 1) })
        }
        cachedCaretElement = supportedCandidate?.element
        return supportedCandidate?.element
    }

    private func descendantCaretElement(startingAt root: AXUIElement) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var best: (element: AXUIElement, score: Int)?
        var seen = Set<CFHashCode>()
        var visited = 0
        while !queue.isEmpty, visited < 1_400 {
            let (element, depth) = queue.removeFirst()
            guard seen.insert(CFHash(element)).inserted else { continue }
            visited += 1
            let score = caretCapabilityScore(element) + depth
            if score >= 100,
               caretBounds(startingAt: element) != nil,
               score > (best?.score ?? -1) {
                best = (element, score)
            }
            queue.append(contentsOf: accessibilityChildren(of: element).map { ($0, depth + 1) })
        }
        return best?.element
    }

    private func accessibilityChildren(of element: AXUIElement) -> [AXUIElement] {
        let relations = [
            kAXChildrenAttribute as String,
            "AXChildrenInNavigationOrder",
            "AXRows",
            "AXContents",
            "AXVisibleChildren"
        ]
        var result: [AXUIElement] = []
        for relation in relations {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, relation as CFString, &value) == .success,
                  let children = value as? [AXUIElement] else { continue }
            result.append(contentsOf: children)
        }
        return result
    }

    private func caretCapabilityScore(_ element: AXUIElement) -> Int {
        var attributes: CFArray?
        var parameterized: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributes) == .success,
              AXUIElementCopyParameterizedAttributeNames(element, &parameterized) == .success,
              let attributeNames = attributes as? [String],
              let parameterNames = parameterized as? [String] else { return 0 }
        var score = 0
        if attributeNames.contains("AXSelectedTextMarkerRange"),
           parameterNames.contains("AXBoundsForTextMarkerRange") { score = 220 }
        if attributeNames.contains(kAXSelectedTextRangeAttribute as String),
           parameterNames.contains(kAXBoundsForRangeParameterizedAttribute as String) { score = max(score, 180) }
        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
           let role = roleValue as? String,
           [kAXTextAreaRole as String, kAXTextFieldRole as String].contains(role) { score += 40 }
        if elementIsFocused(element) { score += 20 }
        return score
    }

    private func elementIsFocused(_ element: AXUIElement) -> Bool {
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focusedValue) == .success else { return false }
        return focusedValue as? Bool == true
    }

    private func elementSupportsCaretBounds(_ element: AXUIElement) -> Bool {
        var attributes: CFArray?
        guard AXUIElementCopyAttributeNames(element, &attributes) == .success,
              let names = attributes as? [String] else { return false }
        return names.contains("AXSelectedTextMarkerRange") || names.contains(kAXSelectedTextRangeAttribute as String)
    }

    private func elementSupportsPreciseCaretBounds(_ element: AXUIElement) -> Bool {
        caretCapabilityScore(element) >= 100
    }

    private func textMarkerCaretBounds(startingAt element: AXUIElement) -> CGRect? {
        var candidate: AXUIElement? = element
        for _ in 0..<6 {
            guard let current = candidate else { break }
            var markerRange: CFTypeRef?
            if AXUIElementCopyAttributeValue(current, "AXSelectedTextMarkerRange" as CFString, &markerRange) == .success,
               let markerRange {
                var endMarker: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(
                    current,
                    "AXEndTextMarkerForTextMarkerRange" as CFString,
                    markerRange,
                    &endMarker
                ) == .success,
                let endMarker {
                    let collapsedMarkers = [endMarker, endMarker] as CFArray
                    var collapsedRange: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(
                        current,
                        "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                        collapsedMarkers,
                        &collapsedRange
                    ) == .success,
                    let collapsedRange,
                    let bounds = textMarkerBounds(current, range: collapsedRange),
                    isUsableCaretBounds(bounds) {
                        return bounds
                    }
                    var previousMarker: CFTypeRef?
                    if AXUIElementCopyParameterizedAttributeValue(
                        current,
                        "AXPreviousTextMarkerForTextMarker" as CFString,
                        endMarker,
                        &previousMarker
                    ) == .success,
                    let previousMarker {
                        let precedingMarkers = [previousMarker, endMarker] as CFArray
                        var precedingRange: CFTypeRef?
                        if AXUIElementCopyParameterizedAttributeValue(
                            current,
                            "AXTextMarkerRangeForUnorderedTextMarkers" as CFString,
                            precedingMarkers,
                            &precedingRange
                        ) == .success,
                        let precedingRange,
                        let bounds = textMarkerBounds(current, range: precedingRange),
                        isUsableCaretBounds(bounds) {
                            return bounds
                        }
                    }
                }
                // Some native controls already return a narrow caret rectangle
                // and do not expose Chromium's text-marker endpoint helpers.
                if let bounds = textMarkerBounds(current, range: markerRange),
                   isUsableCaretBounds(bounds), bounds.width <= 12 {
                    return bounds
                }
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(current, kAXParentAttribute as CFString, &parentValue) == .success,
                  let parent = parentValue as! AXUIElement? else { break }
            candidate = parent
        }
        return nil
    }

    private func textMarkerBounds(_ element: AXUIElement, range: CFTypeRef) -> CGRect? {
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            "AXBoundsForTextMarkerRange" as CFString,
            range,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds) else { return nil }
        return bounds
    }

    private func selectedTextCaretBounds(for focused: AXUIElement) -> CGRect? {
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else { return nil }
        var selectedRange = CFRange()
        var boundsRangeValue = rangeValue
        if CFGetTypeID(rangeValue) == AXValueGetTypeID(),
           AXValueGetValue(rangeValue as! AXValue, .cfRange, &selectedRange),
           selectedRange.location > 0 {
            var precedingCharacter = CFRange(location: selectedRange.location - 1, length: 1)
            if let value = AXValueCreate(.cfRange, &precedingCharacter) {
                boundsRangeValue = value
            }
        }
        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            boundsRangeValue,
            &boundsValue
        ) == .success,
        let boundsValue,
        CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        var bounds = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &bounds), isUsableCaretBounds(bounds) else { return nil }
        return bounds
    }

    private func screenPoint(for quartzRect: CGRect) -> CGPoint {
        let mainTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CGPoint(x: quartzRect.maxX + 8, y: mainTop - quartzRect.maxY + 5)
    }
}

@MainActor
private final class CodexWindowTracker {
    private weak var panel: NSPanel?
    private let preferences: PowerModePreferences
    private var timer: Timer?
    private var lastFrame = CGRect.zero
    private var lastCodexFrame: CGRect?
    private let bundleIdentifier = "com.openai.codex"

    init(panel: NSPanel, preferences: PowerModePreferences) {
        self.panel = panel
        self.preferences = preferences
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    func preferencesChanged() { refresh() }

    func screenParametersChanged() {
        lastFrame = .zero
        refresh()
    }

    private func refresh() {
        guard let panel else { return }
        let inactiveBehavior = preferences.settings.inactiveBehavior
        let codexIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        let windowTarget = trackedWindowTarget(codexIsFrontmost: codexIsFrontmost, inactiveBehavior: inactiveBehavior)
        panel.level = inactiveBehavior == "hide" ? .floating : .statusBar
        guard windowTarget != .hidden else {
            panel.orderOut(nil)
            return
        }
        let currentCodexFrame = codexWindowFrame()
        if codexIsFrontmost, let currentCodexFrame { lastCodexFrame = currentCodexFrame }
        let targetFrame: CGRect?
        if windowTarget == .codex {
            targetFrame = currentCodexFrame ?? lastCodexFrame
        } else {
            targetFrame = frontmostWindowFrame()
        }
        guard let frame = targetFrame, frame.width > 400, frame.height > 300 else {
            panel.orderOut(nil)
            return
        }
        if !frame.equalTo(lastFrame) {
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
            lastFrame = frame
        }
        if inactiveBehavior != "hide" && !codexIsFrontmost {
            NSApp.unhideWithoutActivation()
            panel.orderFrontRegardless()
        } else if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    private func codexWindowFrame() -> CGRect? {
        guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else { return nil }
        return windowFrame(for: application)
    }

    private func frontmostWindowFrame() -> CGRect? {
        guard let application = NSWorkspace.shared.frontmostApplication else { return NSScreen.main?.frame }
        return windowFrame(for: application) ?? NSScreen.main?.frame
    }

    private func windowFrame(for application: NSRunningApplication) -> CGRect? {
        guard let rawWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let candidates = rawWindows.compactMap { info -> CGRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == Int(application.processIdentifier) else { return nil }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0 else { return nil }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let quartzFrame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
            return cocoaFrame(fromQuartz: quartzFrame)
        }
        // CGWindowListCopyWindowInfo preserves front-to-back window order.
        // Keep that order so multiple Codex windows follow the foremost one,
        // instead of jumping to whichever background window is largest.
        return candidates.first { $0.width > 400 && $0.height > 300 }
    }

    private func cocoaFrame(fromQuartz frame: CGRect) -> CGRect {
        let mainTop = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.maxY
            ?? NSScreen.main?.frame.maxY
            ?? 0
        return CGRect(x: frame.origin.x, y: mainTop - frame.origin.y - frame.height, width: frame.width, height: frame.height)
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSPanel?
    private var stream: EventStream?
    private var tracker: CodexWindowTracker?
    private var typingMonitor: TypingComboMonitor?
    private var preferences: PowerModePreferences?
    private var statusItem: NSStatusItem?
    private var positioning = false
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let environment = ProcessInfo.processInfo.environment
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { NSApp.terminate(nil); return }
        let preferences = PowerModePreferences(environment: environment)
        self.preferences = preferences

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
        panel.canHide = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        let powerView = PowerModeView(frame: CGRect(origin: .zero, size: CGSize(width: 900, height: 700)), preferences: preferences)
        powerView.onPositioningFinished = { [weak self] in self?.setPositioning(false) }
        panel.contentView = powerView
        window = panel
        tracker = CodexWindowTracker(panel: panel, preferences: preferences)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        preferences.onChange = { [weak self, weak powerView] in
            powerView?.preferencesChanged()
            self?.tracker?.preferencesChanged()
            self?.typingMonitor?.preferencesChanged()
            self?.rebuildMenu()
        }
        installStatusItem()
        if environment["CODEX_POWER_MODE_POSITIONING_PREVIEW"] == "1" {
            setPositioning(true)
        }

        let endpoint = environment["CODEX_POWER_MODE_URL"] ?? "http://127.0.0.1:4737/api/stream"
        guard let url = URL(string: endpoint), let view = panel.contentView as? PowerModeView else { return }
        let client = EventStream(url: url, token: environment["CODEX_POWER_MODE_TOKEN"] ?? "")
        client.onEvent = { [weak view] event in view?.handle(event) }
        client.onConnectionChange = { [weak view] connected in view?.setStreamConnected(connected) }
        client.start()
        stream = client
        powerView.onTypingCharge = { [weak client] count, sessionId in
            client?.postTypingCharge(inputCombo: count, sessionId: sessionId)
        }
        typingMonitor = TypingComboMonitor(view: powerView, preferences: preferences)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        removeMouseMonitors()
        typingMonitor?.stop()
        stream?.stop()
    }

    @objc private func screenParametersChanged() {
        tracker?.screenParametersChanged()
        window?.contentView?.needsDisplay = true
        if positioning { updateMouseCapture() }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "bolt.circle.fill", accessibilityDescription: "Codex Power Mode")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildMenu()
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu() }

    private func rebuildMenu() {
        guard let menu = statusItem?.menu, let preferences else { return }
        menu.removeAllItems()
        let title = NSMenuItem(title: "Codex Power Mode", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        if let view = window?.contentView as? PowerModeView {
            let history = NSMenuItem(title: view.historySummary(), action: nil, keyEquivalent: "")
            history.isEnabled = false
            menu.addItem(history)
            let diagnostics = NSMenuItem(title: preferences.text("Status & connection", "状态与连接"), action: nil, keyEquivalent: "")
            let diagnosticsMenu = NSMenu()
            for diagnosticTitle in [
                view.displaySummary(),
                view.rawStateSummary(),
                view.connectionSummary(),
                view.lastEventSummary(),
                view.activitySourceSummary(),
                view.sessionSourceSummary()
            ] {
                let item = NSMenuItem(title: diagnosticTitle, action: nil, keyEquivalent: "")
                item.isEnabled = false
                diagnosticsMenu.addItem(item)
            }
            let summary = view.sessionSummary()
            let session = NSMenuItem(title: summary.title, action: nil, keyEquivalent: "")
            session.toolTip = summary.fullId
            session.isEnabled = false
            diagnosticsMenu.addItem(session)
            diagnostics.submenu = diagnosticsMenu
            menu.addItem(diagnostics)
            let position = NSMenuItem(title: view.positionSummary(), action: nil, keyEquivalent: "")
            position.isEnabled = false
            menu.addItem(position)
        }
        menu.addItem(.separator())

        let enabled = NSMenuItem(title: preferences.text("Enabled", "启用"), action: #selector(toggleEnabled), keyEquivalent: "")
        enabled.target = self
        enabled.state = preferences.settings.enabled ? .on : .off
        menu.addItem(enabled)

        menu.addItem(submenu(
            title: preferences.text("Effect", "效果"),
            choices: [("focus", "Focus"), ("arcade", "Arcade")],
            selected: preferences.settings.preset,
            action: #selector(selectPreset)
        ))
        menu.addItem(submenu(
            title: preferences.text("Effect intensity", "效果强度"),
            choices: [
                ("low", preferences.text("Low", "低")),
                ("normal", preferences.text("Normal", "标准")),
                ("high", preferences.text("High", "高"))
            ],
            selected: preferences.settings.effectIntensity ?? "normal",
            action: #selector(selectEffectIntensity)
        ))
        let combo = NSMenuItem(title: preferences.text("Show Combo", "显示 Combo"), action: #selector(toggleCombo), keyEquivalent: "")
        combo.target = self
        combo.state = (preferences.settings.showCombo ?? true) ? .on : .off
        menu.addItem(combo)
        let typing = NSMenuItem(title: preferences.text("Typing Combo", "输入连击"), action: #selector(toggleTypingCombo), keyEquivalent: "")
        typing.target = self
        typing.state = (preferences.settings.typingCombo ?? false) ? .on : .off
        typing.toolTip = typingMonitor?.permissionGranted == true
            ? preferences.text("Counts input rhythm only; never stores text", "只统计输入节奏，不保存文字")
            : preferences.text("Requires macOS Accessibility permission", "需要 macOS 辅助功能权限")
        menu.addItem(typing)
        let cursorEffects = submenu(
            title: preferences.text("Cursor effects", "光标特效"),
            choices: [
                ("off", preferences.text("Off", "关闭")),
                ("spark", preferences.text("Sparks", "火花")),
                ("neon", preferences.text("Neon burst", "霓虹爆发"))
            ],
            selected: preferences.settings.cursorEffect ?? "spark",
            action: #selector(selectCursorEffect)
        )
        cursorEffects.isEnabled = preferences.settings.typingCombo ?? false
        menu.addItem(cursorEffects)
        menu.addItem(submenu(
            title: preferences.text("Activity source", "动态来源"),
            choices: [
                ("focused", preferences.text("Keep current conversation", "保持当前对话")),
                ("global", preferences.text("Follow latest conversation", "跟随最新对话")),
                ("mix", preferences.text("Mix all conversations", "混合所有对话"))
            ],
            selected: preferences.settings.activitySource ?? "focused",
            action: #selector(selectActivitySource)
        ))
        menu.addItem(submenu(
            title: preferences.text("When idle", "静止状态"),
            choices: [
                ("hide", preferences.text("Auto hide", "自动隐藏")),
                ("orb", preferences.text("Keep orb", "保留小球"))
            ],
            selected: preferences.settings.idleBehavior,
            action: #selector(selectIdleBehavior)
        ))
        let autoHideDelay = submenu(
            title: preferences.text("Auto-hide delay", "自动隐藏延迟"),
            choices: [
                ("0", preferences.text("Immediately", "立即")),
                ("2", preferences.text("Brief · 2 seconds", "短暂 · 2 秒")),
                ("6", preferences.text("Relaxed · 6 seconds", "从容 · 6 秒"))
            ],
            selected: String(preferences.settings.autoHideDelay),
            action: #selector(selectAutoHideDelay),
            numericSelected: preferences.settings.autoHideDelay
        )
        autoHideDelay.isEnabled = preferences.settings.idleBehavior == "hide"
        menu.addItem(autoHideDelay)
        menu.addItem(submenu(
            title: preferences.text("Language", "语言"),
            choices: [("auto", preferences.text("System", "跟随系统")), ("zh-CN", "中文"), ("en", "English")],
            selected: preferences.settings.language,
            action: #selector(selectLanguage)
        ))
        menu.addItem(submenu(
            title: preferences.text("Size", "大小"),
            choices: [("0.9", "90%"), ("1.0", "100%"), ("1.15", "115%"), ("1.3", "130%"), ("1.5", "150%")],
            selected: String(preferences.settings.scale),
            action: #selector(selectScale),
            numericSelected: preferences.settings.scale
        ))
        menu.addItem(submenu(
            title: preferences.text("Position preset", "位置预设"),
            choices: [
                ("smart", preferences.text("Smart · avoid side panels", "智能 · 避让侧栏")),
                ("top-right", preferences.text("Top right", "右上")),
                ("top-left", preferences.text("Top left", "左上")),
                ("bottom-right", preferences.text("Bottom right", "右下")),
                ("bottom-left", preferences.text("Bottom left", "左下")),
                ("center", preferences.text("Center", "中央"))
            ],
            selected: preferences.settings.positionX == nil ? preferences.settings.edge : "custom",
            action: #selector(selectEdge)
        ))

        menu.addItem(.separator())
        let adjust = NSMenuItem(title: positioning ? preferences.text("Finish positioning", "完成位置调整") : preferences.text("Adjust position…", "调整位置…"), action: #selector(togglePositioning), keyEquivalent: "p")
        adjust.keyEquivalentModifierMask = [.command, .option]
        adjust.target = self
        adjust.state = positioning ? .on : .off
        menu.addItem(adjust)
        let reset = NSMenuItem(title: preferences.text("Reset position", "重置位置"), action: #selector(resetPosition), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)

        let reduced = NSMenuItem(title: preferences.text("Reduce motion", "减少动态效果"), action: #selector(toggleReducedMotion), keyEquivalent: "")
        reduced.target = self
        reduced.state = preferences.settings.reducedMotion ? .on : .off
        menu.addItem(reduced)
        menu.addItem(submenu(
            title: preferences.text("When Codex is inactive", "Codex 非前台时"),
            choices: [
                ("hide", preferences.text("Hide outside Codex", "离开 Codex 时隐藏")),
                ("stay", preferences.text("Stay over the Codex window", "保持在 Codex 窗口位置")),
                ("follow", preferences.text("Follow the active app", "跟随当前应用"))
            ],
            selected: preferences.settings.inactiveBehavior,
            action: #selector(selectInactiveBehavior)
        ))

        menu.addItem(.separator())
        let quit = NSMenuItem(title: preferences.text("Quit Power Mode", "退出 Power Mode"), action: #selector(quitOverlay), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func submenu(title: String, choices: [(String, String)], selected: String, action: Selector, numericSelected: Double? = nil) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        for (value, label) in choices {
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.target = self
            item.representedObject = value
            if let numericSelected, let number = Double(value) {
                item.state = abs(number - numericSelected) < 0.001 ? .on : .off
            } else {
                item.state = value == selected ? .on : .off
            }
            menu.addItem(item)
        }
        parent.submenu = menu
        return parent
    }

    @objc private func toggleEnabled() { preferences?.toggleEnabled() }
    @objc private func selectPreset(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setPreset(value) } }
    @objc private func selectEffectIntensity(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setEffectIntensity(value) } }
    @objc private func toggleCombo() { preferences?.toggleCombo() }
    @objc private func toggleTypingCombo() { preferences?.toggleTypingCombo() }
    @objc private func selectCursorEffect(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setCursorEffect(value) } }
    @objc private func selectActivitySource(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setActivitySource(value) } }
    @objc private func selectIdleBehavior(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setIdleBehavior(value) } }
    @objc private func selectAutoHideDelay(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let delay = Double(value) { preferences?.setAutoHideDelay(delay) }
    }
    @objc private func selectLanguage(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setLanguage(value) } }
    @objc private func selectScale(_ sender: NSMenuItem) { if let value = sender.representedObject as? String, let scale = Double(value) { preferences?.setScale(scale) } }
    @objc private func selectEdge(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setEdge(value) } }
    @objc private func toggleReducedMotion() { preferences?.toggleReducedMotion() }
    @objc private func selectInactiveBehavior(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String { preferences?.setInactiveBehavior(value) }
    }
    @objc private func resetPosition() {
        if positioning { setPositioning(false) }
        preferences?.resetPosition()
    }
    @objc private func togglePositioning() { setPositioning(!positioning) }
    @objc private func quitOverlay() { NSApp.terminate(nil) }

    private func setPositioning(_ active: Bool) {
        positioning = active
        guard let panel = window, let view = panel.contentView as? PowerModeView else { return }
        if active {
            view.beginPositioning()
            installMouseMonitors()
            updateMouseCapture()
        } else {
            view.cancelPositioning()
            removeMouseMonitors()
            panel.ignoresMouseEvents = true
        }
        rebuildMenu()
    }

    private func installMouseMonitors() {
        removeMouseMonitors()
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] _ in
            Task { @MainActor in self?.updateMouseCapture() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp]) { [weak self] event in
            self?.updateMouseCapture()
            return event
        }
    }

    private func removeMouseMonitors() {
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        globalMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func updateMouseCapture() {
        guard positioning, let panel = window, let view = panel.contentView as? PowerModeView else { return }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !view.hudContains(windowPoint: windowPoint)
    }
}

@main
private struct PowerModeOverlayApp {
    @MainActor
    static func main() {
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_ACCESSIBILITY_SELF_TEST"] == "1" {
            let preferences = PowerModePreferences(environment: ProcessInfo.processInfo.environment)
            let diagnostic = TypingComboMonitor.accessibilityDiagnostic(preferences: preferences)
            if let data = try? JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys]),
               let output = String(data: data, encoding: .utf8) {
                fputs(output + "\n", stdout)
            }
            return
        }
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_PLACEMENT_SELF_TEST"] == "1" {
            runPlacementGeometrySelfTest()
            return
        }
        if let directory = ProcessInfo.processInfo.environment["CODEX_POWER_MODE_RENDER_QA_DIR"] {
            runEnergyRenderQA(directory: directory)
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

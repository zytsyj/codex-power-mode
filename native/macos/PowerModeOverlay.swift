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

private let reconnectStableWindow: TimeInterval = 10

private func reconnectDelay(for attempt: Int) -> TimeInterval {
    min(30, pow(2, Double(max(0, attempt))))
}

private func nextReconnectAttempt(after attempt: Int) -> Int {
    min(5, max(0, attempt) + 1)
}

private func reconnectAttemptAfterConnection(current attempt: Int, connectedDuration: TimeInterval?) -> Int {
    guard let connectedDuration, connectedDuration >= reconnectStableWindow else { return attempt }
    return 0
}

private func runReconnectPolicySelfTest() {
    precondition((0...7).map(reconnectDelay) == [1, 2, 4, 8, 16, 30, 30, 30])
    precondition((0...7).map(nextReconnectAttempt) == [1, 2, 3, 4, 5, 5, 5, 5])
    precondition(reconnectAttemptAfterConnection(current: 4, connectedDuration: nil) == 4)
    precondition(reconnectAttemptAfterConnection(current: 4, connectedDuration: 9.999) == 4)
    precondition(reconnectAttemptAfterConnection(current: 4, connectedDuration: 10) == 0)
    fputs("Event-stream reconnect policy self-test passed\n", stdout)
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
    let tiers = [90, 320, 580, 850, 999]
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
    func renderFrame(variant: (name: String, preset: String, reduced: Bool), dark: Bool, phase: String, momentum: Int, completion: String? = nil, label: String? = nil, filename: String) {
        let preferences = PowerModePreferences(environment: [
            "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
        ])
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
            label: label ?? phase.uppercased()
        )
        renderer.setVisible(true, animated: false)
        writeFrame(host: host, filename: filename)
    }
    func renderTierTransitionFrame(variant: (name: String, preset: String, reduced: Bool), dark: Bool, from previous: Int, to next: Int, filename: String) {
        let preferences = PowerModePreferences(environment: [
            "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
        ])
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
                for momentum in [90, 580, 850] {
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
                let completionLabels = [
                    "verified": "完成/已验证",
                    "unverified": "完成/待验证",
                    "cancelled": "完成/已取消",
                    "no-change": "完成/无修改"
                ]
                renderFrame(
                    variant: variant,
                    dark: dark,
                    phase: "complete",
                    momentum: 850,
                    completion: completion,
                    label: completionLabels[completion],
                    filename: "complete-\(variant.name)-\(theme)-\(completion).png"
                )
            }
            for crossing in [
                (from: 190, to: 220, label: "charge"),
                (from: 430, to: 480, label: "drive"),
                (from: 680, to: 740, label: "critical"),
                (from: 960, to: 999, label: "peak")
            ] {
                renderTierTransitionFrame(
                    variant: variant,
                    dark: dark,
                    from: crossing.from,
                    to: crossing.to,
                    filename: "transition-\(variant.name)-\(theme)-\(crossing.label).png"
                )
            }
            for cursorSample in [
                (effect: "spark", count: 12, label: "spark"),
                (effect: "neon", count: 12, label: "neon"),
                (effect: "orbit", count: 12, label: "orbit"),
                (effect: "ripple", count: 12, label: "ripple"),
                (effect: "prism", count: 12, label: "prism"),
                (effect: "wormhole", count: 12, label: "wormhole"),
                (effect: "glitch", count: 12, label: "glitch"),
                (effect: "tentacle", count: 12, label: "tentacle"),
                (effect: "meme", count: 12, label: "meme-dian"),
                (effect: "meme", count: 13, label: "meme-ji"),
                (effect: "meme", count: 14, label: "meme-xiao"),
                (effect: "meme", count: 15, label: "meme-le"),
                (effect: "meme", count: 16, label: "meme-beng"),
                (effect: "meme", count: 17, label: "meme-ying"),
                (effect: "possum", count: 18, label: "possum"),
                (effect: "freshcat", count: 19, label: "fresh-cat"),
                (effect: "knifeshield", count: 19, label: "knife-shield-dog"),
                (effect: "elegant", count: 19, label: "elegant-person"),
                (effect: "neon", count: 20, label: "neon-milestone")
            ] {
                let preferences = PowerModePreferences(environment: [
                    "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
                ])
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
            for comboSample in [(count: 4, label: "cyan"), (count: 12, label: "violet"), (count: 24, label: "pink"), (count: 48, label: "gold")] {
                let preferences = PowerModePreferences(environment: [
                    "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
                ])
                preferences.setPreset(variant.preset)
                if variant.reduced { preferences.toggleReducedMotion() }
                let host = CALayer()
                host.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
                host.backgroundColor = (dark ? NSColor(calibratedWhite: 0.055, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).cgColor
                let typing = TypingFeedbackRenderer(hostLayer: host, preferences: preferences)
                typing.layout(in: host.bounds, beside: CGRect(x: 112, y: 58, width: 60, height: 60))
                typing.update(count: comboSample.count, progress: 0.72)
                writeFrame(host: host, filename: "typing-\(variant.name)-\(theme)-\(comboSample.label).png")
            }
        }
    }
    for dark in [false, true] {
        let preferences = PowerModePreferences(environment: [
            "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
        ])
        preferences.setPreset("classic")
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 180, height: 180)
        host.backgroundColor = (dark ? NSColor(calibratedWhite: 0.055, alpha: 1) : NSColor(calibratedWhite: 0.96, alpha: 1)).cgColor
        let typing = TypingFeedbackRenderer(hostLayer: host, preferences: preferences)
        typing.layout(in: host.bounds, beside: CGRect(x: 44, y: 44, width: 92, height: 92), centered: true)
        typing.update(count: 24, progress: 0.72)
        writeFrame(host: host, filename: "classic-\(dark ? "dark" : "light")-typing-combo.png")
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
    let mixedLastCompletion: String?
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
    let mixCompletion: String?
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
    var energyGainMultiplier: Double?
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
    private let systemReduceMotionOverride: Bool?
    let assetRootURL: URL?
    var onChange: (() -> Void)?

    init(environment: [String: String]) {
        fileURL = environment["CODEX_POWER_MODE_CONFIG_PATH"].map { URL(fileURLWithPath: $0) }
        assetRootURL = (environment["CODEX_POWER_MODE_ASSET_ROOT"]
            ?? ProcessInfo.processInfo.environment["CODEX_POWER_MODE_ASSET_ROOT"])
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
        switch environment["CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE"] {
        case "0": systemReduceMotionOverride = false
        case "1": systemReduceMotionOverride = true
        default: systemReduceMotionOverride = nil
        }
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

    var reduceMotionEnabled: Bool {
        settings.reducedMotion
            || (systemReduceMotionOverride ?? NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    var isChinese: Bool {
        if settings.language == "zh-CN" { return true }
        if settings.language == "en" { return false }
        return Locale.preferredLanguages.first?.lowercased().hasPrefix("zh") == true
    }

    func text(_ english: String, _ chinese: String) -> String { isChinese ? chinese : english }

    func setPreset(_ value: String) {
        guard ["focus", "arcade", "classic"].contains(value) else { return }
        mutate {
            $0.preset = value
            if value == "classic" { $0.typingCombo = true }
        }
    }
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
    func setEnergyGainMultiplier(_ value: Double) {
        let supported = [0.3, 0.4, 0.5, 0.6, 0.72, 0.85, 1.0, 1.15, 1.3, 1.5]
        guard supported.contains(where: { abs($0 - value) < 0.001 }) else { return }
        mutate { $0.energyGainMultiplier = value }
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
        guard ["off", "spark", "neon", "orbit", "ripple", "prism", "wormhole", "glitch", "tentacle", "meme", "possum", "freshcat", "knifeshield", "elegant"].contains(value) else { return }
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

@MainActor
private func runSettingsPersistenceSelfTest(environment: [String: String]) {
    guard let path = environment["CODEX_POWER_MODE_CONFIG_PATH"], !path.isEmpty else {
        fputs("Settings persistence self-test requires CODEX_POWER_MODE_CONFIG_PATH\n", stderr)
        exit(2)
    }

    let fileURL = URL(fileURLWithPath: path)
    try? FileManager.default.removeItem(at: fileURL)
    defer { try? FileManager.default.removeItem(at: fileURL) }

    var isolatedEnvironment = environment
    isolatedEnvironment["CODEX_POWER_MODE_URL"] = "http://127.0.0.1:4737/api/stream"
    func reloaded() -> PowerModePreferences { PowerModePreferences(environment: isolatedEnvironment) }
    let preferences = PowerModePreferences(environment: isolatedEnvironment)
    precondition(preferences.settings == OverlaySettings())

    preferences.setPreset("focus")
    preferences.setPreset("arcade")
    precondition(reloaded().settings.preset == "arcade")
    preferences.setIdleBehavior("hide")
    preferences.setIdleBehavior("orb")
    precondition(reloaded().settings.idleBehavior == "orb")
    preferences.setAutoHideDelay(6)
    preferences.setLanguage("en")
    precondition(reloaded().settings.language == "en")
    preferences.setLanguage("auto")
    precondition(reloaded().settings.language == "auto")
    preferences.setLanguage("zh-CN")
    preferences.setActivitySource("focused")
    preferences.setActivitySource("global")
    preferences.setActivitySource("mix")
    preferences.setEffectIntensity("high")
    preferences.setEnergyGainMultiplier(1.15)
    preferences.setEdge("bottom-left")
    preferences.setScale(2)
    preferences.toggleEnabled()
    preferences.toggleReducedMotion()
    preferences.setInactiveBehavior("hide")
    preferences.setInactiveBehavior("stay")
    preferences.setInactiveBehavior("follow")
    preferences.toggleCombo()
    preferences.toggleTypingCombo()
    preferences.setPreset("classic")
    preferences.setCursorEffect("off")
    preferences.setCursorEffect("spark")
    preferences.setCursorEffect("neon")
    preferences.setCursorEffect("orbit")
    preferences.setCursorEffect("ripple")
    preferences.setCursorEffect("prism")
    preferences.setCursorEffect("wormhole")
    preferences.setCursorEffect("glitch")
    preferences.setCursorEffect("tentacle")
    preferences.setCursorEffect("meme")
    preferences.setCursorEffect("elegant")
    preferences.setPosition(x: 345, y: 678)

    let persisted = reloaded()
    precondition(persisted.settings.preset == "classic")
    precondition(persisted.settings.idleBehavior == "orb")
    precondition(persisted.settings.autoHideDelay == 6)
    precondition(persisted.settings.language == "zh-CN")
    precondition(persisted.settings.activitySource == "mix")
    precondition(persisted.settings.effectIntensity == "high")
    precondition(persisted.settings.energyGainMultiplier == 1.15)
    precondition(persisted.settings.edge == "bottom-left")
    precondition(persisted.settings.scale == 1.6)
    precondition(!persisted.settings.enabled)
    precondition(persisted.settings.reducedMotion)
    precondition(persisted.settings.inactiveBehavior == "follow")
    precondition(persisted.settings.showCombo == false)
    precondition(persisted.settings.typingCombo == true)
    precondition(persisted.settings.cursorEffect == "elegant")
    precondition(persisted.settings.positionX == 345)
    precondition(persisted.settings.positionY == 678)

    let snapshot = persisted.settings
    persisted.setAutoHideDelay(3)
    persisted.setActivitySource("cli")
    persisted.setEffectIntensity("extreme")
    persisted.setEnergyGainMultiplier(0.73)
    persisted.setInactiveBehavior("detach")
    persisted.setCursorEffect("fixed")
    precondition(persisted.settings == snapshot)

    persisted.resetPosition()
    let reset = reloaded()
    precondition(reset.settings.edge == "smart")
    precondition(reset.settings.positionX == nil && reset.settings.positionY == nil)
    fputs("HUD settings persistence self-test passed\n", stdout)
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

private enum VisualPriority: Int {
    case ambient = 0
    case progress = 1
    case verification = 2
    case attention = 3
    case terminal = 4
}

@MainActor
private final class EnergyEvolutionRenderer {
    private struct Palette {
        let primary: NSColor
        let secondary: NSColor
    }

    private struct ArcSpec {
        let radius: CGFloat
        let start: CGFloat
        let end: CGFloat
    }

    private struct TierBlueprint {
        let nodeRadius: CGFloat
        let nodeAngles: [CGFloat]
        let chassisArcs: [ArcSpec]
        let busArcs: [ArcSpec]
        let showsPorts: Bool
        let showsLocks: Bool
        let showsCrown: Bool
    }

    private let body: CALayer
    private let container: CALayer
    private let effects: CALayer
    private let halo: CALayer
    private let core: CALayer
    private let inner: CAGradientLayer
    private let sheen: CAGradientLayer
    private let mechanism = CALayer()
    private let chassis = CAShapeLayer()
    private let bus = CAShapeLayer()
    private let ports = CAShapeLayer()
    private let stabilizer = CAShapeLayer()
    private let crown = CAShapeLayer()
    private let nodes = (0..<6).map { _ in CALayer() }
    private let track = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let head = CALayer()
    private var lastTier = 0
    private var lastValue = 0
    private var lastProgressBand = 0
    private var lastMotionSignature = ""

    init(
        body: CALayer,
        container: CALayer,
        effects: CALayer,
        halo: CALayer,
        core: CALayer,
        inner: CAGradientLayer,
        sheen: CAGradientLayer
    ) {
        self.body = body
        self.container = container
        self.effects = effects
        self.halo = halo
        self.core = core
        self.inner = inner
        self.sheen = sheen
        mechanism.frame = body.bounds
        body.addSublayer(mechanism)
        for layer in [chassis, bus, ports, stabilizer, crown] {
            layer.frame = mechanism.bounds
            layer.fillColor = NSColor.clear.cgColor
            layer.lineCap = .round
            layer.lineJoin = .round
            mechanism.addSublayer(layer)
        }
        for node in nodes {
            node.bounds = CGRect(x: 0, y: 0, width: 5.6, height: 5.6)
            node.cornerRadius = 2.8
            node.borderWidth = 1
            node.shadowOffset = .zero
            node.opacity = 0
            mechanism.addSublayer(node)
        }
        configureGauge(track, width: 4.2)
        track.strokeColor = NSColor.white.withAlphaComponent(0.14).cgColor
        configureGauge(ring, width: 5.2)
        head.bounds = CGRect(x: 0, y: 0, width: 6.2, height: 6.2)
        head.cornerRadius = 3.1
        head.borderWidth = 0.8
        head.borderColor = NSColor.white.withAlphaComponent(0.82).cgColor
        head.shadowOffset = .zero
        head.opacity = 0
        container.addSublayer(head)
    }

    func update(momentum: Int, phase: String, phaseColor: NSColor, arcade: Bool, reducedMotion: Bool) -> (tier: Int, color: NSColor) {
        let value = max(0, min(999, momentum))
        let tier = Self.tier(for: value)
        let color = stageColor(tier: tier, phaseColor: phaseColor)
        let previousRotation = CGFloat(
            (mechanism.presentation()?.value(forKeyPath: "transform.rotation.z") as? NSNumber)?.doubleValue ?? 0
        )
        let previousNodePositions = nodes.map {
            let point = $0.presentation()?.position ?? $0.position
            let dx = point.x - 46
            let dy = point.y - 46
            return CGPoint(
                x: 46 + dx * cos(previousRotation) - dy * sin(previousRotation),
                y: 46 + dx * sin(previousRotation) + dy * cos(previousRotation)
            )
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        applyAppearance(tier: tier, color: color)
        updateGauge(
            progress: Self.progress(for: value),
            momentum: value,
            color: color,
            arcade: arcade,
            reducedMotion: reducedMotion
        )
        CATransaction.commit()
        updateMotion(tier: tier, phase: phase, arcade: arcade, reducedMotion: reducedMotion)
        if lastTier != tier, lastValue > 0, value > 0, !reducedMotion {
            animateTierChange(
                from: lastValue,
                to: value,
                previousNodePositions: previousNodePositions,
                color: color,
                arcade: arcade
            )
        }
        lastTier = tier
        lastValue = value
        return (tier, color)
    }

    func animateSessionHandoff(reducedMotion: Bool) {
        guard !reducedMotion else { return }
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 0.2, 0.2, 1]
        fade.keyTimes = [0, 0.34, 0.58, 1]
        fade.duration = 0.78
        ring.add(fade, forKey: "session-handoff-energy")
    }

    func animateSemanticDuck(duration: CFTimeInterval, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        for (index, layer) in ([mechanism, ring]).enumerated() {
            let base = layer.presentation()?.opacity ?? layer.opacity
            let duck = CAKeyframeAnimation(keyPath: "opacity")
            duck.values = [base, base, base * 0.3, base * 0.3, base * 0.72, base]
            duck.keyTimes = [0, 0.12, 0.24, 0.48, 0.72, 1]
            duck.duration = duration
            duck.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.012
            duck.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(duck, forKey: "semantic-energy-duck")
        }
    }

    func animateActClearance(duration: CFTimeInterval, reducedMotion: Bool) {
        guard !reducedMotion, mechanism.opacity > 0 else { return }
        let base = mechanism.presentation()?.opacity ?? mechanism.opacity
        let clearance = CAKeyframeAnimation(keyPath: "opacity")
        clearance.values = [base, base * 0.24, base * 0.24, base]
        clearance.keyTimes = [0, 0.16, 0.72, 1]
        clearance.duration = duration
        clearance.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        mechanism.add(clearance, forKey: "act-signal-clearance")
    }

    func setCompletionEmphasis(_ active: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mechanism.opacity = active ? 0.1 : (lastTier > 0 ? 1 : 0)
        ring.opacity = active ? 0 : 1
        track.opacity = active ? 0 : 1
        head.opacity = active ? 0 : (lastValue > 0 && Self.progress(for: lastValue) > 0.015 ? 1 : 0)
        inner.opacity = active ? 0.42 : 1
        sheen.opacity = active ? 0.03 : Float(0.06 + Double(lastTier) * 0.04)
        if active { core.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor }
        halo.shadowOpacity = active ? 0.08 : lastTier >= 4 ? 0.42 : lastTier >= 2 ? 0.3 : 0.2
        CATransaction.commit()
    }

    private static func tier(for momentum: Int) -> Int {
        if momentum <= 0 { return 0 }
        if momentum < 200 { return 1 }
        if momentum < 450 { return 2 }
        if momentum < 700 { return 3 }
        if momentum < 900 { return 4 }
        return 5
    }

    private static func progress(for momentum: Int) -> CGFloat {
        let value = max(0, min(999, momentum))
        let bounds: [(Int, Int)] = [(0, 0), (1, 199), (200, 449), (450, 699), (700, 899), (900, 999)]
        let range = bounds[tier(for: value)]
        guard range.1 > range.0 else { return value > 0 ? 1 : 0 }
        return CGFloat(value - range.0) / CGFloat(range.1 - range.0)
    }

    private func palette(_ tier: Int) -> Palette {
        let values = [
            Palette(primary: .systemGray, secondary: .white),
            Palette(primary: NSColor(calibratedRed: 0.28, green: 0.82, blue: 0.98, alpha: 1), secondary: NSColor(calibratedRed: 0.68, green: 0.94, blue: 1, alpha: 1)),
            Palette(primary: NSColor(calibratedRed: 0.30, green: 0.62, blue: 1, alpha: 1), secondary: NSColor(calibratedRed: 0.66, green: 0.82, blue: 1, alpha: 1)),
            Palette(primary: NSColor(calibratedRed: 0.64, green: 0.46, blue: 1, alpha: 1), secondary: NSColor(calibratedRed: 0.82, green: 0.72, blue: 1, alpha: 1)),
            Palette(primary: NSColor(calibratedRed: 1, green: 0.47, blue: 0.25, alpha: 1), secondary: NSColor(calibratedRed: 1, green: 0.76, blue: 0.58, alpha: 1)),
            Palette(primary: NSColor(calibratedRed: 1, green: 0.82, blue: 0.38, alpha: 1), secondary: NSColor(calibratedRed: 1, green: 0.98, blue: 0.88, alpha: 1))
        ]
        return values[max(0, min(values.count - 1, tier))]
    }

    private func stageColor(tier: Int, phaseColor: NSColor) -> NSColor {
        let accent = palette(tier).primary
        return phaseColor.blended(withFraction: tier > 0 ? 0.96 : 0.72, of: accent) ?? accent
    }

    private func configureGauge(_ layer: CAShapeLayer, width: CGFloat) {
        let path = CGMutablePath()
        path.addArc(center: CGPoint(x: 46, y: 46), radius: 36.5, startAngle: .pi * 2 / 3, endAngle: .pi * 7 / 3, clockwise: false)
        layer.frame = container.bounds
        layer.path = path
        layer.fillColor = NSColor.clear.cgColor
        layer.strokeColor = NSColor.white.cgColor
        layer.lineWidth = width
        layer.lineCap = .round
        layer.strokeStart = 0
        layer.strokeEnd = 1
        container.addSublayer(layer)
    }

    private func gaugePoint(_ progress: CGFloat) -> CGPoint {
        let angle = CGFloat.pi * 2 / 3 + max(0, min(1, progress)) * CGFloat.pi * 5 / 3
        return CGPoint(x: 46 + cos(angle) * 36.5, y: 46 + sin(angle) * 36.5)
    }

    private func point(radius: CGFloat, degrees: CGFloat) -> CGPoint {
        let angle = degrees * .pi / 180
        return CGPoint(x: 46 + cos(angle) * radius, y: 46 + sin(angle) * radius)
    }

    private func blueprint(for tier: Int) -> TierBlueprint {
        switch tier {
        case 1:
            return TierBlueprint(
                nodeRadius: 24,
                nodeAngles: [330],
                chassisArcs: [ArcSpec(radius: 24, start: 210, end: 330)],
                busArcs: [],
                showsPorts: false,
                showsLocks: false,
                showsCrown: false
            )
        case 2:
            return TierBlueprint(
                nodeRadius: 26,
                nodeAngles: [90, 210, 330],
                chassisArcs: [],
                busArcs: [90, 210, 330].map { ArcSpec(radius: 26, start: CGFloat($0 - 25), end: CGFloat($0 + 25)) },
                showsPorts: false,
                showsLocks: false,
                showsCrown: false
            )
        case 3:
            return TierBlueprint(
                nodeRadius: 26,
                nodeAngles: [30, 150, 210, 330],
                chassisArcs: [],
                busArcs: [
                    ArcSpec(radius: 26, start: 18, end: 156),
                    ArcSpec(radius: 26, start: 198, end: 336)
                ],
                showsPorts: true,
                showsLocks: false,
                showsCrown: false
            )
        case 4:
            return TierBlueprint(
                nodeRadius: 29,
                nodeAngles: [30, 90, 150, 210, 270, 330],
                chassisArcs: [],
                busArcs: [ArcSpec(radius: 29, start: 18, end: 342)],
                showsPorts: false,
                showsLocks: true,
                showsCrown: false
            )
        case 5:
            return TierBlueprint(
                nodeRadius: 29,
                nodeAngles: [30, 90, 150, 210, 270, 330],
                chassisArcs: [],
                busArcs: [ArcSpec(radius: 29, start: 0, end: 360)],
                showsPorts: false,
                showsLocks: false,
                showsCrown: true
            )
        default:
            return TierBlueprint(
                nodeRadius: 0,
                nodeAngles: [],
                chassisArcs: [],
                busArcs: [],
                showsPorts: false,
                showsLocks: false,
                showsCrown: false
            )
        }
    }

    private func nodePosition(index: Int, tier: Int) -> CGPoint {
        if tier == 3 {
            let points = [
                CGPoint(x: 64, y: 57),
                CGPoint(x: 28, y: 57),
                CGPoint(x: 64, y: 35),
                CGPoint(x: 28, y: 35)
            ]
            return points[index % points.count]
        }
        let blueprint = blueprint(for: tier)
        guard !blueprint.nodeAngles.isEmpty else { return CGPoint(x: 46, y: 46) }
        return point(
            radius: blueprint.nodeRadius,
            degrees: blueprint.nodeAngles[index % blueprint.nodeAngles.count]
        )
    }

    private func visibleNodeCount(tier: Int) -> Int {
        blueprint(for: tier).nodeAngles.count
    }

    private func path(for arcs: [ArcSpec]) -> CGPath {
        let path = CGMutablePath()
        for arc in arcs {
            path.addArc(
                center: CGPoint(x: 46, y: 46),
                radius: arc.radius,
                startAngle: arc.start * .pi / 180,
                endAngle: arc.end * .pi / 180,
                clockwise: false
            )
        }
        return path
    }

    private func driveGraphPath() -> CGPath {
        let upperLeft = nodePosition(index: 1, tier: 3)
        let upperRight = nodePosition(index: 0, tier: 3)
        let lowerRight = nodePosition(index: 2, tier: 3)
        let lowerLeft = nodePosition(index: 3, tier: 3)
        let path = CGMutablePath()
        path.move(to: upperLeft)
        path.addCurve(
            to: upperRight,
            control1: CGPoint(x: 35, y: 70),
            control2: CGPoint(x: 57, y: 70)
        )
        path.move(to: lowerLeft)
        path.addCurve(
            to: lowerRight,
            control1: CGPoint(x: 35, y: 22),
            control2: CGPoint(x: 57, y: 22)
        )
        return path
    }

    private func portPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 22, y: 39))
        path.addLine(to: CGPoint(x: 18, y: 46))
        path.addLine(to: CGPoint(x: 22, y: 53))
        path.move(to: CGPoint(x: 70, y: 39))
        path.addLine(to: CGPoint(x: 74, y: 46))
        path.addLine(to: CGPoint(x: 70, y: 53))
        return path
    }

    private func stabilizerPath() -> CGPath {
        let path = CGMutablePath()
        for angle in blueprint(for: 4).nodeAngles {
            let radians = angle * .pi / 180
            let tangent = CGPoint(x: -sin(radians), y: cos(radians))
            let anchor = point(radius: 29, degrees: angle)
            path.move(to: CGPoint(x: anchor.x - tangent.x * 4, y: anchor.y - tangent.y * 4))
            path.addLine(to: CGPoint(x: anchor.x + tangent.x * 4, y: anchor.y + tangent.y * 4))
        }
        return path
    }

    private func crownPath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: point(radius: 32, degrees: 82))
        path.addLine(to: point(radius: 36, degrees: 90))
        path.addLine(to: point(radius: 32, degrees: 98))
        return path
    }

    private func applyAppearance(tier: Int, color: NSColor) {
        let active = palette(tier)
        let blueprint = blueprint(for: tier)
        let coreBorders: [CGFloat] = [1, 1.1, 1.3, 1.45, 1.65, 1.9]
        let haloRadii: [CGFloat] = [8, 10, 13, 16, 19, 22]
        core.borderWidth = coreBorders[tier]
        core.borderColor = active.secondary.withAlphaComponent(tier >= 4 ? 0.72 : 0.42).cgColor
        inner.colors = [
            active.secondary.withAlphaComponent(0.12 + CGFloat(tier) * 0.045).cgColor,
            color.withAlphaComponent(0.07 + CGFloat(tier) * 0.03).cgColor,
            NSColor.clear.cgColor
        ]
        inner.borderColor = color.withAlphaComponent(0.18).cgColor
        inner.locations = tier >= 4 ? [0, 0.4, 1] : [0, 0.56, 1]
        sheen.colors = [
            NSColor.clear.cgColor,
            active.secondary.withAlphaComponent(tier >= 4 ? 0.38 : 0.22).cgColor,
            NSColor.white.withAlphaComponent(tier == 5 ? 0.34 : 0.14).cgColor,
            NSColor.clear.cgColor
        ]
        sheen.locations = [0.18, 0.42, 0.57, 0.82]
        sheen.opacity = Float(0.06 + Double(tier) * 0.04)
        halo.shadowRadius = haloRadii[tier]
        halo.shadowOpacity = tier >= 4 ? 0.42 : tier >= 2 ? 0.3 : 0.2
        halo.backgroundColor = color.withAlphaComponent(tier >= 4 ? 0.065 : 0.035).cgColor
        halo.shadowColor = color.cgColor

        mechanism.opacity = tier > 0 ? 1 : 0
        chassis.path = path(for: blueprint.chassisArcs)
        chassis.opacity = tier == 1 ? 0.9 : 0
        chassis.strokeColor = active.secondary.withAlphaComponent(0.92).cgColor
        chassis.lineWidth = 2.1

        bus.path = tier == 3 ? driveGraphPath() : path(for: blueprint.busArcs)
        bus.opacity = tier >= 2 ? (tier == 2 ? 0.76 : tier == 3 ? 0.82 : tier == 4 ? 0.86 : 0.94) : 0
        bus.strokeColor = (tier == 5 ? active.secondary : active.primary).withAlphaComponent(tier == 5 ? 0.98 : 0.88).cgColor
        bus.lineWidth = tier == 5 ? 2.3 : tier >= 4 ? 1.9 : 1.75
        bus.lineDashPattern = nil
        bus.shadowColor = active.primary.cgColor
        bus.shadowOpacity = tier >= 2 ? (tier == 5 ? 0.5 : 0.34) : 0
        bus.shadowRadius = tier == 5 ? 4.5 : 3

        ports.path = portPath()
        ports.opacity = blueprint.showsPorts ? 0.72 : 0
        ports.strokeColor = active.secondary.cgColor
        ports.lineWidth = 1.8
        ports.shadowColor = active.primary.cgColor
        ports.shadowOpacity = blueprint.showsPorts ? 0.34 : 0
        ports.shadowRadius = 3

        stabilizer.path = stabilizerPath()
        stabilizer.opacity = blueprint.showsLocks ? 0.78 : 0
        stabilizer.strokeColor = active.secondary.withAlphaComponent(0.78).cgColor
        stabilizer.lineWidth = 1.4
        stabilizer.shadowColor = active.primary.cgColor
        stabilizer.shadowOpacity = blueprint.showsLocks ? 0.3 : 0
        stabilizer.shadowRadius = 3

        crown.path = crownPath()
        crown.opacity = blueprint.showsCrown ? 1 : 0
        crown.fillColor = NSColor.clear.cgColor
        crown.strokeColor = active.secondary.cgColor
        crown.lineWidth = 1.7
        crown.shadowColor = active.primary.cgColor
        crown.shadowOpacity = blueprint.showsCrown ? 0.58 : 0
        crown.shadowRadius = 5

        let visibleNodes = visibleNodeCount(tier: tier)
        for (index, node) in nodes.enumerated() {
            let nodeSize: CGFloat = tier == 3 ? 4.6 : 5.6
            node.bounds = CGRect(x: 0, y: 0, width: nodeSize, height: nodeSize)
            node.cornerRadius = nodeSize / 2
            node.position = nodePosition(index: index, tier: tier)
            node.opacity = index < visibleNodes ? 1 : 0
            node.backgroundColor = (tier == 5 ? active.secondary : active.primary).cgColor
            node.borderColor = active.secondary.withAlphaComponent(0.9).cgColor
            node.shadowColor = active.primary.cgColor
            node.shadowOpacity = index < visibleNodes ? (tier >= 4 ? 0.62 : 0.5) : 0
            node.shadowRadius = tier >= 4 ? 4 : 3
        }
    }

    private func updateGauge(progress: CGFloat, momentum: Int, color: NSColor, arcade: Bool, reducedMotion: Bool) {
        ring.strokeColor = color.cgColor
        ring.strokeEnd = progress
        ring.lineWidth = momentum >= 999 ? 6 : momentum >= 700 ? 5.8 : 5.2
        ring.shadowColor = color.cgColor
        ring.shadowOpacity = momentum >= 700 ? 0.58 : 0.42
        ring.shadowRadius = momentum >= 999 ? 6 : momentum >= 700 ? 5 : 3
        track.lineWidth = max(4.2, ring.lineWidth - 0.8)
        track.strokeColor = NSColor.white.withAlphaComponent(momentum >= 700 ? 0.2 : 0.14).cgColor
        head.opacity = momentum > 0 && progress > 0.015 ? 1 : 0
        head.position = gaugePoint(progress)
        head.backgroundColor = color.cgColor
        head.shadowColor = color.cgColor
        head.shadowOpacity = progress >= 0.9 ? 1 : 0.68
        head.shadowRadius = progress >= 0.9 ? 8 : 4
        let band = progress >= 0.9 ? 2 : progress >= 0.72 ? 1 : 0
        guard band != lastProgressBand else { return }
        lastProgressBand = band
        head.removeAnimation(forKey: "energy-head-warning")
        guard band > 0, !reducedMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = band == 2 ? [1, 1.45, 0.96, 1.24, 1] : [1, 1.18, 1]
        pulse.keyTimes = band == 2 ? [0, 0.18, 0.42, 0.62, 1] : [0, 0.45, 1]
        pulse.duration = band == 2 ? (arcade ? 0.9 : 1.15) : 1.6
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        head.add(pulse, forKey: "energy-head-warning")
    }

    private func updateMotion(tier: Int, phase: String, arcade: Bool, reducedMotion: Bool) {
        let signature = "\(tier)|\(phase)|\(arcade)|\(reducedMotion)"
        guard signature != lastMotionSignature else { return }
        lastMotionSignature = signature
        for layer in [mechanism, chassis, bus, ports, stabilizer, crown] + nodes {
            for key in layer.animationKeys() ?? [] where key.hasPrefix("energy-steady-") {
                layer.removeAnimation(forKey: key)
            }
        }
    }

    private func animateTierChange(
        from previousValue: Int,
        to nextValue: Int,
        previousNodePositions: [CGPoint],
        color: NSColor,
        arcade: Bool
    ) {
        let previous = Self.tier(for: previousValue)
        let next = Self.tier(for: nextValue)
        guard previous != next else { return }
        let rising = next > previous
        let crossings = max(1, abs(next - previous))
        var values: [CGFloat] = [Self.progress(for: previousValue)]
        for _ in 0..<crossings {
            values.append(contentsOf: rising ? [1, 1, 0, 0] : [0, 0, 1, 1])
        }
        values.append(Self.progress(for: nextValue))
        let duration = rising
            ? min(1.25, 0.72 + Double(crossings) * 0.12 + Double(next) * 0.06)
            : min(1.05, 0.62 + Double(crossings) * 0.1)
        let fill = CAKeyframeAnimation(keyPath: "strokeEnd")
        fill.values = values
        fill.keyTimes = (0..<values.count).map { NSNumber(value: Double($0) / Double(max(1, values.count - 1))) }
        fill.duration = duration
        fill.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(fill, forKey: rising ? "stage-fill-reset" : "stage-drain-restore")
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = rising ? [1, 0.98, 0.96, 1.055, 1] : [1, 0.96, 1.025, 1]
        pulse.keyTimes = rising ? [0, 0.18, 0.36, 0.68, 1] : [0, 0.28, 0.64, 1]
        pulse.duration = duration
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.add(pulse, forKey: "energy-tier-body")
        animateTopologyChange(
            from: previous,
            to: next,
            previousNodePositions: previousNodePositions,
            rising: rising,
            delay: duration * 0.16,
            duration: duration * 0.78
        )
        playBreakthrough(color: color, rising: rising, delay: duration * 0.42, duration: arcade ? 0.5 : 0.62)
    }

    private func topologyLayer(for tier: Int) -> CAShapeLayer {
        switch tier {
        case 1: return chassis
        case 2: return bus
        case 3: return ports
        case 4: return stabilizer
        default: return crown
        }
    }

    private func animateTopologyChange(
        from previous: Int,
        to next: Int,
        previousNodePositions: [CGPoint],
        rising: Bool,
        delay: CFTimeInterval,
        duration: CFTimeInterval
    ) {
        let layer = topologyLayer(for: rising ? next : previous)
        let group = CAAnimationGroup()
        let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
        draw.values = rising ? [0, 0, 0.5, 1, 1] : [1, 1, 0.45, 0]
        draw.keyTimes = rising ? [0, 0.14, 0.5, 0.78, 1] : [0, 0.2, 0.64, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = rising ? [0, 0, 1, 0.88, layer.opacity] : [layer.opacity, 1, 0.42, 0]
        opacity.keyTimes = rising ? [0, 0.14, 0.56, 0.8, 1] : [0, 0.2, 0.64, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = rising ? [0.94, 0.94, 1.04, 1] : [1, 1.02, 0.96, 0.94]
        scale.keyTimes = [0, 0.14, 0.64, 1]
        let glow = CAKeyframeAnimation(keyPath: "shadowRadius")
        glow.values = rising ? [0, 0, 6, 4, layer.shadowRadius] : [layer.shadowRadius, 5, 2, 0]
        glow.keyTimes = rising ? [0, 0.14, 0.52, 0.8, 1] : [0, 0.2, 0.64, 1]
        group.animations = [draw, opacity, scale, glow]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = duration
        group.fillMode = .backwards
        group.timingFunction = CAMediaTimingFunction(name: rising ? .easeOut : .easeInEaseOut)
        layer.add(group, forKey: rising ? "energy-topology-assemble" : "energy-topology-release")

        let previousCount = visibleNodeCount(tier: previous)
        let nextCount = visibleNodeCount(tier: next)
        let animatedCount = max(previousCount, nextCount)
        guard animatedCount > 0 else { return }
        for index in 0..<animatedCount {
            let node = nodes[index]
            let fallbackIndex = previousCount > 0 ? index % previousCount : 0
            let start = index < previousCount
                ? previousNodePositions[index]
                : previousCount > 0 ? previousNodePositions[fallbackIndex] : CGPoint(x: 46, y: 46)
            let end = index < nextCount
                ? nodePosition(index: index, tier: next)
                : nextCount > 0 ? nodePosition(index: index % nextCount, tier: next) : CGPoint(x: 46, y: 46)
            let movement = CAKeyframeAnimation(keyPath: "position")
            movement.values = [start, start, midpoint(from: start, to: end, outward: rising ? 4 : -2), end]
            movement.keyTimes = [0, 0.14, 0.58, 1]
            let nodeOpacity = CAKeyframeAnimation(keyPath: "opacity")
            nodeOpacity.values = index < nextCount
                ? [index < previousCount ? 1 : 0, 0.34, 1, 1]
                : [1, 1, 0.5, 0]
            nodeOpacity.keyTimes = [0, 0.2, 0.64, 1]
            let nodeGroup = CAAnimationGroup()
            nodeGroup.animations = [movement, nodeOpacity]
            nodeGroup.beginTime = CACurrentMediaTime() + delay + Double(index) * 0.045
            nodeGroup.duration = duration * 0.9
            nodeGroup.fillMode = .backwards
            nodeGroup.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            node.add(nodeGroup, forKey: "energy-node-migrate-\(index)")
        }
    }

    private func midpoint(from start: CGPoint, to end: CGPoint, outward: CGFloat) -> CGPoint {
        var midpoint = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = midpoint.x - 46
        let dy = midpoint.y - 46
        let length = max(1, hypot(dx, dy))
        midpoint.x += dx / length * outward
        midpoint.y += dy / length * outward
        return midpoint
    }

    private func playBreakthrough(color: NSColor, rising: Bool, delay: CFTimeInterval, duration: CFTimeInterval) {
        let wave = CAShapeLayer()
        wave.frame = effects.bounds
        wave.path = CGPath(ellipseIn: CGRect(x: 9, y: 9, width: 74, height: 74), transform: nil)
        wave.fillColor = NSColor.clear.cgColor
        wave.strokeColor = (rising ? color : NSColor.systemOrange).cgColor
        wave.lineWidth = rising ? 1.8 : 1.3
        wave.shadowColor = wave.strokeColor
        wave.shadowOpacity = rising ? 0.34 : 0.22
        wave.shadowRadius = rising ? 4 : 2
        effects.addSublayer(wave)
        let group = CAAnimationGroup()
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = rising ? 0.94 : 1.08
        scale.toValue = rising ? 1.2 : 0.94
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0]
        opacity.keyTimes = [0, 0.28, 1]
        group.animations = [scale, opacity]
        group.beginTime = CACurrentMediaTime() + delay
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: rising ? .easeOut : .easeInEaseOut)
        wave.add(group, forKey: rising ? "energy-breakthrough" : "energy-release")
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.08) { [weak wave] in
            wave?.removeFromSuperlayer()
        }
    }
}

@MainActor
private final class ComboArcRenderer {
    private let track: CAShapeLayer
    private let arc: CAShapeLayer
    private let label: CATextLayer
    private var lastSignature = ""
    private var lastCount = 0
    private var lastStage = "idle"
    private var generation = 0

    init(track: CAShapeLayer, arc: CAShapeLayer, label: CATextLayer) {
        self.track = track
        self.arc = arc
        self.label = label
    }

    func update(
        state: PowerState,
        color: NSColor,
        event: PowerEvent?,
        visible: Bool,
        arcade: Bool,
        reducedMotion: Bool
    ) {
        guard visible else {
            reset(signature: "hidden")
            return
        }
        let now = Date()
        let count = state.combo ?? 0
        let expires = parseDate(state.comboExpiresAt)
        let brokenAt = parseDate(state.comboBrokenAt) ?? expires
        guard count > 0, let expires, expires > now else {
            let showBreak = brokenAt.map { now < $0.addingTimeInterval(3.2) } ?? false
            let signature = showBreak ? "lost|\(state.comboBrokenAt ?? state.comboExpiresAt ?? "")" : "idle"
            guard signature != lastSignature else { return }
            lastSignature = signature
            if showBreak {
                playBreak(reducedMotion: reducedMotion)
            } else {
                reset(signature: signature)
            }
            lastCount = 0
            lastStage = showBreak ? "lost" : "idle"
            return
        }

        let hold = parseDate(state.comboHoldUntil) ?? now
        let totalDuration = max(0.1, expires.timeIntervalSince(hold))
        let logicalProgress = now < hold ? 1 : max(0, min(1, expires.timeIntervalSince(now) / totalDuration))
        let stage = state.comboStatus == "reward" || state.comboStatus == "complete"
            ? "reward"
            : logicalProgress <= 0.25 ? "critical" : stageName(count)
        let signature = "\(count)|\(state.comboStatus ?? "")|\(state.comboHoldUntil ?? "")|\(state.comboExpiresAt ?? "")|\(stage)"
        guard signature != lastSignature else { return }

        let hadVisibleArc = lastCount > 0 && arc.opacity > 0
        let displayedProgress = max(0, min(1, arc.presentation()?.strokeEnd ?? arc.strokeEnd))
        let startProgress = hadVisibleArc ? min(displayedProgress, logicalProgress) : logicalProgress
        let grew = count > lastCount && event?.sessionTransition == nil
        let crossedStage = grew && stage != lastStage && !["critical", "reward"].contains(stage)
        let relinked = state.comboRelinkedAt
            .flatMap(parseDate)
            .map { abs(now.timeIntervalSince($0)) < 1.6 } ?? false

        lastSignature = signature
        generation &+= 1
        let currentGeneration = generation
        let stageColor: NSColor = stage == "reward" ? .systemGreen : color
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.opacity = 1
        arc.opacity = 1
        arc.lineDashPattern = nil
        arc.strokeColor = stageColor.cgColor
        arc.shadowColor = stageColor.cgColor
        arc.shadowOpacity = stage == "critical" ? 0.72 : 0.46
        arc.shadowRadius = stage == "critical" ? 6 : 3
        arc.removeAllAnimations()
        arc.strokeEnd = 0
        label.opacity = 1
        label.string = "\(count)×"
        label.foregroundColor = NSColor.white.cgColor
        CATransaction.commit()

        let holdDelay = max(0, hold.timeIntervalSince(now))
        let decayDuration = now < hold ? totalDuration : max(0.1, expires.timeIntervalSince(now))
        if grew, !reducedMotion, logicalProgress - startProgress > 0.01 {
            let refillDuration: CFTimeInterval = 0.22
            let decayStart = max(refillDuration, holdDelay)
            let animationDuration = decayStart + decayDuration
            let refill = CAKeyframeAnimation(keyPath: "strokeEnd")
            refill.values = [startProgress, logicalProgress, logicalProgress, 0]
            refill.keyTimes = [
                0,
                NSNumber(value: refillDuration / animationDuration),
                NSNumber(value: decayStart / animationDuration),
                1
            ]
            refill.duration = animationDuration
            refill.fillMode = .both
            refill.isRemovedOnCompletion = false
            arc.add(refill, forKey: "combo-arc-refill-decay-\(currentGeneration)")
        } else {
            let decay = CABasicAnimation(keyPath: "strokeEnd")
            decay.fromValue = startProgress
            decay.toValue = 0
            decay.beginTime = arc.convertTime(CACurrentMediaTime(), from: nil) + holdDelay
            decay.duration = decayDuration
            decay.fillMode = .both
            decay.isRemovedOnCompletion = false
            arc.add(decay, forKey: "combo-arc-decay-\(currentGeneration)")
        }

        if grew { playGrowth(strong: crossedStage, reducedMotion: reducedMotion) }
        if relinked { playGrowth(strong: true, reducedMotion: reducedMotion) }
        if stage == "critical" && lastStage != "critical" { playWarning(reducedMotion: reducedMotion) }
        lastCount = count
        lastStage = stage
    }

    func playHandoff(reducedMotion: Bool) {
        playGrowth(strong: false, reducedMotion: reducedMotion)
    }

    private func reset(signature: String) {
        lastSignature = signature
        lastCount = 0
        lastStage = "idle"
        arc.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        arc.opacity = 0
        arc.strokeEnd = 0
        arc.lineDashPattern = nil
        track.opacity = 0
        label.opacity = 0
        label.string = ""
        CATransaction.commit()
    }

    private func stageName(_ count: Int) -> String {
        if count < 5 { return "ignition" }
        if count < 10 { return "linked" }
        if count < 20 { return "accelerated" }
        if count < 40 { return "heated" }
        return "extreme"
    }

    private func playGrowth(strong: Bool, reducedMotion: Bool) {
        guard !reducedMotion else { return }
        let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
        pulse.values = strong ? [1, 1.12, 0.97, 1] : [1, 1.06, 1]
        pulse.keyTimes = strong ? [0, 0.35, 0.7, 1] : [0, 0.45, 1]
        pulse.duration = strong ? 0.48 : 0.24
        arc.add(pulse, forKey: "combo-arc-growth")
        label.add(pulse, forKey: "combo-label-growth")
    }

    private func playWarning(reducedMotion: Bool) {
        guard !reducedMotion else { return }
        let warning = CAKeyframeAnimation(keyPath: "opacity")
        warning.values = [1, 0.38, 1, 0.52, 1]
        warning.keyTimes = [0, 0.18, 0.36, 0.62, 1]
        warning.duration = 0.82
        arc.add(warning, forKey: "combo-arc-warning")
    }

    private func playBreak(reducedMotion: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        track.opacity = 1
        arc.removeAllAnimations()
        arc.opacity = reducedMotion ? 0.72 : 0
        arc.strokeColor = NSColor.systemRed.cgColor
        arc.shadowColor = NSColor.systemRed.cgColor
        arc.shadowOpacity = 0.7
        arc.shadowRadius = 6
        arc.lineDashPattern = [8, 6]
        arc.strokeEnd = 0.72
        label.opacity = reducedMotion ? 1 : 0
        label.string = "×"
        label.foregroundColor = NSColor.systemRed.cgColor
        CATransaction.commit()
        guard !reducedMotion else { return }
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [1, 1, 0.65, 0]
        opacity.keyTimes = [0, 0.18, 0.52, 1]
        opacity.duration = 0.72
        arc.add(opacity, forKey: "combo-arc-break")
        label.add(opacity, forKey: "combo-label-break")
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }
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
    private let signatureBackdrop = CAShapeLayer()
    private let signature = CAShapeLayer()
    private var energyVisuals: EnergyEvolutionRenderer!
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
    private var comboVisuals: ComboArcRenderer!
    private let typingValue = CATextLayer()
    private let connectionDot = CALayer()
    private let emitter = CAEmitterLayer()
    private let energyEffects = CALayer()
    private let semanticEffects = CALayer()
    private var completionAnimationGeneration = 0
    private var phase = "idle"
    private var completionStyle: String?
    private var rhythmGeneration = 0
    private var visualGeneration = 0
    private var activeVisualPriority = VisualPriority.ambient
    private var activeVisualUntil = Date.distantPast
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

        energyEffects.frame = container.bounds
        energyVisuals = EnergyEvolutionRenderer(
            body: body,
            container: container,
            effects: energyEffects,
            halo: halo,
            core: core,
            inner: inner,
            sheen: sheen
        )

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

        configureArc(comboTrack, radius: 43.5, width: 1.8, startDegrees: 202, endDegrees: 338)
        comboTrack.strokeColor = NSColor.white.withAlphaComponent(0.06).cgColor
        configureArc(comboRing, radius: 43.5, width: 2.1, startDegrees: 202, endDegrees: 338)
        comboRing.lineCap = .round
        configureRing(mixOrbit, radius: 46, width: 1.2)
        mixOrbit.lineDashPattern = nil
        mixOrbit.opacity = 0
        configureRing(typingOrbit, radius: 40.5, width: 1.8)
        typingOrbit.lineCap = .round
        typingOrbit.lineDashPattern = [3, 4]
        typingOrbit.opacity = 0
        configureRing(phaseRailBackdrop, radius: 32.2, width: 3.8)
        phaseRailBackdrop.lineCap = .round
        phaseRailBackdrop.opacity = 0
        configureRing(phaseRail, radius: 32.2, width: 1.45)
        phaseRail.lineCap = .round
        phaseRail.opacity = 0
        configureRing(beatRing, radius: 40.5, width: 1.4)
        beatRing.opacity = 0
        beatRing.lineCap = .round

        configureText(semantic, frame: CGRect(x: 24, y: 68, width: 44, height: 14), size: 8.8, weight: .bold)
        configureText(comboValue, frame: CGRect(x: 28, y: 59, width: 36, height: 11), size: 7.5, weight: .bold)
        comboVisuals = ComboArcRenderer(track: comboTrack, arc: comboRing, label: comboValue)
        configureText(typingValue, frame: CGRect(x: 14, y: 75, width: 64, height: 10), size: 6.4, weight: .bold)
        typingValue.opacity = 0
        configureText(value, frame: CGRect(x: 14, y: 35, width: 64, height: 29), size: 24, weight: .bold)
        configureText(activity, frame: CGRect(x: 12, y: 23, width: 68, height: 12), size: 7.2, weight: .semibold)
        activity.masksToBounds = true

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
        for effects in [energyEffects, semanticEffects] {
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

    private func configureArc(_ layer: CAShapeLayer, radius: CGFloat, width: CGFloat, startDegrees: CGFloat, endDegrees: CGFloat) {
        layer.frame = container.bounds
        let path = CGMutablePath()
        path.addArc(
            center: CGPoint(x: 46, y: 46),
            radius: radius,
            startAngle: startDegrees * .pi / 180,
            endAngle: endDegrees * .pi / 180,
            clockwise: false
        )
        layer.path = path
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
        reducedMotion = preferences.reduceMotionEnabled
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
        let energy = energyVisuals.update(
            momentum: presentation.momentum,
            phase: nextPhase,
            phaseColor: color,
            arcade: arcade,
            reducedMotion: reducedMotion
        )
        energyVisuals.setCompletionEmphasis(nextPhase == "complete")
        let nextEnergyTier = energy.tier
        CATransaction.begin()
        CATransaction.setAnimationDuration(reducedMotion ? 0 : event?.sessionTransition != nil ? 0.78 : 0.36)
        if event?.sessionTransition != nil, !reducedMotion {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.72
            value.add(fade, forKey: "session-value-crossfade")
        }
        value.string = "\(presentation.momentum)"
        activity.string = label
        let completionLabel = state.completion != nil || state.mixedLastCompletion != nil
        activity.frame = completionLabel
            ? CGRect(x: 12, y: 23, width: 68, height: 12)
            : CGRect(x: 10, y: 23, width: 72, height: 12)
        activity.fontSize = activityFontSize(label, completion: completionLabel)
        let activityColor = color.blended(withFraction: 0.48, of: .white) ?? .white
        activity.foregroundColor = activityColor.withAlphaComponent(nextPhase == "idle" ? 0.48 : 0.96).cgColor
        semantic.string = phaseGlyph(nextPhase, completion: state.completion)
        semantic.foregroundColor = color.cgColor
        CATransaction.commit()
        updateMixOrbit(state, color: color)
        comboVisuals.update(
            state: state,
            color: color,
            event: event,
            visible: preferences.settings.showCombo == true,
            arcade: arcade,
            reducedMotion: reducedMotion
        )
        let visualTransitionAccepted = event.map { beginVisualTransition(for: $0, phase: nextPhase) } ?? false
        let semanticPhaseChanged = phase != nextPhase || completionStyle != state.completion
        if semanticPhaseChanged {
            if nextPhase != "complete" { completionAnimationGeneration += 1 }
            phase = nextPhase
            completionStyle = state.completion
            updateCoreSignature(nextPhase, completion: state.completion, color: color)
            animateSemanticPhase(nextPhase)
            animateCorePhase(nextPhase)
        }
        updateSemanticContrast(phase: nextPhase, tier: nextEnergyTier, color: color)
        if let event, visualTransitionAccepted {
            if event.sessionTransition != nil { animateSessionTransition(color: color) }
            let partialMixCompletion = event.mixCompletion != nil
                && (state.mixedConversationCount ?? 0) > 0
                && nextPhase != "complete"
            if partialMixCompletion {
                playMixCompletion(completion: event.mixCompletion)
            } else {
                animateCoreEvent(nextPhase)
                animateEventRhythm(event, phase: nextPhase, color: color)
                playSemanticChoreography(phase: nextPhase, completion: state.completion, color: color)
                emitFeedback(for: event, phase: nextPhase, color: color)
            }
        }
        if semanticPhaseChanged && (event == nil || visualTransitionAccepted) {
            animateSemanticReveal(phase: nextPhase, tier: nextEnergyTier)
        }
    }

    private func visualPriority(for event: PowerEvent, phase: String) -> VisualPriority {
        if event.type == "turn-stop" || phase == "complete" { return .terminal }
        if event.type == "permission-request" || event.type == "edit-failure" ||
            (event.type == "verification" && event.success != true) || phase == "recover" || phase == "wait" {
            return .attention
        }
        if event.type == "verification" || phase == "verify" { return .verification }
        if event.type == "edit" || phase == "act" { return .progress }
        return .ambient
    }

    private func visualHold(for priority: VisualPriority) -> TimeInterval {
        switch priority {
        case .terminal: return 1.7
        case .attention: return 1.2
        case .verification: return 0.95
        case .progress: return 0.68
        case .ambient: return 0.48
        }
    }

    private func beginVisualTransition(for event: PowerEvent, phase: String) -> Bool {
        let now = Date()
        let priority = visualPriority(for: event, phase: phase)
        if now < activeVisualUntil && priority.rawValue < activeVisualPriority.rawValue {
            return false
        }
        visualGeneration &+= 1
        let generation = visualGeneration
        rhythmGeneration &+= 1
        completionAnimationGeneration &+= 1
        activeVisualPriority = priority
        let hold = visualHold(for: priority)
        activeVisualUntil = now.addingTimeInterval(hold)

        semanticEffects.sublayers?.forEach { $0.removeFromSuperlayer() }
        emitter.emitterCells = nil
        beatRing.removeAllAnimations()
        beatRing.opacity = 0
        body.removeAnimation(forKey: "body-event")
        sheen.removeAnimation(forKey: "sheen-event")
        for key in container.animationKeys() ?? [] where key.hasPrefix("event-rhythm-") || key == "event-impact" {
            container.removeAnimation(forKey: key)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + hold) { [weak self] in
            guard let self, self.visualGeneration == generation else { return }
            self.activeVisualPriority = .ambient
            self.activeVisualUntil = .distantPast
        }
        return true
    }

    private func activityFontSize(_ label: String, completion: Bool) -> CGFloat {
        let weightedLength = label.unicodeScalars.reduce(0) { partial, scalar in
            partial + (scalar.value > 0x7F ? 2 : 1)
        }
        if completion {
            if weightedLength > 14 { return 4.9 }
            if weightedLength > 10 { return 5.6 }
            return 6.2
        }
        if weightedLength > 18 { return 5.2 }
        if weightedLength > 14 { return 5.8 }
        return 7.2
    }

    private func updateMixOrbit(_ state: PowerState, color: NSColor) {
        mixOrbit.opacity = 0
        mixOrbit.removeAllAnimations()
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

    private func animateSessionTransition(color: NSColor) {
        guard !reducedMotion else { return }
        let handoff = CAKeyframeAnimation(keyPath: "transform.scale")
        handoff.values = [1, 0.74, 0.74, 1.06, 1]
        handoff.keyTimes = [0, 0.32, 0.54, 0.8, 1]
        handoff.duration = 0.78
        handoff.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        body.add(handoff, forKey: "session-handoff")
        energyVisuals.animateSessionHandoff(reducedMotion: reducedMotion)
        comboVisuals.playHandoff(reducedMotion: reducedMotion)
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
        phaseRailBackdrop.path = phaseRailPath(phase)
        phaseRail.path = phaseRailPath(phase)
        signature.strokeColor = color.withAlphaComponent(phase == "idle" ? 0.28 : 0.82).cgColor
        signature.shadowColor = color.cgColor
        signature.shadowOpacity = phase == "idle" ? 0.1 : arcade ? 0.72 : 0.42
        signature.shadowRadius = arcade ? 4.5 : 2.5
        signature.lineWidth = phase == "complete" ? (arcade ? 2.15 : 1.8) : (arcade ? 1.9 : 1.55)
        signature.lineDashPattern = phase == "complete" && completion == "unverified" ? [4, 3]
            : phase == "complete" && completion == "cancelled" ? [8, 5]
            : nil
        signature.opacity = phase == "idle" ? 0.36 : 1
        phaseRail.opacity = 0
        phaseRail.strokeColor = color.withAlphaComponent(0.92).cgColor
        phaseRail.shadowColor = color.cgColor
        phaseRail.shadowOpacity = phase == "complete" ? (arcade ? 0.68 : 0.42) : 0
        phaseRail.shadowRadius = arcade ? 4 : 2.4
        phaseRail.lineWidth = phase == "wait" || phase == "recover" ? 1.8 : 1.45
        phaseRail.lineDashPattern = nil
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
    }

    private func updateSemanticContrast(phase: String, tier: Int, color: NSColor) {
        let highEnergy = tier >= 4
        let peakEnergy = tier >= 5
        let active = phase != "idle"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signature.strokeColor = color.withAlphaComponent(active ? 0.98 : 0.28).cgColor
        signature.lineWidth = phase == "complete"
            ? (arcade ? 2.65 : 2.2)
            : (arcade ? 2.35 : 1.95)
        signature.shadowColor = color.cgColor
        signature.shadowOpacity = active
            ? (phase == "complete" ? (highEnergy ? 0.9 : 0.68) : highEnergy ? 0.78 : 0.56)
            : 0.08
        signature.shadowRadius = highEnergy ? (peakEnergy ? 7 : 5.5) : arcade ? 4.5 : 2.8
        signatureBackdrop.strokeColor = NSColor.black.withAlphaComponent(highEnergy ? 0.74 : 0.5).cgColor
        signatureBackdrop.lineWidth = signature.lineWidth + (highEnergy ? 3.6 : 2.5)
        signature.opacity = active ? 1 : 0.36
        signatureBackdrop.opacity = active ? (phase == "complete" ? 0.7 : highEnergy ? 0.5 : 0.28) : 0.12
        phaseRail.strokeColor = color.cgColor
        phaseRail.lineWidth = phase == "wait" || phase == "recover" ? (highEnergy ? 3.1 : 2.7) : (highEnergy ? 2.8 : 2.35)
        phaseRail.shadowOpacity = active ? (highEnergy ? 0.9 : 0.72) : 0
        phaseRail.shadowRadius = highEnergy ? 6.5 : arcade ? 5 : 3.4
        phaseRailBackdrop.strokeColor = NSColor.black.withAlphaComponent(highEnergy ? 0.68 : 0.42).cgColor
        phaseRailBackdrop.lineWidth = phaseRail.lineWidth + (highEnergy ? 3.1 : 2.3)
        phaseRail.opacity = 0
        phaseRailBackdrop.opacity = 0
        semantic.shadowColor = NSColor.black.cgColor
        semantic.shadowOpacity = active ? (highEnergy ? 0.95 : 0.62) : 0
        semantic.shadowRadius = highEnergy ? 3.5 : 2
        CATransaction.commit()
    }

    private func animateSemanticReveal(phase: String, tier: Int) {
        guard !reducedMotion, phase != "idle" else { return }
        let duration: CFTimeInterval = arcade ? 0.46 : 0.58
        if phase == "complete" {
            energyVisuals.animateSemanticDuck(duration: duration, reducedMotion: reducedMotion)
            let revealScale = CAKeyframeAnimation(keyPath: "transform.scale")
            revealScale.values = [0.88, 1.08, 1]
            revealScale.keyTimes = [0, 0.48, 1]
            let revealOpacity = CAKeyframeAnimation(keyPath: "opacity")
            revealOpacity.values = [0, 1, 1]
            revealOpacity.keyTimes = [0, 0.42, 1]
            let reveal = CAAnimationGroup()
            reveal.animations = [revealScale, revealOpacity]
            reveal.duration = duration
            reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
            signature.add(reveal, forKey: "semantic-reveal")
            signatureBackdrop.add(reveal, forKey: "semantic-backdrop-reveal")
        }
        let glyphReveal = CAKeyframeAnimation(keyPath: "transform.scale")
        glyphReveal.values = [0.86, arcade ? 1.14 : 1.08, 1]
        glyphReveal.keyTimes = [0, 0.48, 1]
        glyphReveal.duration = duration
        glyphReveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
        semantic.add(glyphReveal, forKey: "semantic-glyph-reveal")
    }

    private func phaseRailPath(_ phase: String) -> CGPath {
        let path = CGMutablePath()
        let center = CGPoint(x: 46, y: 46)
        let radius: CGFloat = 32.2
        switch phase {
        case "observe":
            // Four inward-facing scanner vanes leave an unmistakable broken aperture.
            for start in stride(from: CGFloat(-78), to: 282, by: 90) {
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: start * .pi / 180,
                    endAngle: (start + 42) * .pi / 180,
                    clockwise: false
                )
            }
        case "act":
            // Two directional rails and arrowheads create a horizontal drive silhouette.
            path.addArc(center: center, radius: radius, startAngle: 0.72, endAngle: 2.42, clockwise: false)
            path.addArc(center: center, radius: radius, startAngle: 3.86, endAngle: 5.56, clockwise: false)
            path.move(to: CGPoint(x: 15, y: 29))
            path.addLine(to: CGPoint(x: 9, y: 35))
            path.addLine(to: CGPoint(x: 17, y: 37))
            path.move(to: CGPoint(x: 77, y: 55))
            path.addLine(to: CGPoint(x: 83, y: 61))
            path.addLine(to: CGPoint(x: 75, y: 63))
        case "verify":
            // A four-corner targeting frame reads as a lock even after particles settle.
            let inset: CGFloat = 15
            let outer: CGFloat = 24
            for (sx, sy) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
                let x = CGFloat(sx)
                let y = CGFloat(sy)
                path.move(to: CGPoint(x: 46 + x * inset, y: 46 + y * outer))
                path.addLine(to: CGPoint(x: 46 + x * outer, y: 46 + y * outer))
                path.addLine(to: CGPoint(x: 46 + x * outer, y: 46 + y * inset))
            }
        case "wait":
            // Opposing rails visibly latch twice without resembling rotation.
            for x in [CGFloat(14), 78] {
                path.move(to: CGPoint(x: x, y: 25))
                path.addLine(to: CGPoint(x: x, y: 67))
            }
            path.move(to: CGPoint(x: 14, y: 31))
            path.addLine(to: CGPoint(x: 23, y: 31))
            path.move(to: CGPoint(x: 69, y: 61))
            path.addLine(to: CGPoint(x: 78, y: 61))
        case "recover":
            // Uneven fragments deliberately break circular continuity.
            for (start, end) in [(-82.0, -24.0), (8.0, 58.0), (96.0, 142.0), (174.0, 226.0)] {
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: CGFloat(start) * .pi / 180,
                    endAngle: CGFloat(end) * .pi / 180,
                    clockwise: false
                )
            }
        case "complete":
            path.addEllipse(in: CGRect(x: 46 - radius, y: 46 - radius, width: radius * 2, height: radius * 2))
        default:
            path.addEllipse(in: CGRect(x: 46 - radius, y: 46 - radius, width: radius * 2, height: radius * 2))
        }
        return path
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
            break
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

    private func playSemanticChoreography(phase: String, completion: String?, color: NSColor) {
        guard phase != "idle" else { return }
        semanticEffects.sublayers?.forEach { $0.removeFromSuperlayer() }
        if reducedMotion {
            if phase == "complete" { playCompleteFamily(completion: completion) }
            return
        }
        switch phase {
        case "observe": playObserveCapture(color: color)
        case "act":
            playActArrow(color: color)
            playActDrive(color: color)
        case "verify": playVerifyConvergence(color: color)
        case "wait": playWaitGates(color: color)
        case "recover": playRecoverFragments(color: color)
        case "complete": playCompleteFamily(completion: completion)
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
        let count = max(4, Int((arcade ? 8 : 4) * intensity))
        for index in 0..<count {
            let angle = CGFloat(index) / CGFloat(count) * .pi * 2 + CGFloat(index % 2) * 0.17
            let radius: CGFloat = arcade ? 66 : 56
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
        let count = max(4, Int((arcade ? 8 : 5) * intensity))
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

    private func playActArrow(color: NSColor) {
        guard !reducedMotion else { return }
        let duration: CFTimeInterval = arcade ? 0.78 : 0.9
        energyVisuals.animateActClearance(duration: duration, reducedMotion: reducedMotion)

        let arrow = CAShapeLayer()
        arrow.frame = semanticEffects.bounds
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 10, y: 39))
        path.addLine(to: CGPoint(x: 58, y: 39))
        path.addLine(to: CGPoint(x: 58, y: 30))
        path.addLine(to: CGPoint(x: 86, y: 46))
        path.addLine(to: CGPoint(x: 58, y: 62))
        path.addLine(to: CGPoint(x: 58, y: 53))
        path.addLine(to: CGPoint(x: 10, y: 53))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = color.withAlphaComponent(arcade ? 0.11 : 0.07).cgColor
        arrow.strokeColor = color.withAlphaComponent(0.96).cgColor
        arrow.lineWidth = arcade ? 2.4 : 1.8
        arrow.lineJoin = .round
        arrow.shadowColor = color.cgColor
        arrow.shadowOpacity = arcade ? 0.72 : 0.46
        arrow.shadowRadius = arcade ? 4.5 : 2.8
        semanticEffects.addSublayer(arrow)

        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        translation.values = [-18, 0, 6, 18]
        translation.keyTimes = [0, 0.22, 0.68, 1]
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 0.82, 0]
        opacity.keyTimes = [0, 0.15, 0.68, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scale.values = [0.84, 1, 1.04, 1]
        scale.keyTimes = [0, 0.28, 0.7, 1]
        let group = CAAnimationGroup()
        group.animations = [translation, opacity, scale]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.fillMode = .both
        group.isRemovedOnCompletion = false
        arrow.add(group, forKey: "act-arrow-pass")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.08) { [weak arrow] in
            arrow?.removeFromSuperlayer()
        }
    }

    private func playVerifyConvergence(color: NSColor) {
        let lanes = arcade ? 6 : 4
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
        let count = max(5, Int((arcade ? 9 : 5) * intensity))
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

    private func playCompleteFamily(completion: String?) {
        completionAnimationGeneration += 1
        let generation = completionAnimationGeneration
        let commonColor = NSColor(calibratedRed: 0.76, green: 0.96, blue: 1, alpha: 1)
        let outcomeColor: NSColor
        switch completion {
        case "verified": outcomeColor = .systemGreen
        case "unverified": outcomeColor = .systemYellow
        case "cancelled": outcomeColor = .systemOrange
        default: outcomeColor = .systemCyan
        }

        if reducedMotion {
            semantic.string = phaseGlyph("complete", completion: completion)
            semantic.foregroundColor = outcomeColor.cgColor
            updateCoreSignature("complete", completion: completion, color: outcomeColor)
            let confirmation = completionRing(radius: 37, color: outcomeColor, width: 2)
            confirmation.opacity = 0.84
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { [weak confirmation] in
                confirmation?.removeFromSuperlayer()
            }
            return
        }

        semantic.string = preferences.text("COMPLETE", "完成")
        semantic.foregroundColor = commonColor.cgColor
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        signature.path = completeClosurePath()
        signature.strokeColor = commonColor.cgColor
        signature.lineDashPattern = nil
        signatureBackdrop.path = completeClosurePath()
        phaseRail.strokeColor = commonColor.cgColor
        phaseRail.lineDashPattern = nil
        CATransaction.commit()
        semantic.removeAnimation(forKey: "complete-stamp")
        let stamp = CAKeyframeAnimation(keyPath: "transform.scale")
        stamp.values = [0.72, 1.12, 1, 1]
        stamp.keyTimes = [0, 0.28, 0.54, 1]
        stamp.duration = arcade ? 0.7 : 0.82
        stamp.timingFunction = CAMediaTimingFunction(name: .easeOut)
        semantic.add(stamp, forKey: "complete-stamp")

        let closure = completionRing(radius: 36, color: commonColor, width: arcade ? 2.8 : 2.1)
        closure.strokeEnd = 0
        let close = CAKeyframeAnimation(keyPath: "strokeEnd")
        close.values = [0, 0.08, 0.82, 1, 1]
        close.keyTimes = [0, 0.14, 0.62, 0.8, 1]
        let pause = CAKeyframeAnimation(keyPath: "transform.scale")
        pause.values = [1.05, 1.05, 0.91, 0.91, 1]
        pause.keyTimes = [0, 0.2, 0.62, 0.76, 1]
        let closureOpacity = CAKeyframeAnimation(keyPath: "opacity")
        closureOpacity.values = [0, 1, 1, 0.92, 0]
        closureOpacity.keyTimes = [0, 0.12, 0.72, 0.88, 1]
        let closureGroup = CAAnimationGroup()
        closureGroup.animations = [close, pause, closureOpacity]
        closureGroup.duration = arcade ? 1.12 : 1.28
        closureGroup.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.78, 0.2, 1)
        closure.add(closureGroup, forKey: "complete-family-closure")

        let outcomeDelay: CFTimeInterval = arcade ? 0.7 : 0.82
        DispatchQueue.main.asyncAfter(deadline: .now() + outcomeDelay) { [weak self] in
            guard let self, self.completionAnimationGeneration == generation else { return }
            self.semantic.string = self.phaseGlyph("complete", completion: completion)
            self.semantic.foregroundColor = outcomeColor.cgColor
            self.updateCoreSignature("complete", completion: completion, color: outcomeColor)
            let reveal = CAKeyframeAnimation(keyPath: "transform.scale")
            reveal.values = [0.62, self.arcade ? 1.55 : 1.32, 0.94, 1]
            reveal.keyTimes = [0, 0.35, 0.7, 1]
            reveal.duration = self.arcade ? 0.44 : 0.56
            reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.semantic.add(reveal, forKey: "complete-outcome-stamp")
            self.playCompleteOutcome(completion: completion, color: outcomeColor)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) { [weak closure] in
            closure?.removeFromSuperlayer()
        }
    }

    private func playMixCompletion(completion: String?) {
        completionAnimationGeneration += 1
        let generation = completionAnimationGeneration
        semanticEffects.sublayers?.forEach { $0.removeFromSuperlayer() }
        let commonColor = NSColor(calibratedRed: 0.76, green: 0.96, blue: 1, alpha: 1)
        let outcomeColor: NSColor
        switch completion {
        case "verified": outcomeColor = .systemGreen
        case "unverified": outcomeColor = .systemYellow
        case "cancelled": outcomeColor = .systemOrange
        default: outcomeColor = .systemCyan
        }
        let closure = completionRing(radius: 40, color: commonColor, width: arcade ? 2.7 : 1.9)
        if reducedMotion {
            closure.opacity = 0.86
        } else {
            closure.strokeEnd = 0
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 0.12, 1, 1]
            draw.keyTimes = [0, 0.18, 0.72, 1]
            let opacity = CAKeyframeAnimation(keyPath: "opacity")
            opacity.values = [0, 0.96, 0.82, 0]
            opacity.keyTimes = [0, 0.12, 0.78, 1]
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [1.04, 0.94, 1, 1.08]
            scale.keyTimes = [0, 0.46, 0.72, 1]
            let group = CAAnimationGroup()
            group.animations = [draw, opacity, scale]
            group.duration = arcade ? 0.86 : 1.02
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            closure.add(group, forKey: "mix-complete-closure")
        }
        let outcomeDelay: CFTimeInterval = reducedMotion ? 0 : arcade ? 0.48 : 0.58
        DispatchQueue.main.asyncAfter(deadline: .now() + outcomeDelay) { [weak self] in
            guard let self, self.completionAnimationGeneration == generation else { return }
            let stamp = self.completionGlyphLayer(self.phaseGlyph("complete", completion: completion), color: outcomeColor)
            let ring = self.completionRing(
                radius: 36,
                color: outcomeColor,
                width: self.arcade ? 2.2 : 1.45,
                start: completion == "unverified" ? 0.08 : completion == "cancelled" ? 0.04 : 0,
                end: completion == "unverified" ? 0.88 : completion == "cancelled" ? 0.46 : 1
            )
            if completion == "unverified" { ring.lineDashPattern = [9, 4] }
            if self.reducedMotion {
                ring.opacity = 0.82
                stamp.opacity = 1
            } else {
                self.animateCompletionOutcomeRing(
                    ring,
                    key: "mix-complete-outcome",
                    scales: [0.9, 1.06, 1.16],
                    duration: self.arcade ? 0.72 : 0.9
                )
                let reveal = CAKeyframeAnimation(keyPath: "transform.scale")
                reveal.values = [0.55, self.arcade ? 1.42 : 1.24, 1]
                reveal.keyTimes = [0, 0.48, 1]
                reveal.duration = self.arcade ? 0.4 : 0.52
                reveal.timingFunction = CAMediaTimingFunction(name: .easeOut)
                stamp.add(reveal, forKey: "mix-complete-stamp")
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + (self.reducedMotion ? 1.1 : 1.02)) { [weak stamp, weak ring] in
                stamp?.removeFromSuperlayer()
                ring?.removeFromSuperlayer()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7) { [weak closure] in
            closure?.removeFromSuperlayer()
        }
    }

    private func completionGlyphLayer(_ glyph: String, color: NSColor) -> CATextLayer {
        let stamp = CATextLayer()
        stamp.frame = CGRect(x: 34, y: 67, width: 24, height: 16)
        stamp.alignmentMode = .center
        stamp.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        stamp.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
        stamp.fontSize = 11
        stamp.string = glyph
        stamp.foregroundColor = color.cgColor
        stamp.shadowColor = NSColor.black.cgColor
        stamp.shadowOpacity = 0.8
        stamp.shadowRadius = 2
        stamp.opacity = reducedMotion ? 1 : 0.96
        semanticEffects.addSublayer(stamp)
        return stamp
    }

    private func completionRing(radius: CGFloat, color: NSColor, width: CGFloat, start: CGFloat = 0, end: CGFloat = 1) -> CAShapeLayer {
        let ring = CAShapeLayer()
        ring.frame = semanticEffects.bounds
        ring.path = CGPath(ellipseIn: CGRect(x: 46 - radius, y: 46 - radius, width: radius * 2, height: radius * 2), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = width
        ring.lineCap = .round
        ring.strokeStart = start
        ring.strokeEnd = end
        ring.shadowColor = color.cgColor
        ring.shadowOpacity = arcade ? 0.82 : 0.46
        ring.shadowRadius = arcade ? 7 : 4
        ring.opacity = 0
        semanticEffects.addSublayer(ring)
        return ring
    }

    private func completeClosurePath() -> CGPath {
        CGPath(ellipseIn: CGRect(x: 20, y: 20, width: 52, height: 52), transform: nil)
    }

    private func playCompleteOutcome(completion: String?, color: NSColor) {
        switch completion {
        case "verified":
            let colors: [NSColor] = [
                .systemGreen,
                NSColor.white.withAlphaComponent(0.82),
                NSColor.systemGreen.withAlphaComponent(0.58)
            ]
            for (index, ringColor) in colors.enumerated() {
                let ring = completionRing(radius: 35 + CGFloat(index) * 4.5, color: ringColor, width: arcade ? 2.4 : 1.7)
                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                opacity.values = [0, 1, 0.72, 0]
                opacity.keyTimes = [0, 0.16, 0.55, 1]
                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                scale.values = [0.82, 1, 1.18, arcade ? 1.48 : 1.3]
                scale.keyTimes = [0, 0.18, 0.56, 1]
                let group = CAAnimationGroup()
                group.animations = [opacity, scale]
                group.beginTime = ring.convertTime(CACurrentMediaTime(), from: nil) + Double(index) * 0.1
                group.duration = arcade ? 0.92 : 1.08
                group.timingFunction = CAMediaTimingFunction(name: .easeOut)
                ring.add(group, forKey: "complete-verified-reward")
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.1 + group.duration + 0.08) { [weak ring] in ring?.removeFromSuperlayer() }
            }
        case "unverified":
            let ring = completionRing(radius: 37, color: color, width: arcade ? 3 : 2, start: 0.08, end: 0.88)
            ring.lineDashPattern = [9, 4]
            animateCompletionOutcomeRing(ring, key: "complete-unverified-gap", scales: [0.9, 1.04, 1], duration: arcade ? 1.12 : 1.3)
        case "cancelled":
            for (start, end) in [(CGFloat(0.04), CGFloat(0.46)), (CGFloat(0.54), CGFloat(0.96))] {
                let arc = completionRing(radius: 37, color: color, width: arcade ? 3.2 : 2.2, start: start, end: end)
                let opacity = CAKeyframeAnimation(keyPath: "opacity")
                opacity.values = [0, 1, 0.86, 0]
                opacity.keyTimes = [0, 0.12, 0.45, 1]
                let retract = CAKeyframeAnimation(keyPath: "strokeEnd")
                retract.values = [end, end, start, start]
                retract.keyTimes = [0, 0.42, 0.86, 1]
                let scale = CAKeyframeAnimation(keyPath: "transform.scale")
                scale.values = [1, 1, 0.82, 0.72]
                scale.keyTimes = [0, 0.42, 0.84, 1]
                let group = CAAnimationGroup()
                group.animations = [opacity, retract, scale]
                group.duration = arcade ? 1 : 1.18
                group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                arc.add(group, forKey: "complete-cancelled-retract")
                DispatchQueue.main.asyncAfter(deadline: .now() + group.duration + 0.08) { [weak arc] in arc?.removeFromSuperlayer() }
            }
        default:
            let ring = completionRing(radius: 36, color: color, width: arcade ? 2 : 1.35)
            animateCompletionOutcomeRing(ring, key: "complete-no-change-settle", scales: [1, 0.94, 0.78], duration: arcade ? 1.05 : 1.3)
        }
    }

    private func animateCompletionOutcomeRing(_ ring: CAShapeLayer, key: String, scales: [CGFloat], duration: CFTimeInterval) {
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 0.92, 0.7, 0]
        opacity.keyTimes = [0, 0.14, 0.62, 1]
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = scales
        scale.keyTimes = [0, 0.5, 1]
        let group = CAAnimationGroup()
        group.animations = [opacity, scale]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(group, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.08) { [weak ring] in ring?.removeFromSuperlayer() }
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
        if completion == "no-change" { return "·" }
        switch phase {
        case "observe": return "◌"
        case "act": return "›"
        case "verify": return "✓"
        case "wait": return "Ⅱ"
        case "recover": return "↻"
        case "complete": return "·"
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
    private let lifetimeFill = CAGradientLayer()
    private let lifetimeCap = CALayer()
    private let effects = CALayer()
    private weak var activeMemeText: CATextLayer?
    private weak var activePossumSticker: CALayer?
    private weak var activeFreshCatSticker: CALayer?
    private weak var activeKnifeShieldDog: CALayer?
    private weak var activeElegantPerson: CALayer?
    private var memeStickerImages: [String: NSImage] = [:]
    private var comboAnchor = CGPoint.zero
    private let lifetimeDuration: TimeInterval = 2

    init(hostLayer: CALayer, preferences: PowerModePreferences) {
        self.preferences = preferences
        root.masksToBounds = false
        effects.masksToBounds = false
        root.addSublayer(effects)
        for label in [comboGlow, comboValue] {
            label.bounds = CGRect(x: 0, y: 0, width: 112, height: 58)
            label.alignmentMode = .center
            label.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            label.font = NSFont.monospacedSystemFont(ofSize: 36, weight: .black)
            label.fontSize = 36
            label.string = ""
            root.addSublayer(label)
        }
        comboGlow.foregroundColor = NSColor(calibratedRed: 0.18, green: 0.88, blue: 1, alpha: 0.28).cgColor
        comboGlow.shadowColor = NSColor.systemCyan.cgColor
        comboGlow.shadowOpacity = 1
        comboGlow.shadowRadius = 11
        comboValue.foregroundColor = NSColor.white.cgColor
        comboValue.shadowColor = NSColor.systemCyan.cgColor
        comboValue.shadowOpacity = 0.9
        comboValue.shadowRadius = 4
        lifetimeTrack.bounds = CGRect(x: 0, y: 0, width: 78, height: 4)
        lifetimeTrack.cornerRadius = 2
        lifetimeTrack.backgroundColor = NSColor.systemCyan.withAlphaComponent(0.14).cgColor
        lifetimeTrack.borderWidth = 0
        lifetimeTrack.shadowOpacity = 0
        root.addSublayer(lifetimeTrack)
        lifetimeFill.bounds = lifetimeTrack.bounds
        lifetimeFill.anchorPoint = CGPoint(x: 0, y: 0.5)
        lifetimeFill.position = CGPoint(x: -39, y: 2)
        lifetimeFill.cornerRadius = 2
        lifetimeFill.startPoint = CGPoint(x: 0, y: 0.5)
        lifetimeFill.endPoint = CGPoint(x: 1, y: 0.5)
        lifetimeFill.shadowColor = NSColor.systemCyan.cgColor
        lifetimeFill.shadowOpacity = 0.9
        lifetimeFill.shadowRadius = 3
        lifetimeTrack.addSublayer(lifetimeFill)
        lifetimeCap.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        lifetimeCap.position = CGPoint(x: 75.5, y: 2)
        lifetimeCap.cornerRadius = 2.5
        lifetimeCap.backgroundColor = NSColor.white.cgColor
        lifetimeCap.shadowColor = NSColor.white.cgColor
        lifetimeCap.shadowOpacity = 1
        lifetimeCap.shadowRadius = 3
        lifetimeFill.addSublayer(lifetimeCap)
        setVisible(false)
        hostLayer.addSublayer(root)
    }

    func layout(in bounds: CGRect, beside hud: CGRect, centered: Bool = false) {
        root.frame = bounds
        effects.frame = bounds
        let placeLeft = hud.midX > bounds.midX
        let proposedX = centered ? hud.midX : placeLeft ? hud.minX - 58 : hud.maxX + 58
        comboAnchor = CGPoint(
            x: min(bounds.maxX - 60, max(bounds.minX + 60, proposedX)),
            y: min(bounds.maxY - 40, max(bounds.minY + 40, hud.midY))
        )
        comboGlow.position = comboAnchor
        comboValue.position = comboAnchor
        lifetimeTrack.position = CGPoint(x: comboAnchor.x, y: comboAnchor.y - 25)
    }

    func showPositioningAnchor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        comboGlow.string = "×0"
        comboGlow.foregroundColor = NSColor.systemCyan.withAlphaComponent(0.18).cgColor
        comboValue.string = "×0"
        comboValue.foregroundColor = NSColor.systemCyan.withAlphaComponent(0.72).cgColor
        lifetimeTrack.backgroundColor = NSColor.systemCyan.withAlphaComponent(0.12).cgColor
        CATransaction.commit()
        setVisible(true)
    }

    func clearCombo() {
        setVisible(false)
    }

    func update(count: Int, progress: CGFloat, pulse: Bool = false) {
        guard count > 0, progress > 0 else { setVisible(false); return }
        let palette = typingPalette(for: count)
        let label = "×\(count)"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        comboGlow.string = label
        comboGlow.foregroundColor = palette.primary.withAlphaComponent(0.34).cgColor
        comboGlow.shadowColor = palette.secondary.cgColor
        comboValue.string = label
        comboValue.foregroundColor = palette.primary.cgColor
        comboValue.shadowColor = palette.secondary.cgColor
        lifetimeTrack.backgroundColor = palette.secondary.withAlphaComponent(0.16).cgColor
        lifetimeFill.colors = [palette.secondary.cgColor, palette.primary.cgColor, NSColor.white.cgColor]
        lifetimeFill.shadowColor = palette.primary.cgColor
        lifetimeCap.backgroundColor = palette.primary.cgColor
        lifetimeCap.shadowColor = palette.secondary.cgColor
        CATransaction.commit()
        setVisible(true)
        animateLifetime(progress: progress, refill: pulse, palette: palette)
        guard pulse, !preferences.reduceMotionEnabled else { return }
        let hit = CAKeyframeAnimation(keyPath: "transform.scale")
        hit.values = count % 10 == 0 ? [1, 1.42, 0.91, 1.08, 1] : [1, 1.18, 0.96, 1]
        hit.duration = count % 10 == 0 ? 0.4 : 0.18
        comboValue.add(hit, forKey: "typing-combo-hit")
        comboGlow.add(hit, forKey: "typing-combo-glow-hit")
    }

    private func typingPalette(for count: Int) -> (primary: NSColor, secondary: NSColor) {
        switch count {
        case 40...:
            return (
                NSColor(calibratedRed: 1, green: 0.82, blue: 0.28, alpha: 1),
                NSColor(calibratedRed: 1, green: 0.28, blue: 0.58, alpha: 1)
            )
        case 20..<40:
            return (
                NSColor(calibratedRed: 1, green: 0.34, blue: 0.76, alpha: 1),
                NSColor(calibratedRed: 0.64, green: 0.32, blue: 1, alpha: 1)
            )
        case 10..<20:
            return (
                NSColor(calibratedRed: 0.72, green: 0.48, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.22, green: 0.82, blue: 1, alpha: 1)
            )
        case 5..<10:
            return (
                NSColor(calibratedRed: 0.26, green: 0.94, blue: 0.76, alpha: 1),
                NSColor(calibratedRed: 0.18, green: 0.72, blue: 1, alpha: 1)
            )
        default:
            return (
                NSColor(calibratedRed: 0.28, green: 0.86, blue: 1, alpha: 1),
                NSColor(calibratedRed: 0.30, green: 0.58, blue: 1, alpha: 1)
            )
        }
    }

    private func animateLifetime(progress: CGFloat, refill: Bool, palette: (primary: NSColor, secondary: NSColor)) {
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
        lifetimeFill.colors = [NSColor.systemOrange.cgColor, NSColor.systemRed.cgColor, NSColor.white.cgColor]
        CATransaction.commit()
        let scale = CAKeyframeAnimation(keyPath: "transform.scale.x")
        scale.values = refill ? [current, 1, 1, 0.001] : [progress, 0.001]
        scale.keyTimes = refill ? [0, 0.07, 0.12, 1] : [0, 1]
        let color = CAKeyframeAnimation(keyPath: "colors")
        color.values = [
            [palette.secondary.cgColor, palette.primary.cgColor, NSColor.white.cgColor],
            [palette.secondary.cgColor, palette.primary.cgColor, NSColor.white.cgColor],
            [palette.primary.cgColor, NSColor.systemOrange.cgColor, NSColor.white.cgColor],
            [NSColor.systemOrange.cgColor, NSColor.systemRed.cgColor, NSColor.white.cgColor]
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
              !preferences.reduceMotionEnabled else { return }
        let effect = preferences.settings.cursorEffect ?? "spark"
        let arcade = preferences.settings.preset == "arcade"
        let milestone = count == 5 || count == 10 || count == 20 || count == 40 || count == 80 || count == 120 || count == 200
        let color: NSColor = count >= 40 ? .systemYellow
            : count >= 20 ? NSColor(calibratedRed: 0.98, green: 0.30, blue: 0.72, alpha: 1)
            : count >= 10 ? NSColor(calibratedRed: 0.62, green: 0.38, blue: 1, alpha: 1)
            : .systemCyan

        if milestone && effect != "meme" && effect != "possum" && effect != "freshcat" && effect != "knifeshield" && effect != "elegant" {
            emitCursorMilestone(at: point, color: color, effect: effect, arcade: arcade)
        }
        switch effect {
        case "orbit":
            emitOrbitCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "ripple":
            emitRippleCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "prism":
            emitPrismCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "wormhole":
            emitWormholeCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "glitch":
            emitGlitchCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "tentacle":
            emitTentacleCursorEffect(at: point, color: color, arcade: arcade, milestone: milestone)
        case "meme":
            emitMemeCursorEffect(at: point, count: count, arcade: arcade, milestone: milestone)
        case "possum":
            emitPossumCursorEffect(at: point, arcade: arcade, milestone: milestone)
        case "freshcat":
            emitFreshCatCursorEffect(at: point, arcade: arcade, milestone: milestone)
        case "knifeshield":
            emitKnifeShieldDogCursorEffect(at: point, arcade: arcade, milestone: milestone)
        case "elegant":
            emitElegantPersonCursorEffect(at: point, arcade: arcade, milestone: milestone)
        default:
            emitClassicCursorEffect(at: point, count: count, color: color, neon: effect == "neon", arcade: arcade, milestone: milestone)
        }
    }

    private func emitClassicCursorEffect(at point: CGPoint, count: Int, color: NSColor, neon: Bool, arcade: Bool, milestone: Bool) {
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
        scheduleRemoval(glyph, after: glyphPulse.duration)

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
            scheduleRemoval(spark, after: group.duration)
        }
    }

    private func emitCursorMilestone(at point: CGPoint, color: NSColor, effect: String, arcade: Bool) {
        let ring = CAShapeLayer()
        ring.frame = effects.bounds
        ring.path = CGPath(ellipseIn: CGRect(x: point.x - 9, y: point.y - 9, width: 18, height: 18), transform: nil)
        ring.fillColor = NSColor.clear.cgColor
        ring.strokeColor = color.cgColor
        ring.lineWidth = arcade ? 2.4 : 1.7
        ring.lineDashPattern = effect == "neon" ? [5, 3] : effect == "orbit" ? [2, 4] : nil
        ring.shadowColor = color.cgColor
        ring.shadowOpacity = 1
        ring.shadowRadius = arcade ? 9 : 6
        effects.addSublayer(ring)
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.62
        scale.toValue = arcade ? 2.65 : 2.1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        let pulse = CAAnimationGroup()
        pulse.animations = [scale, fade]
        pulse.duration = arcade ? 0.5 : 0.42
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(pulse, forKey: "cursor-combo-milestone")
        scheduleRemoval(ring, after: pulse.duration)
    }

    private func emitOrbitCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let radius: CGFloat = milestone ? 17 : 11
        let arc = CAShapeLayer()
        arc.frame = CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)
        arc.path = CGPath(ellipseIn: arc.bounds.insetBy(dx: 1.5, dy: 1.5), transform: nil)
        arc.fillColor = NSColor.clear.cgColor
        arc.strokeColor = color.withAlphaComponent(0.76).cgColor
        arc.lineWidth = arcade ? 1.8 : 1.35
        arc.lineCap = .round
        arc.strokeStart = 0.08
        arc.strokeEnd = 0.72
        arc.shadowColor = color.cgColor
        arc.shadowOpacity = 0.8
        arc.shadowRadius = 4
        effects.addSublayer(arc)
        let rotation = CABasicAnimation(keyPath: "transform.rotation")
        rotation.fromValue = -CGFloat.pi * 0.18
        rotation.toValue = CGFloat.pi * (arcade ? 1.35 : 0.92)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 0.9, 0.72, 0]
        fade.keyTimes = [0, 0.16, 0.72, 1]
        let arcGroup = CAAnimationGroup()
        arcGroup.animations = [rotation, fade]
        arcGroup.duration = milestone ? 0.58 : 0.46
        arcGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        arc.add(arcGroup, forKey: "cursor-orbit-arc")
        scheduleRemoval(arc, after: arcGroup.duration)

        let particleCount = arcade ? 3 : 2
        for index in 0..<particleCount {
            let particle = CALayer()
            let size: CGFloat = index == 0 ? 4 : 3
            particle.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            particle.cornerRadius = size / 2
            particle.position = point
            let particleColor = index == 1 ? NSColor.white : color
            particle.backgroundColor = particleColor.cgColor
            particle.shadowColor = particleColor.cgColor
            particle.shadowOpacity = 1
            particle.shadowRadius = 4
            effects.addSublayer(particle)
            let phase = CGFloat(index) * (.pi * 2 / CGFloat(particleCount))
            let positions = (0...8).map { step -> CGPoint in
                let angle = phase + CGFloat(step) / 8 * .pi * (arcade ? 2.4 : 1.85)
                return CGPoint(
                    x: point.x + cos(angle) * radius,
                    y: point.y + sin(angle) * radius * 0.68
                )
            }
            let orbit = CAKeyframeAnimation(keyPath: "position")
            orbit.values = positions
            orbit.calculationMode = .paced
            let particleFade = CAKeyframeAnimation(keyPath: "opacity")
            particleFade.values = [0, 1, 0.86, 0]
            particleFade.keyTimes = [0, 0.14, 0.76, 1]
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.45, 1, 0.76]
            scale.keyTimes = [0, 0.28, 1]
            let group = CAAnimationGroup()
            group.animations = [orbit, particleFade, scale]
            group.duration = arcGroup.duration
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            particle.add(group, forKey: "cursor-orbit-particle")
            scheduleRemoval(particle, after: group.duration)
        }
    }

    private func emitRippleCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let core = CALayer()
        core.bounds = CGRect(x: 0, y: 0, width: 5, height: 5)
        core.position = point
        core.cornerRadius = 2.5
        core.backgroundColor = NSColor.white.cgColor
        core.shadowColor = color.cgColor
        core.shadowOpacity = 1
        core.shadowRadius = 7
        effects.addSublayer(core)
        let coreScale = CAKeyframeAnimation(keyPath: "transform.scale")
        coreScale.values = [0.35, 1.3, 0.72]
        coreScale.keyTimes = [0, 0.32, 1]
        let coreFade = CAKeyframeAnimation(keyPath: "opacity")
        coreFade.values = [0, 1, 0]
        coreFade.keyTimes = [0, 0.18, 1]
        let coreGroup = CAAnimationGroup()
        coreGroup.animations = [coreScale, coreFade]
        coreGroup.duration = 0.38
        core.add(coreGroup, forKey: "cursor-ripple-core")
        scheduleRemoval(core, after: coreGroup.duration)

        let ringCount = milestone || arcade ? 3 : 2
        for index in 0..<ringCount {
            let baseRadius = CGFloat(5 + index * 3)
            let ring = CAShapeLayer()
            ring.frame = CGRect(x: point.x - baseRadius, y: point.y - baseRadius, width: baseRadius * 2, height: baseRadius * 2)
            ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 1, dy: 1), transform: nil)
            ring.fillColor = NSColor.clear.cgColor
            ring.strokeColor = (index == 1 ? NSColor.white : color).withAlphaComponent(0.86).cgColor
            ring.lineWidth = arcade ? 1.65 : 1.25
            ring.shadowColor = color.cgColor
            ring.shadowOpacity = 0.72
            ring.shadowRadius = 4
            effects.addSublayer(ring)
            let scale = CABasicAnimation(keyPath: "transform.scale")
            scale.fromValue = 0.52
            scale.toValue = 1.75 + CGFloat(index) * 0.34
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.82, 0.58, 0]
            fade.keyTimes = [0, 0.18, 0.62, 1]
            let group = CAAnimationGroup()
            group.animations = [scale, fade]
            group.duration = 0.4 + Double(index) * 0.055
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "cursor-ripple-ring")
            scheduleRemoval(ring, after: group.duration)
        }
    }

    private func emitPrismCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let prismColors = [
            NSColor.systemCyan,
            color,
            countColorForPrism(milestone: milestone)
        ]
        let spread: CGFloat = arcade ? 1.18 : 1
        for index in 0..<3 {
            let direction = CGFloat(index - 1)
            let ray = CAShapeLayer()
            ray.frame = effects.bounds
            let path = CGMutablePath()
            path.move(to: point)
            path.addLine(to: CGPoint(x: point.x + direction * 7 * spread, y: point.y + 8))
            path.addLine(to: CGPoint(x: point.x + direction * 15 * spread, y: point.y + 18 + CGFloat(index % 2) * 3))
            ray.path = path
            ray.fillColor = NSColor.clear.cgColor
            ray.strokeColor = prismColors[index].withAlphaComponent(0.9).cgColor
            ray.lineWidth = index == 1 ? 1.8 : 1.35
            ray.lineCap = .round
            ray.lineJoin = .round
            ray.shadowColor = prismColors[index].cgColor
            ray.shadowOpacity = 0.9
            ray.shadowRadius = 5
            effects.addSublayer(ray)
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 1, 1]
            draw.keyTimes = [0, 0.42, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0.72, 0]
            fade.keyTimes = [0, 0.16, 0.66, 1]
            let group = CAAnimationGroup()
            group.animations = [draw, fade]
            group.duration = milestone ? 0.52 : 0.4
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ray.add(group, forKey: "cursor-prism-ray")
            scheduleRemoval(ray, after: group.duration)
        }

        let core = CAShapeLayer()
        core.frame = effects.bounds
        let diamond = CGMutablePath()
        diamond.move(to: CGPoint(x: point.x, y: point.y - 4))
        diamond.addLine(to: CGPoint(x: point.x + 4, y: point.y))
        diamond.addLine(to: CGPoint(x: point.x, y: point.y + 4))
        diamond.addLine(to: CGPoint(x: point.x - 4, y: point.y))
        diamond.closeSubpath()
        core.path = diamond
        core.fillColor = color.withAlphaComponent(0.42).cgColor
        core.strokeColor = NSColor.white.withAlphaComponent(0.92).cgColor
        core.lineWidth = 1
        core.shadowColor = color.cgColor
        core.shadowOpacity = 1
        core.shadowRadius = 6
        effects.addSublayer(core)
        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.38, 1.28, 0.8]
        scale.keyTimes = [0, 0.36, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [0, 1, 0]
        fade.keyTimes = [0, 0.18, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = milestone ? 0.52 : 0.4
        core.add(group, forKey: "cursor-prism-core")
        scheduleRemoval(core, after: group.duration)
    }

    private func countColorForPrism(milestone: Bool) -> NSColor {
        milestone
            ? NSColor(calibratedRed: 1, green: 0.76, blue: 0.24, alpha: 1)
            : NSColor(calibratedRed: 1, green: 0.30, blue: 0.72, alpha: 1)
    }

    private func emitWormholeCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let wormholeColors = [color, NSColor.systemCyan, NSColor.systemPink]
        let loopCount = arcade || milestone ? 3 : 2
        for index in 0..<loopCount {
            let radius = CGFloat(7 + index * 4)
            let loop = CAShapeLayer()
            loop.frame = CGRect(x: point.x - radius, y: point.y - radius * 0.62, width: radius * 2, height: radius * 1.24)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 1, y: loop.bounds.midY))
            path.addCurve(
                to: CGPoint(x: loop.bounds.maxX - 1, y: loop.bounds.midY),
                control1: CGPoint(x: loop.bounds.width * 0.25, y: -CGFloat(index + 1)),
                control2: CGPoint(x: loop.bounds.width * 0.68, y: loop.bounds.maxY + CGFloat(index + 1))
            )
            path.addCurve(
                to: CGPoint(x: 1, y: loop.bounds.midY),
                control1: CGPoint(x: loop.bounds.width * 0.74, y: -CGFloat(index)),
                control2: CGPoint(x: loop.bounds.width * 0.24, y: loop.bounds.maxY + CGFloat(index))
            )
            loop.path = path
            loop.fillColor = NSColor.clear.cgColor
            loop.strokeColor = wormholeColors[index].withAlphaComponent(0.82).cgColor
            loop.lineWidth = index == 0 ? 1.8 : 1.2
            loop.lineCap = .round
            loop.strokeStart = 0.05
            loop.strokeEnd = 0.78
            loop.shadowColor = wormholeColors[index].cgColor
            loop.shadowOpacity = 0.9
            loop.shadowRadius = 5
            effects.addSublayer(loop)
            let rotation = CABasicAnimation(keyPath: "transform.rotation")
            rotation.fromValue = CGFloat(index) * 0.34
            rotation.toValue = (index.isMultiple(of: 2) ? 1 : -1) * CGFloat.pi * (arcade ? 1.25 : 0.86)
            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.72, 1.18, 0.72]
            scale.keyTimes = [0, 0.42, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0.66, 0]
            fade.keyTimes = [0, 0.16, 0.72, 1]
            let group = CAAnimationGroup()
            group.animations = [rotation, scale, fade]
            group.duration = milestone ? 0.58 : 0.46
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            loop.add(group, forKey: "cursor-wormhole-loop")
            scheduleRemoval(loop, after: group.duration)
        }
    }

    private func emitGlitchCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let glitchColors = [NSColor.systemCyan, color, NSColor.systemPink, NSColor.white]
        let shardCount = arcade || milestone ? 6 : 4
        for index in 0..<shardCount {
            let shard = CALayer()
            let width = CGFloat(5 + (index * 7) % 10)
            shard.bounds = CGRect(x: 0, y: 0, width: width, height: index.isMultiple(of: 3) ? 2 : 1)
            shard.position = CGPoint(x: point.x + CGFloat((index % 3) - 1) * 2, y: point.y + CGFloat(index - shardCount / 2) * 3)
            let shardColor = glitchColors[index % glitchColors.count]
            shard.backgroundColor = shardColor.withAlphaComponent(0.92).cgColor
            shard.shadowColor = shardColor.cgColor
            shard.shadowOpacity = 1
            shard.shadowRadius = 4
            effects.addSublayer(shard)
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let shift = CAKeyframeAnimation(keyPath: "transform.translation.x")
            shift.values = [0, direction * 11, -direction * 5, direction * 16]
            shift.keyTimes = [0, 0.28, 0.58, 1]
            let scaleX = CAKeyframeAnimation(keyPath: "transform.scale.x")
            scaleX.values = [0.7, 1.35, 0.62, 1.1]
            scaleX.keyTimes = [0, 0.24, 0.62, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0.22, 0.86, 0]
            fade.keyTimes = [0, 0.12, 0.38, 0.62, 1]
            let group = CAAnimationGroup()
            group.animations = [shift, scaleX, fade]
            group.duration = milestone ? 0.48 : 0.34
            group.timingFunction = CAMediaTimingFunction(name: .linear)
            shard.add(group, forKey: "cursor-glitch-shard")
            scheduleRemoval(shard, after: group.duration)
        }
    }

    private func emitTentacleCursorEffect(at point: CGPoint, color: NSColor, arcade: Bool, milestone: Bool) {
        let armCount = arcade || milestone ? 4 : 3
        let armColors = [color, NSColor.systemCyan, NSColor.systemPink, NSColor.white]
        for index in 0..<armCount {
            let angle = -CGFloat.pi * 0.92 + CGFloat(index) * CGFloat.pi * 0.58
            let length: CGFloat = milestone ? 22 : 16
            let tangent = CGPoint(x: cos(angle), y: sin(angle))
            let normal = CGPoint(x: -tangent.y, y: tangent.x)
            let arm = CAShapeLayer()
            arm.frame = effects.bounds
            let path = CGMutablePath()
            path.move(to: point)
            path.addCurve(
                to: CGPoint(x: point.x + tangent.x * length, y: point.y + tangent.y * length),
                control1: CGPoint(x: point.x + tangent.x * length * 0.3 + normal.x * 6, y: point.y + tangent.y * length * 0.3 + normal.y * 6),
                control2: CGPoint(x: point.x + tangent.x * length * 0.72 - normal.x * 5, y: point.y + tangent.y * length * 0.72 - normal.y * 5)
            )
            arm.path = path
            arm.fillColor = NSColor.clear.cgColor
            arm.strokeColor = armColors[index].withAlphaComponent(0.86).cgColor
            arm.lineWidth = index == 0 ? 1.8 : 1.25
            arm.lineCap = .round
            arm.shadowColor = armColors[index].cgColor
            arm.shadowOpacity = 0.9
            arm.shadowRadius = 5
            effects.addSublayer(arm)
            let draw = CAKeyframeAnimation(keyPath: "strokeEnd")
            draw.values = [0, 1, 0.72]
            draw.keyTimes = [0, 0.48, 1]
            let retract = CAKeyframeAnimation(keyPath: "strokeStart")
            retract.values = [0, 0, 0.82]
            retract.keyTimes = [0, 0.5, 1]
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 1, 0.82, 0]
            fade.keyTimes = [0, 0.16, 0.72, 1]
            let group = CAAnimationGroup()
            group.animations = [draw, retract, fade]
            group.duration = milestone ? 0.54 : 0.43
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            arm.add(group, forKey: "cursor-tentacle-arm")
            scheduleRemoval(arm, after: group.duration)
        }
    }

    private func emitMemeCursorEffect(at point: CGPoint, count: Int, arcade: Bool, milestone: Bool) {
        activeMemeText?.removeAllAnimations()
        activeMemeText?.removeFromSuperlayer()
        activeMemeText = nil
        let words = ["典", "急", "孝", "乐", "绷", "赢"]
        let colors: [NSColor] = [
            NSColor(calibratedRed: 1, green: 0.78, blue: 0.22, alpha: 1),
            NSColor.systemRed,
            NSColor(calibratedRed: 0.74, green: 0.48, blue: 1, alpha: 1),
            NSColor.systemCyan,
            NSColor.systemPink,
            NSColor(calibratedRed: 0.42, green: 0.94, blue: 0.62, alpha: 1)
        ]
        let index = abs(count) % words.count
        let word = words[index]
        let wordColor = colors[index]
        let text = CATextLayer()
        text.bounds = CGRect(x: 0, y: 0, width: milestone ? 48 : 38, height: milestone ? 38 : 30)
        text.position = CGPoint(x: point.x + 12, y: point.y + 15)
        text.alignmentMode = .center
        text.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        text.font = NSFont.systemFont(ofSize: milestone ? 25 : 20, weight: .black)
        text.fontSize = milestone ? 25 : 20
        text.string = word
        text.foregroundColor = wordColor.cgColor
        text.shadowColor = wordColor.cgColor
        text.shadowOpacity = 1
        text.shadowRadius = arcade ? 8 : 5
        text.shadowOffset = .zero
        effects.addSublayer(text)
        activeMemeText = text

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        switch word {
        case "典": scale.values = [1.55, 0.88, 1.04, 1]
        case "急": scale.values = [0.72, 1.24, 0.94, 1]
        case "孝": scale.values = [1, 0.84, 1.08, 1]
        case "乐": scale.values = [0.5, 1.42, 0.9, 1]
        case "绷": scale.values = [0.34, 1.72, 0.76, 1]
        default: scale.values = [0.58, 1.16, 1.3, 1]
        }
        scale.keyTimes = [0, 0.28, 0.62, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 0.86, 0]
        fade.keyTimes = [0, 0.46, 0.72, 1]
        let motion: CAKeyframeAnimation
        switch word {
        case "典":
            motion = CAKeyframeAnimation(keyPath: "transform.rotation")
            motion.values = [-0.18, 0.06, -0.02, 0]
            motion.keyTimes = [0, 0.3, 0.62, 1]
        case "急":
            motion = CAKeyframeAnimation(keyPath: "transform.translation.x")
            motion.values = [0, -4, 4, -3, 3, 0]
            motion.keyTimes = [0, 0.18, 0.34, 0.5, 0.66, 1]
        case "孝":
            motion = CAKeyframeAnimation(keyPath: "transform.translation.y")
            motion.values = [0, -3, 4, 0]
            motion.keyTimes = [0, 0.3, 0.62, 1]
        case "乐":
            motion = CAKeyframeAnimation(keyPath: "transform.translation.y")
            motion.values = [0, 6, -5, 2, 0]
            motion.keyTimes = [0, 0.22, 0.44, 0.68, 1]
        case "绷":
            motion = CAKeyframeAnimation(keyPath: "transform.translation.x")
            motion.values = [0, -8, 8, 0]
            motion.keyTimes = [0, 0.34, 0.62, 1]
        default:
            motion = CAKeyframeAnimation(keyPath: "transform.translation.y")
            motion.values = [0, 0, 5, -11]
            motion.keyTimes = [0, 0.4, 0.66, 1]
        }
        let group = CAAnimationGroup()
        group.animations = [scale, fade, motion]
        group.duration = milestone ? 0.58 : arcade ? 0.5 : 0.44
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        text.add(group, forKey: "cursor-meme-word")
        scheduleRemoval(text, after: group.duration)
    }

    private func emitPossumCursorEffect(at point: CGPoint, arcade: Bool, milestone: Bool) {
        activePossumSticker?.removeAllAnimations()
        activePossumSticker?.removeFromSuperlayer()
        activePossumSticker = nil
        guard let image = memeStickerImage(named: "hands-behind-possum-cutout.png") else {
            emitMemeCursorEffect(at: point, count: 12, arcade: arcade, milestone: milestone)
            return
        }
        let sticker = CALayer()
        let stickerSize = milestone
            ? CGSize(width: 48, height: 76)
            : CGSize(width: 40, height: 64)
        sticker.bounds = CGRect(origin: .zero, size: stickerSize)
        // macOS input-method candidates normally open above the insertion point.
        // Keep the entire sticker below the input baseline, including its shadow
        // and small rotation, so it never covers the candidate window.
        sticker.position = CGPoint(
            x: point.x + 28,
            y: point.y - (milestone ? 48 : 42)
        )
        sticker.contents = image
        sticker.contentsGravity = .resize
        // The bundled PNG deliberately keeps its source pixels intact. Crop only
        // the transparent canvas at render time so the silhouette reads at cursor scale.
        sticker.contentsRect = CGRect(x: 0.168, y: 0, width: 0.561, height: 0.902)
        sticker.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        sticker.shadowColor = NSColor.black.cgColor
        sticker.shadowOpacity = 0.72
        sticker.shadowRadius = arcade ? 8 : 5
        sticker.shadowOffset = CGSize(width: 0, height: -2)
        effects.addSublayer(sticker)
        activePossumSticker = sticker

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.74, 1.08, 0.98, 1.025, 1]
        scale.keyTimes = [0, 0.24, 0.46, 0.72, 1]
        let walk = CAKeyframeAnimation(keyPath: "transform.translation.x")
        walk.values = [18, 5, 0, -2, -8]
        walk.keyTimes = [0, 0.24, 0.46, 0.74, 1]
        let inspect = CAKeyframeAnimation(keyPath: "transform.rotation")
        inspect.values = [-0.08, 0.025, -0.018, 0.018, 0]
        inspect.keyTimes = [0, 0.28, 0.52, 0.72, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 1, 0.82, 0]
        fade.keyTimes = [0, 0.45, 0.7, 0.84, 1]
        let group = CAAnimationGroup()
        group.animations = [scale, walk, inspect, fade]
        group.duration = milestone ? 0.82 : arcade ? 0.74 : 0.68
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sticker.add(group, forKey: "cursor-possum-inspect")
        scheduleRemoval(sticker, after: group.duration)
    }

    private func emitFreshCatCursorEffect(at point: CGPoint, arcade: Bool, milestone: Bool) {
        activeFreshCatSticker?.removeAllAnimations()
        activeFreshCatSticker?.removeFromSuperlayer()
        activeFreshCatSticker = nil
        guard let image = memeStickerImage(named: "fresh-cat-cutout.png") else {
            emitMemeCursorEffect(at: point, count: 15, arcade: arcade, milestone: milestone)
            return
        }

        let sticker = CALayer()
        let size: CGFloat = milestone ? 62 : 54
        sticker.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        // Match the possum's IME-safe placement: the complete face remains below
        // the insertion baseline, leaving macOS candidate windows unobstructed.
        sticker.position = CGPoint(
            x: point.x + 36,
            y: point.y - (milestone ? 44 : 39)
        )
        sticker.contents = image
        sticker.contentsGravity = .resizeAspect
        sticker.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        sticker.shadowColor = NSColor.black.cgColor
        sticker.shadowOpacity = 0.58
        sticker.shadowRadius = arcade ? 7 : 4
        sticker.shadowOffset = CGSize(width: 0, height: -2)
        effects.addSublayer(sticker)
        activeFreshCatSticker = sticker

        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [0.82, 1.12, 1.02, 0.98, 1]
        press.keyTimes = [0, 0.25, 0.48, 0.74, 1]
        let approach = CAKeyframeAnimation(keyPath: "transform.translation.x")
        approach.values = [18, 4, 0, -2, -7]
        approach.keyTimes = [0, 0.25, 0.48, 0.75, 1]
        let unimpressedTilt = CAKeyframeAnimation(keyPath: "transform.rotation")
        unimpressedTilt.values = [0.075, -0.025, 0.018, -0.012, 0]
        unimpressedTilt.keyTimes = [0, 0.30, 0.53, 0.76, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 1, 0.80, 0]
        fade.keyTimes = [0, 0.48, 0.72, 0.86, 1]
        let group = CAAnimationGroup()
        group.animations = [press, approach, unimpressedTilt, fade]
        group.duration = milestone ? 0.82 : arcade ? 0.72 : 0.66
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        sticker.add(group, forKey: "cursor-fresh-cat-press")
        scheduleRemoval(sticker, after: group.duration)
    }

    private func emitKnifeShieldDogCursorEffect(at point: CGPoint, arcade: Bool, milestone: Bool) {
        activeKnifeShieldDog?.removeAllAnimations()
        activeKnifeShieldDog?.removeFromSuperlayer()
        activeKnifeShieldDog = nil
        guard let image = memeStickerImage(named: "knife-shield-dog-cutout.png") else {
            emitMemeCursorEffect(at: point, count: 16, arcade: arcade, milestone: milestone)
            return
        }

        let dog = CALayer()
        let dogSize = milestone
            ? CGSize(width: 70, height: 49)
            : CGSize(width: 62, height: 43)
        dog.bounds = CGRect(origin: .zero, size: dogSize)
        dog.position = CGPoint(
            x: point.x + 39,
            y: point.y - (milestone ? 38 : 34)
        )
        dog.contents = image
        dog.contentsGravity = .resize
        dog.contentsRect = CGRect(x: 0.156, y: 0.238, width: 0.715, height: 0.498)
        dog.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        dog.shadowColor = NSColor.black.cgColor
        dog.shadowOpacity = 0.58
        dog.shadowRadius = arcade ? 6 : 4
        dog.shadowOffset = CGSize(width: 0, height: -2)
        effects.addSublayer(dog)
        activeKnifeShieldDog = dog
        let duration = milestone ? 0.86 : arcade ? 0.76 : 0.70

        let crouch = CAKeyframeAnimation(keyPath: "transform.scale")
        crouch.values = [0.76, 1.08, 0.96, 1.025, 1]
        crouch.keyTimes = [0, 0.25, 0.48, 0.72, 1]
        let slide = CAKeyframeAnimation(keyPath: "transform.translation.x")
        slide.values = [18, 5, 0, -2, -7]
        slide.keyTimes = [0, 0.25, 0.50, 0.74, 1]
        let wobble = CAKeyframeAnimation(keyPath: "transform.rotation")
        wobble.values = [-0.055, 0.038, -0.026, 0.014, 0]
        wobble.keyTimes = [0, 0.28, 0.50, 0.73, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 1, 0.82, 0]
        fade.keyTimes = [0, 0.48, 0.72, 0.86, 1]
        let group = CAAnimationGroup()
        group.animations = [crouch, slide, wobble, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        dog.add(group, forKey: "cursor-knife-shield-dog-waddle")
        scheduleRemoval(dog, after: duration)
    }

    private func emitElegantPersonCursorEffect(at point: CGPoint, arcade: Bool, milestone: Bool) {
        activeElegantPerson?.removeAllAnimations()
        activeElegantPerson?.removeFromSuperlayer()
        activeElegantPerson = nil
        guard let image = memeStickerImage(named: "elegant-person-cutout.png") else {
            emitMemeCursorEffect(at: point, count: 17, arcade: arcade, milestone: milestone)
            return
        }

        let person = CALayer()
        let personSize = milestone
            ? CGSize(width: 58, height: 70)
            : CGSize(width: 52, height: 63)
        person.bounds = CGRect(origin: .zero, size: personSize)
        person.position = CGPoint(
            x: point.x + 34,
            y: point.y - (milestone ? 48 : 44)
        )
        person.contents = image
        person.contentsGravity = .resize
        person.contentsRect = CGRect(x: 0.162, y: 0.080, width: 0.688, height: 0.824)
        person.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        person.shadowColor = NSColor.black.cgColor
        person.shadowOpacity = 0.62
        person.shadowRadius = arcade ? 7 : 4
        person.shadowOffset = CGSize(width: 0, height: -2)
        effects.addSublayer(person)
        activeElegantPerson = person

        let arrive = CAKeyframeAnimation(keyPath: "transform.translation.x")
        arrive.values = [17, 4, 0, -2, -6]
        arrive.keyTimes = [0, 0.24, 0.48, 0.74, 1]
        let bow = CAKeyframeAnimation(keyPath: "transform.scale.y")
        bow.values = [0.82, 1.06, 0.96, 1.025, 1]
        bow.keyTimes = [0, 0.24, 0.48, 0.72, 1]
        let composedTilt = CAKeyframeAnimation(keyPath: "transform.rotation")
        composedTilt.values = [0.045, -0.024, 0.015, -0.008, 0]
        composedTilt.keyTimes = [0, 0.28, 0.50, 0.74, 1]
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = [1, 1, 1, 0.82, 0]
        fade.keyTimes = [0, 0.48, 0.72, 0.86, 1]
        let group = CAAnimationGroup()
        group.animations = [arrive, bow, composedTilt, fade]
        group.duration = milestone ? 0.84 : arcade ? 0.74 : 0.68
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        person.add(group, forKey: "cursor-elegant-person-bow")
        scheduleRemoval(person, after: group.duration)
    }

    private func memeStickerImage(named name: String) -> NSImage? {
        if let cached = memeStickerImages[name] { return cached }
        guard let url = preferences.assetRootURL?
            .appendingPathComponent("meme-stickers", isDirectory: true)
            .appendingPathComponent(name),
              let image = NSImage(contentsOf: url) else { return nil }
        memeStickerImages[name] = image
        return image
    }

    private func scheduleRemoval(_ layer: CALayer, after duration: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.03) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }

    func inject(to target: CGPoint, count: Int) {
        guard count > 0 else { return }
        let source = comboAnchor
        let color = typingPalette(for: count).primary
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
    private var state = PowerState(sessionId: nil, sessionSource: nil, phase: "observe", status: "ready", momentum: 0, bestMomentum: 0, energyUpdatedAt: nil, combo: 0, bestCombo: 0, comboStatus: "idle", comboHoldUntil: nil, comboExpiresAt: nil, comboBrokenAt: nil, comboRelinkedAt: nil, verificationReward: nil, confidence: 0, riskLevel: "low", currentActivity: "Waiting for Codex activity", completion: nil, turnStoppedAt: nil, lastActivityAt: nil, lastFailureAt: nil, evidence: [], addedLines: 0, removedLines: 0, verifications: 0, mixedConversationCount: nil, mixedLastCompletion: nil)
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
    private var reducedMotion: Bool { preferences.reduceMotionEnabled }
    private var arcadeMode: Bool { preferences.settings.preset == "arcade" }
    private var classicMode: Bool { preferences.settings.preset == "classic" }
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
            typingRenderer.layout(in: bounds, beside: currentHudRect(), centered: classicMode)
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
        typingRenderer?.layout(in: bounds, beside: currentHudRect(), centered: classicMode)
    }

    private func refreshCompositor(event: PowerEvent? = nil, now: Date = Date()) {
        guard usesCompositorRenderer, orbRenderer != nil else { return }
        let presentation = presentationSnapshot(now: now)
        let hudRect = currentHudRect(now: now)
        orbRenderer.layout(in: hudRect)
        if classicMode {
            orbRenderer.setVisible(false, animated: false)
        } else {
            orbRenderer.setConnected(streamConnected == true)
            orbRenderer.apply(state: state, presentation: presentation, label: localizedOrbActivity(presentation), event: event)
            orbRenderer.setVisible(shouldShowHUD(now: now))
        }
        let typingProgress = typingComboProgress(now: now)
        typingRenderer.layout(in: bounds, beside: hudRect, centered: classicMode)
        if classicMode && positioning && typingProgress <= 0 {
            typingRenderer.showPositioningAnchor()
        } else {
            typingRenderer.update(count: typingProgress > 0 ? typingComboCount : 0, progress: typingProgress)
        }
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
        guard shouldShowHUD(now: Date()) else { return false }
        let local = convert(windowPoint, from: nil)
        return currentHudRect().insetBy(dx: -8, dy: -14).contains(local)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rect = currentHudRect()
        guard rect.insetBy(dx: -8, dy: -14).contains(point) else { return }
        if !positioning { beginPositioning() }
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
        if classicMode {
            typingRenderer.clearCombo()
        } else {
            typingRenderer.inject(to: reactorCenter(), count: count)
            orbRenderer.playTypingInjection(count: count)
        }
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
        case "driving":
            shockwave(color: .systemPurple, power: arcadeMode ? 1.18 : 0.68)
            charge(color: .systemPurple, count: arcadeMode ? 92 : 44)
            if arcadeMode {
                scheduleEffect(after: 0.16, generation: generation) { view in
                    view.shockwave(color: .systemCyan, power: 0.82)
                }
            }
        case "critical":
            shockwave(color: .systemYellow, power: arcadeMode ? 1.72 : 0.92)
            burst(color: .systemYellow, count: arcadeMode ? 132 : 58, power: arcadeMode ? 1.18 : 0.78)
            shake = max(shake, arcadeMode ? 5.5 : 2.2)
            scheduleEffect(after: 0.18, generation: generation) { view in
                view.shockwave(color: .systemCyan, power: view.arcadeMode ? 1.28 : 0.62)
            }
        case "peak":
            shockwave(color: .systemYellow, power: arcadeMode ? 1.92 : 1.04)
            burst(color: .white, count: arcadeMode ? 148 : 68, power: arcadeMode ? 1.28 : 0.86)
            shake = max(shake, arcadeMode ? 6.2 : 2.6)
            scheduleEffect(after: 0.2, generation: generation) { view in
                view.shockwave(color: .systemYellow, power: view.arcadeMode ? 1.44 : 0.72)
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
        if let completion = event.mixCompletion {
            switch completion {
            case "verified": return preferences.text("ONE CONVERSATION COMPLETE · VERIFIED", "一个对话完成 · 已验证")
            case "unverified": return preferences.text("ONE CONVERSATION COMPLETE · CHECK", "一个对话完成 · 待验证")
            case "cancelled": return preferences.text("ONE CONVERSATION COMPLETE · CANCELLED", "一个对话完成 · 已取消")
            default: return preferences.text("ONE CONVERSATION COMPLETE · NO CHANGE", "一个对话完成 · 无修改")
            }
        }
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
        if let completion = state.mixedLastCompletion, (state.mixedConversationCount ?? 0) > 0 {
            switch completion {
            case "verified": return preferences.text("1 DONE/OK", "一项已验证")
            case "unverified": return preferences.text("1 DONE/CHECK", "一项待验证")
            case "cancelled": return preferences.text("1 DONE/CANCEL", "一项已取消")
            default: return preferences.text("1 DONE/NO CHANGE", "一项无修改")
            }
        }
        if snapshot.idle || snapshot.phase == "idle" { return preferences.text("IDLE", "待机") }
        if state.status == "needs-attention" || snapshot.phase == "wait" { return preferences.text("APPROVAL", "等待授权") }
        if state.status == "failed" || snapshot.phase == "recover" { return preferences.text("RECOVER", "修复中") }
        if state.completion == "verified" { return preferences.text("DONE/OK", "完成/已验证") }
        if state.completion == "unverified" { return preferences.text("DONE/CHECK", "完成/待验证") }
        if state.completion == "cancelled" { return preferences.text("DONE/CANCEL", "完成/已取消") }
        if state.completion == "no-change" { return preferences.text("DONE/NO CHANGE", "完成/无修改") }
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
        let settledAt = idleAt.addingTimeInterval(45)
        guard now >= idleAt else { return (phase, status, momentum, false, false, false, settledAt) }
        let progress = min(1, max(0, now.timeIntervalSince(idleAt) / 45))
        let returnedMomentum = Int((Double(momentum) * (1 - progress)).rounded())
        let settled = returnedMomentum <= 0 || progress >= 1
        return ("idle", "ready", returnedMomentum, true, settled, !settled, settledAt)
    }

    private func shouldShowHUD(now: Date) -> Bool {
        guard preferences.settings.enabled else { return false }
        if classicMode { return positioning || typingComboProgress(now: now) > 0 }
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
            && (hasEffects || positioning || comboIsDecaying || hudIsFading)
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
        let ranges: [(Int, Int)] = [(0, 0), (1, 199), (200, 449), (450, 699), (700, 899), (900, 999)]
        let rank = energyRank(energyLevel(momentum).name)
        let stageRange = ranges[rank]
        let progress = stageRange.1 > stageRange.0
            ? CGFloat(momentum - stageRange.0) / CGFloat(stageRange.1 - stageRange.0)
            : momentum > 0 ? 1 : 0
        let energy = energyLevel(momentum)
        let energyPulse = reducedMotion ? CGFloat(1) : 0.88 + 0.12 * sin(shakePhase * energy.rhythm)
        let tierMarks = energy.name == "charging" ? 4 : energy.name == "driving" ? 6 : energy.name == "critical" ? 9 : energy.name == "peak" ? 12 : 0
        if tierMarks > 0 {
            let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
            let markers = NSBezierPath()
            for index in 0..<tierMarks {
                let angle = CGFloat(index) / CGFloat(tierMarks) * .pi * 2 - .pi / 2
                let maximumEnergy = energy.name == "critical" || energy.name == "peak"
                let innerRadius: CGFloat = maximumEnergy ? 36.5 : 37.5
                let outerRadius: CGFloat = maximumEnergy ? 41 : 40
                markers.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
                markers.line(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            }
            markers.lineWidth = energy.name == "peak" ? 2 : energy.name == "critical" ? 1.65 : 1
            markers.lineCapStyle = .round
            phaseColor.withAlphaComponent((energy.name == "peak" ? 0.92 : energy.name == "critical" ? 0.76 : 0.48) * energyPulse).setStroke()
            markers.stroke()
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 31, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = energy.lineWidth
        arc.lineCapStyle = .round
        phaseColor.withAlphaComponent(energyPulse).setStroke()
        arc.stroke()

        if ["critical", "peak"].contains(energy.name) {
            let reserve = NSBezierPath()
            reserve.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 36.5, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
            reserve.lineWidth = energy.name == "peak" ? 1.8 : 1.25
            reserve.lineCapStyle = .round
            phaseColor.withAlphaComponent((energy.name == "peak" ? 0.72 : 0.48) * energyPulse).setStroke()
            reserve.stroke()
        }

        if ["critical", "peak"].contains(energy.name) {
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
            drawCompleteClosure(around: origin)
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
        for (index, radius) in [CGFloat(31), 35.5, 40].enumerated() {
            let reward = NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            reward.lineWidth = index == 2 ? 1.8 : 1.25
            NSColor.systemGreen.withAlphaComponent(0.34 + CGFloat(index) * 0.2).setStroke()
            reward.stroke()
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

    private func drawCompleteClosure(around origin: CGPoint) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let closure = NSBezierPath(ovalIn: CGRect(x: center.x - 41, y: center.y - 41, width: 82, height: 82))
        closure.lineWidth = arcadeMode ? 2.6 : 2
        NSColor(calibratedRed: 0.76, green: 0.96, blue: 1, alpha: 0.72).setStroke()
        closure.stroke()
    }

    private func drawUnverifiedSignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let ring = NSBezierPath()
        ring.appendArc(withCenter: center, radius: 37, startAngle: 34, endAngle: 326)
        ring.setLineDash([9, 4], count: 2, phase: 0)
        ring.lineWidth = 2
        color.withAlphaComponent(0.72).setStroke()
        ring.stroke()

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
        for angles in [(12.0, 166.0), (194.0, 348.0)] {
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
        let quietRing = NSBezierPath(ovalIn: CGRect(x: center.x - 36 + settle, y: center.y - 36 + settle, width: 72 - settle * 2, height: 72 - settle * 2))
        quietRing.lineWidth = 1.35
        quietRing.stroke()

        color.withAlphaComponent(0.74).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 2.5, y: center.y - 2.5, width: 5, height: 5)).fill()
        color.withAlphaComponent(0.82).setStroke()
        NSBezierPath(ovalIn: CGRect(x: origin.x + 70, y: origin.y + 10, width: 4, height: 4)).fill()
    }

    private func energyLevel(_ momentum: Int) -> (name: String, lineWidth: CGFloat, rhythm: CGFloat) {
        if momentum <= 0 { return ("idle", 2.0, 0.02) }
        if momentum < 200 { return ("awakening", 2.2, 0.032) }
        if momentum < 450 { return ("charging", 2.7, 0.05) }
        if momentum < 700 { return ("driving", 3.3, 0.078) }
        if momentum < 900 { return ("critical", 4.2, 0.14) }
        return ("peak", 5.2, 0.2)
    }

    private func energyRank(_ level: String) -> Int {
        switch level {
        case "awakening": return 1
        case "charging": return 2
        case "driving": return 3
        case "critical": return 4
        case "peak": return 5
        default: return 0
        }
    }

    private func localizedEnergyLevel(_ level: String) -> String {
        switch level {
        case "awakening": return preferences.text("WAKE", "唤醒")
        case "charging": return preferences.text("CHARGE", "聚能")
        case "driving": return preferences.text("DRIVE", "推进")
        case "critical": return preferences.text("CRITICAL", "临界")
        case "peak": return preferences.text("PEAK", "峰值")
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
        reconnectAttempt = reconnectAttemptAfterConnection(
            current: reconnectAttempt,
            connectedDuration: connectedAt.map { Date().timeIntervalSince($0) }
        )
        connectedAt = nil
        self.task = nil
        self.session = nil
        session.finishTasksAndInvalidate()
        let delay = reconnectDelay(for: reconnectAttempt)
        reconnectAttempt = nextReconnectAttempt(after: reconnectAttempt)
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
        // Keep only the visible HUD hit target interactive. The rest of the
        // transparent panel remains click-through, while the orb can be dragged
        // directly without first enabling a menu-based positioning mode.
        installMouseMonitors()
        updateMouseCapture()
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
        updateMouseCapture()
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
            title: preferences.text("Display mode", "显示模式"),
            choices: [
                ("focus", "Focus"),
                ("arcade", "Arcade"),
                ("classic", preferences.text("Classic Power Mode · cursor + typing Combo", "经典 Power Mode · 光标特效 + 输入连击"))
            ],
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
        menu.addItem(submenu(
            title: preferences.text("Energy gain", "能量获取"),
            choices: [
                ("0.3", preferences.text("Leisurely · 0.30×", "悠闲 · 0.30×")),
                ("0.4", preferences.text("Very slow · 0.40×", "极慢 · 0.40×")),
                ("0.5", preferences.text("Slow · 0.50×", "缓慢 · 0.50×")),
                ("0.6", preferences.text("Steady · 0.60×", "偏慢 · 0.60×")),
                ("0.72", preferences.text("Balanced · 0.72×", "平衡 · 0.72×")),
                ("0.85", preferences.text("Brisk · 0.85×", "稍快 · 0.85×")),
                ("1.0", preferences.text("Standard · 1.00×", "标准 · 1.00×")),
                ("1.15", preferences.text("Fast · 1.15×", "快速 · 1.15×")),
                ("1.3", preferences.text("Powerful · 1.30×", "强劲 · 1.30×")),
                ("1.5", preferences.text("Turbo · 1.50×", "极速 · 1.50×"))
            ],
            selected: String(preferences.settings.energyGainMultiplier ?? 0.72),
            action: #selector(selectEnergyGainMultiplier),
            numericSelected: preferences.settings.energyGainMultiplier ?? 0.72
        ))
        let combo = NSMenuItem(title: preferences.text("Show Combo", "显示 Combo"), action: #selector(toggleCombo), keyEquivalent: "")
        combo.target = self
        combo.state = (preferences.settings.showCombo ?? true) ? .on : .off
        combo.isEnabled = preferences.settings.preset != "classic"
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
                ("neon", preferences.text("Neon burst", "霓虹爆发")),
                ("orbit", preferences.text("Orbit", "轨道环绕")),
                ("ripple", preferences.text("Ripple", "能量涟漪")),
                ("prism", preferences.text("Prism", "棱镜折射")),
                ("wormhole", preferences.text("Liquid wormhole", "液态虫洞")),
                ("glitch", preferences.text("Glitch slices", "故障切片")),
                ("tentacle", preferences.text("Soft tentacles", "软体触手")),
                ("meme", preferences.text("Chinese meme words", "抽象文字")),
                ("possum", preferences.text("Hands-behind possum", "背手负鼠")),
                ("freshcat", preferences.text("Fresh cat", "新鲜猫")),
                ("knifeshield", preferences.text("Knife-shield dog", "刀盾狗")),
                ("elegant", preferences.text("Elegant person", "高雅人士"))
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
    @objc private func selectEnergyGainMultiplier(_ sender: NSMenuItem) {
        if let value = sender.representedObject as? String, let multiplier = Double(value) {
            preferences?.setEnergyGainMultiplier(multiplier)
        }
    }
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
            panel.ignoresMouseEvents = false
            updateMouseCapture()
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
        guard let panel = window, let view = panel.contentView as? PowerModeView else { return }
        let windowPoint = panel.convertPoint(fromScreen: NSEvent.mouseLocation)
        panel.ignoresMouseEvents = !view.hudContains(windowPoint: windowPoint)
    }
}

private struct LayerTreeMetrics: Codable {
    let layers: Int
    let animations: Int
}

private func layerTreeMetrics(_ root: CALayer) -> LayerTreeMetrics {
    let descendants = root.sublayers ?? []
    return descendants.reduce(
        LayerTreeMetrics(layers: 1, animations: root.animationKeys()?.count ?? 0)
    ) { total, layer in
        let child = layerTreeMetrics(layer)
        return LayerTreeMetrics(
            layers: total.layers + child.layers,
            animations: total.animations + child.animations
        )
    }
}

@MainActor
private func runLayerBudgetSelfTest() {
    func state(phase: String, momentum: Int) -> PowerState {
        let json = "{\"phase\":\"\(phase)\",\"status\":\"working\",\"momentum\":\(momentum),\"bestMomentum\":999,\"currentActivity\":\"Layer budget\",\"sessionId\":\"qa\"}"
        return try! JSONDecoder().decode(PowerState.self, from: Data(json.utf8))
    }
    func sample(preset: String, reducedMotion: Bool) -> LayerTreeMetrics {
        let preferences = PowerModePreferences(environment: [
            "CODEX_POWER_MODE_SYSTEM_REDUCE_MOTION_OVERRIDE": "0"
        ])
        preferences.setPreset(preset)
        if reducedMotion { preferences.toggleReducedMotion() }
        let host = CALayer()
        host.frame = CGRect(x: 0, y: 0, width: 420, height: 240)
        let orb = OrbLayerRenderer(hostLayer: host, preferences: preferences)
        orb.layout(in: CGRect(x: 164, y: 74, width: 92, height: 92))
        orb.apply(
            state: state(phase: "observe", momentum: 580),
            presentation: (phase: "observe", status: "working", momentum: 580, idle: false, settled: false, returning: false, settledAt: nil),
            label: "OBSERVE"
        )
        orb.apply(
            state: state(phase: "act", momentum: 999),
            presentation: (phase: "act", status: "working", momentum: 999, idle: false, settled: false, returning: false, settledAt: nil),
            label: "ACT"
        )
        let typing = TypingFeedbackRenderer(hostLayer: host, preferences: preferences)
        typing.layout(in: host.bounds, beside: CGRect(x: 164, y: 74, width: 92, height: 92))
        typing.update(count: 48, progress: 1, pulse: true)
        typing.emitCursorEffect(at: CGPoint(x: 86, y: 124), count: 40)
        typing.inject(to: CGPoint(x: 210, y: 120), count: 48)
        return layerTreeMetrics(host)
    }

    let focus = sample(preset: "focus", reducedMotion: false)
    let arcade = sample(preset: "arcade", reducedMotion: false)
    let reduced = sample(preset: "focus", reducedMotion: true)
    let budgets = LayerTreeMetrics(layers: 96, animations: 88)
    let report: [String: Any] = [
        "schemaVersion": 1,
        "budget": ["layers": budgets.layers, "animations": budgets.animations],
        "focus": ["layers": focus.layers, "animations": focus.animations],
        "arcade": ["layers": arcade.layers, "animations": arcade.animations],
        "reduceMotion": ["layers": reduced.layers, "animations": reduced.animations]
    ]
    let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    fputs(String(data: data, encoding: .utf8)! + "\n", stdout)
    fflush(stdout)
    for metrics in [focus, arcade, reduced] {
        precondition(metrics.layers <= budgets.layers, "Peak native layer budget exceeded")
        precondition(metrics.animations <= budgets.animations, "Peak native animation budget exceeded")
    }
    precondition(reduced.layers < focus.layers, "Reduce Motion must allocate fewer transient layers")
    precondition(reduced.animations < focus.animations, "Reduce Motion must run fewer animations")
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
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_RECONNECT_SELF_TEST"] == "1" {
            runReconnectPolicySelfTest()
            return
        }
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_SETTINGS_SELF_TEST"] == "1" {
            runSettingsPersistenceSelfTest(environment: ProcessInfo.processInfo.environment)
            return
        }
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_LAYER_BUDGET_SELF_TEST"] == "1" {
            runLayerBudgetSelfTest()
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

import AppKit
import Foundation

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
    fputs("HUD placement, inactive behavior, and auto-hide self-test passed\n", stdout)
}

private struct PowerState: Decodable {
    let sessionId: String?
    let sessionSource: String?
    let phase: String?
    let status: String?
    let momentum: Int?
    let bestMomentum: Int?
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
}

private struct PowerEvent: Decodable {
    let type: String
    let timestamp: String?
    let preview: Bool?
    let sessionSource: String?
    let addedLines: Int?
    let removedLines: Int?
    let addedChars: Int?
    let removedChars: Int?
    let category: String?
    let success: Bool?
    let phase: String?
    let toolGroup: String?
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
    func setActivitySource(_ value: String) { mutate { $0.activitySource = value == "global" ? "global" : "focused" } }
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
private final class PowerModeView: NSView {
    private let preferences: PowerModePreferences
    private var particles: [Particle] = []
    private var shockwaves: [Shockwave] = []
    private var scanBeams: [ScanBeam] = []
    private var timer: Timer?
    private var timerInterval: TimeInterval = 0
    private var state = PowerState(sessionId: nil, sessionSource: nil, phase: "observe", status: "ready", momentum: 0, bestMomentum: 0, combo: 0, bestCombo: 0, comboStatus: "idle", comboHoldUntil: nil, comboExpiresAt: nil, comboBrokenAt: nil, comboRelinkedAt: nil, verificationReward: nil, confidence: 0, riskLevel: "low", currentActivity: "Waiting for Codex activity", completion: nil, turnStoppedAt: nil, lastActivityAt: nil, lastFailureAt: nil, evidence: [], addedLines: 0, removedLines: 0, verifications: 0)
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
    private var effectGeneration = 0
    private var positioning = false
    private var positioningHint = ""
    private var dragOffset: CGPoint?
    private var dragPosition: CGPoint?
    private let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    var onPositioningFinished: (() -> Void)?
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
        scheduleTick(highFrequency: false)
    }

    private func scheduleTick(highFrequency: Bool, dormant: Bool = false) {
        let interval: TimeInterval = highFrequency ? 1.0 / 60.0 : dormant ? 1.0 : 0.25
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
        scheduleTick(highFrequency: !reducedMotion)
        needsDisplay = true
    }

    func historySummary() -> String {
        let record = state.verificationReward == "record" ? preferences.text("★ NEW · ", "★ 新纪录 · ") : ""
        return record + "\(preferences.text("BEST ENERGY", "最高能量")) \(state.bestMomentum ?? 0)  ·  \(preferences.text("BEST COMBO", "最高连击")) \(state.bestCombo ?? 0)×"
    }

    func activitySourceSummary() -> String {
        let source = preferences.settings.activitySource == "global"
            ? preferences.text("Follow all Codex activity", "跟随全部 Codex")
            : preferences.text("Keep current conversation", "保持当前对话")
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
        needsDisplay = true
    }

    func cancelPositioning() {
        positioning = false
        positioningHint = ""
        dragOffset = nil
        dragPosition = nil
        hudExpandedUntil = Date().addingTimeInterval(1.2)
        needsDisplay = true
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
        needsDisplay = true
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
        scheduleTick(highFrequency: !reducedMotion)
        needsDisplay = true
    }

    func handle(_ event: PowerEvent) {
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
            needsDisplay = true
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
            needsDisplay = true
            return
        }

        if switchedSession {
            shockwave(color: .systemCyan, power: 0.78)
            charge(color: .systemCyan, count: arcadeMode ? 54 : 30)
            scheduleEffect(after: 0.18, generation: generation) { view in
                view.shockwave(color: .systemPurple, power: 0.62)
            }
            needsDisplay = true
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
        needsDisplay = true
    }

    private func playEnergyUpgrade(_ level: String, generation: Int) {
        switch level {
        case "charging":
            shockwave(color: .systemCyan, power: arcadeMode ? 0.42 : 0.24)
        case "flow":
            charge(color: .systemCyan, count: arcadeMode ? 58 : 28)
            shockwave(color: .systemCyan, power: arcadeMode ? 0.72 : 0.42)
        case "surge":
            shockwave(color: .systemPurple, power: arcadeMode ? 1.18 : 0.68)
            charge(color: .systemPurple, count: arcadeMode ? 92 : 44)
            if arcadeMode {
                scheduleEffect(after: 0.16, generation: generation) { view in
                    view.shockwave(color: .systemCyan, power: 0.82)
                }
            }
        case "overdrive":
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

    private func hudBaseSize(expanded: Bool? = nil) -> CGSize {
        let isExpanded = expanded ?? (positioning || preferences.settings.idleBehavior == "always" || Date() < hudExpandedUntil)
        return isExpanded ? CGSize(width: 322, height: 82) : CGSize(width: 82, height: 82)
    }

    private func currentHudRect(now: Date = Date()) -> CGRect {
        let expanded = positioning || preferences.settings.idleBehavior == "always" || now < hudExpandedUntil
        let baseSize = hudBaseSize(expanded: expanded)
        let scale = effectiveHudScale(for: baseSize)
        let size = CGSize(width: baseSize.width * scale, height: baseSize.height * scale)
        return CGRect(origin: hudOrigin(size: size), size: size)
    }

    private func presentationSnapshot(now: Date = Date()) -> (phase: String, status: String, momentum: Int, idle: Bool, settled: Bool, returning: Bool, settledAt: Date?) {
        let phase = state.phase ?? "observe"
        let status = state.status ?? "ready"
        let momentum = min(100, max(0, state.momentum ?? 0))
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
        return CGPoint(x: origin.x + 41 * scale, y: origin.y + 41 * scale)
    }

    private func codingOrigin() -> CGPoint {
        CGPoint(
            x: bounds.width * CGFloat.random(in: 0.28...0.76),
            y: bounds.height * CGFloat.random(in: 0.24...0.72)
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
        needsDisplay = true
    }

    private func scan(color: NSColor, echo: Bool = true, generation: Int) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        let life: CGFloat = 58
        scanBeams.append(ScanBeam(origin: origin, length: -min(bounds.width * 0.72, origin.x - 48), life: life, maxLife: life, color: color))
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
        let hudIsExpanded = positioning || preferences.settings.idleBehavior == "always" || now < hudExpandedUntil
        if hudIsExpanded != hudWasExpanded {
            hudWasExpanded = hudIsExpanded
            needsDisplay = true
        }
        let comboTimelineEnd = (comboBrokenAt ?? comboExpiresAt ?? .distantPast).addingTimeInterval(3.2)
        let comboIsAnimating = showsCombo && now < comboTimelineEnd
        if comboIsAnimating != comboWasAnimating {
            comboWasAnimating = comboIsAnimating
            needsDisplay = true
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
            needsDisplay = true
        }
        let hasEffects = !particles.isEmpty || !shockwaves.isEmpty || !scanBeams.isEmpty || flashAlpha > 0 || dangerAlpha > 0 || shake > 0
        let comboIsDecaying = showsCombo && (comboHoldUntil.map { now >= $0 } ?? true) && now < (comboExpiresAt ?? .distantPast)
        let presentation = presentationSnapshot(now: now)
        let targetAlpha: CGFloat = shouldShowHUD(now: now) ? 1 : 0
        let previousAlpha = hudAlpha
        let fadeStep: CGFloat = reducedMotion ? 1 : 0.12
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
            needsDisplay = true
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
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)

        context.setBlendMode(.screen)
        for beam in scanBeams {
            let progress = 1 - beam.life / beam.maxLife
            let head = beam.origin.x + beam.length * progress
            let alpha = sin(progress * .pi) * 0.7
            context.setStrokeColor(beam.color.withAlphaComponent(alpha).cgColor)
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
        if hudAlpha > 0.001 { drawHUD() }
    }

    private func drawHUD() {
        let now = Date()
        let presentation = presentationSnapshot(now: now)
        let expanded = positioning || preferences.settings.idleBehavior == "always" || now < hudExpandedUntil
        let baseSize = hudBaseSize(expanded: expanded)
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
        let phaseLabel = localizedPhase(phase)
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
        let progress = CGFloat(momentum) / 100
        let energy = energyLevel(momentum)
        let energyPulse = reducedMotion ? CGFloat(1) : 0.88 + 0.12 * sin(shakePhase * energy.rhythm)
        let tierMarks = energy.name == "flow" ? 4 : energy.name == "surge" ? 8 : energy.name == "overdrive" ? 12 : 0
        if tierMarks > 0 {
            let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
            let markers = NSBezierPath()
            for index in 0..<tierMarks {
                let angle = CGFloat(index) / CGFloat(tierMarks) * .pi * 2 - .pi / 2
                let innerRadius: CGFloat = energy.name == "overdrive" ? 36.5 : 37.5
                let outerRadius: CGFloat = energy.name == "overdrive" ? 41 : 40
                markers.move(to: CGPoint(x: center.x + cos(angle) * innerRadius, y: center.y + sin(angle) * innerRadius))
                markers.line(to: CGPoint(x: center.x + cos(angle) * outerRadius, y: center.y + sin(angle) * outerRadius))
            }
            markers.lineWidth = energy.name == "overdrive" ? 1.8 : energy.name == "surge" ? 1.35 : 1
            markers.lineCapStyle = .round
            phaseColor.withAlphaComponent((energy.name == "overdrive" ? 0.88 : energy.name == "surge" ? 0.68 : 0.48) * energyPulse).setStroke()
            markers.stroke()
        }
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 31, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = energy.lineWidth
        arc.lineCapStyle = .round
        phaseColor.withAlphaComponent(energyPulse).setStroke()
        arc.stroke()

        if energy.name == "surge" || energy.name == "overdrive" {
            let reserve = NSBezierPath()
            reserve.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 36.5, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
            reserve.lineWidth = energy.name == "overdrive" ? 1.8 : 1.1
            reserve.lineCapStyle = .round
            phaseColor.withAlphaComponent((energy.name == "overdrive" ? 0.72 : 0.42) * energyPulse).setStroke()
            reserve.stroke()
        }

        if energy.name == "overdrive" {
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
        if expanded {
            let copyRect = CGRect(x: origin.x + 92, y: origin.y + 7, width: 230, height: 68)
            let copy = NSBezierPath(roundedRect: copyRect, xRadius: 14, yRadius: 14)
            NSColor(calibratedWhite: 0.022, alpha: 0.90).setFill()
            copy.fill()
            NSColor.white.withAlphaComponent(0.10).setStroke()
            copy.lineWidth = 1
            copy.stroke()

            let accentLine = NSBezierPath(roundedRect: CGRect(x: origin.x + 92, y: origin.y + 20, width: 2, height: 42), xRadius: 1, yRadius: 1)
            phaseColor.setFill()
            accentLine.fill()

            drawText("●  \(phaseLabel)", at: CGPoint(x: origin.x + 108, y: origin.y + 58), font: .monospacedSystemFont(ofSize: 7.5, weight: .bold), color: phaseColor, tracking: 1.1)
            let isConnected = streamConnected == true
            let connectionLabel = positioning ? positioningHint : isConnected ? (arcadeMode ? "ARCADE" : "FOCUS") : preferences.text("RECONNECTING", "重新连接中")
            drawText(connectionLabel, at: CGPoint(x: origin.x + (positioning || !isConnected ? 226 : 273), y: origin.y + 58), font: .monospacedSystemFont(ofSize: 6.5, weight: .bold), color: positioning ? phaseColor : isConnected ? NSColor.white.withAlphaComponent(0.34) : NSColor.systemOrange, tracking: preferences.isChinese ? 0.2 : 1.0)
            let presentedEvent = presentation.idle ? preferences.text("POWER MODE READY", "POWER MODE 待机") : eventText
            drawText(String(presentedEvent.prefix(31)), at: CGPoint(x: origin.x + 108, y: origin.y + 38), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(String(localizedActivity(idle: presentation.idle).prefix(39)), at: CGPoint(x: origin.x + 108, y: origin.y + 23), font: .systemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.55))

            let evidence = state.evidence?.isEmpty == false ? "\(state.evidence!.map { localizedCategory($0) }.joined(separator: "+")) ✓" : preferences.text("NO EVIDENCE", "暂无证据")
            let risk = (state.riskLevel ?? "low").lowercased() == "low" ? "" : "  ·  " + preferences.text("RISK", "风险")
            let comboCopy = showsCombo && combo.count > 0 ? "  ·  \(combo.count)× " + preferences.text("COMBO", "连击") : ""
            drawText("\(evidence)  ·  \(preferences.text("CONF", "可信度")) \(state.confidence ?? 0)%\(risk)\(comboCopy)", at: CGPoint(x: origin.x + 108, y: origin.y + 10), font: .monospacedSystemFont(ofSize: 6.8, weight: .semibold), color: phaseColor.withAlphaComponent(0.78), tracking: preferences.isChinese ? 0.15 : 0.45)
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
        let cycle: CGFloat = arcadeMode ? 34 : 54
        let progress = reducedMotion ? CGFloat(0.38) : shakePhase.truncatingRemainder(dividingBy: cycle) / cycle
        let chevronCount = arcadeMode ? 5 : 3
        for index in 0..<chevronCount {
            let trail = CGFloat(index) * (arcadeMode ? 6 : 8)
            let x = center.x - 27 - progress * 10 - trail
            let alpha = max(0.14, (1 - progress) * (0.94 - CGFloat(index) * (arcadeMode ? 0.14 : 0.2)))
            color.withAlphaComponent(alpha).setStroke()
            let chevron = NSBezierPath()
            chevron.move(to: CGPoint(x: x + 7, y: center.y - 7))
            chevron.line(to: CGPoint(x: x, y: center.y))
            chevron.line(to: CGPoint(x: x + 7, y: center.y + 7))
            chevron.lineWidth = 2.1
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()
        }

        color.withAlphaComponent(0.42).setStroke()
        let driveLine = NSBezierPath()
        driveLine.move(to: CGPoint(x: center.x + (arcadeMode ? 38 : 29), y: center.y))
        driveLine.line(to: CGPoint(x: center.x + 12, y: center.y))
        driveLine.lineWidth = 1.4
        driveLine.lineCapStyle = .square
        driveLine.stroke()
    }

    private func drawVerifySignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let cycle: CGFloat = arcadeMode ? 44 : 64
        let progress = reducedMotion ? CGFloat(0.32) : shakePhase.truncatingRemainder(dividingBy: cycle) / cycle
        let half = 38 - progress * 8
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

        let coreSize = 4 + (1 - progress) * 4
        color.withAlphaComponent(0.56).setFill()
        NSBezierPath(rect: CGRect(x: center.x - coreSize / 2, y: center.y - coreSize / 2, width: coreSize, height: coreSize)).fill()

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
        if momentum < 25 { return ("charging", 2.2, 0.035) }
        if momentum < 50 { return ("flow", 2.8, 0.055) }
        if momentum < 75 { return ("surge", 3.4, 0.085) }
        return ("overdrive", 4.1, 0.13)
    }

    private func energyRank(_ level: String) -> Int {
        switch level {
        case "charging": return 1
        case "flow": return 2
        case "surge": return 3
        case "overdrive": return 4
        default: return 0
        }
    }

    private func localizedEnergyLevel(_ level: String) -> String {
        switch level {
        case "charging": return preferences.text("CHARGE", "蓄能")
        case "flow": return preferences.text("FLOW", "流动")
        case "surge": return preferences.text("SURGE", "高能")
        case "overdrive": return preferences.text("OVERDRIVE", "过载")
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
        if count < 3 { return "building" }
        if count < 6 { return "linked" }
        return "chain"
    }

    private func comboRewardStage() -> String {
        if state.verificationReward == "record" { return "record" }
        if state.verificationReward == "confirmation" { return "confirmed" }
        return "reward"
    }

    private func localizedComboStage(_ stage: String) -> String {
        switch stage {
        case "building": return preferences.text("BUILD", "蓄连")
        case "linked": return preferences.text("LINK", "续连")
        case "chain": return preferences.text("CHAIN", "连锁")
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

    init(url: URL) { self.url = url }

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
            self?.rebuildMenu()
        }
        installStatusItem()
        if environment["CODEX_POWER_MODE_POSITIONING_PREVIEW"] == "1" {
            setPositioning(true)
        }

        let endpoint = environment["CODEX_POWER_MODE_URL"] ?? "http://127.0.0.1:4737/api/stream"
        guard let url = URL(string: endpoint), let view = panel.contentView as? PowerModeView else { return }
        let client = EventStream(url: url)
        client.onEvent = { [weak view] event in view?.handle(event) }
        client.onConnectionChange = { [weak view] connected in view?.setStreamConnected(connected) }
        client.start()
        stream = client
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.removeObserver(self, name: NSApplication.didChangeScreenParametersNotification, object: nil)
        removeMouseMonitors()
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
        menu.addItem(submenu(
            title: preferences.text("Activity source", "动态来源"),
            choices: [
                ("focused", preferences.text("Keep current conversation", "保持当前对话")),
                ("global", preferences.text("Follow all Codex activity", "跟随全部 Codex"))
            ],
            selected: preferences.settings.activitySource ?? "focused",
            action: #selector(selectActivitySource)
        ))
        menu.addItem(submenu(
            title: preferences.text("When idle", "静止状态"),
            choices: [
                ("hide", preferences.text("Auto hide", "自动隐藏")),
                ("orb", preferences.text("Keep orb", "保留小球")),
                ("always", preferences.text("Always expanded", "始终展开"))
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
        if ProcessInfo.processInfo.environment["CODEX_POWER_MODE_PLACEMENT_SELF_TEST"] == "1" {
            runPlacementGeometrySelfTest()
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

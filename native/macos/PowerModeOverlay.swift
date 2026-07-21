import AppKit
import Foundation

private struct PowerState: Decodable {
    let sessionId: String?
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
    let confidence: Int?
    let riskLevel: String?
    let currentActivity: String?
    let completion: String?
    let turnStoppedAt: String?
    let evidence: [String]?
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
    let toolGroup: String?
    let state: PowerState?
}

private struct OverlaySettings: Codable, Equatable {
    var schemaVersion = 1
    var preset = "focus"
    var edge = "top-right"
    var scale = 1.15
    var reducedMotion = false
    var followWhenInactive = false
    var enabled = true
    var idleBehavior = "hide"
    var language = "auto"
    var activitySource: String? = "focused"
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
    func setLanguage(_ value: String) { mutate { $0.language = value } }
    func setActivitySource(_ value: String) { mutate { $0.activitySource = value == "global" ? "global" : "focused" } }
    func setScale(_ value: Double) { mutate { $0.scale = min(1.6, max(0.75, value)) } }
    func toggleEnabled() { mutate { $0.enabled.toggle() } }
    func toggleReducedMotion() { mutate { $0.reducedMotion.toggle() } }
    func toggleFollowWhenInactive() { mutate { $0.followWhenInactive.toggle() } }
    func setPosition(x: Double, y: Double) { mutate { $0.positionX = x; $0.positionY = y } }
    func resetPosition() { mutate { $0.positionX = nil; $0.positionY = nil; $0.edge = "top-right" } }

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
    private var timerIsHighFrequency = false
    private var state = PowerState(sessionId: nil, phase: "observe", status: "ready", momentum: 0, bestMomentum: 0, combo: 0, bestCombo: 0, comboStatus: "idle", comboHoldUntil: nil, comboExpiresAt: nil, comboBrokenAt: nil, confidence: 0, riskLevel: "low", currentActivity: "Waiting for Codex activity", completion: nil, turnStoppedAt: nil, evidence: [], addedLines: 0, removedLines: 0, verifications: 0)
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
    private var turnStoppedAt: Date?
    private var comboWasAnimating = false
    private var streamConnected: Bool?
    private var hudAlpha: CGFloat = 0
    private var positioning = false
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

    private func scheduleTick(highFrequency: Bool) {
        guard timer == nil || timerIsHighFrequency != highFrequency else { return }
        timer?.invalidate()
        timerIsHighFrequency = highFrequency
        let interval = highFrequency ? 1.0 / 60.0 : 0.25
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer?.tolerance = highFrequency ? 0.001 : 0.04
    }

    required init?(coder: NSCoder) { nil }

    deinit { timer?.invalidate() }

    func preferencesChanged() {
        scheduleTick(highFrequency: !reducedMotion)
        needsDisplay = true
    }

    func historySummary() -> String {
        "\(preferences.text("BEST ENERGY", "最高能量")) \(state.bestMomentum ?? 0)  ·  \(preferences.text("BEST COMBO", "最高连击")) \(state.bestCombo ?? 0)×"
    }

    func activitySourceSummary() -> String {
        let source = preferences.settings.activitySource == "global"
            ? preferences.text("Follow all Codex activity", "跟随全部 Codex")
            : preferences.text("Keep current conversation", "保持当前对话")
        return "\(preferences.text("Activity source", "动态来源")): \(source)"
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

    func beginPositioning() {
        positioning = true
        hudExpandedUntil = .distantFuture
        hudAlpha = 1
        needsDisplay = true
    }

    func cancelPositioning() {
        positioning = false
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
        let centerX = min(bounds.maxX - size.width / 2, max(size.width / 2, origin.x + size.width / 2))
        let centerY = min(bounds.maxY - size.height / 2, max(size.height / 2, origin.y + size.height / 2))
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
        if let nextState = event.state {
            state = nextState
            comboHoldUntil = nextState.comboHoldUntil.flatMap(isoDateFormatter.date(from:))
            comboExpiresAt = nextState.comboExpiresAt.flatMap(isoDateFormatter.date(from:))
            comboBrokenAt = nextState.comboBrokenAt.flatMap(isoDateFormatter.date(from:))
            turnStoppedAt = nextState.turnStoppedAt.flatMap(isoDateFormatter.date(from:))
        }
        eventText = describe(event)
        if event.type == "connected" {
            needsDisplay = true
            return
        }
        scheduleTick(highFrequency: !reducedMotion)
        let duration: TimeInterval = event.type == "permission-request" || event.type == "edit-failure" || (event.type == "verification" && event.success != true) ? 8 : event.type == "turn-stop" ? 3.2 : 2.2
        hudExpandedUntil = Date().addingTimeInterval(duration)
        flashAlpha = reducedMotion ? 0 : 0.24

        guard !reducedMotion else {
            needsDisplay = true
            return
        }

        switch event.type {
        case "activity-start":
            if event.phase == "observe" {
                if event.toolGroup == "prompt" {
                    focusPulse(color: .systemCyan, count: arcadeMode ? 92 : 54)
                    shockwave(color: .systemCyan, power: 0.38)
                } else {
                    scan(color: .systemCyan)
                }
            } else if event.phase == "verify" {
                charge(color: .systemGreen, count: arcadeMode ? 100 : 58)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                    self?.shockwave(color: .systemGreen, power: 0.42)
                }
            } else {
                directionalSparks(color: .systemPurple, count: arcadeMode ? 48 : 26)
            }
        case "permission-request":
            attentionGates(color: .systemYellow, count: arcadeMode ? 72 : 42)
            shockwave(color: .systemYellow, power: 0.58)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) { [weak self] in
                self?.attentionGates(color: .systemYellow, count: self?.arcadeMode == true ? 48 : 28)
                self?.shockwave(color: .systemYellow, power: 0.42)
            }
        case "edit":
            let added = event.addedLines ?? 0
            let removed = event.removedLines ?? 0
            let addedChars = event.addedChars ?? added * 24
            let primary = removed > added ? NSColor.systemPink : NSColor.systemPurple
            shake = min(8, 1.5 + CGFloat(added + removed) * 0.12)
            shockwave(color: primary, power: min(1.8, 0.8 + CGFloat(added + removed) / 30))
            burst(color: primary, count: max(18, min(130, added * 3 + removed * 4)), power: 1.0, directional: true)
            replayTyping(characters: addedChars, lines: added)
            if removed > 0 { deletionSparks(lines: removed) }
        case "edit-failure":
            shockwave(color: .systemRed, power: 1.15)
            fragments(color: .systemRed, count: arcadeMode ? 132 : 82)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
                self?.shockwave(color: .systemRed, power: 0.68)
            }
            dangerAlpha = 0.42
            shake = 12
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                self?.repairFragments(color: NSColor.systemPink.withAlphaComponent(0.82), count: self?.arcadeMode == true ? 112 : 68)
            }
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                    self?.repairFragments(color: NSColor.systemPink.withAlphaComponent(0.82), count: self?.arcadeMode == true ? 96 : 58)
                }
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
        case "turn-stop" where event.state?.completion == "cancelled":
            shockwave(color: .systemOrange, power: 0.78)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.19) { [weak self] in
                self?.shockwave(color: .systemOrange, power: 0.52)
            }
        case "turn-stop" where event.state?.completion == "unverified":
            shockwave(color: .systemYellow, power: 0.68)
        default:
            break
        }
        needsDisplay = true
    }

    private func describe(_ event: PowerEvent) -> String {
        switch event.type {
        case "activity-start":
            if event.toolGroup == "prompt" { return preferences.text("UNDERSTANDING REQUEST", "正在理解需求") }
            return event.phase == "observe" ? preferences.text("READING CONTEXT", "正在读取上下文") : event.phase == "verify" ? preferences.text("BUILDING EVIDENCE", "正在建立验证证据") : preferences.text("STARTING TOOL", "正在执行工具")
        case "permission-request": return preferences.text("WAITING FOR YOUR APPROVAL", "等待你的授权")
        case "edit": return preferences.text("CHANGE APPLIED", "修改已应用") + "  +\(event.addedLines ?? 0)  −\(event.removedLines ?? 0)"
        case "edit-failure": return preferences.text("CHANGE COULD NOT BE APPLIED", "修改应用失败")
        case "verification": return "\(localizedCategory(event.category)) \(event.success == true ? preferences.text("PASSED", "通过") : preferences.text("FAILED", "失败"))"
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
        let safeMargin: CGFloat = 12
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
                x: min(bounds.width - size.width - safeMargin, max(safeMargin, desired.x)),
                y: min(bounds.height - size.height - safeMargin, max(safeMargin, desired.y))
            )
        }
        let left = min(preferredMargin, max(safeMargin, bounds.width - size.width - safeMargin))
        let right = max(safeMargin, bounds.width - size.width - preferredMargin)
        let bottom = min(preferredMargin, max(safeMargin, bounds.height - size.height - safeMargin))
        let top = max(safeMargin, bounds.height - size.height - preferredMargin)
        switch edge {
        case "top-left": return CGPoint(x: left, y: top)
        case "bottom-left": return CGPoint(x: left, y: bottom)
        case "bottom-right": return CGPoint(x: right, y: bottom)
        case "center": return CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2)
        default: return CGPoint(x: right, y: top)
        }
    }

    private func effectiveHudScale(for baseSize: CGSize) -> CGFloat {
        let safeWidth = max(1, bounds.width - 24)
        let safeHeight = max(1, bounds.height - 24)
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

    private func presentationSnapshot(now: Date = Date()) -> (phase: String, status: String, momentum: Int, idle: Bool, settled: Bool, returning: Bool) {
        let phase = state.phase ?? "observe"
        let status = state.status ?? "ready"
        let momentum = min(100, max(0, state.momentum ?? 0))
        guard let turnStoppedAt else { return (phase, status, momentum, false, false, false) }
        let finalHoldEnd = turnStoppedAt.addingTimeInterval(3)
        let disconnectedAt = comboBrokenAt ?? comboExpiresAt
        let comboEnd = disconnectedAt?.addingTimeInterval(3.2) ?? .distantPast
        let idleAt = max(finalHoldEnd, comboEnd)
        guard now >= idleAt else { return (phase, status, momentum, false, false, false) }
        let progress = min(1, max(0, now.timeIntervalSince(idleAt) / 4))
        return ("idle", "ready", Int((Double(momentum) * (1 - progress)).rounded()), true, progress >= 1, progress < 1)
    }

    private func shouldShowHUD(now: Date) -> Bool {
        guard preferences.settings.enabled else { return false }
        if positioning || streamConnected != true { return true }
        if preferences.settings.idleBehavior != "hide" { return true }
        if state.phase == "wait" || state.phase == "recover" || state.status == "needs-attention" || state.status == "failed" { return true }
        if state.status == "working" { return true }
        if now < hudExpandedUntil { return true }
        let combo = comboSnapshot(now: now)
        if combo.active || combo.lost { return true }
        return turnStoppedAt != nil && !presentationSnapshot(now: now).settled
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
        let origin = reactorCenter()
        let color: NSColor = index.isMultiple(of: 4) ? .systemPurple : .systemCyan
        for _ in 0..<Int.random(in: 4...8) {
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

    private func scan(color: NSColor, echo: Bool = true) {
        guard !reducedMotion else { return }
        let origin = reactorCenter()
        let life: CGFloat = 58
        scanBeams.append(ScanBeam(origin: origin, length: -min(bounds.width * 0.72, origin.x - 48), life: life, maxLife: life, color: color))
        if arcadeMode && echo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { [weak self] in self?.scan(color: color.withAlphaComponent(0.7), echo: false) }
        }
    }

    private func focusPulse(color: NSColor, count: Int) {
        guard !reducedMotion else { return }
        let center = reactorCenter()
        for _ in 0..<count {
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
        for _ in 0..<count {
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
        for index in 0..<count {
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
        for index in 0..<count {
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
        for index in 0..<count {
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
            width: 2.2 * power,
            color: color
        ))
    }

    private func burst(color: NSColor, count: Int, power: CGFloat, directional: Bool = false) {
        let center = reactorCenter()
        let scaledCount = arcadeMode ? Int(Double(count) * 1.55) : count
        for _ in 0..<min(scaledCount, 280) {
            let angle = directional ? CGFloat.random(in: (.pi - 0.65)...(.pi + 0.65)) : CGFloat.random(in: 0...(2 * .pi))
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
        let now = Date()
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
        let hudIsExpanded = positioning || preferences.settings.idleBehavior == "always" || now < hudExpandedUntil
        if hudIsExpanded != hudWasExpanded {
            hudWasExpanded = hudIsExpanded
            needsDisplay = true
        }
        let comboTimelineEnd = (comboBrokenAt ?? comboExpiresAt ?? .distantPast).addingTimeInterval(3.2)
        let comboIsAnimating = now < comboTimelineEnd
        if comboIsAnimating != comboWasAnimating {
            comboWasAnimating = comboIsAnimating
            needsDisplay = true
        }
        let hasEffects = !particles.isEmpty || !shockwaves.isEmpty || !scanBeams.isEmpty || flashAlpha > 0 || dangerAlpha > 0 || shake > 0
        let comboIsDecaying = (comboHoldUntil.map { now >= $0 } ?? true) && now < (comboExpiresAt ?? .distantPast)
        let presentation = presentationSnapshot(now: now)
        let targetAlpha: CGFloat = shouldShowHUD(now: now) ? 1 : 0
        let previousAlpha = hudAlpha
        let fadeStep: CGFloat = reducedMotion ? 1 : 0.12
        hudAlpha += min(fadeStep, max(-fadeStep, targetAlpha - hudAlpha))
        let hudIsFading = abs(hudAlpha - targetAlpha) > 0.001
        let needsHighFrequency = !reducedMotion && (hasEffects || hudIsExpanded || comboIsDecaying || presentation.returning || hudIsFading)
        if hasEffects || hudIsExpanded || comboIsAnimating || presentation.returning || previousAlpha != hudAlpha { needsDisplay = true }
        scheduleTick(highFrequency: needsHighFrequency)
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
        let arc = NSBezierPath()
        arc.appendArc(withCenter: CGPoint(x: origin.x + 41, y: origin.y + 41), radius: 31, startAngle: 90, endAngle: 90 - 360 * progress, clockwise: true)
        arc.lineWidth = 2.4
        arc.lineCapStyle = .round
        phaseColor.setStroke()
        arc.stroke()

        let value = "\(momentum)"
        drawText(value, at: CGPoint(x: origin.x + (value.count > 2 ? 21 : value.count > 1 ? 27 : 34), y: origin.y + 34), font: .systemFont(ofSize: 21, weight: .bold), color: .white)
        drawText(preferences.text("POWER", "能量"), at: CGPoint(x: origin.x + (preferences.isChinese ? 33 : 29), y: origin.y + 24), font: .monospacedSystemFont(ofSize: 5.5, weight: .bold), color: NSColor.white.withAlphaComponent(0.52), tracking: 0.9)
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
            }
        }
        let combo = comboSnapshot()
        drawCombo(combo, at: origin, color: combo.active ? phaseColor : combo.lost ? .systemRed : NSColor.white.withAlphaComponent(0.34))
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
            let connectionLabel = positioning ? preferences.text("DRAG TO POSITION", "拖动调整位置") : isConnected ? (arcadeMode ? "ARCADE" : "FOCUS") : preferences.text("RECONNECTING", "重新连接中")
            drawText(connectionLabel, at: CGPoint(x: origin.x + (positioning || !isConnected ? 226 : 273), y: origin.y + 58), font: .monospacedSystemFont(ofSize: 6.5, weight: .bold), color: positioning ? phaseColor : isConnected ? NSColor.white.withAlphaComponent(0.34) : NSColor.systemOrange, tracking: preferences.isChinese ? 0.2 : 1.0)
            let presentedEvent = presentation.idle ? preferences.text("POWER MODE READY", "POWER MODE 待机") : eventText
            drawText(String(presentedEvent.prefix(31)), at: CGPoint(x: origin.x + 108, y: origin.y + 38), font: .systemFont(ofSize: 13, weight: .semibold), color: .white)
            drawText(String(localizedActivity(idle: presentation.idle).prefix(39)), at: CGPoint(x: origin.x + 108, y: origin.y + 23), font: .systemFont(ofSize: 8.5, weight: .medium), color: NSColor.white.withAlphaComponent(0.55))

            let evidence = state.evidence?.isEmpty == false ? "\(state.evidence!.map { localizedCategory($0) }.joined(separator: "+")) ✓" : preferences.text("NO EVIDENCE", "暂无证据")
            let risk = (state.riskLevel ?? "low").lowercased() == "low" ? "" : "  ·  " + preferences.text("RISK", "风险")
            let comboCopy = combo.count > 0 ? "  ·  \(combo.count)× " + preferences.text("COMBO", "连击") : ""
            drawText("\(evidence)  ·  \(preferences.text("CONF", "可信度")) \(state.confidence ?? 0)%\(risk)\(comboCopy)", at: CGPoint(x: origin.x + 108, y: origin.y + 10), font: .monospacedSystemFont(ofSize: 6.8, weight: .semibold), color: phaseColor.withAlphaComponent(0.78), tracking: preferences.isChinese ? 0.15 : 0.45)
        }
        context.restoreGState()
    }

    private func drawWaitSignal(around origin: CGPoint, color: NSColor) {
        let cycle = reducedMotion ? CGFloat(0) : shakePhase.truncatingRemainder(dividingBy: 72)
        let firstBeat = max(0, 1 - abs(cycle - 8) / 6)
        let secondBeat = max(0, 1 - abs(cycle - 22) / 5) * 0.72
        let beat = min(1, firstBeat + secondBeat)
        let pulse = reducedMotion ? CGFloat(0.82) : 0.48 + beat * 0.52
        let reach = reducedMotion ? CGFloat(5) : 3 + beat * 7
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
        let heading = reducedMotion ? CGFloat(35) : shakePhase * 0.19
        for index in 0..<3 {
            let trail = CGFloat(index) * 14
            let sweep = NSBezierPath()
            sweep.appendArc(withCenter: center, radius: 38.5, startAngle: heading - trail - 13, endAngle: heading - trail)
            sweep.lineWidth = 2.2
            sweep.lineCapStyle = .round
            color.withAlphaComponent(0.78 - CGFloat(index) * 0.23).setStroke()
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
        let progress = reducedMotion ? CGFloat(0.38) : shakePhase.truncatingRemainder(dividingBy: 54) / 54
        for index in 0..<3 {
            let trail = CGFloat(index) * 8
            let x = center.x - 27 - progress * 10 - trail
            let alpha = max(0.18, (1 - progress) * (0.92 - CGFloat(index) * 0.2))
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
        driveLine.move(to: CGPoint(x: center.x + 29, y: center.y))
        driveLine.line(to: CGPoint(x: center.x + 12, y: center.y))
        driveLine.lineWidth = 1.4
        driveLine.lineCapStyle = .square
        driveLine.stroke()
    }

    private func drawVerifySignal(around origin: CGPoint, color: NSColor) {
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        let progress = reducedMotion ? CGFloat(0.32) : shakePhase.truncatingRemainder(dividingBy: 64) / 64
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
    }

    private func drawRecoverSignal(around origin: CGPoint, color: NSColor) {
        let oscillation = reducedMotion ? 0 : sin(shakePhase * 0.075)
        let rotation = oscillation * 7
        let center = CGPoint(x: origin.x + 41, y: origin.y + 41)
        color.withAlphaComponent(0.72 + oscillation * 0.16).setStroke()
        for (index, angles) in [(14.0, 62.0), (88.0, 139.0), (166.0, 224.0), (252.0, 333.0)].enumerated() {
            let direction: CGFloat = index.isMultiple(of: 2) ? 1 : -1
            let segment = NSBezierPath()
            segment.appendArc(
                withCenter: center,
                radius: 41 + direction * oscillation * 1.5,
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
        let rotation = reducedMotion ? 0 : shakePhase * 0.18
        let colors: [NSColor] = [.systemGreen, .systemPurple, .systemCyan]
        for (index, color) in colors.enumerated() {
            let start = CGFloat(index) * 120 + rotation
            let ribbon = NSBezierPath()
            ribbon.appendArc(withCenter: center, radius: 41, startAngle: start + 4, endAngle: start + 112)
            ribbon.lineWidth = 2
            ribbon.lineCapStyle = .round
            color.withAlphaComponent(0.9).setStroke()
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
        ring.setLineDash([7, 5], count: 2, phase: reducedMotion ? 0 : shakePhase * 0.12)
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

    private func comboSnapshot(now: Date = Date()) -> (count: Int, progress: CGFloat, active: Bool, lost: Bool) {
        let count = state.combo ?? 0
        guard count > 0, let expires = comboExpiresAt, now < expires else {
            let disconnectedAt = comboBrokenAt ?? comboExpiresAt
            let lost = disconnectedAt.map { now < $0.addingTimeInterval(3.2) } ?? false
            return (0, 0, false, lost)
        }
        guard let hold = comboHoldUntil, now > hold else { return (count, 1, true, false) }
        let duration = expires.timeIntervalSince(hold)
        let remaining = expires.timeIntervalSince(now)
        return (count, CGFloat(max(0, min(1, remaining / max(0.001, duration)))), true, false)
    }

    private func drawCombo(_ combo: (count: Int, progress: CGFloat, active: Bool, lost: Bool), at origin: CGPoint, color: NSColor) {
        guard combo.active || combo.lost else { return }
        let capsuleRect = CGRect(x: origin.x + 5, y: origin.y - 23, width: 72, height: 21)
        let capsule = NSBezierPath(roundedRect: capsuleRect, xRadius: 8, yRadius: 8)
        NSColor(calibratedWhite: 0.025, alpha: 0.92).setFill()
        capsule.fill()
        color.withAlphaComponent(0.3).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()

        let trackRect = CGRect(x: origin.x + 11, y: origin.y - 17, width: 60, height: 5)
        let track = NSBezierPath(roundedRect: trackRect, xRadius: 2.5, yRadius: 2.5)
        NSColor.white.withAlphaComponent(0.18).setFill()
        track.fill()
        if combo.progress > 0 {
            let fillRect = CGRect(x: trackRect.minX, y: trackRect.minY, width: trackRect.width * combo.progress, height: trackRect.height)
            let fill = NSBezierPath(roundedRect: fillRect, xRadius: 2.5, yRadius: 2.5)
            color.setFill()
            fill.fill()
        }
        let copy = combo.lost ? preferences.text("LOST", "断连") : "\(combo.count)× " + preferences.text("COMBO", "连击")
        drawText(copy, at: CGPoint(x: origin.x + (combo.lost ? 29 : 19), y: origin.y - 10), font: .monospacedSystemFont(ofSize: 6.4, weight: .bold), color: color.withAlphaComponent(0.96), tracking: preferences.isChinese ? 0.2 : 0.55)
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
        reconnectAttempt = 0
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

    private func refresh() {
        guard let panel else { return }
        let followsInactive = preferences.settings.followWhenInactive
        let codexIsFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        panel.level = followsInactive ? .statusBar : .floating
        guard followsInactive || codexIsFrontmost else {
            panel.orderOut(nil)
            return
        }
        let targetFrame = codexIsFrontmost ? codexWindowFrame() : frontmostWindowFrame()
        guard let frame = targetFrame, frame.width > 400, frame.height > 300 else {
            panel.orderOut(nil)
            return
        }
        if !frame.equalTo(lastFrame) {
            panel.setFrame(frame, display: true)
            panel.contentView?.frame = CGRect(origin: .zero, size: frame.size)
            lastFrame = frame
        }
        if followsInactive && !codexIsFrontmost {
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
        preferences.onChange = { [weak self, weak powerView] in
            powerView?.preferencesChanged()
            self?.tracker?.preferencesChanged()
            self?.rebuildMenu()
        }
        installStatusItem()

        let endpoint = environment["CODEX_POWER_MODE_URL"] ?? "http://127.0.0.1:4737/api/stream"
        guard let url = URL(string: endpoint), let view = panel.contentView as? PowerModeView else { return }
        let client = EventStream(url: url)
        client.onEvent = { [weak view] event in view?.handle(event) }
        client.onConnectionChange = { [weak view] connected in view?.setStreamConnected(connected) }
        client.start()
        stream = client
    }

    func applicationWillTerminate(_ notification: Notification) {
        removeMouseMonitors()
        stream?.stop()
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
            let source = NSMenuItem(title: view.activitySourceSummary(), action: nil, keyEquivalent: "")
            source.isEnabled = false
            menu.addItem(source)
            let summary = view.sessionSummary()
            let session = NSMenuItem(title: summary.title, action: nil, keyEquivalent: "")
            session.toolTip = summary.fullId
            session.isEnabled = false
            menu.addItem(session)
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
        let follow = NSMenuItem(title: preferences.text("Show when Codex is inactive", "Codex 非前台时显示"), action: #selector(toggleFollow), keyEquivalent: "")
        follow.target = self
        follow.state = preferences.settings.followWhenInactive ? .on : .off
        menu.addItem(follow)

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
    @objc private func selectActivitySource(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setActivitySource(value) } }
    @objc private func selectIdleBehavior(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setIdleBehavior(value) } }
    @objc private func selectLanguage(_ sender: NSMenuItem) { if let value = sender.representedObject as? String { preferences?.setLanguage(value) } }
    @objc private func selectScale(_ sender: NSMenuItem) { if let value = sender.representedObject as? String, let scale = Double(value) { preferences?.setScale(scale) } }
    @objc private func toggleReducedMotion() { preferences?.toggleReducedMotion() }
    @objc private func toggleFollow() { preferences?.toggleFollowWhenInactive() }
    @objc private func resetPosition() { preferences?.resetPosition() }
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
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

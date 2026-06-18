import Cocoa
import Foundation

// StatusDot — macOS menu bar traffic light for AI agents (Hermes/Claude/Codex/OpenClaw)
// Three dots (R·Y·G) in a white rounded pill with state-driven animations.
// IPC: reads ~/.hermes/agent_status every 0.5s.

let STATUS_FILE = NSHomeDirectory() + "/.hermes/agent_status"
let PREVIEW_LOCK = "/tmp/hermes_preview_active"

enum AgentState: String {
    case idle = "idle", thinking = "thinking", working = "working"
    case success = "success", error = "error", waiting = "waiting"
    case unknown = "unknown"
}

// Low-saturation colors, visually distinct in menu bar
struct C {
    static let red    = NSColor(hue: 355/360, saturation: 0.55, brightness: 0.80, alpha: 1.0)
    static let yellow = NSColor(hue:  42/360, saturation: 0.65, brightness: 0.75, alpha: 1.0)
    static let green  = NSColor(hue: 140/360, saturation: 0.50, brightness: 0.72, alpha: 1.0)
    static let offFill   = NSColor(white: 0.88, alpha: 1.0)
    static let offStroke = NSColor(white: 0.75, alpha: 1.0)
    static let pillFill   = NSColor(white: 0.97, alpha: 1.0)
    static let pillStroke = NSColor(white: 0.82, alpha: 1.0)
}

// ── Three-dot traffic light view ─────────────────────────────────────
class TrafficLightView: NSView {
    var state: AgentState = .idle
    var animStart = Date()
    let stepInterval: TimeInterval = 1.0 / 3

    // Layout
    let dotD: CGFloat = 8
    let gap: CGFloat  = 5
    let padH: CGFloat = 5
    let padV: CGFloat = 4
    let rad: CGFloat  = 6

    var totalW: CGFloat { padH*2 + dotD*3 + gap*2 }
    var totalH: CGFloat { padV*2 + dotD }

    func cx(_ i: Int) -> CGFloat { padH + dotD/2 + CGFloat(i)*(dotD + gap) }
    func cy() -> CGFloat { padV + dotD/2 }

    override func draw(_ dirtyRect: NSRect) {
        let pill = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: totalW, height: totalH),
                                xRadius: rad, yRadius: rad)
        C.pillFill.setFill(); pill.fill()
        C.pillStroke.setStroke(); pill.lineWidth = 0.5; pill.stroke()

        switch state {
        case .idle, .unknown:
            drawDot(0, C.offFill, C.offStroke)
            drawDot(1, C.offFill, C.offStroke)
            drawDot(2, C.offFill, C.offStroke)

        case .thinking:
            let elapsed = Date().timeIntervalSince(animStart)
            let alpha = 0.15 + 0.85 * (1 + cos(elapsed * .pi + .pi)) / 2
            drawDotGradient(0, C.red,    alpha)
            drawDotGradient(1, C.yellow, alpha)
            drawDotGradient(2, C.green,  alpha)

        case .working:
            let elapsed = Date().timeIntervalSince(animStart)
            let phase = (elapsed / stepInterval).truncatingRemainder(dividingBy: 3)
            func dist(_ p: Double) -> Double { max(0, 1 - min(abs(phase - p), 2)) }
            let wrap = phase > 2 ? max(0, phase - 2) : 0
            drawDotGradient(0, C.red,    max(dist(0), wrap))
            drawDotGradient(1, C.yellow, dist(1))
            drawDotGradient(2, C.green,  dist(2))

        case .success:
            let elapsed = Date().timeIntervalSince(animStart)
            let step = Int(elapsed / 0.1)
            if step < 5 {
                let on = step == 0 || step == 4 ? 0 : step == 1 || step == 3 ? 1 : 2
                drawDot(0, on == 0 ? C.red    : C.offFill, C.offStroke)
                drawDot(1, on == 1 ? C.yellow : C.offFill, C.offStroke)
                drawDot(2, on == 2 ? C.green  : C.offFill, C.offStroke)
            } else {
                drawDot(0, C.green, C.offStroke)
                drawDot(1, C.green, C.offStroke)
                drawDot(2, C.green, C.offStroke)
            }

        case .error:
            let elapsed = Date().timeIntervalSince(animStart)
            if elapsed < 0.4 {
                let cycle = Int(elapsed / 0.1) % 2
                if cycle == 0 {
                    drawDot(0, C.red, C.offStroke)
                    drawDot(1, C.red, C.offStroke)
                    drawDot(2, C.red, C.offStroke)
                } else {
                    drawDot(0, C.offFill, C.offStroke)
                    drawDot(1, C.offFill, C.offStroke)
                    drawDot(2, C.offFill, C.offStroke)
                }
            } else {
                drawDot(0, C.red, C.offStroke)
                drawDot(1, C.red, C.offStroke)
                drawDot(2, C.red, C.offStroke)
            }

        case .waiting:
            let elapsed = Date().timeIntervalSince(animStart)
            let alpha = 0.15 + 0.85 * (1 + cos(elapsed * .pi + .pi)) / 2
            drawDotGradient(0, C.yellow, alpha)
            drawDotGradient(1, C.yellow, alpha)
            drawDotGradient(2, C.yellow, alpha)
        }
    }

    private func drawDot(_ i: Int, _ fill: NSColor, _ stroke: NSColor) {
        let x = cx(i) - dotD/2, y = cy() - dotD/2
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotD, height: dotD))
        fill.setFill(); dot.fill()
        if fill == C.offFill {
            stroke.setStroke(); dot.lineWidth = 0.5; dot.stroke()
        }
    }

    private func drawDotGradient(_ i: Int, _ color: NSColor, _ alpha: Double) {
        let x = cx(i) - dotD/2, y = cy() - dotD/2
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotD, height: dotD))
        let a = max(0, min(1, alpha))
        let blended = color.blended(withFraction: a, of: C.offFill) ?? color
        blended.setFill(); dot.fill()
        if a < 0.3 {
            C.offStroke.setStroke(); dot.lineWidth = 0.5; dot.stroke()
        }
    }
}

// ── App delegate ─────────────────────────────────────────────────────
class StatusDot: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lightView: TrafficLightView!
    var pollTimer: Timer?
    var animTimer: Timer?
    var successTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        lightView = TrafficLightView(frame: NSRect(x: 0, y: 0, width: 44, height: 17))
        statusItem = NSStatusBar.system.statusItem(withLength: 44)
        statusItem.button?.title = ""
        if let btn = statusItem.button {
            lightView.frame = NSRect(x: 0, y: 3, width: 44, height: 17)
            btn.addSubview(lightView)
        }
        buildMenu()

        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func buildMenu() {
        let menu = NSMenu()
        let agent = currentAgent()
        menu.addItem(NSMenuItem(title: "Agent: \(agent)", action: nil, keyEquivalent: ""))
        let agentItem = NSMenuItem(title: "Switch Agent", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for a in ["hermes", "claude", "openclaw", "codex", "manual"] {
            let it = NSMenuItem(title: a, action: #selector(switchAgent(_:)), keyEquivalent: "")
            it.representedObject = a
            it.state = a == agent ? .on : .off
            sub.addItem(it)
        }
        agentItem.submenu = sub
        menu.addItem(agentItem)
        menu.addItem(NSMenuItem.separator())
        for s in ["idle", "thinking", "working", "success", "error", "waiting"] {
            let item = NSMenuItem(title: "Preview: \(s)", action: #selector(testState(_:)), keyEquivalent: "")
            item.representedObject = s
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func poll() {
        guard let raw = try? String(contentsOfFile: STATUS_FILE, encoding: .utf8) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let s = AgentState(rawValue: trimmed) else { return }
        setState(s)
    }

    func setState(_ s: AgentState) {
        if s == lightView.state { return }
        lightView.state = s
        lightView.animStart = Date()
        if s == .success {
            successTimer?.invalidate()
            successTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                self?.setState(.idle)
            }
        } else {
            successTimer?.invalidate(); successTimer = nil
        }
        lightView.needsDisplay = true
    }

    func tick() {
        switch lightView.state {
        case .thinking, .working, .waiting:
            lightView.needsDisplay = true
        case .success, .error:
            let elapsed = Date().timeIntervalSince(lightView.animStart)
            if elapsed < 0.6 { lightView.needsDisplay = true }
        default: break
        }
    }

    var previewRestore: DispatchWorkItem?

    @objc func testState(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        previewRestore?.cancel()
        try? "1".write(toFile: PREVIEW_LOCK, atomically: true, encoding: .utf8)
        try? s.write(toFile: STATUS_FILE, atomically: true, encoding: .utf8)
        poll()
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(atPath: PREVIEW_LOCK)
            try? "idle".write(toFile: STATUS_FILE, atomically: true, encoding: .utf8)
            self.poll()
        }
        previewRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    @objc func quitApp() { NSApp.terminate(nil) }

    // ── Agent switching ──
    let PROVIDER_CFG = NSHomeDirectory() + "/.hermes/status_provider"

    func currentAgent() -> String {
        (try? String(contentsOfFile: PROVIDER_CFG, encoding: .utf8))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            ?? "hermes"
    }

    @objc func switchAgent(_ sender: NSMenuItem) {
        guard let agent = sender.representedObject as? String else { return }
        try? agent.write(toFile: PROVIDER_CFG, atomically: true, encoding: .utf8)
        buildMenu()
    }
}

let a = NSApplication.shared
a.setActivationPolicy(.accessory)
let delegate = StatusDot()
a.delegate = delegate
a.run()
_ = delegate

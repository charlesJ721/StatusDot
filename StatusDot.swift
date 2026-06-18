import Cocoa
import Foundation

// StatusDot v3 — macOS menu bar three-dot AI agent status indicator
// Reads ~/.hermes/agent_status/ directory for multi-agent states
// 4 states: idle, thinking, working, waiting

let STATUS_DIR   = NSHomeDirectory() + "/.hermes/agent_status"
let IDLE_FILE    = STATUS_DIR + "/__idle__"
let PREVIEW_FILE = STATUS_DIR + "/__preview__"
let PREVIEW_FLAG = "/tmp/hermes_preview_active"

enum AgentState: String {
    case idle = "idle"
    case thinking = "thinking"
    case working = "working"
    case waiting = "waiting"
}

// ── Color constants ─────────────────────────────────────────────────
struct C {
    static let red       = NSColor(hue: 355/360, saturation: 0.55, brightness: 0.80, alpha: 1.0)
    static let yellow    = NSColor(hue:  42/360, saturation: 0.65, brightness: 0.75, alpha: 1.0)
    static let green     = NSColor(hue: 140/360, saturation: 0.50, brightness: 0.72, alpha: 1.0)
    static let offFill   = NSColor(white: 0.88, alpha: 1.0)
    static let offStroke = NSColor(white: 0.75, alpha: 1.0)
    static let pillFill   = NSColor(white: 0.97, alpha: 1.0)
    static let pillStroke = NSColor(white: 0.82, alpha: 1.0)
}

// ── Three-dot traffic light view ────────────────────────────────────
class TrafficLightView: NSView {
    var state: AgentState = .idle
    var animStart = Date()

    // Layout constants
    let dotD: CGFloat = 8
    let gap: CGFloat  = 5
    let padH: CGFloat = 5
    let padV: CGFloat = 4
    let rad: CGFloat  = 6

    var totalW: CGFloat { padH * 2 + dotD * 3 + gap * 2 }
    var totalH: CGFloat { padV * 2 + dotD }

    func cx(_ i: Int) -> CGFloat { padH + dotD / 2 + CGFloat(i) * (dotD + gap) }
    func cy()         -> CGFloat { padV + dotD / 2 }

    override func draw(_ dirtyRect: NSRect) {
        // Pill background
        let pill = NSBezierPath(
            roundedRect: NSRect(x: 0, y: 0, width: totalW, height: totalH),
            xRadius: rad, yRadius: rad
        )
        C.pillFill.setFill(); pill.fill()
        C.pillStroke.setStroke(); pill.lineWidth = 0.5; pill.stroke()

        switch state {
        case .idle:
            drawDot(0, C.offFill, C.offStroke)
            drawDot(1, C.offFill, C.offStroke)
            drawDot(2, C.offFill, C.offStroke)

        case .thinking:
            // Three-dot cos breathing, same phase, min brightness 15%, start from dimmest
            let elapsed = Date().timeIntervalSince(animStart)
            let alpha = 0.15 + 0.85 * (1 + cos(elapsed * .pi + .pi)) / 2
            drawDotGradient(0, C.red,    alpha)
            drawDotGradient(1, C.yellow, alpha)
            drawDotGradient(2, C.green,  alpha)

        case .working:
            // Marquee: R→Y→G, phase 0→1→2→0 over 1 second
            let elapsed = Date().timeIntervalSince(animStart)
            let stepInterval: Double = 1.0 / 3.0
            let phase = (elapsed / stepInterval).truncatingRemainder(dividingBy: 3)
            // Brightness = 1 - distance; closer to phase = brighter
            func brightness(_ pos: Double) -> Double {
                let d = abs(phase - pos)
                let wrapped = min(d, 3 - d)  // handle wraparound
                return max(0, 1 - wrapped)
            }
            drawDotGradient(0, C.red,    brightness(0))
            drawDotGradient(1, C.yellow, brightness(1))
            drawDotGradient(2, C.green,  brightness(2))

        case .waiting:
            // All yellow, cos breathing (same rhythm as thinking)
            let elapsed = Date().timeIntervalSince(animStart)
            let alpha = 0.15 + 0.85 * (1 + cos(elapsed * .pi + .pi)) / 2
            drawDotGradient(0, C.yellow, alpha)
            drawDotGradient(1, C.yellow, alpha)
            drawDotGradient(2, C.yellow, alpha)
        }
    }

    private func drawDot(_ i: Int, _ fill: NSColor, _ stroke: NSColor) {
        let x = cx(i) - dotD / 2
        let y = cy() - dotD / 2
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotD, height: dotD))
        fill.setFill(); dot.fill()
        if fill == C.offFill {
            stroke.setStroke(); dot.lineWidth = 0.5; dot.stroke()
        }
    }

    private func drawDotGradient(_ i: Int, _ color: NSColor, _ alpha: Double) {
        let x = cx(i) - dotD / 2
        let y = cy() - dotD / 2
        let dot = NSBezierPath(ovalIn: NSRect(x: x, y: y, width: dotD, height: dotD))
        let a = max(0, min(1, alpha))
        let blended = color.blended(withFraction: a, of: C.offFill) ?? color
        blended.setFill(); dot.fill()
        if a < 0.3 {
            C.offStroke.setStroke(); dot.lineWidth = 0.5; dot.stroke()
        }
    }
}

// ── App delegate ────────────────────────────────────────────────────
class StatusDot: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var lightView: TrafficLightView!
    var pollTimer: Timer?
    var animTimer: Timer?

    // Active agent tracking for menu display
    var activeAgent: String = "—"
    var activeState: AgentState = .idle

    func applicationDidFinishLaunching(_ notification: Notification) {
        lightView = TrafficLightView(frame: NSRect(x: 0, y: 0, width: 44, height: 17))

        // Status bar item: width 44
        statusItem = NSStatusBar.system.statusItem(withLength: 44)
        statusItem.button?.title = ""
        if let btn = statusItem.button {
            lightView.frame = NSRect(x: 0, y: 3, width: 44, height: 17)
            btn.addSubview(lightView)
        }
        buildMenu()

        // Ensure status directory exists
        try? FileManager.default.createDirectory(
            atPath: STATUS_DIR,
            withIntermediateDirectories: true,
            attributes: nil
        )

        // Poll every 0.5s
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }

        // Animation tick at ~30fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 0.033, repeats: true) { [weak self] _ in
            self?.tick()
        }

        // Initial poll
        poll()
    }

    func buildMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem.separator())

        let titleItem = NSMenuItem(title: "StatusDot v3", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let activeItem = NSMenuItem(
            title: "Active: \(activeAgent) — \(activeState.rawValue)",
            action: nil,
            keyEquivalent: ""
        )
        activeItem.isEnabled = false
        menu.addItem(activeItem)

        menu.addItem(NSMenuItem.separator())

        // Preview submenu
        let previewItem = NSMenuItem(title: "Preview:", action: nil, keyEquivalent: "")
        let previewSub = NSMenu()
        for s in ["idle", "thinking", "working", "waiting"] {
            let it = NSMenuItem(title: "  · \(s)", action: #selector(testState(_:)), keyEquivalent: "")
            it.representedObject = s
            previewSub.addItem(it)
        }
        previewItem.submenu = previewSub
        menu.addItem(previewItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // ── Polling logic ────────────────────────────────────────────────
    func poll() {
        let fm = FileManager.default

        // ── Built-in fallback: if no file mtime changed in 5s → force idle ──
        var anyRecent = false
        if let entries = try? fm.contentsOfDirectory(atPath: STATUS_DIR) {
            for entry in entries {
                if entry.hasPrefix(".") { continue }
                let path = STATUS_DIR + "/" + entry
                if let attrs = try? fm.attributesOfItem(atPath: path),
                   let mtime = attrs[.modificationDate] as? Date {
                    if Date().timeIntervalSince(mtime) < 5 {
                        anyRecent = true
                        break
                    }
                }
            }
        }
        if !anyRecent {
            setState(.idle, agent: nil)
            return
        }

        // ── Scan agent_status directory ──────────────────────────────
        guard let entries = try? fm.contentsOfDirectory(atPath: STATUS_DIR) else {
            setState(.idle, agent: nil)
            return
        }

        // Exclude __idle__ and hidden files (.prefix); include __preview__
        // Find first agent with a non-"idle" state
        var foundState: AgentState? = nil
        var foundAgent: String? = nil

        for entry in entries {
            if entry.hasPrefix(".") || entry == "__idle__" { continue }

            let path = STATUS_DIR + "/" + entry
            guard let raw = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            if trimmed != "idle", let s = AgentState(rawValue: trimmed) {
                foundState = s
                foundAgent = entry
                break
            }
        }

        if let state = foundState, let agent = foundAgent {
            setState(state, agent: agent)
        } else {
            // All agents are idle → read __idle__ for confirmation
            if let raw = try? String(contentsOfFile: IDLE_FILE, encoding: .utf8),
               let s = AgentState(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                setState(s, agent: nil)
            } else {
                setState(.idle, agent: nil)
            }
        }
    }

    func setState(_ s: AgentState, agent: String?) {
        if let a = agent { activeAgent = a }
        activeState = s

        // Only skip redraw if state unchanged AND no agent name update
        if s == lightView.state && agent == nil { return }

        lightView.state = s
        lightView.animStart = Date()
        lightView.needsDisplay = true

        buildMenu()
    }

    func tick() {
        switch lightView.state {
        case .thinking, .working, .waiting:
            lightView.needsDisplay = true
        default:
            break
        }
    }

    // ── Preview ──────────────────────────────────────────────────────
    var previewRestore: DispatchWorkItem?

    @objc func testState(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }

        previewRestore?.cancel()

        // Signal preview mode to idle detector
        try? "1".write(toFile: PREVIEW_FLAG, atomically: true, encoding: .utf8)

        // Write preview state → picked up by next poll()
        try? s.write(toFile: PREVIEW_FILE, atomically: true, encoding: .utf8)

        // Trigger immediate refresh
        poll()

        // Restore after 3 seconds
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            try? FileManager.default.removeItem(atPath: PREVIEW_FLAG)
            try? FileManager.default.removeItem(atPath: PREVIEW_FILE)
            try? "idle".write(toFile: IDLE_FILE, atomically: true, encoding: .utf8)
            self.poll()
        }
        previewRestore = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// ── Main entry ──────────────────────────────────────────────────────
let a = NSApplication.shared
a.setActivationPolicy(.accessory)
let delegate = StatusDot()
a.delegate = delegate
a.run()

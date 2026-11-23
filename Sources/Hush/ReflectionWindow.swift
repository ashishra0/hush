import AppKit
import HushCore
import SwiftUI

/// Dark-only palette for the evening ritual (DESIGN "Full-screen reflection"); same in light and dark.
private enum Dk {
    static let ground = Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
    static let ink = Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF3 / 255)
    static let inkMute = Color(red: 0x8E / 255, green: 0x8E / 255, blue: 0x93 / 255)
    static let inkFaint = Color(red: 0x5A / 255, green: 0x5A / 255, blue: 0x5F / 255)
    static let list = Color(red: 0xC7 / 255, green: 0xC7 / 255, blue: 0xCC / 255)
    static let hairline = Color(red: 0x1F / 255, green: 0x1F / 255, blue: 0x22 / 255)
}

private final class ReflectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, e.charactersIgnoringModifiers == "w" { close(); return true }
        return super.performKeyEquivalent(with: e)
    }
}

/// Entry point: `ReflectionWindowController.shared.show(store:)`.
@MainActor
final class ReflectionWindowController {
    static let shared = ReflectionWindowController()
    private var window: NSWindow?

    func show(store: TaskStore) {
        window?.close()
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        let w = ReflectionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.setFrame(screen.frame, display: false)
        w.level = .normal
        w.backgroundColor = NSColor(srgbRed: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255, alpha: 1)
        w.isReleasedWhenClosed = false
        w.appearance = NSAppearance(named: .darkAqua)
        w.setAccessibilityLabel("Reflection")
        w.contentView = NSHostingView(rootView: ReflectionView(
            store: store,
            close: { [weak w] in w?.close() },
            history: { [weak w] in w?.close(); HistoryWindowController.shared.show(store: store) }))
        w.alphaValue = 0
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { $0.duration = Theme.reduceMotion ? 0.15 : 0.32; w.animator().alphaValue = 1 }
        window = w
    }
}

struct ReflectionView: View {
    let store: TaskStore
    let close: () -> Void
    let history: () -> Void
    @State private var summaries: [DaySummary] = [] // index = days back from today (0...6)
    @State private var week: [DayCount] = []        // 7, oldest first
    @State private var offset = 0 // 0 = today, 1 = yesterday ...
    @State private var grown = Theme.reduceMotion
    @FocusState private var focused: Bool
    private let cal = Calendar.current

    private func entries(_ off: Int) -> [HistoryEntry] { summaries.indices.contains(off) ? summaries[off].finished : [] }
    private func date(_ off: Int) -> Date { summaries.indices.contains(off) ? summaries[off].day : TaskStore.logicalDay(of: Date()) }

    var body: some View {
        let list = entries(offset), n = list.count
        let copy = summaries.indices.contains(offset) ? summaries[offset].copy : ClosureCopy.choose(doneCount: 0, openCount: 1)
        ZStack(alignment: .top) {
            Dk.ground.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.geist(size: 11, design: .monospaced)).foregroundStyle(Dk.inkFaint)
                Text(copy.headline).font(.geist(size: 64, weight: .semibold)).tracking(-1.6).foregroundStyle(Dk.ink)
                    .scaleEffect(grown ? 1 : 28.0 / 64, anchor: .topLeading).padding(.top, 28)
                Text("\(n) \(n == 1 ? "thing" : "things") finished \(offset == 0 ? "today" : "that day").")
                    .font(.geist(size: 18)).foregroundStyle(Dk.inkMute).padding(.top, 14)
                if n > 0 {
                    LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)], alignment: .leading, spacing: 10) {
                        ForEach(list.prefix(12)) { e in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(Self.time.string(from: e.task.completedAt ?? Date())).font(.geist(size: 11, design: .monospaced))
                                    .foregroundStyle(Dk.inkFaint).fixedSize().frame(width: 64, alignment: .leading)
                                Text(e.task.title).font(.geist(size: 14)).foregroundStyle(Dk.list).lineLimit(1)
                            }
                        }
                    }
                    .padding(.top, 36)
                    if n > 12 { Text("and \(n - 12) more").font(.geist(size: 12)).foregroundStyle(Dk.inkFaint) }
                }
                Text(copy.closing).font(.geist(size: 20).italic()).foregroundStyle(Dk.ink).padding(.top, 36)
                Rectangle().fill(Dk.hairline).frame(height: 1).padding(.top, 36)
                Text("THIS WEEK").font(.geist(size: 10, design: .monospaced)).foregroundStyle(Dk.inkFaint).padding(.top, 24).padding(.bottom, 12)
                WeekStrip(counts: week.enumerated().map { (cal.component(.weekday, from: $1.day), $1.count, $0 == week.count - 1) }, cal: cal)
                Text("One dot per finished task. Rest days are just quiet. There are no numbers, goal lines, or comparisons.").font(.geist(size: 12)).foregroundStyle(Dk.inkFaint).padding(.top, 12)
            }
            .id(offset)
            .transition(.opacity)
            .frame(width: 640, alignment: .leading)
            .padding(.top, 180)
            VStack {
                Spacer()
                HStack(spacing: 20) { hint("esc", "Back to list"); hint("⌘Y", "History"); hint("← →", "Other days") }
                    .padding(.bottom, 50)
            }
        }
        .animation(Theme.reduceMotion ? .easeInOut(duration: 0.15) : .easeInOut(duration: 0.32), value: offset)
        .focusable().focused($focused).focusEffectDisabled()
        .onAppear {
            focused = true
            reload()
            if !grown { withAnimation(.easeOut(duration: 0.32)) { grown = true } }
        }
        .onKeyPress(.leftArrow) { offset = min(offset + 1, 6); return .handled }
        .onKeyPress(.rightArrow) { offset = max(offset - 1, 0); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in reload() }
        .background { Button("") { history() }.keyboardShortcut("y", modifiers: .command).opacity(0) }
        .accessibilityElement(children: .contain)
    }

    private func reload() {
        let today = TaskStore.logicalDay(of: Date())
        week = (try? store.weekCounts(endingOn: today)) ?? []
        summaries = (0..<7).compactMap { off in
            cal.date(byAdding: .day, value: -off, to: today).flatMap { try? store.daySummary(for: $0) }
        }
    }

    private var label: String {
        let f = DateFormatter(); f.dateFormat = "EEEE · d MMMM"
        var s = f.string(from: date(offset)).uppercased()
        if offset == 0 { let t = DateFormatter(); t.timeStyle = .short; s += " · " + t.string(from: Date()) }
        return s
    }

    private static let time: DateFormatter = { let f = DateFormatter(); f.timeStyle = .short; return f }()

    private func hint(_ k: String, _ l: String) -> some View {
        HStack(spacing: 6) {
            Text(k).font(.geist(size: 11, design: .monospaced)).foregroundStyle(Dk.inkMute)
                .padding(.horizontal, 6).frame(minWidth: 22, minHeight: 20)
                .background(Color(red: 0x16 / 255, green: 0x16 / 255, blue: 0x18 / 255), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color(red: 0x2E / 255, green: 0x2E / 255, blue: 0x32 / 255), lineWidth: 1))
            Text(l).font(.geist(size: 12)).foregroundStyle(Dk.inkFaint)
        }
    }
}

/// 7 columns (previous 6 days + Today): a stack of 4px dots per finished task (cap 12) above a day label.
struct WeekStrip: View {
    /// (calendar weekday, finished count, isToday), oldest first.
    let counts: [(Int, Int, Bool)]
    let cal: Calendar
    private static let dk = (past: Color(red: 0x5A / 255, green: 0x5A / 255, blue: 0x5F / 255), now: Color(red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF3 / 255))

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(Array(counts.enumerated()), id: \.offset) { _, c in
                VStack(spacing: 8) {
                    VStack(spacing: 3) {
                        ForEach(0..<min(c.1, 12), id: \.self) { _ in Circle().fill(c.2 ? Self.dk.now : Self.dk.past).frame(width: 4, height: 4) }
                    }
                    Text(c.2 ? "Today" : cal.shortWeekdaySymbols[c.0 - 1]).font(.geist(size: 12, weight: c.2 ? .semibold : .regular))
                        .foregroundStyle(c.2 ? Self.dk.now : Self.dk.past)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(c.2 ? "Today" : cal.weekdaySymbols[c.0 - 1]), \(c.1) finished")
            }
        }
    }
}

import AppKit
import HushCore
import SwiftUI

/// Daily Closure card (⌘D). `ClosureCard.show(relativeTo: statusItem.button!, store: store)`.
/// Set `onHistory` to open History (⌘Y). Esc or ↵ closes.
@MainActor
enum ClosureCard {
    static var onHistory: () -> Void = {}
    private static let popover = NSPopover()

    static func show(relativeTo view: NSView, store: TaskStore) {
        
        popover.close()
        popover.behavior = .transient
        popover.animates = !Theme.reduceMotion
        let host = NSHostingController(rootView: ClosureView(store: store,
            close: { popover.close() }, reflect: { popover.close(); ReflectionWindowController.shared.show(store: store) }, history: { popover.close(); onHistory() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

struct ClosureView: View {
    let store: TaskStore
    @State private var summary: TodaySummary?
    @State private var now = Date()
    let close: () -> Void
    let reflect: () -> Void
    let history: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Group { if let summary { card(summary) } else { Color.clear.frame(width: 340, height: 1) } }
            .onAppear { reload(); schedule() }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in reload() }
            .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in reload() }
    }

    private func reload() { now = Date(); summary = try? store.todaySummary() }

    /// One timer at the next 04:00 rollover; re-arms itself.
    private func schedule() {
        let t = TaskStore.nextDayBoundary(after: Date())
        DispatchQueue.main.asyncAfter(deadline: .now() + max(t.timeIntervalSinceNow, 1)) { reload(); schedule() }
    }

    @ViewBuilder private func card(_ summary: TodaySummary) -> some View {
        let n = summary.doneCount
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.date(now)).font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            Text(summary.copy.headline).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.ink).padding(.top, Theme.s4)
            Text("\(n) \(n == 1 ? "thing" : "things") finished today.").font(.system(size: 15)).foregroundStyle(Theme.inkMute).padding(.top, Theme.s2)
            if n > 0 {
                HStack(spacing: 4) {
                    ForEach(0..<min(n, 8), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Theme.ink).frame(width: 3, height: 14)
                    }
                }
                .padding(.top, Theme.s4)
                Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, Theme.s4)
                VStack(alignment: .leading, spacing: Theme.s3) {
                    ForEach(Array(summary.latestTitles.prefix(3).enumerated()), id: \.offset) { _, t in
                        HStack(spacing: Theme.s3) {
                            Circle().fill(Theme.inkFaint.opacity(0.6)).frame(width: 12, height: 12)
                            Text(t).font(Theme.bodyFont).foregroundStyle(Theme.inkMute).lineLimit(1)
                        }
                    }
                    if n > 3 { Text("and \(n - 3) more").font(Theme.captionFont).foregroundStyle(Theme.inkFaint).padding(.leading, 24) }
                }
                .padding(.top, Theme.s4)
            }
            Text(summary.copy.closing).font(.system(size: 15).italic()).foregroundStyle(Theme.ink).padding(.top, Theme.s4)
            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, Theme.s4)
            HStack(spacing: Theme.s4) {
                hint("↵", "Reflect"); Spacer(); hint("⌘Y", "History")
            }
            .padding(.top, Theme.s3)
        }
        .padding(Theme.s6 - 2)
        .frame(width: 340, alignment: .leading)
        .background(Theme.surface)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.return) { reflect(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .background { Button("") { history() }.keyboardShortcut("y", modifiers: .command).opacity(0) }
    }

    private static func date(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE · d MMMM"; return f.string(from: d).uppercased()
    }

    private func hint(_ k: String, _ l: String) -> some View {
        HStack(spacing: 6) { Keycap(text: k); Text(l).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
    }
}

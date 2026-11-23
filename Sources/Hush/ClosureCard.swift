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
        guard let summary = try? store.todaySummary() else { return }
        popover.close()
        popover.behavior = .transient
        popover.animates = !Theme.reduceMotion
        let host = NSHostingController(rootView: ClosureView(summary: summary, now: Date(),
            close: { popover.close() }, reflect: { popover.close(); ReflectionWindowController.shared.show(store: store) }, history: { popover.close(); onHistory() }))
        host.sizingOptions = [.preferredContentSize]
        popover.contentViewController = host
        NSApp.activate()
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

struct ClosureView: View {
    let summary: TodaySummary
    let now: Date
    let close: () -> Void
    let reflect: () -> Void
    let history: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        let n = summary.doneCount
        VStack(alignment: .leading, spacing: Theme.s3) {
            Text(Self.date(now)).font(.system(size: 10, design: .monospaced)).foregroundStyle(Theme.inkFaint)
            Text(summary.copy.headline).font(.system(size: 28, weight: .light)).foregroundStyle(Theme.ink)
            Text("\(n) \(n == 1 ? "thing" : "things") finished today.").font(Theme.bodyFont).foregroundStyle(Theme.inkMute)
            if n > 0 {
                HStack(spacing: 3) {
                    ForEach(0..<min(n, 8), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1).fill(Theme.ink).frame(width: 14, height: 3)
                    }
                }
                VStack(alignment: .leading, spacing: Theme.s1) {
                    ForEach(Array(summary.latestTitles.prefix(3).enumerated()), id: \.offset) { _, t in
                        Text(t).font(Theme.bodyFont).foregroundStyle(Theme.inkMute).lineLimit(1)
                    }
                    if n > 3 { Text("and \(n - 3) more").font(Theme.captionFont).foregroundStyle(Theme.inkFaint) }
                }
            }
            Text(summary.copy.closing).font(Theme.bodyFont.italic()).foregroundStyle(Theme.inkMute)
            Rectangle().fill(Theme.hairline).frame(height: 1)
            HStack(spacing: Theme.s4) {
                hint("↵", "Reflect"); Spacer(); hint("⌘Y", "History")
            }
        }
        .padding(Theme.s4)
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
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate("EEEEdMMMM"); return f.string(from: d).uppercased()
    }

    private func hint(_ k: String, _ l: String) -> some View {
        HStack(spacing: 6) { Keycap(text: k); Text(l).font(Theme.captionFont).foregroundStyle(Theme.inkMute) }
    }
}

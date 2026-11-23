import AppKit
import SwiftUI

struct RecentTask: Identifiable, Equatable {
    let id: Int64
    let title: String
    let createdAt: Date
}

/// View state + callbacks for the menu bar popover. Swap placeholder data for the real store by
/// assigning `recent` / `openCount` and the closures; the view holds no persistence.
@Observable
final class PopoverModel {
    var recent: [RecentTask] = []
    var openCount = 0
    var shortcut = ""
    var onCapture: () -> Void = {}
    var onComplete: (RecentTask) -> Void = { _ in }
    var onOpenOutline: () -> Void = {}
    var onHistory: () -> Void = {}
    var onSettings: () -> Void = {}
    var onQuit: () -> Void = {}
}

struct PopoverView: View {
    let model: PopoverModel

    var body: some View {
        VStack(spacing: 0) {
            Button(action: model.onCapture) {
                HStack {
                    Text("Capture a task…").font(Theme.bodyFont).foregroundStyle(Theme.inkFaint)
                    Spacer()
                    Keycap(text: model.shortcut)
                }
                .padding(.horizontal, Theme.s3)
                .frame(height: 36)
                .background(Theme.surfaceSunk, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(Theme.s3)

            HStack {
                Text("RECENT").font(Theme.keycapFont).tracking(0.6)
                Spacer()
                Text("\(model.recent.count) of \(model.openCount) open").font(Theme.captionFont)
            }
            .foregroundStyle(Theme.inkFaint)
            .padding(.horizontal, Theme.s4)
            .padding(.bottom, Theme.s1)

            if model.recent.isEmpty {
                Text("All clear.")
                    .font(Theme.bodyFont).foregroundStyle(Theme.inkMute)
                    .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                    .padding(.horizontal, Theme.s4)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.recent) { task in
                        RecentRow(task: task, complete: { model.onComplete(task) }, open: model.onOpenOutline)
                    }
                }
                .padding(.horizontal, Theme.s2)
            }

            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.top, Theme.s2)
            VStack(spacing: 0) {
                FooterRow(title: "Open outline", keys: "⌘O", action: model.onOpenOutline)
                    .keyboardShortcut("o", modifiers: .command)
                FooterRow(title: "History", keys: "⌘Y", action: model.onHistory)
                    .keyboardShortcut("y", modifiers: .command)
                FooterRow(title: "Settings…", keys: "⌘,", action: model.onSettings)
                    .keyboardShortcut(",", modifiers: .command)
                FooterRow(title: "Quit Hush", keys: "⌘Q", action: model.onQuit)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .padding(Theme.s2)
        }
        .frame(width: 320)
        .background(Theme.surface)
    }
}

private struct RecentRow: View {
    let task: RecentTask
    let complete: () -> Void
    let open: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Button(action: complete) {
                Circle().strokeBorder(Theme.inkFaint, lineWidth: 1.5).frame(width: 14, height: 14)
                    .frame(width: 22, height: 22).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Complete \(task.title)")
            Text(task.title).font(.system(size: 13)).foregroundStyle(Theme.ink).lineLimit(1)
            Spacer(minLength: Theme.s2)
            Text(Self.relative(task.createdAt)).font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, Theme.s2)
        .frame(height: 30)
        .background(hover ? Theme.surfaceSunk : .clear, in: RoundedRectangle(cornerRadius: Theme.rRow))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
        .onHover { hover = $0 }
    }

    static func relative(_ d: Date) -> String {
        let s = Int(Date().timeIntervalSince(d))
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(s / 60)m"
        case ..<86400: return "\(s / 3600)h"
        case ..<(7 * 86400): return "\(s / 86400)d"
        default: return d.formatted(.dateTime.day().month(.abbreviated)) // D10: "20 Nov"
        }
    }
}

private struct FooterRow: View {
    let title: String
    let keys: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(Theme.bodyFont).foregroundStyle(Theme.ink)
                Spacer()
                Text(keys).font(Theme.keycapFont).foregroundStyle(Theme.inkFaint)
            }
            .padding(.horizontal, Theme.s2)
            .frame(height: 28)
            .background(hover ? Theme.surfaceSunk : .clear, in: RoundedRectangle(cornerRadius: Theme.rRow))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

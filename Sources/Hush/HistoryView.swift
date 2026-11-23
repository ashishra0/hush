import AppKit
import HushCore
import SwiftUI

/// One block in the History list: a day with finished tasks, or a quiet span (D17).
struct HistorySection: Identifiable {
    let id: Date
    let title: String
    let right: String
    let entries: [HistoryEntry]
}

enum HistoryLayout {
    /// Builds headers per D16 and quiet spans per D17 from the real `HistoryDay.day` dates.
    static func sections(_ days: [HistoryDay], now: Date, calendar cal: Calendar) -> [HistorySection] {
        let today = cal.startOfDay(for: now.addingTimeInterval(-Double(TaskStore.dayBoundaryHour) * 3600))
        var list: [(Date, [HistoryEntry])] = days.map { ($0.day, $0.entries) }
        if list.first.map({ $0.0 < today }) ?? true { list.insert((today, []), at: 0) }
        var out: [HistorySection] = []
        for (i, (day, entries)) in list.enumerated() {
            out.append(section(day, entries, today: today, cal: cal))
            guard i + 1 < list.count else { continue }
            let next = list[i + 1].0
            let gap = cal.dateComponents([.day], from: next, to: day).day ?? 0
            let missing = (1..<max(gap, 1)).compactMap { cal.date(byAdding: .day, value: -$0, to: day) }
            if missing.count == 1 {
                out.append(section(missing[0], [], today: today, cal: cal))
            } else if missing.count == 2, cal.component(.weekday, from: missing[0]) == 1, cal.component(.weekday, from: missing[1]) == 7 {
                out.append(HistorySection(id: missing[1], title: header(missing[1], today: today, cal: cal), right: "A quiet weekend", entries: []))
            }
        }
        return out
    }

    private static func section(_ day: Date, _ entries: [HistoryEntry], today: Date, cal: Calendar) -> HistorySection {
        HistorySection(id: day, title: header(day, today: today, cal: cal),
                       right: entries.isEmpty ? "A quiet day" : "\(entries.count) finished", entries: entries)
    }

    static func header(_ day: Date, today: Date, cal: Calendar) -> String {
        let ago = cal.dateComponents([.day], from: day, to: today).day ?? 0
        if ago == 0 { return "Today" }
        let f = DateFormatter()
        f.calendar = cal
        if ago < 7 { f.dateFormat = "EEEE" }
        else { f.setLocalizedDateFormatFromTemplate(cal.isDate(day, equalTo: today, toGranularity: .year) ? "EEEEdMMMM" : "EEEEdMMMMyyyy") }
        return f.string(from: day)
    }
}

@Observable
@MainActor
final class HistoryModel {
    var days: [HistoryDay] = []
    var selected: TaskID?
    var onRestore: (TaskID) -> Void = { _ in }
    var onHome: () -> Void = {}
    var onClose: () -> Void = {}

    var flat: [HistoryEntry] { days.flatMap(\.entries) }

    func move(_ d: Int) {
        let ids = flat.map(\.id)
        guard !ids.isEmpty else { return }
        let i = selected.flatMap { ids.firstIndex(of: $0) }
        selected = ids[min(max((i ?? (d > 0 ? -1 : ids.count)) + d, 0), ids.count - 1)]
    }

    func restoreSelected() {
        guard let id = selected else { return }
        // Land on the neighbour once the row leaves.
        let ids = flat.map(\.id)
        if let i = ids.firstIndex(of: id) { selected = i + 1 < ids.count ? ids[i + 1] : (i > 0 ? ids[i - 1] : nil) }
        onRestore(id)
    }
}

struct HistoryView: View {
    @Bindable var model: HistoryModel
    @FocusState private var focused: Bool
    private let cal = Calendar.current
    private static let time: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()

    var body: some View {
        let sections = HistoryLayout.sections(model.days, now: Date(), calendar: cal)
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.hairline).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Finished").font(.system(size: 36, weight: .light)).foregroundStyle(Theme.ink)
                            Spacer()
                            Text("Kept forever, on this Mac").font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
                        }
                        .padding(.bottom, Theme.s4)
                        ForEach(sections) { sec in
                            HStack {
                                Text(sec.title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text(sec.right).font(Theme.captionFont).foregroundStyle(Theme.inkFaint)
                            }
                            .padding(.horizontal, Theme.s2)
                            .padding(.top, Theme.s4).padding(.bottom, Theme.s1)
                            ForEach(sec.entries) { e in
                                HistoryRow(entry: e, time: Self.time.string(from: e.task.completedAt ?? Date()),
                                           selected: model.selected == e.id,
                                           restore: { model.selected = e.id; model.restoreSelected() })
                                    .id(e.id)
                                    .onTapGesture { model.selected = e.id }
                            }
                        }
                    }
                    .frame(width: 720)
                    .padding(.vertical, Theme.s6)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: model.selected) { _, id in if let id { proxy.scrollTo(id) } }
            }
        }
        .background(Theme.surface)
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { model.move(-1); return .handled }
        .onKeyPress(.downArrow) { model.move(1); return .handled }
        .onKeyPress(.escape) { model.onClose(); return .handled }
        .background {
            Button("") { model.restoreSelected() }.keyboardShortcut("r", modifiers: .command).opacity(0)
            Button("") { model.onHome() }.keyboardShortcut("[", modifiers: .command).opacity(0)
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.s2) {
            Button { model.onHome() } label: { Text("Home").foregroundStyle(Theme.inkMute) }.buttonStyle(.plain)
            Text("/").foregroundStyle(Theme.inkFaint)
            Text("History").foregroundStyle(Theme.ink)
            Spacer()
        }
        .font(Theme.bodyFont)
        .padding(.leading, 80) // clear the traffic lights
        .frame(height: 52)
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let time: String
    let selected: Bool
    let restore: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: Theme.s3) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 15)).foregroundStyle(Theme.inkFaint)
            Text(entry.task.title).font(Theme.rowFont).foregroundStyle(Theme.inkMute).lineLimit(1)
            if !entry.path.isEmpty {
                Text(entry.path.joined(separator: " › ")).font(Theme.captionFont).foregroundStyle(Theme.inkFaint).lineLimit(1)
            }
            Spacer(minLength: Theme.s2)
            if hover || selected {
                Button(action: restore) {
                    HStack(spacing: 6) {
                        Text("Restore").font(Theme.captionFont).foregroundStyle(Theme.ink)
                        Keycap(text: "⌘R")
                    }
                }
                .buttonStyle(.plain)
            }
            Text(time).font(Theme.keycapFont).foregroundStyle(Theme.inkFaint)
        }
        .padding(.horizontal, Theme.s2)
        .frame(height: Theme.rowHeight)
        .background(selected ? Theme.accentWash : (hover ? Theme.surfaceSunk : .clear), in: RoundedRectangle(cornerRadius: Theme.rRow))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

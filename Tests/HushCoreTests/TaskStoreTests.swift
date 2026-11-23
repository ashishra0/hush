import Foundation
import Testing
@testable import HushCore

final class Clock: @unchecked Sendable {
    var t = Date(timeIntervalSince1970: 1_700_000_000)
    func tick(_ s: TimeInterval = 1) { t += s }
}

private func make() throws -> (TaskStore, Clock) {
    let c = Clock()
    return (try TaskStore.inMemory(now: { c.t }), c)
}
private func titles(_ s: TaskStore, _ root: TaskID? = nil) throws -> [String] { try s.outline(root: root).map(\.task.title) }

private var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
private func date(_ d: Int, _ h: Int, _ m: Int) -> Date { utc.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))! }

@Test func inboxExistsAndIsProtected() throws {
    let (s, _) = try make()
    let inbox = try s.inbox()
    #expect(inbox.isInbox && inbox.title == "Inbox" && inbox.parentID == nil)
    #expect(throws: HushError.inboxProtected) { try s.complete(inbox.id) }
    #expect(throws: HushError.inboxProtected) { try s.delete(inbox.id) }
    #expect(throws: HushError.inboxProtected) { try s.update(inbox.id, title: "x") }
    #expect(throws: HushError.inboxProtected) { try s.move(inbox.id, newParent: nil) }
    #expect(throws: HushError.inboxProtected) { try s.outdent(inbox.id) }
    #expect(try s.openCount() == 0)
    #expect(try s.recent(limit: 5).isEmpty)
}

@Test func createOrdersAndInsertsAfter() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b")
    try s.create(title: "mid", after: a.id)
    #expect(try titles(s) == ["Inbox", "a", "mid", "b"])
    #expect(try s.outline().map(\.task.position) == [0, 1, 2, 3])
    _ = b
}

@Test func indentOutdentEdges() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b")
    #expect(throws: HushError.cannotIndent) { try s.indent(try s.inbox().id) }
    try s.indent(b.id)
    #expect(try titles(s, a.id) == ["b"])
    try s.outdent(b.id)
    #expect(try titles(s) == ["Inbox", "a", "b"])
    #expect(throws: HushError.cannotOutdent) { try s.outdent(a.id) }
    let c = try s.create(title: "c", parent: a.id)
    #expect(throws: HushError.cannotIndent) { try s.indent(c.id) }
}

@Test func indentGoesToEndOfPreviousSibling() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b")
    try s.create(title: "a1", parent: a.id)
    try s.indent(b.id)
    #expect(try titles(s, a.id) == ["a1", "b"])
}

@Test func moveUpDownAndMove() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b"), c = try s.create(title: "c")
    #expect(try s.moveUp(c.id))
    #expect(try titles(s) == ["Inbox", "a", "c", "b"])
    #expect(try s.moveDown(b.id) == false)
    #expect(try s.moveDown(a.id))
    #expect(try titles(s) == ["Inbox", "c", "a", "b"])
    try s.move(b.id, newParent: a.id)
    try s.move(c.id, newParent: a.id, index: 0)
    #expect(try titles(s, a.id) == ["c", "b"])
    #expect(throws: HushError.invalidMove) { try s.move(a.id, newParent: b.id) }
    #expect(throws: HushError.invalidMove) { try s.move(a.id, newParent: a.id) }
}

@Test func completeAndUndoWithDescendants() throws {
    let (s, c) = try make()
    let p = try s.create(title: "p")
    let k1 = try s.create(title: "k1", parent: p.id), k2 = try s.create(title: "k2", parent: p.id)
    c.tick(); _ = try s.complete(k1.id)         // earlier completion, must survive undo of parent
    c.tick()
    let r = try s.complete(p.id)
    #expect(Set(r.ids) == [p.id, k2.id])
    #expect(try titles(s) == ["Inbox"])
    #expect(try s.openCount() == 0)
    try s.undoComplete(r)
    #expect(try titles(s, p.id) == ["k2"])
    #expect(try s.task(k1.id).completedAt != nil)
    #expect(try s.task(p.id).completedAt == nil)
}

@Test func completeHidesFromRecentAndShiftsSiblings() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"); try s.create(title: "b")
    _ = try s.complete(a.id)
    #expect(try s.recent(limit: 5).map(\.title) == ["b"])
    #expect(try s.outline().map(\.task.position) == [0, 1])
}

@Test func deleteAndUndo() throws {
    let (s, _) = try make()
    let p = try s.create(title: "p"); let k = try s.create(title: "k", parent: p.id)
    let r = try s.delete(p.id)
    #expect(Set(r.ids) == [p.id, k.id])
    #expect(try titles(s) == ["Inbox"])
    #expect(throws: HushError.notFound(p.id)) { try s.task(p.id) }
    try s.undoDelete(r)
    #expect(try titles(s) == ["Inbox", "p"])
    #expect(try titles(s, p.id) == ["k"])
}

@Test func restorePlacement() throws {
    let (s, _) = try make()
    let p = try s.create(title: "p")
    let k = try s.create(title: "k", parent: p.id)
    try s.create(title: "other", parent: p.id)
    _ = try s.complete(k.id)
    let back = try s.restore(fromHistory: k.id)
    #expect(back.parentID == p.id)
    #expect(try titles(s, p.id) == ["other", "k"])          // appended at end
    // parent completed too -> nearest open ancestor (top level)
    let g = try s.create(title: "g"), m = try s.create(title: "m", parent: g.id)
    _ = try s.complete(m.id); _ = try s.complete(g.id)
    #expect(try s.restore(fromHistory: m.id).parentID == nil)
    #expect(try titles(s).last == "m")
}

@Test func historyGroupsByDayWith4amBoundary() throws {
    let (s, c) = try make()
    let ids = try (0..<4).map { try s.create(title: "t\($0)").id }
    for (id, when) in zip(ids, [date(20, 3, 59), date(20, 4, 0), date(21, 3, 59), date(21, 12, 0)]) {
        c.t = when; _ = try s.complete(id)
    }
    let h = try s.history(calendar: utc)
    #expect(h.map(\.day) == [date(21, 0, 0), date(20, 0, 0), date(19, 0, 0)])
    #expect(h.map { $0.entries.map(\.task.title) } == [["t3"], ["t2", "t1"], ["t0"]])
}

@Test func todaySummaryAndPath() throws {
    let (s, c) = try make()
    let w = try s.create(title: "Work")
    let ids = try (1...4).map { try s.create(title: "d\($0)", parent: w.id).id }
    c.t = date(20, 3, 0); _ = try s.complete(ids[0])           // previous logical day
    for (i, id) in ids.dropFirst().enumerated() { c.t = date(20, 9 + i, 0); _ = try s.complete(id) }
    let sum = try s.todaySummary(now: date(21, 2, 0), calendar: utc)   // still "today" (before 04:00)
    #expect(sum.doneCount == 3 && sum.latestTitles == ["d4", "d3", "d2"])
    #expect(try s.todaySummary(now: date(21, 5, 0), calendar: utc).doneCount == 0)
    #expect(try s.history(calendar: utc)[0].entries[0].path == ["Work"])
}

@Test func searchEscapesAndFilters() throws {
    let (s, _) = try make()
    let a = try s.create(title: "100% done", note: "x"); try s.create(title: "milk")
    #expect(try s.search("100%").map(\.id) == [a.id])
    #expect(try s.search("MILK").count == 1)
    _ = try s.complete(a.id)
    #expect(try s.search("100").isEmpty)
}

@Test func freshFileDatabaseMigratesAndPersists() throws {
    let path = NSTemporaryDirectory() + "hush-\(UUID().uuidString).sqlite"
    defer { try? FileManager.default.removeItem(atPath: path) }
    do { let s = try TaskStore(path: path); try s.create(title: "kept") }
    let s2 = try TaskStore(path: path)
    #expect(try titles(s2) == ["Inbox", "kept"])
    #expect(try s2.outline().filter(\.task.isInbox).count == 1)
}

@Test func titleAndNoteValidation() throws {
    let (s, _) = try make()
    #expect(try s.create(title: "  a\nb  ").title == "a b")
    #expect(throws: HushError.emptyTitle) { try s.create(title: " \n ") }
    #expect(throws: HushError.titleTooLong) { try s.create(title: String(repeating: "x", count: 501)) }
    #expect(try s.create(title: String(repeating: "x", count: 500)).title.count == 500)
    #expect(throws: HushError.noteTooLong) { try s.create(title: "n", note: String(repeating: "x", count: 10_001)) }
    let t = try s.create(title: "t")
    #expect(throws: HushError.emptyTitle) { try s.update(t.id, title: "") }
    #expect(throws: HushError.noteTooLong) { try s.update(t.id, note: String(repeating: "x", count: 10_001)) }
    #expect(try s.update(t.id, title: " new\ntitle ").title == "new title")
    #expect(try titles(s).last == "new title")
}

@Test func openDescendantCounts() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b", parent: a.id)
    try s.create(title: "c", parent: b.id); try s.create(title: "i", parent: s.inbox().id)
    #expect(try s.openDescendantCount() == 4)
    #expect(try s.openDescendantCount(of: a.id) == 2)
    #expect(try s.openDescendantCount(of: b.id) == 1)
    let n = try s.outline().first { $0.task.id == a.id }!
    #expect(n.openDescendantCount == 2 && n.openChildCount == 1)
    _ = try s.complete(b.id)
    #expect(try s.openDescendantCount(of: a.id) == 0)
}

@Test func nothingDisplacesInbox() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b")
    #expect(try s.moveUp(a.id) == false)
    try s.move(b.id, newParent: nil, index: 0)
    #expect(try titles(s) == ["Inbox", "b", "a"])
    let k = try s.create(title: "k", parent: a.id)
    try s.outdent(k.id)
    #expect(try s.outline().first?.task.isInbox == true)
    try s.indent(a.id)                       // a goes into b, fine
    #expect(try s.outline().first?.task.isInbox == true)
    #expect(throws: HushError.invalidMove) { try s.move(b.id, newParent: a.id) }  // a is inside b
}

@Test func historyCappedAt500() throws {
    let (s, c) = try make()
    for i in 0..<510 { c.tick(); let t = try s.create(title: "t\(i)"); _ = try s.complete(t.id) }
    let h = try s.history(calendar: utc)
    #expect(h.reduce(0) { $0 + $1.entries.count } == 500)
    #expect(h[0].entries[0].task.title == "t509")
    #expect(h[0].day == utc.startOfDay(for: h[0].day))
}

@Test func restoreFallsBackThroughAncestors() throws {
    let (s, _) = try make()
    let g = try s.create(title: "g"), p = try s.create(title: "p", parent: g.id), k = try s.create(title: "k", parent: p.id)
    _ = try s.complete(k.id); _ = try s.complete(p.id)         // p completed, g open
    #expect(try s.restore(fromHistory: k.id).parentID == g.id)
    #expect(try s.task(p.id).completedAt != nil)                // single task only
}

@Test func collapsedPersists() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a")
    try s.setCollapsed(a.id, true)
    #expect(try s.task(a.id).collapsed)
}

@Test func undoRedoRestoresExactPlace() throws {
    let (s, _) = try make()
    #expect(try s.undo().isEmpty && !s.canUndo && !s.canRedo)
    let a = try s.create(title: "a"), b = try s.create(title: "b"), c = try s.create(title: "c")
    let k = try s.create(title: "k", parent: b.id)
    try s.undo()                                            // create k
    #expect(try titles(s, b.id).isEmpty)
    try s.redo()
    #expect(try titles(s, b.id) == ["k"])
    try s.indent(c.id)                                      // c -> under b after k
    #expect(try titles(s, b.id) == ["k", "c"])
    try s.undo()
    #expect(try titles(s) == ["Inbox", "a", "b", "c"])
    try s.outdent(k.id); try s.undo()
    #expect(try titles(s, b.id) == ["k"])
    try s.move(c.id, newParent: nil, index: 1); try s.undo()
    #expect(try titles(s) == ["Inbox", "a", "b", "c"])
    try s.update(a.id, title: "A", note: "n"); try s.undo()
    #expect(try s.task(a.id).title == "a" && s.task(a.id).note == "")
    _ = try s.moveDown(a.id); try s.undo()
    #expect(try titles(s) == ["Inbox", "a", "b", "c"])
}

@Test func undoCompleteDeleteCascadeAndRedoClears() throws {
    let (s, _) = try make()
    let p = try s.create(title: "p"); let k = try s.create(title: "k", parent: p.id)
    _ = try s.complete(p.id)
    #expect(try titles(s) == ["Inbox"])
    try s.undo()
    #expect(try titles(s, p.id) == ["k"])
    _ = try s.delete(p.id); try s.undo()
    #expect(try titles(s, p.id) == ["k"])
    try s.redo()
    #expect(try titles(s) == ["Inbox"])
    try s.undo()
    #expect(s.canRedo)
    try s.create(title: "new")                              // new action clears redo
    #expect(!s.canRedo)
    try s.setCollapsed(k.id, true)                          // not undoable
    let n = try s.undo(); #expect(n.count == 1)
    #expect(try s.task(k.id).collapsed)
}

@Test func undoStackCappedAt100() throws {
    let (s, _) = try make()
    for i in 0..<120 { try s.create(title: "t\(i)") }
    var n = 0
    while !(try s.undo().isEmpty) { n += 1 }
    #expect(n == 100)
}

@Test func searchParentsPrefix() throws {
    let (s, _) = try make()
    let w = try s.create(title: "Work"); try s.create(title: "Workout", parent: w.id); try s.create(title: "Home")
    let r = try s.searchParents(prefix: "wo")
    #expect(r.map(\.task.title) == ["Workout", "Work"] && r[0].path == ["Work"])
    #expect(try s.searchParents(prefix: " ").isEmpty && s.searchParents(prefix: "ork").isEmpty)
    #expect(try s.searchParents(prefix: "i").map(\.task.title) == ["Inbox"])
}

@Test func todaySummaryOpenCountAndClosureCopy() throws {
    let (s, c) = try make()
    let t = try s.create(title: "x"); try s.create(title: "y")
    c.t = date(20, 9, 0); _ = try s.complete(t.id)
    let sum = try s.todaySummary(now: date(20, 10, 0), calendar: utc)
    #expect(sum.doneCount == 1 && sum.openCount == 1 && sum.copy.headline == "One thing, done.")
    #expect(ClosureCopy.choose(doneCount: 0, openCount: 3).headline == "A quiet day.")
    #expect(ClosureCopy.choose(doneCount: 3, openCount: 3).headline == "Steady progress.")
    #expect(ClosureCopy.choose(doneCount: 6, openCount: 1).headline == "A good day's work.")
    #expect(ClosureCopy.choose(doneCount: 9, openCount: 0).headline == "All clear.")
}

@Test func randomOpsKeepOrderGapFreeAndAncestorsOpen() throws {
    let (s, _) = try make()
    var seed: UInt64 = 42
    func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int(seed >> 33) % n }
    func flat(_ ns: [OutlineNode]) -> [OutlineNode] { ns.flatMap { [$0] + flat($0.children) } }
    for i in 0..<300 {
        let all = flat(try s.outline()).filter { !$0.task.isInbox }.map(\.task.id)
        let pick = all.isEmpty ? nil : all[rnd(all.count)]
        switch rnd(9) {
        case 0, 1: try s.create(title: "n\(i)", parent: rnd(2) == 0 ? nil : pick)
        case 2: if let p = pick { try? s.indent(p) }
        case 3: if let p = pick { try? s.outdent(p) }
        case 4: if let p = pick { _ = try? s.moveUp(p) }
        case 5: if let p = pick { try? s.move(p, newParent: all.isEmpty ? nil : all[rnd(all.count)], index: rnd(4)) }
        case 6: if let p = pick, rnd(3) == 0 { _ = try s.complete(p) }
        case 7: if let p = pick, rnd(3) == 0 { _ = try s.delete(p) }
        default: try s.undo()
        }
        func check(_ ns: [OutlineNode]) {
            #expect(ns.map(\.task.position) == Array(0..<ns.count))
            ns.forEach { check($0.children) }
        }
        check(try s.outline())
    }
    // every open task is reachable from the outline => no open task hides under a completed/deleted ancestor
    #expect(flat(try s.outline()).filter { !$0.task.isInbox }.count == (try s.openCount()))
}

private var ny: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/New_York")!; return c }
private func nyDate(_ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    ny.date(from: DateComponents(year: 2026, month: m, day: d, hour: h, minute: min))!
}

@Test func dayBoundaryIsCorrectOnDSTDays() throws {
    for (m, d) in [(3, 8), (11, 1)] {                      // spring forward, fall back
        let (s, c) = try make()
        let ids = try (0..<4).map { try s.create(title: "t\($0)").id }
        for (id, when) in zip(ids, [nyDate(m, d, 3, 59), nyDate(m, d, 4), nyDate(m, d + 1, 3, 59), nyDate(m, d + 1, 4)]) {
            c.t = when; _ = try s.complete(id)
        }
        let h = try s.history(calendar: ny)
        #expect(h.map { $0.entries.map(\.task.title) } == [["t3"], ["t2", "t1"], ["t0"]])
        #expect(h[1].day == ny.startOfDay(for: nyDate(m, d, 12)))
        #expect(try s.todaySummary(now: nyDate(m, d, 4, 30), calendar: ny).doneCount == 2)
        #expect(try s.todaySummary(now: nyDate(m, d, 3, 30), calendar: ny).doneCount == 1)
        #expect(try s.todaySummary(now: nyDate(m, d + 1, 3, 30), calendar: ny).doneCount == 2)
    }
}

@Test func deleteKeepsCompletedDescendantsInHistory() throws {
    let (s, c) = try make()
    let p = try s.create(title: "p"), done = try s.create(title: "done", parent: p.id), open = try s.create(title: "open", parent: p.id)
    c.t = date(20, 9, 0); _ = try s.complete(done.id)
    let r = try s.delete(p.id)
    #expect(Set(r.ids) == [p.id, open.id])
    #expect(try s.history(calendar: utc).first?.entries.map(\.task.title) == ["done"])
    #expect(try s.todaySummary(now: date(20, 10, 0), calendar: utc).doneCount == 1)
    try s.undo()
    #expect(try s.task(done.id).completedAt != nil && s.task(open.id).completedAt == nil)
    try s.redo(); try s.undoDelete(r)
    #expect(try s.task(done.id).completedAt != nil && titles(s, p.id) == ["open"])
}

@Test func restoreKeepsUndoStacks() throws {
    let (s, _) = try make()
    let a = try s.create(title: "a"), b = try s.create(title: "b")
    _ = try s.complete(a.id); _ = try s.complete(b.id)
    try s.undo()                                            // b back
    try s.restore(fromHistory: a.id)
    #expect(s.canUndo && s.canRedo)
    try s.redo()                                            // b completed again
    #expect(try titles(s) == ["Inbox", "a"])
}

@Test func observeDeliversInitialAndChangedSnapshots() async throws {
    let (s, _) = try make()
    let (stream, cont) = AsyncStream<MenuBarSnapshot>.makeStream()
    let sub = s.observeMenuBar(limit: 5) { cont.yield($0) }
    var it = stream.makeAsyncIterator()
    #expect(await it.next()?.openCount == 0)
    try s.create(title: "x")
    var last: MenuBarSnapshot?
    while let snap = await it.next() { last = snap; if snap.openCount == 1 { break } }
    #expect(last?.recent.map(\.title) == ["x"])
    sub.cancel()
}

@Test func daySummaryAnyDayAndWeekCounts() throws {
    let (s, c) = try make()
    let w = try s.create(title: "Work")
    let ids = try (0..<5).map { try s.create(title: "t\($0)", parent: w.id).id }
    for (id, when) in zip(ids, [date(18, 10, 0), date(19, 3, 0), date(20, 9, 0), date(20, 15, 0), date(21, 2, 0)]) {
        c.t = when; _ = try s.complete(id)
    }
    let d = try s.daySummary(for: date(20, 0, 0), calendar: utc)
    #expect(d.day == date(20, 0, 0) && d.doneCount == 3)
    #expect(d.finished.map(\.task.title) == ["t4", "t3", "t2"] && d.finished[0].path == ["Work"])
    #expect(d.finished[0].task.completedAt == date(21, 2, 0) && d.latestTitles == ["t4", "t3", "t2"])
    #expect(d.openCount == 1 && d.copy.headline == "Steady progress.")
    #expect(try s.daySummary(for: date(25, 12, 0), calendar: utc).doneCount == 0)
    let wk = try s.weekCounts(endingOn: date(21, 0, 0), calendar: utc)
    #expect(wk.count == 7 && wk.first!.day == date(15, 0, 0) && wk.last!.day == date(21, 0, 0))
    #expect(wk.map(\.count) == [0, 0, 0, 2, 0, 3, 0])
}

@Test func nextOpenTaskPreOrder() throws {
    let (s, _) = try make()
    let inbox = try s.inbox().id
    let i1 = try s.create(title: "i1", parent: inbox)
    let a = try s.create(title: "a"), a1 = try s.create(title: "a1", parent: a.id), b = try s.create(title: "b")
    #expect(try s.nextOpenTask(after: inbox)?.id == i1.id)
    #expect(try s.nextOpenTask(after: i1.id)?.id == a.id)
    #expect(try s.nextOpenTask(after: a.id)?.id == a1.id)
    #expect(try s.nextOpenTask(after: a.id, skippingSubtree: true)?.id == b.id)
    #expect(try s.nextOpenTask(after: b.id) == nil)
    #expect(try s.nextOpenTask(after: a1.id, within: a.id) == nil)
    _ = try s.complete(a.id)                                           // already completed: still finds b
    #expect(try s.nextOpenTask(after: a.id)?.id == b.id)
    #expect(throws: HushError.notFound(i1.id)) { try s.nextOpenTask(after: i1.id, within: b.id) }
}

@Test func findWithAncestorsAndRanges() throws {
    let (s, _) = try make()
    let w = try s.create(title: "Work"), p = try s.create(title: "Plan Q4", parent: w.id)
    try s.create(title: "plan the PLAN", parent: p.id); try s.create(title: "other")
    let r = try s.find("plan")
    #expect(r.map(\.task.title) == ["Plan Q4", "plan the PLAN"])
    #expect(r[1].ancestors.map(\.title) == ["Work", "Plan Q4"] && r[1].ranges.count == 2)
    #expect(String(r[1].task.title[r[1].ranges[1]]) == "PLAN")
    #expect(try s.find("plan", root: p.id).map(\.task.title) == ["plan the PLAN"])
    #expect(try s.find("plan", root: p.id)[0].ancestors.isEmpty && s.find("  ").isEmpty && s.find("zzz").isEmpty)
}

@Test func findHistoryAndBoundary() throws {
    let (s, c) = try make()
    let a = try s.create(title: "Write report"), b = try s.create(title: "call"), d = try s.create(title: "Report bug")
    c.t = date(20, 9, 0); _ = try s.complete(a.id); _ = try s.complete(b.id)
    c.t = date(21, 9, 0); _ = try s.complete(d.id)
    let h = try s.findHistory("REPORT", calendar: utc)
    #expect(h.map { $0.entries.map(\.task.title) } == [["Report bug"], ["Write report"]])
    #expect(try s.findHistory("", calendar: utc).isEmpty)
    #expect(TaskStore.nextDayBoundary(after: date(20, 3, 0), calendar: utc) == date(20, 4, 0))
    #expect(TaskStore.nextDayBoundary(after: date(20, 4, 0), calendar: utc) == date(21, 4, 0))
    #expect(TaskStore.logicalDay(of: date(20, 3, 59), utc) == date(19, 0, 0))
}

import XCTest
import SwiftData
import NostrCore
import GratefulDayCore
@testable import GratefulDay

/// MEASUREMENT ONLY (branch `measure/backlog-first-sync`, never merged).
///
/// How long does a guest journal with a 60-day backlog take to reach the
/// account on its first sync, once a new account is connected? Seth asked for
/// the number, with no optimisation; method approved by Chief (P121).
///
/// Skipped unless `GD_MEASURE_BACKLOG=1` (pass `TEST_RUNNER_GD_MEASURE_BACKLOG=1`
/// to `xcodebuild test`). It publishes to REAL relays, so CI must never set it.
///
/// What it mirrors, step for step, from `GratefulDayApp`:
/// - 60 guest days written with `JournalRepository(activeOwner: nil).save`,
///   as Today does with no account.
/// - "Create a key" through `AccountModel.createKey` (the app's own
///   `NostrKeys.generatePrivateKey`), with a `KeyVault` over the in-memory
///   `FakeKeychain`, so the key never reaches the system Keychain.
/// - `onChange(of: account.activeOwner)` → `readFromRelays()`: the first pass
///   (`SyncService.start` via `runner`). It defers with `.notAllowedYet`.
/// - The spec A sheet's Continue (`acceptDisclosure`): `PublishDisclosure.accept()`
///   (the `setFlag` path), then `readFromRelays()` again. The person's reading
///   time is taken as zero.
/// - Every later pass is started by the app's own scheduler
///   (`scheduleAfterPass` → retry after the earliest backoff, at least 30 s →
///   `runner`), with `isForeground`/`isActive` true as in an open app. The
///   test starts no pass of its own after the disclosure.
/// - `SyncService(transport: WebSocketTransport())`: real relays, real relay
///   discovery (kind 10002 on the five bootstrap relays), real write set.
@MainActor
final class BacklogFirstSyncMeasurement: XCTestCase {
    private static let backlogDays = 60
    private static let capSeconds: TimeInterval = 15 * 60
    private static let pollInterval: Duration = .milliseconds(20)

    private struct Pass {
        var index: Int
        var startedAt: TimeInterval
        var endedAt: TimeInterval?
        var outcome = "running"
        var syncedBefore = 0
        var syncedAfter = 0
        var publish = ""
        /// host → outcome name → count, from the "sent" lines.
        var sends: [String: [String: Int]] = [:]
        /// host → outcome name → count, from the "read before send" lines.
        var reads: [String: [String: Int]] = [:]
        var relayList = ""
        var writeHosts = ""
        var retry = ""
    }

    func testBacklogFirstSync() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GD_MEASURE_BACKLOG"] == "1",
                          "Measurement only: set TEST_RUNNER_GD_MEASURE_BACKLOG=1 to run (publishes to real relays).")
        let runs = max(1, Int(ProcessInfo.processInfo.environment["GD_MEASURE_RUNS"] ?? "") ?? 1)
        for run in 1...runs {
            try await measure(run: run)
        }
    }

    // MARK: - One run

    private func measure(run: Int) async throws {
        // A fresh store, Keychain and service per run: nothing carries over.
        let config = ModelConfiguration(schema: JournalStore.schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: JournalStore.schema, configurations: config)
        let context = container.mainContext
        let account = AccountModel(vault: KeyVault(keychain: FakeKeychain()))
        account.refresh(context: context)
        XCTAssertEqual(account.state, .guest)

        // 60 guest days, one per day, ending yesterday, as Today saves them.
        let guestRepo = JournalRepository(context: context, activeOwner: nil)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        let noonToday = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now)!
        var dates: Set<String> = []
        for n in 1...Self.backlogDays {
            let instant = cal.date(byAdding: .day, value: -n, to: noonToday)!
            let day = JournalDay(containing: instant, timeZone: .current)
            let marker = String(format: "%016llx", UInt64.random(in: .min ... .max))
            try guestRepo.save(text: "P1VAL backlog d\(n) \(marker)", for: day)
            dates.insert(day.dateString)
        }
        XCTAssertEqual(dates.count, Self.backlogDays)
        let guests = try context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.ownerPubkey == nil }))
        XCTAssertEqual(guests.count, Self.backlogDays)

        // The app's service, as `GratefulDayApp` builds it outside UI tests.
        let sync = SyncService(transport: WebSocketTransport())
        sync.isForeground = true
        sync.isActive = true
        SyncLog.clearRecent()

        // Connect: "Create a key" on a guest journal.
        let owner: String
        do { owner = try account.createKey(context: context) } catch { XCTFail("createKey failed: \(error)"); return }
        XCTAssertEqual(account.activeOwner, owner)
        let npub = NostrKeys.data(hex: owner).flatMap { try? NostrKeys.npub($0) } ?? "npub?"
        print("P1VAL-BACKLOG run=\(run) identity=\(npub) pub=\(owner.prefix(8))")

        // `installRunner()` and `readFromRelays()`: the key is read back from
        // the vault for each pass, exactly as the app does.
        sync.runner = { [weak sync] in
            guard let sync, let key = account.connectedKey() else { return }
            let owner = key.pubkey
            sync.start(owner: owner, secret: key.secret, context: context) {
                account.activeOwner == owner
            }
        }
        sync.publishAllowed = {
            guard let owner = account.activeOwner else { return false }
            return (try? PublishDisclosure(context: context, owner: owner).isAccepted()) ?? false
        }

        func syncedCount() -> Int {
            let o: String? = owner, raw = SyncState.synced.rawValue
            let rows = (try? context.fetch(FetchDescriptor<JournalEntry>(
                predicate: #Predicate { $0.ownerPubkey == o && $0.syncStateRaw == raw && $0.deletedAt == nil }))) ?? []
            return rows.filter { dates.contains($0.dateString) }.count
        }

        // Clock starts at connect, as the first pass is started
        // (`onChange(of: account.activeOwner)` → `readFromRelays()`).
        let clock = ContinuousClock()
        let t0 = clock.now
        func elapsed() -> TimeInterval {
            let d = clock.now - t0
            return TimeInterval(d.components.seconds) + TimeInterval(d.components.attoseconds) / 1e18
        }
        sync.runner?()

        var passes: [Pass] = []
        var accepted = false
        var finishedAt: TimeInterval?
        var stopReason = "cap"
        var stallSince: TimeInterval?

        while elapsed() < Self.capSeconds {
            try? await Task.sleep(for: Self.pollInterval)
            // Drain the sync log (fixed stage names, hosts, outcome names,
            // counts and 8-char event ids only: never keys or text).
            let lines = SyncLog.recent
            SyncLog.clearRecent()
            let now = elapsed()
            for line in lines {
                if line == "pass started" {
                    passes.append(Pass(index: passes.count + 1, startedAt: now, syncedBefore: syncedCount()))
                    continue
                }
                guard !passes.isEmpty else { continue }
                let i = passes.count - 1
                if line.hasPrefix("pass finished") || line.hasPrefix("pass stopped") {
                    passes[i].endedAt = now
                    if line.hasPrefix("pass stopped") {
                        passes[i].outcome = "stopped(\(Self.detail(line)))"
                    } else if passes[i].outcome == "running" {
                        passes[i].outcome = "finished"
                    }
                    passes[i].publish = Self.detail(line)
                    passes[i].syncedAfter = syncedCount()
                } else if line.hasPrefix("publishing deferred") {
                    passes[i].outcome = "deferred(\(Self.detail(line)))"
                } else if line.hasPrefix("relay list read") {
                    passes[i].relayList = Self.detail(line)
                } else if line.hasPrefix("relay set") {
                    if let r = line.range(of: "write: ") { passes[i].writeHosts = String(line[r.upperBound...]) }
                } else if line.hasPrefix("sent:") {
                    Self.tally(line, into: &passes[i].sends)
                } else if line.hasPrefix("read before send") {
                    Self.tally(line, into: &passes[i].reads)
                } else if line.hasPrefix("retry scheduled") {
                    passes[i].retry = Self.detail(line)
                }
            }

            let synced = syncedCount()
            if synced >= Self.backlogDays {
                finishedAt = now
                stopReason = "all synced"
                break
            }
            let running = sync.status == .reading
            // Spec A sheet → Continue, the moment the first pass defers on it.
            if !accepted, !running, sync.publishDeferral == .notAllowedYet {
                try PublishDisclosure(context: context, owner: owner).accept()
                accepted = true
                stallSince = nil
                sync.runner?()   // `acceptDisclosure()` → `readFromRelays()`
                continue
            }
            // Nothing running and nothing scheduled: the app would now wait
            // for a return to the foreground or Try now, which are the
            // person's actions. Report a partial result after a grace period.
            if !running, !sync.retryPending, passes.last?.endedAt != nil {
                if stallSince == nil { stallSince = now }
                if let s = stallSince, now - s > 2 {
                    stopReason = "stalled (no automatic trigger pending; deferral=\(sync.publishDeferral.map { "\($0)" } ?? "none"))"
                    break
                }
            } else {
                stallSince = nil
            }
        }

        // Leave nothing running: as the app does on going to the background.
        sync.isForeground = false
        sync.stop()

        let synced = syncedCount()
        let seconds = finishedAt ?? elapsed()
        let allWrite = Set(passes.map(\.writeHosts).filter { !$0.isEmpty })
        for p in passes {
            let dur = p.endedAt.map { String(format: "%.2f", $0 - p.startedAt) } ?? "unfinished"
            print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) start=\(String(format: "%.2f", p.startedAt)) seconds=\(dur) "
                + "outcome=\(p.outcome) synced_in_pass=\(p.syncedAfter - p.syncedBefore) synced_total=\(p.syncedAfter) "
                + "write=\(p.writeHosts.isEmpty ? "unknown" : p.writeHosts.replacingOccurrences(of: " ", with: ","))")
            if !p.relayList.isEmpty { print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) relay_list: \(p.relayList)") }
            if !p.publish.isEmpty { print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) publish: \(p.publish)") }
            if !p.reads.isEmpty { print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) read_before_send: \(Self.render(p.reads))") }
            if !p.sends.isEmpty { print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) sends: \(Self.render(p.sends))") }
            if !p.retry.isEmpty { print("P1VAL-BACKLOG-PASS run=\(run) pass=\(p.index) retry_scheduled: \(p.retry)") }
        }
        print("P1VAL-BACKLOG run=\(run) days=\(Self.backlogDays) synced=\(synced) seconds=\(String(format: "%.2f", seconds)) "
            + "passes=\(passes.count) write=\(allWrite.sorted().joined(separator: "|").replacingOccurrences(of: " ", with: ",")) "
            + "result=\(synced >= Self.backlogDays ? "complete" : "partial") stop=\"\(stopReason)\"")
        // A partial result is still a result: reported, not failed.
        if synced < Self.backlogDays {
            XCTExpectFailure("Partial result: \(synced)/\(Self.backlogDays) synced (\(stopReason))", strict: false) {
                XCTFail("run \(run): \(synced)/\(Self.backlogDays) synced")
            }
        }
    }

    // MARK: - Log parsing

    private static func detail(_ line: String) -> String {
        guard let r = line.range(of: ": ") else { return "" }
        return String(line[r.upperBound...])
    }

    private static let outcome = try! NSRegularExpression(
        pattern: #"([A-Za-z0-9.\-]+)=(OK|answered|timedOut|rejected|failed|closed|unresolved)"#)

    /// Count each `host=outcome` in a line (a reason in parentheses is dropped).
    private static func tally(_ line: String, into counts: inout [String: [String: Int]]) {
        let ns = line as NSString
        for m in outcome.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            let host = ns.substring(with: m.range(at: 1)), name = ns.substring(with: m.range(at: 2))
            counts[host, default: [:]][name, default: 0] += 1
        }
    }

    private static func render(_ counts: [String: [String: Int]]) -> String {
        counts.keys.sorted().map { host in
            "\(host)[" + counts[host]!.keys.sorted().map { "\($0)=\(counts[host]![$0]!)" }.joined(separator: ",") + "]"
        }.joined(separator: " ")
    }
}

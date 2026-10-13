import Foundation
import SQLite3
import SwiftData

// Q367: the Mac store copy-test CLI. Driven by `plan/release/mac-store-copytest.sh`, which copies
// the prod Mac stores to a temp dir first. This tool opens ONLY that copy:
//
//   1. BEFORE: reads the copied SQLite files raw (schema-agnostic, so it sees the OLD build's
//      columns, e.g. `ZUNLINKEDNAMES` before Q116's `originalName` rename) and counts.
//   2. AFTER: opens the same copy with this build's SwiftData models (`PipelineFile` for the
//      local store, `MemoCloudStore.schema` for the CloudKit mirror), which runs the lightweight
//      migration, and counts the same things through the model API.
//   3. Prints counts only (never a title, a name or any text) and exits 1 if any count dropped.
//
// CloudKit is never touched: both containers open with `cloudKitDatabase: .none`, and
// `MemoCloudStore.container` (the CloudKit one) is never evaluated.
//
// Exit codes: 0 no drop, 1 a count dropped, 2 usage or open error, 3 refused path.

// MARK: - Arguments

struct CopyTestArgs {
    var local: URL?
    var cloud: URL?
    var makeSynthetic: URL?
    var corpus: URL?
    var simulateDrop = false
    var requireNonzero = false

    init(_ argv: [String]) {
        var i = 1
        func next() -> URL? {
            i += 1
            guard i < argv.count else { return nil }
            return URL(fileURLWithPath: (argv[i] as NSString).expandingTildeInPath)
        }
        while i < argv.count {
            switch argv[i] {
            case "--local": local = next()
            case "--cloud": cloud = next()
            case "--make-synthetic": makeSynthetic = next()
            case "--corpus": corpus = next()
            case "--simulate-drop": simulateDrop = true
            case "--require-nonzero": requireNonzero = true
            default: copyTestFail(2, "unknown argument \(argv[i])")
            }
            i += 1
        }
    }
}

func copyTestFail(_ code: Int32, _ message: String) -> Never {
    FileHandle.standardError.write(Data("store-copytest: \(message)\n".utf8))
    exit(code)
}

// MARK: - The guard: never the real store

enum CopyTestGuard {
    /// The copy's directory must hold this file. The script writes it into the fresh temp dir;
    /// the real Application Support folder never has it.
    static let marker = ".skrift-copytest"

    static func normalized(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased()
    }

    /// The real stores' folders (prod `Skrift`, `Skrift Dev`), plus any extra roots from
    /// `SKRIFT_COPYTEST_PROTECTED` (colon-separated; the self-test protects its synthetic source).
    static var protectedRoots: [String] {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        var roots = [base.appendingPathComponent("Skrift", isDirectory: true),
                     base.appendingPathComponent("Skrift Dev", isDirectory: true)]
        if let extra = ProcessInfo.processInfo.environment["SKRIFT_COPYTEST_PROTECTED"] {
            roots += extra.split(separator: ":").map { URL(fileURLWithPath: String($0), isDirectory: true) }
        }
        return roots.map(normalized)
    }

    /// Refuses (exit 3) before any file is opened. `needsMarker` is false only for the
    /// synthetic generator, which writes a fresh store.
    static func check(_ url: URL, needsMarker: Bool = true) {
        let path = normalized(url)
        for root in protectedRoots where path == root || path.hasPrefix(root + "/") {
            copyTestFail(3, "REFUSED: \(url.path) is inside a protected store folder; pass a COPY")
        }
        if needsMarker {
            let marker = url.deletingLastPathComponent().appendingPathComponent(marker)
            guard FileManager.default.fileExists(atPath: marker.path) else {
                copyTestFail(3, "REFUSED: no \(CopyTestGuard.marker) beside \(url.lastPathComponent); only the script's temp copy is opened")
            }
        }
    }
}

// MARK: - Counting rules (one copy, used by both phases)

struct CopyTestCounts {
    var rows: [(label: String, value: Int)] = []
    mutating func add(_ label: String, _ value: Int) { rows.append((label, value)) }
    func value(_ label: String) -> Int? { rows.first { $0.label == label }?.value }
}

enum CopyTestRule {
    /// Live people across every NamesRecord carrier, deduped by canonical name.
    static func people(blobs: [Data]) -> Int {
        var live = Set<String>()
        for blob in blobs {
            guard let names = try? JSONDecoder().decode(NamesData.self, from: blob) else { continue }
            for p in names.people where !p.isDeleted { live.insert(p.canonical.lowercased()) }
        }
        return live.count
    }

    /// The same precedence as `PipelineFile.nameResolutions`: the shared blob wins, else the
    /// legacy unlinked list + picks JSON.
    static func resolutions(shared: Data?, legacyUnlinked: [String], legacyPicks: Data?) -> NameResolutions {
        if shared != nil { return NameResolutions.decode(shared) }
        let picks = legacyPicks.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        return NameResolutions(unlinkedNames: legacyUnlinked, namePicks: picks)
    }

    static func decisions(_ r: [NameResolutions]) -> Int { r.reduce(0) { $0 + $1.unlinkedNames.count + $1.namePicks.count } }
    static func unlinked(_ r: [NameResolutions]) -> Int { r.reduce(0) { $0 + $1.unlinkedNames.count } }

    /// A raw `[String]` column. SwiftData's on-disk encoding is not documented, so try the
    /// encodings Core Data uses for it.
    static func stringArray(_ data: Data?) -> [String] {
        guard let data, !data.isEmpty else { return [] }
        if let a = try? JSONDecoder().decode([String].self, from: data) { return a }
        if let a = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String] { return a }
        if let a = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(ofClass: NSString.self, from: data) { return a.map { $0 as String } }
        return []
    }
}

enum CopyTestLabel {
    static let localNotes = "local notes (PipelineFile)"
    static let localDecisions = "name decisions, local notes"
    static let localUnlinked = "unlinked names, local notes"
    static let cloudNotes = "synced notes (Memo)"
    static let assets = "note assets (MemoAsset)"
    static let enhancements = "enhancements (MemoEnhancement)"
    static let people = "people (NamesRecord, live)"
    static let cloudDecisions = "name decisions, synced notes"
    static let cloudUnlinked = "unlinked names, synced notes"
}

// MARK: - BEFORE: raw SQLite on the copy

final class CopyTestRawStore {
    private var db: OpaquePointer?

    init(_ url: URL) {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            copyTestFail(2, "OPEN FAILED (raw): \(url.lastPathComponent)")
        }
    }
    deinit { sqlite3_close(db) }

    private func query(_ sql: String, _ row: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            copyTestFail(2, "raw query failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW { row(stmt) }
    }

    /// Core Data's table for a SwiftData entity: `Z` + the class name, upper-cased.
    func hasTable(_ entity: String) -> Bool {
        var found = false
        query("SELECT name FROM sqlite_master WHERE type='table' AND name='Z\(entity.uppercased())'") { _ in found = true }
        return found
    }

    func columns(_ entity: String) -> Set<String> {
        var cols = Set<String>()
        query("PRAGMA table_info(Z\(entity.uppercased()))") { s in cols.insert(String(cString: sqlite3_column_text(s, 1))) }
        return cols
    }

    func count(_ entity: String) -> Int {
        guard hasTable(entity) else { return 0 }
        var n = 0
        query("SELECT COUNT(*) FROM Z\(entity.uppercased())") { s in n = Int(sqlite3_column_int64(s, 0)) }
        return n
    }

    /// The listed columns of every row; a column the table lacks reads as nil.
    func blobs(_ entity: String, _ wanted: [String]) -> [[Data?]] {
        guard hasTable(entity) else { return [] }
        let have = columns(entity)
        let select = wanted.map { have.contains($0) ? $0 : "NULL" }.joined(separator: ", ")
        var out: [[Data?]] = []
        query("SELECT \(select) FROM Z\(entity.uppercased())") { s in
            out.append((0..<wanted.count).map { i in
                guard sqlite3_column_type(s, Int32(i)) != SQLITE_NULL else { return nil }
                let n = Int(sqlite3_column_bytes(s, Int32(i)))
                guard n > 0, let p = sqlite3_column_blob(s, Int32(i)) else { return Data() }
                return Data(bytes: p, count: n)
            })
        }
        return out
    }
}

func countBefore(local: URL, cloud: URL?) -> CopyTestCounts {
    var c = CopyTestCounts()
    do {
        let raw = CopyTestRawStore(local)
        let cols = raw.columns("PipelineFile")
        // The rename (Q116/Q252): before the new build migrates, the legacy columns still carry
        // their OLD names; after, the new ones. Read whichever this store has.
        let unlinkedCol = cols.contains("ZLEGACYUNLINKEDNAMES") ? "ZLEGACYUNLINKEDNAMES" : "ZUNLINKEDNAMES"
        let picksCol = cols.contains("ZLEGACYNAMEPICKSJSON") ? "ZLEGACYNAMEPICKSJSON" : "ZNAMEPICKSJSON"
        let res = raw.blobs("PipelineFile", ["ZNAMERESOLUTIONSDATA", unlinkedCol, picksCol]).map {
            CopyTestRule.resolutions(shared: $0[0], legacyUnlinked: CopyTestRule.stringArray($0[1]), legacyPicks: $0[2])
        }
        c.add(CopyTestLabel.localNotes, raw.count("PipelineFile"))
        c.add(CopyTestLabel.localDecisions, CopyTestRule.decisions(res))
        c.add(CopyTestLabel.localUnlinked, CopyTestRule.unlinked(res))
    }
    if let cloud {
        let raw = CopyTestRawStore(cloud)
        let res = raw.blobs("Memo", ["ZNAMERESOLUTIONSDATA"]).map { NameResolutions.decode($0[0]) }
        c.add(CopyTestLabel.cloudNotes, raw.count("Memo"))
        c.add(CopyTestLabel.assets, raw.count("MemoAsset"))
        c.add(CopyTestLabel.enhancements, raw.count("MemoEnhancement"))
        c.add(CopyTestLabel.people, CopyTestRule.people(blobs: raw.blobs("NamesRecord", ["ZBLOB"]).compactMap { $0[0] }))
        c.add(CopyTestLabel.cloudDecisions, CopyTestRule.decisions(res))
        c.add(CopyTestLabel.cloudUnlinked, CopyTestRule.unlinked(res))
    }
    return c
}

// MARK: - AFTER: this build's models on the copy

func localContainer(_ url: URL) throws -> ModelContainer {
    // Same model + options as the app's `SharedStore.container` (SkriftDesktopApp.swift).
    try ModelContainer(for: PipelineFile.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
}

func cloudContainer(_ url: URL) throws -> ModelContainer {
    // The app's own schema (`MemoCloudStore.schema`), CloudKit OFF.
    let schema = MemoCloudStore.schema
    return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
}

func countAfter(local: URL, cloud: URL?, simulateDrop: Bool) -> CopyTestCounts {
    var c = CopyTestCounts()
    do {
        let container: ModelContainer
        do { container = try localContainer(local) } catch { copyTestFail(2, "OPEN FAILED (new build, local store): \(error)") }
        let ctx = ModelContext(container)
        let files = (try? ctx.fetch(FetchDescriptor<PipelineFile>())) ?? []
        let res = files.map(\.nameResolutions)
        c.add(CopyTestLabel.localNotes, (try? ctx.fetchCount(FetchDescriptor<PipelineFile>())) ?? -1)
        c.add(CopyTestLabel.localDecisions, CopyTestRule.decisions(res))
        c.add(CopyTestLabel.localUnlinked, CopyTestRule.unlinked(res))
    }
    if let cloud {
        let container: ModelContainer
        do { container = try cloudContainer(cloud) } catch { copyTestFail(2, "OPEN FAILED (new build, synced store): \(error)") }
        let ctx = ModelContext(container)
        if simulateDrop, let victim = try? ctx.fetch(FetchDescriptor<Memo>()).first {
            ctx.delete(victim)   // self-test only: proves a drop exits 1
            try? ctx.save()
        }
        let memos = (try? ctx.fetch(FetchDescriptor<Memo>())) ?? []
        let res = memos.map { NameResolutions.decode($0.nameResolutionsData) }
        let records = (try? ctx.fetch(FetchDescriptor<NamesRecord>())) ?? []
        c.add(CopyTestLabel.cloudNotes, memos.count)
        c.add(CopyTestLabel.assets, (try? ctx.fetchCount(FetchDescriptor<MemoAsset>())) ?? -1)
        c.add(CopyTestLabel.enhancements, (try? ctx.fetchCount(FetchDescriptor<MemoEnhancement>())) ?? -1)
        c.add(CopyTestLabel.people, CopyTestRule.people(blobs: records.map(\.blob)))
        c.add(CopyTestLabel.cloudDecisions, CopyTestRule.decisions(res))
        c.add(CopyTestLabel.cloudUnlinked, CopyTestRule.unlinked(res))
    }
    return c
}

// MARK: - Synthetic store (self-test only)

/// Builds a local + synced store pair from the synthetic corpus in `dir`, with name decisions
/// in both the shared blob and the legacy columns, and a NamesRecord roster.
func makeSynthetic(in dir: URL, corpus: URL) {
    #if DEBUG
    CopyTestGuard.check(dir.appendingPathComponent("x"), needsMarker: false)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cloudURL = dir.appendingPathComponent("memo_cloud.store")
    let localURL = dir.appendingPathComponent("skrift.store")
    do {
        let cloud = try cloudContainer(cloudURL)
        let cctx = ModelContext(cloud)
        let result = try CorpusSeed.seed(from: corpus, into: cctx,
                                         recordingsDirectory: dir.appendingPathComponent("synthetic-recordings"))
        let roster = (try? JSONDecoder().decode([Person].self, from: Data(contentsOf: corpus.appendingPathComponent("names.json")))) ?? []
        let blob = try JSONEncoder().encode(NamesData(lastModifiedAt: ISO8601.string(from: Date()), people: roster))
        cctx.insert(NamesRecord(blob: blob))
        let memos = try cctx.fetch(FetchDescriptor<Memo>(sortBy: [SortDescriptor(\.recordedAt)]))
        for (i, m) in memos.enumerated() where i % 4 == 0 {
            m.nameResolutionsData = NameResolutions(unlinkedNames: ["synthetic-\(i)"], namePicks: ["alias\(i)": ""]).encoded
        }
        try cctx.save()

        let local = try localContainer(localURL)
        let lctx = ModelContext(local)
        for (i, m) in memos.enumerated() {
            let f = PipelineFile(id: m.id.uuidString, filename: "synthetic-\(i)")
            switch i % 3 {
            case 0:   // legacy columns only (what an older Mac wrote)
                f.legacyUnlinkedNames = ["legacy-\(i)", "legacy-b-\(i)"]
                f.legacyNamePicksJSON = try JSONEncoder().encode(["pick\(i)": "[[Synthetic \(i)]]"])
            case 1:   // the shared blob
                f.nameResolutions = NameResolutions(unlinkedNames: ["shared-\(i)"], namePicks: [:])
            default: break
            }
            lctx.insert(f)
        }
        try lctx.save()
        print("synthetic store: \(memos.count) notes, \(result.enhancements) enhancements, \(roster.count) people")
    } catch {
        copyTestFail(2, "synthetic build failed: \(error)")
    }
    #else
    copyTestFail(2, "--make-synthetic needs a Debug build (CorpusSeed is DEBUG-only)")
    #endif
}

// MARK: - Main

enum StoreCopyTestMain {
    static func run() -> Never {
        // Counts only: keep Core Data's SQL logging off whatever the defaults say (SQLDebug 3+
        // would echo bound row values, i.e. note text, to stderr).
        UserDefaults.standard.setVolatileDomain(["com.apple.CoreData.SQLDebug": 0,
                                                 "com.apple.CoreData.MigrationDebug": 0],
                                                forName: UserDefaults.argumentDomain)
        let args = CopyTestArgs(CommandLine.arguments)

        if let dir = args.makeSynthetic {
            guard let corpus = args.corpus else { copyTestFail(2, "--make-synthetic needs --corpus <test-fixtures/corpus>") }
            makeSynthetic(in: dir, corpus: corpus)
            exit(0)
        }

        guard let local = args.local else {
            copyTestFail(2, "usage: StoreCopyTest --local <copy>/skrift.store [--cloud <copy>/memo_cloud.store]")
        }
        CopyTestGuard.check(local)
        if let cloud = args.cloud { CopyTestGuard.check(cloud) }
        for url in [local] + (args.cloud.map { [$0] } ?? []) where !FileManager.default.fileExists(atPath: url.path) {
            copyTestFail(2, "missing \(url.lastPathComponent) in the copy")
        }

        let before = countBefore(local: local, cloud: args.cloud)
        let after = countAfter(local: local, cloud: args.cloud, simulateDrop: args.simulateDrop)

        var dropped = false
        var empty = false
        let width = before.rows.map(\.label.count).max() ?? 20
        print("count".padding(toLength: width, withPad: " ", startingAt: 0) + "   before    after")
        for row in before.rows {
            let a = after.value(row.label) ?? -1
            if a < row.value { dropped = true }
            if row.value == 0 { empty = true }
            let flag = a < row.value ? "   DROP" : (a > row.value ? "   (grew)" : "")
            print(row.label.padding(toLength: width, withPad: " ", startingAt: 0)
                  + String(format: " %8d %8d", row.value, a) + flag)
        }
        if dropped { print("RESULT: DROP (a count fell after opening with this build)"); exit(1) }
        // Self-test only: every count must be non-zero, or the test proved nothing.
        if args.requireNonzero && empty { print("RESULT: EMPTY (a synthetic count was zero)"); exit(2) }
        print("RESULT: OK (no count dropped)")
        exit(0)
    }
}

StoreCopyTestMain.run()

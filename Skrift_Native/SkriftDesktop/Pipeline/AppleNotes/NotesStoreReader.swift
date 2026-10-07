import Foundation
import SQLite3

/// One note as the triage sees it. `id` is `ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER`, the UUID Notes
/// shares across the user's devices (Q72): the ONLY key a decision is ever stored under, so a
/// rename or an edit never makes a declined note look new.
struct AppleNoteSummary: Identifiable, Equatable, Sendable {
    var id: String
    /// `Z_PK` of the note row, a per-store handle used only to fetch its body and tags.
    var pk: Int64
    var title: String
    var snippet: String
    /// nil = the store has no usable creation date → "Date unknown" (Q141 / C76), never today.
    var created: Date?
    var modified: Date?
    var isLocked: Bool
}

/// Q333 (route 1, signed in mocks/Q71-apple-notes-triage-v3.html): the Mac reads Apple Notes'
/// own database. Reads a COPY of `NoteStore.sqlite` (+ `-wal`, `-shm`) in a temp folder, opened
/// read-only; the live store is never opened and never written (Q76: "never write NoteStore.sqlite").
///
/// Column names drift across macOS releases (creation date lives in `ZCREATIONDATE1/2/3`, the
/// note link in `ZNOTE` or `ZNOTE1`), so every optional column is looked up in
/// `PRAGMA table_info` first and left out of the query when absent.
final class NotesStoreReader {

    struct Failure: Error, LocalizedError, Equatable {
        enum Kind: Equatable { case denied, missing, cannotOpen, schema }
        var kind: Kind
        var detail: String
        var errorDescription: String? {
            switch kind {
            case .denied: return "Skrift is not allowed to read your Notes yet. \(detail)"
            case .missing: return "No Apple Notes database was found. \(detail)"
            case .cannotOpen: return "Could not open the Notes database copy. \(detail)"
            case .schema: return "The Notes database has an unexpected layout. \(detail)"
            }
        }
    }

    static var defaultStoreURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.notes/NoteStore.sqlite")
    }

    private var db: OpaquePointer?
    private let workDir: URL
    private var noteCols: Set<String> = []
    private var objCols: Set<String> = []

    /// Copies `source` (and its WAL/SHM when present), then opens the copy read-only.
    init(copying source: URL = NotesStoreReader.defaultStoreURL) throws {
        let fm = FileManager.default
        workDir = fm.temporaryDirectory.appendingPathComponent("skrift-notes-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: workDir, withIntermediateDirectories: true)
        let dest = workDir.appendingPathComponent("NoteStore.sqlite")
        do {
            try fm.copyItem(at: source, to: dest)
        } catch {
            try? fm.removeItem(at: workDir)
            throw Self.classify(copyError: error, source: source)
        }
        for suffix in ["-wal", "-shm"] {
            let s = URL(fileURLWithPath: source.path + suffix)
            if fm.fileExists(atPath: s.path) { try? fm.copyItem(at: s, to: URL(fileURLWithPath: dest.path + suffix)) }
        }
        if sqlite3_open_v2(dest.path, &db, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite3_open_v2 failed"
            sqlite3_close(db); db = nil
            try? fm.removeItem(at: workDir)
            throw Failure(kind: .cannotOpen, detail: msg)
        }
        noteCols = columns(of: "ZICNOTEDATA")
        objCols = columns(of: "ZICCLOUDSYNCINGOBJECT")
        guard noteCols.contains("ZDATA"), noteCols.contains("ZNOTE"),
              objCols.contains("ZIDENTIFIER"), objCols.contains("Z_PK") else {
            sqlite3_close(db); db = nil
            try? fm.removeItem(at: workDir)
            throw Failure(kind: .schema, detail: "ZICNOTEDATA.ZDATA / ZICCLOUDSYNCINGOBJECT.ZIDENTIFIER not found.")
        }
    }

    deinit {
        if let db { sqlite3_close(db) }
        try? FileManager.default.removeItem(at: workDir)
    }

    static func classify(copyError error: Error, source: URL) -> Failure {
        let ns = error as NSError
        let posix = (ns.userInfo[NSUnderlyingErrorKey] as? NSError).flatMap { $0.domain == NSPOSIXErrorDomain ? Int32($0.code) : nil }
            ?? (ns.domain == NSPOSIXErrorDomain ? Int32(ns.code) : nil)
        let denied = posix == EPERM || posix == EACCES
            || ns.code == NSFileReadNoPermissionError || ns.code == NSFileWriteNoPermissionError
        if denied {
            return Failure(kind: .denied, detail: "Give Skrift Full Disk Access in System Settings > Privacy & Security, then try again. (\(ns.localizedDescription))")
        }
        if ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError {
            return Failure(kind: .missing, detail: source.path)
        }
        return Failure(kind: .cannotOpen, detail: ns.localizedDescription)
    }

    // MARK: - listing

    /// Every live note: not in the trash folder, not marked for deletion. Locked notes are
    /// returned flagged (`isLocked`) so the UI can say how many stayed behind; the triage never offers them.
    func listNotes() throws -> [AppleNoteSummary] {
        let created = ["ZCREATIONDATE3", "ZCREATIONDATE1", "ZCREATIONDATE2", "ZCREATIONDATE"].filter { objCols.contains($0) }
        let modified = ["ZMODIFICATIONDATE1", "ZMODIFICATIONDATE"].filter { objCols.contains($0) }
        let createdExpr = created.isEmpty ? "NULL" : "COALESCE(" + created.map { "o.\($0)" }.joined(separator: ",") + ")"
        let modifiedExpr = modified.isEmpty ? "NULL" : "COALESCE(" + modified.map { "o.\($0)" }.joined(separator: ",") + ")"
        let titleExpr = objCols.contains("ZTITLE1") ? "o.ZTITLE1" : "NULL"
        let snippetExpr = objCols.contains("ZSNIPPET") ? "o.ZSNIPPET" : "NULL"
        let lockedExpr = objCols.contains("ZISPASSWORDPROTECTED") ? "COALESCE(o.ZISPASSWORDPROTECTED,0)" : "0"
        var wheres = ["o.ZIDENTIFIER IS NOT NULL"]
        if objCols.contains("ZMARKEDFORDELETION") { wheres.append("COALESCE(o.ZMARKEDFORDELETION,0) = 0") }
        var join = ""
        if objCols.contains("ZFOLDER"), objCols.contains("ZFOLDERTYPE") {
            join = "LEFT JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = o.ZFOLDER"
            wheres.append("COALESCE(f.ZFOLDERTYPE,0) <> 1")   // 1 = Recently Deleted
        }
        let sql = """
            SELECT o.Z_PK, o.ZIDENTIFIER, \(titleExpr), \(snippetExpr), \(createdExpr), \(modifiedExpr), \(lockedExpr)
            FROM ZICNOTEDATA d JOIN ZICCLOUDSYNCINGOBJECT o ON o.Z_PK = d.ZNOTE \(join)
            WHERE \(wheres.joined(separator: " AND "))
            """
        var out: [AppleNoteSummary] = []
        try query(sql) { st in
            guard let idc = sqlite3_column_text(st, 1) else { return }
            out.append(AppleNoteSummary(
                id: String(cString: idc), pk: sqlite3_column_int64(st, 0),
                title: Self.text(st, 2) ?? "Untitled", snippet: Self.text(st, 3) ?? "",
                created: Self.coreDataDate(st, 4), modified: Self.coreDataDate(st, 5),
                isLocked: sqlite3_column_int(st, 6) != 0))
        }
        return out
    }

    /// The decoded body of one note, with its inline tags resolved. nil = the blob is missing,
    /// encrypted (a locked note) or did not parse.
    func content(of note: AppleNoteSummary) -> NotesBodyDecoder.Decoded? {
        guard !note.isLocked else { return nil }
        var data: Data?
        try? query("SELECT ZDATA FROM ZICNOTEDATA WHERE ZNOTE = \(note.pk) LIMIT 1") { st in
            if let p = sqlite3_column_blob(st, 0) {
                data = Data(bytes: p, count: Int(sqlite3_column_bytes(st, 0)))
            }
        }
        guard let data else { return nil }
        return NotesBodyDecoder.decode(zdata: data, altText: inlineAltText(forNote: note.pk))
    }

    /// `identifier → "#tag"` for the note's inline hashtag / mention / link attachments.
    private func inlineAltText(forNote pk: Int64) -> [String: String] {
        let noteCols = ["ZNOTE", "ZNOTE1"].filter { objCols.contains($0) }
        let utiCols = ["ZTYPEUTI", "ZTYPEUTI1"].filter { objCols.contains($0) }
        guard !noteCols.isEmpty, !utiCols.isEmpty else { return [:] }
        var textParts: [String] = []
        if objCols.contains("ZALTTEXT") { textParts.append("ZALTTEXT") }
        if objCols.contains("ZTOKENCONTENTIDENTIFIER") { textParts.append("'#' || ZTOKENCONTENTIDENTIFIER") }
        guard !textParts.isEmpty else { return [:] }
        let sql = """
            SELECT ZIDENTIFIER, COALESCE(\(textParts.joined(separator: ","))) FROM ZICCLOUDSYNCINGOBJECT
            WHERE (\(noteCols.map { "\($0) = \(pk)" }.joined(separator: " OR ")))
              AND (\(utiCols.map { "\($0) LIKE 'com.apple.notes.inlinetextattachment.%'" }.joined(separator: " OR ")))
            """
        var out: [String: String] = [:]
        try? query(sql) { st in
            if let a = Self.text(st, 0), let b = Self.text(st, 1) { out[a] = b }
        }
        return out
    }

    // MARK: - SQLite plumbing

    private func columns(of table: String) -> Set<String> {
        var out: Set<String> = []
        try? query("PRAGMA table_info(\(table))") { st in
            if let n = Self.text(st, 1) { out.insert(n) }
        }
        return out
    }

    private func query(_ sql: String, row: (OpaquePointer) -> Void) throws {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK, let st else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "no db"
            throw Failure(kind: .schema, detail: msg)
        }
        defer { sqlite3_finalize(st) }
        while sqlite3_step(st) == SQLITE_ROW { row(st) }
    }

    private static func text(_ st: OpaquePointer, _ col: Int32) -> String? {
        sqlite3_column_text(st, col).map { String(cString: $0) }
    }

    /// Core Data seconds since 2001-01-01. NULL or ≤ 0 → nil (date unknown).
    private static func coreDataDate(_ st: OpaquePointer, _ col: Int32) -> Date? {
        guard sqlite3_column_type(st, col) != SQLITE_NULL else { return nil }
        let s = sqlite3_column_double(st, col)
        return s > 0 ? Date(timeIntervalSinceReferenceDate: s) : nil
    }
}

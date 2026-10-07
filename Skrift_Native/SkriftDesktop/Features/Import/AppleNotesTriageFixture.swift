#if DEBUG
import Foundation

/// Q333: the mock's own 412 made-up notes (mocks/Q71-apple-notes-triage-v3.html, `T` + `fake()`),
/// as a ready-made model, so `-snapshot-applenotes` can draw every state without a database.
/// Synthetic text only: nothing here comes from a real Notes store.
enum AppleNotesTriageFixture {
    enum Stage: String, CaseIterable { case start, triageLocked, triageUnlocked, reportSoFar, reportEnd, denied }

    private struct T {
        var t: String; var l: [String]; var pics = 0; var draw = 0; var audio = 0; var pdf = 0; var scan = 0
        var tbl = false; var ck: (Int, Int)? = nil; var tags: [String] = []
    }

    private static let templates: [T] = [
        T(t: "Shino recipe v3", l: ["Cone 6, reduction. Try on the tall jar.", "Nepheline syenite 40, spodumene 20, soda ash 4."], pics: 1, ck: (2, 3), tags: ["glaze"]),
        T(t: "Tram idea: glaze as map", l: ["Crawl glaze that cracks like the 28 route."], draw: 1, audio: 1, tags: ["Kiln"]),
        T(t: "Meter readings", l: ["Readings for the landlord, every first of the month."], tbl: true),
        T(t: "Call back Rui", l: ["About the van on Saturday. After 18h."]),
        T(t: "Gripper v2 notes", l: ["Finger pads slip on glossy boxes.", "Try the softer silicone, shore 20A."], pics: 3, draw: 1, tags: ["gripper", "gfr"]),
        T(t: "Bacalhau à Brás", l: ["Onions thin, potatoes matchstick, eggs last and off the heat."], pics: 2, tags: ["recipe"]),
        T(t: "Gift ideas for Mo", l: ["Book on Japanese joinery. A good chisel. Concert tickets?"], ck: (1, 4), tags: ["gift ideas"]),
        T(t: "Dentist 12 Oct", l: ["10:30, Rua Augusta. Bring the old X-rays."]),
        T(t: "Firing log, September", l: ["Bisque 04 on the 3rd, glaze 6 on the 9th.", "Shelf 2 underfired again."], pics: 4, tbl: true, tags: ["Kiln"]),
        T(t: "Investor call prep", l: ["Three numbers: units shipped, gross margin, pilot count."], audio: 1, pdf: 1, tags: ["gfr"]),
        T(t: "Parking level 3", l: ["P3, row F, next to the pillar with the blue stripe."]),
        T(t: "Sourdough schedule", l: ["Feed 9:00, mix 14:00, shape 19:00, fridge overnight."], ck: (0, 5), tags: ["recipe"]),
        T(t: "Paint colours", l: ["Hall: off-white, sample 3. Bedroom: the grey-green one."], pics: 2, scan: 1),
        T(t: "Words for the song", l: ["Second verse still missing. Something about the ferry."], audio: 1),
        T(t: "Sci-fi list", l: ["Exhalation. The Dispossessed. Something by Le Guin I have not read."], ck: (1, 6), tags: ["books"]),
        T(t: "Servo torque table", l: ["Measured at 6 V, stall."], pdf: 1, tbl: true, tags: ["gfr"]),
        T(t: "Portuguese verbs", l: ["ter, ser, estar, ficar. Ficar is the hard one."], tags: ["pt"]),
        T(t: "Cone 6 celadon test", l: ["Too green at 2% iron. Try 1.5 next firing."], pics: 6, tags: ["glaze"]),
        T(t: "Wi-Fi setup", l: ["Router in the hall cupboard. Guest network is the second one."]),
        T(t: "Misumi order", l: ["2x linear rail 300 mm, 4x carriage."], pdf: 1, scan: 1, ck: (1, 2)),
        T(t: "Caldo verde", l: ["Kale sliced as thin as hair. Chouriço at the end."], tags: ["recipe"]),
        T(t: "Kiln shelf layout", l: ["Three shelves, tall pots at the back."], draw: 1, tags: ["Kiln"]),
        T(t: "Landlord contacts", l: ["Sr. Almeida for the boiler. Mornings only."]),
        T(t: "Dutch novels", l: ["Het diner. De avonden. Max Havelaar, one day."], tags: ["books"]),
        T(t: "Pastéis attempt 2", l: ["Oven not hot enough. Custard split."], pics: 1),
        T(t: "Glaze shopping list", l: ["Before the October firing."], ck: (3, 7)),
        T(t: "Local machinist", l: ["Two streets from the office. Does aluminium, not steel."]),
        T(t: "Passwords to change", l: ["Bank, email, router. (No passwords written here.)"], ck: (1, 3)),
        T(t: "Weekend in Porto", l: ["Train 8:39 from Santa Apolónia. Book the flat by Friday."], pics: 5),
        T(t: "Pottery class", l: ["Tuesday evenings, beginner wheel, 8 weeks."]),
    ]

    static let total = 412

    /// The mock's `fake(i)`.
    private static func fake(_ i: Int) -> (TriageDecision.Kind, Int?) {
        switch (i * 7 + 3) % 10 {
        case 0, 1: return (.rated, 1)
        case 2, 3: return (.rated, 2)
        case 4: return (.rated, 3)
        case 5: return (.rated, 1)
        case 6, 7: return (.skipped, nil)
        default: return (.never, nil)
        }
    }

    @MainActor
    static func model(_ stage: Stage) -> AppleNotesTriageModel {
        let cal = Calendar.current
        let base = cal.date(from: DateComponents(year: 2026, month: 9, day: 24))!
        var notes: [AppleNoteSummary] = []
        var decoded: [String: NotesBodyDecoder.Decoded] = [:]
        for i in 0..<total {
            let t = templates[i % templates.count]
            let id = String(format: "FIXTURE-%04d", i)
            let created = base.addingTimeInterval(-Double(Int((Double(i) * 2.3).rounded())) * 86_400)
            notes.append(AppleNoteSummary(id: id, pk: Int64(i), title: t.t, snippet: t.l.first ?? "", created: created, modified: created, isLocked: false))
            var md = "# " + t.t + "\n\n" + t.l.joined(separator: "\n\n")
            var media = NotesBodyDecoder.Media()
            media.pictures = t.pics; media.drawings = t.draw; media.audio = t.audio; media.pdfs = t.pdf; media.scans = t.scan
            media.tables = t.tbl ? 1 : 0
            if let ck = t.ck { media.checklistItems = ck.1; media.checklistDone = ck.0; md += "\n\n- [ ] checklist" }
            decoded[id] = NotesBodyDecoder.Decoded(markdown: md, title: t.t, tags: t.tags, media: media)
        }
        notes[7].isLocked = true   // one locked note stays behind; the start screen says so

        var state = TriageState()
        state.session = 1
        let today = Date()
        let thu = cal.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 10))!
        let fri = cal.date(from: DateComponents(year: 2026, month: 9, day: 25, hour: 10))!
        var unmapped: [String: NotesBodyDecoder.Media] = [:]
        func put(_ i: Int, _ kind: TriageDecision.Kind, _ rating: Int?, day: Date, imported: Bool) {
            let n = notes[i]
            var d = TriageDecision(kind: kind, rating: rating, title: n.title, created: n.created, decidedAt: day, session: 1)
            if imported && kind == .rated {
                d.skriftID = "pf-\(i)"; d.importedAt = day
                if let m = decoded[n.id]?.media { unmapped[n.id] = m }
            }
            state.decisions[n.id] = d
        }
        let upTo = stage == .reportEnd ? total : 180
        for i in 0..<upTo where !notes[i].isLocked {
            let (k, r) = fake(i)
            put(i, k, r, day: i < 80 ? thu : fri, imported: true)
        }
        switch stage {
        case .start, .reportSoFar, .denied, .triageLocked:
            put(180, .rated, 2, day: today, imported: false)
            put(181, .never, nil, day: today, imported: false)
            put(182, .skipped, nil, day: today, imported: false)
        case .triageUnlocked:
            for (j, i) in (180..<190).enumerated() {
                let (k, r) = fake(i + j)
                put(i, k, r, day: today, imported: false)
            }
        case .reportEnd: break
        }
        if stage != .reportEnd { state.batch = (180..<190).map { notes[$0].id } }
        state.cursor = stage == .triageUnlocked ? 6 : 3
        state.batchesDone = 18
        let phase: AppleNotesTriageModel.Phase
        switch stage {
        case .start: phase = .start
        case .triageLocked, .triageUnlocked: phase = .triage
        case .reportSoFar: phase = .report(end: false)
        case .reportEnd: phase = .report(end: true)
        case .denied: phase = .denied("The operation couldn’t be completed. (Operation not permitted)")
        }
        return AppleNotesTriageModel(fixtureNotes: notes, decoded: decoded, state: state, phase: phase, unmapped: unmapped)
    }
}
#endif

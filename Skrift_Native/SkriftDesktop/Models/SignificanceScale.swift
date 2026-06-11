import Foundation

/// Pure value↔circle mapping for the 10-circle significance control
/// (`Features/Review/SignificanceCircles.swift` — mocks/significance-circles.html).
/// Kept free of SwiftUI and housed in Models/ so the host-less SkriftDesktopTests
/// bundle (which compiles Models/Pipeline/Server only, not Features/) can unit-test
/// it. Circle N ↔ 0.N — the same 0.1 snaps the old slider persisted to
/// `PipelineFile.significance`. Tier boundaries stay 0.4 / 0.7
/// (passing · useful · significant); 0.8+ crosses the "refine wall" (those notes
/// get a refine pass before export).
enum SignificanceScale {
    /// First circle past the refine wall (0.8).
    static let refineWall = 8

    /// Stored value → how many circles are lit (0 = unrated). Tolerates float noise
    /// (0.7000000001 from old slider data) and off-grid phone values by rounding;
    /// clamps BEFORE the Int conversion so an off-contract value can't trap.
    static func litCount(_ value: Double?) -> Int {
        guard let value, value.isFinite else { return 0 }
        return Int(min(10, max(0, (value * 10).rounded())))
    }

    /// Circle N → the persisted value (1 → 0.1 … 10 → 1.0).
    static func value(forCircle n: Int) -> Double { Double(n) / 10 }

    static func tierName(_ n: Int) -> String {
        n >= 7 ? "Significant" : n >= 4 ? "Useful" : "Passing"
    }

    /// "0.5 · Useful" / "1.0 · Significant" — the top-right value text.
    static func valueText(_ n: Int) -> String {
        (n == 10 ? "1.0" : "0.\(n)") + " · " + tierName(n)
    }
}

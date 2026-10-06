import XCTest
import SwiftData

/// Q326 / D182 (mock Q144-mac-weather-daypart.html): a Mac RECORDING gets weather + daypart like
/// a phone take; the OpenWeatherMap key comes from the phone over iCloud; a file dragged into the
/// Mac gets no place and no weather. The fix, the key and the network call are all stubbed.
@MainActor
final class MacWeatherMetadataTests: XCTestCase {
    private let lisbon = LocationInfo(latitude: 38.72, longitude: -9.14, placeName: "Marvila, Lisbon")
    private let cloudy = WeatherReading(weather: WeatherInfo(conditions: "Clouds", temperature: 19, temperatureUnit: "C"),
                                        pressure: PressureInfo(hPa: 1016, trend: .steady))

    private func pipelineContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: PipelineFile.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func cloudContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Memo.self, MemoAsset.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true,
                                                                           cloudKitDatabase: .none)))
    }

    private func fakeTake(in dir: URL, named name: String) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(repeating: 0, count: 4096).write(to: url)
        return url
    }

    /// A service with a synced key and stubbed fix + network; records the key the fetch got.
    private func service(key: String?, fix: LocationInfo?, onFetch: @escaping (String) -> Void = { _ in }) -> MacMetadataService {
        MacMetadataService(location: { fix },
                           weatherKey: { key },
                           fetchWeather: { [cloudy] _, _, k in onFetch(k); return cloudy })
    }

    // MARK: - the key comes from the phone

    func testAKeyTypedOnThePhoneIsAdoptedByTheMac() {
        let phone = VocabularyRecord(words: [], modifiedAt: .distantPast,
                                     weatherKey: "phone-key-a7", weatherKeyModifiedAt: Date(timeIntervalSince1970: 1_000))
        // The Mac never set one: blank + distantPast.
        let out = WeatherKeySyncCore.reconcile(localKey: "", localModifiedAt: .distantPast,
                                               records: [phone], insert: { _ in XCTFail("no new carrier needed") })
        XCTAssertEqual(out, .adoptRemote(key: "phone-key-a7", modifiedAt: Date(timeIntervalSince1970: 1_000)))
    }

    func testAMacWithNoKeyNeverBroadcastsItsBlankOverThePhones() {
        let phone = VocabularyRecord(words: [], modifiedAt: Date(), weatherKey: "k", weatherKeyModifiedAt: Date())
        _ = WeatherKeySyncCore.reconcile(localKey: "", localModifiedAt: .distantPast,
                                         records: [phone], insert: { _ in })
        XCTAssertEqual(phone.weatherKey, "k")
    }

    func testAKeyTypedOnTheMacIsPushedWhenNoneEverSynced() {
        var inserted: VocabularyRecord?
        let stamp = Date(timeIntervalSince1970: 2_000)
        let out = WeatherKeySyncCore.reconcile(localKey: "mac-typed", localModifiedAt: stamp,
                                               records: [], insert: { inserted = $0 })
        XCTAssertEqual(out, .pushedLocal(stamp: stamp))
        XCTAssertEqual(inserted?.weatherKey, "mac-typed")
    }

    func testTheNewerStampWinsBothWays() {
        let rec = VocabularyRecord(words: [], modifiedAt: Date(), weatherKey: "old", weatherKeyModifiedAt: Date(timeIntervalSince1970: 100))
        let out = WeatherKeySyncCore.reconcile(localKey: "new", localModifiedAt: Date(timeIntervalSince1970: 200),
                                               records: [rec], insert: { _ in })
        XCTAssertEqual(out, .pushedLocal(stamp: Date(timeIntervalSince1970: 200)))
        XCTAssertEqual(rec.weatherKey, "new")
    }

    func testTheKeyIsMaskedToTheLastTwoCharacters() {
        XCTAssertEqual(WeatherKeySyncCore.masked("abcdefa7"), "••••••a7")
        XCTAssertEqual(WeatherKeySyncCore.masked("  "), "Not set")
    }

    func testTheMacKeyDefaultsToBlankForALegacySettingsFile() throws {
        let legacy = Data(#"{"authorName":"Tuur"}"#.utf8)
        let s = try JSONDecoder().decode(AppSettings.self, from: legacy)
        XCTAssertEqual(s.weatherKey, "")
        XCTAssertNil(s.weatherKeyModifiedAt)
    }

    // MARK: - a Mac take writes weather + daypart

    func testAMacTakeWithASyncedKeyWritesWeatherAndDaypart() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()

        var keyUsed: String?
        var hooks = ArrivalPath.Hooks.inert
        let svc = service(key: "synced-key", fix: lisbon, onFetch: { keyUsed = $0 })
        hooks.captureContext = { await svc.capture() }

        _ = try await ArrivalPath.run(
            urls: [try fakeTake(in: work, named: "take.m4a")], asRecording: true, into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))

        // The stamp is fire-and-forget (no recording waits on a fix) — wait for it to land.
        var meta: MemoMetadata?
        for _ in 0..<100 {
            meta = try cloud.fetch(FetchDescriptor<Memo>()).first?.metadata
            if meta?.weather != nil { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let m = try XCTUnwrap(meta, "the take's Memo carries a metadata blob")
        XCTAssertEqual(keyUsed, "synced-key", "the weather call uses the key that synced from the phone")
        XCTAssertEqual(m.weather, cloudy.weather)
        XCTAssertEqual(m.pressure, cloudy.pressure)
        XCTAssertEqual(m.location?.placeName, "Marvila, Lisbon")
        XCTAssertNotNil(m.dayPeriod, "daypart lands with the weather")
        XCTAssertNotNil(m.daylight)
        XCTAssertNil(m.steps, "no pedometer on a Mac (D92)")
        // The Mac's own exporter reads the PipelineFile copy.
        let pf = try XCTUnwrap(try ctx.fetch(FetchDescriptor<PipelineFile>()).first)
        XCTAssertNotNil(pf.audioMetadataJSON)
    }

    func testWithNoKeyThereIsNoWeatherAndNoFailure() async throws {
        var fetches = 0
        let svc = service(key: nil, fix: lisbon, onFetch: { _ in fetches += 1 })
        let m = await svc.capture()
        XCTAssertEqual(fetches, 0, "no key, no network call")
        XCTAssertNil(m.weather)
        XCTAssertNil(m.pressure)
        XCTAssertEqual(m.location?.placeName, "Marvila, Lisbon")
        XCTAssertNotNil(m.dayPeriod)
        let blank = await service(key: "   ", fix: lisbon, onFetch: { _ in fetches += 1 }).capture()
        XCTAssertNil(blank.weather)
        XCTAssertEqual(fetches, 0)
    }

    func testWithNoFixThereIsNoWeatherButTheDaypartStays() async throws {
        var fetches = 0
        let m = await service(key: "k", fix: nil, onFetch: { _ in fetches += 1 }).capture()
        XCTAssertEqual(fetches, 0, "the weather call needs coordinates")
        XCTAssertNil(m.location)
        XCTAssertNil(m.weather)
        XCTAssertNotNil(m.dayPeriod)
    }

    // MARK: - a dropped file gets none

    func testADroppedFileWritesNoPlaceAndNoWeather() async throws {
        let work = makeTempDir(); defer { try? FileManager.default.removeItem(at: work) }
        let ctx = try pipelineContext()
        let cloud = try cloudContext()

        var captures = 0
        var hooks = ArrivalPath.Hooks.inert
        let svc = service(key: "synced-key", fix: lisbon)
        hooks.captureContext = { captures += 1; return await svc.capture() }

        let created = try await ArrivalPath.run(
            urls: [try fakeTake(in: work, named: "dropped.m4a")], asRecording: false, into: ctx, cloudContext: cloud,
            hooks: hooks, service: IngestService(outputDir: work.appendingPathComponent("out")))
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(captures, 0, "an import never asks where the Mac is standing")
        XCTAssertTrue(try cloud.fetch(FetchDescriptor<Memo>()).isEmpty)
        let meta = MemoMetadata.lenient(from: created.first?.audioMetadataJSON)
        XCTAssertNil(meta?.weather, "the file carries no weather")
        XCTAssertNil(meta?.location, "the file carries no place")
        XCTAssertNil(meta?.dayPeriod)
    }
}

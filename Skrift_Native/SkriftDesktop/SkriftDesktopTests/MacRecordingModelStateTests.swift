import XCTest
import Foundation

/// Q165: the model line + loading placeholder both recording screens show come from ONE shared
/// `RecordingModelState` (the phone's `ModelLoadStatus.recordingState` and the Mac's
/// `ASRModelStatus` reduce to it). These pin the strings the phone already shipped.
final class MacRecordingModelStateTests: XCTestCase {

    func testStatusTextForEveryState() {
        XCTAssertEqual(RecordingModelState.downloading(0.126).statusText, "Downloading model · 12%")
        XCTAssertEqual(RecordingModelState.preparing(0.5).statusText, "Preparing model · 50%")
        XCTAssertEqual(RecordingModelState.preparing(nil).statusText, "Preparing model…")
        XCTAssertEqual(RecordingModelState.ready.statusText, "On-device transcription · ready")
        XCTAssertEqual(RecordingModelState.failed.statusText, "Couldn’t load model")
        XCTAssertEqual(RecordingModelState.notDownloaded.statusText, "Transcription model not downloaded")
    }

    func testProgressIsClamped() {
        XCTAssertEqual(RecordingModelState.downloading(1.7).statusText, "Downloading model · 100%")
        XCTAssertEqual(RecordingModelState.downloading(-0.2).statusText, "Downloading model · 0%")
    }

    func testIdleNeverClaimsNotDownloadedOnceCached() {
        XCTAssertEqual(RecordingModelState.idle(everDownloaded: true), .preparing(nil))
        XCTAssertEqual(RecordingModelState.idle(everDownloaded: false), .notDownloaded)
    }

    func testLoadingMeansNeitherReadyNorFailed() {
        XCTAssertTrue(RecordingModelState.notDownloaded.isLoading)
        XCTAssertTrue(RecordingModelState.downloading(0.1).isLoading)
        XCTAssertTrue(RecordingModelState.preparing(nil).isLoading)
        XCTAssertFalse(RecordingModelState.ready.isLoading)
        XCTAssertFalse(RecordingModelState.failed.isLoading)
    }

    func testPlaceholderCopy() {
        XCTAssertEqual(RecordingModelState.captionPlaceholder,
                       "Model loading — your words appear once it’s ready")
    }
}

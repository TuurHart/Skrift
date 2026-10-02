import Foundation

/// What a note-creating screen asks for when it wants the context a voice recording
/// carries (place, weather, daypart, …). A protocol so each app supplies what its OS can
/// read — the phone's `MetadataService` adds steps and weather, the Mac's
/// `MacMetadataService` place and daypart — and tests supply a fake. Shared so the typed-note
/// draft (`QuickNoteDraft`) is one rule on both apps (D151).
@MainActor
protocol MetadataProviding {
    func capture() async -> MemoMetadata
}

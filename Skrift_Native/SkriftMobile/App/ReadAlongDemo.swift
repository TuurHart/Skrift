#if DEBUG
import SwiftUI

/// Q537 (DEBUG): the real `ReadAlongView` with canned lines and follow switched off, so a
/// simulator screenshot shows the "Back to playing" pill over the faded text. Launch with
/// `-readAlongDemo`. Nothing here ships: the whole file and the flag's call sites are DEBUG.
enum ReadAlongDemo {
    static let sentences: [BufferSentence] = {
        let lines = [
            "The harbour was quiet that morning, and the boats lay low against the pilings.",
            "Nobody had come down to the water yet, not even the old men who mended nets.",
            "She stood at the end of the pier for a while, counting the gulls on the roofs.",
            "There were eleven, then nine, then twelve, because they never kept still.",
            "When the bell finally rang from the chandler's, she turned and walked back up.",
            "The street smelled of bread and wet rope, and a dog followed her for a block.",
            "At the corner a man was unrolling an awning, one slow crank at a time.",
            "She waved to him, and he lifted two fingers from the handle without looking.",
            "By the time she reached the square the first stalls were already open.",
            "Someone was frying onions somewhere, and the whole morning leaned toward it.",
            "She bought a paper, folded it under her arm, and did not read a word of it.",
            "The clock on the church said ten past, which meant it was nearly eleven.",
        ]
        return lines.enumerated().map { i, text in
            BufferSentence(text: text, start: Double(i) * 6, end: Double(i) * 6 + 5.5, words: [])
        }
    }()
}

struct ReadAlongDemoHost: View {
    private static let book = Audiobook(
        id: UUID(), files: ["demo.m4a"], fileDurations: [72], title: "Demo", author: "",
        duration: 72, chapters: [], hasCover: false, importedAt: Date(), lastPlayedAt: nil,
        position: 0, playbackRate: 1, modifiedAt: Date())

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()
            ReadAlongView(book: Self.book, fileIndex: 0, fileLocal: 24, audioURL: nil, onTranscribe: {})
                .padding(.top, 80).padding(.bottom, 60)
        }
        .preferredColorScheme(.dark)
    }
}
#endif

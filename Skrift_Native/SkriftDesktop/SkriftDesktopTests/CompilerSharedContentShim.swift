import Foundation

// TEMPORARY SHIM (Q247). `CompilerSharedContent` was deleted: the Compiler now takes the one
// wire struct `SharedContent`. `CompilerTests.swift:325-354` (protected) still builds five of
// the old string-typed values, e.g. `CompilerSharedContent(type: "url", url: …)`. This function
// keeps those call sites compiling unedited. When the hand-merge rewrites them to
// `SharedContent(type: .url, …)`, DELETE THIS FILE.
//
// An unknown type string maps to `.file`, which pins nothing — the same "no pinned block" the
// old string `default:` gave (`testCaptureSharedBlockUnknownTypeIsEmpty`).
func CompilerSharedContent(type: String, url: String? = nil, urlTitle: String? = nil,
                           text: String? = nil, fileName: String? = nil) -> SharedContent {
    SharedContent(type: ShareContentType(rawValue: type) ?? .file,
                  url: url, urlTitle: urlTitle, text: text, fileName: fileName)
}

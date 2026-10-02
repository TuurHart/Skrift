import Foundation
import ImageIO

/// Reads a photo's taken-date from its ORIGINAL bytes (A4). Shared (Q134): the phone app, the
/// share extension AND the Mac ingest all read EXIF through it. The extension must read EXIF
/// before its downsample re-encode strips the metadata; the drainer then dates the capture memo
/// to the photo, not the share moment (mirroring video's filming date / audio's clip date).
enum ImageDates {

    /// EXIF `DateTimeOriginal` (else TIFF `DateTime`) via CGImageSource properties —
    /// a metadata read, never a bitmap decode (extension memory ceiling). EXIF
    /// stamps are timezone-naive local time ("2026:07:04 19:21:03"); parsed in the
    /// current timezone, same as Photos treats them. nil when absent/unparseable.
    static func exifDate(from data: Data) -> Date? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return exifDate(of: src)
    }

    /// The same read straight from a file (the Mac drop): metadata only, no full load.
    static func exifDate(at url: URL) -> Date? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return exifDate(of: src)
    }

    /// C70 + C74 for a picture on disk: EXIF → the date in its name → its file date.
    static func ladderDate(at url: URL, name: String? = nil) -> Date? {
        FilenameDate.ladder(embedded: exifDate(at: url), fileAt: url, name: name)
    }

    private static func exifDate(of src: CGImageSource) -> Date? {
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
            return nil
        }
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        let stamp = (exif?[kCGImagePropertyExifDateTimeOriginal] as? String)
            ?? (tiff?[kCGImagePropertyTIFFDateTime] as? String)
        guard let stamp else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return f.date(from: stamp)
    }
}

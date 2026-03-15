import Foundation
import AppKit

enum ClipContentType: UInt8 {
    case text = 0
    case url = 1
    case image = 2

    static func from(_ value: UInt8) -> ClipContentType {
        ClipContentType(rawValue: value) ?? .text
    }
}

struct ClipItem: Identifiable {
    let id: UUID
    let timestamp: Date
    let contentType: ClipContentType
    let textContent: String?
    var imagePath: String?
    let sourceApp: String?
    var isPinned: Bool
    var rawImageData: Data?
    var displacedPrev: Int?
    var displacedNext: Int?
    var sourceFilePath: String?

    var preview: String {
        switch contentType {
        case .text:
            return String((textContent ?? "").prefix(300))
        case .url:
            return textContent ?? ""
        case .image:
            return "Image"
        }
    }

    var sourceAppName: String? {
        guard let bundleID = sourceApp,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return FileManager.default.displayName(atPath: url.path)
    }

    var titlePath: String {
        switch contentType {
        case .text, .url:
            return (textContent ?? "").components(separatedBy: .newlines).first ?? ""
        case .image:
            return imagePath ?? ""
        }
    }

    private static let thumbCache = NSCache<NSString, NSImage>()

    func loadImage() -> NSImage? {
        let key = id.uuidString as NSString
        if let cached = Self.thumbCache.object(forKey: key) {
            return cached
        }

        let source: NSImage?
        if let path = imagePath {
            source = NSImage(contentsOfFile: path)
        } else if let data = rawImageData {
            source = NSImage(data: data)
        } else {
            return nil
        }

        guard let img = source else { return nil }

        let maxDim: CGFloat = 400
        let w = img.size.width, h = img.size.height
        if w > maxDim || h > maxDim {
            let scale = min(maxDim / w, maxDim / h)
            let newSize = NSSize(width: w * scale, height: h * scale)
            let thumb = NSImage(size: newSize)
            thumb.lockFocus()
            img.draw(in: NSRect(origin: .zero, size: newSize),
                     from: NSRect(origin: .zero, size: img.size),
                     operation: .copy, fraction: 1.0)
            thumb.unlockFocus()
            Self.thumbCache.setObject(thumb, forKey: key)
            return thumb
        }

        Self.thumbCache.setObject(img, forKey: key)
        return img
    }
}

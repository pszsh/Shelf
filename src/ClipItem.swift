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

    var relativeTime: String {
        let interval = Date().timeIntervalSince(timestamp)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m" }
        if interval < 86400 { return "\(Int(interval / 3600))h" }
        return "\(Int(interval / 86400))d"
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

    func loadImage() -> NSImage? {
        guard let path = imagePath else {
            if let data = rawImageData {
                return NSImage(data: data)
            }
            return nil
        }
        return NSImage(contentsOfFile: path)
    }
}

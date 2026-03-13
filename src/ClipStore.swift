import Foundation
import AppKit

class ClipStore: ObservableObject {
    @Published var items: [ClipItem] = []
    private var storePtr: OpaquePointer

    init(maxItems: Int = 500) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Shelf").path
        storePtr = shelf_store_new(dir, Int32(maxItems))
        reload()
    }

    deinit {
        shelf_store_free(storePtr)
    }

    private func reload() {
        let list = shelf_store_get_all(storePtr)
        defer { shelf_clip_list_free(list) }

        var loaded: [ClipItem] = []
        guard let clips = list.clips else {
            items = loaded
            return
        }

        for i in 0..<list.count {
            let c = clips[i]
            loaded.append(ClipItem(
                id: UUID(uuidString: c.id != nil ? String(cString: c.id) : "") ?? UUID(),
                timestamp: Date(timeIntervalSince1970: c.timestamp),
                contentType: ClipContentType.from(c.content_type),
                textContent: c.text_content != nil ? String(cString: c.text_content) : nil,
                imagePath: c.image_path != nil ? String(cString: c.image_path) : nil,
                sourceApp: c.source_app != nil ? String(cString: c.source_app) : nil,
                isPinned: c.is_pinned,
                displacedPrev: c.displaced_prev >= 0 ? Int(c.displaced_prev) : nil,
                displacedNext: c.displaced_next >= 0 ? Int(c.displaced_next) : nil
            ))
        }
        items = loaded
    }

    func add(_ item: ClipItem) {
        let idStr = strdup(item.id.uuidString)
        let textStr = item.textContent.flatMap { strdup($0) }
        let appStr = item.sourceApp.flatMap { strdup($0) }
        defer {
            free(idStr)
            free(textStr)
            free(appStr)
        }

        var clip = ShelfClip(
            id: idStr,
            timestamp: item.timestamp.timeIntervalSince1970,
            content_type: item.contentType.rawValue,
            text_content: textStr,
            image_path: nil,
            source_app: appStr,
            is_pinned: item.isPinned,
            displaced_prev: -1,
            displaced_next: -1
        )

        if let data = item.rawImageData {
            data.withUnsafeBytes { buf in
                let ptr = buf.baseAddress?.assumingMemoryBound(to: UInt8.self)
                let result = shelf_store_add(storePtr, &clip, ptr, data.count)
                if result != nil { shelf_string_free(result) }
            }
        } else {
            let result = shelf_store_add(storePtr, &clip, nil, 0)
            if result != nil { shelf_string_free(result) }
        }

        reload()
    }

    func delete(_ item: ClipItem) {
        item.id.uuidString.withCString { shelf_store_delete(storePtr, $0) }
        items.removeAll { $0.id == item.id }
    }

    func togglePin(_ item: ClipItem) {
        let newPinned = item.id.uuidString.withCString { shelf_store_toggle_pin(storePtr, $0) }
        if let idx = items.firstIndex(where: { $0.id == item.id }) {
            items[idx].isPinned = newPinned
        }
    }

    func copyToClipboard(_ item: ClipItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.contentType {
        case .text:
            pb.setString(item.textContent ?? "", forType: .string)
        case .url:
            pb.setString(item.textContent ?? "", forType: .string)
            pb.setString(item.textContent ?? "", forType: .URL)
        case .image:
            if let image = item.loadImage() {
                pb.writeObjects([image])
            }
        }

        NotificationCenter.default.post(name: .dismissShelfPanel, object: nil)
    }

    func clearAll() {
        shelf_store_clear_all(storePtr)
        items.removeAll()
    }
}

extension Notification.Name {
    static let dismissShelfPanel = Notification.Name("dismissShelfPanel")
}

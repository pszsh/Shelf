import AppKit

class PasteboardMonitor {
    private var timer: Timer?
    private var lastChangeCount: Int
    private var lastCopyTime: Date = .distantPast
    private let minInterval: TimeInterval = 0.5

    var onNewClip: ((ClipItem) -> Void)?

    init() {
        self.lastChangeCount = NSPasteboard.general.changeCount
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func syncChangeCount() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    private func check() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let now = Date()
        guard now.timeIntervalSince(lastCopyTime) >= minInterval else { return }
        lastCopyTime = now

        if pb.types?.contains(NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")) == true {
            return
        }

        let sourceApp = NSWorkspace.shared.frontmostApplication?.bundleIdentifier

        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let fileURL = urls.first {
            let ext = fileURL.pathExtension.lowercased()
            let textExts: Set<String> = [
                "txt", "md", "markdown", "rtf", "csv", "json", "xml", "yaml", "yml",
                "toml", "ini", "cfg", "conf", "log", "sh", "zsh", "bash", "fish",
                "py", "rb", "js", "ts", "go", "rs", "c", "h", "cpp", "hpp", "java",
                "swift", "kt", "html", "css", "scss", "less", "sql", "lua", "pl",
                "r", "m", "mm", "zig", "nim", "ex", "exs", "erl", "hs", "ml",
                "tex", "sty", "cls", "bib", "org", "rst", "adoc", "env", "gitignore",
                "dockerfile", "makefile"
            ]
            let imageExts: Set<String> = [
                "png", "jpg", "jpeg", "gif", "bmp", "tiff", "tif", "webp", "heic", "heif", "ico", "svg"
            ]

            let filePath = fileURL.path

            if textExts.contains(ext) || ext.isEmpty {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8),
                   content.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2 {
                    let item = ClipItem(
                        id: UUID(), timestamp: now, contentType: .text,
                        textContent: content, imagePath: nil,
                        sourceApp: sourceApp, isPinned: false,
                        sourceFilePath: filePath
                    )
                    onNewClip?(item)
                    return
                }
            } else if imageExts.contains(ext) {
                if let data = try? Data(contentsOf: fileURL) {
                    let item = ClipItem(
                        id: UUID(), timestamp: now, contentType: .image,
                        textContent: nil, imagePath: nil,
                        sourceApp: sourceApp, isPinned: false,
                        rawImageData: data,
                        sourceFilePath: filePath
                    )
                    onNewClip?(item)
                    return
                }
            } else {
                let item = ClipItem(
                    id: UUID(), timestamp: now, contentType: .text,
                    textContent: filePath, imagePath: nil,
                    sourceApp: sourceApp, isPinned: false,
                    sourceFilePath: filePath
                )
                onNewClip?(item)
                return
            }
        }

        if let imageData = pb.data(forType: .tiff) ?? pb.data(forType: .png) {
            let item = ClipItem(
                id: UUID(), timestamp: now, contentType: .image,
                textContent: nil, imagePath: nil,
                sourceApp: sourceApp, isPinned: false,
                rawImageData: imageData
            )
            onNewClip?(item)
            return
        }

        if let text = pb.string(forType: .string) {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 2 {
                return
            }

            let contentType: ClipContentType
            if let _ = URL(string: text), text.hasPrefix("http") {
                contentType = .url
            } else {
                contentType = .text
            }

            let item = ClipItem(
                id: UUID(), timestamp: now, contentType: contentType,
                textContent: text, imagePath: nil,
                sourceApp: sourceApp, isPinned: false
            )
            onNewClip?(item)
        }
    }
}

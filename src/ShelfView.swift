import SwiftUI
import Quartz

// MARK: - Native Quick Look Controller

class ShelfPreviewController: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = ShelfPreviewController()

    var currentItem: ClipItem?
    private var tempURL: URL?

    var isVisible: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    func toggle(item: ClipItem) {
        if isVisible && currentItem?.id == item.id {
            dismiss()
        } else {
            show(item)
        }
    }

    func show(_ item: ClipItem) {
        cleanup()
        currentItem = item
        prepareFile()

        guard let panel = QLPreviewPanel.shared() else { return }
        panel.reloadData()
        if panel.isVisible {
            panel.reloadData()
        } else {
            panel.orderFront(nil)
        }
    }

    func dismiss() {
        if isVisible {
            QLPreviewPanel.shared()?.orderOut(nil)
        }
        currentItem = nil
        cleanup()
    }

    private func prepareFile() {
        guard let item = currentItem else { return }

        switch item.contentType {
        case .image:
            break
        case .text:
            if let text = item.textContent {
                let url = tempDir().appendingPathComponent("clipboard.txt")
                try? text.write(to: url, atomically: true, encoding: .utf8)
                tempURL = url
            }
        case .url:
            if let urlString = item.textContent {
                let url = tempDir().appendingPathComponent("link.webloc")
                let plist: [String: String] = ["URL": urlString]
                if let data = try? PropertyListSerialization.data(
                    fromPropertyList: plist, format: .xml, options: 0
                ) {
                    try? data.write(to: url)
                }
                tempURL = url
            }
        }
    }

    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf-preview")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        currentItem != nil ? 1 : 0
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard let item = currentItem else { return nil }

        switch item.contentType {
        case .image:
            if let path = item.imagePath {
                return NSURL(fileURLWithPath: path)
            }
        case .text, .url:
            if let url = tempURL {
                return url as NSURL
            }
        }
        return nil
    }
}

// MARK: - Palette

enum Palette {
    private static func adaptive(
        light: (CGFloat, CGFloat, CGFloat, CGFloat),
        dark:  (CGFloat, CGFloat, CGFloat, CGFloat)
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { app in
            let d = app.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = d ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: c.3)
        })
    }

    static let trayTop    = adaptive(light: (0.95, 0.93, 0.90, 0.96), dark: (0.07,  0.05,  0.11,  0.95))
    static let trayBottom = adaptive(light: (0.92, 0.90, 0.87, 0.96), dark: (0.045, 0.03,  0.07,  0.95))
    static let trayEdge   = adaptive(light: (0.78, 0.74, 0.82, 0.50), dark: (0.30,  0.24,  0.40,  0.35))

    static let cardTop    = adaptive(light: (0.97, 0.95, 0.98, 1.0),  dark: (0.15, 0.12, 0.23, 1.0))
    static let cardBottom = adaptive(light: (0.94, 0.92, 0.95, 1.0),  dark: (0.10, 0.08, 0.17, 1.0))
    static let cardEdge   = adaptive(light: (0.80, 0.76, 0.85, 1.0),  dark: (0.26, 0.21, 0.34, 1.0))

    static let textPrimary   = adaptive(light: (0.16, 0.16, 0.16, 1.0), dark: (1.0, 1.0, 1.0, 0.88))
    static let textSecondary = adaptive(light: (0.42, 0.38, 0.45, 1.0), dark: (1.0, 1.0, 1.0, 0.50))
    static let textTertiary  = adaptive(light: (0.60, 0.56, 0.64, 1.0), dark: (1.0, 1.0, 1.0, 0.30))

    static let shadow = adaptive(light: (0.30, 0.25, 0.40, 0.15), dark: (0.04, 0.02, 0.08, 0.50))

    static func accent(for ct: ClipContentType) -> Color {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        switch ct {
        case .text:  return isDark
            ? Color(.sRGB, red: 0.70, green: 0.53, blue: 0.80)
            : Color(.sRGB, red: 0.48, green: 0.25, blue: 0.55)
        case .url:   return isDark
            ? Color(.sRGB, red: 0.36, green: 0.63, blue: 0.75)
            : Color(.sRGB, red: 0.18, green: 0.42, blue: 0.58)
        case .image: return isDark
            ? Color(.sRGB, red: 0.75, green: 0.53, blue: 0.31)
            : Color(.sRGB, red: 0.58, green: 0.38, blue: 0.18)
        }
    }
}

// MARK: - Shelf View

struct ShelfView: View {
    @ObservedObject var store: ClipStore
    @State private var selectedID: UUID? = nil
    @State private var expandedItem: UUID? = nil
    @State private var expandedSelection: Int? = nil
    @State private var lastItemCount: Int = 0
    @State private var loadedCount: Int = 40

    private let bufferPage = 40

    private var sortedItems: [ClipItem] {
        store.items.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.timestamp > b.timestamp
        }
    }

    private var displayedItems: [ClipItem] {
        Array(sortedItems.prefix(loadedCount))
    }

    var body: some View {
        shelf
            .background(
                KeyCaptureView(
                    onSpace: handleSpace,
                    onEscape: handleEscape,
                    onArrow: handleArrow,
                    onDelete: handleDelete,
                    onReturn: handleReturn,
                    onCopy: handleReturn,
                    onScroll: handleScroll
                )
            )
    }

    private var shelf: some View {
        let items = displayedItems
        let allItems = sortedItems
        let trayHeight: CGFloat = 260
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Palette.trayTop, Palette.trayBottom],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Palette.trayEdge, Palette.trayEdge.opacity(0.1)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .frame(height: trayHeight)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(items) { item in
                            cardGroup(for: item, in: allItems)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                }
                .onChange(of: selectedID) {
                    if let id = selectedID {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
                .onChange(of: store.items.count) {
                    if store.items.count > lastItemCount {
                        resetToStart(proxy: proxy)
                    }
                    lastItemCount = store.items.count
                }
                .onReceive(NotificationCenter.default.publisher(for: .resetShelfScroll)) { _ in
                    resetToStart(proxy: proxy)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    @ViewBuilder
    private func cardGroup(for item: ClipItem, in items: [ClipItem]) -> some View {
        let isExpanded = expandedItem == item.id
        let hasNeighbors = item.displacedPrev != nil || item.displacedNext != nil

        HStack(spacing: 4) {
            if isExpanded, let prevIdx = item.displacedPrev,
               prevIdx >= 0, prevIdx < items.count {
                NeighborPeekCard(
                    item: items[prevIdx],
                    isHighlighted: expandedSelection == 0
                )
                .transition(.scale.combined(with: .opacity))
                .onTapGesture {
                    expandedSelection = 0
                }
            }

            ClipCardView(
                item: item,
                isSelected: selectedID == item.id,
                showNeighborHint: selectedID == item.id && hasNeighbors && !isExpanded
            )
            .id(item.id)
            .contextMenu { clipContextMenu(for: item) }
            .onTapGesture {
                if selectedID == item.id {
                    if hasNeighbors {
                        if isExpanded {
                            collapseExpansion()
                        } else {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                expandedItem = item.id
                                expandedSelection = nil
                            }
                        }
                    }
                } else {
                    collapseExpansion()
                    selectedID = item.id
                }
            }

            if isExpanded, let nextIdx = item.displacedNext,
               nextIdx >= 0, nextIdx < items.count {
                NeighborPeekCard(
                    item: items[nextIdx],
                    isHighlighted: expandedSelection == 1
                )
                .transition(.scale.combined(with: .opacity))
                .onTapGesture {
                    expandedSelection = 1
                }
            }
        }
    }

    private func resetToStart(proxy: ScrollViewProxy) {
        collapseExpansion()
        selectedID = nil
        loadedCount = bufferPage
        if let first = sortedItems.first {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo(first.id, anchor: .leading)
            }
        }
    }

    private func collapseExpansion() {
        guard expandedItem != nil else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            expandedItem = nil
            expandedSelection = nil
        }
    }

    private func handleSpace() {
        guard let id = selectedID,
              let item = sortedItems.first(where: { $0.id == id }) else {
            ShelfPreviewController.shared.dismiss()
            return
        }
        ShelfPreviewController.shared.toggle(item: item)
    }

    private func handleEscape() {
        if ShelfPreviewController.shared.isVisible {
            ShelfPreviewController.shared.dismiss()
        } else if expandedItem != nil {
            collapseExpansion()
        } else {
            NotificationCenter.default.post(name: .dismissShelfPanel, object: nil)
        }
    }

    private func handleArrow(_ direction: ArrowDirection) {
        if let expandedID = expandedItem,
           let item = sortedItems.first(where: { $0.id == expandedID }) {
            let items = sortedItems
            switch (direction, expandedSelection) {
            case (.left, nil):
                if let p = item.displacedPrev, p >= 0, p < items.count {
                    expandedSelection = 0
                }
            case (.right, nil):
                if let n = item.displacedNext, n >= 0, n < items.count {
                    expandedSelection = 1
                }
            case (.right, .some(0)):
                expandedSelection = nil
            case (.left, .some(1)):
                expandedSelection = nil
            default:
                break
            }
            return
        }

        let displayed = displayedItems
        guard !displayed.isEmpty else { return }

        if ShelfPreviewController.shared.isVisible {
            ShelfPreviewController.shared.dismiss()
        }

        guard let currentID = selectedID,
              let idx = displayed.firstIndex(where: { $0.id == currentID }) else {
            selectedID = displayed.first?.id
            return
        }

        switch direction {
        case .left:
            if idx > 0 { selectedID = displayed[idx - 1].id }
        case .right:
            if idx < displayed.count - 1 {
                selectedID = displayed[idx + 1].id
            }
            if idx >= loadedCount - 5 {
                loadedCount = min(loadedCount + bufferPage, sortedItems.count)
            }
        }
    }

    private func handleScroll(_ delta: CGFloat) {
        if delta > 0 {
            handleArrow(.left)
        } else if delta < 0 {
            handleArrow(.right)
        }
    }

    @ViewBuilder
    private func clipContextMenu(for item: ClipItem) -> some View {
        Button("Copy") { store.copyToClipboard(item) }
        if item.contentType != .image, item.textContent != nil {
            Button("Copy as Text") { store.copyTextToClipboard(item) }
        }
        if item.sourceFilePath != nil {
            Button("Copy Path") { store.copyPathToClipboard(item) }
        }
        Divider()
        Button("Edit") { store.editItem(item) }
        Divider()
        Button(item.isPinned ? "Unpin" : "Pin") { store.togglePin(item) }
        Divider()
        Button("Delete") { deleteItem(item) }
    }

    private func deleteItem(_ item: ClipItem) {
        if ShelfPreviewController.shared.currentItem?.id == item.id {
            ShelfPreviewController.shared.dismiss()
        }
        collapseExpansion()
        store.delete(item)
    }

    private func handleDelete() {
        guard let id = selectedID,
              let item = sortedItems.first(where: { $0.id == id }) else { return }
        let items = sortedItems
        let idx = items.firstIndex(where: { $0.id == id })
        if ShelfPreviewController.shared.currentItem?.id == id {
            ShelfPreviewController.shared.dismiss()
        }
        collapseExpansion()
        store.delete(item)

        if let idx = idx {
            let remaining = sortedItems
            if !remaining.isEmpty {
                let newIdx = min(idx, remaining.count - 1)
                selectedID = remaining[newIdx].id
            } else {
                selectedID = nil
            }
        }
    }

    private func handleReturn() {
        if let expandedID = expandedItem,
           let item = sortedItems.first(where: { $0.id == expandedID }),
           let sel = expandedSelection {
            let items = sortedItems
            let idx = sel == 0 ? item.displacedPrev : item.displacedNext
            if let idx = idx, idx >= 0, idx < items.count {
                store.copyToClipboard(items[idx])
            }
            return
        }

        guard let id = selectedID,
              let item = sortedItems.first(where: { $0.id == id }) else { return }
        store.copyToClipboard(item)
    }
}

enum ArrowDirection {
    case left, right
}

// MARK: - Clip Card

struct ClipCardView: View {
    let item: ClipItem
    let isSelected: Bool
    var showNeighborHint: Bool = false
    @ObservedObject private var settings = ShelfSettings.shared
    @State private var isHovered = false
    @State private var loadedImage: NSImage?

    private var accent: Color { Palette.accent(for: item.contentType) }
    private var hasHistory: Bool {
        item.displacedPrev != nil || item.displacedNext != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accent.frame(height: 2)

            VStack(alignment: .leading, spacing: 0) {
                titleBar
                    .frame(width: 180)

                cardContent
                    .frame(width: 180, height: 228)
                    .clipped()

                HStack(spacing: 5) {
                    if item.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    }
                    Text(settings.formatTimestamp(item.timestamp))
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                    if settings.showLineCount, item.contentType != .image,
                       let text = item.textContent {
                        Text("\(text.components(separatedBy: .newlines).count)L")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if settings.showCharCount, item.contentType != .image,
                       let text = item.textContent {
                        Text("\(text.count)c")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    if showNeighborHint {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    typeIcon
                        .font(.system(size: 11))
                        .foregroundStyle(accent.opacity(0.5))
                }
                .padding(.top, 6)
            }
            .padding(8)
        }
        .background(
            LinearGradient(
                colors: [
                    isHovered ? Palette.cardTop.opacity(1) : Palette.cardTop.opacity(0.96),
                    Palette.cardBottom.opacity(0.96)
                ],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isSelected
                        ? accent.opacity(0.7)
                        : Palette.cardEdge.opacity(isHovered ? 0.7 : 0.4),
                    lineWidth: isSelected ? 1.5 : 0.5
                )
        )
        .overlay(alignment: .topTrailing) {
            if hasHistory {
                Image(systemName: "square.3.layers.3d")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.6))
                    .padding(.top, 10)
                    .padding(.trailing, 8)
            }
        }
        .compositingGroup()
        .shadow(
            color: isSelected
                ? accent.opacity(0.25)
                : Palette.shadow,
            radius: isSelected ? 12 : 6,
            x: 0, y: isSelected ? 2 : 4
        )
        .shadow(
            color: accent.opacity(isSelected ? 0.18 : 0.08),
            radius: 16, x: 0, y: 10
        )
        .onHover { hov in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = hov }
        }
    }

    @ViewBuilder
    private var titleBar: some View {
        let path = item.titlePath
        if !path.isEmpty {
            Text(titleAttributed(path))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(accent.opacity(0.08))
                )
        }
    }

    private func titleAttributed(_ path: String) -> AttributedString {
        let components = path.components(separatedBy: "/")
        if components.count > 1, let filename = components.last, !filename.isEmpty {
            let dirPart = String(path.dropLast(filename.count))
            var dir = AttributedString(dirPart)
            dir.font = .system(size: 10, design: .monospaced)
            dir.foregroundColor = .init(Palette.textTertiary)

            var file = AttributedString(filename)
            file.font = .system(size: 13, weight: .semibold, design: .monospaced)
            file.foregroundColor = .init(Palette.textPrimary)
            return dir + file
        }
        var attr = AttributedString(path)
        attr.font = .system(size: 13, weight: .semibold, design: .monospaced)
        attr.foregroundColor = .init(Palette.textPrimary)
        return attr
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.contentType {
        case .image:
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 228)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                placeholder("photo")
                    .onAppear { loadedImage = item.loadImage() }
            }
        case .url:
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: "link")
                    .font(.system(size: 13))
                    .foregroundStyle(accent.opacity(0.7))
                Text(item.preview)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(8)
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .text:
            Text(item.preview)
                .font(.system(size: 13, design: .monospaced))
                .lineLimit(9)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 28))
            .foregroundStyle(accent.opacity(0.35))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var typeIcon: some View {
        Group {
            switch item.contentType {
            case .text: Image(systemName: "doc.text")
            case .url: Image(systemName: "link")
            case .image: Image(systemName: "photo")
            }
        }
    }
}

// MARK: - Neighbor Peek Card

struct NeighborPeekCard: View {
    let item: ClipItem
    let isHighlighted: Bool
    @ObservedObject private var settings = ShelfSettings.shared
    @State private var loadedImage: NSImage?

    private var accent: Color { Palette.accent(for: item.contentType) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            accent.frame(height: 2)

            VStack(alignment: .leading, spacing: 3) {
                peekContent
                    .frame(width: 120, height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 3))

                Text(settings.formatTimestamp(item.timestamp))
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(6)
        }
        .background(
            LinearGradient(
                colors: [Palette.cardTop.opacity(0.96), Palette.cardBottom.opacity(0.96)],
                startPoint: .top, endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isHighlighted
                        ? accent.opacity(0.7)
                        : Palette.cardEdge.opacity(0.4),
                    lineWidth: isHighlighted ? 1.5 : 0.5
                )
        )
        .compositingGroup()
        .shadow(
            color: isHighlighted
                ? accent.opacity(0.2)
                : Palette.shadow,
            radius: isHighlighted ? 8 : 4,
            x: 0, y: 3
        )
    }

    @ViewBuilder
    private var peekContent: some View {
        switch item.contentType {
        case .image:
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.medium)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 108)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 18))
                    .foregroundStyle(accent.opacity(0.35))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { loadedImage = item.loadImage() }
            }
        case .url, .text:
            Text(item.preview)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(7)
                .foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Key Capture

struct KeyCaptureView: NSViewRepresentable {
    let onSpace: () -> Void
    let onEscape: () -> Void
    let onArrow: (ArrowDirection) -> Void
    let onDelete: () -> Void
    let onReturn: () -> Void
    let onCopy: () -> Void
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onArrow = onArrow
        view.onDelete = onDelete
        view.onReturn = onReturn
        view.onCopy = onCopy
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onSpace = onSpace
        nsView.onEscape = onEscape
        nsView.onArrow = onArrow
        nsView.onDelete = onDelete
        nsView.onReturn = onReturn
        nsView.onCopy = onCopy
        nsView.onScroll = onScroll
    }
}

class KeyCaptureNSView: NSView {
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrow: ((ArrowDirection) -> Void)?
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?
    var onCopy: (() -> Void)?
    var onScroll: ((CGFloat) -> Void)?

    private var scrollMonitor: Any?
    private var scrollAccum: CGFloat = 0

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }

        guard window != nil else { return }

        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
        }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self = self,
                  let w = self.window,
                  event.window == w else { return event }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY

            guard abs(dy) > abs(dx) else { return event }

            self.scrollAccum += dy

            if abs(self.scrollAccum) >= 20 {
                self.onScroll?(self.scrollAccum)
                self.scrollAccum = 0
            }

            if event.phase == .ended || event.phase == .cancelled {
                self.scrollAccum = 0
            }

            return nil
        }
    }

    deinit {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            onCopy?()
            return
        }

        switch Int(event.keyCode) {
        case 49: onSpace?()
        case 53: onEscape?()
        case 123: onArrow?(.left)
        case 124: onArrow?(.right)
        case 51: onDelete?()
        case 36: onReturn?()
        default: super.keyDown(with: event)
        }
    }
}

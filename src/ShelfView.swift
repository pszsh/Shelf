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

// MARK: - Shelf View

struct ShelfView: View {
    @ObservedObject var store: ClipStore
    @State private var selectedID: UUID? = nil
    @State private var expandedItem: UUID? = nil
    @State private var expandedSelection: Int? = nil

    private var sortedItems: [ClipItem] {
        store.items.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.timestamp > b.timestamp
        }
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
                    onCopy: handleReturn
                )
            )
    }

    private var shelf: some View {
        let items = sortedItems
        let trayHeight: CGFloat = 260
        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                )
                .frame(height: trayHeight)

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            cardGroup(for: item, in: items)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }
                .onChange(of: selectedID) {
                    if let id = selectedID {
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
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

        let items = sortedItems
        guard !items.isEmpty else { return }

        if ShelfPreviewController.shared.isVisible {
            ShelfPreviewController.shared.dismiss()
        }

        guard let currentID = selectedID,
              let idx = items.firstIndex(where: { $0.id == currentID }) else {
            selectedID = items.first?.id
            return
        }

        switch direction {
        case .left:
            if idx > 0 { selectedID = items[idx - 1].id }
        case .right:
            if idx < items.count - 1 { selectedID = items[idx + 1].id }
        }
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
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleBar
                .frame(width: 180)

            cardContent
                .frame(width: 180, height: 230)
                .clipped()

            HStack(spacing: 6) {
                if item.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                Text(item.relativeTime)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if showNeighborHint {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                }
                typeIcon
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, 6)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected
                              ? Color.accentColor
                              : Color.white.opacity(0.4), lineWidth: isSelected ? 2 : 1)
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder
    private var titleBar: some View {
        let path = item.titlePath
        if !path.isEmpty {
            Text(titleAttributed(path))
                .lineLimit(1)
                .truncationMode(.head)
                .shadow(color: .white.opacity(0.6), radius: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                )
        }
    }

    private func titleAttributed(_ path: String) -> AttributedString {
        let components = path.components(separatedBy: "/")
        if components.count > 1, let filename = components.last, !filename.isEmpty {
            let dirPart = String(path.dropLast(filename.count))
            var dir = AttributedString(dirPart)
            dir.font = .system(size: 13, design: .monospaced)
            dir.foregroundColor = .white.opacity(0.7)

            var file = AttributedString(filename)
            file.font = .system(size: 17, weight: .bold, design: .monospaced)
            file.foregroundColor = .white
            return dir + file
        }
        var attr = AttributedString(path)
        attr.font = .system(size: 17, weight: .bold, design: .monospaced)
        attr.foregroundColor = .white
        return attr
    }

    @ViewBuilder
    private var cardContent: some View {
        switch item.contentType {
        case .image:
            if let image = item.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 180, height: 230)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                placeholder("photo")
            }
        case .url:
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "link")
                    .font(.system(size: 15))
                    .foregroundStyle(.blue)
                Text(item.preview)
                    .font(.system(size: 14, design: .monospaced))
                    .lineLimit(7)
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .text:
            Text(item.preview)
                .font(.system(size: 14, design: .monospaced))
                .lineLimit(9)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 30))
            .foregroundStyle(.white.opacity(0.5))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            peekContent
                .frame(width: 120, height: 112)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            Text(item.relativeTime)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(
                    isHighlighted
                        ? Color.accentColor
                        : Color.white.opacity(0.4),
                    lineWidth: isHighlighted ? 2 : 1
                )
        )
    }

    @ViewBuilder
    private var peekContent: some View {
        switch item.contentType {
        case .image:
            if let image = item.loadImage() {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 112)
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .url, .text:
            Text(item.preview)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(7)
                .foregroundStyle(.white)
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

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onArrow = onArrow
        view.onDelete = onDelete
        view.onReturn = onReturn
        view.onCopy = onCopy
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onSpace = onSpace
        nsView.onEscape = onEscape
        nsView.onArrow = onArrow
        nsView.onDelete = onDelete
        nsView.onReturn = onReturn
        nsView.onCopy = onCopy
    }
}

class KeyCaptureNSView: NSView {
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?
    var onArrow: ((ArrowDirection) -> Void)?
    var onDelete: (() -> Void)?
    var onReturn: (() -> Void)?
    var onCopy: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.window?.makeFirstResponder(self)
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

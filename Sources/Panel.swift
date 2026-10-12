import AppKit

/// The floating switcher: a search bar on top of a grid of windows.
///
/// To stay smooth while typing, nothing is rebuilt: cells are kept per item and only moved, the grid's cell
/// size and column count are fixed for the whole session, and the panel's top edge (with the search bar)
/// stays put while results grow or shrink below it.
final class SwitcherPanel: NSPanel {
    var onHover: ((Int) -> Void)?
    var onClick: ((Int) -> Void)?
    var onAction: ((Int, WindowAction) -> Void)?
    var onSearchClick: (() -> Void)?
    var onSearchClear: (() -> Void)?

    /// Cells per row in the current layout, for ↑/↓ navigation.
    var columns: Int { layout?.grid.columns ?? 1 }

    private let background = NSVisualEffectView()
    private let searchBar = SearchBar()
    /// Scrolls only when there are more windows than fit even at the smallest size.
    private let scrollView = NSScrollView()
    private let grid = FlippedView()
    private var announced: (index: Int, label: String)?
    private let emptyLabel = NSTextField(labelWithString: String(localized: "No Matching Windows"))
    private var cells: [ObjectIdentifier: ItemCell] = [:]
    private var layout: Layout?
    fileprivate var mouseAtShow = NSPoint.zero

    private struct Layout {
        let style: SwitcherStyle
        let grid: Grid
        let width: CGFloat
        let maxGridHeight: CGFloat
        let area: CGRect
        var top: CGFloat?
    }

    private static let margin: CGFloat = 14
    private static let gap: CGFloat = 6
    private static let searchHeight: CGFloat = 46
    private static let searchGap: CGFloat = 12
    static let minContentWidth: CGFloat = 540
    private static let emptyHeight: CGFloat = 72
    private static let cornerRadius: CGFloat = 22

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        let r = Self.cornerRadius
        let mask = NSImage(size: NSSize(width: r * 2 + 1, height: r * 2 + 1), flipped: false) { rect in
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        mask.resizingMode = .stretch
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = mask
        background.setAccessibilityRole(.list)
        background.setAccessibilityLabel(String(localized: "Windows"))
        contentView = background

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.documentView = grid
        searchBar.onClick = { [weak self] in self?.onSearchClick?() }
        searchBar.onClear = { [weak self] in self?.onSearchClear?() }
        background.addSubview(searchBar)
        background.addSubview(scrollView)
        grid.addSubview(emptyLabel)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows or updates the switcher. Cheap to call on every keystroke.
    func present(_ items: [SwitcherItem], selected: Int, query: String, total: Int, style: SwitcherStyle, on screen: NSScreen) {
        appearance = Prefs.theme.appearance
        if layout == nil || layout?.style != style {
            let top = layout?.top
            layout = makeLayout(count: max(items.count, 1), style: style, screen: screen)
            if isVisible { layout?.top = top }
            // Cells are sized for a layout; never mix sizes.
            cells.values.forEach { $0.removeFromSuperview() }
            cells = [:]
        }
        guard var layout else { return }

        let columns = layout.grid.columns, cell = layout.grid.cell
        let rows = items.isEmpty ? 0 : (items.count + columns - 1) / columns
        let gridHeight = rows == 0 ? Self.emptyHeight : CGFloat(rows) * cell.height + CGFloat(rows - 1) * Self.gap
        let visibleGridHeight = min(gridHeight, layout.maxGridHeight)
        let height = Self.margin * 2 + Self.searchHeight + Self.searchGap + visibleGridHeight
        // Centered at its largest: growing (e.g. browser tabs arriving) re-centers, shrinking (typing a search)
        // keeps the top edge, and with it the search bar, exactly where it was.
        let centeredTop = min(layout.area.midY + height / 2, layout.area.maxY - 8)
        if layout.top == nil || centeredTop > layout.top! {
            layout.top = centeredTop
            self.layout = layout
        }
        let frame = CGRect(x: layout.area.midX - layout.width / 2, y: layout.top! - height, width: layout.width, height: height).integral

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if self.frame != frame { setFrame(frame, display: false) }
        searchBar.frame = CGRect(x: Self.margin, y: frame.height - Self.margin - Self.searchHeight,
                                 width: frame.width - Self.margin * 2, height: Self.searchHeight)
        searchBar.update(query: query, shown: items.count, total: total,
                         placeholder: Prefs.browserTabs == .off ? String(localized: "Search windows") : String(localized: "Search windows and tabs"))
        scrollView.frame = CGRect(x: Self.margin, y: Self.margin, width: frame.width - Self.margin * 2, height: visibleGridHeight)
        grid.frame = CGRect(x: 0, y: 0, width: scrollView.frame.width, height: gridHeight)
        emptyLabel.isHidden = !items.isEmpty
        emptyLabel.frame = CGRect(x: 0, y: (gridHeight - 20) / 2, width: grid.frame.width, height: 20)

        let gridWidth = CGFloat(columns) * cell.width + CGFloat(columns - 1) * Self.gap
        let originX = (grid.frame.width - gridWidth) / 2
        var next: [ObjectIdentifier: ItemCell] = [:]
        for (index, item) in items.enumerated() {
            let key = item.identity
            let view = cells[key] ?? makeCell(for: item, layout: layout)
            view.configure(item, query: query, index: index)
            let row = index / columns, column = index % columns
            let inRow = row == rows - 1 ? items.count - row * columns : columns
            let inset = style == .list ? 0 : CGFloat(columns - inRow) * (cell.width + Self.gap) / 2
            view.frame.origin = CGPoint(x: originX + inset + CGFloat(column) * (cell.width + Self.gap),
                                        y: CGFloat(row) * (cell.height + Self.gap))
            next[key] = view
        }
        for (key, view) in cells where next[key] == nil { view.removeFromSuperview() }
        cells = next
        CATransaction.commit()

        select(selected)
        if !isVisible {
            mouseAtShow = NSEvent.mouseLocation
            orderFrontRegardless()
            searchBar.restartCaret()
        }
        display()
    }

    /// Shows the search field as focused (after it was clicked, or once there's text).
    func setSearchFocused(_ focused: Bool) {
        searchBar.isFocused = focused
    }

    func select(_ index: Int) {
        for cell in cells.values { cell.isSelected = cell.index == index }
        guard let cell = cells.values.first(where: { $0.index == index }) else { return }
        grid.scrollToVisible(cell.frame.insetBy(dx: 0, dy: -Self.gap))
        // Announce a change of selection, not every redraw (typing would otherwise repeat it).
        let label = cell.accessibilityLabel() ?? ""
        if NSWorkspace.shared.isVoiceOverEnabled, announced?.index != index || announced?.label != label {
            announced = (index, label)
            NSAccessibility.post(element: cell, notification: .announcementRequested,
                                 userInfo: [.announcement: label, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    func update(id: CGWindowID, image: CGImage) {
        cells.values.filter { $0.thumbnailID == id }.forEach { $0.setThumbnail(image) }
    }

    /// Hides the panel and forgets the session's layout.
    func reset() {
        orderOut(nil)
        cells.values.forEach { $0.removeFromSuperview() }
        cells = [:]
        layout = nil
        announced = nil
        searchBar.isFocused = false
    }

    #if DEBUG
    /// Snapshots: show the hover controls on one cell.
    func showHoverControls(at index: Int) {
        cells.values.first { $0.index == index }?.isHovered = true
    }
    #endif

    fileprivate func cellHovered(_ cell: ItemCell) {
        for other in cells.values where other !== cell { other.isHovered = false }
        onHover?(cell.index)
    }

    private func makeLayout(count: Int, style: SwitcherStyle, screen: NSScreen) -> Layout {
        let area = screen.visibleFrame
        let space = CGSize(width: area.width * 0.9 - Self.margin * 2,
                           height: area.height * 0.86 - Self.margin * 2 - Self.searchHeight - Self.searchGap)
        var grid = Grid.fit(count: count, style: style, in: space, gap: Self.gap, maxScale: Prefs.size.maxScale)
        if style == .list { grid.cell.width = Self.minContentWidth }
        let gridWidth = CGFloat(grid.columns) * grid.cell.width + CGFloat(grid.columns - 1) * Self.gap
        return Layout(style: style, grid: grid, width: max(gridWidth, Self.minContentWidth) + Self.margin * 2,
                      maxGridHeight: space.height, area: area, top: nil)
    }

    private func makeCell(for item: SwitcherItem, layout: Layout) -> ItemCell {
        let cell = ItemCell(item: item, style: layout.style, scale: layout.grid.scale, size: layout.grid.cell)
        cell.panel = self
        grid.addSubview(cell)
        return cell
    }
}

/// Picks the largest cell scale (and column count) at which every item fits.
struct Grid {
    var cell: CGSize
    var scale: CGFloat
    var columns: Int
    var rows: Int

    func size(gap: CGFloat) -> CGSize {
        CGSize(width: CGFloat(columns) * cell.width + CGFloat(columns - 1) * gap,
               height: rows == 0 ? 0 : CGFloat(rows) * cell.height + CGFloat(rows - 1) * gap)
    }

    static let minScale: CGFloat = 0.5

    static func fit(count: Int, style: SwitcherStyle, in space: CGSize, gap: CGFloat, maxScale: CGFloat = 1.25) -> Grid {
        guard count > 0 else { return Grid(cell: .zero, scale: 1, columns: 1, rows: 0) }
        var scale = style == .list ? 1 : max(maxScale, minScale)
        while true {
            let cell = ItemCell.size(for: style, scale: scale)
            let fittingColumns = Int((space.width + gap) / (cell.width + gap))
            let fittingRows = Int((space.height + gap) / (cell.height + gap))
            let maxColumns = max(1, fittingColumns), maxRows = max(1, fittingRows)
            // Fewest columns that fit for a list; otherwise as wide as possible, with rows balanced (6 → 3+3, not 5+1).
            let neededRows = Int((Double(count) / Double(style == .list ? maxRows : maxColumns)).rounded(.up))
            let columns = style == .list
                ? min(maxColumns, neededRows)
                : min(maxColumns, Int((Double(count) / Double(neededRows)).rounded(.up)))
            let rows = Int((Double(count) / Double(columns)).rounded(.up))
            if (rows <= fittingRows && fittingColumns >= 1) || scale <= minScale {
                return Grid(cell: cell, scale: scale, columns: columns, rows: rows)
            }
            scale -= 0.05
        }
    }
}

// MARK: - Search bar

private final class SearchBar: NSView {
    var onClick: (() -> Void)?
    var onClear: (() -> Void)?
    /// Drawn with an accent focus ring, like a focused macOS text field.
    var isFocused = false { didSet { if isFocused != oldValue { needsDisplay = true } } }

    private let icon = NSImageView()
    private let text = NSTextField(labelWithString: "")
    private let placeholder = NSTextField(labelWithString: "")
    private let count = NSTextField(labelWithString: "")
    private let clearButton = NSImageView()
    private let caret = CALayer()
    private var query = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        icon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: String(localized: "Search"))
        icon.symbolConfiguration = .init(pointSize: 17, weight: .regular)
        icon.contentTintColor = .secondaryLabelColor
        text.font = .systemFont(ofSize: 20)
        text.lineBreakMode = .byTruncatingHead
        placeholder.font = .systemFont(ofSize: 20)
        placeholder.textColor = .tertiaryLabelColor
        count.font = .systemFont(ofSize: 13, weight: .medium)
        count.textColor = .secondaryLabelColor
        count.alignment = .right
        // Drawn as an image; the field handles the click, which works even though the panel never becomes key.
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: String(localized: "Clear"))
        clearButton.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        clearButton.contentTintColor = .tertiaryLabelColor
        clearButton.isHidden = true
        [icon, placeholder, text, count, clearButton].forEach(addSubview)
        layer?.addSublayer(caret)
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
        let focused = isFocused || !query.isEmpty
        layer?.borderWidth = focused ? 2 : 1
        layer?.borderColor = focused ? NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
                                     : NSColor.labelColor.withAlphaComponent(0.1).cgColor
        caret.backgroundColor = NSColor.controlAccentColor.cgColor
    }

    /// A text caret like macOS's: solid while you type, then blinking on and off. Restarted on every change
    /// and every time the switcher appears (macOS drops layer animations while a window is hidden).
    func restartCaret() {
        caret.removeAnimation(forKey: "blink")
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [1, 0]
        blink.keyTimes = [0, 0.5, 1]
        blink.calculationMode = .discrete
        blink.duration = 1.06
        blink.repeatCount = .infinity
        blink.beginTime = caret.convertTime(CACurrentMediaTime(), from: nil) + 0.5
        blink.fillMode = .backwards
        blink.isRemovedOnCompletion = false
        caret.add(blink, forKey: "blink")
    }

    func update(query: String, shown: Int, total: Int, placeholder placeholderText: String) {
        let changed = query != self.query
        self.query = query
        let h = bounds.height
        icon.frame = CGRect(x: 14, y: (h - 22) / 2, width: 22, height: 22)
        clearButton.isHidden = query.isEmpty
        clearButton.frame = CGRect(x: bounds.width - 34, y: (h - 22) / 2, width: 22, height: 22)
        count.stringValue = query.isEmpty ? "" : String(localized: "\(shown) of \(total)")
        count.sizeToFit()
        let countRight = query.isEmpty ? bounds.width - 16 : clearButton.frame.minX - 8
        count.frame.origin = CGPoint(x: countRight - count.frame.width, y: (h - count.frame.height) / 2)

        let textX: CGFloat = 46
        let maxTextWidth = count.frame.minX - textX - 16
        text.stringValue = query
        placeholder.stringValue = placeholderText
        placeholder.isHidden = !query.isEmpty
        let textWidth = min(ceil(text.attributedStringValue.size().width), maxTextWidth)
        text.frame = CGRect(x: textX, y: (h - 26) / 2, width: max(textWidth + 4, 1), height: 26)
        placeholder.frame = CGRect(x: textX, y: (h - 26) / 2, width: maxTextWidth, height: 26)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        caret.frame = CGRect(x: textX + (query.isEmpty ? 0 : textWidth + 1), y: (h - 24) / 2, width: 2, height: 24)
        CATransaction.commit()
        if changed { restartCaret() }
        needsDisplay = true
        setAccessibilityValue(query)
        setAccessibilityLabel(placeholderText)
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { updateCursor(event) }
    override func mouseMoved(with event: NSEvent) { updateCursor(event) }
    override func mouseExited(with event: NSEvent) { NSCursor.arrow.set() }

    private func updateCursor(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        (clearButton.isHidden || !clearButton.frame.contains(point) ? NSCursor.iBeam : NSCursor.arrow).set()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if !clearButton.isHidden && clearButton.frame.insetBy(dx: -4, dy: -4).contains(point) {
            onClear?()
        } else {
            onClick?()
        }
        restartCaret()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Cell

private final class ItemCell: NSView {
    var index = 0
    let thumbnailID: CGWindowID?
    weak var panel: SwitcherPanel?

    private let style: SwitcherStyle
    private let thumbArea: CGRect
    private let thumbView = FlippedView()
    private let title = NSTextField(labelWithString: "")
    private let subtitle = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let lights: TrafficLights
    private var badges: FlippedView?
    private var badgeSymbols: [String] = []
    private var hasThumbnail = false
    private var item: SwitcherItem
    private var query = ""

    var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            if style == .list { applyText() }
        }
    }
    var isHovered = false { didSet { lights.isHidden = !isHovered; badges?.isHidden = isHovered && style == .list } }

    private static let padding: CGFloat = 8
    private static let headerHeight: CGFloat = 18
    private static let listHeight: CGFloat = 34

    static func size(for style: SwitcherStyle, scale: CGFloat) -> CGSize {
        switch style {
        case .thumbnails: CGSize(width: 220 * scale + padding * 2, height: headerHeight + 6 + 138 * scale + padding * 2)
        case .icons: CGSize(width: max(96 * scale, 76) + padding * 2, height: 64 * scale + 6 + 16 + padding * 2)
        case .list: CGSize(width: SwitcherPanel.minContentWidth, height: listHeight)
        }
    }

    init(item: SwitcherItem, style: SwitcherStyle, scale: CGFloat, size: CGSize) {
        self.item = item
        self.style = style
        self.thumbnailID = item.thumbnailID
        self.lights = TrafficLights(actions: item.actions)
        let p = Self.padding
        switch style {
        case .thumbnails:
            let top = p + Self.headerHeight + 6
            thumbArea = CGRect(x: p, y: top, width: size.width - p * 2, height: size.height - top - p)
        case .icons:
            let side = 64 * scale
            thumbArea = CGRect(x: (size.width - side) / 2, y: p, width: side, height: side)
        case .list:
            thumbArea = CGRect(x: 10, y: (size.height - 20) / 2, width: 20, height: 20)
        }
        super.init(frame: CGRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.cornerRadius = style == .list ? 8 : 12
        layer?.cornerCurve = .continuous
        setAccessibilityElement(true)
        setAccessibilityRole(.button)

        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = style == .thumbnails ? 6 : 0
        thumbView.layer?.cornerCurve = .continuous
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.contentsGravity = .resizeAspect
        addSubview(thumbView)

        title.font = .systemFont(ofSize: style == .list ? 13 : 12.5, weight: style == .thumbnails ? .medium : .regular)
        title.cell?.truncatesLastVisibleLine = true
        addSubview(title)
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.alignment = .right
        if style == .list { addSubview(subtitle) }
        icon.image = item.app.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        if style == .thumbnails { addSubview(icon) }

        if style == .thumbnails, let id = item.thumbnailID, let image = Thumbnails.shared.cache[id] {
            setThumbnail(image)
        } else {
            showIcon(item.app.icon)
        }

        lights.isHidden = true
        lights.onAction = { [weak self] action in
            guard let self else { return }
            self.panel?.onAction?(self.index, action)
        }
        addSubview(lights)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if style == .list {
            layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.cgColor : nil
            layer?.borderWidth = 0
        } else {
            layer?.backgroundColor = isSelected ? NSColor.labelColor.withAlphaComponent(0.08).cgColor : nil
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            layer?.borderWidth = isSelected ? 2.5 : 0
        }
        if style == .thumbnails && !hasThumbnail {
            thumbView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            thumbView.layer?.borderColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
            thumbView.layer?.borderWidth = 1
        }
    }

    override func accessibilityPerformPress() -> Bool {
        panel?.onClick?(index)
        return true
    }

    /// Updates everything that can change while the switcher is open.
    func configure(_ item: SwitcherItem, query: String, index: Int) {
        self.item = item
        self.query = query
        self.index = index
        // The hover buttons, for VoiceOver users.
        setAccessibilityCustomActions(item.actions.map { action in
            NSAccessibilityCustomAction(name: action.title) { [weak self] in
                guard let self else { return false }
                self.panel?.onAction?(self.index, action)
                return true
            }
        })
        toolTip = item.subtitle().isEmpty ? item.title : "\(item.title)\n\(item.subtitle())"
        setAccessibilityLabel(item.accessibilityLabel)
        updateBadges()
        applyText()
        layoutContent()
    }

    private func applyText() {
        let onAccent = style == .list && isSelected
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = Prefs.truncation.lineBreakMode
        paragraph.alignment = style == .icons ? .center : .natural
        let text = item.title(Prefs.titleStyle)
        let string = NSMutableAttributedString(string: text, attributes: [
            .font: title.font!, .foregroundColor: onAccent ? NSColor.white : NSColor.labelColor, .paragraphStyle: paragraph,
        ])
        for range in Search.highlights(query, in: text) {
            string.addAttributes([.backgroundColor: NSColor.findHighlightColor, .foregroundColor: NSColor.black], range: range)
        }
        title.attributedStringValue = string
        subtitle.stringValue = item.subtitle(Prefs.titleStyle)
        subtitle.textColor = onAccent ? NSColor.white.withAlphaComponent(0.85) : .secondaryLabelColor
        badges?.subviews.forEach { ($0 as? NSImageView)?.contentTintColor = onAccent ? .white : .secondaryLabelColor }
    }

    private func layoutContent() {
        let p = Self.padding, w = bounds.width, h = bounds.height
        let badgeWidth = badges?.frame.width ?? 0
        switch style {
        case .thumbnails:
            icon.frame = CGRect(x: p, y: p, width: Self.headerHeight, height: Self.headerHeight)
            title.frame = CGRect(x: icon.frame.maxX + 6, y: p, width: w - p * 2 - Self.headerHeight - 6 - (badgeWidth > 0 ? badgeWidth + 6 : 0),
                                 height: Self.headerHeight)
            badges?.frame.origin = CGPoint(x: w - p - badgeWidth, y: p + 3)
        case .icons:
            title.frame = CGRect(x: 4, y: thumbArea.maxY + 6, width: w - 8, height: 16)
            badges?.frame.origin = CGPoint(x: thumbArea.maxX - badgeWidth + 4, y: thumbArea.minY - 2)
            lights.frame.origin = CGPoint(x: 6, y: 6)
        case .list:
            let trailing = max(badgeWidth, lights.frame.width) + 18
            subtitle.sizeToFit()
            let subtitleWidth = min(subtitle.frame.width, 190)
            subtitle.frame = CGRect(x: w - trailing - subtitleWidth, y: (h - 16) / 2, width: subtitleWidth, height: 16)
            title.frame = CGRect(x: thumbArea.maxX + 10, y: (h - 17) / 2, width: subtitle.frame.minX - thumbArea.maxX - 20, height: 17)
            badges?.frame.origin = CGPoint(x: w - 10 - badgeWidth, y: (h - 12) / 2)
            lights.frame.origin = CGPoint(x: w - 10 - lights.frame.width, y: (h - lights.frame.height) / 2)
        }
        if style == .thumbnails && !hasThumbnail { lights.frame.origin = CGPoint(x: thumbArea.minX + 7, y: thumbArea.minY + 7) }
    }

    func setThumbnail(_ image: CGImage) {
        hasThumbnail = true
        thumbView.subviews.forEach { $0.removeFromSuperview() }
        thumbView.layer?.backgroundColor = nil
        thumbView.layer?.borderWidth = 0
        thumbView.layer?.contents = image
        // Fit the view to the image so the rounded corners land on the image itself.
        let fit = min(thumbArea.width / CGFloat(image.width), thumbArea.height / CGFloat(image.height))
        let w = CGFloat(image.width) * fit, h = CGFloat(image.height) * fit
        thumbView.frame = CGRect(x: thumbArea.midX - w / 2, y: thumbArea.minY + (thumbArea.height - h) / 2, width: w, height: h).integral
        lights.frame.origin = CGPoint(x: thumbView.frame.minX + 7, y: thumbView.frame.minY + 7)
    }

    private func showIcon(_ image: NSImage?) {
        guard style == .thumbnails else {
            thumbView.frame = thumbArea
            let imageView = NSImageView(frame: thumbView.bounds)
            imageView.image = image
            imageView.imageScaling = .scaleProportionallyUpOrDown
            thumbView.addSubview(imageView)
            return
        }
        // No picture (a background tab, or a window macOS isn't drawing): a plain card with the app icon,
        // and the site for tabs, so it reads as deliberate rather than missing.
        thumbView.frame = thumbArea
        let host = item.isTab ? item.subtitle() : ""
        let side = min(56, thumbArea.height * 0.5)
        let textHeight: CGFloat = host.isEmpty ? 0 : 22
        let imageView = NSImageView(frame: CGRect(x: (thumbArea.width - side) / 2, y: (thumbArea.height - side - textHeight) / 2,
                                                  width: side, height: side))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.addSubview(imageView)
        if !host.isEmpty {
            let label = NSTextField(labelWithString: host)
            label.font = .systemFont(ofSize: 11.5)
            label.textColor = .secondaryLabelColor
            label.alignment = .center
            label.lineBreakMode = .byTruncatingMiddle
            label.frame = CGRect(x: 10, y: imageView.frame.maxY + 6, width: thumbArea.width - 20, height: 16)
            thumbView.addSubview(label)
        }
        needsDisplay = true
    }

    /// Small symbols marking tabs, minimized windows, hidden apps and windows on another Space.
    private func updateBadges() {
        var symbols: [(String, String)] = []
        if Prefs.showBadges {
            if item.isTab { symbols.append(("globe", String(localized: "Browser tab"))) }
            if item.isMinimized { symbols.append(("minus.circle", String(localized: "Minimized"))) }
            if item.app.isHidden { symbols.append(("eye.slash", String(localized: "App hidden"))) }
            if item.isOnOtherSpace { symbols.append(("square.on.square", String(localized: "On another Space"))) }
        }
        guard symbols.map(\.0) != badgeSymbols else { return }
        badgeSymbols = symbols.map(\.0)
        badges?.removeFromSuperview()
        badges = nil
        guard !symbols.isEmpty else { return }
        let side: CGFloat = 12, spacing: CGFloat = 4
        let view = FlippedView(frame: CGRect(x: 0, y: 0, width: CGFloat(symbols.count) * (side + spacing) - spacing, height: side))
        for (i, (name, label)) in symbols.enumerated() {
            let image = NSImageView(frame: CGRect(x: CGFloat(i) * (side + spacing), y: 0, width: side, height: side))
            image.image = NSImage(systemSymbolName: name, accessibilityDescription: label)
            image.symbolConfiguration = .init(pointSize: 10, weight: .medium)
            image.contentTintColor = .secondaryLabelColor
            image.toolTip = label
            view.addSubview(image)
        }
        view.isHidden = isHovered && style == .list
        addSubview(view, positioned: .below, relativeTo: lights)
        badges = view
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hover() }
    override func mouseMoved(with event: NSEvent) { hover() }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func mouseDown(with event: NSEvent) { panel?.onClick?(index) }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func hover() {
        // Ignore the cursor merely sitting over the panel when it appears.
        guard !isHovered, let panel, NSEvent.mouseLocation != panel.mouseAtShow else { return }
        isHovered = true
        panel.cellHovered(self)
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Traffic lights

/// Close / minimize / full screen buttons drawn like the real ones, symbols appearing on hover.
private final class TrafficLights: NSView {
    var onAction: ((WindowAction) -> Void)?
    private let actions: [WindowAction]
    private var showSymbols = false { didSet { needsDisplay = true } }

    private static let diameter: CGFloat = 12
    private static let spacing: CGFloat = 8

    init(actions: [WindowAction]) {
        self.actions = actions
        let count = CGFloat(actions.count)
        super.init(frame: CGRect(x: 0, y: 0, width: count * Self.diameter + max(count - 1, 0) * Self.spacing, height: Self.diameter))
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (i, action) in actions.enumerated() {
            let rect = CGRect(x: CGFloat(i) * (Self.diameter + Self.spacing), y: 0, width: Self.diameter, height: Self.diameter)
            let (fill, stroke) = action.colors
            let symbol = action.symbol
            fill.setFill()
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 0.25, dy: 0.25))
            circle.fill()
            stroke.setStroke()
            circle.lineWidth = 0.5
            circle.stroke()
            guard showSymbols else { continue }
            let config = NSImage.SymbolConfiguration(pointSize: 7, weight: .heavy)
                .applying(.init(paletteColors: [NSColor.black.withAlphaComponent(0.55)]))
            if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                image.draw(in: CGRect(x: rect.midX - image.size.width / 2, y: rect.midY - image.size.height / 2,
                                      width: image.size.width, height: image.size.height))
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { showSymbols = true }
    override func mouseExited(with event: NSEvent) { showSymbols = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let index = Int(x / (Self.diameter + Self.spacing))
        // Clicks in the gap between two buttons do nothing.
        guard actions.indices.contains(index), x - CGFloat(index) * (Self.diameter + Self.spacing) <= Self.diameter else { return }
        onAction?(actions[index])
    }
}

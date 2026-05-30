import AppKit

/// A small colored status dot overlaid on the menu-bar button.
///
/// It lives as a sibling subview of the `NSStatusBarButton` rather than being
/// drawn into the template glyph, so its color is not flattened to monochrome
/// by the template tinting. `color == nil` hides the dot.
final class StatusDotView: NSView {
    var color: NSColor? {
        didSet {
            guard color != oldValue else {
                return
            }
            isHidden = (color == nil)
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        isHidden = true
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    override func updateLayer() {
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        layer?.backgroundColor = color?.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

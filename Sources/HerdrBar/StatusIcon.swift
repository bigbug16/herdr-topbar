import AppKit

/// The menu bar glyph: herdr's ram, from the project's own `ram.svg`.
///
/// The asset ships as a vector PDF (see `scripts/make-icon.sh`) cropped to the
/// ram's head — at 18pt the full mark's body is an unreadable block, while the
/// curled horn and `>-` prompt face stay recognisable.
enum StatusIcon {

    static let size = NSSize(width: 18, height: 18)

    /// Loaded once: NSImage keeps the PDF representation and re-renders it at
    /// whatever scale the display needs, so one instance covers every size.
    private static let artwork: NSImage? = {
        guard let url = Bundle.main.url(forResource: "ram", withExtension: "pdf"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = size
        return image
    }()

    /// The resting colour: always the dark ram, in either system appearance.
    ///
    /// Fixed rather than appearance-tracking, which is why the icon is not an
    /// AppKit template image — a template would be re-tinted for contrast and
    /// would go white on a dark menu bar. Keeping one constant resting look
    /// means the blink is the only thing that ever changes.
    static let restingTint: NSColor = .black

    /// The colour the blink swaps to.
    static let alertTint: NSColor = .white

    /// The resting icon, painted in `restingTint`. Not a template — see the
    /// note there for why AppKit must not re-tint it.
    static func normal(withDot dot: Bool = false) -> NSImage {
        let image = compose(tint: restingTint, dot: dot)
        image.isTemplate = false
        return image
    }

    /// One frame of the attention blink: either the resting dark ram or the
    /// light one it swaps to.
    static func flashFrame(inverted: Bool) -> NSImage {
        let image = compose(tint: inverted ? alertTint : restingTint, dot: true)
        image.isTemplate = false
        return image
    }

    /// Draw the ram in `tint`, optionally badged.
    private static func compose(tint: NSColor, dot: Bool) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            if let artwork {
                artwork.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
                tint.setFill()
                rect.fill(using: .sourceAtop)
            } else {
                // The bundle lost its resource: draw something rather than an
                // invisible status item the user cannot click.
                fallbackGlyph(in: rect, color: tint)
            }

            if dot {
                let color = tint
                // Punch a transparent gap so the badge stays legible where it
                // overlaps the horn, then fill the badge itself.
                let center = NSPoint(x: rect.maxX - 3.2, y: rect.maxY - 3.2)
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: center.x - 3.6, y: center.y - 3.6,
                                            width: 7.2, height: 7.2)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: center.x - 2.4, y: center.y - 2.4,
                                            width: 4.8, height: 4.8)).fill()
            }
            return true
        }
    }

    private static func fallbackGlyph(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let frame = rect.insetBy(dx: 2, dy: 3.5)
        let border = NSBezierPath(roundedRect: frame, xRadius: 2.6, yRadius: 2.6)
        border.lineWidth = 1.4
        border.stroke()
    }
}

/// Owns the status item's appearance and the attention flash.
///
/// The flash exists because herdr already raises its own notification when an
/// agent needs input — this only makes that easy to notice from anywhere on
/// screen. It alternates the light and dark renderings, so on any menu bar one
/// frame nearly vanishes and the icon reads as a deliberate blink.
final class IconController {

    enum State {
        /// Nothing waiting.
        case idle
        /// An agent is waiting and the user has not looked at herdr yet.
        case flashing
        /// Still waiting, but herdr has been brought forward — stop moving and
        /// leave a static badge so the state is visible but not nagging.
        case acknowledged
    }

    /// Three swaps a second: quick enough to catch the eye in peripheral
    /// vision, slow enough not to read as a rendering glitch.
    private static let blinkInterval: TimeInterval = 1.0 / 3.0

    private weak var button: NSStatusBarButton?
    private var timer: Timer?
    private var inverted = false
    private(set) var state: State = .idle

    init(button: NSStatusBarButton?) {
        self.button = button
        apply()
    }

    func set(_ newState: State) {
        guard newState != state else { return }
        state = newState
        apply()
    }

    private func apply() {
        timer?.invalidate()
        timer = nil

        switch state {
        case .idle:
            button?.image = StatusIcon.normal()
        case .acknowledged:
            button?.image = StatusIcon.normal(withDot: true)
        case .flashing:
            // Start on the alert colour so the very first frame is a visible
            // change rather than the resting look the user already sees.
            inverted = true
            button?.image = StatusIcon.flashFrame(inverted: inverted)
            let timer = Timer(timeInterval: Self.blinkInterval, repeats: true) { [weak self] _ in
                guard let self, self.state == .flashing else { return }
                self.inverted.toggle()
                self.button?.image = StatusIcon.flashFrame(inverted: self.inverted)
            }
            // Common mode: keep blinking while a menu is tracking the run loop.
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    deinit { timer?.invalidate() }
}

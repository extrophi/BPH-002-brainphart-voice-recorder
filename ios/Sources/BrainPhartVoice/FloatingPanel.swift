#if os(macOS)
import Cocoa

// MARK: - Floating Panel

/// Always-on-top window that floats above other apps
/// Appears in full-screen Spaces and all desktop Spaces
class FloatingPanel: NSPanel {
    var showsTitleBar: Bool = false

    // MARK: - Initialization

    init(
        contentRect: NSRect,
        backing: NSWindow.BackingStoreType = .buffered,
        defer flag: Bool = false,
        showsTitleBar: Bool = false
    ) {
        self.showsTitleBar = showsTitleBar

        let styleMask: NSWindow.StyleMask = showsTitleBar
            ? [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
            : [.nonactivatingPanel, .borderless, .fullSizeContentView]

        super.init(
            contentRect: contentRect,
            styleMask: styleMask,
            backing: backing,
            defer: flag
        )

        configureFloatingBehavior()
        configureAppearance()
    }

    // MARK: - Configuration

    private func configureFloatingBehavior() {
        // Make it a floating panel
        self.isFloatingPanel = true

        // Float above normal windows
        self.level = .floating

        // Allow in full-screen Spaces
        self.collectionBehavior.insert(.fullScreenAuxiliary)

        // Show on all desktop Spaces
        self.collectionBehavior.insert(.canJoinAllSpaces)

        // Don't hide when user clicks other apps
        self.hidesOnDeactivate = false

        // Allow moving by clicking anywhere
        self.isMovableByWindowBackground = true
    }

    private func configureAppearance() {
        if showsTitleBar {
            // Full window mode
            self.titleVisibility = .hidden
            self.titlebarAppearsTransparent = true
            self.backgroundColor = NSColor.windowBackgroundColor
            self.isOpaque = true
            self.minSize = NSSize(width: 800, height: 500)

            self.contentView?.wantsLayer = true
            self.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        } else {
            // Floating mode - borderless, clean
            self.titleVisibility = .hidden
            self.titlebarAppearsTransparent = true
            self.backgroundColor = .clear
            self.isOpaque = false

            // Rounded corners
            self.contentView?.wantsLayer = true
            self.contentView?.layer?.cornerRadius = 12
            self.contentView?.layer?.masksToBounds = true
            self.contentView?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    // MARK: - Behavior Overrides

    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
#endif

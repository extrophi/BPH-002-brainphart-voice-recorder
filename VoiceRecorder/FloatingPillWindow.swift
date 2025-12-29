import UIKit
import SwiftUI

// MARK: - Custom Window (Transparent passthrough)

class FloatingPillWindow: UIWindow {

    var pillView: UIView?

    init(scene: UIWindowScene) {
        super.init(windowScene: scene)
        backgroundColor = nil // CRITICAL: Transparent background

        // iOS 18 fix: Handle keyboard properly
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardDidShow),
            name: UIResponder.keyboardDidShowNotification,
            object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // CRITICAL: Only intercept touches ON the pill, pass through everything else
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let pillView = pillView else { return nil }
        let pillPoint = convert(point, to: pillView)
        return pillView.point(inside: pillPoint, with: event) ? super.hitTest(point, with: event) : nil
    }

    @objc func keyboardDidShow(notification: Notification) {
        // iOS 18+ keyboard fix: Reset window level to stay on top
        if let lastWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
            .last {
            windowLevel = UIWindow.Level(rawValue: lastWindow.windowLevel.rawValue + 1)
        }
    }
}

// MARK: - Floating Pill Controller

class FloatingPillController: UIViewController {

    private let pillWindow: FloatingPillWindow
    private(set) var pillContainerView: UIView!
    private var hostingController: UIHostingController<FloatingPillContent>?

    // Callbacks
    var onRecordTapped: (() -> Void)?
    var onLongPress: (() -> Void)?

    // State
    var isRecording: Bool = false {
        didSet { updatePillState() }
    }
    var audioLevel: Float = 0 {
        didSet { updatePillState() }
    }

    init(scene: UIWindowScene) {
        pillWindow = FloatingPillWindow(scene: scene)
        super.init(nibName: nil, bundle: nil)

        // Set MAXIMUM window level - floats above everything
        pillWindow.windowLevel = UIWindow.Level(rawValue: CGFloat.greatestFiniteMagnitude)
        pillWindow.isHidden = false
        pillWindow.rootViewController = self
    }

    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }

    override func loadView() {
        let containerView = UIView()
        containerView.backgroundColor = .clear // CRITICAL: Transparent

        // Create the pill container
        pillContainerView = UIView()
        pillContainerView.backgroundColor = .clear
        pillContainerView.frame = CGRect(x: 20, y: 100, width: 140, height: 52)
        containerView.addSubview(pillContainerView)

        // Add SwiftUI content
        setupSwiftUIContent()

        // Add pan gesture for dragging
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pillContainerView.addGestureRecognizer(panGesture)

        // Add tap gesture for recording
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        pillContainerView.addGestureRecognizer(tapGesture)

        // Add long press for expand
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.4
        pillContainerView.addGestureRecognizer(longPress)

        // Link to window for hit testing
        pillWindow.pillView = pillContainerView

        self.view = containerView
    }

    private func setupSwiftUIContent() {
        let content = FloatingPillContent(
            isRecording: isRecording,
            audioLevel: audioLevel
        )

        let hosting = UIHostingController(rootView: content)
        hosting.view.backgroundColor = .clear
        hosting.view.frame = pillContainerView.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        addChild(hosting)
        pillContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)

        hostingController = hosting
    }

    private func updatePillState() {
        let content = FloatingPillContent(
            isRecording: isRecording,
            audioLevel: audioLevel
        )
        hostingController?.rootView = content

        // Animate size change
        let targetWidth: CGFloat = isRecording ? 160 : 140
        UIView.animate(withDuration: 0.2, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            self.pillContainerView.frame.size.width = targetWidth
        }
    }

    @objc private func handleTap() {
        onRecordTapped?()
    }

    @objc private func handleLongPress(gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            // Haptic feedback
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
            onLongPress?()
        }
    }

    @objc private func handlePan(gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)

        guard let gestureView = gesture.view else { return }

        // Move the pill
        gestureView.center = CGPoint(
            x: gestureView.center.x + translation.x,
            y: gestureView.center.y + translation.y
        )

        gesture.setTranslation(.zero, in: view)

        // When drag ends, snap to nearest edge
        if gesture.state == .ended {
            snapToEdge(view: gestureView)
        }
    }

    private func snapToEdge(view: UIView) {
        let screenWidth = UIScreen.main.bounds.width
        let screenHeight = UIScreen.main.bounds.height
        let isLeftSide = view.center.x < screenWidth / 2

        let edgePadding: CGFloat = 16
        let targetX = isLeftSide ? edgePadding + view.bounds.width / 2 : screenWidth - edgePadding - view.bounds.width / 2

        // Keep Y within safe area
        let safeTop: CGFloat = 60
        let safeBottom: CGFloat = 100
        let minY = safeTop + view.bounds.height / 2
        let maxY = screenHeight - safeBottom - view.bounds.height / 2
        let targetY = max(minY, min(maxY, view.center.y))

        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: .curveEaseOut) {
            view.center = CGPoint(x: targetX, y: targetY)
        }
    }

    // MARK: - Public Methods

    func show() {
        pillWindow.isHidden = false
    }

    func hide() {
        pillWindow.isHidden = true
    }
}

// MARK: - SwiftUI Pill Content

struct FloatingPillContent: View {
    let isRecording: Bool
    let audioLevel: Float

    var body: some View {
        HStack(spacing: 8) {
            // Record/Stop icon
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : Color.red.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .shadow(color: isRecording ? .red.opacity(0.6) : .clear, radius: 10)

                if isRecording {
                    // Stop icon
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                } else {
                    // Mic icon
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                }
            }

            // Animated dots when recording
            if isRecording {
                HStack(spacing: 4) {
                    ForEach(0..<6, id: \.self) { index in
                        Circle()
                            .fill(Color.white)
                            .frame(width: 5, height: 5)
                            .opacity(pulseOpacity(index))
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        )
        .overlay(
            Capsule()
                .stroke(isRecording ? Color.red.opacity(0.4) : Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func pulseOpacity(_ index: Int) -> Double {
        let phase = (Double(index) / 6.0 + Double(audioLevel)) * 2
        return 0.3 + sin(phase * .pi) * 0.5 + Double(audioLevel) * 0.2
    }
}

#Preview {
    FloatingPillContent(isRecording: true, audioLevel: 0.5)
        .padding()
        .background(Color.gray)
}

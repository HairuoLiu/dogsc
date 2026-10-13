import AppKit
import QuartzCore
import SwiftUI

/// The pointer says what a drag will do: resize arrows over edges and
/// bars, an open hand over things that move. Pushed on entry, popped on
/// exit or when the view goes away, so the stack never leaks.
private struct EditorCursorModifier: ViewModifier {
    let cursor: NSCursor
    @State private var pushed = false

    func body(content: Content) -> some View {
        content
            .onHover { inside in
                if inside, !pushed {
                    cursor.push()
                    pushed = true
                } else if !inside, pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
            .onDisappear {
                if pushed {
                    NSCursor.pop()
                    pushed = false
                }
            }
    }
}

extension View {
    func editorCursor(_ cursor: NSCursor) -> some View {
        modifier(EditorCursorModifier(cursor: cursor))
    }
}

/// A clip's trim grip: a short bar in the clip's colour that grows under
/// the pointer and shows the resize cursor.
struct EditorTrimGrip: View {
    let color: Color
    let height: CGFloat
    @State private var hovered = false

    var body: some View {
        Capsule(style: .continuous)
            .fill(color)
            .frame(width: hovered ? 5 : 3, height: hovered ? height + 6 : height)
            .animation(SpringMotion.hover, value: hovered)
            .frame(width: 12)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .editorCursor(.resizeLeftRight)
    }
}

/// The one handle every canvas object uses: a dot in the object's colour
/// with a white rim. It grows under the pointer and glows while dragged.
struct EditorCanvasHandle: View {
    let color: Color
    var active = false
    var size: CGFloat = 14
    @State private var hovered = false

    var body: some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: size, height: size)
            .shadow(color: active ? color.opacity(0.5) : .black.opacity(0.32), radius: active ? 6 : 2, y: active ? 0 : 1)
            .scaleEffect(RecorderMotion.reduces ? 1 : active ? 1.2 : hovered ? 1.12 : 1)
            .animation(SpringMotion.snappy, value: active)
            .animation(SpringMotion.hover, value: hovered)
            .frame(width: 30, height: 30)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .editorCursor(.crosshair)
    }
}

// MARK: - Clip motion on the timeline

extension AnyTransition {
    /// A clip that is created grows out of its own centre; one that is
    /// deleted shrinks away while its neighbours close the gap.
    static var editorClip: AnyTransition {
        guard !RecorderMotion.reduces else { return .opacity }
        return .asymmetric(
            insertion: .scale(scale: 0.4, anchor: .center).combined(with: .opacity),
            removal: .scale(scale: 0.85, anchor: .center).combined(with: .opacity)
        )
    }
}

extension View {
    /// A clip being moved is picked up: slightly larger, with a soft shadow,
    /// and set down again with a little spring when released.
    func editorClipLift(_ lifted: Bool, scales: Bool = true) -> some View {
        scaleEffect(scales && lifted && !RecorderMotion.reduces ? 1.05 : 1)
            .shadow(color: .black.opacity(lifted ? 0.26 : 0), radius: lifted ? 8 : 0, y: lifted ? 4 : 0)
            .animation(.spring(response: 0.3, dampingFraction: lifted ? 0.8 : 0.62), value: lifted)
    }

    /// Animates a lane only when its set of clips changes (add, delete,
    /// split, undo): neighbours slide into their new places. Moves and drags
    /// keep the same set, so they stay exactly under the pointer.
    func editorClipMembership<ID: Hashable>(_ ids: Set<ID>) -> some View {
        animation(RecorderMotion.reduces ? nil : .spring(response: 0.38, dampingFraction: 0.86), value: ids)
    }
}

// MARK: - Drag updates at the display rate

/// Pointer drags can deliver 120–1000 events a second, and each one used to
/// rebuild the editor's view graph (measured: ~65% of the main thread while
/// dragging a clip). Only the newest drag position matters for a frame, so
/// drag handlers submit their work here and it runs once per display refresh.
/// `onEnded` flushes first, so the last position is always applied before
/// the gesture finishes.
@MainActor
final class EditorDragFrameCoalescer: NSObject {
    static let shared = EditorDragFrameCoalescer()

    /// One pending update per call site: two gestures that are active at the
    /// same time (a drag and a simultaneous gesture) never overwrite each other.
    private var pending: [String: () -> Void] = [:]
    private var order: [String] = []
    private var link: CADisplayLink?

    func submit(file: String = #fileID, line: Int = #line, _ work: @escaping () -> Void) {
        let key = "\(file):\(line)"
        if pending.updateValue(work, forKey: key) == nil { order.append(key) }
        guard link == nil else { return }
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else {
            flush()
            return
        }
        let link = screen.displayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func displayLinkDidFire(_ link: CADisplayLink) {
        flush()
    }

    func flush() {
        link?.invalidate()
        link = nil
        let keys = order
        let works = pending
        order.removeAll()
        pending.removeAll()
        for key in keys { works[key]?() }
    }
}

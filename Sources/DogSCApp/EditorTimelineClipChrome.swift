import SwiftUI

/// 时间线片段只使用一套视觉强调层级。它不参与命中、时间换算或手势分发，
/// 只负责让默认、悬停、选中和正在编辑四种状态清楚且互不叠加。
enum EditorTimelineClipEmphasis: Equatable {
    case idle
    case hovered
    case selected
    case editing

    static func resolve(
        isEditing: Bool,
        isSelected: Bool,
        isHovered: Bool
    ) -> Self {
        if isEditing { return .editing }
        if isSelected { return .selected }
        if isHovered { return .hovered }
        return .idle
    }

    var strokeOpacity: Double {
        switch self {
        case .idle: 0.08
        case .hovered: 0.30
        case .selected: 0.90
        case .editing: 1
        }
    }

    var strokeWidth: CGFloat {
        switch self {
        case .idle: 0.65
        case .hovered: 0.9
        case .selected: 1.45
        case .editing: 1.5
        }
    }

    var handleOpacity: Double {
        switch self {
        case .idle: 0
        case .hovered, .selected, .editing: 1
        }
    }

    var fillOpacity: Double {
        switch self {
        case .idle: 0.20
        case .hovered: 0.26
        case .selected: 0.32
        // Editing uses the outline/drag feedback, keeping its wash within
        // the contrast budget of small labels and trim handles in both themes.
        case .editing: 0.32
        }
    }

    var showsHandles: Bool { self != .idle }

}

extension EditorConsolePalette {
    /// Every clip shares the sidebar task's hue and the same emphasis levels.
    /// `softInk` carries text; the deeper adaptive `text` carries trim handles
    /// on the wash (the sidebar's `stroke` is intended for a neutral panel).
    func timelineSurface(_ emphasis: EditorTimelineClipEmphasis) -> Color {
        fill.opacity(emphasis.fillOpacity)
    }
}

extension View {
    /// `tint` is the clip's identity colour. A single flat outline indicates
    /// selection without glow, shadows or any drawing outside the clip.
    /// `selectionRing` colours only the selected/editing outline of a clip
    /// whose body keeps a neutral look (the screen recording, overlays), so
    /// an idle clip stays quiet and a selected one is never plain black.
    func editorTimelineClipChrome(
        cornerRadius: CGFloat,
        emphasis: EditorTimelineClipEmphasis,
        tint: Color? = nil,
        selectionRing: Color? = nil
    ) -> some View {
        let ring = tint ?? selectionRing ?? EditorTheme.selectionTint
        let active = emphasis == .selected || emphasis == .editing
        return overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    active ? ring : (tint ?? EditorTheme.chrome()),
                    lineWidth: active ? 1.5 : 0.75
                )
                // Only the ink fades; geometry and media stay at their exact
                // edit positions, including selection changes during a cut.
                .animation(.easeOut(duration: 0.14)) { border in
                    border.opacity(active ? 1 : emphasis == .hovered ? 0.55 : (tint == nil ? 0.08 : 0.3))
                }
                .allowsHitTesting(false)
        }
    }
}

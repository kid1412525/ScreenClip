import Cocoa

enum EditorTool: CaseIterable {
    case select, pan, crop, resize, pen, marker, line, arrow, rectangle, ellipse, text, mosaic, blur

    /// "" means no keyboard shortcut (resize is only reachable via the
    /// adjustments panel button, not the drawing toolbar).
    var shortcutKey: String {
        switch self {
        case .select: return "v"
        case .pan: return "h"
        case .crop: return "c"
        case .resize: return ""
        case .pen: return "p"
        case .marker: return "m"
        case .line: return "l"
        case .arrow: return "a"
        case .rectangle: return "r"
        case .ellipse: return "e"
        case .text: return "t"
        case .mosaic: return "o"
        case .blur: return "b"
        }
    }

    var label: String {
        switch self {
        case .select: return "選択"
        case .pan: return "画面移動"
        case .crop: return "切り抜き"
        case .resize: return "サイズ変更"
        case .pen: return "ペン"
        case .marker: return "マーカー"
        case .line: return "直線"
        case .arrow: return "矢印"
        case .rectangle: return "四角"
        case .ellipse: return "楕円"
        case .text: return "テキスト"
        case .mosaic: return "モザイク"
        case .blur: return "ぼかし"
        }
    }

    var symbolName: String {
        switch self {
        case .select: return "cursorarrow"
        case .pan: return "hand.raised"
        case .crop: return "crop"
        case .resize: return "arrow.up.left.and.arrow.down.right"
        case .pen: return "pencil.tip"
        case .marker: return "highlighter"
        case .line: return "line.diagonal"
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .ellipse: return "circle"
        case .text: return "textformat"
        case .mosaic: return "squareshape.split.3x3"
        case .blur: return "drop.circle"
        }
    }

    var isDrawingTool: Bool {
        switch self {
        case .select, .pan, .crop, .resize: return false
        default: return true
        }
    }

    /// Crop and resize both work by dragging handles around a rect overlay
    /// on the canvas, differing only in what happens when it's committed.
    var isBoundsTool: Bool {
        self == .crop || self == .resize
    }
}

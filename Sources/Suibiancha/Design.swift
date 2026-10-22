import SwiftUI
import AppKit

/// Birdy's visual roles; see DESIGN.md. Sizes are macOS points.
enum BirdyDesign {
    static let brand = Font.system(size: 18, weight: .semibold)
    static let section = Font.system(size: 15, weight: .semibold)
    static let heading = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let emphasis = Font.system(size: 13, weight: .medium)
    static let control = Font.system(size: 13)
    static let caption = Font.system(size: 12)
    static let metadata = Font.system(size: 11)
    static let label = Font.system(size: 11, weight: .semibold)
    static let word = Font.custom("Georgia", size: 17).weight(.semibold)
    static let quote = Font.custom("Georgia", size: 15)
    static let example = Font.custom("Georgia", size: 13)
    static let phonetic = Font.custom("Georgia", size: 12)
    static var sourceParagraph: NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 4
        return style
    }
    static let sourceFont = NSFont(name: "Georgia", size: 15) ?? .systemFont(ofSize: 15)

    static let accent = Color.accentColor
    static let sourceBackground = Color(red: 0.08, green: 0.35, blue: 0.82)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let tint = Color.accentColor.opacity(0.065)
    static let quietSurface = Color.primary.opacity(0.035)
}

/// Shared typography and natural wrapping for examples across the reading library.
struct BirdyExampleText: View {
    let text: String
    var isReference = false
    var body: some View {
        Text(TextFlow.prose(text))
            .font(isReference ? BirdyDesign.quote : BirdyDesign.example)
            .foregroundStyle(isReference ? Color.primary : BirdyDesign.secondaryText)
            .lineSpacing(4)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

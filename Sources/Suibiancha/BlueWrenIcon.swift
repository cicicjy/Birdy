import AppKit

enum BlueWrenIcon {
    static func menuBarImage() -> NSImage {
        if let url = Bundle.main.url(forResource: "Birdy-menu", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            image.size = NSSize(width: 20, height: 20)
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: "bird", accessibilityDescription: "Birdy") ?? NSImage()
    }
}

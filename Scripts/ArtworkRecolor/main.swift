import AppKit
import Foundation
import ImageIO

guard CommandLine.arguments.count == 5 else {
    fatalError("用法：ArtworkRecolor 原图 透明蓝色线稿 图标预览 菜单栏图标")
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let inkURL = URL(fileURLWithPath: CommandLine.arguments[2])
let previewURL = URL(fileURLWithPath: CommandLine.arguments[3])
let menuURL = URL(fileURLWithPath: CommandLine.arguments[4])
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue

func clamp(_ value: Double) -> Double { min(1, max(0, value)) }
func pixels(of image: CGImage) -> [UInt8] {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            fatalError("无法读取原图像素")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return bytes
}
func image(from bytes: [UInt8], width: Int, height: Int) -> CGImage {
    guard let provider = CGDataProvider(data: Data(bytes) as CFData),
          let result = CGImage(width: width, height: height, bitsPerComponent: 8,
                               bitsPerPixel: 32, bytesPerRow: width * 4,
                               space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo),
                               provider: provider, decode: nil, shouldInterpolate: true,
                               intent: .defaultIntent) else { fatalError("无法创建图像") }
    return result
}
func save(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("无法导出 PNG")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG 导出失败") }
}
func render(width: Int, height: Int, draw: (CGContext) -> Void) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    bytes.withUnsafeMutableBytes { buffer in
        guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: colorSpace, bitmapInfo: bitmapInfo) else {
            fatalError("无法绘制图标")
        }
        draw(context)
        context.flush()
    }
    return bytes
}

guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let original = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("无法读取线稿") }
let width = original.width, height = original.height
let originalBytes = pixels(of: original)

func inkAmount(x: Int, y: Int) -> Double {
    let i = (y * width + x) * 4
    let r = Double(originalBytes[i]) / 255
    let g = Double(originalBytes[i + 1]) / 255
    let b = Double(originalBytes[i + 2]) / 255
    let warmth = min((r - g - 0.015) / 0.07, (g - b - 0.01) / 0.08)
    let darkness = (0.985 - (r + g + b) / 3) / 0.20
    return clamp(min(warmth, darkness))
}

var minX = width, minY = height, maxX = 0, maxY = 0
for y in 250..<min(height, 730) {
    for x in 190..<min(width, 540) where inkAmount(x: x, y: y) > 0.55 {
        minX = min(minX, x); minY = min(minY, y)
        maxX = max(maxX, x); maxY = max(maxY, y)
    }
}
guard maxX > minX, maxY > minY else { fatalError("没有找到原图中的金色笔触") }
let margin = 14
minX = max(0, minX - margin); minY = max(0, minY - margin)
maxX = min(width - 1, maxX + margin); maxY = min(height - 1, maxY + margin)
let inkWidth = maxX - minX + 1, inkHeight = maxY - minY + 1
var inkBytes = [UInt8](repeating: 0, count: inkWidth * inkHeight * 4)
for y in 0..<inkHeight {
    for x in 0..<inkWidth {
        let sx = x + minX, sy = y + minY
        let sourceIndex = (sy * width + sx) * 4
        let targetIndex = (y * inkWidth + x) * 4
        let alpha = inkAmount(x: sx, y: sy)
        let brightness = Double(originalBytes[sourceIndex]) / 765
            + Double(originalBytes[sourceIndex + 1]) / 765
            + Double(originalBytes[sourceIndex + 2]) / 765
        let relief = clamp((brightness - 0.28) / 0.62)
        let red = 0.025 + 0.38 * relief
        let green = 0.20 + 0.50 * relief
        let blue = 0.67 + 0.32 * relief
        inkBytes[targetIndex] = UInt8(clamp(red * alpha) * 255)
        inkBytes[targetIndex + 1] = UInt8(clamp(green * alpha) * 255)
        inkBytes[targetIndex + 2] = UInt8(clamp(blue * alpha) * 255)
        inkBytes[targetIndex + 3] = UInt8(alpha * 255)
    }
}
let inkImage = image(from: inkBytes, width: inkWidth, height: inkHeight)
save(inkImage, to: inkURL)

func inkRect(side: Int, heightFraction: CGFloat) -> CGRect {
    let size = CGFloat(side), h = size * heightFraction
    let w = h * CGFloat(inkWidth) / CGFloat(inkHeight)
    return CGRect(x: (size - w) / 2, y: (size - h) / 2, width: w, height: h)
}

let previewBytes = render(width: 1024, height: 1024) { context in
    let side: CGFloat = 1024
    context.setFillColor(CGColor(red: 0.975, green: 0.98, blue: 0.99, alpha: 1))
    context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: side, height: side),
                           cornerWidth: side * 0.18, cornerHeight: side * 0.18, transform: nil))
    context.fillPath()
    context.interpolationQuality = .high
    context.draw(inkImage, in: inkRect(side: 1024, heightFraction: 0.78))
}
save(image(from: previewBytes, width: 1024, height: 1024), to: previewURL)

var menuBytes = render(width: 40, height: 40) { context in
    context.interpolationQuality = .high
    context.draw(inkImage, in: inkRect(side: 40, heightFraction: 0.92))
}
for i in stride(from: 0, to: menuBytes.count, by: 4) {
    let alpha = clamp(Double(menuBytes[i + 3]) / 255 * 3.5)
    menuBytes[i] = UInt8(0.04 * alpha * 255)
    menuBytes[i + 1] = UInt8(0.39 * alpha * 255)
    menuBytes[i + 2] = UInt8(0.95 * alpha * 255)
    menuBytes[i + 3] = UInt8(alpha * 255)
}
save(image(from: menuBytes, width: 40, height: 40), to: menuURL)
print("Original ink bounds: \(minX),\(minY) to \(maxX),\(maxY)")

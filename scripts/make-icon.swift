import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// SourceGit 应用图标生成器
//
// 设计:深蓝渐变圆角方形(macOS 规范:1024 画布,824 squircle,圆角 ~186),
// 内容为本应用的招牌"提交泳道图"——三条彩色泳道自上而下汇合到主线,
// 终点是带白色外环的 HEAD 提交点。
//
// 用法: swiftc scripts/make-icon.swift -o build/IconGen && ./build/IconGen
// 输出: build/AppIcon.iconset/(全部尺寸),随后用 iconutil 转 .icns

let outputDir = "build/AppIcon.iconset"

func laneColors() -> (blue: CGColor, orange: CGColor, green: CGColor) {
    (
        CGColor(red: 0.30, green: 0.62, blue: 0.96, alpha: 1),   // 泳道蓝
        CGColor(red: 1.00, green: 0.62, blue: 0.26, alpha: 1),   // 泳道橙
        CGColor(red: 0.20, green: 0.78, blue: 0.48, alpha: 1)    // 泳道绿
    )
}

func draw(size: Int) -> CGImage {
    let s = CGFloat(size) / 1024.0
    let ctx = CGContext(
        data: nil, width: size, height: size,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!

    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
    let dim: (CGFloat) -> CGFloat = { max($0 * s, $0 > 4 ? 1 : 0.75) }

    // 背景 squircle:824×824 居中,圆角 186
    let body = CGRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let radius = 186 * s
    let squircle = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    // 深蓝垂直渐变
    let bg = CGGradient(
        colorsSpace: nil,
        colors: [
            CGColor(red: 0.20, green: 0.31, blue: 0.47, alpha: 1),
            CGColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(bg, start: pt(512, 924), end: pt(512, 100), options: [])

    // 顶部轻微高光(层次感)
    let sheen = CGGradient(
        colorsSpace: nil,
        colors: [
            CGColor(red: 1, green: 1, blue: 1, alpha: 0.12),
            CGColor(red: 1, green: 1, blue: 1, alpha: 0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(sheen, start: pt(0, 924), end: pt(0, 520), options: [])
    ctx.restoreGState()

    // 内描边(轮廓清晰)
    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.setLineWidth(dim(3))
    ctx.strokePath()
    ctx.restoreGState()

    let colors = laneColors()

    // 泳道线
    let lineW = dim(30)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(lineW)

    func stroke(_ closure: (CGMutablePath) -> Void, _ color: CGColor) {
        let p = CGMutablePath()
        closure(p)
        ctx.addPath(p)
        ctx.setStrokeColor(color)
        ctx.strokePath()
    }

    // 主线(蓝):从顶部贯通到 HEAD
    stroke({ p in
        p.move(to: pt(400, 757)); p.addLine(to: pt(400, 267))
    }, colors.blue)

    // 分支一(橙):自顶部下行后汇入主线
    stroke({ p in
        p.move(to: pt(512, 757))
        p.addLine(to: pt(512, 487))
        p.addCurve(to: pt(400, 367), control1: pt(512, 440), control2: pt(400, 450))
    }, colors.orange)

    // 分支二(绿):自顶部下行后汇入橙线(逐级汇入,不交叉)
    stroke({ p in
        p.move(to: pt(624, 757))
        p.addLine(to: pt(624, 667))
        p.addCurve(to: pt(512, 587), control1: pt(624, 650), control2: pt(512, 672))
    }, colors.green)

    // 提交点(深色描边与背景同色,形成分隔)
    let dotR = dim(28)
    let ringBg = CGColor(red: 0.06, green: 0.11, blue: 0.20, alpha: 1)

    func dot(_ x: CGFloat, _ y: CGFloat, _ color: CGColor) {
        let c = pt(x, y)
        let r = CGRect(x: c.x - dotR, y: c.y - dotR, width: dotR * 2, height: dotR * 2)
        ctx.setStrokeColor(ringBg)
        ctx.setLineWidth(dim(13))
        ctx.strokePath()
        ctx.addPath(CGPath(ellipseIn: r.insetBy(dx: -6.5 * s, dy: -6.5 * s), transform: nil))
        ctx.strokePath()
        ctx.setFillColor(color)
        ctx.addPath(CGPath(ellipseIn: r, transform: nil))
        ctx.fillPath()
    }

    dot(400, 790, colors.blue)    // 主线分支头
    dot(512, 790, colors.orange)  // 橙分支头
    dot(624, 790, colors.green)   // 绿分支头
    dot(512, 620, colors.green)   // 绿汇入橙
    dot(400, 400, colors.orange)  // 橙汇入蓝

    // HEAD 提交点:白色外环强调
    let head = pt(400, 267)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineWidth(dim(7.5))
    ctx.addPath(CGPath(ellipseIn: CGRect(
        x: head.x - dotR - dim(14), y: head.y - dotR - dim(14),
        width: (dotR + dim(12)) * 2, height: (dotR + dim(12)) * 2
    ), transform: nil))
    ctx.strokePath()
    ctx.setFillColor(colors.blue)
    ctx.addPath(CGPath(ellipseIn: CGRect(
        x: head.x - dotR, y: head.y - dotR, width: dotR * 2, height: dotR * 2
    ), transform: nil))
    ctx.fillPath()

    return ctx.makeImage()!
}

// 写出 iconset 全部尺寸
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
let sizes: [(name: String, px: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for item in sizes {
    let image = draw(size: item.px)
    let url = URL(fileURLWithPath: "\(outputDir)/\(item.name)") as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("无法创建 \(item.name)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}
print("iconset 已生成: \(outputDir) (\(sizes.count) 个尺寸)")

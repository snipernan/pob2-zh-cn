// Generate the sharing build atlas from the bundled SIL OFL Noto font.
import AppKit
import CoreText

let root = URL(fileURLWithPath: CommandLine.arguments[1])
let chars = Array(try String(contentsOf: root.appendingPathComponent("charset.txt"), encoding: .utf8))
let size = 2048, cell = 64, columns = size / cell, perPage = columns * columns
let fontURL = URL(fileURLWithPath: CommandLine.arguments[2])
var fontError: Unmanaged<CFError>?
guard CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, &fontError) else {
    fatalError("Could not load bundled Noto font")
}
let font = NSFont(name: "NotoSansCJKsc-Regular", size: 56)!
for ch in chars {
    var codes = Array(String(ch).utf16)
    var glyphs = [CGGlyph](repeating: 0, count: codes.count)
    guard CTFontGetGlyphsForCharacters(font, &codes, &glyphs, codes.count) else {
        fatalError("Noto font lacks required glyph: \(ch)")
    }
}
var lua = "return { cell = 64, size = 2048, glyphs = {\n"
for page in 0..<((chars.count + perPage - 1) / perPage) {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let cg = NSGraphicsContext.current!.cgContext
    cg.setAllowsAntialiasing(true)
    cg.setShouldAntialias(true)
    for index in (page * perPage)..<min(chars.count, (page + 1) * perPage) {
        let local = index % perPage, x = (local % columns) * cell, y = (local / columns) * cell
        let ch = String(chars[index])
        let text = NSAttributedString(string: ch, attributes: [.font: font, .foregroundColor: NSColor.white])
        let line = CTLineCreateWithAttributedString(text)
        let width = CTLineGetTypographicBounds(line, nil, nil, nil)
        cg.textPosition = CGPoint(x: x + 4, y: size - y - cell + 13)
        CTLineDraw(line, cg)
        lua += "[\"\(ch)\"]={\(page + 1),\(x),\(y),\(min(60, max(12, width)))},\n"
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("payload/font-\(page + 1).png"))
}
lua += "}}\n"
try lua.write(to: root.appendingPathComponent("payload/font.lua"), atomically: true, encoding: .utf8)
print("Rendered \(chars.count) Chinese glyphs with bundled Noto Sans CJK SC")

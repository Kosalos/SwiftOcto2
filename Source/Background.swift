import Cocoa

class Background: NSView {
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let context = NSGraphicsContext.current()?.cgContext
        let path = CGMutablePath()
        path.addRect(bounds)
        context?.setFillColor(NSColor.darkGray.cgColor)
        context?.addPath(path)
        context?.drawPath(using:.fill)
    }
}

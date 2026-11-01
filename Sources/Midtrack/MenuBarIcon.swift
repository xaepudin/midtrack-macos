import AppKit

/// The menu bar mark, drawn from the same idea as the app icon: a small
/// waveform bisected by the midpoint marker. It is a template image, so macOS
/// tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()

            let heights: [CGFloat] = [3.4, 6.0, 8.6, 11.2, 8.6, 6.0, 3.4]
            let barWidth: CGFloat = 1.6
            let gap: CGFloat = 0.85
            let total = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            let startX = (rect.width - total) / 2

            for (index, height) in heights.enumerated() {
                let x = startX + CGFloat(index) * (barWidth + gap)
                let bar = NSRect(x: x,
                                 y: rect.midY - height / 2,
                                 width: barWidth,
                                 height: height)
                NSBezierPath(roundedRect: bar,
                             xRadius: barWidth / 2,
                             yRadius: barWidth / 2).fill()
            }

            // The midpoint marker, taller than the waveform — the monochrome
            // echo of the orange line in the app icon.
            let marker = NSRect(x: rect.midX - barWidth / 2,
                                y: 1.25,
                                width: barWidth,
                                height: rect.height - 2.5)
            NSBezierPath(roundedRect: marker,
                         xRadius: barWidth / 2,
                         yRadius: barWidth / 2).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

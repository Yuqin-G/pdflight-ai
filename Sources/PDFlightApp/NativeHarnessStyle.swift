import AppKit

enum NativeHarnessStyle {
    static let menu = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 43/255, green: 41/255, blue: 36/255, alpha: 1)
            : NSColor(srgbRed: 251/255, green: 250/255, blue: 246/255, alpha: 1)
    }
    static let input = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 31/255, green: 30/255, blue: 27/255, alpha: 1)
            : .white
    }
    static let userBubble = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.10)
            : NSColor(srgbRed: 240/255, green: 244/255, blue: 248/255, alpha: 1)
    }
    static let primary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 244/255, green: 240/255, blue: 231/255, alpha: 1)
            : NSColor(srgbRed: 31/255, green: 29/255, blue: 25/255, alpha: 1)
    }
    static let secondary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 185/255, green: 179/255, blue: 167/255, alpha: 1)
            : NSColor(srgbRed: 107/255, green: 102/255, blue: 92/255, alpha: 1)
    }
    static let tertiary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 154/255, green: 148/255, blue: 136/255, alpha: 1)
            : NSColor(srgbRed: 111/255, green: 105/255, blue: 95/255, alpha: 1)
    }
    static let caption = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 138/255, green: 132/255, blue: 120/255, alpha: 1)
            : NSColor(srgbRed: 116/255, green: 110/255, blue: 99/255, alpha: 1)
    }
}

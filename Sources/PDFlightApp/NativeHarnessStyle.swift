import AppKit

enum NativeHarnessStyle {
    static let userBubble = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 44/255, green: 44/255, blue: 46/255, alpha: 1)
            : NSColor(srgbRed: 237/255, green: 243/255, blue: 254/255, alpha: 1)
    }
    static let primary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 249/255, green: 250/255, blue: 251/255, alpha: 1)
            : NSColor(srgbRed: 15/255, green: 17/255, blue: 21/255, alpha: 1)
    }
    static let secondary = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 207/255, green: 211/255, blue: 214/255, alpha: 1)
            : NSColor(srgbRed: 97/255, green: 102/255, blue: 107/255, alpha: 1)
    }
    static let caption = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 129/255, green: 133/255, blue: 140/255, alpha: 1)
            : NSColor(srgbRed: 173/255, green: 178/255, blue: 184/255, alpha: 1)
    }
}

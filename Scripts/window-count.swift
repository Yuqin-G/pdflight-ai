import CoreGraphics
import Foundation

guard (2...3).contains(CommandLine.arguments.count),
      let processID = Int32(CommandLine.arguments[1]),
      CommandLine.arguments.count == 2 || CommandLine.arguments[2] == "--list" else {
    exit(2)
}

let options: CGWindowListOption = [.optionAll, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
let qualifyingWindows = windows.filter { window in
    guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
          ownerPID == Int(processID),
          let layer = window[kCGWindowLayer as String] as? Int,
          layer == 0,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let width = bounds["Width"] as? Double,
          let height = bounds["Height"] as? Double else { return false }
    return width >= 600 && height >= 350
}

if CommandLine.arguments.count == 3 {
    for window in qualifyingWindows {
        let name = window[kCGWindowName as String] as? String ?? "<untitled>"
        let bounds = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
        let width = bounds["Width"] as? Double ?? 0
        let height = bounds["Height"] as? Double ?? 0
        print("\(Int(width))x\(Int(height))\t\(name)")
    }
}

print(qualifyingWindows.count)

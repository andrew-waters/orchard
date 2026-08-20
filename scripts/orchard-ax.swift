import AppKit
import ApplicationServices

// Usage: orchard-ax press <ax-identifier> | orchard-ax window-id
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: press <id> | window-id"); exit(64) }

guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "Orchard" }) else {
    fputs("Orchard not running\n", stderr); exit(1)
}

if args[1] == "window-id" {
    let opts: CGWindowListOption = [.optionOnScreenOnly]
    guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier && (w["kCGWindowLayer"] as? Int) == 0 {
        // Skip tiny windows (menu bar panel); the main window is large.
        if let b = w["kCGWindowBounds"] as? [String: Any], let h = b["Height"] as? Double, h > 300 {
            print(w["kCGWindowNumber"] as? Int ?? -1); exit(0)
        }
    }
    fputs("no main window\n", stderr); exit(2)
}

guard args[1] == "press", args.count == 3 else { print("usage: press <id> | window-id"); exit(64) }
let wanted = args[2]

guard AXIsProcessTrusted() else {
    fputs("This tool needs Accessibility permission (System Settings → Privacy & Security → Accessibility) for your terminal.\n", stderr)
    exit(3)
}

let axApp = AXUIElementCreateApplication(app.processIdentifier)

func children(_ el: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success,
          let arr = value as? [AXUIElement] else { return [] }
    return arr
}

func identifier(_ el: AXUIElement) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXIdentifierAttribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func find(_ el: AXUIElement, depth: Int = 0) -> AXUIElement? {
    if depth > 25 { return nil }
    if identifier(el) == wanted { return el }
    for child in children(el) {
        if let hit = find(child, depth: depth + 1) { return hit }
    }
    return nil
}

guard let target = find(axApp) else { fputs("element '\(wanted)' not found\n", stderr); exit(4) }
app.activate()
usleep(200_000)
let err = AXUIElementPerformAction(target, kAXPressAction as CFString)
if err != .success {
    // SwiftUI rows often expose no AXPress; click their screen position instead.
    var posV: CFTypeRef?, sizeV: CFTypeRef?
    guard AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posV) == .success,
          AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeV) == .success else {
        fputs("press failed (\(err.rawValue)) and no position\n", stderr); exit(5)
    }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
    let click = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
}
print("pressed \(wanted)")

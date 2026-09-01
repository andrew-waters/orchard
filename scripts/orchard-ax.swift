import AppKit
import ApplicationServices
import ScreenCaptureKit

// Usage: orchard-ax press <ax-identifier> | window-id | menubar-click | panel-id
let args = CommandLine.arguments
guard args.count >= 2 else { print("usage: press <id> | press-text <text> | hover-text <text> | window-id | menubar-click | panel-id | capture-panels <out.png>"); exit(64) }

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

// The MenuBarExtra panel, once open, is an ordinary Orchard-owned window - but at
// status-bar level rather than layer 0, which is exactly how we tell it apart from
// the main window. Pick the largest non-layer-0 window to skip the 24px status item.
if args[1] == "panel-id" {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    var best: (id: Int, area: Double) = (-1, 0)
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier && (w["kCGWindowLayer"] as? Int) != 0 {
        guard let b = w["kCGWindowBounds"] as? [String: Any],
              let h = b["Height"] as? Double, let wd = b["Width"] as? Double, h > 100 else { continue }
        if h * wd > best.area { best = (w["kCGWindowNumber"] as? Int ?? -1, h * wd) }
    }
    if best.id >= 0 { print(best.id); exit(0) }
    fputs("no open menu bar panel\n", stderr); exit(2)
}

// Click Orchard's status item (toggles the MenuBarExtra panel open/closed).
if args[1] == "menubar-click" {
    guard AXIsProcessTrusted() else {
        fputs("This tool needs Accessibility permission (System Settings → Privacy & Security → Accessibility) for your terminal.\n", stderr)
        exit(3)
    }
    let axApp = AXUIElementCreateApplication(app.processIdentifier)
    var barV: CFTypeRef?
    guard AXUIElementCopyAttributeValue(axApp, "AXExtrasMenuBar" as CFString, &barV) == .success else {
        fputs("no extras menu bar (status item hidden or collapsed?)\n", stderr); exit(4)
    }
    var childrenV: CFTypeRef?
    guard AXUIElementCopyAttributeValue(barV as! AXUIElement, kAXChildrenAttribute as CFString, &childrenV) == .success,
          let items = childrenV as? [AXUIElement], let item = items.first else {
        fputs("status item not found in the extras menu bar\n", stderr); exit(4)
    }
    var posV: CFTypeRef?, sizeV: CFTypeRef?
    guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &posV) == .success,
          AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeV) == .success else {
        fputs("status item has no position\n", stderr); exit(5)
    }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
    let click = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
    print("clicked status item at \(Int(click.x)),\(Int(click.y))")
    exit(0)
}

// Composite every open Orchard panel-level window (menu bar panel + any hover
// popover) into one PNG at their true screen positions, shadows included. A
// single-window `screencapture -l` can't capture the popover alongside the panel,
// so this captures via ScreenCaptureKit with a filter containing just those windows
// (clear background, no cursor) and crops to their union plus a shadow margin.
// Crop an image to its non-transparent bounding box, keeping a small margin.
func trimTransparentMargins(_ img: CGImage, keeping margin: Int) -> CGImage? {
    let w = img.width, h = img.height
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue) else { return nil }
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let data = ctx.data else { return nil }
    let bpr = ctx.bytesPerRow
    let alpha = data.bindMemory(to: UInt8.self, capacity: bpr * h)
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
        let row = y * bpr
        for x in 0..<w where alpha[row + x] > 8 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    let rect = CGRect(x: max(0, minX - margin), y: max(0, minY - margin),
                      width: min(w, maxX + margin + 1) - max(0, minX - margin),
                      height: min(h, maxY + margin + 1) - max(0, minY - margin))
    return img.cropping(to: rect)
}

// Print the main window's bounds as "x y w h" (global points, top-left origin).
if args[1] == "window-bounds" {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier && (w["kCGWindowLayer"] as? Int) == 0 {
        if let b = w["kCGWindowBounds"] as? [String: Any],
           let h = b["Height"] as? Double, h > 300,
           let x = b["X"] as? Double, let y = b["Y"] as? Double, let wd = b["Width"] as? Double {
            print("\(Int(x)) \(Int(y)) \(Int(wd)) \(Int(h))"); exit(0)
        }
    }
    fputs("no main window\n", stderr); exit(2)
}

// Click at absolute screen coordinates (global points, top-left origin).
if args[1] == "click" {
    guard args.count == 4, let x = Double(args[2]), let y = Double(args[3]) else {
        print("usage: click <x> <y>"); exit(64)
    }
    let point = CGPoint(x: x, y: y)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
    print("clicked \(Int(x)),\(Int(y))")
    exit(0)
}

// Post a key chord (e.g. "cmd+k", "escape", "return") to the frontmost app.
if args[1] == "key" {
    guard args.count == 3 else { print("usage: key <chord>  e.g. key cmd+k"); exit(64) }
    var flags: CGEventFlags = []
    var keyName = ""
    for part in args[2].lowercased().split(separator: "+") {
        switch part {
        case "cmd", "command": flags.insert(.maskCommand)
        case "shift": flags.insert(.maskShift)
        case "opt", "option", "alt": flags.insert(.maskAlternate)
        case "ctrl", "control": flags.insert(.maskControl)
        default: keyName = String(part)
        }
    }
    let keyMap: [String: CGKeyCode] = [
        "return": 36, "enter": 36, "escape": 53, "esc": 53, "tab": 48, "space": 49, "delete": 51,
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    ]
    guard let code = keyMap[keyName] else { fputs("unknown key '\(keyName)'\n", stderr); exit(64) }
    // The chord goes on the main key's events (posting separate synthetic modifier
    // key-downs stops the shortcut being recognised at all). That alone leaves the
    // system believing the modifier is still held - every later plain keystroke
    // becomes a chord (⌘Space = Spotlight, ⌘A = select all...) - so afterwards post
    // modifier key-ups with empty flags to clear the latch.
    for down in [true, false] {
        let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
        ev?.flags = flags
        ev?.post(tap: .cghidEventTap)
        usleep(60_000)
    }
    if !flags.isEmpty {
        for modCode in [CGKeyCode(55), 56, 58, 59] {
            let ev = CGEvent(keyboardEventSource: nil, virtualKey: modCode, keyDown: false)
            ev?.flags = []
            ev?.post(tap: .cghidEventTap)
        }
        usleep(50_000)
    }
    print("key \(args[2])")
    exit(0)
}

// Type literal text into the focused field, as real per-character key events.
if args[1] == "type" {
    guard args.count == 3 else { print("usage: type <text>"); exit(64) }
    let charMap: [Character: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35,
        "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        " ": 49, "-": 27, ".": 47, "/": 44, ";": 41,
    ]
    // Release any stuck modifiers first, so the text can't turn into chords.
    for modCode in [CGKeyCode(55), 56, 58, 59] {
        let ev = CGEvent(keyboardEventSource: nil, virtualKey: modCode, keyDown: false)
        ev?.flags = []
        ev?.post(tap: .cghidEventTap)
    }
    usleep(50_000)
    for ch in args[2].lowercased() {
        guard let code = charMap[ch] else { fputs("cannot type character '\(ch)'\n", stderr); exit(64) }
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)
            ev?.flags = []
            ev?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        usleep(20_000)
    }
    print("typed \(args[2])")
    exit(0)
}

// Debug: dump Orchard's on-screen windows (id, layer, bounds).
if args[1] == "windows" {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier {
        let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
        print("id=\(w["kCGWindowNumber"] ?? "?") layer=\(w["kCGWindowLayer"] ?? "?") x=\(b["X"] ?? "?") y=\(b["Y"] ?? "?") w=\(b["Width"] ?? "?") h=\(b["Height"] ?? "?") name=\(w["kCGWindowName"] ?? "")")
    }
    exit(0)
}

if args[1] == "capture-panels" {
    guard args.count == 3 else { print("usage: capture-panels <out.png>"); exit(64) }
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { exit(1) }
    var ids = Set<CGWindowID>()
    var union = CGRect.null
    for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier && (w["kCGWindowLayer"] as? Int) != 0 {
        guard let b = w["kCGWindowBounds"] as? [String: Any],
              let h = b["Height"] as? Double, h > 50,
              let wd = b["Width"] as? Double, let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let id = w["kCGWindowNumber"] as? Int else { continue }
        ids.insert(CGWindowID(id))
        union = union.union(CGRect(x: x, y: y, width: wd, height: h))
    }
    guard !ids.isEmpty else { fputs("no open menu bar panel\n", stderr); exit(2) }

    let sem = DispatchSemaphore(value: 0)
    var out: CGImage?
    var failure = "capture failed (missing Screen Recording permission?)"
    Task {
        defer { sem.signal() }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            // Capture only the panel (the largest of the ids): a desktop-independent
            // window capture includes its attached child windows - the hover popover -
            // at native scale and true relative position, with native shadows. The
            // display-filter composite path misplaces windows on secondary displays.
            let windows = content.windows.filter { ids.contains($0.windowID) }
            guard let panel = windows.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                failure = "panel windows not shareable"; return
            }
            let filter = SCContentFilter(desktopIndependentWindow: panel)
            let scale = CGFloat(filter.pointPixelScale)
            let cfg = SCStreamConfiguration()
            // Generous canvas: the pair plus room for shadows; transparent excess is trimmed below.
            cfg.width = Int((union.width + 300) * scale)
            cfg.height = Int((union.height + 300) * scale)
            cfg.ignoreShadowsSingleWindow = false
            cfg.showsCursor = false
            cfg.captureResolution = .best
            out = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
        } catch {
            failure = "capture failed: \(error.localizedDescription)"
        }
    }
    sem.wait()

    // Trim transparent margins down to the content plus a small border.
    if let img = out, let trimmed = trimTransparentMargins(img, keeping: 8) { out = trimmed }
    guard let img = out,
          let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[2]) as CFURL, "public.png" as CFString, 1, nil) else {
        fputs(failure + "\n", stderr); exit(5)
    }
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fputs("could not write \(args[2])\n", stderr); exit(5) }
    print("captured \(ids.count) window(s) to \(args[2])")
    exit(0)
}

guard ["press", "press-text", "hover-text"].contains(args[1]), args.count == 3 else {
    print("usage: press <ax-identifier> | press-text <visible-text> | hover-text <visible-text> | window-id | menubar-click | panel-id | capture-panels <out.png>"); exit(64)
}
let byText = args[1] != "press"
let hover = args[1] == "hover-text"
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

func stringAttr(_ el: AXUIElement, _ attr: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success else { return nil }
    return value as? String
}

func matches(_ el: AXUIElement) -> Bool {
    if byText {
        return stringAttr(el, kAXValueAttribute as String) == wanted
            || stringAttr(el, kAXTitleAttribute as String) == wanted
            || stringAttr(el, kAXDescriptionAttribute as String) == wanted
    }
    return identifier(el) == wanted
}

func find(_ el: AXUIElement, depth: Int = 0, where extra: (AXUIElement) -> Bool = { _ in true }) -> AXUIElement? {
    if depth > 60 { return nil }
    if matches(el) && extra(el) { return el }
    for child in children(el) {
        if let hit = find(child, depth: depth + 1, where: extra) { return hit }
    }
    return nil
}

func frame(_ el: AXUIElement) -> CGRect? {
    var posV: CFTypeRef?, sizeV: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posV) == .success,
          AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeV) == .success else { return nil }
    var p = CGPoint.zero, s = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &p)
    AXValueGetValue(sizeV as! AXValue, .cgSize, &s)
    return CGRect(origin: p, size: s)
}

// Hovering targets the menu bar panel, but the same container name also appears in the
// main window's list - so restrict the search to elements inside the panel's bounds.
var scope: (AXUIElement) -> Bool = { _ in true }
if hover {
    var panelRect = CGRect.null
    if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] {
        for w in list where (w["kCGWindowOwnerPID"] as? Int32) == app.processIdentifier && (w["kCGWindowLayer"] as? Int) != 0 {
            guard let b = w["kCGWindowBounds"] as? [String: Any],
                  let h = b["Height"] as? Double, h > 100,
                  let wd = b["Width"] as? Double, let x = b["X"] as? Double, let y = b["Y"] as? Double else { continue }
            let r = CGRect(x: x, y: y, width: wd, height: h)
            if r.width * r.height > panelRect.width * panelRect.height { panelRect = r }
        }
    }
    guard !panelRect.isNull else { fputs("no open menu bar panel to hover in\n", stderr); exit(2) }
    scope = { el in frame(el).map { panelRect.contains(CGPoint(x: $0.midX, y: $0.midY)) } ?? false }
}

guard let target = find(axApp, where: scope) else { fputs("element '\(wanted)' not found\n", stderr); exit(4) }

// SwiftUI onTapGesture rows accept AXPress without doing anything, so don't trust it:
// always click the element's screen position with real mouse events (what XCUITest does).
// Hovering skips activation: raising the main window would dismiss the menu bar panel.
if !hover {
    app.activate(options: [.activateIgnoringOtherApps])
    var windowV: CFTypeRef?
    if AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &windowV) == .success {
        AXUIElementPerformAction(windowV as! AXUIElement, kAXRaiseAction as CFString)
    }
    usleep(400_000)
}

var posV: CFTypeRef?, sizeV: CFTypeRef?
guard AXUIElementCopyAttributeValue(target, kAXPositionAttribute as CFString, &posV) == .success,
      AXUIElementCopyAttributeValue(target, kAXSizeAttribute as CFString, &sizeV) == .success else {
    fputs("element '\(wanted)' has no position\n", stderr); exit(5)
}
var pos = CGPoint.zero, size = CGSize.zero
AXValueGetValue(posV as! AXValue, .cgPoint, &pos)
AXValueGetValue(sizeV as! AXValue, .cgSize, &size)
let click = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
if hover {
    // Two nudged moves, then the centre: a single synthetic mouseMoved doesn't always
    // wake NSTrackingArea/onHover.
    for point in [CGPoint(x: click.x - 4, y: click.y - 2), CGPoint(x: click.x + 2, y: click.y + 1), click] {
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(120_000)
    }
    print("hovering \(wanted) at \(Int(click.x)),\(Int(click.y))")
} else {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: click, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
    print("clicked \(wanted) at \(Int(click.x)),\(Int(click.y))")
}

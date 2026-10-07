#!/usr/bin/env python3
"""Check production appearance mapping and native fields in invisible windows."""
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
app = (root / "Sources/JustNow/JustNowApp.swift").read_text()
mapping = re.search(r"^\s*(NSApp\.appearance = appearance .*?)$", app, re.MULTILINE)
assert mapping, "The application's appearance mapping is missing"
sheet_callback = re.search(
    r"    func window\(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect\) -> NSRect \{.*?\n    \}",
    app, re.DOTALL)
assert sheet_callback, "The application's sheet-position callback is missing"
assert "preferredColorScheme" not in (root / "Sources/JustNow/Views.swift").read_text(), \
    "A SwiftUI color-scheme override can retain the previous mode when returning to System"

harness = r'''
import AppKit
import SwiftUI

extension Bundle { static var module: Bundle { .main } }
enum FixtureAppearance { case system, light, dark }
func apply(_ appearance: FixtureAppearance) { APPEARANCE_MAPPING }
final class SheetDelegate: NSObject, NSWindowDelegate { SHEET_CALLBACK }
struct SchemeProbe: NSViewRepresentable {
    @Environment(\.colorScheme) var scheme
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        view.identifier = NSUserInterfaceItemIdentifier(scheme == .dark ? "dark" : "light")
    }
}
func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
func dark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
}
func red(_ color: NSColor, in appearance: NSAppearance) -> CGFloat {
    var value: CGFloat = 0
    appearance.performAsCurrentDrawingAppearance { value = color.usingColorSpace(.sRGB)!.redComponent }
    return value
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let systemDark = dark(app.effectiveAppearance)
let windows: [NSWindow] = [
    NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false),
    NSPanel(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false),
    NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
]
let sheetDelegate = SheetDelegate()
windows[0].delegate = sheetDelegate
func checkSheetBackground(_ expectedDark: Bool) {
    let sheet = windows[2]
    let expected: [CGFloat] = expectedDark ? [23, 23, 25] : [248, 247, 244]
    sheet.effectiveAppearance.performAsCurrentDrawingAppearance {
        let color = sheet.backgroundColor!.usingColorSpace(.sRGB)!
        let actual = [color.redComponent, color.greenComponent, color.blueComponent]
        assert(zip(actual, expected).allSatisfy { abs($0 - $1 / 255) < 0.001 },
               "The sheet's native backing color does not match the rendered background")
    }
}
// Run the production callback before the hosting view's first layout.
let sheetRect = NSRect(x: 0, y: 0, width: 400, height: 200)
assert(sheetDelegate.window(windows[0], willPositionSheet: windows[2], using: sheetRect) == sheetRect)
checkSheetBackground(systemDark)
for window in windows {
    window.contentView = NSHostingView(rootView: VStack {
        SchemeProbe().frame(height: 1)
        JournalTextEditor(text: .constant("Unchanged details"), placeholder: "Details", focused: .constant(false))
    })
}
func settle() {
    for _ in 0..<5 {
        windows.forEach { $0.contentView!.layoutSubtreeIfNeeded() }
        RunLoop.main.run(until: Date().addingTimeInterval(0.01))
    }
}
func check(_ expectedDark: Bool) {
    checkSheetBackground(expectedDark)
    settle()
    for window in windows {
        let host = window.contentView!
        assert(host.appearance == nil, "Hosting view retained an appearance override")
        assert(dark(window.effectiveAppearance) == expectedDark && dark(host.effectiveAppearance) == expectedDark,
               "Window or host did not inherit its current appearance")
        assert(descendants(host).contains { $0.identifier?.rawValue == (expectedDark ? "dark" : "light") },
               "SwiftUI colorScheme retained the previous mode")
        let editor = descendants(host).compactMap { $0 as? NSTextView }.first!
        assert(editor.appearance == nil && dark(editor.effectiveAppearance) == expectedDark,
               "Native editor did not inherit the host appearance")
        let expectedInk: CGFloat = expectedDark ? 241.0 / 255 : 40.0 / 255
        for color in [editor.textColor!, editor.typingAttributes[.foregroundColor] as! NSColor,
                      editor.selectedTextAttributes[.foregroundColor] as! NSColor] {
            assert(abs(red(color, in: editor.effectiveAppearance) - expectedInk) < 0.001,
                   "Native text or selection color did not adapt")
        }
        assert(abs(red(NSColor(Theme.background), in: host.effectiveAppearance) - (expectedDark ? 23.0 / 255 : 248.0 / 255)) < 0.001,
               "Theme background did not adapt")
        assert(editor.string == "Unchanged details", "Appearance change altered the editor text")
    }
}
for mode: FixtureAppearance in [.light, .dark, .system, .dark, .light, .system] {
    apply(mode)
    assert(windows.allSatisfy { $0.appearance == nil }, "A window retained its own appearance override")
    check(mode == .system ? systemDark : mode == .dark)
    if mode == .system { assert(app.appearance == nil, "System mode must release the application override") }
}
// Change only these invisible parent windows to exercise live appearance inheritance.
for appearance: NSAppearance.Name in [.darkAqua, .aqua, .darkAqua, .aqua] {
    windows.forEach { $0.appearance = NSAppearance(named: appearance) }
    assert(app.appearance == nil, "Inherited appearance changed the application preference")
    check(appearance == .darkAqua)
}
windows.forEach { $0.appearance = nil }
check(systemDark)
print("PASS: light/dark/System transitions, live host inheritance, native text colors and sheet backing color before first layout")
'''.replace("APPEARANCE_MAPPING", mapping.group(1)).replace("SHEET_CALLBACK", sheet_callback.group(0))

with tempfile.TemporaryDirectory(prefix="justnow-appearance-check-") as directory:
    work = Path(directory)
    main = work / "main.swift"
    main.write_text(harness)
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5", "-parse-as-library",
        str(root / "Sources/JustNowCore/CalendarSelection.swift"),
        "-emit-module", "-emit-object", "-module-name", "JustNowCore",
        "-emit-module-path", str(work / "JustNowCore.swiftmodule"), "-o", str(work / "Core.o"),
    ], check=True)
    binary = work / "check"
    subprocess.run([
        "xcrun", "swiftc", "-swift-version", "5", "-I", directory,
        str(root / "Sources/JustNow/Controls.swift"), str(root / "Sources/JustNow/Theme.swift"),
        str(work / "Core.o"), str(main), "-o", str(binary),
    ], check=True)
    subprocess.run([str(binary)], check=True)

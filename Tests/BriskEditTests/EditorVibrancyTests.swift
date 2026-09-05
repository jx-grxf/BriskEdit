import AppKit
import Observation
import SwiftUI
import XCTest
@testable import BriskEdit

@MainActor
final class EditorVibrancyTests: XCTestCase {
    func testAccessibilityAndLowPowerOverrideEveryPreset() {
        for mode in EditorVibrancy.allCases {
            XCTAssertEqual(mode.resolved(reduceTransparency: true), .off)
            XCTAssertEqual(mode.resolved(reduceTransparency: false, lowPower: true), .off)
            XCTAssertEqual(mode.resolved(reduceTransparency: false), mode)
        }
    }

    func testVibrancyDefaultsOffAndPersistsIndependentlyOfTheme() throws {
        let suite = "vibrancy-tests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        XCTAssertEqual(preferences.editorVibrancy, .off)
        let palette = preferences.themeID
        preferences.editorVibrancy = .balanced
        let restored = Preferences(defaults: defaults)
        XCTAssertEqual(restored.editorVibrancy, .balanced)
        XCTAssertEqual(restored.themeID, palette)
        preferences.performanceMode = .lowPower
        XCTAssertEqual(preferences.editorTheme.vibrancy, .off)
        XCTAssertEqual(preferences.editorVibrancy, .balanced)
    }

    func testSurfaceChangesDoNotChangeTextConfiguration() {
        let solid = EditorTheme.default
        var vibrant = solid
        vibrant.vibrancy = .strong
        XCTAssertNotEqual(solid, vibrant)
        XCTAssertTrue(solid.hasSameTextAppearance(as: vibrant))
        vibrant.fontSize += 1
        XCTAssertFalse(solid.hasSameTextAppearance(as: vibrant))
    }

    func testBackdropIsReusedThenRemovedWithoutReplacingContent() throws {
        var theme = EditorTheme.default
        let backing = EditorBackingView(theme: theme)
        let content = NSView()
        backing.addSubview(content)
        XCTAssertTrue(backing.isOpaque)
        XCTAssertFalse(backing.subviews.contains { $0 is NSVisualEffectView })

        theme.vibrancy = .strong
        backing.setTheme(theme)
        let effect = try XCTUnwrap(backing.subviews.first as? NSVisualEffectView)
        XCTAssertEqual(effect.material, .underWindowBackground)
        XCTAssertEqual(effect.blendingMode, .behindWindow)
        XCTAssertEqual(effect.state, .active)
        XCTAssertTrue(backing.subviews.last === content)
        XCTAssertFalse(backing.isOpaque)

        theme.vibrancy = .subtle
        backing.setTheme(theme)
        XCTAssertEqual(backing.subviews.filter { $0 is NSVisualEffectView }.count, 1)
        XCTAssertTrue(backing.subviews.first === effect)
        theme.vibrancy = .off
        backing.setTheme(theme)
        XCTAssertEqual(backing.subviews.count, 1)
        XCTAssertTrue(backing.subviews.first === content)
        XCTAssertTrue(backing.isOpaque)
    }

    func testWindowSurfaceRestoresItsOriginalAppearance() {
        let window = NSWindow()
        window.isReleasedWhenClosed = false
        window.isOpaque = true
        window.backgroundColor = .orange
        let surface = EditorWindowSurface(window: window)
        surface.setVibrant(true)
        surface.setVibrant(true)
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor.alphaComponent, 0)
        surface.setVibrant(false)
        XCTAssertTrue(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .orange)
    }

    func testGutterAndMinimapBecomeTransparentTogether() {
        var theme = EditorTheme.default
        let gutter = TextKit2GutterView(theme: theme)
        let minimap = MinimapView(theme: theme)
        theme.vibrancy = .balanced
        gutter.setTheme(theme)
        minimap.setTheme(theme)
        XCTAssertFalse(gutter.isOpaque)
        XCTAssertFalse(minimap.isOpaque)
        XCTAssertEqual(gutter.layer?.backgroundColor?.alpha, 0)
        XCTAssertEqual(minimap.layer?.backgroundColor?.alpha, 0)
        theme.vibrancy = .off
        gutter.setTheme(theme)
        minimap.setTheme(theme)
        XCTAssertTrue(gutter.isOpaque)
        XCTAssertTrue(minimap.isOpaque)
    }

    func testLiveSurfaceChangesPreserveEditorStateAndHonorAccessibility() async throws {
        let document = TextDocument(fileURL: nil, text: String(repeating: "line of text\n", count: 200), encoding: .utf8)
        let state = VibrancyTestState()
        let systemReducesTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let hosting = NSHostingView(rootView: VibrancyTestHost(document: document, state: state))
        let panel = NonactivatingVibrancyPanel(contentRect: NSRect(x: 100, y: 100, width: 900, height: 480),
                                             styleMask: [.titled, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.contentView = hosting
        panel.orderBack(nil)
        defer { panel.close() }
        try await Task.sleep(for: .milliseconds(300))
        let textView = try XCTUnwrap(find(BriskCodeTextView.self, in: hosting))
        let layoutManager = try XCTUnwrap(textView.textLayoutManager)
        let backing = try XCTUnwrap(find(EditorBackingView.self, in: hosting))
        textView.insertText("x", replacementRange: NSRange(location: 0, length: 0))
        textView.setSelectedRange(NSRange(location: 30, length: 4))
        try await Task.sleep(for: .milliseconds(200))
        if let scrollView = textView.enclosingScrollView {
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: 120))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
        try await Task.sleep(for: .milliseconds(200))
        let revision = document.revision
        let text = textView.string
        let selection = textView.selectedRange()
        let scroll = textView.enclosingScrollView?.contentView.bounds.origin
        XCTAssertTrue(textView.undoManager?.canUndo == true)

        for mode in [EditorVibrancy.subtle, .strong, .balanced, .off, .strong] {
            state.theme.vibrancy = mode
            try await Task.sleep(for: .milliseconds(100))
            XCTAssertTrue(find(BriskCodeTextView.self, in: hosting) === textView)
            XCTAssertTrue(textView.textLayoutManager === layoutManager)
            XCTAssertEqual(textView.string, text)
            XCTAssertEqual(document.revision, revision)
            XCTAssertEqual(textView.selectedRange(), selection)
            XCTAssertEqual(textView.enclosingScrollView?.contentView.bounds.origin, scroll)
            XCTAssertTrue(textView.undoManager?.canUndo == true)
            XCTAssertEqual(backing.isVibrant, mode != .off && !systemReducesTransparency)
            XCTAssertEqual(textView.drawsBackground, mode == .off || systemReducesTransparency)
        }

        state.reduceTransparency = true
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(backing.isVibrant)
        XCTAssertTrue(textView.drawsBackground)
        XCTAssertTrue(textView.isOpaque)
        state.reduceTransparency = false
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(backing.isVibrant, !systemReducesTransparency)
        XCTAssertEqual(textView.isOpaque, systemReducesTransparency)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, String(repeating: "line of text\n", count: 200))
    }

    private func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let result = view as? T { return result }
        return view.subviews.lazy.compactMap { self.find(type, in: $0) }.first
    }
}

@MainActor @Observable
private final class VibrancyTestState {
    var theme = EditorTheme.default
    var reduceTransparency = false
}

private struct VibrancyTestHost: View {
    let document: TextDocument
    let state: VibrancyTestState
    var body: some View {
        var theme = state.theme
        theme.vibrancy = theme.vibrancy.resolved(reduceTransparency: state.reduceTransparency)
        return TextKit2EditorHost(document: document, theme: theme, showMinimap: true)
    }
}

private final class NonactivatingVibrancyPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

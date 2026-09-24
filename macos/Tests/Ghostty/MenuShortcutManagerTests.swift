import AppKit
import Foundation
import Testing
@testable import Ghostty

struct MenuShortcutManagerTests {
    @Test(.bug("https://github.com/ghostty-org/ghostty/issues/779", id: 779))
    func unbindShouldDiscardDefault() async throws {
        let config = try TemporaryConfig("keybind = super+d=unbind")

        let item = NSMenuItem(title: "Split Right", action: #selector(BaseTerminalController.splitRight(_:)), keyEquivalent: "d")
        item.keyEquivalentModifierMask = .command
        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()
        await manager.syncMenuShortcut(config, action: "new_split:right", menuItem: item)

        #expect(item.keyEquivalent.isEmpty)
        #expect(item.keyEquivalentModifierMask.isEmpty)

        try config.reload("")

        await manager.reset()
        await manager.syncMenuShortcut(config, action: "new_split:right", menuItem: item)

        #expect(item.keyEquivalent == "d")
        #expect(item.keyEquivalentModifierMask == .command)
    }

    @MainActor @Test func physicalBackquoteUsesCurrentKeyboardLayout() throws {
        let config = try TemporaryConfig("keybind=super+backquote=toggle_quick_terminal")
        let expected = try #require(KeyboardLayout.character(for: 0x32, modifiers: .command))
        let item = NSMenuItem(title: "Quick Terminal", action: nil, keyEquivalent: "")
        let manager = Ghostty.MenuShortcutManager()

        manager.reset()
        manager.syncMenuShortcut(config, action: "toggle_quick_terminal", menuItem: item)

        #expect(item.keyEquivalent == String(expected))
        #expect(item.keyEquivalentModifierMask == .command)
        #expect(!item.allowsAutomaticKeyEquivalentLocalization)
        #expect(!item.allowsAutomaticKeyEquivalentMirroring)
    }

    @Test(.bug("https://github.com/ghostty-org/ghostty/issues/11396", id: 11396))
    func overrideDefault() async throws {
        let config = try TemporaryConfig("keybind=super+h=goto_split:left")

        let hideItem = NSMenuItem(title: "Hide Ghostty", action: "hide:", keyEquivalent: "h")
        hideItem.keyEquivalentModifierMask = .command

        let goToLeftItem = NSMenuItem(title: "Select Split Left", action: "splitMoveFocusLeft:", keyEquivalent: "")

        let manager = await Ghostty.MenuShortcutManager()
        await manager.reset()

        await manager.syncMenuShortcut(config, action: nil, menuItem: hideItem)
        await manager.syncMenuShortcut(config, action: "goto_split:left", menuItem: goToLeftItem)

        #expect(hideItem.keyEquivalent.isEmpty)
        #expect(hideItem.keyEquivalentModifierMask.isEmpty)

        #expect(goToLeftItem.keyEquivalent == "h")
        #expect(goToLeftItem.keyEquivalentModifierMask == .command)
    }

    @MainActor @Test func nativeShortcutsRemapAndRestoreOnReload() throws {
        let config = try TemporaryConfig("""
        key-remap = super=ctrl
        key-remap = ctrl=super
        """)
        let root = NSMenu()
        let parent = NSMenuItem(title: "App", action: nil, keyEquivalent: "")
        root.addItem(parent)
        let menu = NSMenu()
        parent.submenu = menu
        let hide = NSMenuItem(title: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = .command
        menu.addItem(hide)
        let other = NSMenuItem(title: "Other", action: nil, keyEquivalent: "x")
        other.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(other)
        let configured = NSMenuItem(title: "New Tab", action: nil, keyEquivalent: "")
        menu.addItem(configured)
        let manager = Ghostty.MenuShortcutManager()

        for _ in 0..<2 {
            manager.reset()
            manager.syncMenuShortcut(config, action: "new_tab", menuItem: configured)
            manager.syncNativeMenuShortcuts(config, menu: root)
            #expect(hide.keyEquivalentModifierMask == .control)
            #expect(other.keyEquivalentModifierMask == [.control, .shift])
            // The configured binding was already remapped by Config.finalize.
            #expect(configured.keyEquivalentModifierMask == .control)
        }

        try config.reload("")
        manager.reset()
        manager.syncMenuShortcut(config, action: "new_tab", menuItem: configured)
        manager.syncNativeMenuShortcuts(config, menu: root)
        #expect(hide.keyEquivalentModifierMask == .command)
        #expect(other.keyEquivalentModifierMask == [.command, .shift])
        #expect(configured.keyEquivalentModifierMask == .command)
    }

    @MainActor @Test func remappedNativeShortcutDoesNotConsumeCommandH() throws {
        let config = try TemporaryConfig("""
        key-remap = super=ctrl
        key-remap = ctrl=super
        """)
        let target = ShortcutTarget()
        let menu = NSMenu()
        menu.autoenablesItems = false
        let hide = NSMenuItem(title: "Hide", action: #selector(ShortcutTarget.invoke(_:)), keyEquivalent: "h")
        hide.target = target
        hide.keyEquivalentModifierMask = .command
        menu.addItem(hide)
        let manager = Ghostty.MenuShortcutManager()
        manager.syncNativeMenuShortcuts(config, menu: menu)

        func event(_ modifiers: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: modifiers,
                timestamp: 1, windowNumber: 0, context: nil, characters: "h",
                charactersIgnoringModifiers: "h", isARepeat: false, keyCode: 4))
        }
        #expect(!menu.performKeyEquivalent(with: try event(.command)))
        #expect(target.count == 0)
        #expect(menu.performKeyEquivalent(with: try event(.control)))
        #expect(target.count == 1)
    }

    @MainActor private class ShortcutTarget: NSObject {
        var count = 0

        @objc func invoke(_ sender: NSMenuItem) {
            count += 1
        }
    }

}

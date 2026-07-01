//
//  GlobalHotKeyManager.swift
//  Reader for Language Learner
//
//  System-wide hotkey via Carbon RegisterEventHotKey — works sandboxed and
//  needs no Accessibility/Input Monitoring permission, unlike NSEvent global
//  monitors. Default binding: ⌃⌥Space toggles the Quick Lookup panel.
//

import AppKit
import Carbon.HIToolbox

@MainActor
final class GlobalHotKeyManager {
    static let shared = GlobalHotKeyManager()

    static let enabledKey = "quickLookupHotkeyEnabled"

    /// Fired on the main actor when the registered hotkey is pressed.
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    private init() {}

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) == nil
            || UserDefaults.standard.bool(forKey: enabledKey)
    }

    /// Registers ⌃⌥Space. Safe to call repeatedly — re-registers cleanly.
    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        // C callback — context arrives through userData, never captured.
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let manager = Unmanaged<GlobalHotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()
            Task { @MainActor in
                manager.onHotKey?()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x52_45_4C_4C) /* 'RELL' */, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    /// App-launch wiring: point the hotkey at the Quick Lookup panel and
    /// register when the preference allows it.
    func configureForQuickLookup() {
        onHotKey = { QuickLookupPanelController.shared.toggle() }
        if Self.isEnabled { register() }
    }
}

import Foundation
import Testing
@testable import GaxoCore

@Suite struct SettingsTests {
    private func makeStore() throws -> (SettingsStore, () -> Void) {
        (SettingsStore(defaults: MemoryPreferences()), {})
    }

    @Test func defaultsMatchSpec() {
        let s = Settings.default
        #expect(s.name == "Gaxo")
        #expect(s.resolution == .hd1080)
        #expect(s.frameRate == 60)
        #expect(s.openAtLogin == false)
        #expect(s.showStatusWindowAtLaunch == true)
        #expect(s.keepOnTop == false)
        #expect(s.closeWindowWhenMirroringStops == true)
        #expect(s.playSound == true)
        #expect(s.requireCode == false)
    }

    @Test func freshStoreReturnsDefaultsAndPersistsChanges() throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        #expect(store.settings == .default)
        store.settings.keepOnTop = true
        #expect(store.settings.keepOnTop == true)
    }

    @Test func renameRequiresRestart() {
        var renamed = Settings.default
        renamed.name = "Living Room"
        #expect(SettingsStore.requiresEngineRestart(.default, renamed))
    }

    @Test func keepOnTopDoesNotRequireRestart() {
        var changed = Settings.default
        changed.keepOnTop = true
        changed.playSound = false
        changed.closeWindowWhenMirroringStops = false
        #expect(!SettingsStore.requiresEngineRestart(.default, changed))
    }

    @Test func engineConfigUsesPort7100AndResolution() throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        let identity = DeviceIdentity(deviceID: "02:11:22:33:44:55")
        let config = store.engineConfig(identity: identity)
        #expect(config.name == "Gaxo")
        #expect(config.deviceID == "02:11:22:33:44:55")
        #expect(config.basePort == 7100)
        #expect(config.width == 1920)
        #expect(config.height == 1080)
        #expect(config.refreshRate == 60)
        #expect(config.maxFPS == 60)
        #expect(config.pinOnce == false)
        #expect(config.advertise == true)
        #expect(config.keyfile == GaxoPaths.keyfile)
    }

    @Test func emptyNameFallsBackToGaxo() {
        #expect(Settings.cleanName("") == "Gaxo")
        #expect(Settings.cleanName("   \n ") == "Gaxo")
    }

    @Test func nameIsTrimmedAndCappedAt40Chars() {
        #expect(Settings.cleanName("  Living Room  ") == "Living Room")
        let long = String(repeating: "abcde", count: 10) // 50 chars
        #expect(Settings.cleanName(long).count == 40)
        // Bonjour allows 63 bytes for "<12-hex MAC>@<name>": keep the name within 50 UTF-8 bytes.
        let wide = String(repeating: "é", count: 40) // 80 bytes
        #expect(Settings.cleanName(wide).utf8.count <= 50)
    }

    @Test func requireCodeChangeRequiresRestart() {
        var changed = Settings.default
        changed.requireCode = true
        #expect(SettingsStore.requiresEngineRestart(.default, changed))
    }

    @Test func engineConfigUsesCleanName() throws {
        let (store, cleanup) = try makeStore()
        defer { cleanup() }
        store.settings.name = "   "
        #expect(store.engineConfig(identity: DeviceIdentity(deviceID: "02:11:22:33:44:55")).name == "Gaxo")
    }

    @Test func resolutionSizes() {
        #expect(Resolution.hd720.size == (1280, 720))
        #expect(Resolution.hd1080.size == (1920, 1080))
        #expect(Resolution.qhd1440.size == (2560, 1440))
    }
}

@Suite struct NameDraftTests {
    @Test func nameDraftAppliesOnlyWhenItChangesTheName() {
        #expect(Settings.default.applyingNameDraft("Gaxo") == nil)
        #expect(Settings.default.applyingNameDraft("  Gaxo  ") == nil, "same name after cleaning")
        #expect(Settings.default.applyingNameDraft("   ") == nil, "blank falls back to the current default name")
        var expected = Settings.default
        expected.name = "Gaxo Test"
        #expect(Settings.default.applyingNameDraft(" Gaxo Test ") == expected)
    }
}

@Suite struct PairingCodeTests {
    @Test func settingsSavedBeforeCodesExistedStillLoad() throws {
        let store = SettingsStore(defaults: MemoryPreferences())
        let old = #"{"name":"Gaxo Test","openAtLogin":false,"showStatusWindowAtLaunch":true,"resolution":"hd1080","frameRate":60,"keepOnTop":true,"closeWindowWhenMirroringStops":true,"playSound":true,"requireCode":true}"#
        let prefs = MemoryPreferences()
        prefs.set(Data(old.utf8), forKey: "settings")
        let loaded = SettingsStore(defaults: prefs).settings
        #expect(loaded.name == "Gaxo Test")
        #expect(loaded.keepOnTop)
        #expect(loaded.pairingCode == nil)
        _ = store
    }

    @Test func codeIsAssignedOnceWhenAskingForACode() {
        var settings = Settings.default
        settings.requireCode = true
        let withCode = settings.ensuringPairingCode { 4821 }
        #expect(withCode.pairingCode == 4821)
        #expect(withCode.ensuringPairingCode { 1111 }.pairingCode == 4821, "keeps the existing code")
        #expect(Settings.default.ensuringPairingCode { 4821 }.pairingCode == nil, "no code while the option is off")
    }

    @Test func engineConfigCarriesTheFixedCode() {
        let prefs = MemoryPreferences()
        let store = SettingsStore(defaults: prefs)
        var settings = Settings.default
        settings.requireCode = true
        settings.pairingCode = 4821
        store.settings = settings
        let identity = DeviceIdentity(deviceID: "02:11:22:33:44:55")
        #expect(store.engineConfig(identity: identity).fixedPIN == 4821)
        settings.requireCode = false
        store.settings = settings
        #expect(store.engineConfig(identity: identity).fixedPIN == nil)
    }

    @Test func newCodeRequiresRestart() {
        var old = Settings.default
        old.requireCode = true
        old.pairingCode = 1111
        var new = old
        new.pairingCode = 2222
        #expect(SettingsStore.requiresEngineRestart(old, new))
    }

    @Test func codeIsShownWithFourDigits() {
        #expect(Settings.codeText(7) == "0007")
        #expect(Settings.codeText(4821) == "4821")
    }
}

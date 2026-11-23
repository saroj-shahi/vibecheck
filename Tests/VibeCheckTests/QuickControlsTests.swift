import CoreGraphics
import Testing
@testable import VibeCheck

/// Volume, brightness and Bluetooth quick controls. Fakes only: nothing here touches the real
/// volume, brightness or Bluetooth.
@MainActor
struct QuickControlsTests {
    // MARK: Level math

    @Test func clampsToUnitRange() {
        #expect(LevelMath.clamp(-0.2) == 0)
        #expect(LevelMath.clamp(1.7) == 1)
        #expect(LevelMath.clamp(0.42) == 0.42)
        #expect(LevelMath.clamp(.nan) == 0)
        #expect(LevelMath.clamp(.infinity) == 1)
        #expect(LevelMath.clamp(-.infinity) == 0)
    }

    @Test func percentText() {
        #expect(LevelMath.percentText(0) == "0%")
        #expect(LevelMath.percentText(0.424) == "42%")
        #expect(LevelMath.percentText(0.425) == "43%")
        #expect(LevelMath.percentText(1) == "100%")
        #expect(LevelMath.percentText(3) == "100%")
        #expect(LevelMath.percentText(-1) == "0%")
    }

    @Test func percentTextNeverExceedsFourCharacters() {
        for step in 0...100 { #expect(LevelMath.percentText(Double(step) / 100).count <= 4) }
    }

    @Test func speakerSymbol() {
        #expect(LevelMath.speakerSymbol(volume: 0.8, muted: true) == "speaker.slash.fill")
        #expect(LevelMath.speakerSymbol(volume: 0, muted: false) == "speaker.slash.fill")
        #expect(LevelMath.speakerSymbol(volume: 0.2, muted: false) == "speaker.wave.1.fill")
        #expect(LevelMath.speakerSymbol(volume: 0.5, muted: false) == "speaker.wave.2.fill")
        #expect(LevelMath.speakerSymbol(volume: 0.9, muted: false) == "speaker.wave.3.fill")
    }

    @Test func volumeSpoken() {
        #expect(LevelMath.volumeSpoken(volume: 0.5, muted: false) == "50%")
        #expect(LevelMath.volumeSpoken(volume: 0.5, muted: true) == "Muted, 50%")
    }

    // MARK: Volume

    @Test func volumeHiddenWithoutSettableOutput() {
        let fake = FakeVolume(volume: nil, muted: nil)
        let model = SystemVolume(backend: fake)
        model.refresh()
        #expect(!model.isAvailable)
    }

    @Test func volumeShownAndClamped() {
        let fake = FakeVolume(volume: 0.6, muted: false)
        let model = SystemVolume(backend: fake)
        model.refresh()
        #expect(model.isAvailable)
        #expect(model.canMute)
        #expect(model.volume == 0.6)
        model.setVolume(1.4)
        #expect(fake.volume == 1)
        #expect(model.volume == 1)
    }

    @Test func noMuteSwitchMeansIconIsDecorative() {
        let fake = FakeVolume(volume: 0.3, muted: nil)
        let model = SystemVolume(backend: fake)
        model.refresh()
        #expect(!model.canMute)
        model.toggleMute()
        #expect(!model.isMuted)
        #expect(fake.muteWrites == 0)
    }

    @Test func raisingVolumeUnmutes() {
        let fake = FakeVolume(volume: 0.3, muted: true)
        let model = SystemVolume(backend: fake)
        model.refresh()
        #expect(model.isMuted)
        model.setVolume(0.5)
        #expect(!model.isMuted)
        #expect(fake.muted == false)
    }

    @Test func toggleMuteFlipsState() {
        let fake = FakeVolume(volume: 0.3, muted: false)
        let model = SystemVolume(backend: fake)
        model.refresh()
        model.toggleMute()
        #expect(model.isMuted)
        #expect(fake.muted == true)
    }

    @Test func listenerRefreshesButNotWhileDragging() {
        let fake = FakeVolume(volume: 0.3, muted: false)
        let model = SystemVolume(backend: fake)
        model.start()
        fake.volume = 0.7
        fake.fire()
        #expect(model.volume == 0.7)
        model.isEditing = true
        fake.volume = 0.1
        fake.fire()
        #expect(model.volume == 0.7)
        model.stop()
        #expect(fake.observing == false)
    }

    @Test func outputDisappearingHidesSlider() {
        let fake = FakeVolume(volume: 0.3, muted: false)
        let model = SystemVolume(backend: fake)
        model.start()
        fake.volume = nil
        fake.fire()
        #expect(!model.isAvailable)
        model.stop()
    }

    // MARK: Brightness

    @Test func brightnessAvailability() {
        #expect(DisplayBrightness.isAvailable(hasSymbols: true, display: 1, reading: 0.5))
        #expect(!DisplayBrightness.isAvailable(hasSymbols: false, display: 1, reading: 0.5)) // symbol missing
        #expect(!DisplayBrightness.isAvailable(hasSymbols: true, display: nil, reading: nil)) // clamshell / desktop
        #expect(!DisplayBrightness.isAvailable(hasSymbols: true, display: 1, reading: nil))   // read failed
    }

    @Test func brightnessHiddenInClamshell() {
        let model = DisplayBrightness(backend: FakeBrightness(display: nil, level: 0.5))
        model.refresh()
        #expect(!model.isAvailable)
    }

    @Test func brightnessHiddenWhenSymbolsMissing() {
        let fake = FakeBrightness(display: 7, level: 0.5)
        fake.hasSymbols = false
        let model = DisplayBrightness(backend: fake)
        model.refresh()
        #expect(!model.isAvailable)
        #expect(fake.builtInQueries == 0)
    }

    @Test func brightnessReadsAndClampsWrites() {
        let fake = FakeBrightness(display: 7, level: 0.25)
        let model = DisplayBrightness(backend: fake)
        model.refresh()
        #expect(model.isAvailable)
        #expect(model.brightness == 0.25)
        model.setBrightness(-0.5)
        #expect(fake.level == 0)
        #expect(fake.lastDisplay == 7)
    }

    @Test func brightnessSetIgnoredWhenUnavailable() {
        let fake = FakeBrightness(display: nil, level: 0.5)
        let model = DisplayBrightness(backend: fake)
        model.refresh()
        model.setBrightness(0.9)
        #expect(fake.writes == 0)
    }

    // MARK: Bluetooth

    @Test func bluetoothTapDecisions() {
        #expect(BluetoothTap.decide(available: false, access: .allowed, poweredOn: true) == .unavailable)
        #expect(BluetoothTap.decide(available: true, access: .notAsked, poweredOn: nil) == .askPermission)
        #expect(BluetoothTap.decide(available: true, access: .denied, poweredOn: nil) == .denied)
        #expect(BluetoothTap.decide(available: true, access: .allowed, poweredOn: true) == .setPower(false))
        #expect(BluetoothTap.decide(available: true, access: .allowed, poweredOn: false) == .setPower(true))
        #expect(BluetoothTap.decide(available: true, access: .allowed, poweredOn: nil) == .unavailable)
    }

    @Test func bluetoothSpoken() {
        #expect(BluetoothTap.spoken(poweredOn: true) == "Bluetooth, on")
        #expect(BluetoothTap.spoken(poweredOn: false) == "Bluetooth, off")
        #expect(BluetoothTap.spoken(poweredOn: nil) == "Bluetooth")
        #expect(BluetoothTap.deniedMessage.contains("Privacy & Security"))
    }
}

@MainActor
private final class FakeVolume: VolumeBackend {
    var volume: Double?
    var muted: Bool?
    var muteWrites = 0
    var observing = false
    private var onChange: (@MainActor () -> Void)?

    init(volume: Double?, muted: Bool?) {
        self.volume = volume
        self.muted = muted
    }

    func readVolume() -> Double? { volume }
    func readMuted() -> Bool? { volume == nil ? nil : muted }
    func writeVolume(_ value: Double) -> Bool { volume = value; return true }
    func writeMuted(_ muted: Bool) -> Bool { muteWrites += 1; self.muted = muted; return true }
    func startObserving(_ onChange: @escaping @MainActor () -> Void) { observing = true; self.onChange = onChange }
    func stopObserving() { observing = false; onChange = nil }
    func fire() { onChange?() }
}

@MainActor
private final class FakeBrightness: BrightnessBackend {
    var hasSymbols = true
    var display: CGDirectDisplayID?
    var level: Double
    var writes = 0
    var builtInQueries = 0
    var lastDisplay: CGDirectDisplayID?

    init(display: CGDirectDisplayID?, level: Double) {
        self.display = display
        self.level = level
    }

    func builtInDisplay() -> CGDirectDisplayID? { builtInQueries += 1; return display }
    func readBrightness(_ display: CGDirectDisplayID) -> Double? { level }
    func writeBrightness(_ display: CGDirectDisplayID, _ value: Double) -> Bool {
        writes += 1
        lastDisplay = display
        level = value
        return true
    }
}

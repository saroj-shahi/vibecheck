import CoreGraphics
import Foundation
import Observation

/// What the brightness slider talks to; the real one is DisplayServices, tests inject a fake.
@MainActor
protocol BrightnessBackend: AnyObject {
    /// The private calls were found on this macOS.
    var hasSymbols: Bool { get }
    /// The built-in display, if it is on and active (nil in clamshell mode or on a desktop Mac).
    func builtInDisplay() -> CGDirectDisplayID?
    func readBrightness(_ display: CGDirectDisplayID) -> Double?
    @discardableResult func writeBrightness(_ display: CGDirectDisplayID, _ value: Double) -> Bool
}

/// Brightness of the built-in display, for the deck's brightness slider.
///
/// External displays are out of scope: they need DDC/CI over the display cable, which is a separate,
/// per-monitor protocol (and Apple's own external displays use yet another path).
@MainActor
@Observable
final class DisplayBrightness {
    static let shared = DisplayBrightness(backend: DisplayServicesBrightness())

    /// Pure availability decision, for tests.
    nonisolated static func isAvailable(hasSymbols: Bool, display: CGDirectDisplayID?, reading: Double?) -> Bool {
        hasSymbols && display != nil && reading != nil
    }

    /// False hides the slider.
    private(set) var isAvailable = false
    private(set) var brightness: Double = 0
    /// True while the slider is being dragged: refreshes don't move the knob.
    var isEditing = false

    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private var display: CGDirectDisplayID?

    init(backend: BrightnessBackend) {
        self.backend = backend
    }

    /// Reads the current level. Called when the deck opens; there's no change notification to listen to.
    func refresh() {
        let display = backend.hasSymbols ? backend.builtInDisplay() : nil
        let reading = display.flatMap { backend.readBrightness($0) }
        self.display = display
        isAvailable = Self.isAvailable(hasSymbols: backend.hasSymbols, display: display, reading: reading)
        if let reading, !isEditing { brightness = LevelMath.clamp(reading) }
    }

    func setBrightness(_ value: Double) {
        guard let display else { return }
        let level = LevelMath.clamp(value)
        guard (level * 100).rounded() != (brightness * 100).rounded() || level == 0 || level == 1 else { return }
        brightness = level
        backend.writeBrightness(display, level)
    }
}

/// `DisplayServices{Get,Set}Brightness` from the private DisplayServices framework, looked up at runtime
/// (never linked), so a macOS without them just hides the slider.
@MainActor
final class DisplayServicesBrightness: BrightnessBackend {
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private let getFn: GetFn?
    private let setFn: SetFn?

    init() {
        let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW)
        getFn = handle.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetFn.self) }
        setFn = handle.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetFn.self) }
    }

    var hasSymbols: Bool { getFn != nil && setFn != nil }

    func builtInDisplay() -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return nil }
        // Clamshell: the built-in panel drops out of the active list (or reports asleep).
        return displays.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 && CGDisplayIsAsleep($0) == 0 }
    }

    func readBrightness(_ display: CGDirectDisplayID) -> Double? {
        guard let getFn else { return nil }
        var value: Float = 0
        return getFn(display, &value) == 0 ? Double(value) : nil
    }

    func writeBrightness(_ display: CGDirectDisplayID, _ value: Double) -> Bool {
        guard let setFn else { return false }
        return setFn(display, Float(LevelMath.clamp(value))) == 0
    }
}

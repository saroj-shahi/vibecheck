import Foundation
import Testing
import VibeCheckShared
@testable import VibeCheck

struct ReviewFixesTests {
    @Test func settingsBackupCoversDeckAndTimelineKeys() {
        #expect(SettingsBackup.keys.contains("showQuickToggles"))
        #expect(SettingsBackup.keys.contains("showDeckSummary"))
        #expect(SettingsBackup.keys.contains("vibeTimelineRange"))
    }

    @Test func claudeLimitsParsesOpusAndSonnetKeys() {
        let payload = """
        {
          "subscription_type": "max",
          "rate_limits_available": true,
          "rate_limits": {
            "five_hour": { "utilization": 25, "resets_at": "2027-01-15T12:00:00Z" },
            "seven_day": { "utilization": 40, "resets_at": "2027-01-20T00:00:00Z" },
            "seven_day_opus": { "utilization": 60, "resets_at": "2027-01-20T00:00:00Z" },
            "seven_day_sonnet": { "utilization": 15, "resets_at": "2027-01-20T00:00:00Z" }
          }
        }
        """
        let usage = ClaudeLimitsClient.parse(Data(payload.utf8))
        #expect(usage.available)
        #expect(usage.plan == "max")
        #expect(usage.windows.count == 4)
        #expect(usage.windows.map(\.title).contains("Weekly · Opus"))
        #expect(usage.windows.map(\.title).contains("Weekly · Sonnet"))
    }

    @Test func openMeteoDecodeHandlesShortParallelArrays() throws {
        let payload = """
        {
          "utc_offset_seconds": 0,
          "current": {
            "time": "2026-11-24T10:00",
            "temperature_2m": 18.5,
            "apparent_temperature": 17.0,
            "relative_humidity_2m": 55,
            "weather_code": 1,
            "wind_speed_10m": 10.0,
            "is_day": 1
          },
          "current_units": { "wind_speed_10m": "km/h" },
          "hourly": {
            "time": ["2026-11-24T10:00", "2026-11-24T11:00", "2026-11-24T12:00"],
            "temperature_2m": [18.5],
            "weather_code": [1, 2],
            "precipitation_probability": []
          },
          "daily": {
            "time": ["2026-11-24", "2026-11-25"],
            "weather_code": [1],
            "temperature_2m_max": [20.0],
            "temperature_2m_min": [12.0],
            "precipitation_probability_max": []
          }
        }
        """
        let forecast = try OpenMeteo.decode(Data(payload.utf8))
        #expect(forecast.hours.count == 1)
        #expect(forecast.hours[0].precipitationChance == nil)
        #expect(forecast.days.count == 1)
        #expect(forecast.days[0].precipitationChance == nil)
    }

    @Test func precomputedVibeReasonsMatchDirectEvaluation() {
        let input = VibeInput(cpuRecent: 0.92, memoryPressure: .warning, hottest: 84, thermalState: .serious)
        let reasons = VibeScore.reasons(input)
        let level = VibeScore.evaluate(reasons)
        #expect(level == VibeScore.evaluate(input))
        #expect(VibeScore.held(reasons) == VibeScore.held(input))
        #expect(VibeScore.culprit(for: level, reasons: reasons) == VibeScore.culprit(for: level, input: input))
        #expect(VibeScore.badge(for: level, reasons: reasons) == VibeScore.badge(for: level, input: input))
        #expect(VibeScore.verdict(for: level, reasons: reasons, topApp: ("Xcode", 140))
                == VibeScore.verdict(for: level, input: input, topApp: ("Xcode", 140)))
    }

    @Test func binaryByteFormattingMatchesBetweenAppAndShared() {
        #expect(StatusSnapshot.bytesText(1_073_741_824) == "1.0 GB")
        #expect(Fmt.bytes(1_073_741_824) == "1.0 GB")
        #expect(Fmt.bytes(SmartAlertState.leakBytes) == "1.0 GB")
    }

    @Test func atomicPrivateFileWrites0600Atomically() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("vc-atomic-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        let file = base.appendingPathComponent("sub/data.json")
        #expect(AtomicPrivateFile.write(Data("first".utf8), to: file))
        let attrs = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect(attrs[.posixPermissions] as? Int == 0o600)
        #expect(try Data(contentsOf: file) == Data("first".utf8))
        #expect(AtomicPrivateFile.write(Data("second".utf8), to: file))
        #expect(try Data(contentsOf: file) == Data("second".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: file.deletingLastPathComponent().path) == ["data.json"])
    }
}

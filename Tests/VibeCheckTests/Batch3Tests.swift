import Foundation
import Testing
@testable import VibeCheck

struct SettingsBackupTests {
    private func suite() -> UserDefaults {
        let name = "vibecheck-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func exportImportRoundTrip() throws {
        let source = suite()
        source.set(["cpu", "clock"], forKey: "enabledModules")
        source.set("tight", forKey: "menuBarSpacing")
        source.set("not ours", forKey: "someOtherKey")

        let data = try SettingsBackup.exportData(from: source)
        let target = suite()
        let applied = try SettingsBackup.importData(data, into: target)

        #expect(applied == 2)
        #expect(target.stringArray(forKey: "enabledModules") == ["cpu", "clock"])
        #expect(target.string(forKey: "menuBarSpacing") == "tight")
        #expect(target.object(forKey: "someOtherKey") == nil)
    }

    @Test func rejectsFilesThatAreNotExports() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["enabledModules": ["cpu"]], format: .xml, options: 0)
        #expect(throws: SettingsBackup.BackupError.self) { try SettingsBackup.importData(data, into: suite()) }
    }

    @Test func resetClearsOnlyOurKeys() {
        let defaults = suite()
        defaults.set("tight", forKey: "menuBarSpacing")
        defaults.set(1, forKey: "someOtherKey")
        SettingsBackup.reset(defaults)
        #expect(defaults.object(forKey: "menuBarSpacing") == nil)
        #expect(defaults.integer(forKey: "someOtherKey") == 1)
    }
}

struct WeatherDecodingTests {
    @Test func decodesOpenMeteoResponse() throws {
        let json = """
        {"utc_offset_seconds":0,
         "current":{"time":"2026-11-18T04:15","interval":900,"temperature_2m":9.9,"apparent_temperature":6.9,
                    "relative_humidity_2m":83,"weather_code":3,"wind_speed_10m":15.5,"is_day":0},
         "current_units":{"wind_speed_10m":"km/h"},
         "hourly":{"time":["2026-11-18T02:00","2026-11-18T04:00","2026-11-18T05:00"],
                   "temperature_2m":[9.0,9.8,10.1],"weather_code":[3,3,61],"precipitation_probability":[5,10,60]},
         "daily":{"time":["2026-11-18","2026-11-19"],"weather_code":[53,63],
                  "temperature_2m_max":[11.5,10.5],"temperature_2m_min":[8.7,8.3],
                  "precipitation_probability_max":[71,100]}}
        """
        let forecast = try OpenMeteo.decode(Data(json.utf8))
        #expect(forecast.temperature == 9.9)
        #expect(forecast.isDay == false)
        #expect(forecast.windUnit == "km/h")
        #expect(forecast.hours.count == 2)      // the 02:00 hour is more than an hour old
        #expect(forecast.hours.last?.precipitationChance == 60)
        #expect(forecast.days.count == 2)
        #expect(forecast.days[1].high == 10.5)
    }

    @Test func everyCodeHasASymbolAndDescription() {
        for code in [0, 1, 2, 3, 45, 51, 61, 65, 71, 80, 95, 99, 1234] {
            #expect(!WeatherCode.symbol(code).isEmpty)
            #expect(!WeatherCode.describe(code).isEmpty)
        }
    }
}

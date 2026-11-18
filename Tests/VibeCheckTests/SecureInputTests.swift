import Foundation
import Testing
@testable import VibeCheck

struct SecureInputTests {
    @Test func readsPidFromConsoleUsers() {
        let users: [[String: Any]] = [
            ["kCGSSessionUserIDKey": 501],
            ["kCGSSessionSecureInputPID": 412, "kCGSSessionUserIDKey": 501],
        ]
        #expect(SecureInput.pid(inConsoleUsers: users) == 412)
    }

    @Test func acceptsNumericString() {
        #expect(SecureInput.pid(inConsoleUsers: [["kCGSSessionSecureInputPID": " 77 "]]) == 77)
    }

    @Test func missingOrMalformedGivesNil() {
        #expect(SecureInput.pid(inConsoleUsers: nil) == nil)
        #expect(SecureInput.pid(inConsoleUsers: "nope") == nil)
        #expect(SecureInput.pid(inConsoleUsers: [[String: Any]]()) == nil)
        #expect(SecureInput.pid(inConsoleUsers: [["other": 1]]) == nil)
        #expect(SecureInput.pid(inConsoleUsers: [["kCGSSessionSecureInputPID": 0]]) == nil)
        #expect(SecureInput.pid(inConsoleUsers: [["kCGSSessionSecureInputPID": -5]]) == nil)
        #expect(SecureInput.pid(inConsoleUsers: [["kCGSSessionSecureInputPID": "abc"]]) == nil)
    }

    @Test func parsesIORegText() {
        let text = #"""
          | "IOConsoleUsers" = ({"kCGSSessionOnConsoleKey"=Yes,"kCGSSessionSecureInputPID"=1234,"kCGSSessionUserIDKey"=501})
        """#
        #expect(SecureInput.pid(fromIORegText: text) == 1234)
        #expect(SecureInput.pid(fromIORegText: "\"kCGSSessionSecureInputPID\" = 99") == 99)
        #expect(SecureInput.pid(fromIORegText: "no such key") == nil)
        #expect(SecureInput.pid(fromIORegText: "\"kCGSSessionSecureInputPID\"=Yes") == nil)
    }

    @Test func displayNameFallsBack() {
        #expect(SecureInput.displayName(localizedName: "Terminal", processName: "login") == "Terminal")
        #expect(SecureInput.displayName(localizedName: "  ", processName: "loginwindow") == "loginwindow")
        #expect(SecureInput.displayName(localizedName: nil, processName: nil) == nil)
    }

    @Test func messageNamesTheApp() {
        #expect(SecureInputStatus(appName: "Terminal").message.contains("macOS points to Terminal."))
        #expect(!SecureInputStatus(appName: nil).message.contains("points to"))
        #expect(SecureInputStatus(appName: nil).message.hasPrefix("Shortcuts are paused while secure keyboard entry is on."))
    }
}

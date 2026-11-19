import CoreGraphics
import ApplicationServices
print(CGEvent(source: nil)!.location, "trusted:", AXIsProcessTrusted(), "postAccess:", CGPreflightPostEventAccess())

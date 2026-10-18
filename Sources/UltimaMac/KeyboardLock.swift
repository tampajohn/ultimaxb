import IOKit
import IOKit.hidsystem

/// Clear the actual macOS keyboard lock, including the hardware LED when supported.
/// The game's RunMode latch is cleared separately even if this call fails.
@MainActor
enum KeyboardLock {
    struct Result {
        let status: kern_return_t
        let enabledAfter: Bool?
    }
    static func clearCapsLock() -> Result {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return Result(status: kIOReturnNotFound, enabledAfter: nil) }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        let opened = IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection)
        guard opened == KERN_SUCCESS else { return Result(status: opened, enabledAfter: nil) }
        defer { IOServiceClose(connection) }
        let result = IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false)
        guard result == KERN_SUCCESS else { return Result(status: result, enabledAfter: nil) }
        var enabled = true
        let read = IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &enabled)
        return Result(status: read, enabledAfter: read == KERN_SUCCESS ? enabled : nil)
    }
}

import Foundation
import IOKit

/// Reads the system-wide HID (keyboard + mouse) idle time via IOKit.
/// Does NOT require Accessibility permission.
final class InputMonitor {

    /// Seconds since the last keyboard or mouse event system-wide.
    var systemIdleTime: TimeInterval {
        return fetchHIDIdleTime() ?? 0
    }

    private func fetchHIDIdleTime() -> TimeInterval? {
        var iter: io_iterator_t = 0

        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iter
        ) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        let service = IOIteratorNext(iter)
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        guard let cfValue = IORegistryEntryCreateCFProperty(
            service,
            "HIDIdleTime" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? NSNumber else { return nil }

        // HIDIdleTime is reported in nanoseconds
        return TimeInterval(cfValue.uint64Value) / 1_000_000_000.0
    }
}

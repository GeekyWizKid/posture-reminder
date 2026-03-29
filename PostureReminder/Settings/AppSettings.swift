import Foundation
import Combine

/// All user-configurable durations, persisted in UserDefaults.
final class AppSettings: ObservableObject {

    static let shared = AppSettings()

    // MARK: - Published properties (UserDefaults-backed)

    @Published var sittingAlertMinutes: Int = 45 {
        didSet { UserDefaults.standard.set(sittingAlertMinutes, forKey: Key.sittingAlert) }
    }
    /// Keyboard / mouse idle time before leaving .working state
    @Published var idleThresholdMinutes: Int = 2 {
        didSet { UserDefaults.standard.set(idleThresholdMinutes, forKey: Key.idleThreshold) }
    }
    /// Continuous resting time required to reset the sitting clock
    @Published var breakMinutes: Int = 5 {
        didSet { UserDefaults.standard.set(breakMinutes, forKey: Key.breakDuration) }
    }

    // MARK: - Derived TimeIntervals

    var sittingAlertThreshold: TimeInterval { TimeInterval(sittingAlertMinutes * 60) }
    var idleThreshold: TimeInterval         { TimeInterval(idleThresholdMinutes * 60) }
    var breakThreshold: TimeInterval        { TimeInterval(breakMinutes * 60) }

    // MARK: - Init

    private init() {
        let ud = UserDefaults.standard
        if let v = ud.object(forKey: Key.sittingAlert)   as? Int { sittingAlertMinutes   = v }
        if let v = ud.object(forKey: Key.idleThreshold)  as? Int { idleThresholdMinutes  = v }
        if let v = ud.object(forKey: Key.breakDuration)  as? Int { breakMinutes          = v }
    }

    // MARK: - Keys

    private enum Key {
        static let sittingAlert  = "sittingAlertMinutes"
        static let idleThreshold = "idleThresholdMinutes"
        static let breakDuration = "breakMinutes"
    }
}

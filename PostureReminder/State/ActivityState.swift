import Foundation

enum ActivityState: Equatable {
    /// Keyboard / mouse recently active
    case working
    /// Input idle > 2 min, body leaning forward, head facing screen — do not interrupt
    case deepThinking
    /// Input idle, relaxed / away posture
    case resting

    var displayName: String {
        switch self {
        case .working:      return NSLocalizedString("state.working",       comment: "")
        case .deepThinking: return NSLocalizedString("state.deep_thinking", comment: "")
        case .resting:      return NSLocalizedString("state.resting",       comment: "")
        }
    }

    /// SF Symbol name for the status-bar button
    var sfSymbol: String {
        switch self {
        case .working:      return "figure.seated.side"
        case .deepThinking: return "brain.head.profile"
        case .resting:      return "figure.stand"
        }
    }
}

import Foundation

/// Fine-grained visual state for the status-bar icon.
/// Derived from ActivityState + PoseResult — does NOT affect the state machine.
///
///  ActivityState  │  isPersonDetected  │  DisplayState
///  ───────────────┼────────────────────┼──────────────────
///  .working       │  any               │  .sittingWorking
///  .deepThinking  │  any               │  .deepFocus
///  .resting       │  true              │  .standingOrResting
///  .resting       │  false             │  .away
enum DisplayState: Equatable {
    /// Keyboard / mouse active — person detected sitting at desk.
    case sittingWorking
    /// Idle but leaning forward, face toward screen — deep focus.
    case deepFocus
    /// Idle, person still in frame — standing up or resting at desk.
    case standingOrResting
    /// No person detected — stepped away.
    case away

    // MARK: SF Symbol

    /// Requires SF Symbols 4 (macOS 13+); gracefully degrades to nil on older OS.
    var sfSymbol: String {
        switch self {
        case .sittingWorking:   return "figure.seated.side"
        case .deepFocus:        return "brain.head.profile"
        case .standingOrResting: return "figure.stand"
        case .away:             return "figure.walk"
        }
    }

    // MARK: Factory

    static func derive(from state: ActivityState, pose: PoseResult) -> DisplayState {
        // Person not in frame → away icon immediately, regardless of activity state
        guard pose.isPersonDetected else { return .away }

        switch state {
        case .working:      return .sittingWorking
        case .deepThinking: return .deepFocus
        case .resting:      return .standingOrResting
        }
    }
}

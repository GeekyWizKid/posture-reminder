import Foundation

/// Posture analysis result returned by PostureAnalyzer.
struct PoseResult {
    /// A person was detected in the frame.
    let isPersonDetected: Bool
    /// Body is leaning toward the screen (前倾).
    let isLeaningForward: Bool
    /// Head / face is oriented toward the screen.
    let isHeadFacingScreen: Bool

    static let notDetected = PoseResult(
        isPersonDetected: false,
        isLeaningForward: false,
        isHeadFacingScreen: false
    )
}

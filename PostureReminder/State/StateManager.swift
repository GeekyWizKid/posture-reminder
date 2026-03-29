import Foundation
import Combine

final class StateManager: ObservableObject {

    // MARK: - Published

    @Published private(set) var currentState: ActivityState = .working
    @Published private(set) var sittingDuration: TimeInterval = 0
    @Published private(set) var deepThinkingDuration: TimeInterval = 0
    @Published private(set) var latestPose: PoseResult = .notDetected
    @Published private(set) var currentIdleSeconds: TimeInterval = 0
    @Published private(set) var isCameraActive: Bool = false

    // MARK: - Sub-systems

    private let inputMonitor         = InputMonitor()
    private let cameraCapture        = CameraCapture()
    private let postureAnalyzer      = PostureAnalyzer()
    private let notificationManager  = NotificationManager()
    private let settings             = AppSettings.shared

    // MARK: - Presence / sitting timers

    /// Sitting time accumulated before the current at-desk session started
    private var sittingAccumulated: TimeInterval = 0
    /// When the current at-desk session began (nil = currently away)
    private var atDeskSince: Date? = Date()
    /// When person was first not detected (nil = person is present)
    private var notDetectedSince: Date?
    /// When the away period started (after grace period expired)
    private var awaySince: Date?
    /// Prevent repeated reset once break threshold is crossed while away
    private var didResetDuringAbsence = false

    /// How long person must be absent before the timer pauses (prevents single-frame misses)
    private let awayGracePeriod: TimeInterval = 30

    // MARK: - Deep thinking timer

    private var deepThinkingStartTime: Date?

    // MARK: - Misc

    private var evaluationTimer: Timer?
    private let evaluationInterval: TimeInterval = 5

    // MARK: - Lifecycle

    func start() {
        notificationManager.requestAuthorization()
        cameraCapture.start()

        evaluationTimer = Timer.scheduledTimer(
            withTimeInterval: evaluationInterval,
            repeats: true
        ) { [weak self] _ in self?.evaluate() }
    }

    func stop() {
        evaluationTimer?.invalidate()
        cameraCapture.stop()
    }

    func sendTestNotification() {
        notificationManager.sendTestNotification()
    }

    func resetSittingTimer() {
        sittingAccumulated  = 0
        atDeskSince         = Date()
        awaySince           = nil
        notDetectedSince    = nil
        didResetDuringAbsence = false
        deepThinkingStartTime = nil
        notificationManager.resetCooldown()
    }

    // MARK: - Core evaluation loop

    private func evaluate() {
        let now      = Date()
        let idleTime = inputMonitor.systemIdleTime

        let pose: PoseResult = {
            guard let buf = cameraCapture.latestFrame else { return .notDetected }
            return postureAnalyzer.analyze(pixelBuffer: buf)
        }()

        let newState = resolveState(idleTime: idleTime, pose: pose)

        // Detect state transitions before anything is updated
        let exitingDeepThinking = (currentState == .deepThinking && newState != .deepThinking)

        // Idle-based break: if system has been idle >= breakThreshold and we're
        // not in deep-thinking, treat it as a completed break and reset the timer.
        // This handles the common case where the user stands up but remains visible
        // to the camera, so the camera-based absence path never fires.
        if newState == .resting && idleTime >= settings.breakThreshold {
            applyIdleBreakResetIfNeeded()
        }

        updateDeepThinkingTimer(newState: newState, now: now)
        updatePresenceTimer(
            pose: pose,
            exitingDeepThinking: exitingDeepThinking,
            newState: newState,
            now: now
        )

        let sitting      = currentSittingDuration(now: now)
        let deepDuration = deepThinkingStartTime.map { now.timeIntervalSince($0) } ?? 0

        if sitting >= settings.sittingAlertThreshold && newState != .deepThinking {
            notificationManager.sendSittingReminderIfNeeded(duration: sitting)
        }

        DispatchQueue.main.async {
            self.currentState         = newState
            self.sittingDuration      = sitting
            self.deepThinkingDuration = deepDuration
            self.latestPose           = pose
            self.currentIdleSeconds   = idleTime
            self.isCameraActive       = self.cameraCapture.isRunning
        }
    }

    // MARK: - State resolution

    private func resolveState(idleTime: TimeInterval, pose: PoseResult) -> ActivityState {
        guard idleTime >= settings.idleThreshold else { return .working }
        let cameraConfirmed = cameraCapture.latestFrame != nil && pose.isPersonDetected
        if cameraConfirmed && pose.isLeaningForward && pose.isHeadFacingScreen {
            return .deepThinking
        }
        return .resting
    }

    // MARK: - Deep thinking timer

    private func updateDeepThinkingTimer(newState: ActivityState, now: Date) {
        if newState == .deepThinking {
            if deepThinkingStartTime == nil { deepThinkingStartTime = now }
        } else {
            deepThinkingStartTime = nil
        }
    }

    // MARK: - Idle-break reset

    /// Resets sitting timer when idle time alone confirms a completed break.
    /// No-op if the timer is already at zero (prevents repeated resets each tick).
    private func applyIdleBreakResetIfNeeded() {
        guard sittingAccumulated > 0 || atDeskSince != nil else { return }
        sittingAccumulated    = 0
        atDeskSince           = nil   // pause clock; updatePresenceTimer restarts it on return
        awaySince             = nil
        notDetectedSince      = nil
        didResetDuringAbsence = false
        notificationManager.resetCooldown()
    }

    // MARK: - Presence / sitting timer

    /// Returns the current (possibly frozen) sitting duration.
    private func currentSittingDuration(now: Date) -> TimeInterval {
        guard let sessionStart = atDeskSince else {
            return sittingAccumulated          // clock is paused (person away)
        }
        return sittingAccumulated + now.timeIntervalSince(sessionStart)
    }

    private func updatePresenceTimer(
        pose: PoseResult,
        exitingDeepThinking: Bool,
        newState: ActivityState,
        now: Date
    ) {
        // ── Immediate reset when finishing a deep-focus session ───────────────
        if exitingDeepThinking && newState == .resting {
            sittingAccumulated    = 0
            atDeskSince           = now
            awaySince             = nil
            notDetectedSince      = nil
            didResetDuringAbsence = false
            notificationManager.resetCooldown()
            return
        }

        // ── Determine whether person is effectively "present" ─────────────────
        // Use grace period to suppress transient detection misses.
        // Also treat camera-not-yet-started as "present" (conservative).
        let cameraHasFrame = cameraCapture.latestFrame != nil
        let rawPresent = cameraHasFrame ? pose.isPersonDetected : true

        if rawPresent {
            // ── Person is here ────────────────────────────────────────────────
            notDetectedSince = nil     // clear grace-period clock

            if awaySince != nil {
                // Just returned from confirmed absence
                let awayDuration = awaySince.map { now.timeIntervalSince($0) } ?? 0
                if awayDuration >= settings.breakThreshold || didResetDuringAbsence {
                    // Long enough break → start fresh
                    sittingAccumulated    = 0
                    notificationManager.resetCooldown()
                }
                awaySince             = nil
                didResetDuringAbsence = false
                atDeskSince           = now   // begin new at-desk session
            } else if atDeskSince == nil {
                // Resumed after grace period (awaySince wasn't set yet)
                atDeskSince = now
            }
            // else: already at desk, clock ticks via currentSittingDuration()

        } else {
            // ── Person not detected ───────────────────────────────────────────
            if notDetectedSince == nil {
                notDetectedSince = now    // start grace period
            }

            let absentDuration = notDetectedSince.map { now.timeIntervalSince($0) } ?? 0

            if absentDuration >= awayGracePeriod && awaySince == nil {
                // Grace period expired → officially away: freeze clock
                if let sessionStart = atDeskSince {
                    sittingAccumulated += now.timeIntervalSince(sessionStart)
                }
                atDeskSince = nil
                awaySince   = now
            }

            // Check if break threshold crossed while away
            if let awayStart = awaySince,
               !didResetDuringAbsence,
               now.timeIntervalSince(awayStart) >= settings.breakThreshold {
                sittingAccumulated    = 0
                didResetDuringAbsence = true
                notificationManager.resetCooldown()
            }
        }
    }
}

import Vision
import CoreML
import CoreVideo

/// Analyses a single camera frame and returns a PoseResult.
///
/// Pipeline:
///   1. Try YOLOv8n-pose via CoreML if the model bundle is present.
///   2. If YOLO returns no detection, fall through to Apple Vision.
///   3. Apple Vision (VNDetectHumanBodyPoseRequest) is the reliable baseline.
///
/// Person-detection rule: nose visible with confidence ≥ 0.10 → isPersonDetected = true.
/// Posture analysis (lean / head orientation) requires shoulders; if they are out of
/// frame the flags default to conservative values rather than "not detected".
final class PostureAnalyzer {

    private let yoloModel: VNCoreMLModel?

    // Thresholds — kept intentionally low so partial / side-angle frames still work
    private let noseMinConf:     Float = 0.10   // just needs to see the face
    private let keypointConf:    Float = 0.20   // shoulder / ear landmarks
    private let detectionConf:   Float = 0.40   // YOLO object confidence
    private let forwardLeanRatio: Float = 0.38  // face-height / shoulder-span

    init() {
        yoloModel = Self.loadYOLOModel()
    }

    // MARK: - Public

    func analyze(pixelBuffer: CVPixelBuffer) -> PoseResult {
        // Try YOLO first; if it finds no person, fall through to Apple Vision
        if let model = yoloModel {
            let result = analyzeYOLO(pixelBuffer: pixelBuffer, model: model)
            if result.isPersonDetected { return result }
        }
        return analyzeAppleVision(pixelBuffer: pixelBuffer)
    }

    // MARK: - Model loading

    private static func loadYOLOModel() -> VNCoreMLModel? {
        guard let url = Bundle.main.url(forResource: "yolov8n-pose", withExtension: "mlmodelc"),
              let mlModel = try? MLModel(contentsOf: url),
              let vnModel = try? VNCoreMLModel(for: mlModel) else { return nil }
        return vnModel
    }

    // MARK: - Apple Vision

    private func analyzeAppleVision(pixelBuffer: CVPixelBuffer) -> PoseResult {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .notDetected
        }

        // Take the highest-confidence observation (multiple people support)
        guard let obs = request.results?.max(by: { a, b in
            (try? a.recognizedPoint(.nose))?.confidence ?? 0
            < (try? b.recognizedPoint(.nose))?.confidence ?? 0
        }) else { return .notDetected }

        do {
            return try evaluateVisionObservation(obs)
        } catch {
            return .notDetected
        }
    }

    /// Vision coordinate system: (0,0) = bottom-left, Y increases upward.
    private func evaluateVisionObservation(
        _ obs: VNHumanBodyPoseObservation
    ) throws -> PoseResult {

        let pts = try obs.recognizedPoints(.all)

        // ── Person detection: only needs a visible nose ───────────────────────
        guard let nose = pts[.nose], nose.confidence >= noseMinConf else {
            return .notDetected
        }

        // ── Head orientation ──────────────────────────────────────────────────
        // Facing screen = nose is horizontally between both ears.
        // If only one or neither ear is visible, assume facing forward.
        let leftEar  = pts[.leftEar]
        let rightEar = pts[.rightEar]
        let isHeadFacing: Bool = {
            guard let le = leftEar,  le.confidence  >= keypointConf,
                  let re = rightEar, re.confidence >= keypointConf else {
                return nose.confidence >= 0.30  // ears occluded → face likely toward camera
            }
            let minX = min(le.location.x, re.location.x)
            let maxX = max(le.location.x, re.location.x)
            return nose.location.x > minX && nose.location.x < maxX
        }()

        // ── Forward lean: needs shoulders ─────────────────────────────────────
        // If shoulders are out of frame we still return isPersonDetected = true
        // but cannot determine lean; default to false (avoid false deepThinking).
        guard let ls = pts[.leftShoulder],  ls.confidence  >= keypointConf,
              let rs = pts[.rightShoulder], rs.confidence >= keypointConf else {
            return PoseResult(
                isPersonDetected: true,
                isLeaningForward: false,
                isHeadFacingScreen: isHeadFacing
            )
        }

        let shoulderMidX = (ls.location.x + rs.location.x) / 2
        let shoulderMidY = (ls.location.y + rs.location.y) / 2
        let shoulderSpan = abs(ls.location.x - rs.location.x)

        // Y increases upward in Vision coords:
        // nose.y > shoulderMid.y means nose is above shoulder line
        let noseAbove  = nose.location.y - shoulderMidY
        let faceHeight = hypot(nose.location.x - shoulderMidX,
                               nose.location.y - shoulderMidY)
        let ratio = Float(faceHeight / max(shoulderSpan, 0.01))
        let isLeaningForward = noseAbove > 0.03 && ratio > forwardLeanRatio

        return PoseResult(
            isPersonDetected: true,
            isLeaningForward: isLeaningForward,
            isHeadFacingScreen: isHeadFacing
        )
    }

    // MARK: - YOLOv8n-Pose via CoreML

    private func analyzeYOLO(pixelBuffer: CVPixelBuffer, model: VNCoreMLModel) -> PoseResult {
        let request = VNCoreMLRequest(model: model)
        request.imageCropAndScaleOption = .scaleFill
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return .notDetected
        }

        guard let results = request.results as? [VNCoreMLFeatureValueObservation],
              let output  = results.first?.featureValue.multiArrayValue
        else { return .notDetected }

        return parseYOLOOutput(output)
    }

    /// Shape [1, 56, N]:
    ///   [0][0..3][i] = cx,cy,w,h   [0][4][i] = confidence
    ///   keypoint k: x=[5+k*3], y=[6+k*3], c=[7+k*3]
    ///   Order: 0=nose 1=l_eye 2=r_eye 3=l_ear 4=r_ear
    ///          5=l_shoulder 6=r_shoulder …
    private func parseYOLOOutput(_ arr: MLMultiArray) -> PoseResult {
        guard arr.shape.count == 3, arr.shape[1].intValue == 56 else { return .notDetected }

        let n = arr.shape[2].intValue
        var bestConf: Float = 0
        var bestIdx  = -1
        for i in 0..<n {
            let c = arr[[0, 4, i] as [NSNumber]].floatValue
            if c > bestConf { bestConf = c; bestIdx = i }
        }
        guard bestConf >= detectionConf, bestIdx >= 0 else { return .notDetected }

        func kp(_ k: Int) -> (x: Float, y: Float, conf: Float) {
            let b = 5 + k * 3
            return (
                arr[[0, b,     bestIdx] as [NSNumber]].floatValue,
                arr[[0, b + 1, bestIdx] as [NSNumber]].floatValue,
                arr[[0, b + 2, bestIdx] as [NSNumber]].floatValue
            )
        }

        let nose      = kp(0)
        let leftEar   = kp(3)
        let rightEar  = kp(4)
        let ls        = kp(5)
        let rs        = kp(6)

        // Must at least see the nose
        guard nose.conf >= noseMinConf else { return .notDetected }

        let isHeadFacing: Bool = {
            guard leftEar.conf >= keypointConf, rightEar.conf >= keypointConf else {
                return nose.conf >= 0.30
            }
            let minX = min(leftEar.x, rightEar.x)
            let maxX = max(leftEar.x, rightEar.x)
            return nose.x > minX && nose.x < maxX
        }()

        guard ls.conf >= keypointConf, rs.conf >= keypointConf else {
            return PoseResult(isPersonDetected: true,
                              isLeaningForward: false,
                              isHeadFacingScreen: isHeadFacing)
        }

        // YOLO: image coords, Y increases downward
        let shoulderMidX = (ls.x + rs.x) / 2
        let shoulderMidY = (ls.y + rs.y) / 2
        let shoulderSpan = abs(ls.x - rs.x)
        let noseAbove    = shoulderMidY - nose.y   // positive = nose above shoulders
        let faceHeight   = hypot(nose.x - shoulderMidX, nose.y - shoulderMidY)
        let ratio        = faceHeight / max(shoulderSpan, 0.01)
        let isLeaningForward = noseAbove > 0.03 && ratio > forwardLeanRatio

        return PoseResult(
            isPersonDetected: true,
            isLeaningForward: isLeaningForward,
            isHeadFacingScreen: isHeadFacing
        )
    }
}

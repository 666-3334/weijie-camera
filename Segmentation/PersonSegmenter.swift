import Vision
import CoreImage
import CoreVideo

/// 使用 Vision 的人像语义分割，输出「人像=白(1)、背景=黑(0)」的灰度 mask。
/// iOS 15+ 可用，在 iPhone 13 Pro(A15) 上 balanced 档可实时运行。
final class PersonSegmenter {

    private let request = VNGeneratePersonSegmentationRequest()

    init() {
        // balanced：速度与精度折中，A15 可实时；追求精度可改 .accurate
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    /// 从相机帧生成 mask。
    /// - Parameters:
    ///   - pixelBuffer: 相机输出像素
    ///   - orientation: 与输入图像一致的 EXIF 方向，保证 mask 与源图 extent 对齐
    func mask(from pixelBuffer: CVPixelBuffer,
              orientation: CGImagePropertyOrientation) -> CIImage? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let result = request.results?.first else { return nil }
        // 关键：mask 尺寸与输入一致，需按同一方向旋转，才能和 source 对齐
        return CIImage(cvPixelBuffer: result.pixelBuffer).oriented(orientation)
    }
}

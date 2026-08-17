import AVFoundation
import CoreImage
import CoreVideo
import ImageIO

/// 管理相机会话：输出预览帧 + 拍照。
final class CameraManager: NSObject, ObservableObject {

    /// 预览帧回调（在 camera.session 队列上调用）
    var onPreviewFrame: ((CVPixelBuffer) -> Void)?
    /// 拍照完成回调（返回 JPEG 原图数据）
    var onPhotoCaptured: ((Data) -> Void)?

    @Published private(set) var isRunning = false

    /// 帧的 EXIF 方向。默认针对「后置 + 竖屏」。
    /// 若实际设备上画面/分割方向不对，只需改这一个值（.right/.left/.up/.down）。
    @Published private(set) var previewOrientation: CGImagePropertyOrientation = .right

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session", qos: .userInteractive)

    // MARK: - 启动 / 停止

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.configure()
            self.session.startRunning()
            DispatchQueue.main.async { self.isRunning = true }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - 配置

    private func configure() {
        // 已配置过输入则不重复配置
        guard session.inputs.isEmpty else { return }
        if session.isRunning { session.stopRunning() }

        session.beginConfiguration()
        session.sessionPreset = .hd1920x1080

        // 后置广角主摄
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)

        // 预览帧输出（BGRA，供实时处理）
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }

        // 拍照输出（拿原图，用于「可逆」保存）
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        session.commitConfiguration()
    }

    // MARK: - 拍照

    func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .off
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
}

// MARK: - 预览帧回调
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onPreviewFrame?(pixelBuffer)
    }
}

// MARK: - 拍照回调
extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation() else { return }
        onPhotoCaptured?(data)
    }
}

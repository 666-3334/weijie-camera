import AVFoundation
import CoreImage
import CoreVideo
import ImageIO
import UIKit
import Combine

/// 相机位置
enum CameraPosition {
    case back
    case front
}

/// 管理相机会话：输出预览帧 + 拍照。
final class CameraManager: NSObject, ObservableObject {

    /// 预览帧回调（在 camera.session 队列上调用）
    var onPreviewFrame: ((CVPixelBuffer) -> Void)?
    /// 拍照完成回调（返回 JPEG 原图数据）
    var onPhotoCaptured: ((Data) -> Void)?

    @Published private(set) var isRunning = false
    @Published private(set) var cameraPosition: CameraPosition = .back

    /// 帧的 EXIF 方向，根据设备方向 + 前后置动态计算。
    @Published private(set) var previewOrientation: CGImagePropertyOrientation = .right

    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera.session", qos: .userInteractive)
    private var rotationObserver: NSObjectProtocol?

    deinit {
        if let rotationObserver {
            NotificationCenter.default.removeObserver(rotationObserver)
        }
    }

    // MARK: - 权限

    enum PermissionStatus {
        case authorized
        case denied
        case notDetermined
    }

    static func permissionStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .authorized
        case .denied, .restricted: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video, completionHandler: completion)
    }

    // MARK: - 启动 / 停止

    func start() {
        queue.async { [weak self] in
            guard let self, !self.session.isRunning else { return }
            self.configure()
            self.session.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.startObservingRotation()
                self.updatePreviewOrientation()
            }
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
            self.stopObservingRotation()
            DispatchQueue.main.async { self.isRunning = false }
        }
    }

    // MARK: - 前后摄像头切换

    func switchCamera() {
        queue.async { [weak self] in
            guard let self else { return }
            let newPosition: AVCaptureDevice.Position =
                (self.cameraPosition == .back) ? .front : .back
            self.replaceInput(position: newPosition)
        }
    }

    // MARK: - 配置

    private func configure() {
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

    /// 切换摄像头输入：移除旧输入、添加新输入。
    private func replaceInput(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        session.commitConfiguration()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.cameraPosition = (position == .back) ? .back : .front
            self.updatePreviewOrientation()
        }
    }

    // MARK: - 方向处理

    private func startObservingRotation() {
        guard rotationObserver == nil else { return }
        rotationObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePreviewOrientation()
        }
    }

    private func stopObservingRotation() {
        if let rotationObserver {
            NotificationCenter.default.removeObserver(rotationObserver)
            self.rotationObserver = nil
        }
    }

    /// 根据设备方向 + 前后置，计算预览方向并同步到视频连接。
    private func updatePreviewOrientation() {
        let deviceOrientation = UIDevice.current.orientation
        guard deviceOrientation.isPortrait || deviceOrientation.isLandscape else { return }

        let videoOrientation: AVCaptureVideoOrientation
        switch deviceOrientation {
        case .portrait:          videoOrientation = .portrait
        case .portraitUpsideDown: videoOrientation = .portraitUpsideDown
        case .landscapeLeft:     videoOrientation = .landscapeRight   // 设备左转 -> 画面右旋
        case .landscapeRight:    videoOrientation = .landscapeLeft    // 设备右转 -> 画面左旋
        default: return
        }

        let isFront = cameraPosition == .front
        let videoConnection = videoOutput.connection(with: .video)
        videoConnection?.videoOrientation = videoOrientation
        videoConnection?.isVideoMirrored = isFront

        // 同步设置拍照输出的方向，否则照片 EXIF 方向错误
        let photoConnection = photoOutput.connection(with: .video)
        photoConnection?.videoOrientation = videoOrientation
        photoConnection?.isVideoMirrored = isFront

        previewOrientation = Self.cgOrientation(videoOrientation: videoOrientation,
                                                mirrored: isFront)
    }

    private static func cgOrientation(videoOrientation: AVCaptureVideoOrientation,
                                      mirrored: Bool) -> CGImagePropertyOrientation {
        switch videoOrientation {
        case .portrait:           return mirrored ? .leftMirrored  : .right
        case .portraitUpsideDown: return mirrored ? .rightMirrored : .left
        case .landscapeRight:     return mirrored ? .downMirrored  : .up
        case .landscapeLeft:      return mirrored ? .upMirrored    : .down
        @unknown default:         return .right
        }
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

import Foundation
import CoreImage
import CoreVideo
import Combine

/// 协调层：串联「相机帧 → 人像分割 → 风格渲染 → Metal 预览」。
final class CameraViewModel: ObservableObject {

    let camera = CameraManager()
    private let segmenter = PersonSegmenter()
    private let engine = StyleEngine()

    /// 当前风格（UI 通过绑定修改，处理队列读取）
    @Published var style: StyleVector = .neutral
    /// 相机权限被拒绝（用于 UI 提示）
    @Published var permissionDenied = false
    /// 是否有可用后置摄像头（无则禁用切换按钮）
    @Published private(set) var cameraPosition: CameraPosition = .back

    private let processingQueue = DispatchQueue(label: "frame.processing", qos: .userInteractive)
    private let lock = NSLock()
    private var isBusy = false

    /// 缓存最近一帧的人像 mask（拍照渲染成品时复用，避免照片与预览风格不一致）
    private var lastMask: CIImage?
    private var lastSource: CIImage?

    private(set) weak var previewView: MetalPreviewView?

    // MARK: - 生命周期

    func attach(preview: MetalPreviewView) {
        previewView = preview
    }

    /// 启动：先处理权限，再开启会话。
    func start() {
        switch CameraManager.permissionStatus() {
        case .authorized:
            beginSession()
        case .notDetermined:
            camera.requestPermission { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.beginSession() : (self?.permissionDenied = true)
                }
            }
        case .denied:
            DispatchQueue.main.async { self.permissionDenied = true }
        }
    }

    func stop() {
        camera.stop()
    }

    func switchCamera() {
        camera.switchCamera()
    }

    private func beginSession() {
        camera.onPreviewFrame = { [weak self] buffer in
            self?.process(buffer)
        }
        camera.start()
    }

    // MARK: - 拍照（原图 + 当前风格）

    func capture() {
        let styleSnapshot = style
        camera.onPhotoCaptured = { [weak self] data in
            self?.savePhoto(originalData: data, style: styleSnapshot)
        }
        camera.capturePhoto()
    }

    private func savePhoto(originalData: Data, style: StyleVector) {
        // 1. 可逆保存：原图 + 参数（App 内）
        PhotoStore.shared.save(originalData: originalData, style: style)

        // 2. 渲染成品并写入系统相册（用最近帧的 mask 保持一致风格）
        guard let source = CIImage(data: originalData) else { return }
        let oriented = source.oriented(camera.previewOrientation)
        let result = engine.render(source: oriented, mask: lastMask, style: style)
        if let cgImage = engine.renderToCGImage(result) {
            PhotoStore.shared.saveToPhotoLibrary(cgImage: cgImage)
        }
    }

    // MARK: - 帧处理（节流：跳过上一帧未处理完的）

    private func process(_ pixelBuffer: CVPixelBuffer) {
        lock.lock()
        guard !isBusy else { lock.unlock(); return }
        isBusy = true
        lock.unlock()

        processingQueue.async { [weak self] in
            defer {
                guard let self else { return }
                self.lock.lock()
                self.isBusy = false
                self.lock.unlock()
            }
            guard let self else { return }

            autoreleasepool {
                let orientation = self.camera.previewOrientation
                let source = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
                let mask = self.segmenter.mask(from: pixelBuffer, orientation: orientation)
                self.lastMask = mask
                self.lastSource = source
                let result = self.engine.render(source: source, mask: mask, style: self.style)
                self.previewView?.display(result)
            }
        }
    }
}

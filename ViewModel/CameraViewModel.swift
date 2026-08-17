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

    private let processingQueue = DispatchQueue(label: "frame.processing", qos: .userInteractive)
    private let lock = NSLock()
    private var isBusy = false

    private(set) weak var previewView: MetalPreviewView?

    // MARK: - 生命周期

    func attach(preview: MetalPreviewView) {
        previewView = preview
    }

    func start() {
        camera.onPreviewFrame = { [weak self] buffer in
            self?.process(buffer)
        }
        camera.start()
    }

    func stop() {
        camera.stop()
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
        PhotoStore.shared.save(originalData: originalData, style: style)
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
                let result = self.engine.render(source: source, mask: mask, style: self.style)
                self.previewView?.display(result)
            }
        }
    }
}

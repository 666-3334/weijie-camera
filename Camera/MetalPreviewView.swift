import MetalKit
import CoreImage

/// 用 Metal 把处理后的 CIImage 实时渲染到屏幕。
final class MetalPreviewView: MTKView, MTKViewDelegate {

    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var pendingImage: CIImage?

    private let renderQueue = DispatchQueue(label: "metal.preview")

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device)
        commonInit(device: device ?? MTLCreateSystemDefaultDevice()!)
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
        commonInit(device: MTLCreateSystemDefaultDevice()!)
    }

    private func commonInit(device: MTLDevice) {
        ciContext = CIContext(mtlDevice: device)
        commandQueue = device.makeCommandQueue()
        framebufferOnly = false
        colorPixelFormat = .bgra8Unorm
        delegate = self
    }

    /// 提交一帧，线程安全（可从处理队列调用）
    func display(_ image: CIImage) {
        renderQueue.async { [weak self] in
            self?.pendingImage = image
            DispatchQueue.main.async { self?.setNeedsDisplay() }
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let image = pendingImage else { return }

        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let transformed = Self.transform(image: image, toFill: target)

        ciContext.render(transformed,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: transformed.extent,
                         colorSpace: CGColorSpaceCreateDeviceRGB())

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Y 翻转 + aspect-fill 铺满 drawable（Core Image 原点在左下，需翻转）
    private static func transform(image: CIImage, toFill target: CGSize) -> CIImage {
        let src = image.extent
        let scale = max(target.width / src.width, target.height / src.height)
        let dx = (target.width - src.width * scale) / 2
        let dy = (target.height - src.height * scale) / 2

        var t = CGAffineTransform(translationX: 0, y: src.height)
            .scaledBy(x: 1, y: -1)            // 翻转 Y
        t = t.scaledBy(x: scale, y: scale)     // 缩放铺满
            .translatedBy(x: dx / scale, y: dy / scale) // 居中
        return image.transformed(by: t)
    }
}

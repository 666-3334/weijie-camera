import MetalKit
import CoreImage

/// 用 Metal 把处理后的 CIImage 实时渲染到屏幕。
final class MetalPreviewView: MTKView, MTKViewDelegate {

    private var ciContext: CIContext!
    private var commandQueue: MTLCommandQueue!
    private var pendingImage: CIImage?

    private let renderLock = NSLock()

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

    /// 提交一帧，线程安全（可从处理队列调用）。
    func display(_ image: CIImage) {
        renderLock.lock()
        pendingImage = image
        renderLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.setNeedsDisplay()
        }
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        renderLock.lock()
        let image = pendingImage
        renderLock.unlock()
        guard let image else { return }

        let target = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let transformed = Self.aspectFill(image: image, to: target)

        // 使用 P3 色彩空间，充分利用 iPhone 13 Pro 广色域屏幕
        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)
            ?? CGColorSpaceCreateDeviceRGB()

        ciContext.render(transformed,
                         to: drawable.texture,
                         commandBuffer: commandBuffer,
                         bounds: CGRect(origin: .zero, size: target),
                         colorSpace: colorSpace)

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Y 翻转 + aspect-fill 铺满 + 居中裁剪到 target 尺寸（Core Image 原点在左下，需翻转）
    private static func aspectFill(image: CIImage, to target: CGSize) -> CIImage {
        let src = image.extent
        let scale = max(target.width / src.width, target.height / src.height)
        let scaledW = src.width * scale
        let scaledH = src.height * scale
        let dx = (scaledW - target.width) / 2
        let dy = (scaledH - target.height) / 2

        // 1. 缩放 + Y 翻转令图像方向正确
        let scaled = image
            .transformed(by: CGAffineTransform(translationX: 0, y: src.height)
                .scaledBy(x: 1, y: -1))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // 2. 裁剪到 target 尺寸（居中）
        let cropRect = CGRect(x: dx, y: dy, width: target.width, height: target.height)
        return scaled.cropped(to: cropRect)
    }
}
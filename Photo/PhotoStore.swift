import UIKit
import Photos

/// 「可逆」编辑的持久化：保存原图 + 风格参数(JSON)到 Documents。
/// 之后可在 App 内重新加载原图，用同一套参数重新渲染（这才是真正的可逆，而非烘死成品）。
struct EditMeta: Codable {
    let id: String
    let style: StyleVector
    let createdAt: Date
}

final class PhotoStore {

    static let shared = PhotoStore()

    // MARK: - 可逆保存（App 内部）

    /// 保存一张照片：原图 + 参数元数据
    func save(originalData: Data, style: StyleVector) {
        let dir = editsDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let id = UUID().uuidString
        let imageURL = dir.appendingPathComponent("\(id).jpg")
        try? originalData.write(to: imageURL)

        let meta = EditMeta(id: id, style: style, createdAt: Date())
        if let data = try? JSONEncoder().encode(meta) {
            try? data.write(to: dir.appendingPathComponent("\(id).json"))
        }
    }

    /// 加载所有可逆编辑记录
    func loadAll() -> [EditMeta] {
        let dir = editsDirectory()
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil)) ?? []
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(EditMeta.self, from: data)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func editsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Edits", isDirectory: true)
    }

    // MARK: - 保存到系统相册

    /// 将渲染后的成品 CGImage 写入系统相册。
    func saveToPhotoLibrary(cgImage: CGImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }
            PHPhotoLibrary.shared().performChanges {
                guard let data = self.jpegData(from: cgImage) else { return }
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error {
                    print("[PhotoStore] 保存到相册失败: \(error.localizedDescription)")
                }
            }
        }
    }

    private func jpegData(from cgImage: CGImage, quality: CGFloat = 0.92) -> Data? {
        let uiImage = UIImage(cgImage: cgImage)
        return uiImage.jpegData(compressionQuality: quality)
    }
}
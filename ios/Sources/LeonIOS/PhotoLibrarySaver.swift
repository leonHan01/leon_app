import Foundation
import Photos
import ImageIO

enum PhotoSaveError: LocalizedError, Equatable {
    case permissionDenied, invalidImage, writeFailed
    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "没有添加照片的权限。请在系统设置中允许 Leon 添加照片后重试。"
        case .invalidImage: return "图片数据无效，请重新加载图片后重试。"
        case .writeFailed: return "图片未能保存到相册，请检查可用空间后重试。"
        }
    }
}

@MainActor
enum PhotoLibrarySaver {
    static func save(_ data: Data) async throws {
        guard !data.isEmpty, data.count <= 1_048_576,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw PhotoSaveError.invalidImage }
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw PhotoSaveError.permissionDenied }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
            }
        } catch { throw PhotoSaveError.writeFailed }
    }
}

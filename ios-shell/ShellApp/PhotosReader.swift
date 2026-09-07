import AVFoundation
import Photos
import UIKit

/// Album reader matching Android LingNative photo JSON shape.
enum PhotosReader {
  static func isAuthorized() -> Bool {
    if #available(iOS 14, *) {
      let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
      return s == .authorized || s == .limited
    }
    let s = PHPhotoLibrary.authorizationStatus()
    return s == .authorized
  }

  static func requestAccess(completion: @escaping (Bool) -> Void) {
    if isAuthorized() {
      completion(true)
      return
    }
    if #available(iOS 14, *) {
      PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
        DispatchQueue.main.async { completion(isAuthorized()) }
      }
    } else {
      PHPhotoLibrary.requestAuthorization { _ in
        DispatchQueue.main.async { completion(isAuthorized()) }
      }
    }
  }

  /// limit <= 0 → entire library. thumbMax is max edge in px (Android uses ~280 for full sync).
  static func photosJSON(limit: Int, thumbMax: Int) -> String {
    guard isAuthorized() else { return "[]" }
    let unlimited = limit <= 0
    let edge = max(64, thumbMax > 0 ? thumbMax : 280)

    let opts = PHFetchOptions()
    opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    opts.includeHiddenAssets = false
    let fetch = PHAsset.fetchAssets(with: opts)

    var assets: [PHAsset] = []
    fetch.enumerateObjects { asset, _, stop in
      if !unlimited && assets.count >= limit {
        stop.pointee = true
        return
      }
      if asset.mediaType == .image || asset.mediaType == .video {
        assets.append(asset)
      }
    }

    var rows: [[String: Any]] = []
    rows.reserveCapacity(assets.count)
    for asset in assets {
      guard let thumb = thumbnailDataURL(for: asset, maxEdge: edge) else { continue }
      let isVideo = asset.mediaType == .video
      let idPrefix = isVideo ? "v:" : "i:"
      var name = originalFilename(for: asset)
      if name.isEmpty {
        name = isVideo ? "视频" : "图片"
      }
      let takenAt: Int64
      if let d = asset.creationDate {
        takenAt = Int64(d.timeIntervalSince1970 * 1000)
      } else {
        takenAt = 0
      }
      var item: [String: Any] = [
        "id": idPrefix + asset.localIdentifier,
        "kind": isVideo ? "video" : "image",
        "name": name,
        "takenAt": takenAt,
        "thumb": thumb,
      ]
      if isVideo {
        item["duration"] = max(1, Int(round(asset.duration)))
      }
      rows.append(item)
    }

    guard JSONSerialization.isValidJSONObject(rows),
          let data = try? JSONSerialization.data(withJSONObject: rows, options: []),
          let json = String(data: data, encoding: .utf8)
    else {
      return "[]"
    }
    return json
  }

  static func photoDataURL(id: String, maxEdge: Int) -> String {
    guard isAuthorized() else { return "" }
    guard let asset = asset(forMediaId: id), asset.mediaType == .image else { return "" }
    let edge = maxEdge <= 0 ? 2048 : min(max(maxEdge, 320), 2560)
    return thumbnailDataURL(for: asset, maxEdge: edge) ?? ""
  }

  /// Returns (dataURL, durationSec).
  static func videoDataURL(id: String) -> (String, Int) {
    guard isAuthorized() else { return ("", 1) }
    guard let asset = asset(forMediaId: id), asset.mediaType == .video else { return ("", 1) }
    let duration = max(1, Int(round(asset.duration)))

    let opts = PHVideoRequestOptions()
    opts.isNetworkAccessAllowed = true
    opts.version = .current

    var outURL: URL?
    let sem = DispatchSemaphore(value: 0)
    PHImageManager.default().requestAVAsset(forVideo: asset, options: opts) { av, _, _ in
      defer { sem.signal() }
      if let urlAsset = av as? AVURLAsset {
        outURL = urlAsset.url
      }
    }
    _ = sem.wait(timeout: .now() + 180)
    guard let url = outURL, let data = try? Data(contentsOf: url), !data.isEmpty else {
      return ("", duration)
    }
    if data.count > 40 * 1024 * 1024 { return ("", duration) }
    let mime = mimeForVideoURL(url)
    let b64 = data.base64EncodedString(options: [])
    return ("data:\(mime);base64,\(b64)", duration)
  }

  // MARK: - Private

  private static func originalFilename(for asset: PHAsset) -> String {
    let resources = PHAssetResource.assetResources(for: asset)
    if let name = resources.first?.originalFilename, !name.isEmpty {
      return name
    }
    return ""
  }

  private static func asset(forMediaId raw: String) -> PHAsset? {
    var id = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if id.count > 2 {
      let second = id[id.index(id.startIndex, offsetBy: 1)]
      if second == ":" {
        let c = id[id.startIndex].lowercased()
        if c == "i" || c == "v" {
          id = String(id.dropFirst(2))
        }
      }
    }
    guard !id.isEmpty else { return nil }
    return PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
  }

  private static func thumbnailDataURL(for asset: PHAsset, maxEdge: Int) -> String? {
    let opts = PHImageRequestOptions()
    opts.isSynchronous = true
    opts.isNetworkAccessAllowed = true
    opts.deliveryMode = .highQualityFormat
    opts.resizeMode = .fast

    let size = CGSize(width: maxEdge, height: maxEdge)
    var out: UIImage?
    PHImageManager.default().requestImage(
      for: asset,
      targetSize: size,
      contentMode: .aspectFit,
      options: opts
    ) { image, info in
      let cancelled = (info?[PHImageCancelledKey] as? Bool) ?? false
      if cancelled || info?[PHImageErrorKey] != nil { return }
      out = image
    }
    guard let image = out else { return nil }
    let quality: CGFloat = maxEdge <= 400 ? 0.70 : maxEdge <= 800 ? 0.85 : 0.92
    guard let jpeg = image.jpegData(compressionQuality: quality) else { return nil }
    return "data:image/jpeg;base64," + jpeg.base64EncodedString(options: [])
  }

  private static func mimeForVideoURL(_ url: URL?) -> String {
    let ext = url?.pathExtension.lowercased() ?? ""
    if ext == "webm" { return "video/webm" }
    if ext == "mov" { return "video/quicktime" }
    return "video/mp4"
  }
}

import Accelerate
import Flutter
import ImageIO
import MobileCoreServices
import Photos

final class RemoteImageRequest: ImageRequest {
  var task: URLSessionDataTask?
  let id: Int64

  init(id: Int64, completion: @escaping @Sendable (Result<[String: Int64]?, any Error>) -> Void) {
    self.id = id
    super.init(completion: completion)
  }

  override func cancel() {
    super.cancel()
    task?.cancel()
  }
}

/// Custom fork: offline albums. Thumbnails / previews saved for chosen albums live in
/// Application Support/offline_images as "<assetId>_<size>" and are served before the network
/// (the URLCache evicts, so it cannot keep an album). Written only by the Dart offline channel.
enum OfflineStore {
  static let dir: URL = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    let d = base.appendingPathComponent("offline_images", isDirectory: true)
    try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
    return d
  }()

  /// ".../assets/<id>/thumbnail?size=preview..." -> "<id>_preview"; nil for any other URL.
  static func key(_ url: URL) -> String? {
    let parts = url.pathComponents
    guard let i = parts.lastIndex(of: "assets"), i + 2 < parts.count, parts[i + 2] == "thumbnail" else {
      return nil
    }
    let size = URLComponents(url: url, resolvingAgainstBaseURL: false)?
      .queryItems?.first(where: { $0.name == "size" })?.value ?? "thumbnail"
    return parts[i + 1] + "_" + size
  }

  static func file(_ url: URL) -> URL? {
    guard let k = key(url) else { return nil }
    let f = dir.appendingPathComponent(k)
    return FileManager.default.fileExists(atPath: f.path) ? f : nil
  }
}

class RemoteImageApiImpl: NSObject, RemoteImageApi {
  private static let registry = RequestRegistry<RemoteImageRequest>()
  private static let rgbaFormat = vImage_CGImageFormat(
    bitsPerComponent: 8,
    bitsPerPixel: 32,
    colorSpace: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
    renderingIntent: .perceptual
  )!
  private static let decodeOptions: [NSString: Bool] = [
    kCGImageSourceShouldCache: false,
    kCGImageSourceShouldCacheImmediately: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceCreateThumbnailFromImageAlways: true
  ]

  func requestImage(url: String, requestId: Int64, preferEncoded: Bool, width: Int64?, height: Int64?, completion: @escaping (Result<[String : Int64]?, any Error>) -> Void) {
    var urlRequest = URLRequest(url: URL(string: url)!)
    urlRequest.cachePolicy = .returnCacheDataElseLoad

    let request = RemoteImageRequest(id: requestId, completion: completion)

    // Custom fork: offline album copy first (works with no server)
    if let local = OfflineStore.file(urlRequest.url!), let data = try? Data(contentsOf: local) {
      Self.registry.add(requestId: requestId, request: request)
      Self.handleCompletion(request: request, encoded: preferEncoded, width: width, height: height, data: data, response: nil, error: nil)
      return
    }

    let task = URLSessionManager.shared.session.dataTask(with: urlRequest) { data, response, error in
      Self.handleCompletion(request: request, encoded: preferEncoded, width: width, height: height, data: data, response: response, error: error)
    }

    request.task = task
    Self.registry.add(requestId: requestId, request: request)
    task.resume()
  }

  private static func handleCompletion(request: RemoteImageRequest, encoded: Bool, width: Int64?, height: Int64?, data: Data?, response: URLResponse?, error: Error?) {
    if request.isCancelled {
      return request.completion(ImageProcessing.cancelledResult)
    }

    if let error = error {
      registry.remove(requestId: request.id)
      return request.completion(.failure(error))
    }

    guard let data = data else {
      registry.remove(requestId: request.id)
      return request.completion(.failure(PigeonError(code: "", message: "No data received", details: nil)))
    }

    if encoded {
      let length = data.count
      let pointer = malloc(length)!
      data.copyBytes(to: pointer.assumingMemoryBound(to: UInt8.self), count: length)

      if request.isCancelled {
        free(pointer)
        return request.completion(ImageProcessing.cancelledResult)
      }

      registry.remove(requestId: request.id)
      return request.completion(
        .success([
          "pointer": Int64(Int(bitPattern: pointer)),
          "length": Int64(length),
        ]))
    }

    ImageProcessing.queue.addOperation {
      if request.isCancelled {
        return request.completion(ImageProcessing.cancelledResult)
      }

      guard let imageSource = CGImageSourceCreateWithData(data as CFData, nil) else {
        registry.remove(requestId: request.id)
        return request.completion(.failure(PigeonError(code: "", message: "Failed to decode image for request", details: nil)))
      }

      var options: [NSString: Any] = decodeOptions
      if let maxPixelSize = targetThumbnailRenderSize(imageSource: imageSource, width: width, height: height) {
        options[kCGImageSourceThumbnailMaxPixelSize] = maxPixelSize
      }

      guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
        registry.remove(requestId: request.id)
        return request.completion(.failure(PigeonError(code: "", message: "Failed to decode image for request", details: nil)))
      }

      if request.isCancelled {
        return request.completion(ImageProcessing.cancelledResult)
      }

      do {
        let buffer = try vImage_Buffer(cgImage: cgImage, format: rgbaFormat)

        if request.isCancelled {
          buffer.free()
          return request.completion(ImageProcessing.cancelledResult)
        }

        registry.remove(requestId: request.id)
        return request.completion(
                 .success([
                   "pointer": Int64(Int(bitPattern: buffer.data)),
                   "width": Int64(buffer.width),
                   "height": Int64(buffer.height),
                   "rowBytes": Int64(buffer.rowBytes),
                 ]))
      } catch {
        registry.remove(requestId: request.id)
        return request.completion(.failure(PigeonError(code: "", message: "Failed to convert image for request: \(error)", details: nil)))
      }
    }
  }

  /// Returns the longest rendered edge needed to cover the requested size.
  private static func targetThumbnailRenderSize(imageSource: CGImageSource, width: Int64?, height: Int64?) -> Int? {
    guard let width,
          let height,
          width > 0,
          height > 0,
          let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
          let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
          let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
      return nil
    }

    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)
      .flatMap { CGImagePropertyOrientation(rawValue: $0.uint32Value) } ?? .up
    let swapsDimensions: Bool
    switch orientation {
    case .leftMirrored, .right, .rightMirrored, .left:
      swapsDimensions = true
    default:
      swapsDimensions = false
    }
    let sourceWidth = swapsDimensions ? pixelHeight.doubleValue : pixelWidth.doubleValue
    let sourceHeight = swapsDimensions ? pixelWidth.doubleValue : pixelHeight.doubleValue
    let fillScale = max(Double(width) / sourceWidth, Double(height) / sourceHeight)
    let scale = min(1, fillScale)
    return scale < 1 ? Int(ceil(max(sourceWidth * scale, sourceHeight * scale))) : nil
  }

  func cancelRequest(requestId: Int64) {
    Self.registry.remove(requestId: requestId)?.cancel()
  }

  func clearCache(completion: @escaping (Result<Int64, any Error>) -> Void) {
    Task {
      let cache = URLSessionManager.shared.session.configuration.urlCache!
      let cacheSize = Int64(cache.currentDiskUsage)
      cache.removeAllCachedResponses()
      completion(.success(cacheSize))
    }
  }
}

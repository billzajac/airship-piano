import CommonCrypto
import Foundation

final class SoundFontManager: ObservableObject {
    enum State {
        case checking
        case downloading(progress: Double)
        case ready(URL)
        case error(String)
    }

    @Published fileprivate(set) var state: State = .checking

    private static let fileName = "SalC5Light2.sf2"
    // Salamander Grand Piano — sampled from a Yamaha C5 grand piano by Alexander Holm
    // SF2 conversion "Salamander C5 Light" by HED-Sounds
    // Source: https://musical-artifacts.com/artifacts/483
    private static let downloadURL = "https://github.com/knuton/piano-notes/raw/master/SalC5Light2.sf2"
    private static let expectedSHA256 = "f0c8cb73b87e1b3b1a190e9e37ace4668fb4fcfa381f94aac00178b72e68fca4"

    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?

    private static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("AirshipPiano")
    }

    static var soundFontURL: URL {
        appSupportDir.appendingPathComponent(fileName)
    }

    init() {
        ensureSoundFont()
    }

    func useDefaultSound() {
        state = .ready(Self.soundFontURL)
    }

    func retry() {
        download()
    }

    private func ensureSoundFont() {
        let url = Self.soundFontURL
        if FileManager.default.fileExists(atPath: url.path) {
            state = .ready(url)
            return
        }
        download()
    }

    private func download() {
        // Cancel any in-flight download
        downloadTask?.cancel()
        session?.invalidateAndCancel()

        state = .downloading(progress: 0)

        let dir = Self.appSupportDir
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            state = .error("Failed to create directory: \(error.localizedDescription)")
            return
        }

        guard let url = URL(string: Self.downloadURL) else {
            state = .error("Invalid download URL")
            return
        }

        let delegate = DownloadDelegate(manager: self)
        let newSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        self.session = newSession
        let task = newSession.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }

    fileprivate static func verifySHA256(fileAt url: URL) -> Bool {
        guard let stream = InputStream(url: url) else { return false }
        stream.open()
        defer { stream.close() }

        var context = CC_SHA256_CTX()
        CC_SHA256_Init(&context)

        let bufferSize = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read < 0 { return false }
            if read == 0 { break }
            CC_SHA256_Update(&context, buffer, CC_LONG(read))
        }

        var digest = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        CC_SHA256_Final(&digest, &context)

        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return hex == expectedSHA256
    }
}

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: SoundFontManager?

    init(manager: SoundFontManager) {
        self.manager = manager
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        // Verify integrity before accepting
        guard SoundFontManager.verifySHA256(fileAt: location) else {
            manager?.state = .error("Download integrity check failed — file hash does not match expected value")
            session.invalidateAndCancel()
            return
        }

        let dest = SoundFontManager.soundFontURL
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: location, to: dest)
            manager?.state = .ready(dest)
        } catch {
            manager?.state = .error("Failed to save file: \(error.localizedDescription)")
        }
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        if let error = error {
            manager?.state = .error("Download failed: \(error.localizedDescription)")
            session.invalidateAndCancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 {
            let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
            manager?.state = .downloading(progress: progress)
        }
    }
}

import Foundation
import Combine

final class SoundFontManager: ObservableObject {
    enum State {
        case checking
        case downloading(progress: Double)
        case ready(URL)
        case error(String)
    }

    @Published var state: State = .checking

    private static let fileName = "SalC5Light2.sf2"
    // Google Drive direct download link
    private static let downloadURL = "https://drive.google.com/uc?export=download&id=0B5gPxvwx-I4KWjZ2SHZOLU42dHM"

    private var downloadTask: URLSessionDownloadTask?

    private static var appSupportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("PianoApp")
    }

    static var soundFontURL: URL {
        appSupportDir.appendingPathComponent(fileName)
    }

    func ensureSoundFont() {
        let url = Self.soundFontURL
        if FileManager.default.fileExists(atPath: url.path) {
            state = .ready(url)
            return
        }

        download()
    }

    func retry() {
        download()
    }

    private func download() {
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
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
        let task = session.downloadTask(with: url)
        self.downloadTask = task
        task.resume()
    }
}

private class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
    weak var manager: SoundFontManager?

    init(manager: SoundFontManager) {
        self.manager = manager
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
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

import AVFoundation
import Foundation

// Records from the default microphone and writes a 16 kHz mono 16-bit PCM WAV file.
// whisper.cpp reads WAV at 16 kHz; we resample on-the-fly via AVAudioConverter.
final class AudioRecorder {
    private let engine       = AVAudioEngine()
    private var converter:     AVAudioConverter?
    private var samples:       [Int16] = []
    private var isRecording    = false
    private let capSeconds:    Double = 60
    private var capTimer:      DispatchSourceTimer?
    private let onCapReached:  () -> Void

    // Called on main thread when the 60-second recording cap is reached.
    init(onCapReached: @escaping () -> Void) {
        self.onCapReached = onCapReached
    }

    // MARK: - Public API

    func start() throws {
        guard !isRecording else { return }
        samples = []

        let inputNode   = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // whisper.cpp requires 16 kHz mono
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: true) else {
            throw RecorderError.formatUnavailable
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.converterUnavailable
        }
        self.converter = conv

        let targetSR = AVAudioFrameCount(targetFormat.sampleRate)

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer: buffer, converter: conv, targetFormat: targetFormat, targetSR: targetSR)
        }

        try engine.start()
        isRecording = true

        // Auto-stop after cap
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + capSeconds)
        timer.setEventHandler { [weak self] in
            AppLogger.log("Recording cap reached (60s)", level: .warn)
            self?.onCapReached()
        }
        timer.resume()
        capTimer = timer
    }

    // Returns the URL of the written WAV file.
    @discardableResult
    func stop() throws -> URL {
        guard isRecording else { throw RecorderError.notRecording }
        capTimer?.cancel()
        capTimer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        // Release the audio device fully so the orange privacy dot disappears
        // and CoreAudio can power the mic down between sessions.
        engine.reset()
        isRecording = false
        return try writeWAV(samples: samples)
    }

    // MARK: - Audio processing

    private func process(buffer: AVAudioPCMBuffer, converter: AVAudioConverter,
                         targetFormat: AVAudioFormat, targetSR: AVAudioFrameCount) {
        // Calculate how many output frames we'll get after resampling
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 1)

        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                   frameCapacity: outputFrameCapacity) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Append the Int16 samples
        let frameCount = Int(outputBuffer.frameLength)
        if let channelData = outputBuffer.int16ChannelData {
            let ptr = channelData[0]
            samples.append(contentsOf: UnsafeBufferPointer(start: ptr, count: frameCount))
        }
    }

    // MARK: - WAV writing

    private func writeWAV(samples: [Int16]) throws -> URL {
        let sampleRate: Int32 = 16_000
        let channels:   Int16 = 1
        let bitsPerSample: Int16 = 16
        let byteRate    = sampleRate * Int32(channels) * Int32(bitsPerSample) / 8
        let blockAlign  = channels * bitsPerSample / 8
        let dataSize    = Int32(samples.count * 2)
        let chunkSize   = 36 + dataSize

        var header = Data()
        // RIFF chunk
        header.append(contentsOf: "RIFF".utf8)
        header.appendLE(chunkSize)
        header.append(contentsOf: "WAVE".utf8)
        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.appendLE(Int32(16))      // sub-chunk size for PCM
        header.appendLE(Int16(1))       // PCM = 1
        header.appendLE(channels)
        header.appendLE(sampleRate)
        header.appendLE(byteRate)
        header.appendLE(blockAlign)
        header.appendLE(bitsPerSample)
        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.appendLE(dataSize)

        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("WhisperDictate-\(UUID().uuidString).wav")

        var fileData = header
        samples.withUnsafeBufferPointer { ptr in
            fileData.append(Data(buffer: ptr))
        }
        try fileData.write(to: url)
        return url
    }
}

// MARK: - Errors

enum RecorderError: Error, LocalizedError {
    case formatUnavailable
    case converterUnavailable
    case notRecording

    var errorDescription: String? {
        switch self {
        case .formatUnavailable:   return "Could not create 16kHz audio format"
        case .converterUnavailable: return "Could not create audio format converter"
        case .notRecording:        return "Recorder was not active"
        }
    }
}

// MARK: - Data little-endian helpers

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var le = value.littleEndian
        append(Data(bytes: &le, count: MemoryLayout<T>.size))
    }
}

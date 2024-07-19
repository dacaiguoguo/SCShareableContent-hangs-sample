//
//  SCShareableContent_hangs_sampleApp.swift
//  Untitled 1
//
//  Created by Nonstrict on 2023-03-16.
//

import SwiftUI
import ScreenCaptureKit

// IMPORTANT: Make sure this app has screen recording permission
import SwiftUI
import ScreenCaptureKit

@main
struct SCShareableContent_hangs_sampleApp: App {
    @State var state = "Idle..."
    @State var detectedQRCode = "No QR code detected yet"
    let sch = ScreenCaptureHandler()

    var body: some Scene {
        WindowGroup {
            VStack {
                Text(state)
                Text(detectedQRCode) // 显示扫描出来的内容
            }
            .task {
                let timeout = Task {
                    do {
                        try await Task.sleep(nanoseconds: 3_000_000_000)
                        state = "Timeout accessing SCShareableContent.current"
                    } catch {}
                }

                do {
                    state = "Before SCShareableContent.current"
                    let content = try await SCShareableContent.current
                    state = "After SCShareableContent.current → \(content.displays.count)"
                    sch.qrCodeDetected = { qrCode in
                        detectedQRCode = qrCode
                        state = "QR code detected"
                    }
                    await sch.startCapture()
                } catch {
                    state = error.localizedDescription
                }

                timeout.cancel()
            }
        }
    }
}

import ScreenCaptureKit
import AVFoundation
import CoreImage

class ScreenCaptureHandler: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var context: CIContext
    private var detector: CIDetector
    var qrCodeDetected: ((String) -> Void)?

    override init() {
        context = CIContext()
        let options: [String: Any] = [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        detector = CIDetector(ofType: CIDetectorTypeQRCode, context: context, options: options)!
        super.init()
    }

    func startCapture() async {
        guard checkScreenCapturePermission() else {
            print("Screen capture permission not granted.")
            return
        }

        do {
            let shareableContent = try await SCShareableContent.current
            guard let display = shareableContent.displays.first else {
                print("No displays found")
                return
            }

            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60) // 60 FPS

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let queue = DispatchQueue(label: "screen_capture_queue")

            self.stream = SCStream(filter: filter, configuration: config, delegate: self)
            try self.stream?.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)

            self.stream?.startCapture { error in
                if let error = error {
                    print("Error starting capture: \(error.localizedDescription)")
                } else {
                    print("Capture started successfully")
                }
            }
        } catch {
            print("Failed to get shareable content or start stream: \(error)")
        }
    }

    func stopCapture() {
        stream?.stopCapture { error in
            if let error = error {
                print("Error stopping capture: \(error.localizedDescription)")
            } else {
                print("Capture stopped successfully")
            }
        }
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        print("Captured frame at time: \(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))")
        processImage(ciImage)
    }

    private func processImage(_ image: CIImage) {
        if let features = detector.features(in: image) as? [CIQRCodeFeature] {
            for feature in features {
                if let qrCodeString = feature.messageString {
                    print("Detected QR code: \(qrCodeString)") // 要显示的内容
                    // 调用回调函数
                    qrCodeDetected?(qrCodeString)
                    self.stopCapture() // 扫描到二维码后停止
                }
            }
        }
    }

    private func checkScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        } else {
            CGRequestScreenCaptureAccess()
            // 等待用户手动授权
            Thread.sleep(forTimeInterval: 2) // 延迟2秒以等待用户授权
            return CGPreflightScreenCaptureAccess()
        }
    }
}

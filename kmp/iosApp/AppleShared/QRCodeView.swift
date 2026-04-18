import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

struct QRCodeView: View {
    let payload: String
    var size: CGFloat = 176
    var padding: CGFloat = 16
    var backgroundColor: Color = .white
    var correctionLevel: String = "M"

    @State private var qrImage: PlatformImage?

    var body: some View {
        Group {
            if let qrImage {
                qrImageView(qrImage)
            } else {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.quaternary)
                    .frame(width: size + (padding * 2), height: size + (padding * 2))
                    .overlay {
                        ProgressView()
                    }
            }
        }
        .task(id: payload) {
            qrImage = await generateQRCode(
                from: payload,
                targetSize: size,
                correctionLevel: correctionLevel
            )
        }
        .accessibilityLabel("Código QR de enlace")
        .accessibilityValue(payload)
    }

    @ViewBuilder
    private func qrImageView(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
        Image(uiImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
#elseif canImport(AppKit)
        Image(nsImage: image)
            .interpolation(.none)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .padding(padding)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
#endif
    }

    private func generateQRCode(
        from payload: String,
        targetSize: CGFloat,
        correctionLevel: String
    ) async -> PlatformImage? {
        await Task.detached(priority: .userInitiated) {
            let context = CIContext()
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(payload.utf8)
            filter.correctionLevel = correctionLevel

            guard let outputImage = filter.outputImage else { return nil }

            let scale = max(targetSize / outputImage.extent.width, 10)
            let scaledImage = outputImage.transformed(
                by: CGAffineTransform(scaleX: scale, y: scale)
            )

            guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else {
                return nil
            }

#if canImport(UIKit)
            return UIImage(cgImage: cgImage)
#elseif canImport(AppKit)
            return NSImage(cgImage: cgImage, size: NSSize(width: scaledImage.extent.width, height: scaledImage.extent.height))
#else
            return nil
#endif
        }.value
    }
}

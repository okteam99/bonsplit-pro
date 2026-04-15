#if DEBUG
import AppKit
import Bonsplit
import Foundation

private struct ExportManifest: Decodable {
    let generatedAt: String
    let scenarioResults: [ExportScenario]
}

private struct ExportScenario: Decodable {
    let id: String
    let title: String
    let appKitPNG: String
    let scenario: ScenarioSpec
}

private struct ScenarioSpec: Decodable {
    let tab: TabSpec
    let isSelected: Bool
    let isHovered: Bool
    let isCloseHovered: Bool
    let isClosePressed: Bool
    let showsZoomIndicator: Bool
    let isZoomHovered: Bool
    let isZoomPressed: Bool
    let appearance: AppearanceSpec
}

private struct TabSpec: Decodable {
    let id: UUID
    let title: String
    let hasCustomTitle: Bool
    let icon: String?
    let iconImageDataBase64: String?
    let kind: String?
    let isDirty: Bool
    let showsNotificationBadge: Bool
    let isLoading: Bool
    let isPinned: Bool
}

private struct AppearanceSpec: Decodable {
    let tabBarHeight: Double
    let tabMinWidth: Double
    let tabMaxWidth: Double
    let tabTitleFontSize: Double
    let tabSpacing: Double
    let minimumPaneWidth: Double
    let minimumPaneHeight: Double
    let showSplitButtons: Bool
    let splitButtonsOnHover: Bool
    let tabBarLeadingInset: Double
    let splitButtonTooltips: SplitButtonTooltipsSpec
    let animationDuration: Double
    let enableAnimations: Bool
    let chromeColors: ChromeColorsSpec
}

private struct SplitButtonTooltipsSpec: Decodable {
    let newTerminal: String
    let newBrowser: String
    let splitRight: String
    let splitDown: String
}

private struct ChromeColorsSpec: Decodable {
    let backgroundHex: String?
    let borderHex: String?
}

private struct DiffMetrics: Codable {
    let width: Int
    let height: Int
    let differingPixelCount: Int
    let totalPixelCount: Int
    let maxChannelDelta: Int
    let meanAbsoluteChannelDelta: Double
    let matchingPixels: Bool
}

private struct ComparisonScenarioResult: Codable {
    let id: String
    let title: String
    let appKitPNG: String
    let referencePNG: String
    let diffPNG: String
    let metrics: DiffMetrics
}

private struct ComparisonManifest: Codable {
    let generatedAt: String
    let scenarioResults: [ComparisonScenarioResult]
}

@main
struct BonsplitTabChromeDebugCLI {
    @MainActor
    static func main() throws {
        _ = NSApplication.shared

        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 1 else {
            fputs("usage: BonsplitTabChromeDebugCLI <export-dir>\n", stderr)
            Foundation.exit(64)
        }

        let exportDirectory = URL(fileURLWithPath: arguments[0], isDirectory: true)
        let manifestURL = exportDirectory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: manifestURL)
        let manifest = try JSONDecoder().decode(ExportManifest.self, from: data)

        var comparisonResults: [ComparisonScenarioResult] = []
        for scenarioResult in manifest.scenarioResults {
            let referenceName = "\(scenarioResult.id)-reference.png"
            let diffName = "\(scenarioResult.id)-diff.png"
            let appKitURL = exportDirectory.appendingPathComponent(scenarioResult.appKitPNG)
            let referenceURL = exportDirectory.appendingPathComponent(referenceName)
            let diffURL = exportDirectory.appendingPathComponent(diffName)

            guard let appKitImage = NSImage(contentsOf: appKitURL),
                  let referenceImage = BonsplitTabChromeDebugRenderer.renderImage(
                    scenario: bonsplitScenario(from: scenarioResult.scenario),
                    scale: 2
                  ),
                  let diff = diffImages(appKitImage: appKitImage, referenceImage: referenceImage) else {
                continue
            }

            try writePNG(image: referenceImage, to: referenceURL)
            try writePNG(image: diff.image, to: diffURL)
            comparisonResults.append(
                ComparisonScenarioResult(
                    id: scenarioResult.id,
                    title: scenarioResult.title,
                    appKitPNG: scenarioResult.appKitPNG,
                    referencePNG: referenceName,
                    diffPNG: diffName,
                    metrics: diff.metrics
                )
            )
        }

        let formatter = ISO8601DateFormatter()
        let comparisonManifest = ComparisonManifest(
            generatedAt: formatter.string(from: Date()),
            scenarioResults: comparisonResults
        )
        let comparisonURL = exportDirectory.appendingPathComponent("comparison-manifest.json")
        let comparisonData = try JSONEncoder().encode(comparisonManifest)
        try comparisonData.write(to: comparisonURL, options: .atomic)
    }

    @MainActor
    private static func bonsplitScenario(from spec: ScenarioSpec) -> BonsplitTabChromeDebugScenario {
        BonsplitTabChromeDebugScenario(
            tab: Tab(
                id: TabID(uuid: spec.tab.id),
                title: spec.tab.title,
                hasCustomTitle: spec.tab.hasCustomTitle,
                icon: spec.tab.icon,
                iconImageData: spec.tab.iconImageDataBase64.flatMap { Data(base64Encoded: $0) },
                kind: spec.tab.kind,
                isDirty: spec.tab.isDirty,
                showsNotificationBadge: spec.tab.showsNotificationBadge,
                isLoading: spec.tab.isLoading,
                isPinned: spec.tab.isPinned
            ),
            isSelected: spec.isSelected,
            isHovered: spec.isHovered,
            isCloseHovered: spec.isCloseHovered,
            isClosePressed: spec.isClosePressed,
            showsZoomIndicator: spec.showsZoomIndicator,
            isZoomHovered: spec.isZoomHovered,
            isZoomPressed: spec.isZoomPressed,
            appearance: BonsplitConfiguration.Appearance(
                tabBarHeight: spec.appearance.tabBarHeight,
                tabMinWidth: spec.appearance.tabMinWidth,
                tabMaxWidth: spec.appearance.tabMaxWidth,
                tabTitleFontSize: spec.appearance.tabTitleFontSize,
                tabSpacing: spec.appearance.tabSpacing,
                minimumPaneWidth: spec.appearance.minimumPaneWidth,
                minimumPaneHeight: spec.appearance.minimumPaneHeight,
                showSplitButtons: spec.appearance.showSplitButtons,
                splitButtonsOnHover: spec.appearance.splitButtonsOnHover,
                tabBarLeadingInset: spec.appearance.tabBarLeadingInset,
                splitButtonTooltips: BonsplitConfiguration.SplitButtonTooltips(
                    newTerminal: spec.appearance.splitButtonTooltips.newTerminal,
                    newBrowser: spec.appearance.splitButtonTooltips.newBrowser,
                    splitRight: spec.appearance.splitButtonTooltips.splitRight,
                    splitDown: spec.appearance.splitButtonTooltips.splitDown
                ),
                animationDuration: spec.appearance.animationDuration,
                enableAnimations: spec.appearance.enableAnimations,
                chromeColors: BonsplitConfiguration.Appearance.ChromeColors(
                    backgroundHex: spec.appearance.chromeColors.backgroundHex,
                    borderHex: spec.appearance.chromeColors.borderHex
                )
            ),
            saturation: 1.0,
            fixedSpinnerPhaseDegrees: spec.tab.isLoading ? 0 : nil
        )
    }

    private static func diffImages(
        appKitImage: NSImage,
        referenceImage: NSImage
    ) -> (image: NSImage, metrics: DiffMetrics)? {
        guard let appKitBuffer = rgbaImageBuffer(from: appKitImage),
              let referenceBuffer = rgbaImageBuffer(from: referenceImage) else {
            return nil
        }

        let width = max(appKitBuffer.width, referenceBuffer.width)
        let height = max(appKitBuffer.height, referenceBuffer.height)
        guard let resizedAppKit = resizeImageBuffer(appKitBuffer, width: width, height: height),
              let resizedReference = resizeImageBuffer(referenceBuffer, width: width, height: height) else {
            return nil
        }

        var diffBytes = [UInt8](repeating: 0, count: width * height * 4)
        var differingPixelCount = 0
        var maxChannelDelta = 0
        var totalChannelDelta = 0

        for pixelIndex in 0..<(width * height) {
            let base = pixelIndex * 4
            let rDelta = abs(Int(resizedAppKit.bytes[base]) - Int(resizedReference.bytes[base]))
            let gDelta = abs(Int(resizedAppKit.bytes[base + 1]) - Int(resizedReference.bytes[base + 1]))
            let bDelta = abs(Int(resizedAppKit.bytes[base + 2]) - Int(resizedReference.bytes[base + 2]))
            let aDelta = abs(Int(resizedAppKit.bytes[base + 3]) - Int(resizedReference.bytes[base + 3]))
            let pixelMax = max(rDelta, gDelta, bDelta, aDelta)
            if pixelMax > 0 {
                differingPixelCount += 1
            }
            maxChannelDelta = max(maxChannelDelta, pixelMax)
            totalChannelDelta += rDelta + gDelta + bDelta + aDelta

            diffBytes[base] = UInt8(clamping: rDelta)
            diffBytes[base + 1] = UInt8(clamping: gDelta)
            diffBytes[base + 2] = UInt8(clamping: bDelta)
            diffBytes[base + 3] = pixelMax == 0 ? 0 : 255
        }

        guard let diffImage = imageFromRGBABytes(diffBytes, width: width, height: height) else {
            return nil
        }

        let totalPixels = width * height
        let meanAbsoluteChannelDelta = totalPixels == 0
            ? 0
            : Double(totalChannelDelta) / Double(totalPixels * 4)
        let metrics = DiffMetrics(
            width: width,
            height: height,
            differingPixelCount: differingPixelCount,
            totalPixelCount: totalPixels,
            maxChannelDelta: maxChannelDelta,
            meanAbsoluteChannelDelta: meanAbsoluteChannelDelta,
            matchingPixels: differingPixelCount == 0
        )
        return (diffImage, metrics)
    }

    private struct RGBAImageBuffer {
        let width: Int
        let height: Int
        let bytes: [UInt8]
    }

    private static func rgbaImageBuffer(from image: NSImage) -> RGBAImageBuffer? {
        guard let cgImage = cgImage(from: image) else { return nil }
        return rgbaImageBuffer(from: cgImage)
    }

    private static func rgbaImageBuffer(from cgImage: CGImage) -> RGBAImageBuffer? {
        let width = cgImage.width
        let height = cgImage.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAImageBuffer(width: width, height: height, bytes: bytes)
    }

    private static func resizeImageBuffer(
        _ buffer: RGBAImageBuffer,
        width: Int,
        height: Int
    ) -> RGBAImageBuffer? {
        guard let image = imageFromRGBABytes(buffer.bytes, width: buffer.width, height: buffer.height),
              let cgImage = cgImage(from: image) else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &bytes,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .none
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBAImageBuffer(width: width, height: height, bytes: bytes)
    }

    private static func imageFromRGBABytes(
        _ bytes: [UInt8],
        width: Int,
        height: Int
    ) -> NSImage? {
        let data = Data(bytes)
        guard let provider = CGDataProvider(data: data as CFData),
              let cgImage = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: CGSize(width: width, height: height))
    }

    private static func cgImage(from image: NSImage) -> CGImage? {
        var proposed = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) {
            return cgImage
        }
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.cgImage
    }

    private static func writePNG(image: NSImage, to url: URL) throws {
        guard let cgImage = cgImage(from: image) else {
            throw NSError(domain: "BonsplitTabChromeDebugCLI", code: 1, userInfo: nil)
        }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "BonsplitTabChromeDebugCLI", code: 2, userInfo: nil)
        }
        try data.write(to: url, options: .atomic)
    }
}
#else
import Foundation

@main
struct BonsplitTabChromeDebugCLI {
    static func main() {
        fputs("BonsplitTabChromeDebugCLI requires a DEBUG build.\n", stderr)
        Foundation.exit(64)
    }
}
#endif

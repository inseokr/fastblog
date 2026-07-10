import Foundation
import CoreImage
import UIKit
import SwiftUI

/// Supports feature ①: hero photo dominant color → blog theme.
/// CIAreaAverage — pure pixel math (one of Prof. Seoin's "O" items).
enum ColorTheme {

    struct Theme {
        let name: String
        let emotion: String
        let primary: Color
        let secondary: Color
    }

    static func from(image: UIImage) -> Theme {
        let avg = averageColor(of: image)
        var hue: CGFloat = 0, sat: CGFloat = 0, bri: CGFloat = 0, alpha: CGFloat = 0
        avg.getHue(&hue, saturation: &sat, brightness: &bri, alpha: &alpha)

        // Prof. Kim's mapping: warm → amber/terracotta, cool → navy/steel, nature → sage/olive
        switch hue {
        case 0..<0.17, 0.92...1.0:
            return Theme(name: "Amber / Terracotta", emotion: "Adventurous · dynamic",
                         primary: Color(red: 0.85, green: 0.55, blue: 0.20),
                         secondary: Color(red: 0.55, green: 0.30, blue: 0.15))
        case 0.45..<0.75:
            return Theme(name: "Navy / Steel", emotion: "Calm · mysterious",
                         primary: Color(red: 0.16, green: 0.28, blue: 0.45),
                         secondary: Color(red: 0.40, green: 0.50, blue: 0.60))
        default:
            return Theme(name: "Sage / Olive", emotion: "Healing · relaxed",
                         primary: Color(red: 0.45, green: 0.55, blue: 0.40),
                         secondary: Color(red: 0.60, green: 0.62, blue: 0.45))
        }
    }

    private static func averageColor(of image: UIImage) -> UIColor {
        guard let ciImage = CIImage(image: image) else { return .gray }
        let extent = ciImage.extent
        guard let filter = CIFilter(name: "CIAreaAverage",
                                    parameters: [kCIInputImageKey: ciImage,
                                                 kCIInputExtentKey: CIVector(cgRect: extent)]),
              let output = filter.outputImage else { return .gray }
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: kCFNull as Any])
        context.render(output, toBitmap: &pixel, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
        return UIColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                       blue: CGFloat(pixel[2]) / 255, alpha: 1)
    }
}

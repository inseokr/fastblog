import Foundation
import CoreGraphics
import ImageIO

func process() {
    let url = URL(fileURLWithPath: "/Users/justinseo/.gemini/antigravity/brain/ea64f05c-286e-4716-babf-cf6e79da9dc7/media__1773224493587.png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        print("Failed to load image")
        return
    }
    
    let width = cgImage.width
    let height = cgImage.height
    
    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data,
          let ptr = CFDataGetBytePtr(data) else {
        print("Failed to get image bytes")
        return
    }
    
    let bpr = cgImage.bytesPerRow
    let bpp = cgImage.bitsPerPixel
    
    var opaqueCount = 0
    var transparentCount = 0
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bpr + x * (bpp/8)
            let a = bpp == 32 ? ptr[offset+3] : 255
            if a > 128 {
                opaqueCount += 1
            } else {
                transparentCount += 1
            }
        }
    }
    
    print("Opaque pixels: \(opaqueCount)")
    print("Transparent pixels: \(transparentCount)")
}

process()

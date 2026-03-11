import UIKit

func testPDF() {
    let url = URL(fileURLWithPath: "/Users/justinseo/Desktop/fastblog/test.pdf")
    let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 200, height: 200))
    guard let img = UIImage(contentsOfFile: "/Users/justinseo/.gemini/antigravity/brain/ea64f05c-286e-4716-babf-cf6e79da9dc7/media__1773224493587.png") else {
        print("Image load failed")
        return
    }
    
    // Test 1: withTintColor
    let tinted = img.withTintColor(.black, renderingMode: .alwaysOriginal)
    
    do {
        try renderer.writePDF(to: url) { ctx in
            ctx.beginPage()
            
            // Draw regular image
            img.draw(in: CGRect(x: 10, y: 10, width: 50, height: 50))
            
            // Draw tinted image
            tinted.draw(in: CGRect(x: 10, y: 70, width: 50, height: 50))
            
            // Draw via NSAttributedString
            let attach = NSTextAttachment()
            attach.image = tinted
            attach.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
            let attrStr = NSAttributedString(attachment: attach)
            attrStr.draw(at: CGPoint(x: 10, y: 130))
            
            let attach2 = NSTextAttachment()
            attach2.image = img
            attach2.bounds = CGRect(x: 0, y: 0, width: 13, height: 13)
            let attrStr2 = NSAttributedString(attachment: attach2)
            attrStr2.draw(at: CGPoint(x: 50, y: 130))
        }
        print("Success, written to test.pdf")
    } catch {
        print("Error: \(error)")
    }
}

testPDF()

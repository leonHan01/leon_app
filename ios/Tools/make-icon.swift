import Foundation
import CoreGraphics
import ImageIO
let input = URL(fileURLWithPath:CommandLine.arguments[1]), output = URL(fileURLWithPath:CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL,nil), let image = CGImageSourceCreateImageAtIndex(source,0,nil),
      let context = CGContext(data:nil,width:1024,height:1024,bitsPerComponent:8,bytesPerRow:4096,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue) else {throw NSError(domain:"Icon",code:1)}
context.setFillColor(CGColor(red:1,green:1,blue:1,alpha:1));context.fill(CGRect(x:0,y:0,width:1024,height:1024));context.draw(image,in:CGRect(x:0,y:0,width:1024,height:1024))
guard let flattened = context.makeImage(), let destination = CGImageDestinationCreateWithURL(output as CFURL,"public.png" as CFString,1,nil) else {throw NSError(domain:"Icon",code:2)}
CGImageDestinationAddImage(destination,flattened,nil)
guard CGImageDestinationFinalize(destination) else {throw NSError(domain:"Icon",code:3)}

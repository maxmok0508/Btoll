import AppKit
let path=URL(fileURLWithPath:CommandLine.arguments[1])
var labels=try JSONSerialization.jsonObject(with:Data(contentsOf:path)) as! [String:String]
for phase in ["处理中","响应中","等待输入","已完成","已中止"] {
 for remaining in -1...100 {
  autoreleasepool {
   let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:168,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
   let context=NSGraphicsContext.current!.cgContext;context.scaleBy(x:2,y:2)
   NSColor.black.setFill();NSRect(x:0,y:0,width:84,height:32).fill()
   let font=NSFont.monospacedDigitSystemFont(ofSize:12,weight:.medium)
   func draw(_ text:String,_ y:CGFloat,_ color:NSColor) {
    let value=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:color])
    value.draw(at:NSPoint(x:80-value.size().width,y:y))
   }
   draw(phase,18.5,.white)
   let ratio=Double(max(0,remaining))/100
   let color=remaining<0 ? NSColor.gray : NSColor(calibratedRed:ratio<0.5 ? 1 : 1-(ratio-0.5)*1.68,green:ratio<0.5 ? 0.22+ratio : 0.72+(ratio-0.5)*0.2,blue:ratio<0.5 ? 0.25-ratio*0.18 : 0.16+(ratio-0.5)*0.42,alpha:1)
   draw(remaining<0 ? "额度待同步":"周余 \(remaining)%",3.5,color)
   if remaining>=0 {
    NSColor.white.withAlphaComponent(0.18).setFill();NSBezierPath(roundedRect:NSRect(x:12,y:1,width:68,height:1.5),xRadius:0.75,yRadius:0.75).fill()
    color.setFill();NSBezierPath(roundedRect:NSRect(x:12,y:1,width:68*ratio,height:1.5),xRadius:0.75,yRadius:0.75).fill()
   }
   NSGraphicsContext.restoreGraphicsState()
   labels["\(phase)|\(remaining)"]=rep.representation(using:.png,properties:[:])!.base64EncodedString()
  }
 }
}
try JSONSerialization.data(withJSONObject:labels,options:[.sortedKeys]).write(to:path,options:.atomic)
print("Status labels:",labels.count)

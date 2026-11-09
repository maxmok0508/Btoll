import AppKit
let path=URL(fileURLWithPath:CommandLine.arguments[1])
let english=CommandLine.arguments.count>2 && CommandLine.arguments[2]=="en"
var labels=((try? Data(contentsOf:path)).flatMap { try? JSONSerialization.jsonObject(with:$0) } as? [String:String]) ?? [:]
let names=["工作中":"Working","执行中":"Running","等待中":"Idle","待确认":"Uncertain","处理中":"Processing","响应中":"Responding","等待输入":"Needs input","已完成":"Done","已中止":"Stopped"]
for phase in (english ? ["工作中","执行中","等待中","待确认","处理中","响应中","等待输入","已完成","已中止"] : ["处理中","响应中","等待输入","已完成","已中止"]) {
 for remaining in -1...100 {
  autoreleasepool {
   let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:168,pixelsHigh:64,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
   NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
   let context=NSGraphicsContext.current!.cgContext;context.scaleBy(x:2,y:2)
   NSColor.black.setFill();NSRect(x:0,y:0,width:84,height:32).fill()
   let fontSize:CGFloat=english ? 11:12
   let font=NSFont.monospacedDigitSystemFont(ofSize:fontSize,weight:.medium)
   func draw(_ text:String,_ y:CGFloat,_ color:NSColor) {
    var value=NSAttributedString(string:text,attributes:[.font:font,.foregroundColor:color])
    if value.size().width>78 {
        value=NSAttributedString(string:text,attributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:fontSize*78/value.size().width,weight:.medium),.foregroundColor:color])
    }
    value.draw(at:NSPoint(x:80-value.size().width,y:y))
   }
   draw(english ? names[phase]! : phase,english ? 17.5:18.5,.white)
   let ratio=Double(max(0,remaining))/100
   let color=remaining<0 ? NSColor.gray : NSColor(calibratedRed:ratio<0.5 ? 1 : 1-(ratio-0.5)*1.68,green:ratio<0.5 ? 0.22+ratio : 0.72+(ratio-0.5)*0.2,blue:ratio<0.5 ? 0.25-ratio*0.18 : 0.16+(ratio-0.5)*0.42,alpha:1)
   draw(english ? (remaining<0 ? "Quota pending":"Week \(remaining)%") : (remaining<0 ? "额度待同步":"周余 \(remaining)%"),3.5,color)
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

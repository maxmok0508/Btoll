import Foundation
let smc=SMC.shared
var result:[String:Double]=[:]
for key in smc.getAllKeys() where (key.hasPrefix("T") || key.hasPrefix("F")) { if let v=smc.getValue(key),v>=0,v<20000 {result[key]=v} }
if let data=try? JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]), let line=String(data:data,encoding:.utf8) {print(line)}

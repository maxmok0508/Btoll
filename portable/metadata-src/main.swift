import Foundation
import SQLite3
let root=ProcessInfo.processInfo.environment["CODEX_HOME"].map{URL(fileURLWithPath:$0)} ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
let databases=((try? FileManager.default.contentsOfDirectory(at:root,includingPropertiesForKeys:nil)) ?? []).filter{$0.lastPathComponent.range(of:"^state_[0-9]+\\.sqlite$",options:.regularExpression) != nil}.sorted{($0.lastPathComponent as NSString).compare($1.lastPathComponent,options:.numeric) == .orderedDescending}
var result:[[String:Any]]=[]
if let file=databases.first {
 var db:OpaquePointer?
 if sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_NOMUTEX,nil) == SQLITE_OK,let db {
  defer{sqlite3_close(db)}
  sqlite3_busy_timeout(db,1000)
  var columns=Set<String>();var statement:OpaquePointer?
  if sqlite3_prepare_v2(db,"PRAGMA table_info(threads)",-1,&statement,nil) == SQLITE_OK {
   while sqlite3_step(statement)==SQLITE_ROW {if let p=sqlite3_column_text(statement,1){columns.insert(String(cString:p))}}
  };sqlite3_finalize(statement);statement=nil
  if ["id","title","cwd","updated_at","archived"].allSatisfy(columns.contains) {
   let title=columns.contains("name") ? "coalesce(nullif(name,''),title)" : "title"
   let agent=columns.contains("agent_path") ? " and (agent_path is null or agent_path='')" : ""
   let sql="select id,\(title),cwd,updated_at,archived from threads where archived=0\(agent) order by updated_at desc limit 12"
   if sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK {
    while sqlite3_step(statement)==SQLITE_ROW {
     func string(_ n:Int32)->String {sqlite3_column_text(statement,n).map{String(cString:$0)} ?? ""}
     result.append(["id":string(0),"title":string(1),"cwd":string(2),"updated_at":sqlite3_column_int64(statement,3),"archived":sqlite3_column_int(statement,4)])
    }
   };sqlite3_finalize(statement)
  }
 }
}
let data=try JSONSerialization.data(withJSONObject:["sessions":result])
print(String(decoding:data,as:UTF8.self))

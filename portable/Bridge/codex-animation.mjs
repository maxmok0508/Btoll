export function codexAnimationState(summary={},now=Date.now()) {
 const active=Array.isArray(summary.active)?summary.active:[];
 const running=active.filter(x=>!x.waitingInput);
 const latest=[...(running.length?running:active)].sort((a,b)=>(b.last??0)-(a.last??0))[0];
 if(latest){
  if(!running.length&&latest.waitingInput)return {category:'blocked',label:'等待输入'};
  if(latest.phase==='工具执行中')return {category:'working',label:'执行中'};
  if(latest.phase==='响应中')return {category:'streaming',label:'响应中'};
  return {category:'rotation',label:'处理中'};
 }
 if(summary.unknown?.length)return {category:'idle',label:'待确认'};
 const recent=summary.recent;
 if(recent?.finished && now-recent.finished>=0 && now-recent.finished<15000){
  if(recent.outcome==='已完成')return {category:'done',label:'已完成'};
  if(recent.outcome==='已中止')return {category:'blocked',label:'已中止'};
 }
 return {category:'idle',label:'等待中'};
}

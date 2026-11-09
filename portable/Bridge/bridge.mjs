import {coreMetrics} from './thermal-metrics.mjs';
import {workAnimation,animationMode} from './work-animation.mjs';
import {codexAnimationState} from './codex-animation.mjs';
import fs from 'node:fs';
import {spawn,execFileSync} from 'node:child_process';
import path from 'node:path';
import os from 'node:os';
import {fileURLToPath} from 'node:url';
import {StringDecoder} from 'node:string_decoder';

const BUNDLE = 'local.codex.atoll-status';
const statusLabels=JSON.parse(fs.readFileSync(new URL('./assets/status-labels.json',import.meta.url),'utf8'));
// Optional per-user artwork survives runtime upgrades and is never bundled automatically.
function statusAsset(local, fallback) {
  const candidate=new URL('./assets/'+local,import.meta.url);
  return fs.readFileSync(fs.existsSync(candidate) ? candidate : new URL('./assets/'+fallback,import.meta.url)).toString('base64');
}
const brandPNG = statusAsset('local-status.png','brand-icon.png');
const brandMotion = statusAsset('local-status-active.json','brand-icon-active.json');

const ROOT = process.env.CODEX_HOME || path.join(os.homedir(), '.codex');
const states = new Map();
let quota = null;
let resetCards = null;
let backendAttempt = 0;
let temperatures = null;
let accountUsage = null;
function readTemperatures(){
 try { const values=JSON.parse(execFileSync(fileURLToPath(new URL("./temperature-reader",import.meta.url)),{encoding:"utf8",timeout:2000,maxBuffer:65536})); temperatures={values,observed:Date.now()}; } catch {temperatures=null;}
}

const color = {red:0.27, green:0.83, blue:0.69, alpha:1};
const font = {size:12, weight:'medium', design:'default', isMonospacedDigit:false};
const text = value => ({text:{_0:value, font}});

export function applyEvent(state, record, setQuota = () => {}) {
  const p = record.payload || {};
  const time = Date.parse(record.timestamp || '') || 0;
  if (record.type === 'session_meta') {
    state.id = p.id;
    state.project = path.basename(p.cwd || '') || 'Codex';
    state.child = Boolean(p.source && typeof p.source === 'object' && p.source.subagent);
  }
  if (record.type === 'response_item' && state.running) {
    if (p.type === 'function_call' || p.type === 'custom_tool_call') {
      state.tool=String(p.name || '工具').split('__').pop().split('.').pop().slice(0,36);state.waitingInput=['request_user_input','request_permissions'].includes(state.tool);state.inputCall=state.waitingInput?p.call_id:null;state.phase=state.waitingInput?'等待输入':'工具执行中';state.last=time;
    } else if(p.type==='message'&&p.role==='assistant'){state.phase='响应中';state.last=time;
    } else if (p.type === 'function_call_output' || p.type === 'custom_tool_call_output') {
      if(!state.inputCall||p.call_id===state.inputCall){state.waitingInput=false;state.inputCall=null;}state.phase='处理中'; state.last=time;
    }
  }
  if (record.type === 'event_msg') {
    if (p.type === 'task_started') {
      state.running = true; state.started = time; state.last = time; state.tools = 0; state.tool = ''; state.phase='处理中';state.waitingInput=false;state.inputCall=null;
    } else if (p.type === 'task_complete' || p.type === 'turn_aborted') {
      state.running = false;state.waitingInput=false;state.inputCall=null; state.last = time; state.finished = time; state.outcome=p.type==='turn_aborted'?'已中止':'已完成';
    } else if(['approval_required','waiting_for_input','request_user_input'].includes(p.type)){state.waitingInput=true;state.phase='等待输入';state.last=time;
    } else if(['agent_message','agent_message_delta'].includes(p.type)&&state.running){state.waitingInput=false;state.phase='响应中';state.last=time;
    } else if(p.type==='user_message'&&state.running){state.waitingInput=false;state.inputCall=null;state.phase='处理中';state.last=time;
    } else if (p.type === 'item_completed') {
      state.last = Math.max(state.last || 0, time);
      const item = p.item || {};
      const tool = item.tool || item.name;
      if (tool) { state.tool = String(tool).split('__').pop().slice(0,36); state.tools = (state.tools || 0) + 1; }
    }
    if (p.type === 'token_count' && p.rate_limits) {
      const limits = p.rate_limits;
      if (!limits.limit_id || limits.limit_id === 'codex') {
        // Never assume primary = five-hour or secondary = weekly.
        const week = [limits.primary, limits.secondary].find(w => w?.window_minutes === 10080);
        if (week && Number.isFinite(week.used_percent)) setQuota({used:Math.min(100,Math.max(0,week.used_percent)), reset:week.resets_at, observed:time});
      }
    }
  }
}

export function accountSummary(result, now=Date.now()) {
  const limits=result.rateLimitsByLimitId?.codex || result.rateLimits;
  const week=(!limits?.limitId || limits.limitId==='codex')?[limits?.primary,limits?.secondary].find(w=>w?.windowDurationMins===10080):null;
  const cards=result.rateLimitResetCredits;
  return {
    quota:week&&Number.isFinite(week.usedPercent)?{used:Math.min(100,Math.max(0,week.usedPercent)),reset:week.resetsAt,observed:now}:null,
    resetCards:Number.isInteger(cards?.availableCount)&&cards.availableCount>=0?{count:cards.availableCount,observed:now}:null
  };
}

export function findCodexCLI(){
 const appRoots=['/Applications',path.join(os.homedir(),'Applications')];
 const candidates=[process.env.CODEX_CLI_PATH];
 for(const base of appRoots)for(const app of ['Codex.app','ChatGPT.app'])for(const relative of ['Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex','Contents/Resources/codex'])candidates.push(path.join(base,app,relative));
 candidates.push(path.join(os.homedir(),'.local/bin/codex'),'/opt/homebrew/bin/codex','/usr/local/bin/codex');
 for(const candidate of candidates.filter(Boolean)){try{fs.accessSync(candidate,fs.constants.X_OK);if(fs.statSync(candidate).isFile())return candidate;}catch{}}
 throw new Error('Codex CLI 未找到，请在本机安装并登录 Codex');
}

export function readAccount() {
  return new Promise((resolve,reject)=>{
    const executable=findCodexCLI();
    const child=spawn(executable,['app-server','--stdio'],{stdio:['pipe','pipe','ignore']});
    let buffer='',done=false;let rateResult=null;let usageResult=null;let gotRate=false;let gotUsage=false;
    const finish=(error,value)=>{if(done)return;done=true;clearTimeout(timer);child.kill();error?reject(new Error('Codex 额度后台暂不可用')):resolve({...accountSummary(value),usage:usageResult});};
    const timer=setTimeout(()=>finish(true),15000);
    const send=value=>child.stdin.write(JSON.stringify(value)+'\n');
    child.on('error',()=>finish(true));child.stdin.on('error',()=>finish(true));child.on('exit',()=>{if(!done)finish(true)});
    child.stdout.on('data',data=>{
      buffer+=data;let end;
      while((end=buffer.indexOf('\n'))>=0){
        const line=buffer.slice(0,end);buffer=buffer.slice(end+1);let message;try{message=JSON.parse(line)}catch{continue}
        if(message.id===1){if(message.error){finish(true);return}send({method:'initialized'});send({id:2,method:'account/rateLimits/read'});send({id:3,method:'account/usage/read',params:{}});}
        if(message.id===2){gotRate=true;rateResult=message.result;if(message.error){finish(true);return}}
        if(message.id===3){gotUsage=true;if(!message.error)usageResult=message.result;}
        if(gotRate&&gotUsage){finish(false,rateResult);return}
      }
    });
    send({id:1,method:'initialize',params:{clientInfo:{name:'atoll_codex_monitor',title:'Btoll Codex Monitor',version:'1.1.0'},capabilities:{experimentalApi:true}}});
  });
}

export function resetCountdown(reset,now=Date.now()) {
  if(!Number.isFinite(reset))return '重置待同步';
  const hours=Math.ceil((reset*1000-now)/3600000);
  if(hours<=0)return '待刷新';
  return hours>=24?`${Math.floor(hours/24)}天${hours%24?hours%24+'时':''}后重置`:`${hours}时后重置`;
}

function discover(dir, files) {
  let items; try { items = fs.readdirSync(dir,{withFileTypes:true}); } catch { return; }
  for (const item of items) {
    const p = path.join(dir,item.name);
    if (item.isDirectory()) discover(p,files);
    else if (item.isFile() && item.name.endsWith('.jsonl')) {
      const st=fs.statSync(p);
      if (Date.now()-st.mtimeMs < 7*86400000) files.push({path:p,mtime:st.mtimeMs});
    }
  }
}

function refresh() {
  const files=[]; discover(path.join(ROOT,'sessions'),files);
  files.sort((a,b)=>b.mtime-a.mtime);
  for (const f of files.slice(0,64)) {
    let s=states.get(f.path);
    if (!s) { s={offset:0,buffer:'',decoder:new StringDecoder('utf8'),running:false,project:'Codex',tools:0}; states.set(f.path,s); }
    try {
      const size=fs.statSync(f.path).size;
      if (size < s.offset) { s.offset=0; s.buffer=''; s.decoder=new StringDecoder('utf8'); s.running=false; }
      if (size === s.offset) continue;
      // Incremental reading: a growing transcript is not reread every refresh.
      const fd=fs.openSync(f.path,'r');
      try {
        while(s.offset<size){
        const chunk=Buffer.alloc(Math.min(size-s.offset,4*1024*1024));
        const n=fs.readSync(fd,chunk,0,chunk.length,s.offset); s.offset+=n;
        if(!n)break;
        const lines=(s.buffer+s.decoder.write(chunk.subarray(0,n))).split('\n');
        s.buffer=lines.pop();
        for (const line of lines) {
          let r; try {r=JSON.parse(line);} catch {continue;}
          applyEvent(s,r,q=>{if (!quota || q.observed>=quota.observed) quota=q;});
        }
        }
      } finally {fs.closeSync(fd);}
    } catch { /* files may be rotated or removed while Codex writes */ }
  }
  for (const [f,s] of states) if (!files.some(x=>x.path===f) && !s.running) states.delete(f);
}

export function snapshot() {
  const now=Date.now();
  const all=[...states.values()].filter(s=>!s.child);
  const active=all.filter(s=>s.running && now-(s.last||s.started||0)<30*60000);
  const unknown=all.filter(s=>s.running && now-(s.last||s.started||0)>=30*60000);
  const recent=all.filter(s=>!s.running && s.finished).sort((a,b)=>b.finished-a.finished)[0];
  const available=quota && (!quota.reset || quota.reset*1000>now);
  const clean = ({decoder,buffer,...rest}) => rest;
  return {sessions:all.map(clean),active:active.map(clean),unknown:unknown.map(clean),recent:recent?clean(recent):undefined,quota:available?quota:null,resetCards:resetCards&&now-resetCards.observed<5*60000?resetCards:null};
}

function statusLabel(phase,remaining) {
  const data=statusLabels[`${phase}|${remaining??-1}`];
  const animation={v:'5.7.4',fr:30,ip:0,op:90,w:168,h:64,assets:[{id:'label',w:168,h:64,u:'',p:'data:image/png;base64,'+data,e:1}],layers:[{ddd:0,ind:1,ty:2,refId:'label',sr:1,ks:{o:{a:0,k:100},r:{a:0,k:0},p:{a:0,k:[0,0,0]},a:{a:0,k:[0,0,0]},s:{a:0,k:[100,100,100]}},ip:0,op:90,st:0,bm:0}]};
  return {animation:{data:Buffer.from(JSON.stringify(animation)).toString('base64'),size:[84,32]}};
}

export function quotaColor(remaining) {
  if(!Number.isFinite(remaining))return {red:.5,green:.5,blue:.5,alpha:1};
  const t=Math.max(0,Math.min(100,remaining))/100;
  return {red:t<.5?1:1-(t-.5)*1.68,green:t<.5?.22+t:.72+(t-.5)*.2,blue:t<.5?.25-t*.18:.16+(t-.5)*.42,alpha:1};
}

export function descriptors(s) {
  const q=s.quota;
  const remaining=q?Math.round(100-q.used):null;
  const qText=q?`周剩余 ${remaining}%`:'周额度待同步';
  const status=s.active.length?`${s.active.length} 个会话工作中`:s.unknown.length?'会话状态待确认':'当前无运行会话';
  const latest=[...s.active].sort((a,b)=>b.last-a.last)[0];
  const detail=latest?`${latest.project} · ${latest.phase||'处理中'}${latest.tool?' · '+latest.tool:''}`:s.recent?'最近一轮已完成':'等待 Codex 会话';
  const reset=q?.reset?new Date(q.reset*1000).toLocaleString('zh-CN',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'}):'待同步';
  const age=q?Math.floor((Date.now()-q.observed)/60000):null;
  const phase=codexAnimationState(s).label;
  const animationRoot=fileURLToPath(new URL('.',import.meta.url));
  const animate=s.active.length>0||animationMode(animationRoot)==='codex';
  const cards=s.resetCards?.count;
  const cardsText=Number.isInteger(cards)?String(cards):'—';
  const countdown=resetCountdown(q?.reset);
  const quotaDetail=q?`已用 ${Math.round(q.used)}% · 重置 ${reset}${age>5?` · ${age} 分钟前数据`:''}`:'开始一次 Codex 对话后自动同步';
  const escape=value=>String(value).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const blue={red:0.08,green:0.64,blue:1,alpha:1};
  const nativeText=(value,size=17)=>({text:{_0:value,font:{...font,size,weight:'medium'},color:{red:1,green:1,blue:1,alpha:1},alignment:'leading'}});
  const sections=[
    {id:'status-quota',layout:'stack',elements:[nativeText(`${status} · ${qText}`),{progress:{_0:{bar:{width:560,height:5,cornerRadius:2.5}},value:(remaining??0)/100,color:quotaColor(remaining)}}]},
    {id:'session-detail',title:'当前任务',layout:'stack',elements:[nativeText(detail,14)]},
    {id:'quota-detail',layout:'stack',elements:[nativeText(quotaDetail,13)]},
    {id:'reset-details',title:'额度重置',subtitle:q?`${reset} 重置`:undefined,layout:'columns',elements:[nativeText(`重置卡 ${cardsText} 张`,20),nativeText(countdown,17)]}
  ];
  return {
    activity:{id:'codex-status',bundleIdentifier:BUNDLE,priority:s.active.length?'high':'normal',title:'Codex',subtitle:status,
      leadingIcon:animate?{lottie:{animationData:workAnimation(animationRoot,Date.now(),s) ?? brandMotion,size:[26,26]}}:{image:{data:brandPNG,size:[19,19],cornerRadius:0}},
      trailingContent:statusLabel(phase,remaining),
      progress:0,accentColor:blue,allowsMusicCoexistence:!s.active.length,metadata:{source:'local-codex-events'},
      centerTextStyle:'standard',sneakPeekConfig:{enabled:false,showOnUpdate:false}},
    experience:{id:'codex-monitor',bundleIdentifier:BUNDLE,priority:'normal',accentColor:blue,metadata:{source:'local-codex-events'},
      tab:{title:'Codex',iconSymbolName:'chevron.left.forwardslash.chevron.right',badgeIcon:{appIcon:{bundleIdentifier:'com.openai.chat',size:[28,28],cornerRadius:7}},preferredHeight:360,sections,allowWebInteraction:false}}

  };
}

let sessionMetadata = {sessions:[]};
let metadataAttempt = 0;
function writeDashboard(){
 const now=Date.now();
 if(now-metadataAttempt>30000){
  metadataAttempt=now;
  try{sessionMetadata=JSON.parse(execFileSync(fileURLToPath(new URL('./metadata-reader',import.meta.url)),[],{encoding:'utf8',timeout:3000,maxBuffer:262144}));}catch{}
 }
 const snap=snapshot();
 const byID=new Map(snap.sessions.map(s=>[s.id,s]));
 const sessions=sessionMetadata.sessions.map(m=>{
  const live=byID.get(m.id);
  const status=live?.running?(now-(live.last||live.started||0)<30*60000?(live.phase||'处理中'):'状态待确认'):live?.finished?(live.outcome||'已完成'):'未运行';
  return {id:m.id,title:m.title||path.basename(m.cwd)||'Codex',project:path.basename(m.cwd)||'Codex',updated:Math.max(m.updated_at*1000,live?.last||0),status,tool:live?.running?live.tool||'':''};
 });
 let fanControl=null;try{fanControl=JSON.parse(fs.readFileSync(new URL("./fan-state.json",import.meta.url),"utf8"));}catch{}
 try{const reply=JSON.parse(execFileSync('/Library/PrivilegedHelperTools/local.bsstoll.fan-helper',['client','{"command":"status"}'],{encoding:'utf8',timeout:3500})); if(reply.ok)fanControl={...reply,updated:Date.now()};else if(!fanControl||fanControl.mode!=='error')fanControl={...reply,mode:'error'};}catch{if(!fanControl||fanControl.backend!=='bsstoll-smc')fanControl={mode:'error',unavailable:true,message:'风扇控制服务未就绪或本机接口暂不支持'};}
 const data={coreTemperatures:temperatures?coreMetrics(temperatures.values):null,fanControl,updated:now,quota:snap.quota,resetCards:snap.resetCards,activeCount:snap.active.length,uncertainCount:snap.unknown.length,sessions,temperatures,profile:accountUsage&&now-accountUsage.observed<600000?accountUsage:null,profileStatus:accountUsage?'Codex 账户活动':'个人资料数据暂不可用'};
 const target=fileURLToPath(new URL('./dashboard.json',import.meta.url));
 fs.writeFileSync(target+'.tmp',JSON.stringify(data),{mode:0o600});fs.renameSync(target+'.tmp',target);
}

class RPC {
  constructor() {this.next=0;this.pending=new Map();}
  async connect() {
    this.ws=new WebSocket('ws://127.0.0.1:9020');
    await new Promise((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('Atoll 连接超时')),5000);
      this.ws.addEventListener('open',()=>{clearTimeout(timer);resolve();},{once:true});
      this.ws.addEventListener('error',()=>{clearTimeout(timer);reject(new Error('Atoll 尚未启动'));},{once:true});
    });
    this.ws.addEventListener('message',e=>{
      let m;try{m=JSON.parse(e.data);}catch{return;}
      const p=this.pending.get(m.id);if(!p)return;
      clearTimeout(p.timer);this.pending.delete(m.id);m.error?p.reject(new Error(m.error.message)):p.resolve(m.result);
    });
    this.ws.addEventListener('close',()=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(new Error('Atoll 已断开'));}this.pending.clear();});
  }
  call(method,params={}) {
    return new Promise((resolve,reject)=>{
      const id=String(++this.next);const timer=setTimeout(()=>{this.pending.delete(id);reject(new Error('Atoll RPC 超时'));},5000);
      this.pending.set(id,{resolve,reject,timer});this.ws.send(JSON.stringify({jsonrpc:'2.0',id,method,params:{bundleIdentifier:BUNDLE,...params}}));
    });
  }
  close(){this.ws?.close();}
}

async function main() {
  if(process.argv.includes('--snapshot')){refresh();console.log(JSON.stringify(snapshot(),null,2));return;}
  let rpc;let presented=false;let previous='';let busy=false;let lastError='';
  async function tick(){
    if(busy)return;busy=true;
    try{
      refresh();
      readTemperatures();
      if(Date.now()-backendAttempt>=60000){
        backendAttempt=Date.now();
        try{const live=await readAccount();if(live.quota&&(!quota||live.quota.observed>quota.observed))quota=live.quota;resetCards=live.resetCards;if(live.usage)accountUsage={...live.usage,observed:Date.now()};}catch{}
      }
      writeDashboard();
      if(!rpc || rpc.ws.readyState!==WebSocket.OPEN){
        rpc?.close();rpc=new RPC();await rpc.connect();
        const auth=await rpc.call(process.argv.includes('--authorize')?'atoll.requestAuthorization':'atoll.checkAuthorization');
        if(!auth.authorized)throw new Error('请在 Atoll 扩展设置中授权 Codex 状态显示；不会自动恢复已撤销的权限');
        presented=false;previous='';
      }
      writeDashboard();
      const d=descriptors(snapshot());const sig=JSON.stringify(d);
      if(sig!==previous){
        await rpc.call(presented?'atoll.updateLiveActivity':'atoll.presentLiveActivity',{descriptor:d.activity});
        await rpc.call(presented?'atoll.updateNotchExperience':'atoll.presentNotchExperience',{descriptor:d.experience});
        presented=true;previous=sig;
        if(process.argv.includes('--once'))console.log('Atoll 已接收 Codex 刘海状态与额度页');
      }
      const values=temperatures?.values||{};
      const group=prefix=>Object.entries(values).filter(([k,v])=>k.startsWith(prefix)&&Number.isFinite(v)&&v>5&&v<125).map(([,v])=>v);
      const avg=a=>a.length?a.reduce((x,y)=>x+y,0)/a.length:null;
      const fmt=v=>v==null?'暂无读数':`${v.toFixed(1)} °C`;
      const cores=coreMetrics(values);
      const t=(value,size=18)=>({text:{_0:value,font:{...font,size,weight:'medium'},color:{red:1,green:1,blue:1,alpha:1},alignment:'leading'}});
      await rpc.call('atoll.presentNotchExperience',{descriptor:{id:'hardware-temperature',bundleIdentifier:BUNDLE,priority:'normal',accentColor:color,metadata:{source:'local-smc'},tab:{title:'温度',iconSymbolName:'thermometer.medium',preferredHeight:330,allowWebInteraction:false,sections:[
        {id:'chip',title:'CPU 核心温度 · 本机映射',layout:'stack',elements:[t(`CPU 平均 ${fmt(cores.cpuAverage)}    最高 ${fmt(cores.cpuMaximum)}    GPU ${fmt(cores.gpuAverage)}`,17)]}
      ]}}});
      lastError='';
    }catch(e){if(e.message!==lastError){console.error(e.message);lastError=e.message;}rpc?.close();rpc=null;}
    finally{busy=false;}
  }
  await tick();
  if(process.argv.includes('--once')){rpc?.close();process.exit(presented?0:1);}
  const timer=setInterval(tick,5000);
  for(const signal of ['SIGTERM','SIGINT'])process.on(signal,async()=>{
    clearInterval(timer);
    if(rpc?.ws.readyState===WebSocket.OPEN){
      await Promise.allSettled([rpc.call('atoll.dismissLiveActivity',{activityID:'codex-status'}),rpc.call('atoll.dismissNotchExperience',{experienceID:'codex-monitor'})]);
    }
    rpc?.close();process.exit(0);
  });
}
if(process.argv[1] && fileURLToPath(import.meta.url)===path.resolve(process.argv[1]))await main();

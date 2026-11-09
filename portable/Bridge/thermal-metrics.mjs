import fs from 'node:fs';
import {execFileSync} from 'node:child_process';
const mappings=JSON.parse(fs.readFileSync(new URL('./sensor-mappings.json',import.meta.url)));
let detected='';try{detected=execFileSync('/usr/sbin/sysctl',['-n','machdep.cpu.brand_string'],{encoding:'utf8'}).match(/Apple (M[1-6])(?:\s|$)/i)?.[1]?.toLowerCase()||'';}catch{}
export function coreMetrics(values={},generation=detected){
 const mapping=mappings[generation]||[];
 const sensors=mapping.flatMap(s=>Number.isFinite(values[s.key])&&values[s.key]>0&&values[s.key]<130?[{...s,value:values[s.key]}]:[]);
 const cpu=sensors.filter(s=>s.group==='CPU');const gpu=sensors.filter(s=>s.group==='GPU');
 const avg=a=>a.length?a.reduce((n,s)=>n+s.value,0)/a.length:null;
 return {cpuAverage:avg(cpu),cpuMaximum:cpu.length?Math.max(...cpu.map(s=>s.value)):null,gpuAverage:avg(gpu),sensors,source:mapping.length?'Stats '+generation.toUpperCase()+' sensor mapping':'CPU sensor mapping unavailable'};
}

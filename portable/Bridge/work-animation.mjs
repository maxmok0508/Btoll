import {codexAnimationState} from './codex-animation.mjs';
import fs from 'node:fs';
import path from 'node:path';
function json(file,fallback){try{return JSON.parse(fs.readFileSync(file,'utf8'));}catch{return fallback;}}
function safeFile(root,relative){
 if(typeof relative!=='string'||path.isAbsolute(relative)||relative.split(/[\\/]/).includes('..'))return null;
 const file=path.join(root,relative);
 try{if(fs.statSync(file).size>16*1024*1024)return null;return file;}catch{return null;}
}
export function animationMode(root){const value=json(path.join(root,'animation-preferences.json'),{});return value?.selected ?? 'codex';}
export function workAnimation(root,now=Date.now(),summary={}){
 const raw=json(path.join(root,'animation-preferences.json'),{});
 const settings=raw&&typeof raw==='object'?raw:{};
 const array=file=>{const v=json(file,[]);return Array.isArray(v)?v:[];};
 const builtin=array(path.join(root,'assets/animations/catalog.json'));
 const custom=array(path.join(root,'user-animations/catalog.json'));
 const ids=new Set();
 const entries=[...builtin,...custom].filter(x=>{if(!x||typeof x.id!=='string'||ids.has(x.id)||!safeFile(root,x.file))return false;ids.add(x.id);return true;});
 let id=settings.selected ?? 'codex';
 if(id==='codex'){
  const state=codexAnimationState(summary,now);
  const file=safeFile(root,'assets/animations/state-'+state.category+'.json');
  if(file)return fs.readFileSync(file).toString('base64');
 }
 if(id==='shuffle'&&entries.length)id=entries[Math.floor(now/20000)%entries.length].id;
 const selected=entries.find(x=>x.id===id);
 let file=selected ? safeFile(root,selected.file):null;
 if(!file&&id!=='project')file=safeFile(root,'assets/local-status-active.json');
 file??=safeFile(root,'assets/brand-icon-active.json');
 try{return file ? fs.readFileSync(file).toString('base64'):null;}catch{return null;}
}

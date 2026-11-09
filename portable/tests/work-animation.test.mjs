import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import os from 'node:os';import path from 'node:path';
import {workAnimation} from '../Bridge/work-animation.mjs';
test('animation selection updates without restarting, with safe fallbacks and shuffle',()=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'btoll-animations-'));
 try{
  const write=(name,value)=>{const file=path.join(root,name);fs.mkdirSync(path.dirname(file),{recursive:true});fs.writeFileSync(file,value);};
  const decode=()=>Buffer.from(workAnimation(root,0),'base64').toString();
  write('assets/brand-icon-active.json','project');assert.equal(decode(),'project');
  write('assets/local-status-active.json','original');write('animation-preferences.json','{"selected":"original"}');assert.equal(decode(),'original');
  write('assets/animations/one.json','one');write('assets/animations/two.json','two');
  write('assets/animations/catalog.json',JSON.stringify([{id:'one',file:'assets/animations/one.json'},{id:'two',file:'assets/animations/two.json'},{id:'bad',file:'../outside.json'}]));
  write('animation-preferences.json','{"selected":"one"}');assert.equal(decode(),'one');
  write('animation-preferences.json','{"selected":"two"}');assert.equal(decode(),'two');
  write('animation-preferences.json','{"selected":"project"}');assert.equal(decode(),'project');
  write('animation-preferences.json','{"selected":"shuffle"}');assert.equal(decode(),'one');assert.equal(Buffer.from(workAnimation(root,20000),'base64').toString(),'two');
  write('animation-preferences.json','{"selected":"bad"}');assert.equal(decode(),'original');
  write('animation-preferences.json','null');write('user-animations/catalog.json','{}');assert.equal(decode(),'original');
 }finally{fs.rmSync(root,{recursive:true,force:true});}
});

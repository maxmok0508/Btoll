import test from 'node:test';import assert from 'node:assert/strict';
import {applyEvent,descriptors} from '../Bridge/bridge.mjs';import {codexAnimationState} from '../Bridge/codex-animation.mjs';
test('actual lifecycle follows processing, tool work, input block, response and completion',()=>{
 const state={};let now=1000000;
 const event=(type,payload)=>applyEvent(state,{type,payload,timestamp:new Date(now+=1000).toISOString()});
 const summary=()=>({active:state.running?[state]:[],unknown:[],recent:state.running?null:state});
 event('event_msg',{type:'task_started'});assert.equal(codexAnimationState(summary(),now).category,'rotation');
 event('response_item',{type:'function_call',name:'functions.exec',call_id:'tool'});assert.equal(codexAnimationState(summary(),now).category,'working');
 event('response_item',{type:'function_call',name:'functions.request_user_input',call_id:'input'});assert.equal(codexAnimationState(summary(),now).category,'blocked');
 event('response_item',{type:'function_call_output',call_id:'input'});assert.equal(codexAnimationState(summary(),now).category,'rotation');
 event('response_item',{type:'message',role:'assistant'});assert.equal(codexAnimationState(summary(),now).category,'streaming');
 event('event_msg',{type:'task_complete'});assert.equal(codexAnimationState(summary(),now).category,'done');assert.equal(codexAnimationState(summary(),now+16000).category,'idle');
});
test('async optional questions and stale sessions do not falsely imply a blocked task or completion',()=>{
 const state={running:true};applyEvent(state,{type:'response_item',timestamp:new Date().toISOString(),payload:{type:'function_call',name:'functions.request_user_input_async'}});
 assert.equal(codexAnimationState({active:[state]}).category,'working');
 assert.equal(codexAnimationState({unknown:[state]}).label,'待确认');
 assert.equal(codexAnimationState({recent:{finished:Date.now(),outcome:'已中止'}}).label,'已中止');
});

test('every Codex phase has valid bundled artwork at every weekly quota value',async()=>{
 const {readFile}=await import('node:fs/promises');
 for(const name of ['status-labels.json','status-labels-en.json']){
  const labels=JSON.parse(await readFile(new URL('../Bridge/assets/'+name,import.meta.url),'utf8'));
  for(const phase of ['处理中','执行中','响应中','等待输入','待确认','已完成','已中止','等待中'])for(let quota=-1;quota<=100;quota++){
   const data=labels[`${phase}|${quota}`];assert.ok(data,`${name}: ${phase}|${quota}`);
   assert.equal(Buffer.from(data,'base64').subarray(0,8).toString('hex'),'89504e470d0a1a0a');
  }
 }
});

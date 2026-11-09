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

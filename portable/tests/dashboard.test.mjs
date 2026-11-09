import test from 'node:test';
import assert from 'node:assert/strict';
import {accountSummary,applyEvent,resetCountdown} from '../Bridge/bridge.mjs';
test('weekly primary window and real reset cards',()=>{
 const s=accountSummary({rateLimits:{primary:{windowDurationMins:10080,usedPercent:74,resetsAt:1794551214}},rateLimitResetCredits:{availableCount:1}},1000);
 assert.equal(s.quota.used,74);assert.equal(s.resetCards.count,1);
});
test('missing quota and cards remain unknown',()=>{
 const s=accountSummary({rateLimits:{primary:{windowDurationMins:300,usedPercent:10}}});
 assert.equal(s.quota,null);assert.equal(s.resetCards,null);
});
test('task tool lifecycle and abort',()=>{
 const s={};const event=(type,payload,time)=>applyEvent(s,{type,payload,timestamp:time});
 event('event_msg',{type:'task_started'},'2026-11-08T00:00:00Z');assert.equal(s.running,true);
 event('response_item',{type:'function_call',name:'functions.exec'},'2026-11-08T00:00:01Z');assert.equal(s.phase,'工具执行中');
 event('response_item',{type:'function_call_output'},'2026-11-08T00:00:02Z');assert.equal(s.phase,'处理中');
 event('event_msg',{type:'turn_aborted'},'2026-11-08T00:00:03Z');assert.equal(s.running,false);assert.ok(s.finished);
});
test('reset countdown handles expired and unknown reset',()=>{assert.equal(resetCountdown(null),'重置待同步');assert.equal(resetCountdown(1,2000),'待刷新');});

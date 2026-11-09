import test from 'node:test';import assert from 'node:assert/strict';
import {coreMetrics} from '../Bridge/thermal-metrics.mjs';
test('uses mapped CPU keys rather than all Tp or battery sensors',()=>{
 const m=coreMetrics({Tp0j:90,Tp0g:80,Te07:50,TpZZ:125,TB0T:35,TW0P:60,Tg1e:70},"m6");
 assert.equal(m.cpuAverage,220/3);assert.equal(m.cpuMaximum,90);assert.equal(m.gpuAverage,70);assert.equal(m.sensors.length,4);
});
test('missing and invalid readings stay unavailable',()=>{const m=coreMetrics({Tp0j:0,Tp0g:NaN,Te07:200},"m6");assert.equal(m.cpuAverage,null);assert.equal(m.cpuMaximum,null);assert.equal(m.gpuAverage,null);});

test('unknown generation never borrows another chip mapping',()=>{const m=coreMetrics({Tp0j:91,TB0T:38},"unknown");assert.equal(m.cpuAverage,null);assert.equal(m.cpuMaximum,null);});

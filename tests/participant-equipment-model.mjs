// Independent transport-state and actual worklet aggregation expectations.
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import vm from 'node:vm';
const sandbox={window:{},performance:{now:()=>5000}};
vm.runInNewContext(await fs.readFile('www/participant/equipment.js','utf8'),sandbox);
const {cameraCheck}=sandbox.window.BrohnEquipment,requirements={freshness_ms:2000,audio:false};
const snapshot={video:{live:true,enabled:true,muted:false,frames:2,last_frame_ms:3000},audio:{},recording:{browser_bytes:0,browser_sequence:0,acked_bytes:0,acked_sequence:0}};
let checks=0;const check=(condition,name)=>{assert.ok(condition,name);console.log(`PASS ${name}`);checks++;};
check(cameraCheck(snapshot,requirements).video,'Exact engineering freshness boundary is current');
check(!cameraCheck(snapshot,requirements,5000.001).video,'Observation beyond freshness boundary is unknown');
check(!cameraCheck({...snapshot,video:{...snapshot.video,muted:true}},requirements).video,'Live but muted track cannot pass frame support');
check(!cameraCheck({...snapshot,video:{...snapshot.video,last_frame_ms:5001}},requirements).video,'Future frame clock cannot pass');
check(!cameraCheck(snapshot,requirements).browser&&!cameraCheck(snapshot,requirements).receiver,'Arriving frames do not imply browser or server writes');
check(cameraCheck({...snapshot,recording:{browser_bytes:100,browser_sequence:1,acked_bytes:0,acked_sequence:0}},requirements).browser,'Committed local bytes remain distinct from server receipt');
check(cameraCheck(snapshot,requirements).quality==='unknown','Transport success never supplies scientific quality');
const messages=[];let Processor;
const audio={sampleRate:1280,currentTime:0,AudioWorkletProcessor:class{constructor(){this.port={postMessage:value=>messages.push(value)};}},registerProcessor:(name,value)=>{assert.equal(name,'brohn-input-meter');Processor=value;}};
vm.runInNewContext(await fs.readFile('www/participant/audio-worklet.js','utf8'),audio);
const p=new Processor(),out=new Float32Array(128).fill(1),wave=Float32Array.from({length:128},(_,i)=>i%2?-.5:.5);
p.process([[wave]],[[out]]);
check(messages.length===1&&messages[0].rms===.5&&messages[0].peak===.5&&messages[0].samples===128,'Independent alternating waveform RMS, peak and complete sample count');
check(out.every(x=>x===0),'Worklet output remains silent');
p.process([[new Float32Array(128)]],[[out]]);
check(messages[1].rms===0&&messages[1].peak===0&&messages[1].blocks===2,'Actual silent input remains observed zero level');
p.process([[]],[[out]]);
check(messages.length===2,'Absent input channels cannot increment receiving support');
const bad=wave.slice();bad[4]=NaN;p.process([[bad]],[[out]]);
check(messages[2].rms===null&&messages[2].peak===null,'Nonfinite input support stays unavailable');
audio.sampleRate=48000;
for(const level of [.3,-.3,.7,-.7]){
  const constant=new Float32Array(128).fill(level),meter=new Processor(),before=messages.length;
  for(let block=0;block<38;block++)meter.process([[constant]],[[out]]);
  const observed=messages.at(-1),amplitude=Math.abs(constant[0]);
  check(messages.length===before+1&&observed.rms===amplitude&&observed.peak===amplitude&&observed.blocks===38&&observed.samples===4864,
    `Constant Float32 ${level} has its exact independent amplitude as RMS and peak across 38 blocks`);
}
const s={...snapshot,audio:{live:true,enabled:true,muted:false,state:'running',blocks:2,samples:256,channels:1,rms:0,peak:0,last_block_ms:5000}};
check(cameraCheck(s,{...requirements,audio:true}).audio,'Zero-amplitude microphone buffers count as observed, without a speech-quality claim');
check(!cameraCheck({...s,audio:{...s.audio,state:'suspended'}},{...requirements,audio:true}).audio,'Suspended audio context cannot pass current support');
console.log(JSON.stringify({checks,origin:'original_deterministic_software_observations'}));

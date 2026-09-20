/* Untimed equipment observations. No task stimuli, scores or physical-device claims. */
(() => {
  "use strict";
  const node=(tag,text,attrs={})=>{const e=document.createElement(tag);if(text!==null)e.textContent=text;for(const [k,v]of Object.entries(attrs))e.setAttribute(k,String(v));return e;};
  const fresh=(last,now,limit)=>Number.isFinite(last)&&last<=now&&now-last<=limit;
  const keyLabel=code=>({Space:"Space",ArrowUp:"Up arrow",ArrowDown:"Down arrow",ArrowLeft:"Left arrow",ArrowRight:"Right arrow"}[code]||(/^Key[A-Z]$/.test(code)?code.slice(3):/^Digit[0-9]$/.test(code)?code.slice(5):code));
  const cameraCheck=(snapshot,requirements,now=performance.now())=>{
    const v=snapshot.video,a=snapshot.audio,w=snapshot.recording;
    const video=v.live&&v.enabled&&!v.muted&&v.frames>=2&&fresh(v.last_frame_ms,now,requirements.freshness_ms);
    const audio=!requirements.audio||(a.live&&a.enabled&&!a.muted&&a.state==="running"&&a.blocks>0&&a.samples>0&&a.channels>0&&Number.isFinite(a.rms)&&Number.isFinite(a.peak)&&fresh(a.last_block_ms,now,requirements.freshness_ms));
    return {video,audio,browser:w.browser_bytes>0&&w.browser_sequence>0,receiver:w.acked_bytes>0&&w.acked_sequence>0,quality:"unknown"};
  };
  function panel(parent,controller,requirements) {
    const box=node("section",null,{class:"equipment-panel","aria-label":"Camera and microphone observations"});
    box.append(node("h2","Equipment observations"));const rows=node("div",null),note=node("p","Image, speech and gaze quality are unknown. This browser camera is not an eye tracker.",{class:"hint"});box.append(rows,note);parent.append(box);
    let lastState="";const live=node("p",null,{role:"status","aria-live":"polite"});box.append(live);
    const update=()=>{
      const s=controller.snapshot(),c=cameraCheck(s,requirements),age=s.video.last_frame_ms===null?"not observed":`${Math.max(0,performance.now()-s.video.last_frame_ms).toFixed(0)} ms ago`;
      const video=s.video.live?(s.video.muted?"muted":s.video.enabled?"connected":"disabled"):"not connected";
      rows.replaceChildren(node("p",`Camera: ${video}. ${s.video.frames} preview frame callbacks; latest ${age}. ${c.video?"Current frames observed.":"Current frame support unavailable."}`),
        node("p",`Recorder: ${controller.recorder?.state||"not started"}. Recording totals: ${s.recording.browser_bytes} bytes committed in this browser; ${s.recording.acked_bytes} bytes already received by the study service; ${s.recording.browser_bytes-s.recording.acked_bytes} committed bytes still waiting for receipt.`));
      if(requirements.audio)rows.append(node("p",`Microphone: ${s.audio.live&&!s.audio.muted?"connected":"unavailable or muted"}. ${s.audio.blocks} input blocks; ${s.audio.samples} channel samples. ${c.audio?"Current audio buffers observed.":"Current input support unavailable."}`),
        node("p",`Observed level: ${s.audio.rms===null?"unknown":s.audio.rms.toFixed(4)} RMS; ${s.audio.peak===null?"unknown":s.audio.peak.toFixed(4)} peak (normalized full scale). Speech quality unknown.`));
      const state=`${c.video?"Camera frames observed":"Camera frame check pending"}${requirements.audio?`; ${c.audio?"audio buffers observed":"microphone check pending"}`:""}; ${c.receiver?"recording bytes received":c.browser?"recording bytes saved locally":"recording bytes not yet saved"}.`;
      if(state!==lastState){lastState=state;live.textContent=state;}
    };
    update();const timer=setInterval(update,500);return ()=>clearInterval(timer);
  }
  async function inputs({container,requirements,emit,signal}) {
    const checkAbort=()=>{if(signal?.aborted)throw new DOMException("Equipment setup stopped.","AbortError");};checkAbort();
    if(requirements.required_codes.length){
      const needed=new Set(requirements.required_codes),observed=new Set(),down=new Set();let last=0;
      container.replaceChildren(node("h1","Check your task keys"),node("p","Press and release each required key. This is untimed practice; it is not a trial or a timing calibration."));
      const status=node("p",null,{role:"status"});container.append(status);const paint=()=>{status.textContent=`Keys still to check: ${[...needed].filter(k=>!observed.has(k)).map(keyLabel).join(", ")||"none"}.`;};paint();
      await new Promise((resolve,reject)=>{
        const cleanup=()=>{document.removeEventListener("keydown",press,true);document.removeEventListener("keyup",release,true);window.removeEventListener("blur",reset);document.removeEventListener("visibilitychange",reset);signal?.removeEventListener("abort",abort);};
        const abort=()=>{cleanup();reject(new DOMException("Equipment setup stopped.","AbortError"));};
        const reset=()=>{down.clear();observed.clear();paint();};
        const press=e=>{if(!needed.has(e.code)||e.ctrlKey||e.metaKey||e.altKey||!e.isTrusted||e.repeat)return;e.preventDefault();if(document.hasFocus()&&!document.hidden)down.add(e.code);};
        const release=e=>{if(!needed.has(e.code)||!e.isTrusted||e.ctrlKey||e.metaKey||e.altKey)return;e.preventDefault();if(down.delete(e.code)&&document.hasFocus()&&!document.hidden){observed.add(e.code);last=performance.now();paint();if(observed.size===needed.size&&!down.size){cleanup();resolve();}}};
        document.addEventListener("keydown",press,true);document.addEventListener("keyup",release,true);window.addEventListener("blur",reset);document.addEventListener("visibilitychange",reset);signal?.addEventListener("abort",abort,{once:true});
      });
      checkAbort();await emit("keyboard",{codes:[...observed].sort(),released:true,focused:document.hasFocus(),visible:!document.hidden,last_input_ms:last});
    }
    if(requirements.controls){
      container.replaceChildren(node("h1","Try the response control"),node("p","Activate this practice button using the input method you will use for this study. No answer is scored."));
      const activate=node("button","Activate practice control",{type:"button"});container.append(activate);
      const evidence=await new Promise((resolve,reject)=>{
        let pointer=null;const abort=()=>reject(new DOMException("Equipment setup stopped.","AbortError"));signal?.addEventListener("abort",abort,{once:true});
        activate.addEventListener("pointerup",e=>{if(e.isTrusted)pointer={type:e.pointerType,time:performance.now()};});
        activate.addEventListener("click",e=>{if(!e.isTrusted)return;activate.disabled=true;signal?.removeEventListener("abort",abort);resolve({activation:e.detail&&pointer&&performance.now()-pointer.time<1000&&["mouse","pen","touch"].includes(pointer.type)?pointer.type:"keyboard_or_assistive",trusted:true,last_input_ms:performance.now()});});
        activate.focus();
      });checkAbort();await emit("controls",evidence);
    }
  }
  async function firstWrite({controller,requirements,signal}) {
    const end=performance.now()+requirements.first_write_wait_ms;
    while(performance.now()<end){
      if(signal?.aborted)throw new DOMException("Equipment setup stopped.","AbortError");
      if(controller.damaged||!controller.stream)throw new Error("The recording stopped during its equipment check.");
      const snapshot=controller.snapshot(),check=cameraCheck(snapshot,requirements);
      if(check.video&&check.audio&&check.browser&&check.receiver)return snapshot;
      // flush deduplicates concurrent uploads and preserves the original queued request.
      void controller.flush().catch(()=>{});await new Promise(resolve=>setTimeout(resolve,100));
    }
    throw new Error("The 15-second recording check is still waiting for current frames, requested audio or saved-byte receipts. Retry the check or stop; previously saved bytes remain retained.");
  }
  window.BrohnEquipment=Object.freeze({cameraCheck,panel,inputs,firstWrite});
})();

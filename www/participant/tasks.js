/* Original Brohn task presentation. The caller owns consent, frozen protocols,
 * durable journal, service delivery and scientific scoring. No network is owned here. */
(() => {
  "use strict";
  const supported = new Set(["iat-gnb2003-d1/1.0", "biat-nosek2014-goodfocal/1.0", "aat-keyboard-cue-balanced/1.0", "rt-deary-liewald-simple/1.0", "rt-deary-liewald-choice/1.0"]);
  const node = (name, text = null, attributes = {}) => {
    const value = document.createElement(name);
    if (text !== null) value.textContent = text;
    Object.entries(attributes).forEach(([key, item]) => value.setAttribute(key, String(item)));
    return value;
  };
  function styles() {
    if (document.getElementById("brohn-task-styles")) return;
    const sheet = node("style", `
      .brohn-task{font-family:Arial,Helvetica,sans-serif;color:inherit;background:inherit;min-height:60vh}
      .brohn-task *{box-sizing:border-box}.brohn-task h1{font-size:1.8rem;line-height:1.3;margin:0 0 24px}
      .brohn-task p{white-space:pre-wrap;max-width:72ch}.brohn-task button{font:inherit;min-height:48px;padding:12px 20px;border:1px solid currentColor;background:inherit;color:inherit;border-radius:8px;cursor:pointer}
      .brohn-task button:focus-visible{outline:3px double currentColor;outline-offset:4px}
      .brohn-task .task-keyboard-map{display:flex;justify-content:space-between;gap:24px;min-height:84px;font-size:1.12rem;line-height:1.4}
      .brohn-task .task-keyboard-map>div{max-width:46%;white-space:pre-wrap}.brohn-task .task-keyboard-map>div:last-child{text-align:right}
      .brohn-task .task-stage{display:flex;align-items:center;justify-content:center;min-height:320px;height:44vh;gap:20px}
      .brohn-task .task-material{font-size:1.9rem;line-height:1.3;text-align:center;white-space:pre-wrap;max-width:620px;max-height:320px;display:flex;align-items:center;justify-content:center}
      .brohn-task .task-material img{display:block;max-width:100%;max-height:300px;object-fit:contain}
      .brohn-task .task-cue{display:flex;align-items:center;justify-content:center;border:4px solid currentColor;flex-shrink:0}
      .brohn-task .task-cue.landscape{width:300px;height:220px}.brohn-task .task-cue.portrait{width:220px;height:300px}
      .brohn-task .task-cue .task-material{max-width:180px;max-height:180px;font-size:1.3rem}.brohn-task .task-cue img{max-width:180px;max-height:180px}
      .brohn-task .task-boxes{display:flex;gap:20px;justify-content:center;width:100%}.brohn-task .task-box{width:90px;height:90px;display:flex;align-items:center;justify-content:center;border:2px solid currentColor;font-size:2.2rem;flex-shrink:0}
      .brohn-task .task-feedback{min-height:70px;text-align:center;font-size:1rem}.brohn-task .task-feedback strong{display:block;font-size:1.8rem}
      .brohn-task .task-help{text-align:center;font-size:.82rem}.brohn-task .task-status{font-size:.85rem}
      @media(max-width:560px){.brohn-task .task-stage{gap:10px}.brohn-task .task-boxes{gap:10px}.brohn-task .task-box{width:62px;height:62px}.brohn-task .task-keyboard-map{font-size:.95rem}.brohn-task .task-cue.landscape{width:260px}}
    `, {id: "brohn-task-styles"});
    document.head.append(sheet);
  }
  function unique() {
    return crypto.randomUUID ? crypto.randomUUID() : Array.from(crypto.getRandomValues(new Uint8Array(16)), x => x.toString(16).padStart(2,"0")).join("");
  }
  async function preload(compiled) {
    const images = new Map();
    const uniqueMaterials = new Map(compiled.timeline.filter(step => step.type === "task_trial" && step.material?.type === "image").map(step => [step.material.id, step.material]));
    let total = 0;
    for (const material of uniqueMaterials.values()) {
      total += material.asset?.size || 0;
      if (total > 256*1024*1024) throw new Error("Task images exceed the supported preload size.");
      const url = new URL(material.asset?.url || "", location.href);
      if (!material.asset?.url || url.origin !== location.origin || !url.pathname.startsWith("/api/assets/")) throw new Error("A task image has no supported immutable asset address.");
      const image = new Image(); image.alt = material.content || "Task image";
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error("A task image did not load before the task.")), 30000);
        image.onload = () => { clearTimeout(timeout); resolve(); };
        image.onerror = () => { clearTimeout(timeout); reject(new Error("A task image could not be opened.")); };
        image.src = url.href;
      });
      if (image.decode) await image.decode();
      images.set(material.id, image);
    }
    return images;
  }
  async function run({container, compiled, emit, onCheckpoint = async () => {}, signal, startStepId = null, clockInstanceId = null}) {
    if (!(container instanceof HTMLElement) || !compiled || compiled.schema_version !== "brohn-compiled-task/1.0" || !supported.has(compiled.profile) || !Array.isArray(compiled.timeline) || typeof emit !== "function") {
      throw new Error("Task renderer needs a supported frozen task, a container and a durable event callback.");
    }
    const startIndex = startStepId ? compiled.timeline.findIndex(step => step.id === startStepId && step.type === "task_instructions") : 0;
    if (startIndex < 0) throw new Error("Tasks can resume only at a service-verified instruction/block boundary.");
    styles();
    const images = await preload(compiled);
    const root = node("div", null, {class: "brohn-task"}); container.replaceChildren(root);
    if (clockInstanceId !== null && (typeof clockInstanceId !== "string" || !clockInstanceId || clockInstanceId.length > 128)) throw new Error("The caller's browser clock identity is invalid.");
    const clockId = clockInstanceId || unique(), responses = [], held = new Set();
    let interrupted = false, interruptionReason = null, current = null, cancelCurrent = null;
    let chain = Promise.resolve(), lastCompleted = null, previousResponseTime = null;
    const clock = value => ({id: "browser-monotonic", unit: "ms", value: value.toFixed(6), instance_id: clockId, time_origin_ms: performance.timeOrigin.toFixed(3)});
    const commit = (type, payload) => {
      const frozen = structuredClone(payload);
      chain = chain.then(() => emit(type, frozen));
      chain.catch(() => interrupt("journal_write_failed"));
      return chain;
    };
    const interrupt = reason => {
      if (interrupted) return;
      interrupted = true; interruptionReason = reason;
      cancelCurrent?.();
    };
    const onVisibility = () => { if (current?.type === "task_trial" && document.hidden) interrupt("visibility_lost_during_trial"); };
    const onBlur = () => { if (current?.type === "task_trial") interrupt("window_focus_lost_during_trial"); };
    const onResize = () => { if (current?.type === "task_trial") interrupt("viewport_changed_during_trial"); };
    const onDown = event => {
      if (event.code === "Escape") { event.preventDefault(); interrupt("participant_stopped"); }
      if (!event.repeat) held.add(event.code);
    };
    const onUp = event => held.delete(event.code);
    const onAbort = () => interrupt("caller_aborted");
    document.addEventListener("visibilitychange", onVisibility);
    window.addEventListener("blur", onBlur); window.addEventListener("resize", onResize);
    document.addEventListener("keydown", onDown); document.addEventListener("keyup", onUp);
    signal?.addEventListener("abort", onAbort, {once: true});
    if (signal?.aborted) interrupt("caller_aborted");
    const waitFrames = milliseconds => new Promise(resolve => {
      const start = performance.now(); let frame;
      const tick = time => { if (interrupted || time-start >= milliseconds) { cancelCurrent=null; resolve(); } else frame=requestAnimationFrame(tick); };
      cancelCurrent = () => { cancelAnimationFrame(frame); resolve(); };
      frame=requestAnimationFrame(tick);
    });
    const instruction = async step => {
      root.replaceChildren(node("h1", compiled.title), node("p", step.text),
        node("p", "Use a physical keyboard and keep this window in focus. Press Escape to stop. A timed trial cannot be replayed after an interruption.", {class: "task-status"}));
      const heading=root.querySelector("h1"); heading.tabIndex=-1; heading.focus();
      await commit("task_instructions", {task_id: compiled.id, step_id: step.id, block_id: step.block_id, clock: clock(performance.now())});
      await onCheckpoint({task_id: compiled.id, step_id: step.id, resumable: true, phase: "instructions", last_completed_trial_id: lastCompleted});
      await new Promise(resolve => {
        const next=node("button", "Begin this block", {type: "button"});root.append(next);
        cancelCurrent=resolve;
        next.addEventListener("click", () => {next.disabled=true;cancelCurrent=null;resolve();}, {once:true});
      });
    };
    const trial = async step => {
      const allowed=new Set(step.allowed_codes);
      if (!allowed.has(step.correct_code) || !Number.isFinite(step.timeout_ms) || step.timeout_ms < 1 || !Number.isFinite(step.foreperiod_ms)) throw new Error("Frozen trial response/timing fields are invalid.");
      await onCheckpoint({task_id: compiled.id, step_id: step.id, resumable: false, phase: "timed", last_completed_trial_id: lastCompleted});
      if (document.hidden || !document.hasFocus()) {interrupt("trial_started_without_focus");return null;}
      const map=node("div",null,{class:"task-keyboard-map"});
      if (step.mode === "iat" || step.mode === "biat") map.append(node("div",`E\n${step.left_label}`),node("div",`I\n${step.right_label}`));
      else if (step.mode === "aat") map.append(node("div","Up: avoid"),node("div","Down: approach"));
      const stage=node("div",null,{class:"task-stage"}),feedback=node("div",null,{class:"task-feedback","aria-live":"polite"});
      const help=node("p","Press Escape to stop",{class:"task-help"});root.replaceChildren(map,stage,feedback,help);
      const boxes=step.box_count>0 ? node("div",null,{class:"task-boxes"}):null;
      if(boxes){for(let i=0;i<step.box_count;i++)boxes.append(node("div","",{class:"task-box","aria-label":`Position ${i+1}`}));stage.append(boxes);}
      const material=node("div",null,{class:"task-material"});
      if(step.material?.type==="image")material.append(images.get(step.material.id).cloneNode(true));
      else if(step.material)material.textContent=step.material.content;
      const cue=step.mode==="aat"?node("div",null,{class:`task-cue ${step.cue}`}):null;
      if(cue)cue.append(material);
      let frame=null,onset=null,foreperiodStart=null,first=null,final=null,outcome=null;
      let maxFrameGap=0,lastFrame=null,frameCount=0,resolveResponse;
      const keypresses=[],beforeOnset=new Set(held);
      const responsePromise=new Promise(resolve=>{resolveResponse=resolve;});
      const complete=value=>{if(outcome)return;outcome=value;cancelAnimationFrame(frame);document.removeEventListener("keydown",handleKey,true);cancelCurrent=null;resolveResponse();};
      const handleKey=event=>{
        if(!allowed.has(event.code)||event.ctrlKey||event.metaKey||event.altKey)return;
        event.preventDefault();
        const now=performance.now();
        const accepted=onset!==null&&!event.repeat&&!beforeOnset.has(event.code)&&event.isTrusted;
        const key={code:event.code,clock:clock(now),rt_ms:onset===null?null:now-onset,accepted,
          phase:onset===null?"foreperiod":"response",correct:event.code===step.correct_code,
          ignored_reason:onset===null?"anticipatory":event.repeat?"key_repeat":beforeOnset.has(event.code)?"key_held_from_previous_phase":!event.isTrusted?"synthetic_key_event":null};
        keypresses.push(key);
        if(keypresses.length>2000){interrupt("excessive_key_events");return;}
        if(!accepted)return;
        if(now-onset>step.timeout_ms){key.accepted=false;key.ignored_reason="after_timeout";complete("timeout");return;}
        if(first===null)first=key;
        if(key.correct){final=key;complete("correct");}
        else if(step.forced_correction){feedback.replaceChildren(node("strong","X"),node("span","Incorrect. Press the other key to continue."));}
        else{feedback.replaceChildren(node("strong","X"),node("span","Incorrect response."));complete("incorrect");}
      };
      const localUp=event=>beforeOnset.delete(event.code);
      // Start the observed foreperiod before accepting anticipatory key events.
      // The first X onset remains the requestAnimationFrame-before-paint clock.
      foreperiodStart=performance.now();
      document.addEventListener("keydown",handleKey,true);document.addEventListener("keyup",localUp);
      cancelCurrent=()=>complete("interrupted");
      const tick=time=>{
        if(interrupted){complete("interrupted");return;}
        if(lastFrame!==null)maxFrameGap=Math.max(maxFrameGap,time-lastFrame);
        lastFrame=time;frameCount++;
        if(onset===null&&time-foreperiodStart>=step.foreperiod_ms){
          if(boxes)boxes.children[step.position-1].textContent="X";else stage.append(cue||material);
          onset=time;
          const rect=(boxes?boxes.children[step.position-1]:cue||material).getBoundingClientRect();
          void commit("task_trial_started",{task_id:compiled.id,trial_id:step.id,block_id:step.block_id,clock:clock(time),
            observed_foreperiod_ms:time-foreperiodStart,scheduled_foreperiod_ms:step.foreperiod_ms,
            observed_gap_since_previous_response_ms:previousResponseTime===null?null:time-previousResponseTime,
            timing_reference:"requestAnimationFrame_before_paint",viewport:{width:innerWidth,height:innerHeight,device_pixel_ratio:devicePixelRatio},
            stimulus_rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height}}).catch(()=>{});
        }
        if(onset!==null&&time-onset>=step.timeout_ms){complete("timeout");return;}
        frame=requestAnimationFrame(tick);
      };
      frame=requestAnimationFrame(tick);
      await responsePromise;
      document.removeEventListener("keyup",localUp);
      const responseObservedAt=performance.now();
      const response={task_id:compiled.id,trial_id:step.id,block_id:step.block_id,outcome,
        clock:clock(responseObservedAt),
        response_code:first?.code||null,final_code:final?.code||null,first_correct:first?.correct||false,
        first_response_ms:first?.rt_ms??null,final_correct_ms:final?.rt_ms??null,
        clock_instance_id:clockId,onset_ms:onset,foreperiod_start_ms:foreperiodStart,
        observed_foreperiod_ms:onset===null?null:onset-foreperiodStart,
        anticipatory_count:keypresses.filter(key=>key.phase==="foreperiod").length,
        keypresses,frame_count:frameCount,max_frame_gap_ms:maxFrameGap};
      if(step.mode==="aat"&&outcome==="correct"&&!interrupted){
        const animation=material.animate([{transform:"scale(1)"},{transform:step.action==="approach"?"scale(1.2)":"scale(.8)"}],{duration:step.zoom_duration_ms,fill:"forwards",easing:"linear"});
        const started=performance.now();cancelCurrent=()=>animation.cancel();
        try{await animation.finished;}catch{}
        response.zoom_feedback_observed_ms=performance.now()-started;cancelCurrent=null;
        if(interrupted)response.outcome="interrupted";
      }
      const intervalStarted=performance.now();
      stage.replaceChildren();feedback.replaceChildren();
      await commit("task_trial_finished",response);
      if(response.outcome==="interrupted")return response;
      if(step.forced_correction&&response.outcome!=="correct"){interrupt("correction_trial_timeout");return response;}
      previousResponseTime=final?Number(final.clock.value):first?Number(first.clock.value):responseObservedAt;
      await waitFrames(Math.max(0,step.intertrial_ms-(performance.now()-intervalStarted)));
      return response;
    };
    try {
      for(let index=startIndex;index<compiled.timeline.length&&!interrupted;index++){
        current=compiled.timeline[index];
        if(current.type==="task_instructions")await instruction(current);
        else if(current.type==="task_trial"){
          const response=await trial(current);
          if(response){responses.push(response);if(response.outcome!=="interrupted")lastCompleted=response.trial_id;}
        }else throw new Error("Unsupported task timeline step.");
      }
      if(interrupted)await commit("task_interrupted",{task_id:compiled.id,step_id:current?.id||null,reason:interruptionReason,clock:clock(performance.now())});
      await chain;
      return {outcome:interrupted?"interrupted":"completed",reason:interruptionReason,responses,last_completed_trial_id:lastCompleted};
    } finally {
      cancelCurrent?.();current=null;
      document.removeEventListener("visibilitychange",onVisibility);window.removeEventListener("blur",onBlur);window.removeEventListener("resize",onResize);
      document.removeEventListener("keydown",onDown);document.removeEventListener("keyup",onUp);signal?.removeEventListener("abort",onAbort);
    }
  }
  window.BrohnTasks=Object.freeze({version:"1.0.0",run});
})();

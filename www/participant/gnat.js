/* Named Brohn GNAT renderer. Caller owns consent, durable journal, exact retries,
 * received session state and scoring. Timed administrations never resume. */
(() => {
  "use strict";
  const node = (tag, text = null, attributes = {}) => {
    const n = document.createElement(tag); if (text !== null) n.textContent = text;
    for (const [name, value] of Object.entries(attributes)) n.setAttribute(name, String(value)); return n;
  };
  async function run({container, compiled, emit, onCheckpoint, signal, clockInstanceId, checkpoint = null}) {
    const core = globalThis.BrohnGnatCore;
    if (!core || !(container instanceof HTMLElement) || compiled?.profile !== core.profile || compiled.timeline?.length !== 396 ||
      compiled.timeline.filter(t => t.type === "task_trial").length !== 384 || typeof emit !== "function" || typeof onCheckpoint !== "function" ||
      typeof clockInstanceId !== "string" || !clockInstanceId || checkpoint !== null) {
      throw Error(checkpoint !== null ? "A GNAT administration cannot restart after refresh. Preserve its journal and use interrupted-session recovery." :
        "GNAT needs its complete frozen procedure, page clock and durable caller.");
    }
    if (!document.getElementById("brohn-gnat-style")) document.head.append(node("style",
      ".brohn-gnat{font-family:Arial,sans-serif;min-height:65vh;line-height:1.5}.brohn-gnat *{box-sizing:border-box}.brohn-gnat h1{font-size:1.7rem}.brohn-gnat p{max-width:70ch;overflow-wrap:anywhere}.brohn-gnat button{font:inherit;min-height:48px;padding:12px 20px;border:1px solid currentColor;border-radius:8px;background:inherit;color:inherit}.brohn-gnat button:focus-visible{outline:3px double currentColor;outline-offset:4px}.brohn-gnat .gnat-map{min-height:88px;text-align:center;overflow-wrap:anywhere}.brohn-gnat .gnat-map strong{display:block;font-size:1.15rem}.brohn-gnat .gnat-stage{min-height:220px;height:38vh;display:flex;align-items:center;justify-content:center;text-align:center}.brohn-gnat .gnat-material{font-size:clamp(1.2rem,5vw,2rem);line-height:1.3;max-width:100%;overflow-wrap:anywhere}.brohn-gnat .gnat-feedback{min-height:80px;text-align:center}.brohn-gnat .gnat-feedback strong{display:block;font-size:1.7rem}", {id:"brohn-gnat-style"}));
    const root = node("div", null, {class:"brohn-gnat"}); container.replaceChildren(root);
    const now = () => Number(performance.now().toFixed(6)), origin = performance.timeOrigin.toFixed(3);
    const clock = n => ({id:"browser-monotonic",unit:"ms",value:n.toFixed(6),instance_id:clockInstanceId,time_origin_ms:origin});
    const base = t => ({task_id:compiled.id,trial_id:t.id,block_id:t.block_id,procedure_hash:compiled.procedure_hash});
    let current=null,active=null,wait=null,cancel=null,reason=null,interruptionStep=null,failure=null,contradiction=null,failedWait=null,last=null,chain=Promise.resolve();
    const held=new Set(),responses=[],sealed=[];
    const interrupt = why => {
      if(reason)return;reason=why;interruptionStep=current?.id??last;
      if(wait){wait.end_ms=now();wait.visibility.push({observed_ms:wait.end_ms,visible:!document.hidden,focused:document.hasFocus()});failedWait=structuredClone(wait);}
      if(active&&!['finished','interrupted'].includes(active.phase))active=core.transition(active,{type:'interrupt',now:now(),reason:why});
      cancel?.();
    };
    const commit = (kind,data) => {
      const fixed=structuredClone(data);chain=chain.then(()=>emit(kind,fixed));
      chain.catch(e=>{failure=e;interrupt('journal_write_failed');});return chain;
    };
    const visibility = () => {
      const at=now(),v={observed_ms:at,visible:!document.hidden,focused:document.hasFocus()};
      if(wait)wait.visibility.push(v);
      if(active&&!['finished','interrupted'].includes(active.phase)){
        active=core.transition(active,{type:'visibility',now:at,visible:v.visible,focused:v.focused});
        if(active.phase==='interrupted')interrupt(active.interruption_reason);
      }else if(current&&(!v.visible||!v.focused))interrupt(!v.visible?'visibility_lost_during_task':'window_focus_lost_during_task');
    };
    const blur=()=>visibility(),resize=()=>{if(active||wait)interrupt('viewport_changed_during_trial');};
    const stop=()=>interrupt('caller_aborted');
    const key = event => {
      if(reason)return;
      try {
        const observed=now();let stamp=event.timeStamp;
        if(stamp>performance.timeOrigin)stamp-=performance.timeOrigin;
        stamp=Number(stamp.toFixed(6));
        if(!Number.isFinite(stamp)||stamp<0||stamp>observed||performance.timeOrigin.toFixed(3)!==origin){interrupt('unsupported_keyboard_event_clock');return;}
        const modifiers=event.ctrlKey||event.altKey||event.metaKey||event.shiftKey,wasHeld=held.has(event.code);
        const raw={type:event.type==='keydown'?'down':'up',code:event.code||'Unidentified',event_ms:stamp,observed_ms:observed,
          repeat:event.repeat,trusted:event.isTrusted,modifiers};
        if(event.isTrusted){if(event.type==='keyup')held.delete(raw.code);else held.add(raw.code);}
        if(active||wait)event.preventDefault();
        if(event.type==='keydown'&&raw.code==='Space'&&event.isTrusted&&!event.repeat&&!modifiers){
          const prior=sealed.find(w=>stamp>=w.onset&&stamp<w.deadline&&(w.first===null||stamp<w.first));
          if(prior){contradiction={trial_id:prior.id,key:{...raw,response_open:false,accepted:false,ignored_reason:'eligible_key_after_seal'}};interrupt('eligible_key_after_seal');return;}
        }
        if(wait){
          if(wait.keys.length>=5000){interrupt('excessive_key_events');return;}
          const reversed=wait.keys.length&&stamp<wait.keys.at(-1).event_ms;
          wait.keys.push(raw);
          if(reversed||raw.trusted&&raw.code==='Space'&&!wasHeld&&(raw.type==='up'||raw.repeat))interrupt(reversed?'event_clock_reversed':'impossible_space_key_state');
        }else if(active&&!['finished','interrupted'].includes(active.phase)){
          active=core.transition(active,{type:'key',now:observed,event_ms:stamp,keyType:raw.type,code:raw.code,repeat:raw.repeat,trusted:raw.trusted,modifiers});
          if(active.phase==='interrupted')interrupt(active.interruption_reason);
        }
        if(event.code==='Escape'&&event.type==='keydown'&&event.isTrusted){event.preventDefault();interrupt('participant_stopped');}
      }catch(e){interrupt('invalid_keyboard_observation');}
    };
    document.addEventListener('keydown',key,true);document.addEventListener('keyup',key,true);
    document.addEventListener('visibilitychange',visibility);window.addEventListener('blur',blur);window.addEventListener('resize',resize);
    signal?.addEventListener('abort',stop,{once:true});if(signal?.aborted)stop();
    try {
      for(current of compiled.timeline){
        if(reason)break;
        if(current.type==='task_instructions'){
          root.replaceChildren(node('h1',compiled.title,{tabindex:'-1'}),node('p',current.text),
            node('p','Use a physical keyboard. Press Space for the named categories and do nothing for other items. Each first response is final.'),
            node('p','Keep this page visible and focused. Escape stops the task; refreshing ends this administration. Training and practice run once, without a pass threshold.'));
          root.querySelector('h1').focus();
          await onCheckpoint({task_id:compiled.id,step_id:current.id,resumable:false,phase:'instructions',last_completed_trial_id:last});
          if(reason)break;
          await commit('task_instructions',{task_id:compiled.id,step_id:current.id,block_id:current.block_id,procedure_hash:compiled.procedure_hash,clock:clock(now())});
          await new Promise(resolve=>{const b=node('button',current.phase==='test'?'Begin test phase':'Begin practice phase',{type:'button'});root.append(b);cancel=resolve;
            b.addEventListener('click',()=>{b.disabled=true;cancel=null;resolve();},{once:true});});
          continue;
        }
        if(current.type!=='task_trial'||current.material?.type!=='text')throw Error('This GNAT revision requires its exact text-only timeline.');
        await onCheckpoint({task_id:compiled.id,step_id:current.id,resumable:false,phase:'timed',last_completed_trial_id:last});if(reason)break;
        if(document.hidden||!document.hasFocus()){interrupt('trial_started_without_focus');break;}
        const mapping=node('div',null,{class:'gnat-map'});mapping.append(node('strong','Space: '+current.go_labels.join(' or ')),node('span','Other items: do not press a key.'));
        const stage=node('div',null,{class:'gnat-stage'}),material=node('div',current.material.content,{class:'gnat-material'}),feedback=node('div',null,{class:'gnat-feedback','aria-live':'polite'});
        root.replaceChildren(mapping,stage,feedback,node('p','Press Escape to stop.'));
        const start=now();wait={start_ms:start,end_ms:null,held_codes:[...held],keys:[],visibility:[{observed_ms:start,visible:true,focused:true}]};
        if(held.has('Space'))feedback.textContent='Release Space to continue.';
        let handle=null,timer=null,frames=0,maxGap=0,lastFrame=null;
        await new Promise((resolve,reject)=>{
          const finish=()=>{if(handle!==null)cancelAnimationFrame(handle);if(timer!==null)clearTimeout(timer);cancel=null;resolve();};cancel=finish;
          const deadline=()=>{if(reason||!active||!['response','pending'].includes(active.phase))return;const at=now();
            if(at<active.deadline_ms){timer=setTimeout(deadline,Math.ceil(active.deadline_ms-at));return;}
            active=core.transition(active,{type:'deadline_timer',now:at});timer=null;};
          const tick=()=>{try{
            if(reason){finish();return;}const at=now();
            if(performance.timeOrigin.toFixed(3)!==origin){interrupt('page_clock_changed');return;}
            if(!active){
              if(document.hidden||!document.hasFocus()){visibility();return;}
              if(held.has('Space')){handle=requestAnimationFrame(tick);return;}
              wait.end_ms=at;wait.visibility.push({observed_ms:at,visible:true,focused:true});const released=structuredClone(wait);wait=null;
              feedback.replaceChildren();stage.append(material);const rect=material.getBoundingClientRect();
              if(rect.x<0||rect.y<0||rect.right>innerWidth||rect.bottom>innerHeight){stage.replaceChildren();failedWait=released;interrupt('stimulus_does_not_fit_viewport');return;}
              active=core.create(current,at,[...held]);
              void commit('task_trial_started',{...base(current),clock:clock(at),held_codes:[...held],release_wait:released,
                timing_reference:'requestAnimationFrame_before_paint',viewport:{width:innerWidth,height:innerHeight,device_pixel_ratio:devicePixelRatio},
                stimulus_rect:{x:rect.x,y:rect.y,width:rect.width,height:rect.height},visible:true,focused:true}).catch(()=>{});
              timer=setTimeout(deadline,Math.ceil(active.deadline_ms-now()));
            }
            frames++;if(lastFrame!==null)maxGap=Math.max(maxGap,at-lastFrame);lastFrame=at;
            if(['response','pending'].includes(active.phase)){
              if(active.phase==='pending'&&active.deadline_frame_ms===null)active=core.transition(active,{type:'deadline_frame',now:at});
              if(active.first||active.deadline_frame_ms!==null){
                active=core.transition(active,{type:'seal',now:at});if(timer!==null){clearTimeout(timer);timer=null;}stage.replaceChildren();
                const correct=['hit','correct_rejection'].includes(active.response_outcome);
                const words={hit:'Correct',miss:'Missed response',false_alarm:'Incorrect response',correct_rejection:'Correct: no response needed'};
                feedback.replaceChildren(node('strong',correct?'O':'X',{'aria-hidden':'true'}),node('span',words[active.response_outcome]));
              }
            }else if(active.phase==='feedback'&&at>=active.feedback_start_ms+100){feedback.replaceChildren();active=core.transition(active,{type:'feedback_end',now:at});}
            else if(active.phase==='blank'&&at>=Math.max(active.feedback_end_ms+400,active.response_closed_ms+500)){
              if(!held.has('Space')){active=core.transition(active,{type:'visibility',now:at,visible:!document.hidden,focused:document.hasFocus()});
                if(active.phase==='interrupted'){interrupt(active.interruption_reason);return;}
                active=core.transition(active,{type:'blank_end',now:at});finish();return;}
              feedback.textContent='Release Space to continue.';
            }
            handle=requestAnimationFrame(tick);
          }catch(e){if(timer!==null)clearTimeout(timer);if(handle!==null)cancelAnimationFrame(handle);cancel=null;reject(e);}};
          handle=requestAnimationFrame(tick);
        });
        wait=null;
        if(active){
          const result={...base(current),...core.result(active),clock:clock(now()),frame_count:frames,max_frame_gap_ms:Number(maxGap.toFixed(6))};
          if(result.outcome!=='interrupted')sealed.push({id:current.id,onset:result.onset_ms,deadline:result.deadline_ms,first:active.first?.event_ms??null,closed:result.response_closed_ms});
          await commit('task_trial_finished',result);responses.push(result);if(result.outcome!=='interrupted')last=current.id;active=null;
        }
      }
      if(reason&&!failure){const data={task_id:compiled.id,step_id:contradiction?.trial_id??interruptionStep,procedure_hash:compiled.procedure_hash,reason,clock:clock(failedWait?.end_ms??now())};
        if(contradiction)data.contradiction=contradiction;if(failedWait)data.release_wait=failedWait;await commit('task_interrupted',data);}
      await chain;if(failure)throw failure;
      return {outcome:reason?'interrupted':'completed',reason,responses,last_completed_trial_id:last};
    }finally{cancel?.();document.removeEventListener('keydown',key,true);document.removeEventListener('keyup',key,true);
      document.removeEventListener('visibilitychange',visibility);window.removeEventListener('blur',blur);window.removeEventListener('resize',resize);signal?.removeEventListener('abort',stop);}
  }
  globalThis.BrohnGnat = Object.freeze({version:'1.0.0',run});
})();

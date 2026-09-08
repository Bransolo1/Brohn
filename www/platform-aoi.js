'use strict';
(() => {
  const fields = ['x','y','width','height'];
  let active = null;
  const values = () => Object.fromEntries(fields.map(k=>[k,Number(document.getElementById(`aoi_${k}`)?.value)]));
  const valid = a => fields.every(k=>Number.isFinite(a[k])) && a.x>=0 && a.y>=0 && a.width>0 && a.height>0 && a.x+a.width<=1.000001 && a.y+a.height<=1.000001;
  function draw(a, announce=false) {
    const svg = document.getElementById('brohn-aoi-canvas'); if (!svg || !valid(a)) return;
    const box = svg.viewBox.baseVal;
    for (const id of ['brohn-aoi-selection','brohn-aoi-outline']) {
      const rect = document.getElementById(id);
      for (const k of fields) rect.setAttribute(k,String(a[k]*(k==='x'||k==='width'?box.width:box.height)));
    }
    if (announce) document.getElementById('brohn-aoi-announcement').textContent = ` Region ${Math.round(a.width*100)}% wide, ${Math.round(a.height*100)}% high.`;
  }
  function write(a) {
    if (!valid(a)) return;
    for (const k of fields) {
      const el=document.getElementById(`aoi_${k}`); if (!el) return;
      el.value=String(Math.round(a[k]*1e6)/1e6);
      el.dispatchEvent(new Event('change',{bubbles:true}));
      window.Shiny?.setInputValue(`aoi_${k}`,Number(el.value),{priority:'event'});
    }
    draw(a,true);
  }
  const history = [];
  const remember = () => {history.push(values()); if(history.length>50)history.shift();};
  const point = (event,svg) => {
    const pt=new DOMPoint(event.clientX,event.clientY).matrixTransform(svg.getScreenCTM().inverse());
    return {x:Math.max(0,Math.min(1,pt.x/svg.viewBox.baseVal.width)),y:Math.max(0,Math.min(1,pt.y/svg.viewBox.baseVal.height))};
  };
  document.addEventListener('pointerdown',event=>{
    const svg=event.target.closest('#brohn-aoi-canvas'); if(!svg || event.button!==0)return;
    event.preventDefault(); remember(); active={svg,start:point(event,svg),id:event.pointerId}; svg.setPointerCapture(event.pointerId);
  });
  document.addEventListener('pointermove',event=>{
    if(!active || event.pointerId!==active.id)return;
    const end=point(event,active.svg), start=active.start;
    const a={x:Math.min(start.x,end.x),y:Math.min(start.y,end.y),width:Math.abs(end.x-start.x),height:Math.abs(end.y-start.y)};
    if(a.width>=.001 && a.height>=.001){active.region=a;draw(a);}
  });
  document.addEventListener('pointerup',event=>{
    if(!active || event.pointerId!==active.id)return;
    if(active.region)write(active.region); active.svg.releasePointerCapture(event.pointerId);active=null;
  });
  document.addEventListener('pointercancel',()=>{if(active){draw(values());active=null;}});
  document.addEventListener('keydown',event=>{
    if(event.target.id!=='brohn-aoi-canvas' || !['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;
    event.preventDefault();const a=values();remember();
    const horizontal=['ArrowLeft','ArrowRight'].includes(event.key), delta=['ArrowLeft','ArrowUp'].includes(event.key)?-.01:.01;
    const k=event.shiftKey?(horizontal?'width':'height'):(horizontal?'x':'y');a[k]+=delta;
    if(event.shiftKey) {a.width=Math.max(.001,Math.min(a.width,1-a.x));a.height=Math.max(.001,Math.min(a.height,1-a.y));}
    else {a.x=Math.max(0,Math.min(a.x,1-a.width));a.y=Math.max(0,Math.min(a.y,1-a.height));}
    write(a);
  });
  document.addEventListener('input',event=>{if(fields.some(k=>event.target.id===`aoi_${k}`))draw(values());});
  document.addEventListener('click',event=>{if(event.target.closest('#brohn-aoi-undo') && history.length)write(history.pop());});
  new MutationObserver(()=>{if(!document.getElementById('brohn-aoi-canvas')){active=null;history.length=0;}}).observe(document.body,{childList:true,subtree:true});
  function promptPoint(x,y) {
    const svg=document.getElementById('brohn-aoi-prompt'); if(!svg)return;
    const p={x:Math.max(0,Math.min(1,x)),y:Math.max(0,Math.min(1,y))};
    if(!Number.isFinite(p.x)||!Number.isFinite(p.y))return;
    for(const k of ['x','y']) {
      const field=document.getElementById(`aoi_prompt_${k}`);field.value=String(Math.round(p[k]*1e6)/1e6);
      field.dispatchEvent(new Event('change',{bubbles:true}));window.Shiny?.setInputValue(`aoi_prompt_${k}`,Number(field.value),{priority:'event'});
    }
    const marker=document.getElementById('brohn-aoi-prompt-marker');
    marker.setAttribute('cx',String(p.x*svg.viewBox.baseVal.width));marker.setAttribute('cy',String(p.y*svg.viewBox.baseVal.height));
  }
  document.addEventListener('pointerdown',event=>{
    const svg=event.target.closest('#brohn-aoi-prompt');if(!svg||event.button!==0)return;
    event.preventDefault();const p=point(event,svg);promptPoint(p.x,p.y);svg.focus();
  });
  document.addEventListener('keydown',event=>{
    if(event.target.id!=='brohn-aoi-prompt'||!['ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].includes(event.key))return;
    event.preventDefault();let x=Number(document.getElementById('aoi_prompt_x').value),y=Number(document.getElementById('aoi_prompt_y').value);
    x+=event.key==='ArrowLeft'?-.01:event.key==='ArrowRight'?.01:0;y+=event.key==='ArrowUp'?-.01:event.key==='ArrowDown'?.01:0;promptPoint(x,y);
  });
  document.addEventListener('input',event=>{if(['aoi_prompt_x','aoi_prompt_y'].includes(event.target.id))promptPoint(Number(document.getElementById('aoi_prompt_x').value),Number(document.getElementById('aoi_prompt_y').value));});
})();

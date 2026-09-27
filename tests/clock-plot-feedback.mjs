import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
const asset=process.argv[2]||new URL('../www/clock-review-ui.js',import.meta.url),out=process.argv[3],code=fs.readFileSync(asset,'utf8'),checks=[];
function fixture(){
 const frames=[],sent=[],observers=[],listeners={},focus=[],scroll=[];let plot=null,main=null;
 const body={name:'body'},document={body,activeElement:body,visibilityState:'visible',documentElement:{},
  querySelector:s=>s.startsWith('#clock_plot_status')?plot:main,querySelectorAll:()=>[],
  addEventListener:(name,fn)=>(listeners[name]??=[]).push(fn)};
 const Shiny={setInputValue:(...args)=>sent.push(args)},window={Shiny,innerWidth:390,innerHeight:844,addEventListener:(name,fn)=>(listeners[name]??=[]).push(fn)};
 const context=vm.createContext({window,document,Shiny,Set,Array,Date,requestAnimationFrame:fn=>frames.push(fn),MutationObserver:class{constructor(fn){observers.push(fn)}observe(){}}});
 vm.runInContext(code,context);
 const event=name=>listeners[name]?.forEach(fn=>fn({target:{id:'unrelated',open:true}}));
 function node(token,phase='preparing',visible=true,prefix='plot'){
  const attrs={[`data-clock-${prefix}-ticket`]:token,[`data-clock-${prefix}-phase`]:phase};
  const n={attrs,visible,getAttribute:key=>attrs[key],setAttribute:(k,v)=>attrs[k]=v,
   getClientRects:()=>n.visible?[{}]:[],getBoundingClientRect:()=>({width:360,height:60,left:12,right:372,top:920,bottom:980}),
   focus:()=>{focus.push(n);document.activeElement=n;},scrollIntoView:()=>scroll.push(n)};return n;
 }
 const mutate=()=>observers.forEach(fn=>fn());
 return{frames,sent,focus,scroll,document,window,context,event,mutate,observers,
  set:(token,phase='preparing',visible=true)=>{plot=token?node(token,phase,visible):null;mutate();return plot;},
  main:(token,phase='preparing')=>{main=token?node(token,phase,true,'review'):null;mutate();return main;},
  frame:()=>{const count=frames.length;for(let i=0;i<count;i++)frames.shift()();}};
}
function check(label,fn){fn();checks.push(label);}
check('Rendered automatic plot waits for two frames and sends only its own acknowledgement',()=>{const f=fixture();f.set('plot-1');assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,0);f.frame();assert.deepEqual(f.sent.map(x=>x.slice(0,2)),[['clock_plot_prepare_ack','plot-1']]);});
check('Passive preparation does not focus or scroll a status below the viewport',()=>{const f=fixture(),control={name:'original export'};f.document.activeElement=control;f.set('plot-1');f.frame();f.frame();assert.equal(f.document.activeElement,control);assert.equal(f.focus.length,0);assert.equal(f.scroll.length,0);assert.equal(f.sent.length,1);});
check('Repeated mutations and duplicate script installation cannot acknowledge twice',()=>{const f=fixture();vm.runInContext(code,f.context);assert.equal(f.observers.length,2);f.set('one');f.frame();f.frame();f.mutate();f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Removed original window prevents a delayed automatic acknowledgement',()=>{const f=fixture();f.set('old');f.frame();f.set(null);f.frame();assert.equal(f.sent.length,0);});
check('Replaced plot ticket receives its own two frames without starting stale work',()=>{const f=fixture();f.set('old');f.frame();f.set('new');f.frame();assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,0);f.frame();assert.deepEqual(f.sent.map(x=>x[1]),['new']);});
check('Hidden tabs defer automatic work until their visible state changes',()=>{const f=fixture();f.document.visibilityState='hidden';f.set('one');f.frame();f.frame();assert.equal(f.sent.length,0);f.document.visibilityState='visible';f.event('visibilitychange');f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Collapsed or unrendered plot status cannot acknowledge until it has layout',()=>{const f=fixture(),n=f.set('one','preparing',false);f.frame();f.frame();assert.equal(f.sent.length,0);n.visible=true;f.event('toggle');f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Cancelled phase before the second paint prevents queue acknowledgement',()=>{const f=fixture(),n=f.set('one');f.frame();n.attrs['data-clock-plot-phase']='failed';f.mutate();f.frame();assert.equal(f.sent.length,0);});
check('Waiting and ready transitions neither queue extra work nor move current focus',()=>{const f=fixture(),control={name:'window bound'};f.document.activeElement=control;f.set('one');f.frame();f.frame();f.set('one','waiting');f.set('one','ready');f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.document.activeElement,control);assert.equal(f.focus.length,0);});
check('Missing Shiny connection defers without consuming the acknowledgement ticket',()=>{const f=fixture();f.window.Shiny=null;f.set('one');f.frame();f.frame();assert.equal(f.sent.length,0);f.window.Shiny={setInputValue:()=>{}};f.event('shiny:connected');f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Retry uses a new ticket and still leaves the researcher on their current control',()=>{const f=fixture(),control={name:'exports'};f.document.activeElement=control;f.set('first');f.frame();f.frame();f.set('first','failed');f.set('second');f.frame();f.frame();assert.deepEqual(f.sent.map(x=>x[1]),['first','second']);assert.equal(f.document.activeElement,control);});
check('A status hidden between animation frames does not start background work',()=>{const f=fixture(),n=f.set('one');f.frame();n.visible=false;f.frame();assert.equal(f.sent.length,0);});
if(out)fs.writeFileSync(out,JSON.stringify({passed:true,checks,asset_sha256:createHash('sha256').update(code).digest('hex'),scope:'Node simulated DOM/animation events for passive plot acknowledgement, alongside the full clock review script. Actual browser focus, Shiny and transport qualification remain separate.'},null,2));console.log('PASS',checks.length,'passive client checks');

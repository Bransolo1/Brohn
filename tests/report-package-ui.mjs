import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import path from 'node:path';
import {createHash} from 'node:crypto';
// node tests/report-package-ui.mjs <source-root-or-JS-file> <fresh-evidence-directory>
const args=process.argv.slice(2);
assert.equal(args.length,2,'Supply the source root or JS asset, and a fresh evidence directory.');
const source=path.resolve(args[0]),folder=path.resolve(args[1]);
assert(!fs.existsSync(folder),'Evidence directory must be fresh.');
const asset=fs.statSync(source).isDirectory()?path.join(source,'www','report-package-ui.js'):source;
const code=fs.readFileSync(asset,'utf8'),checks=[];
fs.mkdirSync(folder,{recursive:true});
const out=path.join(folder,'results.json');
function fixture(){
 let status=null;const frames=[],sent=[],observers=[],handlers={},headings=[],focus=[],scroll=[];
 const event=(name,value={})=>{for(const fn of handlers[name]||[])fn(value);};
 const on=(name,fn)=>(handlers[name]??=[]).push(fn);
 const body={},document={body,activeElement:body,visibilityState:'visible',documentElement:{},
  querySelector:()=>status,querySelectorAll:()=>headings,addEventListener:on};
 const Shiny={setInputValue:(...args)=>sent.push(args)},window={Shiny,innerHeight:844,innerWidth:390,addEventListener:on};
 const context=vm.createContext({window,document,Shiny,Set,Array,requestAnimationFrame:fn=>frames.push(fn),MutationObserver:class{constructor(fn){observers.push(fn)}observe(){}}});
 vm.runInContext(code,context);
 const mutate=()=>observers.forEach(fn=>fn());
 function node(ticket,phase,owner,passive=false){
  const attrs={'data-rpk-ticket':ticket,'data-rpk-phase':phase,'data-rpk-focus':owner,'data-rpk-passive':String(passive),'data-rpk-complete':owner};
  const n={attrs,visible:true,rect:{left:10,right:380,top:850,bottom:950},getAttribute:name=>attrs[name],setAttribute:(name,v)=>attrs[name]=v,
   getClientRects:()=>n.visible?[n.rect]:[],getBoundingClientRect:()=>n.rect,
   focus:options=>{assert.equal(options.preventScroll,true);document.activeElement=n;focus.push(n);event('focusin',{target:n});},
   scrollIntoView:options=>{scroll.push({node:n,...options});n.rect={left:10,right:380,top:options.block==='start'?0:350,bottom:options.block==='start'?100:450};}};
  return n;
 }
 return{frames,sent,observers,context,document,window,focus,scroll,event,mutate,
  set:(ticket,phase='preparing',owner='owner',passive=false)=>{status=phase===null?null:node(ticket,phase,owner,passive);mutate();return status;},
  target:owner=>{const n=node(null,'ready',owner);headings.push(n);mutate();return n;},
  frame:()=>{for(const fn of frames.splice(0))fn();},manual:target=>{document.activeElement=target;event('focusin',{target});}};
}
function check(label,fn){fn();checks.push(label);}
check('Explicit preparation is centered and focused before two complete frames acknowledge it',()=>{const f=fixture(),n=f.set('one');assert.equal(f.document.activeElement,n);assert.equal(f.scroll[0].block,'center');f.frame();assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent[0][0],'rpk_prepare_ack');assert.equal(f.sent[0][1],'one');});
check('Passive package opening does not move focus or scroll after the first queue action',()=>{const f=fixture();f.set('save');f.frame();f.frame();f.set(null,'waiting');const control={name:'other result'};f.manual(control);f.set('open','preparing','owner',true);f.frame();f.frame();assert.deepEqual(f.sent.map(x=>x[1]),['save','open']);assert.equal(f.document.activeElement,control);assert.equal(f.scroll.length,1);});
check('Owned completion focuses the actual heading at viewport start once',()=>{const f=fixture();f.set('save');f.frame();f.frame();f.set(null,'waiting');f.set('open','preparing','owner',true);f.frame();f.frame();f.document.activeElement=f.document.body;f.set(null,'ready');const heading=f.target('owner');assert.equal(f.document.activeElement,heading);assert.equal(f.scroll.at(-1).block,'start');f.mutate();assert.equal(f.focus.length,2);});
check('Keyboard focus elsewhere prevents completion focus and scrolling',()=>{const f=fixture();f.set('save');f.frame();f.frame();const other={};f.manual(other);f.set(null,'ready');f.target('owner');assert.equal(f.document.activeElement,other);assert.equal(f.focus.length,1);});
check('Trusted wheel and touch navigation retain user control after blur to body',()=>{for(const name of ['wheel','touchmove']){const f=fixture();f.set('save');f.frame();f.frame();f.event(name,{isTrusted:true});f.document.activeElement=f.document.body;f.set(null,'ready');f.target('owner');assert.equal(f.focus.length,1);}});
check('Navigation removal cancels the pending acknowledgement and completion ownership',()=>{const f=fixture();f.set('save');f.frame();f.set(null,null);f.frame();f.set(null,'ready');f.target('owner');assert.equal(f.sent.length,0);assert.equal(f.focus.length,1);});
check('Replacing a ticket requires two new frames and refuses the stale ticket',()=>{const f=fixture();f.set('old');f.frame();f.set('new','preparing','new-owner');f.frame();assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,0);f.frame();assert.deepEqual(f.sent.map(x=>x[1]),['new']);});
check('Repeated mutations and duplicated installation never acknowledge twice',()=>{const f=fixture();vm.runInContext(code,f.context);assert.equal(f.observers.length,1);f.set('one');f.frame();f.frame();f.mutate();f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.focus.length,1);});
check('Hidden documents defer both acknowledgement and focus until visible',()=>{const f=fixture();f.document.visibilityState='hidden';f.set('one');f.frame();f.frame();assert.equal(f.focus.length,0);assert.equal(f.sent.length,0);f.document.visibilityState='visible';f.event('visibilitychange');f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Clipped explicit feedback waits for visible geometry without forced second scrolling',()=>{const f=fixture(),n=f.set('one');n.rect.right=410;f.frame();f.frame();assert.equal(f.sent.length,0);n.rect.right=380;f.event('resize');f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.scroll.length,1);});
check('Hidden or cancelled status between frames cannot acknowledge work',()=>{for(const variant of ['hidden','cancelled']){const f=fixture(),n=f.set('one');f.frame();if(variant==='hidden')n.visible=false;else n.attrs['data-rpk-phase']='idle';f.frame();assert.equal(f.sent.length,0);}});
check('An owned failure is centered, but a failure after voluntary focus movement is passive',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.document.activeElement=f.document.body;const failure=f.set(null,'failed');assert.equal(f.document.activeElement,failure);assert.equal(f.scroll.at(-1).block,'center');const g=fixture();g.set('one');g.frame();g.frame();const other={};g.manual(other);g.set(null,'failed');assert.equal(g.document.activeElement,other);assert.equal(g.scroll.length,1);});
check('A passive historical reopen outside the viewport acknowledges without claiming focus',()=>{const f=fixture();f.set('open','preparing',null,true);f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.focus.length,0);assert.equal(f.scroll.length,0);});
fs.writeFileSync(out,JSON.stringify({passed:true,checks,asset_sha256:createHash('sha256').update(code).digest('hex'),scope:'Node simulated DOM/animation queue for the complete report-package feedback script. No actual browser paint or keyboard claim.'},null,2));
console.log(`PASS ${checks.length} report package client checks`);

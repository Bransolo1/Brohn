import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import os from 'node:os';
import path from 'node:path';
import {createHash} from 'node:crypto';
const asset=process.argv[2]||new URL('../www/task-plot-ui.js',import.meta.url);
const code=fs.readFileSync(asset,'utf8'), checks=[];
function fixture(){
  let node=null,observer;const frames=[],sent=[],listeners={},headings=[],focus=[],scroll=[];
  const body={name:'body'};
  const document={body,activeElement:body,visibilityState:'visible',documentElement:{},
    querySelector:()=>node,querySelectorAll:()=>headings,addEventListener:(type,fn)=>listeners[type]=fn};
  const Shiny={setInputValue:(...args)=>sent.push(args)};
  const window={Shiny,innerHeight:844,innerWidth:390,addEventListener:(type,fn)=>listeners[type]=fn};
  const context=vm.createContext({window,document,Shiny,Set,Array,requestAnimationFrame:fn=>frames.push(fn),MutationObserver:class{constructor(fn){observer=fn;}observe(){}}});
  vm.runInContext(code,context);
  function element(token,phase='preparing',visible=true){
    const attrs={'data-task-plot-ticket':token,'data-task-plot-phase':phase,'data-task-plot-complete':token};
    const element={attrs,visible,rect:{left:12,right:378,top:820,bottom:920,width:366,height:100},
      getAttribute:name=>attrs[name],setAttribute:(name,value)=>attrs[name]=value,
      getClientRects:()=>element.visible?[element.rect]:[],getBoundingClientRect:()=>element.rect,
      focus:options=>{assert.equal(options.preventScroll,true);document.activeElement=element;focus.push(element);listeners.focusin?.({target:element});},
      scrollIntoView:options=>{assert.equal(options.behavior,'instant');scroll.push(element);element.rect={...element.rect,top:350,bottom:450};}};
    return element;
  }
  return {sent,frames,document,listeners,context,focus,scroll,headings,element,
    set:(token,phase='preparing',visible=true)=>{node=token?element(token,phase,visible):null;observer();return node;},
    target:(token)=>{const el=element(token,'ready');headings.push(el);observer();return el;},
    mutate:()=>observer(),frame:()=>{const count=frames.length;for(let i=0;i<count;i++)frames.shift()();},
    manual:target=>{document.activeElement=target;listeners.focusin?.({target});}};
}
function check(label,fn){fn();checks.push(label);}
check('Current status is focused and instantly revealed before two complete animation frames and ack',()=>{const f=fixture(),n=f.set('one');assert.equal(f.document.activeElement,n);assert.equal(f.scroll.length,1);assert.equal(n.attrs.tabindex,'-1');assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,1);assert.equal(f.sent[0][1],'one');});
check('Repeated mutations cannot focus or acknowledge the same ticket twice',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.mutate();f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.focus.length,1);});
check('Replaced ticket requires its own two frames and never acknowledges stale work',()=>{const f=fixture();f.set('old');f.frame();f.set('new');f.frame();assert.equal(f.sent.length,0);f.frame();assert.equal(f.sent.length,0);f.frame();assert.deepEqual(f.sent.map(x=>x[1]),['new']);});
check('Navigation before ack clears ownership and does not focus delayed completion',()=>{const f=fixture();f.set('old');f.frame();f.set(null);f.frame();const outside={name:'new page'};f.manual(outside);f.target('old');f.set('old','ready');assert.equal(f.sent.length,0);assert.equal(f.document.activeElement,outside);assert.equal(f.focus.length,1);});
check('Hidden document is neither focused nor acknowledged until visible',()=>{const f=fixture();f.document.visibilityState='hidden';f.set('one');f.frame();f.frame();assert.equal(f.sent.length,0);assert.equal(f.focus.length,0);f.document.visibilityState='visible';f.listeners.visibilitychange();f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Non-rendered output waits for visible layout',()=>{const f=fixture();const n=f.set('one','preparing',false);f.frame();f.frame();assert.equal(f.sent.length,0);assert.equal(f.focus.length,0);n.visible=true;f.mutate();f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Duplicate script load creates no second focus or acknowledgment',()=>{const f=fixture();vm.runInContext(code,f.context);f.set('one');f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.focus.length,1);});
check('Scrolling pending status out of viewport before ack defers work without forcing scroll back',()=>{const f=fixture(),n=f.set('one');f.frame();n.rect={...n.rect,top:-100,bottom:0};f.frame();assert.equal(f.sent.length,0);assert.equal(f.scroll.length,1);n.rect={...n.rect,top:100,bottom:200};f.listeners.scroll();f.frame();f.frame();assert.equal(f.sent.length,1);assert.equal(f.scroll.length,1);});
check('Horizontal clipping also refuses acknowledgment until actual viewport fit',()=>{const f=fixture(),n=f.set('one');n.rect={...n.rect,right:410};f.frame();f.frame();assert.equal(f.sent.length,0);n.rect={...n.rect,right:378};f.listeners.resize();f.frame();f.frame();assert.equal(f.sent.length,1);});
check('Ready waits for matching rendered heading, then transfers focus once',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.document.activeElement=f.document.body;f.set('one','ready');assert.equal(f.focus.length,1);const heading=f.target('one');assert.equal(f.document.activeElement,heading);f.mutate();assert.equal(f.focus.length,2);assert.equal(f.scroll.length,2);});
check('Ready does not take focus from a researcher who selected another control',()=>{const f=fixture();f.set('one');f.frame();f.frame();const outside={name:'elsewhere'};f.manual(outside);f.set('one','ready');f.target('one');assert.equal(f.document.activeElement,outside);assert.equal(f.focus.length,1);});
check('Manual focus then blur to body does not restore permission to steal focus',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.manual({name:'elsewhere'});f.document.activeElement=f.document.body;f.set('one','ready');f.target('one');assert.equal(f.document.activeElement,f.document.body);assert.equal(f.focus.length,1);});
check('Old result cannot steal focus while newer ticket owns preparation',()=>{const f=fixture();f.set('old');f.frame();f.frame();const fresh=f.set('new');f.target('old');assert.equal(f.document.activeElement,fresh);assert.equal(f.focus.length,2);});
check('Own failure explanation receives focus without acknowledging more work',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.document.activeElement=f.document.body;const failure=f.set('one','failed');assert.equal(f.document.activeElement,failure);assert.equal(f.sent.length,1);assert.equal(f.focus.length,2);});
check('Ready completion in hidden document waits until visible',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.document.activeElement=f.document.body;f.document.visibilityState='hidden';f.set('one','ready');const heading=f.target('one');assert.equal(f.focus.length,1);f.document.visibilityState='visible';f.listeners.visibilitychange();assert.equal(f.document.activeElement,heading);});
check('Unrelated completion without a current owned ticket never takes focus',()=>{const f=fixture();f.target('other');f.set('other','ready');assert.equal(f.focus.length,0);assert.equal(f.sent.length,0);});
check('Trusted wheel navigation yields completion focus even when the old status remains focused',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.listeners.wheel({isTrusted:true});f.document.activeElement=f.document.body;f.set('one','ready');f.target('one');assert.equal(f.focus.length,1);assert.equal(f.document.activeElement,f.document.body);});
check('Trusted touch scrolling yields completion focus; a new explicit request owns focus afresh',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.listeners.touchmove({isTrusted:true});f.set('one','ready');f.target('one');assert.equal(f.focus.length,1);f.set('two');f.frame();f.frame();f.document.activeElement=f.document.body;f.set('two','ready');const target=f.target('two');assert.equal(f.document.activeElement,target);assert.equal(f.focus.length,3);});
check('Synthetic scroll event does not claim a researcher deliberately changed focus',()=>{const f=fixture();f.set('one');f.frame();f.frame();f.listeners.wheel({isTrusted:false});f.document.activeElement=f.document.body;f.set('one','ready');const target=f.target('one');assert.equal(f.document.activeElement,target);});
const result={passed:true,checks,asset_sha256:createHash('sha256').update(code).digest('hex'),scope:'Portable Node DOM/animation queue simulation. Actual viewport geometry, keyboard and source work require connected browser acceptance.'};
const output=process.argv[3]||path.join(fs.mkdtempSync(path.join(os.tmpdir(),'brohn-task-plot-ui-')),'results.json');
fs.writeFileSync(output,JSON.stringify(result,null,2));console.log(JSON.stringify({...result,output}));

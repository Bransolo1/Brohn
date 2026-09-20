/* Shared pre-consent welcome renderer. This component never allocates a run,
   stores a response, emits a timing event or inserts researcher text as HTML. */
(() => {
  'use strict';
  const node=(tag,text,attributes={})=>{
    const e=document.createElement(tag);if(text!==null&&text!==undefined)e.textContent=text;
    for(const[k,v]of Object.entries(attributes))e.setAttribute(k,String(v));return e;
  };
  function render(root,welcome,{imageSource=null,onContinue=()=>{},onError=()=>{},onReady=()=>{}}={}){
    if(!welcome||welcome.schema!=='brohn-welcome/1.0'||typeof welcome.title!=='string'||typeof welcome.text!=='string')throw Error('This welcome page is unavailable. Please contact your researcher.');
    root.replaceChildren(node('h1',welcome.title));
    if(welcome.text)root.append(node('p',welcome.text,{class:'welcome-text'}));
    const action=node('button','Continue to study information',{type:'button',class:'primary'});
    let ready=!welcome.asset;
    action.disabled=!ready;
    action.addEventListener('click',()=>{if(ready)onContinue();});
    if(welcome.asset){
      if(!imageSource||typeof welcome.image_alt!=='string'||!welcome.image_alt.trim())throw Error('The welcome image or its description is unavailable. Please contact your researcher.');
      const picture=node('img',null,{class:'welcome-image',alt:welcome.image_alt,width:welcome.asset.width,height:welcome.asset.height});
      const note=node('p','Loading the study image…',{class:'hint',role:'status'});
      const retry=node('button','Retry image',{type:'button',class:'secondary',hidden:''});
      const load=()=>{ready=false;action.disabled=true;retry.hidden=true;note.textContent='Loading the study image…';picture.removeAttribute('src');picture.src=imageSource;};
      picture.addEventListener('load',()=>{if(picture.naturalWidth<1)return;ready=true;action.disabled=false;note.textContent='';retry.hidden=true;onReady();});
      picture.addEventListener('error',()=>{ready=false;action.disabled=true;note.textContent='The study image could not load. Retry when your connection is available.';retry.hidden=false;onError('The welcome image could not load. No participant session has started.');});
      retry.addEventListener('click',load);
      root.append(picture,note,retry);load();
    }
    root.append(node('div',null,{class:'actions'}));root.lastElementChild.append(action);
    root.focus();
    return {continueButton:action};
  }
  window.BrohnWelcome=Object.freeze({render});
})();

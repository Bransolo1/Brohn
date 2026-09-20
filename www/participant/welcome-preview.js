/* Sandboxed, read-only rendering of the exact saved opening content. All data
   is embedded by the researcher server; no participant API or storage is used. */
(() => {
  'use strict';
  const data=JSON.parse(document.getElementById('welcome-preview-data').textContent);
  const root=document.getElementById('content'),status=document.getElementById('preview-status');
  for(const[k,v]of Object.entries({background:'--participant-bg',foreground:'--participant-fg'})){
    if(!/^#[a-f0-9]{6}$/i.test(data.appearance[k]))throw Error('Invalid saved appearance');
    document.documentElement.style.setProperty(v,data.appearance[k]);
  }
  const node=(tag,text,attrs={})=>{const e=document.createElement(tag);e.textContent=text;for(const[k,v]of Object.entries(attrs))e.setAttribute(k,v);return e;};
  const showWelcome=()=>{
    status.textContent='Saved welcome preview. No participant session is created.';
    window.BrohnWelcome.render(root,data.welcome,{imageSource:data.image_source,onContinue:()=>{
      root.replaceChildren(node('h1',data.consent.title),node('p',data.consent.text));
      status.textContent='Study information preview. Agreement and participant registration are disabled here.';
      const back=node('button','Back to welcome',{type:'button',class:'secondary'});back.addEventListener('click',showWelcome);root.append(back);root.focus();
    },onError:message=>{status.textContent=message;},onReady:()=>{status.textContent='Saved welcome preview. No participant session is created.';}});
  };
  showWelcome();
})();

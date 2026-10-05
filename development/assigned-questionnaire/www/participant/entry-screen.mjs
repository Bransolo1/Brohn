import {createParticipantStartController} from './start-controller.mjs';

const owners = new WeakSet();
const messages = {
  start_busy: 'This study is already being opened. Please wait.',
  start_consent: 'Read the study information and select the agreement box to take part.',
  start_alias: 'Enter the participant alias supplied by your researcher.',
  start_choice: 'Check your consent choice and participant alias.',
  start_unavailable: 'This study is not accepting new participants at the moment.',
  start_renderer: 'This link requires its original study software. Contact your researcher.',
  start_integrity: 'Saved study progress could not be verified. Contact your researcher; keep this browser’s stored data.',
  start_conflict: 'This browser already has a saved start. Continue that session without changing the original details.',
  start_network: 'The connection was interrupted. Retry to recover the same saved session.',
  start_blocked: 'Close other study tabs, then retry opening this link.'
};

export function mountParticipantEntry({container, releaseToken, rendererIdentity, onSession}) {
  if (container?.nodeType !== 1 || owners.has(container) || typeof onSession !== 'function')
    throw new TypeError('Use one owned entry container and a saved-session callback.');
  owners.add(container);
  const doc = container.ownerDocument, abort = new AbortController();
  let controller, busy = false, closed = false, closing = null, latest = null, handedOff = false;
  let form = null, fields = null, consent = null, alias = null, primary = null, retry = null;
  const root = doc.createElement('section'), content = doc.createElement('div'), status = doc.createElement('p'), error = doc.createElement('p');
  root.className = 'brohn-participant-entry'; root.setAttribute('aria-label', 'Study opening');
  status.className = 'brohn-entry-status'; status.setAttribute('role','status'); status.setAttribute('aria-live','polite');
  error.className = 'brohn-entry-error'; error.setAttribute('role','alert'); error.tabIndex = -1; error.hidden = true;
  root.append(content,status,error); container.append(root);
  const alive = () => {if(closed)throw Object.assign(new Error('Study opening was closed.'),{code:'start_closed'});};
  function disabled() {
    if(fields)fields.disabled=busy||!!latest?.request_saved;
    if(primary)primary.disabled=busy;
    if(retry)retry.disabled=busy;
    root.setAttribute('aria-busy',String(busy));
  }
  function state(value) {
    if(closed)return;
    latest=value;
    status.textContent=({loading:'Loading the study information…',starting:'Opening your study…',retrying:'Reconnecting to the same saved study…',
      saving:'Saving your study session in this browser…',saved:'Your saved session is ready.',pending:'A previous start is saved in this browser.',
      opening:'Read the information before choosing whether to take part.',
      attention:'Review the message below to continue.',
      empty:'Read the information before choosing whether to take part.'})[value.phase] || '';
    disabled();
  }
  function makeController() {controller=createParticipantStartController({releaseToken,rendererIdentity,onState:state});}
  makeController();
  function paragraph(value,parent=content) {const p=doc.createElement('p');p.textContent=value;p.className='brohn-entry-copy';parent.append(p);return p;}
  function heading(value,level='h1') {const h=doc.createElement(level);h.textContent=value;h.tabIndex=-1;content.append(h);return h;}
  function button(label,handler,parent=content) {const b=doc.createElement('button');b.type='button';b.textContent=label;b.addEventListener('click',handler);parent.append(b);return b;}
  function clear() {content.replaceChildren();form=fields=consent=alias=primary=retry=null;}
  function recoverable() {
    clear(); heading('Continue your study');
    paragraph('This browser has saved progress for this study link. Continue to recover the same session.');
    primary=button('Continue saved study',()=>launch()); disabled();
  }
  function render(page) {
    clear();root.style.setProperty('--entry-background',page.appearance.background);root.style.setProperty('--entry-foreground',page.appearance.foreground);
    const title=heading(page.title);
    if(page.welcome){
      heading(page.welcome.title,'h2');
      if(page.welcome.text)paragraph(page.welcome.text);
      if(page.welcome.image){const img=doc.createElement('img');img.src=page.welcome.image.url;img.alt=page.welcome.image_alt;
        img.width=page.welcome.image.width;img.height=page.welcome.image.height;img.className='brohn-entry-image';content.append(img);}
    }
    heading(page.consent.title,'h2');paragraph(page.consent.text);
    if(page.release_status!=='open'||page.workspace_paused){paragraph('This study is not accepting new participants at the moment.');return;}
    form=doc.createElement('form');fields=doc.createElement('fieldset');const legend=doc.createElement('legend');legend.textContent='Your choice to take part';fields.append(legend);
    const consentLabel=doc.createElement('label');consentLabel.className='brohn-entry-consent';consent=doc.createElement('input');consent.type='checkbox';consent.required=page.consent.required;
    const consentText=doc.createElement('span');consentText.textContent=page.consent.required?'I have read the information and agree to take part.':'I agree to take part (optional consent confirmation).';
    consentLabel.append(consent,consentText);fields.append(consentLabel);
    if(page.alias_required){const label=doc.createElement('label');label.className='brohn-entry-alias';const text=doc.createElement('span');text.textContent='Participant alias';
      alias=doc.createElement('input');alias.type='text';alias.required=true;alias.maxLength=200;alias.autocomplete='off';alias.spellcheck=false;
      label.append(text,alias);fields.append(label);paragraph('Use the alias supplied by your researcher. Do not enter your name unless they asked you to.',fields);}
    primary=doc.createElement('button');primary.type='submit';primary.textContent='Start study';form.append(fields,primary);
    form.addEventListener('submit',event=>{event.preventDefault();if(!busy)launch();});content.append(form);
    paragraph('Your session is saved in this browser so you can return using the same study link.');
    disabled();title.focus({preventScroll:true});
  }
  function showError(problem) {
    if(closed)return;
    status.textContent='Review the message below to continue.';
    error.hidden=false;error.textContent=messages[problem?.code] || 'The study could not be opened. Your saved progress is retained. Retry, or contact your researcher if this continues.';
    if(latest?.request_saved)recoverable();
    else if(!retry)retry=button('Retry opening study',()=>reload());
    disabled();error.focus({preventScroll:true});
  }
  async function load() {
    busy=true;error.hidden=true;disabled();
    try {const saved=await controller.inspect();alive();if(saved.request_saved)recoverable();else {const page=await controller.entry();alive();render(page);}}
    catch(problem){showError(problem);}
    finally {busy=false;if(!closed)disabled();}
  }
  async function reload() {
    if(busy||closed)return;
    busy=true;disabled();
    try {await controller.close();alive();makeController();}
    catch(problem){showError(problem);busy=false;disabled();return;}
    busy=false;await load();
  }
  async function launch() {
    if(busy||closed)return;
    // Capture participant input at submit, before network or storage can wait.
    const choice=latest?.request_saved?null:{consented:consent.checked,...(alias?{participantAlias:alias.value}:{})};
    busy=true;error.hidden=true;disabled();
    try {
      const held=await(choice===null?controller.resume():controller.begin(choice));alive();
      status.textContent='Recovering your current study progress…';
      // The host owns fresh CURRENT, participant renderers and their lifetime.
      await onSession(held,{signal:abort.signal});alive();
      handedOff=true;
      await close();
    }catch(problem){showError(problem);}
    finally{busy=false;if(!closed)disabled();}
  }
  function close() {
    if(!closing){closed=true;if(!handedOff)abort.abort();closing=controller.close().finally(()=>{root.remove();owners.delete(container);});}
    return closing;
  }
  const ready=load();
  return Object.freeze({ready,close});
}

/* Shared optional question/choice illustrations. No answer or journal ownership. */
(() => {
  'use strict';
  const require = (ok,message) => {if(!ok)throw new Error(message);};
  const object = value => value && typeof value==='object'&&!Array.isArray(value);
  const fields = (value,keys) => object(value)&&Object.keys(value).length===keys.length&&keys.every(k=>Object.hasOwn(value,k));
  const text = (value,max) => typeof value==='string'&&value.trim().length>0&&new TextEncoder().encode(value).length<=max;
  const integer = (value,min,max) => Number.isSafeInteger(value)&&value>=min&&value<=max;
  function validate(value) {
    require(fields(value,['asset','image_alt'])&&text(value.image_alt,2000),'This study illustration has an incomplete image description.');
    const a=value.asset;
    require(fields(a,['hash','size','media_type','filename','width','height'])&&/^[a-f0-9]{64}$/.test(a.hash)&&a.media_type==='image/png'&&
      integer(a.size,33,5*1024**2)&&integer(a.width,1,4096)&&integer(a.height,1,4096)&&a.width*a.height<=8000000&&
      text(a.filename,240)&&!/[\\/:]/.test(a.filename)&&!['.','..'].includes(a.filename),'This study illustration is outside the supported PNG profile.');
    return value;
  }
  function profile(protocol) {
    const questions=new Map(),choiceItems=new Map(),images=new Map(),all=new Map();let pixels=0;
    const register=value=>{
      const a=validate(value).asset,old=images.get(a.hash);
      require(!old||['size','media_type','width','height'].every(k=>old[k]===a[k]),'Shared illustration metadata disagrees.');
      if(!old){images.set(a.hash,a);all.set(a.hash,a);pixels+=a.width*a.height;}
    };
    for(const q of protocol.design.questions)if(Object.hasOwn(q,'illustration')) {questions.set(q.id,q.illustration);register(q.illustration);}
    for(const exercise of protocol.design.maxdiff||[])for(const item of exercise.items) {
      choiceItems.set(JSON.stringify([exercise.id,item.id]),item);
      if(Object.hasOwn(item,'illustration'))register(item.illustration);
    }
    for(const s of protocol.design.stimuli)if(s.asset){const a=s.asset,old=all.get(a.hash);require(!old||(old.size===a.size&&old.media_type===a.media_type),'Shared study media metadata disagrees.');if(!old)all.set(a.hash,a);}
    const bytes=[...all.values()].reduce((sum,a)=>sum+a.size,0);
    require(pixels<=64000000&&bytes<=512*1024**2,'Use smaller images. Question and choice illustrations share up to 64 million unique pixels; their bytes and passive media together must fit 512 MiB.');
    const steps=new Map(),choices=new Map(),urls=new Map();
    const bind=(source,address)=>{
      const url=new URL(address||'',location.href),a=source.asset;
      require(typeof address==='string'&&url.origin===location.origin&&!url.username&&!url.password&&!url.search&&!url.hash&&
        new RegExp(`^/api/assets/[a-f0-9]{64}/${a.hash}$`).test(url.pathname),'The saved illustration address is unavailable.');
      const prior=urls.get(a.hash);require(!prior||prior===url.href,'Shared illustration addresses disagree.');urls.set(a.hash,url.href);
    };
    for(const step of protocol.timeline)if(step.type==='question') {
      const source=questions.get(step.question.id);
      require(JSON.stringify(source)===JSON.stringify(step.question.illustration),'A question illustration differs from its frozen design.');
      if(!source)continue;
      bind(source,step.question_image_url);steps.set(step.id,source);
    }else if(step.type==='maxdiff') {
      const offered=new Map();
      for(const item of step.choice.items) {
        const declared=choiceItems.get(JSON.stringify([step.choice.exercise_id,item.id]));
        require(declared&&JSON.stringify(declared.illustration)===JSON.stringify(item.illustration),'An offered choice illustration differs from its frozen exercise.');
        if(!declared.illustration)continue;
        bind(declared.illustration,step.item_image_urls?.[item.id]);offered.set(item.id,declared.illustration);
      }
      choices.set(step.id,offered);
    }
    require([...images.keys()].every(hash=>urls.has(hash)),'A saved illustration has no compiled occurrence address.');
    return {images,steps,choices,urls,pixels,mediaBytes:bytes};
  }
  async function prepare(protocol,{signal}={}) {
    const plan=profile(protocol),prepared=new Map();
    // Sequential decoding bounds simultaneous work; repeated occurrences share bytes.
    for(const [hash,a] of plan.images) {
      require(!signal?.aborted,'Question image preparation was stopped.');
      const image=new Image();image.width=a.width;image.height=a.height;
      await new Promise((resolve,reject)=>{
        let settled=false;
        const done=error=>{if(settled)return;settled=true;clearTimeout(timer);signal?.removeEventListener('abort',abort);image.onload=null;image.onerror=null;error?reject(error):resolve();};
        const abort=()=>done(new Error('Question image preparation was stopped.'));
        const timer=setTimeout(()=>done(new Error('A question image did not load. Retry the saved materials.')),30000);
        image.onload=()=>done();image.onerror=()=>done(new Error('A question image could not be opened. Retry the saved materials.'));
        signal?.addEventListener('abort',abort,{once:true});image.src=plan.urls.get(hash);
      });
      if(image.decode)await image.decode();
      require(!signal?.aborted&&image.naturalWidth===a.width&&image.naturalHeight===a.height,'A question image differs from its saved dimensions.');
      prepared.set(hash,image);
    }
    const element=(illustration,className)=>{
      if(!illustration)return null;
      const image=prepared.get(illustration.asset.hash).cloneNode(true);image.alt=illustration.image_alt;
      image.className=className;return image;
    };
    return Object.freeze({node(step,compact=false){
      const image=element(plan.steps.get(step.id),`question-illustration${compact?' question-illustration-review':''}`);
      if(image)image.dataset.questionIllustration=step.question.id;return image;
    },itemNode(step,item){
      const image=element(plan.choices.get(step.id)?.get(item.id),'maxdiff-illustration');
      if(image)image.dataset.choiceIllustration=item.id;return image;
    }});
  }
  window.BrohnIllustrations=Object.freeze({validate,profile,prepare});
})();

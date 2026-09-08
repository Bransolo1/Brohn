import fs from 'node:fs/promises';
import path from 'node:path';
import {chromium} from '@playwright/test';
const root=path.resolve('../../work/test-runs/brohn-neural-plots-ui-evidence');
const browser=await chromium.launch({channel:'chrome',headless:true});
try{const page=await browser.newPage({viewport:{width:390,height:844}});await page.goto(`file:///${path.join(root,'erp.html').replaceAll('\\','/')}`);
 const result=await page.evaluate(()=>({width:innerWidth,documentWidth:document.documentElement.scrollWidth,plots:[...document.querySelectorAll('.brohn-neural-plots svg')].map(x=>({visible:!!x.getClientRects().length,box:x.getAttribute('viewBox'),rect:x.getBoundingClientRect().toJSON()})),outside:[...document.querySelectorAll('body *')].filter(x=>x.getClientRects().length&&x.getBoundingClientRect().right>innerWidth+1).slice(0,25).map(x=>({tag:x.tagName,class:x.className,text:x.textContent.slice(0,100),rect:x.getBoundingClientRect().toJSON(),display:getComputedStyle(x).display,minWidth:getComputedStyle(x).minWidth}))}));
 await fs.writeFile(path.join(root,'erp-offline-layout.json'),JSON.stringify(result,null,2));await page.screenshot({path:path.join(root,'erp-offline-layout.png'),fullPage:true});console.log(JSON.stringify(result,null,2));
}finally{await browser.close();}

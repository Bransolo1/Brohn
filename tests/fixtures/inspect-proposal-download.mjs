// Read-only diagnostics for an already saved synthetic QA proposal.
import {chromium,expect} from '@playwright/test';
const browser=await chromium.launch({channel:'chrome',headless:true});
try{
 const page=await browser.newPage();await page.goto('http://127.0.0.1:3851/');
 await page.getByRole('button',{name:'Studies',exact:true}).click();
 const card=page.locator('.brohn-card').filter({has:page.locator(`[data-brohn-value='"${process.argv[2]}"']`)});
 await card.getByRole('button',{name:'Open study',exact:true}).click();
 await page.getByRole('button',{name:'Review suggestion',exact:true}).first().click();
 await page.getByText('Inspect the saved model mask',{exact:true}).click();
 const link=page.getByRole('link',{name:'Download mask',exact:true});await expect(link).toHaveAttribute('href',/session\/.*download\//);
 const response=await page.request.get(new URL(await link.getAttribute('href'),page.url()).href);
 const body=await response.body();console.log(JSON.stringify({status:response.status(),headers:response.headers(),bytes:body.length,body:response.status()===200?body.subarray(0,8).toString('hex'):body.toString('utf8')}));
}finally{await browser.close();}

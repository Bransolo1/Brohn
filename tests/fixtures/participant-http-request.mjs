// Transport-only probe. Credentials live only in the external synthetic fixture.
import fs from 'node:fs/promises';
const request=JSON.parse(await fs.readFile(process.argv[2],'utf8'));
const bytes=request.path?await fs.readFile(request.path):Buffer.from(request.json,'utf8');
const headers={'Content-Type':'application/json',Origin:request.base};
if(request.token)headers.Authorization=`Bearer ${request.token}`;
const then=performance.now();
const response=await fetch(`${request.base}${request.route}`,{method:'POST',headers,body:bytes,signal:AbortSignal.timeout(180000)});
const body=await response.text(),elapsed_s=(performance.now()-then)/1000;
process.stdout.write(JSON.stringify({status:response.status,wire_bytes:bytes.length,elapsed_s,body}));

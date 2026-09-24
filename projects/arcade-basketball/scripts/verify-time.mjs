import fs from 'node:fs';
const base=fs.readFileSync('scripts/verify-api.mjs','utf8').split('let count=0;')[0];
const checks=`
const put=async(i,name,score,time)=>{const r=await post({source:src(i),rows:[{...row(name,'contest',1,0,score),bestTimeMs:time}]});assert.equal(r.status,200)};
const best=async name=>(await get()).modes.contest.find(r=>r.name===name);
await put(1,'PAIR',30,60000);await put(1,'PAIR',20,10000);assert.equal((await best('PAIR')).bestTimeMs,60000);
await put(1,'PAIR',30,55000);assert.equal((await best('PAIR')).bestTimeMs,55000);
await put(2,'PAIR',29,9000);assert.equal((await best('PAIR')).bestTimeMs,55000);
await put(2,'PAIR',31,65000);assert.equal((await best('PAIR')).bestTimeMs,65000);
await put(3,'PAIR',31,62000);assert.equal((await best('PAIR')).bestTimeMs,62000);
await put(3,'PAIR',31,null);assert.equal((await best('PAIR')).bestTimeMs,62000);
await put(4,'FAST',31,61000);await put(5,'OLD',31,null);assert.deepEqual((await get()).modes.contest.map(r=>r.name),['FAST','PAIR','OLD']);
await put(1,'PAIR',32,null);assert.equal((await best('PAIR')).bestTimeMs,null);
for(const t of [-1,70001,1.5,'50000'])assert.equal((await post({source:src(6),rows:[{...row('BAD','contest',1,0,30),bestTimeMs:t}]})).status,400);
console.log('PASS time pairing, stale snapshots, cross-device aggregation, ties, legacy nulls and invalid times');`;
await import('data:text/javascript;base64,'+Buffer.from(base.replace("'../dist/server/index.js'",JSON.stringify(new URL('../dist/server/index.js',import.meta.url).href))+checks).toString('base64'));

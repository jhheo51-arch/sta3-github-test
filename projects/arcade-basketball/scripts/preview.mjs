import http from 'node:http';
import fs from 'node:fs';
import {DatabaseSync} from 'node:sqlite';
import worker from '../dist/server/index.js';
const sqlite=new DatabaseSync(':memory:');
for(const file of fs.readdirSync('drizzle').filter(n=>n.endsWith('.sql')))sqlite.exec(fs.readFileSync('drizzle/'+file,'utf8'));
const DB={prepare(sql){return{bind(...args){return{all:async()=>({results:sqlite.prepare(sql).all(...args)}),run:async()=>sqlite.prepare(sql).run(...args)}}}},async batch(statements){sqlite.exec('BEGIN');try{const results=[];for(const s of statements)results.push(await s.run());sqlite.exec('COMMIT');return results}catch(e){sqlite.exec('ROLLBACK');throw e}}};
http.createServer(async(req,res)=>{try{const chunks=[];for await(const c of req)chunks.push(c);const body=Buffer.concat(chunks),request=new Request('http://127.0.0.1:8768'+req.url,{method:req.method,headers:req.headers,...(body.length?{body}:{} )});const response=await worker.fetch(request,{DB});res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()))}catch(e){res.writeHead(500);res.end('Preview error');console.error(e.message)}}).listen(8768,'127.0.0.1',()=>console.log('Local Worker + isolated SQLite preview on http://127.0.0.1:8768'));

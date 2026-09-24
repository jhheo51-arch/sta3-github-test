const MODES=['one','challenge','local','online','contest'];
function json(value,status=200){return new Response(JSON.stringify(value),{status,headers:{'content-type':'application/json; charset=utf-8','cache-control':'no-store','x-content-type-options':'nosniff'}})}
function db(env){if(!env.DB?.prepare)throw Error('Ranking DB unavailable');return env.DB}
function validateSnapshot(input){
 if(!input||typeof input.source!=='string'||!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/.test(input.source)||!Array.isArray(input.rows)||input.rows.length>60)throw Error('invalid_snapshot');
 const seen=new Set();const rows=input.rows.map(r=>{
  if(!r||!MODES.includes(r.mode)||typeof r.name!=='string')throw Error('invalid_row');
  const name=r.name.trim().normalize('NFC');if(!name||name.length>16||/[\u0000-\u001f\u007f]/.test(name))throw Error('invalid_name');
  for(const k of ['games','wins','bestScore','made','attempts'])if(!Number.isSafeInteger(r[k])||r[k]<0||r[k]>10000000)throw Error('invalid_score');
  if(r.wins>r.games||r.made>r.attempts||r.bestScore>10000||(r.mode==='contest'&&r.bestScore>40))throw Error('invalid_score');
  if(r.bestTimeMs!=null&&(!Number.isSafeInteger(r.bestTimeMs)||r.bestTimeMs<0||r.bestTimeMs>70000))throw Error('invalid_time');
  const key=r.mode+'|'+name;if(seen.has(key))throw Error('duplicate_row');seen.add(key);
  return{mode:r.mode,name,bestTimeMs:r.mode==='contest'?(r.bestTimeMs??null):null,games:r.games,wins:r.wins,bestScore:r.bestScore,made:r.made,attempts:r.attempts};
 });return{source:input.source,rows};
}
async function saveSnapshot(database,input){
 const data=validateSnapshot(input),now=Date.now();if(!data.rows.length)return;
 // Per-browser cumulative snapshots: retries and older requests cannot add a record twice.
 const statements=data.rows.map(r=>database.prepare(`INSERT INTO ranking_sources(source,mode,name,games,wins,best_score,made,attempts,updated_at,best_time_ms)
 VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(source,mode,name) DO UPDATE SET
 games=MAX(ranking_sources.games,excluded.games),wins=MAX(ranking_sources.wins,excluded.wins),
 best_time_ms=CASE WHEN excluded.best_score>ranking_sources.best_score THEN excluded.best_time_ms
 WHEN excluded.best_score=ranking_sources.best_score THEN CASE WHEN ranking_sources.best_time_ms IS NULL THEN excluded.best_time_ms WHEN excluded.best_time_ms IS NULL THEN ranking_sources.best_time_ms ELSE MIN(ranking_sources.best_time_ms,excluded.best_time_ms) END
 ELSE ranking_sources.best_time_ms END,
 best_score=MAX(ranking_sources.best_score,excluded.best_score),made=MAX(ranking_sources.made,excluded.made),
 attempts=MAX(ranking_sources.attempts,excluded.attempts),updated_at=excluded.updated_at`).bind(data.source,r.mode,r.name,r.games,r.wins,r.bestScore,r.made,r.attempts,now,r.bestTimeMs));
 await database.batch(statements);
}
async function getLeaders(database){
 const out={};for(const mode of MODES){
 const order=mode==='contest'?'bestScore DESC,bestTimeMs IS NULL ASC,bestTimeMs ASC,name ASC':mode==='challenge'?'bestScore DESC,games ASC,name ASC':'wins DESC,CAST(wins AS REAL)/MAX(games,1) DESC,games ASC,name ASC';
 const result=await database.prepare(`WITH best AS (SELECT name,MAX(best_score) AS score FROM ranking_sources WHERE mode=? GROUP BY name)
 SELECT * FROM (SELECT r.name AS name,SUM(games) AS games,SUM(wins) AS wins,MAX(best_score) AS bestScore,SUM(made) AS made,SUM(attempts) AS attempts,MIN(CASE WHEN r.best_score=best.score THEN r.best_time_ms END) AS bestTimeMs FROM ranking_sources r JOIN best ON best.name=r.name WHERE mode=? GROUP BY r.name HAVING SUM(games)>0) ORDER BY ${order} LIMIT 5`).bind(mode,mode).all();out[mode]=result.results;
 }return{modes:out,updatedAt:Date.now()};
}
export default {async fetch(request,env){
 const url=new URL(request.url);
 if(url.pathname==='/api/rankings'){
  try{
   if(request.method==='GET')return json(await getLeaders(db(env)));
   if(request.method==='POST'){
    const origin=request.headers.get('origin');if(origin&&origin!==url.origin)return json({error:'다른 사이트에서 보낸 요청입니다.'},403);
    if(!request.headers.get('content-type')?.startsWith('application/json'))return json({error:'JSON 형식이 필요합니다.'},415);
    const body=await request.text();if(body.length>32768)return json({error:'한 번에 보낼 기록이 너무 많습니다.'},413);
    let input;try{input=validateSnapshot(JSON.parse(body))}catch{return json({error:'기록 형식이나 점수를 확인해 주세요.'},400)}
    await saveSnapshot(db(env),input);return json({saved:true});
   }return json({error:'지원하지 않는 요청입니다.'},405);
  }catch(e){console.error('rankings unavailable',e?.message);return json({error:'공용 랭킹에 연결하지 못했습니다. 잠시 후 다시 시도해 주세요.'},503)}
 }
 if((url.pathname==='/'||url.pathname==='/index.html')&&['GET','HEAD'].includes(request.method))return new Response(request.method==='HEAD'?null:page,{headers:{'content-type':'text/html; charset=utf-8','cache-control':'no-cache','x-content-type-options':'nosniff'}});
 return new Response('Not found',{status:404});
}};

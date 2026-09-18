import fs from 'node:fs';
const html=fs.readFileSync('src/index.html','utf8'),api=fs.readFileSync('worker/api.js','utf8');
fs.mkdirSync('dist/server',{recursive:true});fs.mkdirSync('dist/.openai',{recursive:true});
fs.writeFileSync('dist/server/index.js','const page='+JSON.stringify(html)+';\n'+api);
fs.copyFileSync('.openai/hosting.json','dist/.openai/hosting.json');
fs.cpSync('drizzle','dist/.openai/drizzle',{recursive:true});
if(fs.existsSync('dist/index.html'))fs.unlinkSync('dist/index.html');
console.log('Built Worker HTML + ranking API + D1 migrations');

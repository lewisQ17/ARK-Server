require('dotenv').config();
const {Proxmox}=require('./proxmox');
const cfg=require('./config');
(async()=>{
  const p=new Proxmox(cfg.proxmox);
  for(let i=0;i<7;i++){
    try{ const r=await p.guestShell('echo AGENT_BACK', {timeoutMs:9000}); console.log('['+i+'] RECOVERED:', r.out.trim()); process.exit(0); }
    catch(e){ console.log('['+i+'] still down:', (e.message.match(/message":"([^"\\]+)/)?.[1]||'').slice(0,40)); await new Promise(r=>setTimeout(r,18000)); }
  }
  console.log('NOT recovered after ~2min');
})().catch(e=>console.log('ERR',e.message));

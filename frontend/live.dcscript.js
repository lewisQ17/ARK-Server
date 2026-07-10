// live.dcscript.js — live logic for the ARK dashboard.
// Replaces the design prototype's mock data with real data from the backend API.
// Same renderVals() output keys as the prototype, so the template renders identically.
// Assembled inline into index.html (dc-runtime reads the inline script's textContent).

const IC = {
  overview:'<rect x="3.5" y="3.5" width="7" height="7" rx="1.5"/><rect x="13" y="3.5" width="7" height="7" rx="1.5"/><rect x="13" y="13" width="7" height="7" rx="1.5"/><rect x="3.5" y="13" width="7" height="7" rx="1.5"/>',
  instance:'<rect x="3.5" y="4.5" width="17" height="6" rx="1.6"/><rect x="3.5" y="13" width="17" height="6" rx="1.6"/><circle cx="7.2" cy="7.5" r="1"/><circle cx="7.2" cy="16" r="1"/>',
  cluster:'<circle cx="6" cy="6.5" r="2.3"/><circle cx="18" cy="6.5" r="2.3"/><circle cx="12" cy="17.5" r="2.3"/><path d="M7.6 8.2 10.8 15.6M16.4 8.2 13.2 15.6M8.3 6.5h7.4"/>',
  console:'<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M7 9.5 10 12l-3 2.5M12.5 14.5H16"/>',
  backups:'<path d="M3.5 12a8.5 8.5 0 1 0 2.6-6.1"/><path d="M3.2 4.2v3.4h3.4"/><path d="M12 8v4.3l3 1.8"/>',
  settings:'<path d="M5 7h14M5 12h14M5 17h14"/><circle cx="9" cy="7" r="2"/><circle cx="15" cy="12" r="2"/><circle cx="8" cy="17" r="2"/>',
  mobile:'<rect x="7" y="3" width="10" height="18" rx="2.4"/><path d="M11 18h2"/>',
  bolt:'<path d="M13 2 4 14h6l-1 8 9-12h-6z"/>',
  restart:'<path d="M4.5 12a7.5 7.5 0 1 1 2.3 5.4M4.2 20v-4.2h4.2"/>',
  clock:'<circle cx="12" cy="12" r="8"/><path d="M12 7.5V12l3 1.8"/>',
  save:'<path d="M5 4h11l3 3v13H5z"/><path d="M8 4v5h7V4M8 20v-6h8v6"/>',
  broom:'<path d="M15 4 9 10M19.5 5 14 10.5l-1.5-1.5L18 3.5zM12.5 9 6 15.5 5 20l4.5-1L16 12.5"/>'
};
function icn(name, size, color){
  return React.createElement('svg',{width:size||18,height:size||18,viewBox:'0 0 24 24',fill:'none',stroke:color||'currentColor',strokeWidth:1.7,strokeLinecap:'round',strokeLinejoin:'round',style:{display:'block',flex:'none'},dangerouslySetInnerHTML:{__html:IC[name]||''}});
}
// Per-map themed logos (by internal map name). Distinct silhouettes so each map is recognisable at a glance.
const MAP_ICONS={
  // The Island — palm tree on a mound
  TheIsland_WP:'<path d="M12 21V11"/><path d="M12 11c-3-3-6-2-8-1 2-2 5-3 8-1 0-3 2-5 4-6-2 2-3 4-3 6 3-2 6-1 8 1-2-1-5-2-9 1"/><path d="M6 21h12"/>',
  // Lost Island — compass rose
  LostIsland_WP:'<circle cx="12" cy="12" r="9"/><path d="m8.5 8.5 3 3 4-4-2.5 5-3 3z"/>',
  // Crystal Isles — gem
  CrystalIsles_WP:'<path d="M8 3h8l3 5-7 13-7-13z"/><path d="M5 8h14M9 3l3 18M15 3l-3 18"/>',
  // Fjordur — fjord peaks over water
  Fjordur_WP:'<path d="M3 17 8 7l3 5 3-7 4 12z"/><path d="M3 20h18M3 17c1.5 1 2.5 1 4 0s2.5-1 4 0 2.5 1 4 0 2.5-1 4 0"/>',
  // Scorched Earth — sun
  ScorchedEarth_WP:'<circle cx="12" cy="12" r="4"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3M5.6 5.6l2 2M16.4 16.4l2 2M5.6 18.4l2-2M16.4 7.6l2-2"/>',
  // Aberration — mushroom
  Aberration_WP:'<path d="M10 14v5a2 2 0 0 0 4 0v-5"/><path d="M4.5 13a7.5 7.5 0 0 1 15 0z"/><path d="M9 10h.01M13 9h.01"/>',
  // Extinction — ruined city skyline
  Extinction_WP:'<path d="M3 21V9l4-2v4l4-3v5l4-3v6l4-2v9z"/><path d="M3 21h18"/>',
  // Ragnarok — mountain range with peak
  Ragnarok_WP:'<path d="M2 20 8 8l3 5 3.5-7L22 20z"/><path d="M2 20h20M6.5 12l1.5-1 1.5 1.5"/>',
  // Valguero — waterfall between cliffs
  Valguero_WP:'<path d="M5 3v18M19 3v18"/><path d="M9 5c2 2 4 2 6 0M10 10c1.5 1.5 2.5 1.5 4 0M9 15c2 1.5 4 1.5 6 0"/>',
  // The Center — shield hex
  TheCenter_WP:'<path d="M12 2 4 6v6c0 5 3.5 8 8 10 4.5-2 8-5 8-10V6z"/><path d="M9 11l2 2 4-4"/>',
  // Genesis 1 — biome hexagon
  Genesis_WP:'<path d="M12 2 3 7.5v9L12 22l9-5.5v-9z"/><path d="M12 8v8M8 10v4M16 10v4"/>',
  // Genesis 2 — orbital ring
  Gen2_WP:'<circle cx="12" cy="12" r="4"/><path d="M4 12a8 8 0 0 0 16 0M20 12a8 8 0 0 0-16 0"/><ellipse cx="12" cy="12" rx="10" ry="4"/>'
};
function mapIcon(internal, color){
  const p=MAP_ICONS[internal]||'<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><path d="M8 9l3 3-3 3M13 15h4"/>';
  return React.createElement('svg',{width:22,height:22,viewBox:'0 0 24 24',fill:'none',stroke:color||'currentColor',strokeWidth:1.8,strokeLinecap:'round',strokeLinejoin:'round',style:{display:'block'},dangerouslySetInnerHTML:{__html:p}});
}
const STATUS = {
  running:{label:'Running',c:'#37D67A'},
  starting:{label:'Booting',c:'#FFB23E'},
  sleeping:{label:'Sleeping',c:'#5AA9FF'},
  stopped:{label:'Stopped',c:'#6B7686'},
  crashed:{label:'Crashed',c:'#FF5B5B'},
  unprovisioned:{label:'Not deployed',c:'#5C6979'},
  unknown:{label:'Connecting…',c:'#5C6979'}
};
function spark(arr,w,h){
  if(!arr||arr.length<2) return {line:'M0 '+h+' L'+w+' '+h, area:'M0 '+h+' L'+w+' '+h+' L'+w+' '+h+' L0 '+h+' Z', last:0};
  const n=arr.length; const mn=Math.min.apply(null,arr)-3; const mx=Math.max.apply(null,arr)+3; const rng=(mx-mn)||1;
  const pts=arr.map((v,i)=>[(i/(n-1))*w,(h-((v-mn)/rng)*h)]);
  const line='M'+pts.map(p=>p[0].toFixed(1)+' '+p[1].toFixed(1)).join(' L');
  return {line, area:line+' L'+w+' '+h+' L0 '+h+' Z', last:arr[arr.length-1]};
}
function sparkF(arr,w,h){
  if(!arr||arr.length<2) return {line:'M0 '+h+' L'+w+' '+h, area:''};
  const n=arr.length; const pts=arr.map((v,i)=>[(i/(n-1))*w,h-(Math.max(0,Math.min(100,v))/100)*h]);
  const line='M'+pts.map(p=>p[0].toFixed(1)+' '+p[1].toFixed(1)).join(' L');
  return {line, area:line+' L'+w+' '+h+' L0 '+h+' Z'};
}
const FEED_DOT = {join:'#37D67A',leave:'#6B7686',transfer:'#37D3C3',sys:'#5AA9FF'};
const CTAG={sys:['SYS','#5C6979'],ok:['OK','#37D67A'],join:['JOIN','#37D67A'],leave:['LEFT','#6B7686'],chat:['CHAT','#37D3C3'],rcon:['RCON','#FF7A2E'],warn:['WARN','#FFB23E'],error:['ERR','#FF5B5B'],log:['LOG','#93A0B2']};
const CFILTERS=[['all','All'],['chat','Chat'],['rcon','RCON'],['join','Joins'],['warn','Alerts']];
const CMACROS=[{label:'Broadcast',cmd:'Broadcast Hello survivors!'},{label:'Save World',cmd:'SaveWorld'},{label:'List Players',cmd:'ListPlayers'},{label:'Get Time',cmd:'GetGameLog'},{label:'Destroy Wild Dinos',cmd:'DestroyWildDinos'},{label:'Get Chat',cmd:'GetChat'}];
const MACROS = [{label:'Broadcast',cmd:'Broadcast Hello survivors!'},{label:'Save World',cmd:'SaveWorld'},{label:'List Players',cmd:'ListPlayers'},{label:'Get Chat',cmd:'GetChat'}];

// classify a raw ARK log line for console colouring
function classifyLog(line){
  if(/RCON/i.test(line)) return 'rcon';
  if(/joined/i.test(line)) return 'join';
  if(/left|disconnect/i.test(line)) return 'leave';
  if(/error|fatal|illegal/i.test(line)) return 'error';
  if(/warning|warn/i.test(line)) return 'warn';
  if(/save|backup/i.test(line)) return 'ok';
  if(/\[chat\]|: /i.test(line) && /global|tribe|chat/i.test(line)) return 'chat';
  return 'log';
}

function api(path, opts){
  return fetch(path, Object.assign({headers:{'Content-Type':'application/json'}}, opts||{}))
    .then(r=>r.json());
}
function cronHuman(cron){
  if(!cron) return '';
  const p=cron.split(/\s+/); if(p.length<5) return cron;
  const [mi,ho,dom,mon,dow]=p;
  if(mi.indexOf('*/')===0) return 'every '+mi.slice(2)+' minutes';
  if(ho.indexOf('*/')===0) return 'every '+ho.slice(2)+' hours';
  if(dow!=='*'&&ho!=='*') return 'weekly · '+ho.padStart(2,'0')+':'+mi.padStart(2,'0');
  if(ho!=='*'&&mi!=='*') return 'daily at '+ho.padStart(2,'0')+':'+mi.padStart(2,'0');
  return cron;
}
// Next fire time for a cron, scanning minute-by-minute (correct for every pattern
// the scheduler can produce). Returns a short human label like "in 3h" / "tomorrow 04:00".
function cronField(expr, val){
  if(expr==='*') return true;
  return String(expr).split(',').some(part=>{
    if(part.indexOf('*/')===0){ const step=parseInt(part.slice(2),10); return step>0 && val%step===0; }
    const dash=part.split('-'); if(dash.length===2){ const a=+dash[0],b=+dash[1]; return val>=a&&val<=b; }
    const n=parseInt(part,10); return !isNaN(n) && n===val;
  });
}
function cronNext(cron, now){
  if(!cron||!now) return '';
  const p=cron.trim().split(/\s+/); if(p.length<5) return '';
  const [mi,ho,dom,mon,dow]=p;
  const d=new Date(now.getTime()); d.setSeconds(0,0); d.setMinutes(d.getMinutes()+1);
  for(let i=0;i<8*1440;i++){
    if(cronField(mi,d.getMinutes())&&cronField(ho,d.getHours())&&cronField(dom,d.getDate())&&cronField(mon,d.getMonth()+1)&&cronField(dow,d.getDay())){
      const diff=Math.round((d.getTime()-now.getTime())/60000);
      if(diff<1) return 'now';
      if(diff<60) return 'in '+diff+'m';
      if(diff<1440){ const h=Math.floor(diff/60), m=diff%60; return 'in '+h+'h'+(m?' '+m+'m':''); }
      const days=Math.floor(diff/1440); const hhmm=String(d.getHours()).padStart(2,'0')+':'+String(d.getMinutes()).padStart(2,'0');
      return days===1?('tomorrow '+hhmm):('in '+days+'d');
    }
    d.setMinutes(d.getMinutes()+1);
  }
  return '';
}
// Build a cron string from a friendly day (0-6 or '*') + "HH:MM" — so the UI never
// shows raw cron. Day '*' = every day, else weekly on that weekday.
function cronFromDT(day, time){
  const p=String(time||'0:0').split(':'); const h=Math.min(23,Math.max(0,parseInt(p[0],10)||0)); const m=Math.min(59,Math.max(0,parseInt(p[1],10)||0));
  return `${m} ${h} * * ${day==='*'?'*':String(day)}`;
}
const DAY_NAMES={'0':'Sundays','1':'Mondays','2':'Tuesdays','3':'Wednesdays','4':'Thursdays','5':'Fridays','6':'Saturdays'};
function humanDT(day, time){ const t=time||'00:00'; return day==='*'?('every day at '+t):((DAY_NAMES[String(day)]||'')+' at '+t); }
// Any applied/non-default multiplier-type setting that isn't already one of the six
// base multipliers, so searched-and-applied rates show up in the Multipliers grid too.
function isMultKey(k){ return /(Multiplier|Scale)$/.test(k); }
function shortLabel(c){ return c.key.replace(/(Multiplier|Scale)$/,'').replace(/([a-z0-9])([A-Z])/g,'$1 $2').replace(/\bPve\b/,'PvE').trim(); }
function extendMults(base, config, override, catalog){
  base=base||[]; override=override||{}; catalog=catalog||[];
  const have={}; base.forEach(m=>have[m.key]=1);
  const all=(config&&config.all)||{};
  const norm=x=>String(x==null?'':x).trim().replace(/^(\d+)\.0+$/,'$1');
  const extra=[];
  catalog.forEach(c=>{
    if(have[c.key]||!isMultKey(c.key)||c.type==='bool') return;
    const ov=override[c.key], cur=all[c.key];
    const raw = ov!=null ? ov : (cur!=null ? cur : null);
    if(raw==null) return;
    if(ov==null && norm(raw)===norm(c.def)) return; // config value still at default & not touched
    have[c.key]=1;
    const bn=parseFloat(c.def)||1, v=parseFloat(raw); const vv=isNaN(v)?bn:v;
    extra.push({ k:shortLabel(c), key:c.key, file:c.file, v:vv+'×', val:vv, v2:String(vv), base:bn+'×', baseNum:bn, max:c.max||10, pct:Math.min(100,Math.round(vv/(c.max||10)*100)), hot:vv>bn });
  });
  return base.concat(extra);
}
function relTime(ts){
  const s=Math.max(0,Math.round((Date.now()-ts)/1000));
  if(s<60) return s+'s ago'; if(s<3600) return Math.floor(s/60)+'m ago';
  if(s<86400) return Math.floor(s/3600)+'h ago'; return Math.floor(s/86400)+'d ago';
}
// Forgiving search over the config catalog: matches key + description + plain-language
// aliases (EN/NL), tokenised, and ranks the best matches first so a vague query still
// finds the right setting.
function searchCatalog(catalog, query, addedKeys){
  const q=(query||'').trim().toLowerCase(); if(!q) return [];
  const words=q.split(/\s+/).filter(Boolean);
  const scored=[];
  (catalog||[]).forEach(c=>{
    if((addedKeys||[]).indexOf(c.key)>=0) return;
    const key=c.key.toLowerCase(), desc=(c.desc||'').toLowerCase();
    const aliases=(c.aliases||[]).map(a=>a.toLowerCase());
    const hay=key+' '+desc+' '+aliases.join(' ');
    let score=0;
    if(key===q) score+=100;
    if(aliases.indexOf(q)>=0) score+=80;
    if(key.indexOf(q)===0) score+=40;
    if(aliases.some(a=>a.indexOf(q)===0)) score+=30;
    if(key.indexOf(q)>=0) score+=20;
    if(desc.indexOf(q)>=0) score+=12;
    if(aliases.some(a=>a.indexOf(q)>=0)) score+=15;
    // every query word appears somewhere (handles multi-word / vague queries)
    if(words.length && words.every(w=>hay.indexOf(w)>=0)) score+=10;
    if(score>0) scored.push({c,score});
  });
  scored.sort((a,b)=>b.score-a.score);
  return scored.slice(0,8).map(x=>x.c);
}
// merge server config multipliers with optimistic overrides + the edit buffer
function effMultipliers(mults, override, edit){
  override=override||{}; edit=edit||{};
  return (mults||[]).map(m=>{
    const ov=override[m.key]; const eb=edit[m.key];
    const effVal = ov!=null ? parseFloat(ov) : m.val;
    const vNum = isNaN(effVal)?m.val:effVal;
    const displayVal = eb!=null ? eb : (ov!=null ? String(parseFloat(ov)) : m.v2);
    const pct = Math.min(100, Math.round(vNum/(m.max||10)*100));
    const hot = vNum > (m.baseNum||1);
    return Object.assign({}, m, {effVal:vNum, displayVal, pct, hot, v:vNum+'×'});
  });
}
// Active overrides = every setting whose (server value ⊕ pending override) differs
// from its default. Applied search-settings and rate changes both land here.
function buildOverrides(config, override, catalog, self){
  override=override||{}; catalog=catalog||[]; const all=(config&&config.all)||{};
  const norm=(x)=>String(x==null?'':x).trim().toLowerCase().replace(/^(\d+)\.0+$/,'$1');
  const items=[]; const seen={};
  catalog.forEach(c=>{
    const eff = override[c.key]!=null ? String(override[c.key]) : (all[c.key]!=null ? String(all[c.key]) : null);
    if(eff==null) return;
    if(norm(eff)!==norm(c.def)){ seen[c.key]=1; items.push({key:c.key, value:eff, def:c.def, file:c.file, desc:c.desc||''}); }
  });
  Object.keys(override).forEach(k=>{ if(seen[k])return; const c=catalog.find(x=>x.key===k)||{}; if(norm(override[k])!==norm(c.def)) items.push({key:k, value:String(override[k]), def:c.def||'', file:c.file||'gus', desc:c.desc||''}); });
  return items.map(o=>Object.assign({}, o, {reset:()=>self.removeOverride(o.key,o.file,o.def||'1.0')}));
}
function parseIniLines(ini){
  return (ini||'').split('\n').filter(l=>l.trim().length).slice(0,400).map(l=>{
    if(/^\s*[;#]/.test(l)) return {isSec:false, k:'', v:l.trim(), kColor:'#5C6979', vColor:'#5C6979'};
    if(/^\s*\[.*\]\s*$/.test(l)) return {isSec:true, k:'', v:l.trim(), kColor:'#FF7A2E', vColor:'#FF7A2E'};
    const i=l.indexOf('='); if(i<0) return {isSec:false, k:'', v:l, kColor:'#93A0B2', vColor:'#93A0B2'};
    const k=l.slice(0,i), v=l.slice(i+1);
    const isNum=/^-?\d+(\.\d+)?$/.test(v.trim()); const isBool=/^(true|false)$/i.test(v.trim());
    return {isSec:false, k, v, kColor:'#93A0B2', vColor: isNum?'#37D3C3':(isBool?'#8C7BF7':'#E7ECF3')};
  });
}

class Component extends DCLogic {
  rootRef = React.createRef();
  logRef = React.createRef();
  state = this.build();
  build(){
    return {
      view:'overview', sel:'extinction', now:new Date(),
      live:{connected:false, error:null, host:null, instances:[], feed:[], updatedAt:0},
      lines:[], consoleFilter:'all', consoleTab:'extinction', consoleSearch:'',
      settingsTab:'general', palette:false, toasts:[], rconBusy:false, update:null, rconInput:'',
      catalog:[], cfgQuery:'', cfgAdded:[], schedule:[], auditLog:[], cfgFile:null, backupList:[], selBkpName:null, addMap:null, newTask:null,
      cfgOverride:{}, notifications:[], notifOpen:false, notifReadTs:0, pendingStatus:{}, cfgEdit:{}, platformOverride:null, computeDraft:null, computeOpen:false,
      confirmDelete:null, editWorld:null, cfgDraft:''
    };
  }
  componentDidMount(){
    this.applyTheme();
    this.refreshState();
    this.ensureCatalog(); setTimeout(()=>{ this.loadSchedule(); this.loadAudit(); }, 2500);
    this._t=setInterval(()=>this.refreshState(), 4000);
    this._c=setInterval(()=>this.setState({now:new Date()}),1000);
    this._lg=setInterval(()=>{ if(this.state.view==='console') this.refreshConsole(); }, 5000);
    this._key=(e)=>{ if((e.metaKey||e.ctrlKey)&&(e.key==='k'||e.key==='K')){ e.preventDefault(); this.setState(s=>({palette:!s.palette})); } else if(e.key==='Escape'){ this.setState({palette:false}); } };
    window.addEventListener('keydown',this._key);
  }
  componentWillUnmount(){ clearInterval(this._t); clearInterval(this._c); clearInterval(this._lg); window.removeEventListener('keydown',this._key); }
  componentDidUpdate(){ this.applyTheme(); const l=this.logRef.current; if(l&&this.state.view==='console'){ l.scrollTop=l.scrollHeight; } }
  applyTheme(){
    const el=this.rootRef.current; if(!el) return;
    const acc=this.props.accent||'#FF7A2E'; el.style.setProperty('--ember',acc);
    const map={compact:['12px','11px','12px'],balanced:['18px','16px','14px'],spacious:['24px','22px','16px']};
    const d=map[this.props.density]||map.balanced;
    el.style.setProperty('--pad',d[0]); el.style.setProperty('--gap',d[1]); el.style.setProperty('--radius',d[2]);
  }

  refreshState(){
    api('/api/state').then(live=>{ if(live && !live.error===false){} this.setState({live:live||this.state.live}); })
      .catch(e=>this.setState(s=>({live:Object.assign({},s.live,{connected:false,error:String(e)})})));
  }
  refreshConsole(){
    const id=this.state.consoleTab;
    api('/api/console/'+id).then(r=>{ if(r&&r.lines){ this.setState({lines:r.lines.map(t=>({t:classifyLog(t),txt:t}))}); } }).catch(()=>{});
  }
  toast(msg,color){ const id=Date.now()+Math.random(); this.setState(s=>({toasts:s.toasts.concat([{id,msg,color:color||'#FF7A2E'}]).slice(-4)})); setTimeout(()=>this.setState(s=>({toasts:s.toasts.filter(t=>t.id!==id)})),3600); }
  // notify = toast + add to the notifications bell
  notify(msg,color){ const id=Date.now()+Math.random(); this.setState(s=>({notifications:[{id,msg,ts:Date.now(),color:color||'#5AA9FF'}].concat(s.notifications||[]).slice(0,40)})); this.toast(msg,color); }
  // opening the panel marks everything read (badge clears); items stay listed until dismissed
  toggleNotif(){ this.setState(s=>({notifOpen:!s.notifOpen, notifReadTs: !s.notifOpen ? Date.now() : s.notifReadTs})); }
  clearNotif(){ this.setState({notifications:[], notifOpen:false}); }
  dismissNotif(id){ this.setState(s=>({notifications:(s.notifications||[]).filter(n=>n.id!==id)})); }

  setView(v){ this.setState({view:v}); if(v==='console') this.refreshConsole();
    if(v==='settings'){ this.ensureCatalog(); this.loadSchedule(); this.loadAudit(); }
    if(v==='backups'){ this.loadBackups(); this.loadSchedule(); } }
  sel(id){ this.setState({sel:id,view:'instance',computeOpen:false,computeDraft:null}); }
  toggleCompute(){ this.setState(s=>({computeOpen:!s.computeOpen})); }
  closeCompute(){ this.setState({computeOpen:false}); }
  openConsole(id){ this.setState({consoleTab:id,view:'console'}, ()=>this.refreshConsole()); }
  setConsoleTab(id){ this.setState({consoleTab:id}, ()=>this.refreshConsole()); }
  setFilter(f){ this.setState({consoleFilter:f}); }
  onConsoleSearch(e){ this.setState({consoleSearch:e.target.value}); }
  setStab(t){ this.setState({settingsTab:t}); if(t==='schedule') this.loadSchedule(); if(t==='audit') this.loadAudit(); if(t==='files') this.loadConfigFile('gus'); }

  // send an RCON command and append the response to the console
  sendRcon(id, cmd){
    if(!cmd) return;
    this.setState(s=>({lines:s.lines.concat([{t:'rcon',txt:'[RCON] → '+cmd}]).slice(-300)}));
    api('/api/rcon',{method:'POST',body:JSON.stringify({id:id||this.state.sel, command:cmd})})
      .then(r=>{
        if(r.ok){ const out=(r.output||'').trim(); this.setState(s=>({lines:s.lines.concat((out||'(ok, no output)').split('\n').map(t=>({t:'ok',txt:t}))).slice(-300)})); this.notify((out?out.replace(/\n/g,' ').slice(0,60):'Sent · '+cmd.split(' ')[0]),'#37D67A'); }
        else { const er=r.error||'failed'; this.setState(s=>({lines:s.lines.concat([{t:'error',txt:'[RCON] '+er}]).slice(-300)})); this.notify('RCON failed: '+er.slice(0,50),'#FF5B5B'); }
      }).catch(e=>this.toast('RCON error: '+e,'#FF5B5B'));
  }
  onRconInput(e){ this.setState({rconInput:e.target.value}); }
  onRconKey(e){ if(e.key==='Enter'){ e.preventDefault(); this.sendRconInput(); } }
  sendRconInput(){ const cmd=(this.state.rconInput||'').trim(); if(!cmd) return; const id=this.state.view==='console'?this.state.consoleTab:this.state.sel; this.sendRcon(id, cmd); this.setState({rconInput:''}); }
  instAction(id, action, label){
    const optim = action==='stop'?'stopped':((action==='start'||action==='restart')?'starting':null);
    if(optim) this.setState(s=>({pendingStatus:Object.assign({},s.pendingStatus,{[id]:{status:optim, at:Date.now()}})}));
    this.notify((label||action)+' · '+id, action==='stop'?'#FF5B5B':'#FFB23E');
    api('/api/instance/'+id+'/action',{method:'POST',body:JSON.stringify({action})})
      .then(r=>{ this.notify(r.ok?((label||action)+' done — '+id):((label||action)+' failed'), r.ok?'#37D67A':'#FF5B5B'); setTimeout(()=>this.refreshState(),2000); })
      .catch(e=>this.notify('Action error: '+e,'#FF5B5B'));
  }
  wake(id){ this.instAction(id,'start','Start'); }
  // Save world via the reliable action endpoint. Guard offline servers with a clear
  // message instead of a confusing RCON-connection error.
  saveWorld(id){
    id=id||this.state.sel;
    const inst=((this.state.live||{}).instances||[]).find(m=>m.id===id);
    if(inst && inst.status!=='running'){ this.notify('Server is offline — start '+(inst.name||id)+' first, then save','#FFB23E'); return; }
    this.notify('Saving world · '+id,'#37D3C3');
    api('/api/instance/'+id+'/action',{method:'POST',body:JSON.stringify({action:'save'})})
      .then(r=>this.notify(r.ok?('World saved · '+id):('Save failed: '+((r&&r.error)||'unknown')), r.ok?'#37D67A':'#FF5B5B'))
      .catch(e=>this.notify('Save error: '+e,'#FF5B5B'));
  }

  // real SteamCMD update check + apply
  openUpdate(id){
    id=id||this.state.sel;
    this.setState({update:{id, phase:'checking'}});
    api('/api/update/'+id).then(r=>{
      if(!r || r.ok===false){ this.setState(s=>s.update?{update:Object.assign({},s.update,{phase:'error',error:(r&&r.error)||'check failed'})}:null); return; }
      this.setState(s=>s.update?{update:Object.assign({},s.update,{installed:r.installed, latest:r.latest, updateAvailable:r.updateAvailable,
        phase: r.updateAvailable?'ready':(r.latest?'uptodate':'error'), error: r.latest?null:(r.latestErr||'Could not reach SteamCMD to check the latest build')})}:null);
    }).catch(e=>this.setState(s=>s.update?{update:Object.assign({},s.update,{phase:'error',error:String(e)})}:null));
  }
  closeUpdate(){ this.setState({update:null}); }
  applyUpdate(){
    const id=this.state.update&&this.state.update.id; if(!id) return;
    this.setState(s=>({update:Object.assign({},s.update,{phase:'applying'})}));
    this.toast('Update started — server saves & restarts','#5AA9FF');
    api('/api/update/'+id+'/apply',{method:'POST',body:JSON.stringify({})}).then(r=>{
      this.setState(s=>s.update?{update:Object.assign({},s.update,{phase:r.ok?'done':'error',error:r.ok?null:(r.error||'apply failed')})}:null);
      setTimeout(()=>this.refreshState(),3000);
    }).catch(e=>this.setState(s=>s.update?{update:Object.assign({},s.update,{phase:'error',error:String(e)})}:null));
  }

  // ---- Add map ----
  openAddMap(){
    this.setState({addMap:{open:true, busy:false, error:null, available:[], form:{display:'',internal:'',sessionName:'',gamePort:'',queryPort:'',rconPort:'',maxPlayers:'70',adminPassword:'',serverPassword:'',cores:'',ramGB:''}}});
    api('/api/maps/available').then(r=>{
      const av=(r&&r.available)||[]; const p=(r&&r.ports)||{};
      this.setState(s=>s.addMap?{addMap:Object.assign({},s.addMap,{available:av, form:Object.assign({},s.addMap.form,{gamePort:String(p.gamePort||7777),queryPort:String(p.queryPort||27015),rconPort:String(p.rconPort||27020)})})}:null);
    }).catch(()=>{});
  }
  closeAddMap(){ this.setState({addMap:null}); }
  setAddField(field, val){ this.setState(s=>{ const f=Object.assign({},s.addMap.form,{[field]:val});
    if(field==='display'){ const m=(s.addMap.available||[]).find(x=>x.display===val); if(m){ f.internal=m.internal; if(!f.sessionName) f.sessionName='Haven - '+val; } }
    return {addMap:Object.assign({},s.addMap,{form:f})}; }); }
  submitAddMap(){
    const f=this.state.addMap.form;
    if(!f.display||!f.internal){ this.setState(s=>({addMap:Object.assign({},s.addMap,{error:'Pick a map'})})); return; }
    if(!f.adminPassword){ this.setState(s=>({addMap:Object.assign({},s.addMap,{error:'Admin password required'})})); return; }
    this.setState(s=>({addMap:Object.assign({},s.addMap,{busy:true,error:null})}));
    api('/api/maps',{method:'POST',body:JSON.stringify(f)}).then(r=>{
      if(r.ok){ const fw=r.forward; let msg='World "'+f.display+'" created';
        if(fw&&fw.ok) msg+=' · internet port '+fw.wanPort+' opened';
        else if(fw&&!fw.ok) msg+=' · port-forward failed ('+(fw.error||'')+')';
        this.notify(msg, (fw&&!fw.ok)?'#FFB23E':'#37D67A'); this.setState({addMap:null}); setTimeout(()=>this.refreshState(),1500); }
      else this.setState(s=>s.addMap?{addMap:Object.assign({},s.addMap,{busy:false,error:r.error||'Create failed'})}:null);
    }).catch(e=>this.setState(s=>s.addMap?{addMap:Object.assign({},s.addMap,{busy:false,error:String(e)})}:null));
  }

  // ---- config search / check / apply ----
  ensureCatalog(){ if(this._catalogLoaded) return; this._catalogLoaded=true; api('/api/config-catalog').then(r=>this.setState({catalog:(r&&r.catalog)||[]})).catch(()=>{}); }
  validateCfg(entry, raw){
    const v=(raw==null?entry.def:String(raw)).trim();
    if(v==='') return {status:'invalid',msg:'Value required'};
    if(entry.type==='custom'){ return {status:'valid',msg:'custom — not schema-checked'}; }
    if(entry.type==='bool'){ return /^(true|false)$/i.test(v)?{status:'valid',msg:'Valid boolean'}:{status:'invalid',msg:'Must be True or False'}; }
    const num=Number(v);
    if(!isFinite(num)) return {status:'invalid',msg:'Not a number'};
    if(entry.type==='int' && !Number.isInteger(num)) return {status:'invalid',msg:'Must be a whole number'};
    if(entry.min!=null && num<entry.min) return {status:'invalid',msg:'Below minimum ('+entry.min+')'};
    if(entry.max!=null && num>entry.max) return {status:'invalid',msg:'Above maximum ('+entry.max+')'};
    return {status:'valid',msg:'Valid · '+entry.min+'–'+entry.max};
  }
  onCfgSearch(e){ this.setState({cfgQuery:e.target.value}); }
  cfgAdd(entry){ if((this.state.cfgAdded||[]).some(a=>a.key===entry.key)){ this.toast(entry.key+' already added','#FFB23E'); this.setState({cfgQuery:''}); return; }
    const row=Object.assign({},entry,{value:entry.def},this.validateCfg(entry,entry.def)); this.setState(s=>({cfgAdded:(s.cfgAdded||[]).concat([row]), cfgQuery:''})); }
  // add ANY setting that isn't in the built-in catalog (value not schema-checked)
  cfgAddCustom(file){ const key=(this.state.cfgQuery||'').trim();
    if(!/^[A-Za-z0-9_]+$/.test(key)){ this.toast('Key: letters, numbers, underscore only','#FF5B5B'); return; }
    if((this.state.cfgAdded||[]).some(a=>a.key===key)){ this.toast(key+' already added','#FFB23E'); this.setState({cfgQuery:''}); return; }
    const isGame=file==='game';
    const row={key, file:isGame?'game':'gus', sec:isGame?'GameMode':'ServerSettings', type:'custom', def:'', desc:'custom setting ('+(isGame?'Game.ini':'GameUserSettings.ini')+')', value:'', status:'invalid', msg:'Value required'};
    this.setState(s=>({cfgAdded:(s.cfgAdded||[]).concat([row]), cfgQuery:''})); }
  cfgEdit(key,val){ this.setState(s=>({cfgAdded:(s.cfgAdded||[]).map(a=>a.key===key?Object.assign({},a,{value:val},this.validateCfg(a,val)):a)})); }
  cfgRemove(key){ this.setState(s=>({cfgAdded:(s.cfgAdded||[]).filter(a=>a.key!==key)})); }
  cfgApply(a){ if(a.status!=='valid'){ this.toast('Fix the value first','#FF5B5B'); return; }
    this.setState(s=>({cfgOverride:Object.assign({},s.cfgOverride,{[a.key]:String(a.value)})}));  // optimistic → shows in Active overrides
    this.notify(a.key+' → '+a.value,'#37D67A'); this.cfgRemove(a.key);
    api('/api/config/'+this.state.sel+'/set',{method:'POST',body:JSON.stringify({key:a.key,value:a.value,file:a.file})}).then(r=>{
      if(!r.ok){ this.setState(s=>{ const o=Object.assign({},s.cfgOverride); delete o[a.key]; return {cfgOverride:o}; }); this.notify('Apply failed: '+(r.error||''),'#FF5B5B'); }
      this._cfgReloadSoon();
    }).catch(e=>this.notify('Apply error: '+e,'#FF5B5B')); }

  // ---- audit export ----
  exportAudit(){
    const rows=(this.state.auditLog||[]).map(a=>['','','',''].map((_,i)=>{ const v=[new Date(a.ts).toISOString(),a.who,a.action,a.target||''][i]; return '"'+String(v).replace(/"/g,'""')+'"'; }).join(','));
    const csv='timestamp,actor,command,target\n'+rows.join('\n');
    try{ const blob=new Blob([csv],{type:'text/csv'}); const url=URL.createObjectURL(blob); const a=document.createElement('a'); a.href=url; a.download='ark-audit.csv'; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url); this.toast('Audit exported','#37D67A'); }catch(e){ this.toast('Export failed','#FF5B5B'); }
  }
  // ---- schedule tasks ----
  openNewTask(){ this.setState({newTask:{open:true, taskType:'restart', startDay:'*', startTime:'04:00', endDay:'0', endTime:'23:59', message:'Server restarting soon — wrap up!', rateKey:'', rateValue:'2', rateFile:'gus', rates:[], restart:false, busy:false, error:null}}); }
  closeNewTask(){ this.setState({newTask:null}); }
  setTask(field,val){ this.setState(s=>({newTask:Object.assign({},s.newTask,{[field]:val})})); }
  // multi-rate event: add/remove/edit the list of rates that fire together
  addRate(key,file){ if(!/^[A-Za-z0-9_]+$/.test(key||'')) return; this.setState(s=>{ const rs=(s.newTask.rates||[]); if(rs.some(r=>r.key===key)) return {}; return {newTask:Object.assign({},s.newTask,{rates:rs.concat([{key, file:(file==='game'?'game':'gus'), value:'2'}]), error:null})}; }); }
  // typing a key: auto-pick its config file when it's a setting we recognise, so the
  // user rarely has to think about GUS vs Game.
  onRateKeyType(e){ const val=e.target.value; const c=(this.state.catalog||[]).find(x=>x.key.toLowerCase()===String(val).trim().toLowerCase());
    this.setState(s=>({newTask:Object.assign({},s.newTask, {rateKey:val}, c?{rateFile:c.file}:{})})); }
  addRateFromInput(){ const t=this.state.newTask; if(!t) return; const k=(t.rateKey||'').trim();
    if(!/^[A-Za-z0-9_]+$/.test(k)){ this.setState(s=>({newTask:Object.assign({},s.newTask,{error:'Type a valid setting key (letters/numbers/underscore)'})})); return; }
    this.addRate(k, t.rateFile); this.setState(s=>({newTask:Object.assign({},s.newTask,{rateKey:''})})); }
  removeRateAt(i){ this.setState(s=>({newTask:Object.assign({},s.newTask,{rates:(s.newTask.rates||[]).filter((_,j)=>j!==i)})})); }
  setRateValueAt(i,val){ this.setState(s=>({newTask:Object.assign({},s.newTask,{rates:(s.newTask.rates||[]).map((r,j)=>j===i?Object.assign({},r,{value:val}):r)})})); }
  submitNewTask(){ const t=this.state.newTask; if(!t) return; let body;
    if(t.taskType==='multiplier'){
      const inst=((this.state.live||{}).instances||[]).find(m=>m.id===this.state.sel)||{}; const all=((inst.config||{}).all)||{};
      const rates=(t.rates||[]).map(r=>({key:r.key, value:String(r.value), file:r.file, revertValue:(all[r.key]!=null?String(all[r.key]):'1.0')}));
      if(!rates.length){ this.setState(s=>({newTask:Object.assign({},s.newTask,{error:'Add at least one rate to the event'})})); return; }
      const bad=rates.find(r=>!/^-?\d+(\.\d+)?$/.test(r.value));
      if(bad){ this.setState(s=>({newTask:Object.assign({},s.newTask,{error:'Value for '+bad.key+' must be a number'})})); return; }
      body={taskType:'multiplier', cron:cronFromDT(t.startDay,t.startTime), endCron:cronFromDT(t.endDay,t.endTime), message:t.message, rates, restart:!!t.restart};
    } else { body={taskType:t.taskType, cron:cronFromDT(t.startDay,t.startTime), message:t.message, restart:!!t.restart}; }
    this.setState(s=>({newTask:Object.assign({},s.newTask,{busy:true,error:null})}));
    api('/api/schedule/'+this.state.sel,{method:'POST',body:JSON.stringify(body)}).then(r=>{ if(r.ok){ const base=t.taskType==='multiplier'?'Rate event scheduled':'Scheduled task added'; this.notify(base+(r.verified?' · verified in crontab ✓':' · added (verify pending)'), r.verified?'#37D67A':'#FFB23E'); this.setState({newTask:null}); this.loadSchedule(); } else this.setState(s=>s.newTask?{newTask:Object.assign({},s.newTask,{busy:false,error:r.error||'failed'})}:null); }).catch(e=>this.setState(s=>s.newTask?{newTask:Object.assign({},s.newTask,{busy:false,error:String(e)})}:null)); }
  deleteTask(match){ this.toast('Removing task…','#FFB23E'); api('/api/schedule/'+this.state.sel,{method:'DELETE',body:JSON.stringify({match})}).then(r=>{ this.toast(r.ok?'Task removed':'Remove failed', r.ok?'#37D67A':'#FF5B5B'); this.loadSchedule(); }).catch(e=>this.toast('Error: '+e,'#FF5B5B')); }
  // ---- interactive rates / rules ----
  applyRate(key,file,value){ if(!key) return;
    // optimistic: update the UI instantly, then persist (revert on failure)
    this.setState(s=>({cfgOverride:Object.assign({},s.cfgOverride,{[String(key)]:String(value)})}));
    this.notify(key+' → '+value,'#37D67A');
    api('/api/config/'+this.state.sel+'/set',{method:'POST',body:JSON.stringify({key,value:String(value),file:file||'gus'})}).then(r=>{
      if(!r.ok){ this.setState(s=>{ const o=Object.assign({},s.cfgOverride); delete o[String(key)]; return {cfgOverride:o}; }); this.notify('Failed to apply '+key+': '+(r.error||''),'#FF5B5B'); }
      this._cfgReloadSoon();
    }).catch(e=>this.notify('Error applying '+key,'#FF5B5B')); }
  setGameMode(pve){ this.applyRate('ServerPVE','gus',pve?'True':'False'); }
  // crossplay per platform = real -ServerPlatform=PC+XSX+PS5+WINGDK launch arg; applies on restart
  togglePlatform(tok, cur){
    cur = Object.assign({PC:true,XSX:true,PS5:true,WINGDK:true}, cur||{});
    const next = Object.assign({}, cur, {[tok]: cur[tok]===false});
    const list = ['PC','XSX','PS5','WINGDK'].filter(t=>next[t]!==false);
    if(list.length===0){ this.notify('At least one platform must stay enabled','#FFB23E'); return; }
    this.setState({platformOverride:next});
    const nm={PC:'PC',XSX:'Xbox',PS5:'PS5',WINGDK:'Windows'};
    this.notify((next[tok]===false?'Blocked ':'Allowed ')+nm[tok]+' · applies on restart', next[tok]===false?'#FFB23E':'#37D67A');
    api('/api/config/'+this.state.sel+'/platforms',{method:'POST',body:JSON.stringify({list})}).then(r=>{
      if(!r.ok){ this.setState({platformOverride:cur}); this.notify('Platform change failed: '+(r.error||''),'#FF5B5B'); }
    }).catch(e=>{ this.setState({platformOverride:cur}); this.notify('Platform error','#FF5B5B'); }); }
  _cfgReloadSoon(){ clearTimeout(this._cfgT); this._cfgT=setTimeout(()=>this.refreshState(),1800); }
  // multiplier inputs: track locally while typing, apply on blur / Enter
  onRateInput(key,e){ const v=e.target.value; this.setState(s=>({cfgEdit:Object.assign({},s.cfgEdit,{[key]:v})})); }
  commitRate(key,file){ const v=this.state.cfgEdit[key]; if(v==null) return; const o=Object.assign({},this.state.cfgEdit); delete o[key]; this.setState({cfgEdit:o}); const n=parseFloat(v); if(v!==''&&!isNaN(n)) this.applyRate(key,file,n); }
  // --- per-world compute allocation (CPU cores + RAM ceiling, cgroup-enforced) ---
  onComputeCpu(e){ const v=parseFloat(e.target.value); if(isNaN(v)) return; this.setState(s=>({computeDraft:Object.assign({},s.computeDraft,{cores:v})})); }
  onComputeRam(e){ const v=Math.round(parseFloat(e.target.value)); if(isNaN(v)) return; this.setState(s=>({computeDraft:Object.assign({},s.computeDraft,{ram:v})})); }
  applyCompute(){
    const d=this.state.computeDraft; if(!d) return;   // nothing changed → greyed no-op click does nothing
    const id=this.state.sel;
    const live=this.state.live||{}; const inst=((live.instances||[]).find(i=>i.id===id))||{}; const host=live.host||{};
    const vmCores=Math.max(1,Math.round(host.cpus||4)), vmRam=host.memTotal?Math.max(1,Math.floor(host.memTotal*1e9/1073741824)):Math.max(1,Math.floor(inst.ramAlloc||16));
    const cores=(d.cores!=null)?d.cores:(inst.coresAlloc!=null?inst.coresAlloc:vmCores);
    const ram=(d.ram!=null)?d.ram:(inst.ramLimitGB!=null?inst.ramLimitGB:vmRam);
    // mirror the backend OOM guard for instant feedback: never shrink RAM below a running world's live use
    if(inst.status==='running' && inst.ramLiveGB!=null && inst.ramLiveGB>0.1 && ram < inst.ramLiveGB*1.15){
      this.notify('RAM '+ram+' GB is below live use ('+inst.ramLiveGB+' GB) — stop the world first or raise the limit','#FFB23E'); return;
    }
    this.setState(s=>({computeDraft:Object.assign({},s.computeDraft,{busy:true})}));
    this.toast('Applying compute limits…','#37D3C3');
    api('/api/instance/'+id+'/resources',{method:'POST',body:JSON.stringify({cores,ramGB:ram})}).then(r=>{
      if(r&&r.ok){ this.notify('Compute set: '+r.cores+' vCPU · '+r.ramGB+' GB','#37D67A');
        // optimistically fold the applied caps into live state so the slider holds its value (no snap-back)
        this.setState(s=>{ const lv=s.live||{}; const insts=(lv.instances||[]).map(i=> i.id===id?Object.assign({},i,{coresAlloc:r.cores,ramLimitGB:r.ramGB}):i); return {live:Object.assign({},lv,{instances:insts}), computeDraft:null}; });
        setTimeout(()=>this.refreshState(),1500);
      } else { this.notify('Compute apply failed: '+((r&&r.error)||'unknown'),'#FF5B5B'); this.setState(s=>({computeDraft:Object.assign({},s.computeDraft,{busy:false})})); }
    }).catch(e=>{ this.notify('Compute error: '+e,'#FF5B5B'); this.setState(s=>({computeDraft:Object.assign({},s.computeDraft,{busy:false})})); });
  }
  resetCompute(){ this.setState({computeDraft:null}); }
  onRateKey(e){ if(e.key==='Enter'&&e.target&&e.target.blur) e.target.blur(); }
  // clear an applied override (reset to what's on the server / default) — visible in the overrides list
  removeOverride(key,file,def){ this.applyRate(key,file,def); }

  // ---- settings data loaders ----
  loadSchedule(){ api('/api/schedule/'+this.state.sel).then(r=>this.setState({schedule:(r&&r.jobs)||[]})).catch(()=>{}); }
  loadAudit(){ api('/api/audit').then(r=>this.setState({auditLog:(r&&r.audit)||[]})).catch(()=>{}); }
  loadConfigFile(which){ api('/api/config/'+this.state.sel+'?file='+(which||'gus')).then(r=>this.setState({cfgFile:{which:which||'gus',path:r.path||'',ini:r.ini||''}, cfgDraft:(r.ini||'')})).catch(()=>{}); }
  onCfgDraft(e){ this.setState({cfgDraft:e.target.value}); }
  saveCfgRaw(){ const cf=this.state.cfgFile; if(!cf) return; const nm=cf.which==='game'?'Game.ini':'GameUserSettings.ini';
    this.toast('Saving '+nm+'…','#37D3C3');
    api('/api/config/'+this.state.sel+'/raw',{method:'POST',body:JSON.stringify({file:cf.which,content:this.state.cfgDraft})}).then(r=>{
      this.notify(r.ok?(nm+' saved · applies on restart'):('Save failed: '+((r&&r.error)||'')), r.ok?'#37D67A':'#FF5B5B'); if(r.ok) this.loadConfigFile(cf.which);
    }).catch(e=>this.toast('Save error: '+e,'#FF5B5B')); }
  // Apply the rate-event's setting immediately, so you can confirm it works before scheduling.
  testRateNow(){ const t=this.state.newTask; if(!t) return;
    let rates=(t.rates||[]).slice(); const k=(t.rateKey||'').trim();
    if(/^[A-Za-z0-9_]+$/.test(k) && !rates.some(r=>r.key===k)) rates=rates.concat([{key:k, file:t.rateFile, value:t.rateValue}]);
    if(!rates.length){ this.setState(s=>({newTask:Object.assign({},s.newTask,{error:'Add a rate to test'})})); return; }
    const bad=rates.find(r=>isNaN(parseFloat(r.value)));
    if(bad){ this.setState(s=>({newTask:Object.assign({},s.newTask,{error:'Value for '+bad.key+' must be numeric'})})); return; }
    this.setState(s=>({newTask:Object.assign({},s.newTask,{error:null})}));
    rates.forEach(r=>this.applyRate(r.key, r.file, parseFloat(r.value))); this.notify('Test: applied '+rates.length+' rate(s) now','#37D3C3'); }
  loadBackups(){ api('/api/backups/'+this.state.sel).then(r=>this.setState({backupList:(r&&r.backups)||[]})).catch(()=>{}); }
  createBackup(){ this.toast('Creating snapshot…','#37D3C3'); api('/api/backups/'+this.state.sel+'/create',{method:'POST',body:'{}'}).then(r=>{ this.toast(r.ok?'Snapshot created':'Snapshot failed', r.ok?'#37D67A':'#FF5B5B'); setTimeout(()=>this.loadBackups(),1200); }).catch(e=>this.toast('Snapshot error: '+e,'#FF5B5B')); }
  restoreBackup(name){ if(!name) return;
    this.toast('Restoring — server saves, stops, restores & restarts','#FFB23E');
    api('/api/backups/'+this.state.sel+'/restore',{method:'POST',body:JSON.stringify({name})}).then(r=>{ this.toast(r.ok?'Restore started · watch the console':'Restore failed: '+(r.error||''), r.ok?'#37D67A':'#FF5B5B'); setTimeout(()=>this.refreshState(),2500); }).catch(e=>this.toast('Restore error: '+e,'#FF5B5B')); }

  // ---- destructive-confirm modal (backups + worlds) ----
  askDeleteBackup(name){ if(!name) return; this.setState({confirmDelete:{kind:'backup', name, busy:false, error:null}}); }
  askDeleteWorld(display){ if(!display) return; this.setState({confirmDelete:{kind:'world', display, busy:false, error:null}}); }
  closeConfirm(){ this.setState({confirmDelete:null}); }
  confirmDeleteDo(){
    const c=this.state.confirmDelete; if(!c) return;
    this.setState(s=>({confirmDelete:Object.assign({},s.confirmDelete,{busy:true,error:null})}));
    if(c.kind==='backup'){
      api('/api/backups/'+this.state.sel,{method:'DELETE',body:JSON.stringify({name:c.name})}).then(r=>{
        if(r.ok){ this.toast('Snapshot deleted','#37D67A'); this.setState({confirmDelete:null, selBkpName:null}); setTimeout(()=>this.loadBackups(),700); }
        else this.setState(s=>s.confirmDelete?{confirmDelete:Object.assign({},s.confirmDelete,{busy:false,error:(r&&r.error)||'delete failed'})}:null);
      }).catch(e=>this.setState(s=>s.confirmDelete?{confirmDelete:Object.assign({},s.confirmDelete,{busy:false,error:String(e)})}:null));
    } else if(c.kind==='world'){
      api('/api/maps/'+encodeURIComponent(c.display),{method:'DELETE'}).then(r=>{
        if(r.ok){ const fw=r.forward; this.notify('World "'+c.display+'" deleted'+((fw&&fw.ok&&fw.removed)?' · internet port closed':''),'#37D67A'); this.setState({confirmDelete:null}); setTimeout(()=>this.refreshState(),1200); }
        else this.setState(s=>s.confirmDelete?{confirmDelete:Object.assign({},s.confirmDelete,{busy:false,error:(r&&r.error)||'delete failed'})}:null);
      }).catch(e=>this.setState(s=>s.confirmDelete?{confirmDelete:Object.assign({},s.confirmDelete,{busy:false,error:String(e)})}:null));
    }
  }

  // ---- edit world (session name + admin/server password) ----
  openEditWorld(){
    const s=this.state; const insts=(s.live||{}).instances||[]; const inst=insts.find(m=>m.id===s.sel)||insts[0]||{};
    const sess=((inst.config||{}).sessionName)||inst.name||'';
    this.setState({editWorld:{open:true, busy:false, error:null, name:inst.name||s.sel, form:{sessionName:sess, adminPassword:'', serverPassword:''}}});
  }
  closeEditWorld(){ this.setState({editWorld:null}); }
  setEditField(field,val){ this.setState(s=>({editWorld:Object.assign({},s.editWorld,{form:Object.assign({},s.editWorld.form,{[field]:val})})})); }
  submitEditWorld(){
    const w=this.state.editWorld; if(!w) return; const f=w.form;
    if((!f.sessionName||!f.sessionName.trim()) && !f.adminPassword && !f.serverPassword){ this.setState(s=>({editWorld:Object.assign({},s.editWorld,{error:'Nothing to change'})})); return; }
    this.setState(s=>({editWorld:Object.assign({},s.editWorld,{busy:true,error:null})}));
    const body={sessionName:f.sessionName};
    if(f.adminPassword) body.adminPassword=f.adminPassword;
    if(f.serverPassword) body.serverPassword=f.serverPassword;
    const changingAdmin=!!f.adminPassword;
    const inst=((this.state.live||{}).instances||[]).find(m=>m.id===this.state.sel);
    const running=inst&&inst.status==='running';
    api('/api/instance/'+this.state.sel+'/settings',{method:'POST',body:JSON.stringify(body)}).then(r=>{
      if(r.ok){
        // A password change only activates on restart; warn loudly so live RCON doesn't silently break.
        if(changingAdmin && running) this.notify('Admin password changed — restart '+(inst.name||this.state.sel)+' now to activate it (live RCON pauses until you do)','#FFB23E');
        else this.notify('World settings updated'+(changingAdmin?' · restart to activate the new password':' · applies on restart'),'#37D67A');
        this.setState({editWorld:null}); setTimeout(()=>this.refreshState(),1200); }
      else this.setState(s=>s.editWorld?{editWorld:Object.assign({},s.editWorld,{busy:false,error:(r&&r.error)||'update failed'})}:null);
    }).catch(e=>this.setState(s=>s.editWorld?{editWorld:Object.assign({},s.editWorld,{busy:false,error:String(e)})}:null));
  }

  tog(on,color){ color=color||'#FF7A2E'; return {track:{width:'34px',height:'20px',borderRadius:'99px',flex:'none',position:'relative',background:on?color:'var(--line2)',display:'inline-block'}, knob:{position:'absolute',top:'2px',left:on?'16px':'2px',width:'16px',height:'16px',borderRadius:'99px',background:'#fff'}}; }

  navStyle(active){ return {display:'flex',alignItems:'center',gap:'11px',padding:'9px 11px',borderRadius:'10px',border:'1px solid '+(active?'var(--line2)':'transparent'),background:active?'linear-gradient(90deg,var(--ember-soft),transparent)':'transparent',color:active?'var(--text)':'var(--dim)',font:'inherit',fontSize:'13px',fontWeight:active?'700':'500',cursor:'pointer',width:'100%',position:'relative'}; }

  renderVals(){
    const s=this.state; const v=s.view; const live=s.live||{};
    const rawInsts = live.instances||[];
    const insts = rawInsts.map(m=>{
      let st = m.status||'unknown';
      const pend = (s.pendingStatus||{})[m.id];
      if(pend){ const age=Date.now()-pend.at;
        if(pend.status==='starting' && age<75000 && st!=='running') st='starting';
        else if(pend.status==='starting' && age<50000) st='starting'; // ARK boots ~40-60s even when systemd says active
        else if(pend.status==='stopped' && age<90000 && st!=='stopped' && st!=='crashed') st='stopped';
      }
      const sm=STATUS[st]||STATUS.unknown;
      const hist = m.hist||{cpu:[],ram:[]};
      const sp = spark(hist.cpu||[],120,52);
      const cpu = m.cpuPct||0;
      const running = st==='running'; const starting = st==='starting';
      const unprov = st==='unprovisioned';
      return Object.assign({}, m, {
        st, statusLabel:sm.label,
        isRunning:running, isSleeping:st==='sleeping', isStarting:starting, isStopped:st==='stopped'||st==='crashed', isUnprovisioned:unprov,
        cpuStr: running||starting ? cpu+'%' : '—', cpuColor: cpu>80?'var(--red)':(cpu>60?'var(--amber)':'var(--text)'),
        ramUsed:(m.ramUsed||0).toFixed(1), ramAlloc:m.ramAlloc||16,
        playersStr:(m.players||0)+' / '+(m.max||70), uptime:m.uptime||'—',
        ver:m.ver||'ASA', mods:m.mods||0, hasUpd:false, bootLabel: starting?'starting…':'',
        emblemStyle:{width:'44px',height:'44px',borderRadius:'11px',flex:'none',display:'flex',alignItems:'center',justifyContent:'center',fontWeight:'800',fontSize:'13px',letterSpacing:'.02em',background:m.emblem+'1f',color:m.emblem,border:'1px solid '+m.emblem+'44',fontFamily:'JetBrains Mono,monospace'},
        icon:mapIcon(m.map, m.emblem),
        pillStyle:{display:'inline-flex',alignItems:'center',gap:'6px',flex:'none',fontSize:'11px',fontWeight:'700',padding:'4px 10px',borderRadius:'99px',color:sm.c,background:sm.c+'18',border:'1px solid '+sm.c+'3a'},
        dotStyle:{width:'7px',height:'7px',borderRadius:'99px',background:sm.c,boxShadow:'0 0 8px '+sm.c, animation: starting?'pulse 1.2s infinite':'none'},
        gid:'sp-'+m.id, spColor: cpu>80?'#FF5B5B':(m.emblem==='#FF7A2E'?'#FF9E63':'var(--cyan)'), sparkLine:sp.line, sparkArea:sp.area,
        open:()=>this.sel(m.id), console:()=>this.openConsole(m.id), wake:()=>this.wake(m.id), restart:()=>this.instAction(m.id,'restart','Restart'), deploy:()=>this.openAddMap(),
        del:()=>this.askDeleteWorld(m.name)
      });
    });
    const running = insts.filter(i=>i.isRunning).length;
    const totalPlayers = insts.reduce((a,i)=>a+(i.players||0),0);
    const selectedInst = insts.find(i=>i.id===s.sel)||insts[0]||{id:'extinction',name:'Extinction',map:'Extinction',emblem:'#FF7A2E',hist:{cpu:[],ram:[]},ramAlloc:16,max:70};
    const host = live.host||{};

    // selected-instance detail
    const gh = selectedInst.hist||{cpu:[],ram:[]};
    const gcpu=sparkF(gh.cpu||[],620,150); const gram=sparkF(gh.ram||[],620,150);
    const idle=!selectedInst.isRunning && !selectedInst.isStarting;
    const plist = (rawInsts.find(m=>m.id===selectedInst.id)||{}).playerList || (cacheSelPlayers(selectedInst)) || [];
    const selDetail=Object.assign({}, selectedInst, {
      graphCpu:gcpu.line, graphCpuArea:gcpu.area, graphRam:gram.line,
      players: (selectedInst.playerList||[]).map(p=>({name:p.name, tribe:'online', lvl:'—', ping:0, pingColor:'var(--dim)', play:'—', av:(p.name||'?').slice(0,2).toUpperCase(),
        kick:()=>this.sendRcon(selectedInst.id,'KickPlayer '+p.id),
        whisper:()=>this.sendRcon(selectedInst.id,'ServerChatToPlayer "'+(p.name||'')+'" An admin says hi')})),
      playerCount: selectedInst.players||0, max:selectedInst.max||70,
      metrics:[
        {k:'CPU',sub:(selectedInst.coresAlloc!=null?(selectedInst.coresAlloc+' vCPU cap'):'the ARK VM · 4 vCPU'),big:selectedInst.cpuStr,unit:'',pct:idle?0:(parseInt(selectedInst.cpuStr)||0),alloc:'host VM',color:'#37D3C3',flag:null},
        (function(cap,use){ return {k:'Memory',sub:cap+' GB cap',big:use,unit:'GB',pct:Math.round((parseFloat(use)||0)/cap*100),alloc:'of '+cap+' GB',color:'#FF7A2E',flag: idle?'Idle — VM RAM reclaimable':null}; })(selectedInst.ramLimitGB!=null?selectedInst.ramLimitGB:(selectedInst.ramAlloc||16), selectedInst.ramLiveGB!=null?selectedInst.ramLiveGB:selectedInst.ramUsed),
        {k:'Disk',sub:'VM disk',big:host.diskUsed!=null?host.diskUsed:'—',unit:host.diskUsed!=null?'GB':'',pct:host.diskTotal?Math.round(host.diskUsed/host.diskTotal*100):0,alloc:host.diskTotal?('of '+host.diskTotal+' GB'):'—',color:'#8C7BF7',flag:null},
        {k:'Network',sub:'in / out',big:idle?'0':((((host.netin||0)+(host.netout||0))/125000).toFixed(1)),unit:'Mb/s',pct:idle?0:20,alloc:((host.netin||0)/125000).toFixed(1)+' Mb/s in',color:'#37D67A',flag:null}
      ].map(m=>({...m, barStyle:{height:'100%',width:Math.max(2,m.pct)+'%',borderRadius:'99px',background:m.color,transition:'width .5s ease'}})),
      healthColor: selectedInst.isRunning?'var(--green)':(selectedInst.isStarting?'var(--amber)':'var(--blue)'),
      healthLabel: selectedInst.isRunning?'Healthy':(selectedInst.isStarting?'Booting':'Offline'),
      mult: effMultipliers((selectedInst.config||{}).multipliers, s.cfgOverride, {}).map(m=>({...m, valColor:m.hot?'var(--ember)':'var(--text)', barStyle:{height:'100%',width:Math.max(2,m.pct)+'%',borderRadius:'99px',background:m.hot?'linear-gradient(90deg,var(--ember),var(--ember2))':'var(--cyan)'}})),
      modList:[], modUpd:0,
      ruleMode: ((selectedInst.config||{}).rules||{}).mode || '—',
      ruleDifficulty: (selectedInst.config&&selectedInst.config.rules)?((((s.cfgOverride||{}).OverrideOfficialDifficulty)!=null?parseFloat(s.cfgOverride.OverrideOfficialDifficulty):selectedInst.config.rules.difficulty)+' · max wild '+Math.round((((s.cfgOverride||{}).OverrideOfficialDifficulty)!=null?parseFloat(s.cfgOverride.OverrideOfficialDifficulty):selectedInst.config.rules.difficulty)*30)):'—',
      diffFill:(function(){ const d=(((s.cfgOverride||{}).OverrideOfficialDifficulty)!=null?parseFloat(s.cfgOverride.OverrideOfficialDifficulty):(((selectedInst.config||{}).rules||{}).difficulty||1)); const pct=Math.min(100,Math.round(d/10*100)); return {position:'absolute',left:'0',top:'0',bottom:'0',width:pct+'%',borderRadius:'99px',background:'var(--cyan)'}; })(),
      diffKnob:(function(){ const d=(((s.cfgOverride||{}).OverrideOfficialDifficulty)!=null?parseFloat(s.cfgOverride.OverrideOfficialDifficulty):(((selectedInst.config||{}).rules||{}).difficulty||1)); const pct=Math.min(100,Math.round(d/10*100)); return {position:'absolute',top:'50%',left:pct+'%',transform:'translate(-50%,-50%)',width:'14px',height:'14px',borderRadius:'99px',background:'#fff',border:'2px solid var(--cyan)'}; })(),
      ruleTameLimit: (selectedInst.config&&selectedInst.config.rules)?('cap '+selectedInst.config.rules.tameLimit):'—',
      dayTime: (selectedInst.config&&selectedInst.config.sessionName)?selectedInst.config.sessionName:(selectedInst.map||'ASA')
    });

    // console
    const macros=MACROS.map(m=>({label:m.label, run:()=>this.sendRcon(selectedInst.id, m.cmd)}));
    const navDef=[['overview','Overview'],['instance','Instances'],['console','Live Console'],['backups','Backups'],['settings','Settings']];
    const nav=navDef.map(d=>{ const active=v===d[0]; const badge=d[0]==='console'?(live.connected?'live':null):null;
      return {label:d[1], go:()=>this.setView(d[0]), active, style:this.navStyle(active), icon:icn(d[0],19), iconStyle:{color:active?'var(--ember)':'var(--faint)',display:'flex'},
        badge, badgeStyle:{fontSize:'9px',fontWeight:700,letterSpacing:'.08em',textTransform:'uppercase',color:'var(--green)',background:'rgba(55,214,122,.14)',border:'1px solid rgba(55,214,122,.3)',padding:'1px 6px',borderRadius:'5px'} }; });
    const connLabel = live.connected? (running+' running · the ARK VM @ pve') : ('offline · '+(live.error?String(live.error).slice(0,40):'connecting…'));
    const T={overview:['Overview','Extinction cluster · '+connLabel],instance:[selectedInst.name,'Instance control · '+(selectedInst.map||'')],cluster:['Cluster','Single map — cluster not configured'],console:['Live Console','game log + RCON · '+selectedInst.name],backups:['Backups & Snapshots','ark-manager saved worlds'],settings:['Settings','Server configuration'],mobile:['Mobile / PWA','Companion view']};
    const clock=s.now.toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit',second:'2-digit'});
    const date=s.now.toLocaleDateString('en-GB',{weekday:'short',day:'2-digit',month:'short'});
    // Live activity = your recent dashboard actions + server-log events, newest first
    const actionFeed=(s.notifications||[]).slice(0,6).map(n=>({who:'You', action:n.msg, map:'dashboard', type:'sys', ago:relTime(n.ts), _color:n.color}));
    const feed=actionFeed.concat((live.feed||[]).map(f=>({...f, ago:f.ago||'live'}))).slice(0,10).map(f=>({...f, ago:f.ago||'live', dot:{width:'8px',height:'8px',borderRadius:'99px',flex:'none',background:f._color||FEED_DOT[f.type]||'#5AA9FF',boxShadow:'0 0 7px '+(f._color||FEED_DOT[f.type]||'#5AA9FF')}}));
    const tasks=(s.schedule||[]).slice(0,4).map(j=>{ const col={backup:'var(--cyan)',restart:'var(--amber)',healthcheck:'var(--green)',rcon:'var(--violet)',broadcast:'var(--violet)',multiplier:'var(--ember)',task:'var(--blue)'}[j.type]||'var(--blue)'; const ic={backup:'save',restart:'restart',healthcheck:'clock',rcon:'console',broadcast:'bolt',multiplier:'bolt',task:'clock'}[j.type]||'clock';
      return {name:(j.cmd.split('/').pop()||j.type).replace('.sh',''), when:cronHuman(j.cron), in:cronNext(j.cron, s.now), color:col, icon:icn(ic,16,col)}; });

    // host card values (sidebar + overview KPI) — real VM metrics
    const hostName = host.name||'ark';
    const memPct = host.memTotal? Math.round(host.memUsed/host.memTotal*100):0;
    const hostCard = {
      name:hostName, healthy: host.vmStatus==='running',
      ram: (host.memUsed||0)+' / '+(host.memTotal||0)+' GB', ramPct: memPct+'%', ramBarStyle:{height:'100%',width:memPct+'%',borderRadius:'99px',background:'linear-gradient(90deg,var(--ember),var(--ember2))'},
      cpu:(host.cpuPct||0)+'% · 4 vCPU', cpuBarStyle:{height:'100%',width:(host.cpuPct||0)+'%',borderRadius:'99px',background:'linear-gradient(90deg,var(--cyan),#69e3d6)'},
      disk: (host.diskUsed!=null? host.diskUsed+' GB':'—')+(host.diskTotal? ' / '+host.diskTotal+' GB':''),
      memBig:(host.memUsed||0), memTotal:(host.memTotal||0), memPctStr:memPct+'%',
      statusColor: host.vmStatus==='running'?'var(--green)':'var(--red)',
      statusLabel: host.vmStatus==='running'?'VM healthy':'VM '+(host.vmStatus||'unknown'),
      note: live.connected ? (running>0 ? 'Extinction · advertising for join' : 'Extinction · '+((insts[0]||{}).statusLabel||'offline')) : 'connecting to the ARK VM…'
    };
    const provMax = insts.filter(i=>i.provisioned).reduce((a,i)=>a+(i.max||0),0);

    // console view lines
    const consoleView = (function(lines,filter,q){
      const f={all:function(){return true;}, chat:function(l){return l.t==='chat';}, rcon:function(l){return l.t==='rcon'||l.t==='ok';}, join:function(l){return l.t==='join'||l.t==='leave';}, warn:function(l){return l.t==='warn'||l.t==='error';}};
      q=(q||'').toLowerCase();
      return (lines||[]).filter(f[filter]||f.all).filter(function(l){return !q || (l.txt||'').toLowerCase().indexOf(q)>=0;}).map(function(l){
        return {txt:l.txt, tag:(CTAG[l.t]||CTAG.log)[0], tagColor:(CTAG[l.t]||CTAG.log)[1],
          textColor: l.t==='warn'?'#FFCF8A':(l.t==='error'?'#FF9E9E':(l.t==='rcon'?'#FFD0AC':(l.t==='chat'?'#E7ECF3':(l.t==='ok'?'#A9E7C2':'#93A0B2'))))};
      });
    })(s.lines, s.consoleFilter, s.consoleSearch);

    const pclose=()=>this.setState({palette:false});
    const paletteItems=[
      {isHeader:true,label:'Navigate'},
      {label:'Overview',ic:'overview',meta:'screen',act:()=>this.setView('overview')},
      {label:'Live Console',ic:'console',meta:'screen',act:()=>this.setView('console')},
      {label:'Backups',ic:'backups',meta:'screen',act:()=>this.setView('backups')},
      {label:'Settings',ic:'settings',meta:'screen',act:()=>this.setView('settings')},
      {isHeader:true,label:'RCON'},
      {label:'Save world (Extinction)',ic:'save',meta:'rcon',act:()=>this.saveWorld('extinction')},
      {label:'List players',ic:'instance',meta:'rcon',act:()=>this.sendRcon('extinction','ListPlayers')},
      {label:'Broadcast to server…',ic:'bolt',meta:'rcon',act:()=>this.sendRcon('extinction','Broadcast Hello survivors!')}
    ].map(p=>p.isHeader?p:{...p,isItem:true,icon:icn(p.ic,16),go:()=>{p.act();pclose();}});

    const _rules=(selectedInst.config||{}).rules||{}; const _ov=s.cfgOverride||{};
    const effMode = _ov.ServerPVE!=null ? (/^true$/i.test(_ov.ServerPVE)?'PvE':'PvP') : _rules.mode;
    const effThird = _ov.AllowThirdPersonPlayer!=null ? /^true$/i.test(_ov.AllowThirdPersonPlayer) : _rules.thirdPerson;
    const effFlyer = _ov.AllowFlyerCarryPvE!=null ? /^true$/i.test(_ov.AllowFlyerCarryPvE) : _rules.flyerCarry;
    const effPlat = Object.assign({PC:true,XSX:true,PS5:true,WINGDK:true}, (_rules.platforms||{}), (s.platformOverride||{}));
    const _overrides = buildOverrides((selectedInst.config||{}), s.cfgOverride, s.catalog, this);
    return {rootRef:this.rootRef,
      paletteOpen:s.palette, openPalette:()=>this.setState({palette:true}), closePalette:pclose, stopClick:(e)=>e.stopPropagation(),
      paletteItems,
      toasts: s.toasts.map(t=>({...t, dot:{width:'8px',height:'8px',borderRadius:'99px',flex:'none',background:t.color,boxShadow:'0 0 8px '+t.color}})),
      notifOpen:s.notifOpen,
      notifCount:(s.notifications||[]).filter(n=>n.ts>(s.notifReadTs||0)).length,
      notifUnread:(s.notifications||[]).filter(n=>n.ts>(s.notifReadTs||0)).length>0,
      notifHasAny:(s.notifications||[]).length>0, notifEmpty:(s.notifications||[]).length===0,
      notifItems:(s.notifications||[]).slice(0,20).map(n=>({msg:n.msg, ago:relTime(n.ts), dismiss:()=>this.dismissNotif(n.id), dot:{width:'7px',height:'7px',borderRadius:'99px',flex:'none',marginTop:'5px',background:n.color||'#5AA9FF',boxShadow:'0 0 6px '+(n.color||'#5AA9FF')}})),
      toggleNotif:()=>this.toggleNotif(), clearNotif:()=>this.clearNotif(), closeNotif:()=>this.setState({notifOpen:false}),
      isOverview:v==='overview', isInstance:v==='instance', isCluster:v==='cluster', isConsole:v==='console', isBackups:v==='backups', isSettings:v==='settings', isMobile:v==='mobile',
      nav, title:T[v][0], subtitle:T[v][1], clock, date,
      insts, running, totalPlayers, sel:selDetail, macros, feed, tasks,
      instCount: insts.length,
      instBars: insts.map(i=>({style:{flex:'1',height:'5px',borderRadius:'99px',background:(STATUS[i.st]||STATUS.unknown).c}})),
      host:hostCard, connected:live.connected, connError:live.error,
      clusterHealth: live.connected ? (running>0?'Online':'Offline') : 'Connecting…',
      clusterColor: live.connected ? (running>0?'var(--green)':'var(--red)') : 'var(--amber)',
      clusterSub: live.connected ? (totalPlayers+' online · '+running+' running') : (live.error?String(live.error).slice(0,28):'reaching the ARK VM…'),
      hasEvent:false, eventLabel:'', eventDesc:'', eventWhen:'',
      totalMax: provMax||70, playersTrend: live.connected ? 'live' : '',
      // settings General tab (real)
      genSession: ((selectedInst.config||{}).sessionName)||selectedInst.name||'—',
      genGamePort: ((selectedInst.ports||{}).game)||'—', genRconPort: ((selectedInst.ports||{}).rcon)||'27020',
      genStatus: (selectedInst.statusLabel||'—')+(selectedInst.isRunning?' · '+(selectedInst.players||0)+'/'+(selectedInst.max||70)+' players · uptime '+selectedInst.uptime:''),
      // console
      logRef:this.logRef,
      consoleTabs: insts.filter(i=>i.provisioned).map(m=>{ const active=s.consoleTab===m.id; return {name:m.name, code:m.code, go:()=>this.setConsoleTab(m.id), sleeping:false, style:{display:'flex',alignItems:'center',gap:'7px',padding:'8px 13px',borderRadius:'9px',cursor:'pointer',fontSize:'12.5px',fontWeight:active?700:500,color:active?'var(--text)':'var(--mute)',background:active?'var(--surface2)':'transparent',border:'1px solid '+(active?'var(--line2)':'transparent')}, dot:{width:'6px',height:'6px',borderRadius:'99px',background:'var(--green)'}}; }),
      consoleFilters: CFILTERS.map(f=>{ const active=s.consoleFilter===f[0]; return {label:f[1], go:()=>this.setFilter(f[0]), style:{fontSize:'11.5px',fontWeight:600,padding:'5px 11px',borderRadius:'7px',cursor:'pointer',fontFamily:'JetBrains Mono,monospace',color:active?'var(--ember)':'var(--mute)',background:active?'var(--ember-soft)':'transparent',border:'1px solid '+(active?'rgba(255,122,46,.3)':'var(--line)')}}; }),
      consoleView,
      consoleMacros: CMACROS.map(mc=>({label:mc.label, run:()=>this.sendRcon(s.consoleTab, mc.cmd)})),
      rconInput:s.rconInput, onRconInput:(e)=>this.onRconInput(e), onRconKey:(e)=>this.onRconKey(e), sendRconInput:()=>this.sendRconInput(),
      consoleSearch:s.consoleSearch, onConsoleSearch:(e)=>this.onConsoleSearch(e),
      downloadConsole:()=>{ try{ const txt=(s.lines||[]).map(l=>l.txt).join('\n'); const blob=new Blob([txt],{type:'text/plain'}); const url=URL.createObjectURL(blob); const a=document.createElement('a'); a.href=url; a.download='ark-console.log'; document.body.appendChild(a); a.click(); a.remove(); URL.revokeObjectURL(url); this.toast('Console log downloaded','#37D67A'); }catch(e){ this.toast('Download failed','#FF5B5B'); } },
      // settings
      settingsTab:s.settingsTab,
      stGeneral:s.settingsTab==='general', stRates:s.settingsTab==='rates', stMods:s.settingsTab==='mods', stCluster:s.settingsTab==='cluster', stFiles:s.settingsTab==='files', stSchedule:s.settingsTab==='schedule', stDiscord:s.settingsTab==='discord', stAudit:s.settingsTab==='audit',
      settingsTabs: [['general','General'],['rates','Rates & Rules'],['files','Config Files'],['schedule','Schedule'],['audit','Audit']].map(t=>{ const active=s.settingsTab===t[0]; return {label:t[1], go:()=>this.setStab(t[0]), style:{fontSize:'12.5px',fontWeight:active?700:500,padding:'9px 15px',borderRadius:'9px',cursor:'pointer',whiteSpace:'nowrap',color:active?'var(--text)':'var(--mute)',background:active?'var(--surface2)':'transparent',border:'1px solid '+(active?'var(--line2)':'transparent')}}; }),
      // instance controls + real update flow
      openUpdate:()=>this.openUpdate(selectedInst.id), closeUpdate:()=>this.closeUpdate(), applyUpdate:()=>this.applyUpdate(), stopClick2:(e)=>e.stopPropagation(),
      macroSave:()=>this.saveWorld(selectedInst.id),
      goSettings:()=>this.setView('settings'), goOverview:()=>this.setView('overview'),
      selUpdAvail:false, selUpdVer:(s.update&&s.update.latest)||'',
      bldCur:(s.update&&s.update.installed)||'—', bldNext:(s.update&&(s.update.latest||s.update.installed))||'—',
      bldCurB:(s.update&&s.update.installed)||'', bldNextB:(s.update&&s.update.latest)||'', bldSize:'ASA server files',
      updNotes:[],
      upd:(function(u){ if(!u) return null;
        const busy=u.phase==='checking'||u.phase==='applying';
        const isDone=u.phase==='done'||u.phase==='uptodate'||u.phase==='error';
        const pct=u.phase==='applying'?60:(isDone?100:0);
        const phaseLabel={checking:'Querying SteamCMD…',ready:'Update available',applying:'Updating — download + restart',done:'Update started · watch the console',uptodate:'Up to date',error:(u.error||'Check failed')}[u.phase]||'';
        return {instName:selectedInst.name,
          isChecking:u.phase==='checking', isReady:u.phase==='ready', isDownloading:u.phase==='applying', isDone:isDone,
          showProgress:u.phase==='applying'||u.phase==='done', busy, phaseLabel, pct, dl:pct, steps:[],
          barStyle:{height:'100%',width:pct+'%',borderRadius:'99px',background: (u.phase==='done'||u.phase==='uptodate')?'var(--green)':'linear-gradient(90deg,var(--blue),#8FC4FF)',transition:'width .35s ease'}};
      })(s.update),
      // instance action buttons (used by header on instance page via inline onClicks are static; expose helpers)
      doRestart:()=>this.instAction(selectedInst.id,'restart','Restart'),
      doStop:()=>this.instAction(selectedInst.id,'stop','Stop'),
      doSleep:()=>this.instAction(selectedInst.id,'stop','Sleep'),
      // --- config search / check / apply (real catalog + real writes) ---
      cfgQuery:s.cfgQuery, onCfgSearch:(e)=>this.onCfgSearch(e), cfgHasQuery:(s.cfgQuery||'').trim().length>0,
      cfgResults: searchCatalog(s.catalog, s.cfgQuery, (s.cfgAdded||[]).map(a=>a.key)).map(c=>({...c, add:()=>this.cfgAdd(c)})),
      cfgNoResults:(s.cfgQuery||'').trim().length>0 && searchCatalog(s.catalog, s.cfgQuery, (s.cfgAdded||[]).map(a=>a.key)).length===0,
      cfgCustomKey:(s.cfgQuery||'').trim(), cfgCanAddCustom:/^[A-Za-z0-9_]+$/.test((s.cfgQuery||'').trim()),
      cfgAddCustomGus:()=>this.cfgAddCustom('gus'), cfgAddCustomGame:()=>this.cfgAddCustom('game'),
      cfgAdded:(s.cfgAdded||[]).map(a=>{ const checking=a.status==='checking', valid=a.status==='valid', invalid=a.status==='invalid'; const c=valid?'#37D67A':(invalid?'#FF5B5B':'#FFB23E');
        return Object.assign({}, a, {checking, valid, invalid, statusColor:c, onEdit:(e)=>this.cfgEdit(a.key,e.target.value), remove:()=>this.cfgRemove(a.key), apply:()=>this.cfgApply(a),
          badgeStyle:{display:'inline-flex',alignItems:'center',gap:'6px',fontSize:'10.5px',fontWeight:600,padding:'3px 9px',borderRadius:'6px',color:c,background:c+'18',border:'1px solid '+c+'33',whiteSpace:'nowrap'},
          inputStyle:{width:'92px',background:'var(--bg2)',border:'1px solid '+(invalid?'#FF5B5B':'var(--line2)'),borderRadius:'7px',padding:'7px 9px',color:valid?'#A9E7C2':(invalid?'#FF9E9E':'var(--text)'),fontFamily:'JetBrains Mono,monospace',fontSize:'12px',outline:'none'}}); }),
      cfgCount:(s.cfgAdded||[]).length, cfgValidCount:(s.cfgAdded||[]).filter(a=>a.status==='valid').length,
      applyAllCfg:()=>{ (this.state.cfgAdded||[]).filter(a=>a.status==='valid').forEach(a=>this.cfgApply(a)); },
      // --- rates (settings tab): base multipliers + any searched-and-applied multiplier ---
      rates: effMultipliers(extendMults((selectedInst.config||{}).multipliers, selectedInst.config, s.cfgOverride, s.catalog), s.cfgOverride, s.cfgEdit).map(r=>{
        // live value follows the edit buffer so the thin bar/knob move while dragging
        const lv=(r.displayVal!==''&&!isNaN(parseFloat(r.displayVal)))?parseFloat(r.displayVal):r.effVal;
        const lp=Math.min(100,Math.max(0,Math.round(lv/(r.max||10)*100))); const col=r.hot?'var(--ember)':'var(--cyan)';
        return {k:r.k, v:r.v, v2:r.displayVal, pct:lp, boost:r.hot, valColor:r.hot?'var(--ember)':'var(--text)',
        onChange:(e)=>this.onRateInput(r.key,e), onBlur:()=>this.commitRate(r.key,r.file), onKey:(e)=>this.onRateKey(e),
        // old thin look (track+fill+knob) with a transparent range input over it for the drag
        sMin:0, sMax:(r.max||10), sStep:((r.max||10)>20?1:0.1), sVal:lv,
        onSlide:(e)=>this.onRateInput(r.key,e), onSlideUp:()=>this.commitRate(r.key,r.file),
        track:{position:'absolute',left:'0',right:'0',top:'50%',transform:'translateY(-50%)',height:'6px',borderRadius:'99px',background:'var(--line)'},
        fill:{position:'absolute',left:'0',top:'50%',transform:'translateY(-50%)',height:'6px',width:lp+'%',borderRadius:'99px',background:r.hot?'linear-gradient(90deg,var(--ember),var(--ember2))':'var(--cyan)'},
        knob:{position:'absolute',top:'50%',left:lp+'%',transform:'translate(-50%,-50%)',width:'14px',height:'14px',borderRadius:'99px',background:'#fff',border:'2px solid '+col,boxShadow:'0 1px 3px rgba(0,0,0,.4)'},
        rangeStyle:{position:'absolute',left:'0',top:'0',width:'100%',height:'18px',margin:'0',opacity:'0',cursor:'pointer',WebkitAppearance:'none',appearance:'none'},
        inputStyle:{width:'64px',textAlign:'right',background:'var(--bg2)',border:'1px solid var(--line2)',borderRadius:'7px',padding:'5px 8px',color:r.hot?'var(--ember)':'var(--text)',fontFamily:'JetBrains Mono,monospace',fontSize:'13px',fontWeight:700,outline:'none'}}; }),
      // difficulty as a thin working slider (OverrideOfficialDifficulty 1–10)
      diff:(function(self,rules,ov,edit){ const eb=edit.OverrideOfficialDifficulty;
        const base=ov.OverrideOfficialDifficulty!=null?parseFloat(ov.OverrideOfficialDifficulty):(rules.difficulty||1);
        const cur=(eb!=null&&eb!==''&&!isNaN(parseFloat(eb)))?parseFloat(eb):base;
        const lp=Math.min(100,Math.max(0,Math.round((cur-1)/9*100)));
        return {val:cur, label:cur.toFixed(1)+' · max wild '+Math.round(cur*30), sMin:1, sMax:10, sStep:0.1, pct:lp,
          onSlide:(e)=>self.setState(s=>({cfgEdit:Object.assign({},s.cfgEdit,{OverrideOfficialDifficulty:e.target.value})})),
          onSlideUp:()=>self.commitRate('OverrideOfficialDifficulty','gus'),
          track:{position:'absolute',left:'0',right:'0',top:'50%',transform:'translateY(-50%)',height:'6px',borderRadius:'99px',background:'var(--line)'},
          fill:{position:'absolute',left:'0',top:'50%',transform:'translateY(-50%)',height:'6px',width:lp+'%',borderRadius:'99px',background:'var(--cyan)'},
          knob:{position:'absolute',top:'50%',left:lp+'%',transform:'translate(-50%,-50%)',width:'14px',height:'14px',borderRadius:'99px',background:'#fff',border:'2px solid var(--cyan)',boxShadow:'0 1px 3px rgba(0,0,0,.4)'},
          rangeStyle:{position:'absolute',left:'0',top:'0',width:'100%',height:'18px',margin:'0',opacity:'0',cursor:'pointer',WebkitAppearance:'none',appearance:'none'}}; })(this, (selectedInst.config||{}).rules||{}, s.cfgOverride, s.cfgEdit),
      // per-world compute allocation — CPU cores + RAM ceiling as a share of the shared VM
      compute:(function(self,inst,host,draft){
        const vmCores=Math.max(1,Math.round(host.cpus||4));
        const vmRam=host.memTotal?Math.max(1,Math.floor(host.memTotal*1e9/1073741824)):Math.max(1,Math.floor(inst.ramAlloc||16));
        const svC=inst.coresAlloc!=null?inst.coresAlloc:vmCores;   // current server-side cap (null→full VM)
        const svR=inst.ramLimitGB!=null?inst.ramLimitGB:vmRam;
        const curC=(draft&&draft.cores!=null)?draft.cores:svC;
        const curR=(draft&&draft.ram!=null)?draft.ram:svR;
        const cp=Math.min(100,Math.max(0,Math.round((curC-0.25)/Math.max(0.01,vmCores-0.25)*100)));
        const rp=Math.min(100,Math.max(0,Math.round((curR-1)/Math.max(1,vmRam-1)*100)));
        const liveGB=inst.ramLiveGB;
        const dirty=draft!=null && (Math.abs(curC-svC)>0.001 || curR!==svR);
        const overcap=liveGB!=null && curR<liveGB;
        const mk=(pct,hot)=>({track:{position:'absolute',left:'0',right:'0',top:'50%',transform:'translateY(-50%)',height:'6px',borderRadius:'99px',background:'var(--line)'},
          fill:{position:'absolute',left:'0',top:'50%',transform:'translateY(-50%)',height:'6px',width:pct+'%',borderRadius:'99px',background:hot?'linear-gradient(90deg,var(--ember),var(--ember2))':'var(--cyan)'},
          knob:{position:'absolute',top:'50%',left:pct+'%',transform:'translate(-50%,-50%)',width:'14px',height:'14px',borderRadius:'99px',background:'#fff',border:'2px solid '+(hot?'var(--ember)':'var(--cyan)'),boxShadow:'0 1px 3px rgba(0,0,0,.4)'},
          rangeStyle:{position:'absolute',left:'0',top:'0',width:'100%',height:'18px',margin:'0',opacity:'0',cursor:'pointer',WebkitAppearance:'none',appearance:'none'}});
        const capped=inst.coresAlloc!=null||inst.ramLimitGB!=null;
        return {vmCores, vmRam,
          capped,
          coresLabel:(Math.round(curC*100)/100)+' vCPU', ramLabel:curR+' GB',
          cpuShare:Math.round(curC/vmCores*100)+'% of '+vmCores+' vCPU', ramShare:Math.round(curR/vmRam*100)+'% of '+vmRam+' GB',
          liveLabel: liveGB!=null?(' · using '+liveGB+' GB now'):'',
          cpuSMin:0.25, cpuSMax:vmCores, cpuSStep:0.25, cpuSVal:curC,
          ramSMin:1, ramSMax:vmRam, ramSStep:1, ramSVal:curR,
          onCpu:(e)=>self.onComputeCpu(e), onRam:(e)=>self.onComputeRam(e),
          cpu:mk(cp,false), mem:mk(rp,overcap),
          dirty, overcap, busy:!!(draft&&draft.busy),
          warn: overcap?("RAM below this world's live use ("+liveGB+' GB) — stop the world first, or raise the limit'):'',
          apply:()=>self.applyCompute(), reset:()=>self.resetCompute(),
          applyStyle:{display:'flex',alignItems:'center',gap:'6px',fontSize:'12px',fontWeight:700,color:dirty?'#0A0C10':'var(--mute)',background:dirty?(overcap?'linear-gradient(90deg,var(--amber),var(--amber))':'linear-gradient(90deg,var(--ember),var(--ember2))'):'var(--surface2)',border:dirty?'none':'1px solid var(--line2)',borderRadius:'8px',padding:'8px 14px',cursor:dirty?'pointer':'default',pointerEvents:dirty?'auto':'none',opacity:(draft&&draft.busy)?0.6:1},
          resetStyle:{fontSize:'11.5px',fontWeight:600,color:'var(--mute)',background:'none',border:'none',cursor:'pointer',display:dirty?'inline':'none'}};
      })(this, selectedInst, host, s.computeDraft),
      computeOpen:!!s.computeOpen, toggleCompute:()=>this.toggleCompute(), closeCompute:()=>this.closeCompute(),
      // crossplay per platform (real -ServerPlatform= launch arg) — each badge toggles that platform
      crossPlatforms:[['PC','Steam'],['XSX','Xbox'],['PS5','PS5'],['WINGDK','Windows']].map(([tok,short])=>{ const on=effPlat[tok]!==false; return {name:short, short, on, toggle:()=>this.togglePlatform(tok, effPlat),
        style:{fontSize:'11px',fontWeight:600,borderRadius:'7px',padding:'5px 11px',cursor:'pointer',border:'1px solid '+(on?'rgba(55,211,195,.35)':'var(--line2)'),background:on?'rgba(55,211,195,.12)':'var(--surface2)',color:on?'var(--cyan)':'var(--mute)'}, mark:on?'✓ ':'',
        miniStyle:{fontSize:'9.5px',fontFamily:'JetBrains Mono,monospace',borderRadius:'5px',padding:'1px 6px',border:'1px solid '+(on?'rgba(55,211,195,.3)':'var(--line2)'),background:on?'rgba(55,211,195,.1)':'var(--surface2)',color:on?'var(--cyan)':'var(--mute)',opacity:on?1:0.5}}; }),
      // game mode + rule toggles (optimistic apply)
      ruleModeIsPve: effMode==='PvE',
      setPvE:()=>this.setGameMode(true), setPvP:()=>this.setGameMode(false),
      pveStyle:{flex:'1',textAlign:'center',fontSize:'12px',padding:'7px',borderRadius:'6px',cursor:'pointer',fontWeight:700,background:effMode==='PvE'?'rgba(55,214,122,.14)':'transparent',color:effMode==='PvE'?'var(--green)':'var(--mute)'},
      pvpStyle:{flex:'1',textAlign:'center',fontSize:'12px',padding:'7px',borderRadius:'6px',cursor:'pointer',fontWeight:700,background:effMode==='PvP'?'rgba(255,91,91,.14)':'transparent',color:effMode==='PvP'?'var(--red)':'var(--mute)'},
      toggleFlyer:()=>{ this.applyRate('AllowFlyerCarryPvE','gus',effFlyer?'False':'True'); },
      flyerTog:this.tog(effFlyer, '#FF7A2E'),
      toggleThird:()=>{ this.applyRate('AllowThirdPersonPlayer','gus',effThird?'False':'True'); },
      thirdTog:this.tog(effThird, '#FF7A2E'),
      activeOverrides: _overrides, overrideCount: _overrides.length+' changed', noOverrides: _overrides.length===0,
      exportAudit:()=>this.exportAudit(),
      openNewTask:()=>this.openNewTask(),
      // --- schedule (real crontab) ---
      schedule:(s.schedule||[]).map(j=>{ const st={backup:{c:'#37D3C3',ic:'save',label:'Backup'},restart:{c:'#FFB23E',ic:'restart',label:'Restart'},healthcheck:{c:'#37D67A',ic:'clock',label:'Health check'},rcon:{c:'#8C7BF7',ic:'console',label:'RCON'},broadcast:{c:'#8C7BF7',ic:'bolt',label:'Announce'},multiplier:{c:'#FF7A2E',ic:'bolt',label:'Rate event'},save:{c:'#37D3C3',ic:'save',label:'Save world'},task:{c:'#5AA9FF',ic:'clock',label:'Task'}}[j.type]||{c:'#5AA9FF',ic:'clock',label:'Task'};
        return {name:st.label, human:cronHuman(j.cron)||j.cron, target:selectedInst.name, cron:j.cron, next:'active', nextColor:'var(--dim)', icon:icn(st.ic,15,st.c), del:()=>this.deleteTask(j.cmd)}; }),
      // --- audit (real dashboard actions) ---
      audit:(s.auditLog||[]).map(a=>({who:a.who, cmd:a.action, target:a.target||'—', ago:relTime(a.ts), whoColor:a.who==='cron'?'var(--violet)':'var(--cyan)', whoBg:a.who==='cron'?'rgba(140,123,247,.14)':'rgba(55,211,195,.14)', cmdColor:a.danger?'#FFB08A':'var(--text)'})),
      // --- config files (real) ---
      files:[['GameUserSettings.ini','gus'],['Game.ini','game']].map(f=>{ const active=(s.cfgFile?s.cfgFile.which:'gus')===f[1]; return {name:f[0], size:'', go:()=>this.loadConfigFile(f[1]),
        style:{display:'flex',alignItems:'center',gap:'9px',padding:'9px 11px',borderRadius:'8px',cursor:'pointer',fontSize:'12px',fontFamily:'JetBrains Mono,monospace',color:active?'var(--text)':'var(--dim)',background:active?'var(--ember-soft)':'transparent',border:'1px solid '+(active?'rgba(255,122,46,.25)':'transparent')}}; }),
      ini:parseIniLines(s.cfgFile?s.cfgFile.ini:''), cfgFileName:s.cfgFile?(s.cfgFile.which==='game'?'Game.ini':'GameUserSettings.ini'):'GameUserSettings.ini',
      cfgDraft:s.cfgDraft||'', onCfgDraft:(e)=>this.onCfgDraft(e), saveCfgRaw:()=>this.saveCfgRaw(), cfgIsEmpty:!((s.cfgDraft||'').trim()),
      // --- add map ---
      addMapOpen:!!(s.addMap&&s.addMap.open), openAddMap:()=>this.openAddMap(),
      addMap: s.addMap ? (function(a,self){ return {busy:a.busy, error:a.error, hasError:!!a.error, form:a.form,
        available:(a.available||[]).map(m=>({display:m.display, active:a.form.display===m.display, select:()=>self.setAddField('display',m.display),
          style:{fontSize:'12px',fontWeight:a.form.display===m.display?700:500,padding:'7px 11px',borderRadius:'8px',cursor:'pointer',border:'1px solid '+(a.form.display===m.display?'var(--ember)':'var(--line2)'),background:a.form.display===m.display?'var(--ember-soft)':'var(--surface2)',color:a.form.display===m.display?'var(--ember)':'var(--dim)',whiteSpace:'nowrap'}})),
        setSession:(e)=>self.setAddField('sessionName',e.target.value), setGame:(e)=>self.setAddField('gamePort',e.target.value), setQuery:(e)=>self.setAddField('queryPort',e.target.value), setRcon:(e)=>self.setAddField('rconPort',e.target.value), setMax:(e)=>self.setAddField('maxPlayers',e.target.value), setAdmin:(e)=>self.setAddField('adminPassword',e.target.value), setServer:(e)=>self.setAddField('serverPassword',e.target.value), setCores:(e)=>self.setAddField('cores',e.target.value), setRam:(e)=>self.setAddField('ramGB',e.target.value),
        submit:()=>self.submitAddMap(), close:()=>self.closeAddMap(), stop:(e)=>e.stopPropagation()}; })(s.addMap,this) : null,
      // new scheduled task modal
      newTaskOpen:!!(s.newTask&&s.newTask.open),
      newTask: s.newTask ? (function(t,self,inst,ovr){ const presets=[['restart','Restart server'],['backup','Backup world'],['save','Save world'],['broadcast','Announce message'],['multiplier','Rate event']];
        const RATES=[['XPMultiplier','XP','gus'],['HarvestAmountMultiplier','Harvest','gus'],['TamingSpeedMultiplier','Taming','gus'],['BabyMatureSpeedMultiplier','Maturation','game'],['MatingIntervalMultiplier','Mating interval','game'],['EggHatchSpeedMultiplier','Egg hatch','game']];
        const DAYS=[['*','Every day'],['1','Mon'],['2','Tue'],['3','Wed'],['4','Thu'],['5','Fri'],['6','Sat'],['0','Sun']];
        const isMult=t.taskType==='multiplier';
        const dayBtn=(field,cyan)=>DAYS.map(([v,l])=>({label:l, active:t[field]===v, select:()=>self.setTask(field,v),
          style:{fontSize:'11.5px',fontWeight:t[field]===v?700:500,padding:'6px 10px',borderRadius:'7px',cursor:'pointer',border:'1px solid '+(t[field]===v?(cyan?'var(--cyan)':'var(--ember)'):'var(--line2)'),background:t[field]===v?(cyan?'rgba(55,211,195,.12)':'var(--ember-soft)'):'var(--surface2)',color:t[field]===v?(cyan?'var(--cyan)':'var(--ember)'):'var(--dim)'}}));
        const ov=ovr[t.rateKey]; const all=((inst.config||{}).all)||{}; const revertVal=ov!=null?String(parseFloat(ov)):(all[t.rateKey]!=null?String(all[t.rateKey]):'1.0');
        return {busy:t.busy, error:t.error, hasError:!!t.error, taskType:t.taskType, message:t.message||'', isBroadcast:t.taskType==='broadcast', isMultiplier:isMult, showMessage:t.taskType==='broadcast'||isMult, whenLabel:isMult?'Event starts':'When?',
          types:presets.map(p=>({label:p[1], active:t.taskType===p[0], select:()=>self.setTask('taskType',p[0]),
            style:{fontSize:'12px',fontWeight:t.taskType===p[0]?700:500,padding:'8px 12px',borderRadius:'8px',cursor:'pointer',border:'1px solid '+(t.taskType===p[0]?'var(--ember)':'var(--line2)'),background:t.taskType===p[0]?'var(--ember-soft)':'var(--surface2)',color:t.taskType===p[0]?'var(--ember)':'var(--dim)'}})),
          // preset chips ADD a rate to the event's list (a rate = one setting at one value)
          ratePresets:RATES.map(r=>({label:r[1], add:()=>self.addRate(r[0], r[2]),
            style:{fontSize:'12px',fontWeight:500,padding:'7px 11px',borderRadius:'8px',cursor:'pointer',border:'1px solid var(--line2)',background:'var(--surface2)',color:'var(--dim)',whiteSpace:'nowrap'}})),
          rateList:(t.rates||[]).map((r,i)=>({key:r.key, value:r.value, file:(r.file==='game'?'Game':'GUS'),
            setValue:(e)=>self.setRateValueAt(i,e.target.value), remove:()=>self.removeRateAt(i),
            valInputStyle:{width:'62px',textAlign:'right',background:'var(--bg2)',border:'1px solid var(--line2)',borderRadius:'7px',padding:'5px 8px',color:'var(--ember)',fontFamily:'JetBrains Mono,monospace',fontSize:'13px',fontWeight:700,outline:'none'}})),
          hasRates:(t.rates||[]).length>0, rateCount:(t.rates||[]).length,
          rateKeyValue:t.rateKey||'', setRateKey:(e)=>self.onRateKeyType(e), addFromInput:()=>self.addRateFromInput(),
          setRateFileGus:()=>self.setTask('rateFile','gus'), setRateFileGame:()=>self.setTask('rateFile','game'),
          gusStyle:{fontSize:'11px',fontWeight:700,padding:'8px 12px',borderRadius:'8px',cursor:'pointer',whiteSpace:'nowrap',border:'1px solid '+(t.rateFile!=='game'?'var(--ember)':'var(--line2)'),background:t.rateFile!=='game'?'var(--ember-soft)':'var(--surface2)',color:t.rateFile!=='game'?'var(--ember)':'var(--dim)'},
          gameStyle:{fontSize:'11px',fontWeight:700,padding:'8px 12px',borderRadius:'8px',cursor:'pointer',whiteSpace:'nowrap',border:'1px solid '+(t.rateFile==='game'?'var(--ember)':'var(--line2)'),background:t.rateFile==='game'?'var(--ember-soft)':'var(--surface2)',color:t.rateFile==='game'?'var(--ember)':'var(--dim)'},
          testNow:()=>self.testRateNow(),
          restartOn:!!t.restart, toggleRestart:()=>self.setTask('restart',!t.restart), restartTog:self.tog(!!t.restart,'#FFB23E'),
          startDays:dayBtn('startDay',false), endDays:dayBtn('endDay',true),
          startTime:t.startTime, setStartTime:(e)=>self.setTask('startTime',e.target.value),
          endTime:t.endTime, setEndTime:(e)=>self.setTask('endTime',e.target.value),
          startHuman:humanDT(t.startDay,t.startTime), endHuman:humanDT(t.endDay,t.endTime), setMessage:(e)=>self.setTask('message',e.target.value),
          submit:()=>self.submitNewTask(), close:()=>self.closeNewTask(), stop:(e)=>e.stopPropagation()}; })(s.newTask,this,selectedInst,s.cfgOverride) : null,
      // --- backups (real snapshots from ark-manager) ---
      backups:(function(self){ const arr=s.backupList||[]; const selName=s.selBkpName||(arr[0]&&arr[0].name);
        const TRG={auto:{c:'#8C7BF7',label:'Auto · pre-restore'},scheduled:{c:'#FFB23E',label:'Scheduled'},update:{c:'#5AA9FF',label:'Pre-update'},manual:{c:'#37D3C3',label:'Manual'}};
        return arr.map((b,i)=>{ const pos=arr.length>1?(95-i*(90/(arr.length-1))):50; const active=b.name===selName; const tg=TRG[b.trigger]||TRG.manual; const c=tg.c;
          return {id:b.name, when:b.when||b.name, map:selectedInst.name, size:b.size||'', note:(b.trigger==='auto'?'auto safety copy':(b.trigger==='scheduled'?'scheduled backup':'saved world')), tgLabel:tg.label, tgColor:c, active, select:()=>self.setState({selBkpName:b.name}), restore:()=>self.restoreBackup(b.name), del:()=>self.askDeleteBackup(b.name),
            dotStyle:{position:'absolute',top:'50%',left:pos+'%',transform:'translate(-50%,-50%)',width:active?'18px':'12px',height:active?'18px':'12px',borderRadius:'99px',background:c,border:'2px solid #0A0C10',boxShadow:active?'0 0 0 4px '+c+'40':'0 0 6px '+c,cursor:'pointer',zIndex:active?3:2},
            scrubStyle:{position:'absolute',top:'0',bottom:'0',left:pos+'%',width:'2px',background:'linear-gradient(180deg,transparent,'+c+',transparent)',transform:'translateX(-50%)',display:active?'block':'none',pointerEvents:'none'},
            rowStyle:{display:'grid',gridTemplateColumns:'1.2fr 1.1fr 1fr .8fr auto',gap:'12px',padding:'11px 16px',borderBottom:'1px solid rgba(33,41,54,.5)',alignItems:'center',fontSize:'12.5px',cursor:'pointer',background:active?'var(--ember-soft)':'transparent'},
            pillStyle:{display:'inline-flex',alignItems:'center',gap:'5px',fontSize:'10.5px',fontWeight:600,padding:'2px 8px',borderRadius:'6px',color:c,background:c+'18',border:'1px solid '+c+'33'}}; }); })(this),
      selBkp:(function(self){ const arr=s.backupList||[]; const b=arr.find(x=>x.name===(s.selBkpName||(arr[0]&&arr[0].name)))||arr[0]||{}; return {id:b.name||'', when:b.when||b.name||'—', map:selectedInst.name, size:b.size||'—', tgColor:'#37D3C3', restore:()=>self.restoreBackup(b.name), del:()=>self.askDeleteBackup(b.name)}; })(this),
      bkpCount:(s.backupList||[]).length,
      hasBackups:(s.backupList||[]).length>0, noBackups:(s.backupList||[]).length===0,
      bkpStorageNote:(s.backupList||[]).length>0 ? ('in '+selectedInst.name+" · maps/"+selectedInst.name+"/backups") : 'None yet — click Snapshot to create one',
      createBackupBtn:()=>this.createBackup(),
      // auto-backup transparency: list any scheduled backup cron; if none, reassure the user
      backupSchedules:(s.schedule||[]).filter(j=>j.type==='backup').map(j=>({human:cronHuman(j.cron)||j.cron, cron:j.cron, del:()=>this.deleteTask(j.cmd)})),
      hasAutoBackup:(s.schedule||[]).some(j=>j.type==='backup'),
      autoBackupState:(s.schedule||[]).some(j=>j.type==='backup') ? 'On' : 'Off',
      autoBackupColor:(s.schedule||[]).some(j=>j.type==='backup') ? 'var(--amber)' : 'var(--green)',
      autoBackupNote:(s.schedule||[]).some(j=>j.type==='backup') ? 'A scheduled backup is running — turn it off below to stop automatic snapshots.' : 'No scheduled auto-backup. Snapshots are only created when you click Snapshot, or automatically as a one-off safety copy just before a Restore (shown as “Auto · pre-restore”).',
      // --- world delete + edit (instance header) ---
      delSelWorld:()=>this.askDeleteWorld(selectedInst.name),
      openEditWorld:()=>this.openEditWorld(),
      // --- destructive-confirm modal ---
      confirmDeleteOpen:!!s.confirmDelete,
      confirmDelete: s.confirmDelete ? (function(c,self){ const isWorld=c.kind==='world';
        return {isWorld, isBackup:c.kind==='backup', busy:c.busy, error:c.error, hasError:!!c.error,
          title: isWorld?('Delete world "'+c.display+'"?'):'Delete this snapshot?',
          body: isWorld
            ? ('This permanently removes the '+c.display+' server, its service and ALL of its save data on the VM. This cannot be undone.')
            : ('This permanently removes the snapshot '+c.name+'. This cannot be undone.'),
          confirmLabel: isWorld?'Delete world':'Delete snapshot',
          confirm:()=>self.confirmDeleteDo(), close:()=>self.closeConfirm(), stop:(e)=>e.stopPropagation()}; })(s.confirmDelete,this) : null,
      // --- edit world (name + passwords) ---
      editWorldOpen:!!(s.editWorld&&s.editWorld.open),
      editWorld: s.editWorld ? (function(w,self){ return {busy:w.busy, error:w.error, hasError:!!w.error, name:w.name, form:w.form,
        setSession:(e)=>self.setEditField('sessionName',e.target.value),
        setAdmin:(e)=>self.setEditField('adminPassword',e.target.value),
        setServer:(e)=>self.setEditField('serverPassword',e.target.value),
        submit:()=>self.submitEditWorld(), close:()=>self.closeEditWorld(), stop:(e)=>e.stopPropagation()}; })(s.editWorld,this) : null,
      // unused design panels kept empty (hidden tabs / honest)
      playersLine:'', playersArea:''
    };
  }
}
function cacheSelPlayers(){ return null; }

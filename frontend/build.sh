#!/usr/bin/env bash
# Regenerate index.html from the design template + the live logic script.
# The dc-runtime reads the inline <script data-dc-script>, so the logic must be
# inlined (a src= script would have empty textContent at boot time).
set -euo pipefail
cd "$(dirname "$0")"

DP='{"accent":{"editor":"color","default":"#FF7A2E","tsType":"string","options":["#FF7A2E","#37D3C3","#8C7BF7","#37D67A"],"section":"Theme"},"density":{"editor":"enum","default":"balanced","options":["compact","balanced","spacious"],"tsType":"string","section":"Theme"},"liveData":{"editor":"boolean","default":true,"tsType":"boolean","section":"Behavior"}}'

cat > index.html <<'HEAD'
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ARK Server Manager</title>
<link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'><rect width='24' height='24' rx='5' fill='%230A0C10'/><path d='M4 19 12 4l8 15M8.4 14.5h7.2' stroke='%23FF7A2E' stroke-width='2.4' fill='none' stroke-linecap='round' stroke-linejoin='round'/></svg>">
<style>
  /* Hide the design template until the app mounts; show a clean loader meanwhile. */
  x-dc{display:none!important}
  html,body{background:#0A0C10}
  #dc-boot{position:fixed;inset:0;z-index:9999;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:14px;background:#0A0C10;color:#5C6979;font-family:Archivo,system-ui,sans-serif}
  #dc-boot.hide{display:none}
  #dc-boot .spin{width:26px;height:26px;border-radius:50%;border:3px solid #212936;border-top-color:#FF7A2E;animation:dcspin .8s linear infinite}
  @keyframes dcspin{to{transform:rotate(360deg)}}
</style>
<script src="./vendor/react.production.min.js"></script>
<script src="./vendor/react-dom.production.min.js"></script>
<script src="./support.js"></script>
</head>
<body>
<div id="dc-boot"><div class="spin"></div><div id="dc-boot-msg">Loading ARK Control…</div></div>
HEAD

cat _template.xdc.html >> index.html
printf '<script type="text/x-dc" data-dc-script data-props=%s>\n' "'$DP'" >> index.html
cat live.dcscript.js >> index.html
cat >> index.html <<'FOOT'

</script>
<script>
// Hide the loader the moment the app mounts (#dc-root gains children). A
// MutationObserver is reliable across timings; polling + a hard fallback back it up.
(function(){
  var boot=document.getElementById('dc-boot');
  var done=false;
  function mounted(){ var r=document.getElementById('dc-root'); return r && r.children && r.children.length>0; }
  function hide(){ if(done) return; done=true; boot.classList.add('hide'); if(obs) obs.disconnect(); clearInterval(iv); }
  var obs=null;
  try{ obs=new MutationObserver(function(){ if(mounted()) hide(); }); obs.observe(document.body,{childList:true,subtree:true}); }catch(e){}
  var iv=setInterval(function(){ if(mounted()) hide(); },100);
  if(mounted()) hide();
  setTimeout(function(){ if(!done){ if(mounted()){ hide(); } else { document.getElementById('dc-boot-msg').textContent='Could not start — please refresh (⌘R).'; } } },12000);
})();
</script>
</body>
</html>
FOOT

echo "index.html: $(wc -l < index.html) lines, $(wc -c < index.html) bytes"

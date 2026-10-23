/* Kottkampen: independent teacher panel. */
(()=>{"use strict";
const URL="https://mjgkkwdgowvxuehiudvj.supabase.co",KEY="sb_publishable_rezjH5i8fLkwlIv-BOLWBQ_mtWJtyYg";
const G=[["percentConvert","Bråk · Decimal · Procent"],["sharePart","Hur stor andel?"],["percentChange","Beräkna förändring"],["percentPart","Beräkna delen"],["whole","Hitta det hela"],["fractionDecimal","Bråk ↔ Decimal"],["multiplication","Multiplikation"],["equations","Ekvationer"],["pow10","Tiopotenser"],["interest","Räntebanken"],["unitConvert","Enhetsomvandling"],["prefixMatch","Prefix"],["statistics","Statistik"],["fractionArithmetic","Räkna med bråk"],["scientificNotation","Grundpotensform"]];
const $=id=>document.getElementById(id);let sb,id=null,shown=false,busy=false;
const rpc=async(a,p={})=>{sb ||=window.supabase.createClient(URL,KEY,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false,storageKey:"matteparken-admin-auth-v1"}});
const {data,error}=await sb.rpc("kottkamp_teacher",{p_action:a,p_session_id:id,p_payload:p});
if(error)throw error;if(!data?.ok)throw Error(data?.reason||"Servern kunde inte utföra åtgärden");return data;};
const key=()=>"kottkamp-current-"+$("classSelect").value;
const say=t=>{$("kkMessage").textContent=t;};
function install(){
if(!$("classSelect")||$("kkPanel"))return;
const btn=document.createElement("button");btn.className="btn primary";btn.type="button";btn.textContent="🐿️ Kottkampen";$("classSelect").insertAdjacentElement("afterend",btn);
const card=document.createElement("section");card.className="card hidden";card.id="kkPanel";card.style.marginBottom="18px";
card.innerHTML=[
'<div class="section-head"><div><h2>🐿️ Kottkampen · Kottjakten</h2><p class="muted">Välj spel och tävlingstid. Eleverna ansluter via sin spelhylla.</p></div><button class="btn secondary" id="kkClose">Stäng</button></div>',
'<div class="grid" style="grid-template-columns:repeat(auto-fit,minmax(275px,1fr))"><div class="stack">',
'<label>Rubrik<input id="kkTitle" maxlength="90" value="Procentmästaren"></label>',
'<h3 style="margin:0">Välj matematikspel</h3><div id="kkGames" style="display:grid;grid-template-columns:repeat(auto-fit,minmax(180px,1fr));gap:8px"></div>',
'<div style="display:flex;gap:18px"><label style="display:flex;align-items:center;gap:5px"><input style="width:auto" type="radio" name="kkMode" value="time" checked>På tid</label><label style="display:flex;align-items:center;gap:5px"><input style="width:auto" type="radio" name="kkMode" value="questions">Antal frågor</label></div>',
'<label id="kkMinutesRow">Speltid i minuter (1–60)<input type="number" id="kkMinutes" min="1" max="60" value="10"></label>',
'<label id="kkQuestionsRow" class="hidden">Antal frågor (1–100)<input type="number" id="kkQuestions" min="1" max="100" value="15"></label>',
'<div class="form-actions"><button class="btn primary" id="kkCreate">Skapa tävling</button><button class="btn secondary" id="kkRestore">Återgå till tävling</button></div></div>',
'<div class="stack"><h3 id="kkHeading">Ingen tävling startad</h3><p id="kkInfo" class="muted">Skapa en tävling först.</p>',
'<div class="form-actions"><button class="btn primary" id="kkStart" disabled>▶ Starta</button><button class="btn secondary" id="kkPause" disabled>⏸ Pausa</button><button class="btn secondary" id="kkResume" disabled>▶ Fortsätt</button><button class="btn danger" id="kkFinish" disabled>🏁 Avsluta</button><button class="btn secondary" id="kkProjector" disabled>🏆 Visa på storbild ↗</button></div>',
'<h4>Topplista</h4><div class="table-wrap"><table><thead><tr><th>Elev</th><th>Poäng</th><th>Rätt</th><th>Kottar</th></tr></thead><tbody id="kkRows"></tbody></table></div>',
'<p class="muted small">Rätt svar ger +100 och fel svar −50 tävlingspoäng. Stubbar påverkar tävlingspoäng, aldrig elevens riktiga kottar. Vid målgång delas 25/20/15 kottar ut till de tre främsta, övriga deltagare får 8.</p></div></div><p id="kkMessage" class="feedback" aria-live="polite"></p>'
].join("");
$("adminView").insertBefore(card,$("adminView").querySelector(".topbar").nextSibling);
G.forEach(([value,name],i)=>{let label=document.createElement("label"),checkbox=document.createElement("input");checkbox.type="checkbox";checkbox.value=value;checkbox.checked=i<5;checkbox.style.width="auto";label.style.cssText="display:flex;flex-direction:row;gap:8px;align-items:center;font-size:13px";label.append(checkbox,document.createTextNode(name));$("kkGames").append(label);});
btn.onclick=()=>{shown=!shown;card.classList.toggle("hidden",!shown);if(shown)restore();};
$("kkClose").onclick=()=>{shown=false;card.classList.add("hidden");};
document.querySelectorAll('input[name="kkMode"]').forEach(e=>e.onchange=()=>{let timed=document.querySelector('input[name="kkMode"]:checked').value==="time";$("kkMinutesRow").classList.toggle("hidden",!timed);$("kkQuestionsRow").classList.toggle("hidden",timed);});
$("kkCreate").onclick=create;$("kkRestore").onclick=restore;
$("kkProjector").onclick=()=>{if(!id){say("Skapa en tävling först.");return;}window.open("kottkampen_live.html?session="+encodeURIComponent(id),"_blank","noopener");};
for(const action of ["start","pause","resume","finish"])$("kk"+action[0].toUpperCase()+action.slice(1)).onclick=()=>control(action);
$("classSelect").addEventListener("change",()=>{id=null;if(shown)restore();});
setInterval(()=>{if(shown&&id&&!busy)refresh();},2500);
}
async function create(){
if(busy)return;busy=true;
try{
const games=[...$("kkGames").querySelectorAll("input:checked")].map(x=>x.value);
const minutes=Number($("kkMinutes").value),question_count=Number($("kkQuestions").value),mode=document.querySelector('input[name="kkMode"]:checked').value;
if(!games.length||!Number.isInteger(minutes)||minutes<1||minutes>60||!Number.isInteger(question_count)||question_count<1||question_count>100)throw Error("Välj spel och ange giltig tävlingslängd.");
const x=await rpc("create",{class_id:$("classSelect").value,title:$("kkTitle").value,games,minutes,question_count,mode});
id=x.id;localStorage.setItem(key(),id);say("Tävlingen är skapad! Eleverna kan nu ansluta.");await refresh();
}catch(e){say(e.message);}finally{busy=false;}
}
async function restore(){id=localStorage.getItem(key());if(id)await refresh();else say("Ingen sparad tävling för den här klassen.");}
async function control(action){if(busy||!id)return;if(action==="finish"&&!confirm("Avsluta tävlingen och dela ut kottbelöningarna?"))return;
busy=true;try{await rpc(action);await refresh();say(action==="finish"?"Tävlingen avslutad. Belöningarna är utdelade.":"Tävlingsstatus uppdaterad.");}catch(e){say(e.message);}finally{busy=false;}
}
async function refresh(){if(!id)return;try{
const x=await rpc("snapshot"),s=x.session;
$("kkHeading").textContent=s.title+" · "+({waiting:"Väntar",running:"Pågår",paused:"Pausad",finished:"Avslutad"}[s.status]||s.status);
let timer="";if(s.mode==="time"&&s.started_at){let end=new Date(s.started_at).getTime()+(s.minutes*60+s.paused_seconds)*1000;let now=new Date(s.status==="paused"?s.paused_at:x.server_now).getTime();timer=" · "+Math.max(0,Math.ceil((end-now)/1000))+" s kvar";}
$("kkInfo").textContent=x.players.length+" deltagare · "+(s.mode==="time"?s.minutes+" minuter":s.question_count+" frågor")+timer;
$("kkProjector").disabled=false;$("kkStart").disabled=s.status!=="waiting";$("kkPause").disabled=s.status!=="running"||s.mode!=="time";$("kkResume").disabled=s.status!=="paused";$("kkFinish").disabled=s.status==="waiting"||s.status==="finished";
$("kkRows").replaceChildren();
if(!x.players.length){let row=document.createElement("tr"),cell=document.createElement("td");cell.colSpan=4;cell.textContent="Eleverna har inte anslutit ännu.";row.append(cell);$("kkRows").append(row);}
for(const p of x.players){let tr=document.createElement("tr");for(const v of [p.name,p.score,p.correct,p.reward==null?"–":p.reward]){let td=document.createElement("td");td.textContent=v;tr.append(td);} $("kkRows").append(tr);}
}catch(e){say("Kunde inte hämta ställningen: "+e.message);}}
document.addEventListener("DOMContentLoaded",install);
})();
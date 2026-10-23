/* Kottkampen student game: server-scored live questions and mystery stumps. */
(()=>{"use strict";
const $=id=>document.getElementById(id);
const KK_ICONS=["🐿️","🦊","🐻","🦉","🦔","🐸","🐞","🦆","🐟","🐝","🦋","🐭","🐰","🐺","🦌","🐱","🐶","🐢","🦫","🦦","🐌","🐛","🐜","🦜","🍄","🌻","🌲","🍎","🎃","🌰"];
const M=()=>window.Mattezoo;
let room=null,question=null,loading=false,selectingIcon=false,pending=false,lastStatus="",endedSynced=false,prizesSynced=false,prizeNames=[],clock=null,offsetMs=0,autoAdvanceTimer=null;
function cancelAutoAdvance(){if(autoAdvanceTimer!==null){clearTimeout(autoAdvanceTimer);autoAdvanceTimer=null;}}
function scheduleAutoAdvance(delayMs,expectedRoom){cancelAutoAdvance();autoAdvanceTimer=setTimeout(()=>{autoAdvanceTimer=null;if(room!==expectedRoom||$("kkOverlay")?.classList.contains("hidden"))return;pending=false;void getQuestion();},delayMs);}
const rpc=async(action,p={})=>{
 const client=M()?.cloudStudent?.getClient?.();
 if(!client)throw Error("Logga in med elevkod via Dagens uppdrag först.");
 const {data,error}=await client.rpc("kottkamp_student",{p_action:action,p_session_id:room,p_payload:p});
 if(error)throw error;
 if(!data?.ok)throw Error(data?.reason||"Kunde inte uppdatera spelet");
 return data;
};
const t=(id,value)=>{if($(id))$(id).textContent=value;};
const stage=html=>{$("kkStage").innerHTML=html;};
async function syncKottkampPrizes(force=false){
 if((prizesSynced&&!force)||!room)return;
 const r=await rpc("prizes");
 const studentId=M()?.cloudStudent?.currentState?.()?.student?.id;
 if(!studentId)throw Error("Eleven behöver vara inloggad för att ta emot priset.");
 prizeNames=[];
 for(const prize of r.prizes||[]){
  const result=M()?.rewards?.grantKottkampReward?.(prize,studentId);
  if(!result?.ok)throw Error("Priset kunde inte levereras till förrådet.");
  prizeNames.push(prize.type==="seedPack"?"fröpåse":prize.type==="decorBox"?"dekorationslåda":prize.type==="blindBag"?"blind bag":(result.name||"dekoration"));
 }
 prizesSynced=true;
}
function install(){
 const shelf=document.querySelector("#gameShelfDrawer .game-shelf");if(!shelf||$("kkShelf"))return;
 const card=document.createElement("button");card.id="kkShelf";card.type="button";card.className="game-card";
 card.innerHTML='<span class="shelf-cover" aria-hidden="true"><span class="shelf-volume">16</span><span class="shelf-symbol">🐿️ 🌰</span><span class="shelf-cover-rule"></span></span><strong>Kottkampen</strong><span class="shelf-description">Tävla i Kottjakten! Rätt svar +100 poäng, fel svar −50. Öppna mystiska stubbar.</span><span class="shelf-play" aria-hidden="true">Spela <span>↗</span></span>';
 shelf.appendChild(card);card.onclick=open;
 const shade=document.createElement("div");shade.id="kkOverlay";shade.className="hidden";
 shade.style.cssText="position:fixed;inset:0;z-index:5000;background:#142a20ee;display:flex;align-items:center;justify-content:center;padding:12px;overflow:auto";
 shade.innerHTML=[
 '<section role="dialog" aria-modal="true" aria-label="Kottkampen" style="width:min(780px,100%);max-height:95vh;overflow:auto;background:#fffaf0;color:#294233;border:5px solid #536b4b;border-radius:16px;padding:20px;box-shadow:0 20px 80px #0008">',
 '<div style="display:flex;justify-content:space-between;align-items:center;gap:10px"><h2 style="margin:0">🐿️ Kottkampen</h2><button class="secondary" type="button" id="kkCloseStudent">✕ Stäng</button></div>',
 '<p id="kkSub" class="muted" style="margin-top:10px">Kottjakten · klassens tävling</p>',
 '<div id="kkStudentStatus" style="font-weight:800;padding:10px;background:#e8efd9;border-radius:8px"></div>',
 '<div id="kkCalculatorDock" style="margin-top:12px"></div>',
 '<div id="kkStage" style="margin-top:18px;display:grid;gap:14px"></div>',
 '<div style="border-top:1px solid #bec8b5;margin-top:18px;padding-top:12px"><h3 style="margin:0 0 7px">🏆 Topplista</h3><div id="kkLeaders" style="font-size:13px"></div></div>',
 '</section>'
 ].join("");
 document.body.appendChild(shade);
 // Reuse the calculator already used in Matteparken's other maths games.
 const calculator=window.MatteparkenCalculator;
 if(calculator){
  $("kkCalculatorDock").innerHTML=calculator.markup();
  calculator.bind($("kkCalculatorDock"));
 }else{
  $("kkCalculatorDock").textContent="Miniräknaren kunde inte laddas. Uppdatera sidan.";
 }
 $("kkCloseStudent").onclick=()=>{$("kkOverlay").classList.add("hidden");room=null;question=null;selectingIcon=false;cancelAutoAdvance();};
 setInterval(()=>{if(!$("kkOverlay")?.classList.contains("hidden")&&room&&!loading&&!selectingIcon)void tick();},2200);
 setInterval(()=>{if(!$("kkOverlay")?.classList.contains("hidden")&&room&&clock?.status==="running"&&clock?.mode==="time")renderCountdown();},1000);
}
async function open(){
 $("kkOverlay").classList.remove("hidden");t("kkSub","Anslut till lärarens tävling");t("kkStudentStatus","Söker efter Kottkamper …");
 cancelAutoAdvance();stage("");$("kkLeaders").replaceChildren();room=null;question=null;selectingIcon=false;lastStatus="";endedSynced=false;prizesSynced=false;prizeNames=[];
 try{
 const x=await rpc("list");
 if(!x.sessions?.length){t("kkStudentStatus","Ingen Kottkamp finns för din klass just nu.");return;}
 // The server lists recent sessions in creation order. Old unstarted test
 // rooms must not crowd the lobby or compete with the current round.
 // An ongoing/paused round wins; otherwise only the newest round counts.
 const sessions=x.sessions;
 const current=sessions.find(s=>s.status==="running"||s.status==="paused")||sessions[0];
 if(current.status==="finished"){
  t("kkStudentStatus","Den senaste Kottkampen är avslutad.");
  const notice=document.createElement("p");notice.textContent="🏁 "+current.title+" är färdigspelad. Läraren kan starta en ny tävling från läraradmin.";
  $("kkStage").replaceChildren(notice);
  return;
 }
 if(current.status!=="waiting"&&current.status!=="running"&&current.status!=="paused"){
  t("kkStudentStatus","Ingen öppen Kottkamp just nu.");return;
 }
 t("kkStudentStatus",current.status==="waiting"?"En tävling är öppen för din klass:":"Klassens tävling pågår:");
 const button=document.createElement("button");button.type="button";button.className="primary";
 button.textContent=current.title+" · "+(current.status==="waiting"?"Anslut":current.status==="paused"?"Pausad":"Pågår");
 button.onclick=()=>void join(current.id);
 $("kkStage").replaceChildren(button);
 }catch(e){t("kkStudentStatus",e.message);}
}
async function join(id){
 cancelAutoAdvance();room=id;question=null;selectingIcon=true;pending=false;endedSynced=false;prizesSynced=false;prizeNames=[];
 stage("");t("kkStudentStatus","Välj din spelikon:");
 try{
  const data=await rpc("icons");
  if(data.mine){await rpc("join",{icon:data.mine});selectingIcon=false;await syncKottkampPrizes(true);await tick();return;}
  const taken=new Set(data.taken||[]);
  const board=document.createElement("div");
  board.style.cssText="display:grid;grid-template-columns:repeat(auto-fit,minmax(68px,1fr));gap:8px";
  KK_ICONS.forEach((icon,i)=>{
   const button=document.createElement("button");
   button.className="secondary";button.type="button";button.textContent=icon;button.title="Spelikon "+(i+1);
   button.setAttribute("aria-label","Välj spelikon "+(i+1)+": "+icon);
   button.style.cssText="font-size:32px;min-height:64px;padding:8px";
   button.disabled=taken.has(i+1);
   if(button.disabled){button.style.opacity="0.25";button.title="Redan vald av en annan elev";}
   button.onclick=async()=>{
    board.querySelectorAll("button").forEach(b=>b.disabled=true);
    try{await rpc("join",{icon:i+1});selectingIcon=false;stage("");await syncKottkampPrizes(true);await tick();}
    catch(e){t("kkStudentStatus",e.message==="icon_taken"?"Den ikonen valdes precis. Välj en annan!":e.message);await join(id);}
   };board.append(button);
  });
  const hint=document.createElement("p");hint.textContent="Välj en ledig ikon. Grå ikoner har redan valts av andra i klassen.";
  $("kkStage").replaceChildren(hint,board);
 }catch(e){t("kkStudentStatus",e.message);}
}
function renderCountdown(){
 if(!clock||clock.mode!=="time"||!clock.started_at)return;
 const end=new Date(clock.started_at).getTime()+(clock.minutes*60+clock.paused_seconds)*1000;
 const now=clock.status==="paused"?new Date(clock.paused_at).getTime():Date.now()+offsetMs;
 const left=Math.max(0,Math.ceil((end-now)/1000));
 t("kkTime",Math.floor(left/60)+":"+String(left%60).padStart(2,"0"));
}
function leaders(players){
 const host=$("kkLeaders");host.replaceChildren();
 for(const [i,p] of (players||[]).slice(0,12).entries()){
  const line=document.createElement("div");
  line.style.cssText="display:flex;justify-content:space-between;padding:5px 8px;border-bottom:1px solid #dce6d6;gap:8px";
  const a=document.createElement("span");a.textContent=(i+1)+". "+(p.icon_id?KK_ICONS[p.icon_id-1]+" ":"")+p.name;const b=document.createElement("b");b.textContent=p.score+" poäng";
  line.append(a,b);host.append(line);
 }
 if(!players?.length)host.textContent="Väntar på deltagare.";
}
async function tick(){
 if(!room||loading)return;loading=true;
 try{
 const r=await rpc("snapshot"),s=r.session;
 offsetMs=new Date(r.server_now).getTime()-Date.now();clock=s;
 leaders(r.players);t("kkSub",s.title+" · "+(s.mode==="time"?"Tidstävling":"Frågetävling"));
 if(s.status==="finished"){
  const reward=r.me?.reward;
  t("kkStudentStatus","🏁 Tävlingen är avslutad!");
  stage('<div style="padding:18px;text-align:center;background:#e8efd9;border-radius:12px"><h2>🎉 Målgång!</h2><div id="kkFinal" style="font-size:20px;font-weight:bold"></div></div>');
  t("kkFinal",(r.me.icon_id?KK_ICONS[r.me.icon_id-1]+" · ":"")+r.me.score+" tävlingspoäng · "+r.me.correct+" rätt · "+(reward??0)+" riktiga kottar");
  if(!endedSynced){endedSynced=true;void M()?.cloudCones?.sync?.();}
  if(lastStatus!=="finished")prizesSynced=false;
  try{await syncKottkampPrizes();}catch(error){console.warn("Kottkampen-belöning väntar:",error);}
  if(prizeNames.length)t("kkFinal",r.me.score+" tävlingspoäng · "+r.me.correct+" rätt · "+(reward??0)+" riktiga kottar · 🎁 "+prizeNames.join(", "));
  lastStatus="finished";return;
 }
 if(s.status==="waiting"){
  t("kkStudentStatus","Väntar på att läraren ska starta …");
  if(lastStatus!=="waiting")stage("<p>🌲 Du är anmäld! Läraren startar när klassen är redo.</p>");
  lastStatus="waiting";return;
 }
 if(s.status==="paused"){
  t("kkStudentStatus","⏸ Läraren har pausat tävlingen.");
  if(lastStatus!=="paused")stage("<p>Vänta tills läraren fortsätter.</p>");
  lastStatus="paused";return;
 }
 t("kkStudentStatus","🌰 "+r.me.score+" poäng · "+r.me.correct+" rätt · "+r.me.answered+" frågor lösta"+(s.mode==="time"?" · ⏱ ":"") );
 if(s.mode==="time"&&!$("kkTime")){$("kkStudentStatus").appendChild(document.createElement("strong")).id="kkTime";}
 renderCountdown();
 if(lastStatus!=="running"||(!question&&!pending))await getQuestion();
 lastStatus="running";
 }catch(e){t("kkStudentStatus",e.message);}finally{loading=false;}
}
async function getQuestion(){
 if(!room)return;
 try{
 const r=await rpc("question");
 if(r.status==="stump"){drawStumps();return;}
 if(r.status==="complete"){question=null;pending=true;stage("<h3>🎉 Alla frågor klara!</h3><p>Vänta på att läraren avslutar och delar ut kottarna.</p>");return;}
 if(r.status!=="question"){question=null;return;}
 question=r;pending=false;
 const host=document.createElement("div");host.style.cssText="display:grid;gap:13px";
 const header=document.createElement("div");header.textContent="Fråga "+(r.index+1)+" · "+label(r.game_id);header.style.fontWeight="800";header.textContent+=" · ✅ +100 rätt / ❌ −50 fel";
 const text=document.createElement("h2");text.style.cssText="text-align:center;padding:22px 9px;background:#eef4df;border-radius:12px;font-size:clamp(19px,4vw,27px)";text.textContent=r.prompt;
 const grid=document.createElement("div");grid.style.cssText="display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px";
 r.options.forEach((value,i)=>{const b=document.createElement("button");b.className="secondary";b.type="button";b.style.cssText="min-height:68px;font-size:21px;font-weight:900";b.textContent=value;b.onclick=()=>answer(i);grid.append(b);});
 const fb=document.createElement("div");fb.id="kkFeedback";fb.style.fontWeight="800";
 host.append(header,text,grid,fb);$("kkStage").replaceChildren(host);
 }catch(e){t("kkStudentStatus",e.message);}
}
const labels={percentConvert:"Procent och decimal",sharePart:"Beräkna andelen",percentChange:"Beräkna förändring",percentPart:"Beräkna delen",whole:"Beräkna det hela",fractionDecimal:"Bråk och decimal",multiplication:"Multiplikation",equations:"Ekvationer",pow10:"Tiopotenser",interest:"Ränta",unitConvert:"Enhetsomvandling",prefixMatch:"Prefix",statistics:"Statistik",fractionArithmetic:"Räkna med bråk",scientificNotation:"Grundpotensform"};
function label(id){return labels[id]||id;}
async function answer(choice){
 if(!question||pending)return;pending=true;
 try{
 const q=question,ans=await rpc("answer",{index:q.index,choice});
 question=null;
 $("kkStage").querySelectorAll("button").forEach(b=>b.disabled=true);
 t("kkFeedback",ans.correct?"✅ Rätt svar! +100 tävlingspoäng":"❌ Fel svar: −50 tävlingspoäng. Rätt svar: "+ans.correct_answer);
 const activeRoom=room;
 if(ans.stump){scheduleAutoAdvance(1300,activeRoom);}else{scheduleAutoAdvance(1300,activeRoom);}
 }catch(e){pending=false;t("kkStudentStatus",e.message);}
}
function drawStumps(){
 question=null;pending=true;
 const box=document.createElement("div");box.style.cssText="text-align:center;background:#eef4df;padding:20px;border-radius:13px";
 const title=document.createElement("h2");title.textContent="🪵 Tre mystiska stubbar!";
 const sub=document.createElement("p");sub.textContent="Du svarade rätt tre gånger! Välj en stubbe. Där kan finnas en bonus, tomma löv eller en ekorre som norpar tävlingspoäng.";
 const grid=document.createElement("div");grid.style.cssText="display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px";
 for(let slot=1;slot<=3;slot++){
  const b=document.createElement("button");b.className="secondary";b.type="button";b.style.cssText="min-height:100px;font-size:31px";b.textContent="🪵";b.setAttribute("aria-label","Välj stubbe "+slot);
  b.onclick=async()=>{grid.querySelectorAll("button").forEach(x=>x.disabled=true);try{
   const r=await rpc("stump",{slot});
   sub.textContent=r.award>0?"🌰 Extra "+r.award+" tävlingspoäng!":r.award<0?"🐿️ En ekorre norpade "+Math.abs(r.award)+" tävlingspoäng!":"🍂 Tom stubbe! Inga bonuspoäng.";
   if(r.prize_type){
    try{await syncKottkampPrizes(true);}catch(error){console.warn("Sällsynt fynd väntar på leverans:",error);}
    const name=r.prize_type==="decoration" ? (M()?.rewards?.findItem?.(r.prize_item)?.name||"en dekoration") : "en blind bag";
    sub.textContent+=" 🎉 SÄLLSYNT FYND! Du hittade "+name+"! Titta i ditt förråd.";
   }
   scheduleAutoAdvance(r.prize_type?3000:1700,room);
  }catch(e){sub.textContent=e.message;grid.querySelectorAll("button").forEach(x=>x.disabled=false);}};
  grid.append(b);
 }
 box.append(title,sub,grid);$("kkStage").replaceChildren(box);
}
document.addEventListener("DOMContentLoaded",install);
})();
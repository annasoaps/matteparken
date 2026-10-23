/* Kottkampen 1.2: persistent prize inbox, independent of the active game.
   The database owns all prize IDs. Local receipt prevents paying twice on the same park.
   The server confirmation is written only after the local reward function succeeds. */
(()=>{
 "use strict";
 const M=()=>window.Mattezoo;
 let syncing=null;
 const $=id=>document.getElementById(id);
 const types={seedPack:"Fröpåse",decorBox:"Dekorationslåda",blindBag:"Blind bag",decoration:"Dekoration"};
 const context=()=>({studentId:M()?.cloudStudent?.currentState?.()?.student?.id,client:M()?.cloudStudent?.getClient?.()});
 const safeText=v=>String(v??"");
 async function api(action="list",id=null){
   const {client,studentId}=context();
   if(!client||!studentId)throw Error("Logga in med elevkod i Dagens uppdrag för att se dina priser.");
   const {data,error}=await client.rpc("kottkamp_prize_inbox",{p_action:action,p_prize_id:id});
   if(error)throw error;
   if(!data?.ok)throw Error(data?.reason||"Kunde inte hämta tävlingspriser.");
   return data;
 }
 function localDelivered(prize,studentId){
   return Boolean(M()?.rewards?.hasKottkampReward?.(prize.id,studentId));
 }
 function prizeTitle(prize){
   if(prize.type==="decoration"){
     return M()?.rewards?.findItem?.(prize.item)?.name||"En dekoration";
   }
   return types[prize.type]||"Okänt pris";
 }
 async function performSync(){
   const {studentId}=context();
   if(!studentId)return {ok:false,reason:"student_login_required"};
   const data=await api("list");
   let newPrizes=0,existingPrizes=0,errors=[];
   const items=data.prizes||[];
   for(const p of items){
     // IMPORTANT: don't trust 'confirmed_at' as a substitute for the local receipt.
     // If the student opens another browser, each park has its own local state.
     try{
       const r=M()?.rewards?.grantKottkampReward?.(p,studentId);
       if(!r?.ok)throw Error(r?.reason||"Priset kunde inte läggas i förrådet.");
       if(r.granted)newPrizes++;else existingPrizes++;
       // Acknowledgement is informational, never the gate for local delivery.
       if(!p.confirmed_at){
         try{await api("confirm",p.id);}
         catch(e){console.warn("Kottkampen: levererat lokalt, men kvitto till servern väntar.",e);}
       }
     }catch(e){
       errors.push({id:p.id,name:prizeTitle(p),message:e?.message||"Leverans misslyckades"});
     }
   }
   const summary={ok:errors.length===0,newPrizes,existingPrizes,pending:errors.length,errors,prizes:items};
   renderStatus(summary);
   if(newPrizes>0){
     M()?.office?.render?.();
     M()?.park?.updateShopUI?.();
   }
   return summary;
 }
 function sync(){
   if(syncing)return syncing;
   syncing=performSync().finally(()=>{syncing=null;});
   return syncing;
 }
 function renderStatus(summary){
   const line=$("kkPrizeInboxNotice");
   if(line){
     if(summary.pending)line.textContent=summary.pending+" pris kunde inte levereras. Prova Hämta igen. Inget pris tas bort från servern.";
     else if(summary.newPrizes)line.textContent="🎁 "+summary.newPrizes+" nya priser finns nu i ditt förråd!";
     else line.textContent="Dina registrerade priser är synkade med förrådet på den här enheten.";
   }
 }
 function install(){
   if($("kkPrizeInboxButton"))return;
   const shelf=document.querySelector("#gameShelfDrawer .game-shelf");
   if(!shelf)return;
   const btn=document.createElement("button");
   btn.type="button";btn.id="kkPrizeInboxButton";btn.className="game-card";
   btn.innerHTML='<span class="shelf-cover" aria-hidden="true"><span class="shelf-volume">🎁</span><span class="shelf-symbol">📦 🌰</span><span class="shelf-cover-rule"></span></span><strong>Mina Kottkamp-priser</strong><span class="shelf-description">Hämta priser från tidigare tävlingar, även när spelet är avslutat.</span><span class="shelf-play" aria-hidden="true">Visa priser <span>↗</span></span>';
   shelf.append(btn);
   const shade=document.createElement("div");shade.id="kkPrizeInboxOverlay";shade.className="hidden";
   shade.style.cssText="position:fixed;inset:0;z-index:5100;background:#142a20ee;display:flex;align-items:center;justify-content:center;padding:12px;overflow:auto";
   shade.innerHTML='<section role="dialog" aria-modal="true" aria-label="Mina Kottkamp-priser" style="width:min(650px,100%);max-height:94vh;overflow:auto;background:#fffaf0;color:#294233;border:5px solid #536b4b;border-radius:16px;padding:20px">'
    +'<header style="display:flex;justify-content:space-between;gap:10px;align-items:center"><h2 style="margin:0">🎁 Mina Kottkamp-priser</h2><button type="button" class="secondary" id="kkPrizeInboxClose">Stäng ✕</button></header>'
    +'<p>Här finns dina vinster från alla Kottkamper. Priser som inte kommit fram kan hämtas igen.</p>'
    +'<div id="kkPrizeInboxNotice" role="status" aria-live="polite"></div>'
    +'<div id="kkPrizeInboxList" style="display:grid;gap:10px;margin:14px 0"></div>'
    +'<button type="button" class="primary" id="kkPrizeInboxRetry">↻ Hämta mina priser igen</button>'
    +'</section>';
   document.body.append(shade);
   $("kkPrizeInboxClose").onclick=()=>shade.classList.add("hidden");
   btn.onclick=()=>void open();
   $("kkPrizeInboxRetry").onclick=()=>void refresh(true);
 }
 async function refresh(runDelivery){
   const list=$("kkPrizeInboxList"),notice=$("kkPrizeInboxNotice"),retry=$("kkPrizeInboxRetry");
   if(!list)return;
   list.replaceChildren();retry.disabled=true;notice.textContent="Hämtar priser från Matteparken …";
   try{
     if(runDelivery)await sync();
     const r=await api("list");
     const studentId=context().studentId;
     const prizes=r.prizes||[];
     if(!prizes.length){
       const p=document.createElement("p");p.textContent="Du har inga registrerade Kottkamp-priser ännu.";list.append(p);
     } else for(const prize of prizes){
       const box=document.createElement("div");box.style.cssText="background:#edf3e1;border:1px solid #a9b897;border-radius:9px;padding:10px";
       const title=document.createElement("strong");title.textContent="🎁 "+prizeTitle(prize);
       const body=document.createElement("div");body.style.cssText="font-size:13px;margin-top:4px";
       body.textContent=safeText(prize.title)+" · "+(localDelivered(prize,studentId)?"✅ Finns i förrådet":prize.confirmed_at?"ℹ️ Bekräftad tidigare, kontrollera ditt förråd":"⏳ Väntar på leverans");
       box.append(title,body);list.append(box);
     }
     const pending=prizes.filter(p=>!localDelivered(p,studentId)).length;
     notice.textContent=pending
       ?pending+" pris saknar leveranskvitto på den här enheten. Tryck Hämta mina priser igen."
       :"Alla registrerade priser är inlagda i ditt förråd på den här enheten.";
   }catch(e){notice.textContent=e?.message||"Priserna kunde inte hämtas.";}
   finally{retry.disabled=false;}
 }
 async function open(){
   const shade=$("kkPrizeInboxOverlay");shade?.classList.remove("hidden");
   await refresh(true);
 }
 document.addEventListener("DOMContentLoaded",install);
 M().kottkampPrizeInbox={sync,open,prizeTitle};
})();
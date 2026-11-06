/* Novemberregn i Matteparken. Kort miljöhändelse utan poäng, elevdata eller nätljud. */
(() => {
 "use strict";
 function stockholmMonth(){
   try{return Number(new Intl.DateTimeFormat("en-GB",{timeZone:"Europe/Stockholm",month:"numeric"}).format(new Date()));}
   catch{return new Date().getMonth()+1;}
 }
 if(stockholmMonth()!==11)return;
 const MUTE_KEY="matteparkenNovemberRainSound_v1";
 const reduced=!!(window.matchMedia&&window.matchMedia("(prefers-reduced-motion: reduce)").matches);
 const FIRST=2*60*1000, INTERVAL=6*60*1000, DURATION=20000, PUDDLE_DURATION=38000;
 let park, rain, puddles, soundButton, audioCtx, audioSource, gain;
 let active=false, elapsed=0, due=FIRST+Math.random()*2*60*1000, events=0, maxEvents=3;
 let last=performance.now(),lastInput=performance.now(), rainEnd=0, puddleTimer=0, timer=0;
 let soundOn=false;
 try{soundOn=localStorage.getItem(MUTE_KEY)==="1";}catch{}
 const robinSVG='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 48" shape-rendering="crispEdges" aria-hidden="true"><path fill="#584a35" d="M11 35h25v5H11z"/><path fill="#5b4f3d" d="M12 12h23v26H12z"/><path fill="#81745a" d="M9 19h25v18H9z"/><path fill="#b9a88b" d="M13 9h18v20H13z"/><path fill="#cf7447" d="M18 14h16v17H18z"/><path fill="#e8a36a" d="M22 18h11v10H22z"/><path fill="#31372f" d="M28 14h4v4h-4z"/><path fill="#c49c55" d="M33 20h8v4h-8z"/><path stroke="#4e4031" stroke-width="2" d="M17 36v8m8-8v8m-11 0h7m1 0h7"/></svg>';
 function hasStudent(){return Boolean(window.Mattezoo?.cloudStudent?.activeStudent?.());}
 function canPlay(){
  if(document.hidden||!park||!park.isConnected||park.clientWidth<120)return false;
  if(document.querySelector(".modal-backdrop.open,.weekly-gate.open"))return false;
  for(const id of ["placementBanner","itemActionBanner"]){
   const el=document.getElementById(id);
   if(el&&getComputedStyle(el).display!=="none")return false;
  }
  return true;
 }
 function updateButton(){
  if(!soundButton)return;
  soundButton.textContent=soundOn?"🌧️ Ljud på":"🌧️ Ljud av";
  soundButton.setAttribute("aria-pressed",String(soundOn));
  soundButton.setAttribute("aria-label",soundOn?"Stäng av regnljud":"Sätt på regnljud");
 }
 function stopSound(){
  if(gain&&audioCtx){
   try{gain.gain.setTargetAtTime(0,audioCtx.currentTime,.12);}catch{}
  }
 }
 function startSound(){
  if(!soundOn||!active||document.hidden)return;
  try{
   const AudioContext=window.AudioContext||window.webkitAudioContext;
   if(!AudioContext)return;
   if(!audioCtx){
    audioCtx=new AudioContext();
    const seconds=2, sampleRate=audioCtx.sampleRate;
    const buf=audioCtx.createBuffer(1,seconds*sampleRate,sampleRate);
    const data=buf.getChannelData(0);
    // A mild loop of filtered random noise, generated locally; no external sound file.
    let prev=0;
    for(let i=0;i<data.length;i++){
      const white=Math.random()*2-1;
      prev=(prev+.04*white)/1.04;
      data[i]=prev*2.5;
    }
    audioSource=audioCtx.createBufferSource();
    audioSource.buffer=buf;audioSource.loop=true;
    const filter=audioCtx.createBiquadFilter();
    filter.type="lowpass";filter.frequency.value=1700;
    gain=audioCtx.createGain();gain.gain.value=0;
    audioSource.connect(filter);filter.connect(gain);gain.connect(audioCtx.destination);
    audioSource.start();
   }
   audioCtx.resume().then(()=>{if(soundOn&&active&&!document.hidden)gain.gain.setTargetAtTime(.065,audioCtx.currentTime,.25);}).catch(()=>{});
  }catch(e){ /* No sound support: weather continues silently. */ }
 }
 function removePuddles(){
  clearTimeout(puddleTimer);
  if(!puddles)return;
  puddles.classList.add("mz-puddles-leaving");
  puddleTimer=setTimeout(()=>{puddles.replaceChildren();puddles.hidden=true;puddles.classList.remove("mz-puddles-leaving");},3000);
 }
 function showPuddles(){
  clearTimeout(puddleTimer);
  puddles.replaceChildren();
  puddles.classList.remove("mz-puddles-leaving");
  const spots=[{x:27,y:67,w:9,h:3.8},{x:68,y:63,w:8,h:3.1},{x:42,y:30,w:6,h:2.4}];
  spots.forEach(({x,y,w,h})=>{
   const item=document.createElement("span");item.className="mz-november-puddle";
   item.style.setProperty("--left",x+"%");
   item.style.setProperty("--top",y+"%");
   item.style.setProperty("--width",w+"%");
   item.style.setProperty("--height",h+"%");
   puddles.appendChild(item);
  });
  if(!reduced&&Math.random()<.75){
   const bird=document.createElement("span");
   bird.className="mz-november-robin";bird.innerHTML=robinSVG;
   bird.style.setProperty("--left","68%");
   bird.style.setProperty("--top","63%");
   bird.setAttribute("aria-label","En rödhake besöker en vattenpöl");
   bird.setAttribute("role","img");
   puddles.appendChild(bird);
  }
  puddles.hidden=false;
  puddleTimer=setTimeout(removePuddles,PUDDLE_DURATION);
 }
 function stopRain(withPuddles){
  if(!active)return;
  active=false;rain.hidden=true;rain.replaceChildren();stopSound();
  if(withPuddles)showPuddles();
  due=elapsed+INTERVAL+Math.random()*4*60*1000;
 }
 function startRain(force=false){
  if(active||!canPlay()||(!force&&!hasStudent()))return false;
  if(!force&&events>=maxEvents)return false;
  active=true;rainEnd=performance.now()+DURATION;events++;
  if(!reduced){
   const frag=document.createDocumentFragment();
   const count=window.innerWidth<700?40:75;
   for(let i=0;i<count;i++){
    const drop=document.createElement("i");drop.className="mz-november-drop";
    drop.style.setProperty("--x",(Math.random()*145-8).toFixed(2)+"%");
    drop.style.setProperty("--length",(9+Math.random()*14).toFixed(1)+"px");
    drop.style.setProperty("--opacity",(.28+Math.random()*.43).toFixed(2));
    drop.style.setProperty("--duration",(1.3+Math.random()*.9).toFixed(2)+"s");
    drop.style.setProperty("--delay",(-Math.random()*2.4).toFixed(2)+"s");
    frag.appendChild(drop);
   }
   rain.replaceChildren(frag);rain.hidden=false;
  }
  startSound();
  return true;
 }
 function tick(){
  const now=performance.now(),dt=Math.max(0,Math.min(1500,now-last));last=now;
  if(stockholmMonth()!==11){stopRain(false);clearInterval(timer);removePuddles();soundButton?.remove();return;}
  if(active){
   if(document.hidden||!canPlay())stopRain(false);
   else if(now>=rainEnd)stopRain(true);
   return;
  }
  if(!document.hidden&&hasStudent()&&now-lastInput<2*60*1000&&canPlay())elapsed+=dt;
  if(events<maxEvents&&elapsed>=due)startRain();
 }
 function init(){
  park=document.querySelector("main.game > .park");
  if(!park)return;
  rain=document.createElement("div");rain.className="mz-november-rain";rain.hidden=true;
  rain.setAttribute("aria-hidden","true");
  puddles=document.createElement("div");puddles.className="mz-november-puddles";puddles.hidden=true;
  park.append(puddles,rain);
  soundButton=document.createElement("button");soundButton.type="button";
  soundButton.className="mz-november-audio";updateButton();
  soundButton.addEventListener("click",e=>{
   e.stopPropagation();soundOn=!soundOn;
   try{localStorage.setItem(MUTE_KEY,soundOn?"1":"0");}catch{}
   updateButton();if(soundOn)startSound();else stopSound();
  });
  park.appendChild(soundButton);
  document.addEventListener("pointerdown",()=>{lastInput=performance.now();},{passive:true});
  document.addEventListener("keydown",()=>{lastInput=performance.now();});
  document.addEventListener("visibilitychange",()=>{last=performance.now();if(document.hidden)stopRain(false);});
  timer=setInterval(tick,500);
  window.Mattezoo=window.Mattezoo||{};
  window.Mattezoo.novemberRain={preview:()=>startRain(true),stop:()=>stopRain(true)};
 }
 if(document.readyState==="loading")document.addEventListener("DOMContentLoaded",init,{once:true});
 else init();
})();

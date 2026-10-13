
/* Svampstigen v1. Isolerad från fisket och övriga spel. */
(function () {
  "use strict";
  const MZ = window.Mattezoo;
  if (!MZ || !MZ.state || !MZ.habitats) return;
  const byId = id => document.getElementById(id);
  const SPECIES = [
    {id:"kantarell",name:"Kantarell",color:"#e6ad38",dark:"#a56b25",weight:36,min:20,max:110,rarity:"Vanlig"},
    {id:"bjorksopp",name:"Björksopp",color:"#ac8560",dark:"#614d38",weight:28,min:35,max:180,rarity:"Vanlig"},
    {id:"karljohan",name:"Karljohan",color:"#9a633c",dark:"#543e2a",weight:19,min:45,max:280,rarity:"Ovanlig"},
    {id:"flugsvamp",name:"Röd flugsvamp",color:"#c74330",dark:"#8d3029",weight:12,min:40,max:195,rarity:"Ovanlig",spots:true},
    {id:"fjallskivling",name:"Stolt fjällskivling",color:"#c7aa78",dark:"#836b4d",weight:5,min:65,max:330,rarity:"Sällsynt"}
  ];
  const COVERS = ["stone","stump","spruce"];
  const COVER_NAMES = {stone:"Mossig sten",stump:"Gammal stubbe",spruce:"Under granen"};
  const DIRECTIONS = [
    {id:"left",name:"⬅ Vänster"},
    {id:"straight",name:"⬆ Rakt fram"},
    {id:"right",name:"Höger ➡"}
  ];
  const STORE_KEY = "matteparkenSvampstigen_v1";
  let progress = {catches:{},records:{}};
  let factBag = [];
  let round = {};
  let modal;
  let launcher;
  let guideTab;

  function ownerKey() {
    const active = MZ.cloudStudent && MZ.cloudStudent.activeStudent && MZ.cloudStudent.activeStudent();
    return active && active.student && active.student.id ? "student:" + active.student.id : "guest";
  }
  function allSaved() {
    try {
      const data = JSON.parse(localStorage.getItem(STORE_KEY) || "{}");
      return data && typeof data === "object" && !Array.isArray(data) ? data : {};
    } catch (_) { return {}; }
  }
  function loadProgress() {
    const data = allSaved()[ownerKey()] || {};
    progress = {
      catches: data.catches && typeof data.catches === "object" ? data.catches : {},
      records: data.records && typeof data.records === "object" ? data.records : {}
    };
  }
  function saveProgress() {
    try {
      const data = allSaved();
      data[ownerKey()] = progress;
      localStorage.setItem(STORE_KEY, JSON.stringify(data));
    } catch (_) { /* Spela vidare även om lagring inte är tillgänglig. */ }
  }
  function pickSpecies() {
    let draw = Math.random() * SPECIES.reduce((total, sp) => total + sp.weight, 0);
    return SPECIES.find(sp => (draw -= sp.weight) < 0) || SPECIES[0];
  }
  function pickSize(sp) {
    // Storlek i tiondels centimeter. Stora exemplar är ovanligare.
    const bias = (Math.random() + Math.random() + Math.random()) / 3;
    return Math.round(sp.min + (sp.max - sp.min) * bias);
  }
  function sizeText(tenths) {
    return (Number(tenths) / 10).toFixed(1).replace(".", ",") + " cm";
  }
  function refillFacts() {
    factBag = [];
    for (let a = 2; a <= 10; a++) {
      for (let b = a; b <= 10; b++) factBag.push({a,b});
    }
    for (let i = factBag.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      const tmp = factBag[i]; factBag[i] = factBag[j]; factBag[j] = tmp;
    }
  }
  // Byt uppgiftstyp här senare utan att ändra spelets vägval eller belöningar.
  function nextMathQuestion() {
    if (!factBag.length) refillFacts();
    const q = factBag.pop();
    if (q.a !== q.b && Math.random() < .5) return {a:q.b,b:q.a,answer:q.a*q.b};
    return {a:q.a,b:q.b,answer:q.a*q.b};
  }
  function mushroomSvg(sp) {
    if (!sp) return "";
    const spots = sp.spots
      ? '<rect x="17" y="21" width="7" height="5" fill="#fff3d1"/><rect x="35" y="17" width="6" height="5" fill="#fff3d1"/><rect x="43" y="25" width="5" height="4" fill="#fff3d1"/>'
      : '<rect x="18" y="24" width="9" height="3" fill="#f9e4a5" opacity=".45"/>';
    return '<svg viewBox="0 0 64 64" xmlns="http://www.w3.org/2000/svg" role="img" aria-label="'+sp.name+'" shape-rendering="crispEdges">'
      + '<rect x="29" y="31" width="11" height="25" fill="#d6c6a0"/><rect x="29" y="36" width="3" height="19" fill="#fff0ca"/>'
      + '<path d="M6 34 L10 24 L16 18 L22 15 L40 15 L49 19 L55 26 L58 34 L54 37 L11 37 Z" fill="'+sp.color+'" stroke="'+sp.dark+'" stroke-width="3" stroke-linejoin="miter"/>'
      + spots + '<rect x="24" y="55" width="22" height="4" fill="#718657"/><rect x="19" y="59" width="30" height="3" fill="#4e6845"/>'
      + '</svg>';
  }
  function tree(x,y,scale,shade) {
    return '<g transform="translate('+x+' '+y+') scale('+scale+')" shape-rendering="crispEdges">'
      + '<rect x="-7" y="60" width="14" height="68" fill="#584934"/>'
      + '<path d="M0 -10 L-62 77 L-42 77 L-75 109 L75 109 L42 77 L62 77 Z" fill="'+shade+'" stroke="#244b3a" stroke-width="5"/>'
      + '<path d="M0 0 L-40 64 L-19 64 L-42 89 L0 83 Z" fill="#83a16a" opacity=".46"/>'
      + '</g>';
  }
  function makeLandscape() {
    const parts = [
      '<svg class="sp-landscape" viewBox="0 0 800 400" preserveAspectRatio="xMidYMid slice" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" shape-rendering="crispEdges">',
      '<rect width="800" height="400" fill="#c2d9ae"/>',
      '<rect y="90" width="800" height="310" fill="#7fa06c"/>',
      '<path d="M0 218 L100 190 L210 212 L305 184 L440 219 L550 181 L670 207 L800 183 L800 400 L0 400Z" fill="#567f58"/>',
      '<path d="M0 390 L200 306 L310 235 L353 205 L444 205 L480 235 L605 306 L800 390 L800 400 L0 400Z" fill="#b7a077"/>',
      '<path d="M310 235 L0 270 L0 340 L353 205Z" fill="#c9ad7d"/>',
      '<path d="M444 205 L800 267 L800 338 L480 235Z" fill="#c9ad7d"/>',
      '<path d="M352 205 L443 205 L487 400 L316 400Z" fill="#cdb88a"/>',
      '<path d="M360 213 L441 213 L470 400 L338 400Z" fill="#d9c499"/>'
    ];
    [[40,115,1.2,"#3b6646"],[147,92,.94,"#46724e"],[235,78,.65,"#547e53"],[558,95,.82,"#456f4b"],[664,98,1.1,"#3d6948"],[765,94,1.15,"#3e6846"]]
      .forEach(t => parts.push(tree(t[0],t[1],t[2],t[3])));
    // Enkla pixelblock ger sten, stubbe och ormbunkar utan separata tunga bilder.
    parts.push('<path d="M36 322 L79 277 L123 284 L153 344 L143 365 L35 365Z" fill="#82917c" stroke="#4a604b" stroke-width="8"/>');
    parts.push('<path d="M660 339 L663 275 L738 275 L741 353 L655 353Z" fill="#765539" stroke="#59432e" stroke-width="8"/>');
    parts.push('<ellipse cx="701" cy="275" rx="41" ry="13" fill="#b19268" stroke="#624930" stroke-width="7"/>');
    for (let i = 0; i < 16; i++) {
      const x = 24 + i * 51;
      const y = 342 + (i % 3) * 12;
      parts.push('<rect x="'+x+'" y="'+y+'" width="12" height="7" fill="#426f49" opacity=".9"/>');
    }
    parts.push('</svg>');
    return parts.join("");
  }
  const LANDSCAPE = makeLandscape();

  function startRound() {
    round = {
      step:0,
      target:1 + Math.floor(Math.random()*3),
      phase:"choose",
      direction:null,
      cover:null,
      question:null,
      species:null,
      size:0,
      error:""
    };
    render();
  }
  function selectDirection(direction) {
    if (round.phase !== "choose") return;
    round.direction = direction;
    round.cover = COVERS[Math.floor(Math.random() * COVERS.length)];
    round.question = nextMathQuestion();
    round.error = "";
    round.phase = "math";
    render();
    const input = byId("spAnswer");
    if (input) input.focus();
  }
  function answer() {
    if (round.phase !== "math" || !round.question) return;
    const value = byId("spAnswer") ? byId("spAnswer").value.trim() : "";
    if (value === "") return;
    if (Number(value) !== round.question.answer) {
      round.error = "Inte riktigt! Försök igen.";
      const message = byId("spError");
      if (message) message.textContent = round.error;
      if (byId("spAnswer")) { byId("spAnswer").select(); byId("spAnswer").focus(); }
      return;
    }
    round.step++;
    round.error = "";
    if (round.step === round.target) {
      round.species = pickSpecies();
      round.size = pickSize(round.species);
      round.phase = "search";
    } else round.phase = "empty";
    render();
  }
  function discover() {
    if (round.phase !== "search" || !round.species) return;
    const sp = round.species;
    const previous = Math.max(0, Number(progress.catches[sp.id]) || 0);
    const oldRecord = Math.max(0, Number(progress.records[sp.id]) || 0);
    progress.catches[sp.id] = previous + 1;
    if (round.size > oldRecord) progress.records[sp.id] = round.size;
    round.first = previous === 0;
    round.record = round.size > oldRecord;
    saveProgress();
    round.phase = "found";
    render();
  }
  function drawScene() {
    let content = '<div class="sp-scene">'+LANDSCAPE;
    if (round.phase === "choose") {
      content += '<div class="sp-place">Välj en stig · stopp '+(round.step+1)+' av högst 3</div>';
      content += '<div class="sp-choices">'+DIRECTIONS.map(d => '<button type="button" data-sp-dir="'+d.id+'">'+d.name+'</button>').join("")+'</div>';
    } else if (round.phase === "search") {
      content += '<div class="sp-place">'+COVER_NAMES[round.cover]+'</div>';
      content += '<button type="button" class="sp-spot sp-'+round.cover+'" id="spDiscover" aria-label="Jag hittade svampen! Klicka för att upptäcka den.">'
        + '<span class="sp-specimen">'+mushroomSvg(round.species)+'</span></button>';
    } else {
      content += '<div class="sp-place">'+(round.cover ? COVER_NAMES[round.cover] : "Svampstigen")+'</div>';
    }
    return content + '</div>';
  }
  function render() {
    if (!modal) return;
    const body = byId("spBody");
    if (!body) return;
    let html = drawScene();
    if (round.phase === "choose") {
      html += '<div class="sp-panel"><strong>Vart vill du gå?</strong><p>Välj vänster, rakt fram eller höger och lös ett tal för att följa stigen.</p></div>';
    } else if (round.phase === "math") {
      const q = round.question;
      html += '<div class="sp-panel"><strong>Följ stigen!</strong><div class="sp-question">'+q.a+' × '+q.b+' = ?</div>'
        + '<div class="sp-answer-wrap"><input class="sp-answer" id="spAnswer" type="text" inputmode="numeric" autocomplete="off" aria-label="Svar på multiplikationen" maxlength="3"/><button type="button" class="sp-primary" id="spSubmit">Gå vidare</button></div>'
        + '<p class="sp-error" id="spError" role="status">'+round.error+'</p></div>';
    } else if (round.phase === "empty") {
      html += '<div class="sp-panel"><strong>Ingen svamp här den här gången.</strong><p>Det prasslar längre bort bland träden …</p><button type="button" class="sp-primary" id="spNext">Fortsätt leta →</button></div>';
    } else if (round.phase === "search") {
      html += '<div class="sp-panel"><strong>Vänta … ser du något bakom '+COVER_NAMES[round.cover].toLowerCase()+'?</strong><p>Klicka på svampen som sticker fram!</p></div>';
    } else if (round.phase === "found") {
      const sp=round.species;
      const count=progress.catches[sp.id];
      const record=progress.records[sp.id];
      html += '<div class="sp-panel"><div class="sp-discovery">'+mushroomSvg(sp)+'<div><strong>'
        +(round.first ? "🍄 NY SVAMPART!" : round.record ? "🏆 NYTT REKORD!" : "🍄 SVAMP HITTAD!")
        +'</strong><h3>'+sp.name+'</h3><p>Hattdiameter: <strong>'+sizeText(round.size)+'</strong></p><p class="sp-record">Rekord: '+sizeText(record)+'</p><small>'+sp.rarity+' · hittad '+count+' gånger</small></div></div></div>';
    }
    if (round.phase === "found") html += '<div class="sp-actions"><button type="button" class="sp-primary" id="spAgain">🍄 Leta igen</button><button type="button" class="sp-secondary" id="spClose">Tillbaka till parken</button></div>';
    html += '<div class="sp-foot">Multiplikation 2–10 · dina fynd hamnar i Fältguiden</div>';
    body.innerHTML = html;
    body.querySelectorAll("[data-sp-dir]").forEach(button => button.addEventListener("click",() => selectDirection(button.dataset.spDir)));
    byId("spSubmit")?.addEventListener("click",answer);
    byId("spAnswer")?.addEventListener("keydown",event=>{if(event.key==="Enter") answer();});
    byId("spNext")?.addEventListener("click",()=>{round.phase="choose";render();});
    byId("spDiscover")?.addEventListener("click",discover);
    byId("spAgain")?.addEventListener("click",startRound);
    byId("spClose")?.addEventListener("click",close);
  }
  function open() {
    if (!MZ.habitats.isUnlocked("northwest") || !MZ.state.onboarding?.keyTaken) return;
    loadProgress();
    startRound();
    MZ.openModal("svampstigenModal");
  }
  function close() {
    MZ.closeModal("svampstigenModal");
  }
  function refreshLauncher() {
    if (!launcher) return;
    const unlocked = MZ.habitats.isUnlocked("northwest") && !!MZ.state.onboarding?.keyTaken;
    launcher.classList.toggle("hidden",!unlocked);
  }
  function showGuide() {
    if (!guideTab) return;
    loadProgress();
    const grid = byId("fieldGuideGrid");
    if (!grid) return;
    guideTab.classList.add("active");
    byId("fieldGuideFishTab")?.classList.remove("active");
    byId("fieldGuideWildlifeTab")?.classList.remove("active");
    const found = SPECIES.filter(sp => Number(progress.catches[sp.id]) > 0).length;
    const count = byId("fieldGuideCount");
    if (count) count.textContent = found+" / "+SPECIES.length;
    const label = byId("fieldGuideProgressLabel");
    if (label) label.textContent = "svampar upptäckta";
    const intro = byId("fieldGuideIntro");
    if (intro) intro.textContent = "Svampar du hittar längs Svampstigen sparas här.";
    grid.innerHTML = "";
    SPECIES.forEach(sp=>{
      const catches = Math.max(0,Number(progress.catches[sp.id])||0);
      const record = Math.max(0,Number(progress.records[sp.id])||0);
      const card=document.createElement("article");
      card.className="field-guide-card "+(catches?"discovered":"unknown");
      if (catches) {
        card.innerHTML='<div class="field-guide-icon sp-guide-img">'+mushroomSvg(sp)+'</div><div class="field-guide-entry-copy"><div class="field-guide-kicker">Upptäckt svamp · '+sp.rarity+'</div><h3>'+sp.name+'</h3><p>Hittad '+catches+' gånger</p><p>🏆 Största hatt: '+sizeText(record)+'</p></div>';
      } else {
        card.innerHTML='<div class="field-guide-icon unknown-mark">?</div><div class="field-guide-entry-copy"><div class="field-guide-kicker">Inte upptäckt ännu</div><h3>Okänd svamp</h3><p>Följ stigen och se vad som gömmer sig.</p></div>';
      }
      grid.appendChild(card);
    });
  }
  function init() {
    const park = document.querySelector(".park");
    if (!park || !byId("fieldGuideFishTab")) return;
    launcher=document.createElement("button");
    launcher.type="button";
    launcher.className="sp-launcher hidden";
    launcher.textContent="🍄 Svampstigen";
    launcher.title="Utforska Skogsdungen och hitta svampar";
    launcher.setAttribute("aria-label","Starta minispel Svampstigen");
    park.appendChild(launcher);
    launcher.addEventListener("click",event=>{event.stopPropagation();if(park.classList.contains("carrying-item"))return;open();});
    modal=document.createElement("div");
    modal.className="modal-backdrop";
    modal.id="svampstigenModal";
    modal.innerHTML='<section class="sp-dialog" role="dialog" aria-modal="true" aria-labelledby="spHeading">'
      +'<button type="button" class="close" id="spCloseX" aria-label="Stäng">×</button>'
      +'<header class="sp-head"><div><h2 id="spHeading">🍄 Svampstigen</h2><p>En liten jakt i Skogsdungen</p></div></header>'
      +'<div id="spBody"></div></section>';
    document.body.appendChild(modal);
    byId("spCloseX").addEventListener("click",close);
    modal.addEventListener("click",event=>{if(event.target===modal)close();});
    modal.addEventListener("keydown",event=>{if(event.key==="Escape"){event.preventDefault();close();launcher.focus();}});
    const tabs=byId("fieldGuideFishTab").parentElement;
    guideTab=document.createElement("button");
    guideTab.type="button";
    guideTab.id="fieldGuideMushroomTab";
    guideTab.className="secondary";
    guideTab.textContent="🍄 Svampar";
    tabs.appendChild(guideTab);
    guideTab.addEventListener("click",showGuide);
    ["fieldGuideFishTab","fieldGuideWildlifeTab"].forEach(id=>{
      byId(id).addEventListener("click",()=>guideTab.classList.remove("active"));
    });
    byId("openFieldGuide")?.addEventListener("click",()=>guideTab.classList.remove("active"));
    MZ.events.addEventListener("habitatchange",refreshLauncher);
    MZ.events.addEventListener("wildlifechange",refreshLauncher);
    refreshLauncher();
  }
  MZ.svampstigen = {open, close, startRound};
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded",init);
  else init();
})();

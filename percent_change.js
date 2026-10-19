/* Beräkna förändring: 3 uppgifter, minskande stöd och Matteparkens egna sprites. */
(() => {
  "use strict";
  const MZ=window.Mattezoo;
  if(!MZ || !MZ.math) return;
  const $=(id)=>document.getElementById(id);
  const pick=(arr)=>arr[Math.floor(Math.random()*arr.length)];
  function shuffle(arr){
    const a=[...arr];
    for(let i=a.length-1;i>0;i--){const j=Math.floor(Math.random()*(i+1));[a[i],a[j]]=[a[j],a[i]];}
    return a;
  }
  const fmt=(n)=>String(n).replace(".",",");
  const toNumber=(value)=>{
    const s=String(value||"").trim().replace(/\s/g,"").replace(",",".");
    return s!=="" && Number.isFinite(Number(s)) ? Number(s) : NaN;
  };

  // Sprites hämtade ur den existerande park-, fisk- och djurkatalogen.
  const scenes=[
    {kind:"price",name:"Parkbänk",sprite:"assets/asset_025_f401b526b32e3899.png"},
    {kind:"price",name:"Fågelbad",sprite:"assets/asset_078_81345a4252eccd45.png"},
    {kind:"price",name:"Fågelholk",sprite:"assets/asset_077_68c74a47e42cac8e.png"},
    {kind:"price",name:"Insektshotell",sprite:"assets/asset_076_83787b2cf30cc428.png"},
    {kind:"price",name:"Fiskestol",sprite:"assets/asset_044_bd359c4db667a2b7.png"},
    {kind:"fish",name:"Abborre",sprite:"assets/asset_010_4d934d32860a6f71.png"},
    {kind:"fish",name:"Mört",sprite:"assets/asset_009_0acf7f453fafef11.png"},
    {kind:"fish",name:"Björkna",sprite:"assets/asset_011_af68fed0e2a7b71f.png"},
    {kind:"fish",name:"Sarv",sprite:"assets/asset_012_f1f3ee8e3e1700c4.png"},
    {kind:"fish",name:"Braxen",sprite:"assets/asset_014_dc2996f6647f44cb.png"},
    {kind:"fish",name:"Sutare",sprite:"assets/asset_016_b7e817f9f96a8ad7.png"},
    {kind:"fish",name:"Gädda",sprite:"assets/asset_018_0b60142227813124.png"},
    {kind:"wildlife",name:"Ekorrar",sprite:"assets/asset_096_ce74dff387440071.png",plural:"ekorrar"},
    {kind:"wildlife",name:"Nyckelpigor",sprite:"assets/asset_094_d009886419d7962c.png",plural:"nyckelpigor"},
    {kind:"wildlife",name:"Igelkottar",sprite:"assets/asset_097_f11e3af0d2f58427.png",plural:"igelkottar"},
    {kind:"wildlife",name:"Fjärilar",sprite:"assets/asset_091_e5e08e43b416da8e.png",plural:"fjärilar"},
    {kind:"wildlife",name:"Grodor",sprite:"assets/asset_088_48ecad7f46b02390.png",plural:"grodor"},
    {kind:"wildlife",name:"Svarta katter",sprite:"assets/autumn/black_cat_1.png",plural:"svarta katter"},
    {kind:"stock",name:"Pumpor",sprite:"assets/autumn/pumpkins.png",plural:"pumpor"},
    {kind:"stock",name:"Höstblommor",sprite:"assets/autumn/autumn_pot.png",plural:"höstblommor"},
    {kind:"stock",name:"Lövkorgar",sprite:"assets/autumn/leaf_basket.png",plural:"lövkorgar"},
    {kind:"stock",name:"Äppelkorgar",sprite:"assets/autumn/apple_basket.png",plural:"äppelkorgar"},
    {kind:"stock",name:"Lövhögar",sprite:"assets/autumn/leaf_pile.png",plural:"lövhögar"},
    {kind:"stock",name:"Soppar",sprite:"assets/autumn/boletes.png",plural:"svampar"},
    {kind:"stock",name:"Fjällskivlingar",sprite:"assets/autumn/parasol_mushroom.png",plural:"fjällskivlingar"}
  ];
  const starts={
    price:[100,120,150,160,200,240,250,300,400,500],
    fish:[160,200,240,250,300,320,400,480,500,600,800,1000],
    wildlife:[12,16,20,24,25,30,32,40,50,60],
    stock:[12,16,20,24,25,30,40,50,60]
  };
  const changes=[10,12,15,20,25,30,40,50];
  let questions=[],index=0,step=0,solved=false,finished=false,formulaVisible=true,hintLevel=0,reward=0;

  function makeProblem(scene,direction){
    let start=pick(starts[scene.kind]),change=pick(changes);
    if(scene.kind==="stock" || scene.kind==="wildlife") change=pick([10,20,25,30,40,50]);
    let difference=Math.max(1,Math.round(start*change/100));
    if(direction==="decrease" && difference>=start)difference=start-1;
    const end=start+(direction==="increase"?difference:-difference);
    const percent=Math.round(difference/start*100);
    const unit=scene.kind==="fish"?"g":scene.kind==="price"?"kottar":"st";
    const title=scene.kind==="price"?"Parkens prislista":scene.kind==="fish"?"Fiskar i sjön":scene.kind==="wildlife"?"Djurlivet i parken":"Parkens förråd";
    let text;
    if(scene.kind==="price") text="I ett räkneexempel var priset på "+scene.name.toLowerCase()+" tidigare "+start+" kottar. Nu är priset "+end+" kottar.";
    else if(scene.kind==="fish") text="Förra veckans "+scene.name.toLowerCase()+" vägde "+start+" g. Den här veckans fångst väger "+end+" g.";
    else if(scene.kind==="wildlife") text="Förra veckan såg parkvakten "+start+" "+scene.plural+". Den här veckan sågs "+end+".";
    else text="Tidigare fanns "+start+" "+scene.plural+" i parkens förråd. Nu finns "+end+".";
    return {scene,direction,start,end,difference,percent,unit,title,text};
  }
  function makeRound(){
    const kinds=shuffle(["price","fish","wildlife","stock"]).slice(0,3);
    const directions=shuffle(["increase","decrease",Math.random()<.5?"increase":"decrease"]);
    questions=kinds.map((kind,i)=>makeProblem(pick(scenes.filter(s=>s.kind===kind)),directions[i]));
  }
  function show(id,yes){const n=$(id);if(n)n.classList.toggle("hidden",!yes);}
  function current(){return questions[index];}
  function begin(){
    makeRound();index=0;step=0;solved=false;finished=false;hintLevel=0;reward=0;formulaVisible=true;
    show("pcFinished",false);show("pcMain",true);render();
  }
  function open(){
    const other=["fieldGuideView","seedQuestView","dailyQuestView","multiplicationView","equationsView","pow10View","fractionDecimalView","fractionArithmeticView","mgnView","percentConvertView","sharePartView","prefixMatchView","unitConvertView","statisticsView","scientificNotationView","activityView"];
    other.forEach(id=>show(id,false));
    show("officeHome",false);show("percentChangeView",true);
    $("pcNp").textContent=MZ.storage.getNaturePoints();
    begin();
  }
  function back(){show("percentChangeView",false);show("officeHome",true);}

  function stagePrompt(q){
    if(index===2)return "Med hur många hela procent har värdet förändrats?";
    if(step===0)return "Vilket var värdet från början?";
    if(step===1)return "Hur stor är skillnaden (differensen)?";
    if(step===2)return index===0?"Vilken division är rätt?":"Skriv divisionen: skillnaden ÷ värdet från början.";
    return "Hur stor är förändringen i hela procent? Ökning eller minskning?";
  }
  const labelDirection=(q)=>q.direction==="increase"?"ökning":"minskning";
  function mcOptions(q){
    const n=(v)=>fmt(v)+" "+q.unit;
    if(step===0)return shuffle([...new Set([n(q.start),n(q.end),n(q.difference),n(q.start+10)])].slice(0,3));
    if(step===1)return shuffle([...new Set([n(q.difference),n(q.start),n(q.end),n(q.difference+10)])].slice(0,3));
    if(step===2)return shuffle([fmt(q.difference)+" ÷ "+fmt(q.start),fmt(q.difference)+" ÷ "+fmt(q.end),fmt(q.start)+" ÷ "+fmt(q.difference)]);
    const right=q.percent+" % "+labelDirection(q);
    const opposite=q.percent+" % "+(q.direction==="increase"?"minskning":"ökning");
    const wrong=(q.percent===50?25:q.percent+10)+" % "+labelDirection(q);
    return shuffle([right,opposite,wrong]);
  }
  function correctMc(q){
    if(step===0)return fmt(q.start)+" "+q.unit;
    if(step===1)return fmt(q.difference)+" "+q.unit;
    if(step===2)return fmt(q.difference)+" ÷ "+fmt(q.start);
    return q.percent+" % "+labelDirection(q);
  }
  function inputHtml(){
    if(index===0)return '<div class="pc-choices" id="pcChoices"></div>';
    if(index===1&&step===2){
      return '<div class="pc-inputs"><label>Skillnaden<input id="pcNumerator" type="text" inputmode="decimal" autocomplete="off" aria-label="Skillnaden" placeholder="Täljare"></label><span class="pc-divide">÷</span><label>Värdet från början<input id="pcDenominator" type="text" inputmode="decimal" autocomplete="off" aria-label="Värdet från början" placeholder="Nämnare"></label></div>';
    }
    if((index===1&&step===3)||index===2){
      return '<div class="pc-inputs"><label>Förändring i hela procent<input id="pcAnswer" type="text" inputmode="numeric" autocomplete="off" placeholder="Procent"></label><label>Förändringen är<select id="pcDirection" aria-label="Ökning eller minskning"><option value="">Välj …</option><option value="increase">Ökning</option><option value="decrease">Minskning</option></select></label></div>';
    }
    return '<div class="pc-inputs"><label>'+ (step===0?"Värdet från början":"Skillnaden") +'<input id="pcAnswer" type="text" inputmode="decimal" autocomplete="off" placeholder="Skriv talet"></label><span>'+current().unit+'</span></div>';
  }
  function feedback(text,good){
    const n=$("pcFeedback");n.textContent=text;n.className="pc-feedback "+(good?"good":"bad");
  }
  function clearFeedback(){$("pcFeedback").textContent="";$("pcFeedback").className="pc-feedback";}
  function showFormula(){
    show("pcFormula",formulaVisible);
    $("pcFormulaBtn").textContent=formulaVisible?"Dölj formeln":"Visa formeln";
  }
  function render(){
    if(finished)return;
    const q=current();
    $("pcProgressText").textContent="Uppgift "+(index+1)+" av 3";
    $("pcProgressFill").style.width=(index/3*100)+"%";
    $("pcMode").textContent=["1 · Välj rätt svar","2 · Skriv med stöd","3 · Räkna själv"][index];
    $("pcStory").textContent=q.text;
    $("pcTopic").textContent=q.title;
    $("pcBeforeValue").textContent=fmt(q.start)+" "+q.unit;
    $("pcAfterValue").textContent=fmt(q.end)+" "+q.unit;
    $("pcBeforeImg").src=q.scene.sprite;
    $("pcAfterImg").src=q.scene.sprite;
    $("pcBeforeImg").alt=q.scene.name;
    $("pcAfterImg").alt=q.scene.name;
    $("pcPrompt").textContent=stagePrompt(q);
    $("pcResponse").innerHTML=inputHtml();
    if(index===0){
      const all=mcOptions(q),list=$("pcChoices");
      all.forEach(val=>{
        const b=document.createElement("button");b.type="button";b.className="pc-choice";b.textContent=val;
        b.addEventListener("click",()=>answerMc(val));list.appendChild(b);
      });
    }
    $("pcHintBtn").textContent="Ledtråd";
    show("pcHintBtn",index!==0);
    show("pcHint",false);
    show("pcCheck",index!==0);
    show("pcNext",false);
    showFormula();
    $("pcCheck").disabled=false;
    solved=false;hintLevel=0;clearFeedback();
    const first=$("pcAnswer")||$("pcNumerator");
    if(first)first.addEventListener("keydown",e=>{if(e.key==="Enter")check();});
    const second=$("pcDenominator");if(second)second.addEventListener("keydown",e=>{if(e.key==="Enter")check();});
    const dir=$("pcDirection");if(dir)dir.addEventListener("keydown",e=>{if(e.key==="Enter")check();});
  }
  function stepExplanation(q){
    if(step===0)return "Vi jämför alltid med värdet från början: "+q.start+" "+q.unit+".";
    if(step===1)return "Skillnaden är "+Math.max(q.start,q.end)+" − "+Math.min(q.start,q.end)+" = "+q.difference+" "+q.unit+".";
    if(step===2)return "Skillnaden ÷ värdet från början = "+q.difference+" ÷ "+q.start+".";
    return "Rätt! "+q.difference+" ÷ "+q.start+" × 100 ≈ "+q.percent+" %. Det är en "+labelDirection(q)+".";
  }
  function acceptStep(){
    solved=true;
    show("pcNext",true);show("pcCheck",false);
    if(index===0)$("pcChoices").querySelectorAll("button").forEach(b=>{b.disabled=true;if(b.textContent===correctMc(current()))b.style.borderColor="#589462";});
    feedback(stepExplanation(current()),true);
    $("pcNext").focus();
  }
  function answerMc(v){
    if(solved)return;
    if(v===correctMc(current()))acceptStep();
    else feedback(step===0?"Tänk på vilket värde som gällde tidigare.":step===1?"Beräkna skillnaden mellan talen.":step===2?"Skillnaden ska stå först, sedan värdet från början.":"Kontrollera både procenttalet och om det ökat eller minskat.",false);
  }
  function check(){
    if(solved || index===0 || finished)return;
    const q=current(),val=toNumber($("pcAnswer")?.value);
    let ok=false;
    if(index===1 && step===2) ok=toNumber($("pcNumerator")?.value)===q.difference && toNumber($("pcDenominator")?.value)===q.start;
    else if((index===1&&step===3)||index===2) ok=val===q.percent && $("pcDirection").value===q.direction;
    else ok=val===(step===0?q.start:q.difference);
    if(ok){
      if(index===2) {solved=true;show("pcCheck",false);show("pcNext",true);feedback("Rätt! "+q.difference+" ÷ "+q.start+" × 100 ≈ "+q.percent+" %. Bra räknat!",true);$("pcNext").focus();}
      else acceptStep();
    }else{
      if((index===1&&step===3)||index===2)feedback("Inte riktigt ännu. Kontrollera vilket värde du dividerar med, avrunda till hela procent och välj ökning eller minskning.",false);
      else if(index===1&&step===2)feedback("Kom ihåg ordningen: skillnaden ÷ värdet från början.",false);
      else feedback("Försök igen. Jämför värdet före och efter.",false);
    }
  }
  function next(){
    if(!solved)return;
    if(index<2&&step<3){step++;render();return;}
    MZ.math.recordQuestion({gameId:"percentChange"});
    if(index===2){finish();return;}
    index++;step=0;formulaVisible=index<2;render();
  }
  function finish(){
    if(finished)return;
    finished=true;
    let result;
    try{result=MZ.math.completeActivity({gameId:"percentChange",type:"three-change-round",questions:3});}
    catch(error){console.error("Beräkna förändring",error);result={rewardNP:0};}
    reward=Math.max(0,Number(result?.rewardNP)||0);
    $("pcProgressText").textContent="3 av 3 klara";
    $("pcProgressFill").style.width="100%";
    show("pcMain",false);show("pcFinished",true);
    $("pcFinalText").textContent="Du har klarat alla tre uppgifterna. Du fick "+reward+" kottar!";
    $("pcNp").textContent=MZ.storage.getNaturePoints();
  }
  function hint(){
    const q=current();hintLevel=Math.min(3,hintLevel+1);
    const msg=hintLevel===1?"Börja med att jämföra "+q.start+" och "+q.end+" "+q.unit+"."
      :hintLevel===2?"Beräkna skillnaden. Sätt sedan skillnaden över det första värdet ("+q.start+")."
      :"Du ska räkna ("+Math.max(q.start,q.end)+" − "+Math.min(q.start,q.end)+") ÷ "+q.start+" × 100. Kom ihåg att avrunda till hela procent.";
    $("pcHint").textContent=msg;show("pcHint",true);
  }
  function init(){
    const location=$("statisticsView");
    if(!location || $("percentChangeView"))return;
    const view=document.createElement("div");
    view.id="percentChangeView";view.className="hidden pp-game";
    view.innerHTML=[
      '<div class="trainer-head"><div><button class="secondary" id="pcBack" type="button">← Till parkkontoret</button><h2 style="margin-top:16px">Beräkna förändring</h2><div class="muted">Skillnaden ÷ värdet från början. Tre uppgifter med mindre och mindre stöd.</div></div><div class="pill">🌰 <span id="pcNp">0</span> kottar</div></div>',
      '<div class="trainer-panel pc-panel"><div class="pc-progress-top"><span id="pcMode">1 · Välj rätt svar</span><span id="pcProgressText">Uppgift 1 av 3</span></div><div class="pc-progress-track"><div class="pc-progress-fill" id="pcProgressFill"></div></div>',
      '<div id="pcMain"><div class="pc-topic" id="pcTopic"></div><p class="pc-story" id="pcStory"></p>',
      '<div class="pc-cards"><div class="pc-card"><small>FÖRE</small><img id="pcBeforeImg" alt=""><strong id="pcBeforeValue"></strong></div><div class="pc-card"><small>EFTER</small><img id="pcAfterImg" alt=""><strong id="pcAfterValue"></strong></div></div>',
      '<div class="pc-question" id="pcPrompt"></div><div id="pcResponse"></div>',
      '<div class="pc-actions"><button class="primary hidden" id="pcCheck" type="button">Kontrollera</button><button class="primary hidden" id="pcNext" type="button">Nästa steg →</button><button class="secondary hidden" id="pcHintBtn" type="button">Ledtråd</button></div>',
      '<div class="pc-feedback" id="pcFeedback" role="status" aria-live="polite"></div><div class="pc-hint hidden" id="pcHint"></div>',
      '<div class="pc-actions"><button class="secondary" id="pcFormulaBtn" type="button">Dölj formeln</button></div>',
      '<div class="pc-formula" id="pcFormula">Procentuell förändring = <span class="fraction"><span>skillnaden</span><span>värdet från början</span></span> × 100</div>',
      window.MatteparkenCalculator.markup(),
       '</div>',
      '<div id="pcFinished" class="pc-finished hidden"><h3>🌳 Tre av tre klara!</h3><p id="pcFinalText"></p><button class="primary" id="pcAgain" type="button">Spela tre nya uppgifter</button></div></div>'
    ].join("");
    location.parentElement.insertBefore(view,location);
    const card=$("openScientificNotation");
    if(card)card.insertAdjacentHTML("afterend",'<button class="game-card" id="openPercentChange" type="button"><span class="shelf-cover" aria-hidden="true"><span class="shelf-volume">12</span><span class="shelf-symbol">%</span><span class="shelf-cover-rule"></span></span><strong>Beräkna förändring</strong><span class="shelf-description">Ökning och minskning i procent. Tre uppgifter med stegvis mindre hjälp.</span><span class="shelf-play" aria-hidden="true">Spela <span>↗</span></span></button>');
    $("openPercentChange")?.addEventListener("click",open);
    $("pcBack").addEventListener("click",back);
    $("pcNext").addEventListener("click",next);
    $("pcCheck").addEventListener("click",check);
    $("pcAgain").addEventListener("click",begin);
    $("pcHintBtn").addEventListener("click",hint);
    $("pcFormulaBtn").addEventListener("click",()=>{formulaVisible=!formulaVisible;showFormula();});
    window.MatteparkenCalculator.bind(view);
    MZ.events.addEventListener("npchange",()=>{$("pcNp").textContent=MZ.storage.getNaturePoints();});
  }
  MZ.math.registerGame({id:"percentChange",title:"Beräkna förändring",description:"Procentuell ökning och minskning: skillnaden delat med värdet från början."});
  MZ.games=MZ.games||{};
  MZ.games.percentChange={init,open};
})();

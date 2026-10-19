/* Matteparken: 2.4 Delen och 2.5 Ränta. Använder den gemensamma kott- och uppdragsmotorn. */
(() => {
  "use strict";
  const MZ=window.Mattezoo;
  if(!MZ?.math || !MZ?.storage) return;
  const $=id=>document.getElementById(id);
  const fmt=n=>new Intl.NumberFormat("sv-SE",{maximumFractionDigits:3}).format(n);
  const parse=v=>{
    const s=String(v??"").trim().replace(/[\s\u00a0\u202f]/g,"").replace(",",".");
    return /^-?\d+(?:\.\d+)?$/.test(s)?Number(s):NaN;
  };
  const random=arr=>arr[Math.floor(Math.random()*arr.length)];
  const hideIds=["officeHome","gameShelfDrawer","rewardShelfDrawer","fieldGuideView","seedQuestView",
    "dailyQuestView","multiplicationView","equationsView","pow10View","fractionDecimalView",
    "fractionArithmeticView","mgnView","percentConvertView","sharePartView","prefixMatchView",
    "unitConvertView","statisticsView","scientificNotationView","percentChangeView",
    "wholeView","activityView","percentPartView","interestView"];
  const samplePart=[
    {p:20,n:450,icon:"🎮",title:"Spelbutiken",story:"Ett spel kostar 450 kr. Priset sänks med 20 %. Hur många kronor billigare blir spelet?",unit:"kr"},
    {p:25,n:400,icon:"🎒",title:"Ny ryggsäck",story:"En ryggsäck kostar 400 kr och säljs med 25 % rabatt. Hur stor är rabatten?",unit:"kr"},
    {p:10,n:250,icon:"📚",title:"Bokrean",story:"En bok kostar 250 kr. Du får 10 % rabatt. Hur många kronor blir rabatten?",unit:"kr"},
    {p:15,n:200,icon:"🌻",title:"Blomsterängen",story:"I blomsterängen växer 200 blommor. 15 % är gula. Hur många gula blommor finns det?",unit:"blommor"},
    {p:30,n:240,icon:"🐸",title:"Grodinventering",story:"Parkvakten räknar 240 grodor i området. 30 % finns vid den lilla dammen. Hur många är det?",unit:"grodor"},
    {p:5,n:600,icon:"🛹",title:"Skejtbutiken",story:"En skejtboard kostar 600 kr. Du får 5 % rabatt. Hur många kronor sparar du?",unit:"kr"},
    {p:35,n:1200,icon:"🚲",title:"Cykelrean",story:"En cykel kostar 1 200 kr. Priset sänks med 35 %. Hur stor är rabatten?",unit:"kr"},
    {p:50,n:60,icon:"🥕",title:"Parkens skörd",story:"Det skördas 60 morötter i trädgården. Hälften (50 %) säljs. Hur många morötter säljs?",unit:"morötter"}
  ];
  const sampleInterest=[
    {kind:"save",p:4,n:5000,months:12,icon:"🐿️",title:"Sparbanken"},
    {kind:"save",p:5,n:4000,months:12,icon:"🌰",title:"Kottsparandet"},
    {kind:"loan",p:5,n:4000,months:12,icon:"🚲",title:"Cykellånet"},
    {kind:"loan",p:3,n:8000,months:12,icon:"💻",title:"Datorlånet"},
    {kind:"save",p:6,n:3000,months:6,icon:"🌻",title:"Sex månaders sparande"},
    {kind:"save",p:4,n:6000,months:6,icon:"📚",title:"Halvårskontot"},
    {kind:"loan",p:4,n:8000,months:3,icon:"🎒",title:"Låna ett kvartal"},
    {kind:"loan",p:6,n:6000,months:6,icon:"🏕️",title:"Lån för en utflykt"}
  ];
  const specs={
    percentPart:{view:"percentPartView",open:"openPercentPart",title:"Beräkna delen",icon:"🎯",lesson:"2.4 Delen",
      description:"Beräkna delen: andelen · det hela. Fyra uppgifter ger 10 kottar.",type:"four-part-round"},
    interest:{view:"interestView",open:"openInterest",title:"Räntebanken",icon:"🏦",lesson:"2.5 Ränta",
      description:"Spara, låna och beräkna ränta under ett år eller kortare tid. Fyra uppgifter ger 10 kottar.",type:"four-interest-round"}
  };
  let active=null;
  function problems(id){
    if(id==="percentPart")return [
      samplePart[0],
      random(samplePart.slice(1,3)),
      random(samplePart.slice(3,6)),
      random(samplePart.slice(6))
    ];
    return [
      random(sampleInterest.slice(0,2)),
      random(sampleInterest.slice(2,4)),
      random(sampleInterest.slice(4,6)),
      random(sampleInterest.slice(6))
    ];
  }
  function interestStory(q){
    const time=q.months===12?"ett år":q.months===6?"sex månader":"tre månader";
    if(q.kind==="save")return "Du sätter in "+fmt(q.n)+" kr på ett sparkonto. Räntesatsen är "+fmt(q.p)+" % per år. Hur mycket ränta får du efter "+time+"?";
    return "Du lånar "+fmt(q.n)+" kr. Räntesatsen är "+fmt(q.p)+" % per år och du betalar tillbaka lånet efter "+time+". Beräkna räntan och hur mycket du totalt ska betala tillbaka.";
  }
  function answers(q){
    if(active.id==="percentPart"){
      const result=q.p*q.n/100;
      const fields=[{key:"part",title:"Hur stor är delen?",unit:q.unit,value:result}];
      if(active.index<=1)fields.unshift({key:"decimal",title:"Steg 1: Andelen i decimalform",unit:"",value:q.p/100});
      return fields;
    }
    const year=q.p*q.n/100,period=year*q.months/12;
    const fields=[
      {key:"decimal",title:"Steg 1: Räntesats i decimalform",unit:"",value:q.p/100},
      {key:"year",title:"Steg 2: Räntan på ett år",unit:"kr",value:year}
    ];
    if(q.months!==12)fields.push({key:"period",title:"Steg 3: Ränta för "+q.months+" månader",unit:"kr",value:period});
    if(q.kind==="loan")fields.push({key:"total",title:"Totalt att betala tillbaka",unit:"kr",value:q.n+period});
    return fields;
  }
  function calculation(q){
    const d=q.p/100,base=q.p*q.n/100;
    const steps=[fmt(q.p)+" % = "+fmt(d),fmt(d)+" · "+fmt(q.n)+" = "+fmt(base)+(active.id==="percentPart"?" "+q.unit:" kr per år")];
    if(active.id==="interest"){
      if(q.months!==12)steps.push(fmt(base)+" · "+q.months+"/12 = "+fmt(base*q.months/12)+" kr för "+q.months+" månader");
      if(q.kind==="loan")steps.push(fmt(q.n)+" + "+fmt(base*q.months/12)+" = "+fmt(q.n+base*q.months/12)+" kr att betala tillbaka");
    }
    return steps;
  }
  function updateCones(){
    Object.values(specs).forEach(s=>{const el=$(s.view)?.querySelector(".pp-cones");if(el)el.textContent=MZ.storage.getNaturePoints();});
  }
  function initGame(id){
    const spec=specs[id],anchor=$("statisticsView");
    if(!anchor || $(spec.view))return;
    const node=document.createElement("div");
    node.id=spec.view;
    node.className="hidden pp-game";
    anchor.parentElement.insertBefore(node,anchor);
    const card=document.createElement("button");
    card.className="game-card";
    card.id=spec.open;
    card.type="button";
    const no=id==="percentPart"?"14":"15";
    const symbol=id==="percentPart"?"20 % × 450":"4 % · 5000";
    card.innerHTML='<span class="shelf-cover" aria-hidden="true"><span class="shelf-volume">'+no+'</span><span class="shelf-symbol">'+symbol+'</span><span class="shelf-cover-rule"></span></span><strong>'+spec.title+'</strong><span class="shelf-description">'+spec.description+'</span><span class="shelf-play" aria-hidden="true">Spela <span>↗</span></span>';
    const previous=$(id==="percentPart"?"openWhole":"openPercentPart");
    (previous||$("openPercentChange")||$("openScientificNotation"))?.insertAdjacentElement("afterend",card);
    card.addEventListener("click",()=>open(id));
    MZ.events.addEventListener("npchange",updateCones);
  }
  function open(id){
    hideIds.forEach(el=>$(el)?.classList.add("hidden"));
    active={id,index:0,questions:problems(id),solved:false,completed:false,reward:0,hints:0,calculatorOpen:false};
    $(specs[id].view)?.classList.remove("hidden");
    render();
  }
  function back(){
    if(!active)return;
    $(specs[active.id].view)?.classList.add("hidden");
    $("officeHome")?.classList.remove("hidden");
    active=null;
  }

  // Räknaren är fristående från svarsrutorna och kan aldrig skicka in ett svar.
  // Tillåter bara tal och de fyra räknesätten. Ingen eval eller tolkning av fri kod.
  function calculatorHtml(){
    const keys=[
      ["7","7"],["8","8"],["9","9"],["÷","Division"],
      ["4","4"],["5","5"],["6","6"],["×","Multiplikation"],
      ["1","1"],["2","2"],["3","3"],["−","Subtraktion"],
      ["C","Rensa"],["0","0"],[",","Decimaltecken"],["+","Addition"],
      ["⌫","Radera sista siffran"],["=","Visa resultat"]
    ];
    const buttons=keys.map(([key,label])=>
      '<button type="button" class="pp-calc-key'+(["+","−","×","÷"].includes(key)?" pp-calc-operator":"")
      +(key==="="?" pp-calc-equals":(key==="⌫"?" pp-calc-delete":""))
      +'" data-pp-calc-key="'+key+'" aria-label="'+label+'">'+key+'</button>'
    ).join("");
    return '<details class="pp-calculator"'+(active.calculatorOpen?" open":"")+'>'
      +'<summary>🧮 Miniräknare <span>Öppna för att räkna</span></summary>'
      +'<div class="pp-calc-body"><div class="pp-calc-screen">'
      +'<div class="pp-calc-expression" aria-hidden="true"></div>'
      +'<output class="pp-calc-display" tabindex="0" aria-label="Miniräknarens resultat">0</output></div>'
      +'<div class="pp-calc-keys">'+buttons+'</div>'
      +'<p class="pp-calc-help">Komma eller punkt fungerar. Du kan också skriva på tangentbordet när resultatet är markerat.</p></div></details>';
  }
  function wireCalculator(host){
    const details=host.querySelector(".pp-calculator");
    if(!details)return;
    const session=active;
    const output=details.querySelector(".pp-calc-display");
    const expression=details.querySelector(".pp-calc-expression");
    let shown="0",stored=null,operator=null,startNew=false,history="";
    const formNumber=n=>String(n).replace(".",",");
    function paint(){
      output.textContent=shown;
      expression.textContent=history;
    }
    function clear(){
      shown="0";stored=null;operator=null;startNew=false;history="";paint();
    }
    function error(){
      shown="Fel";stored=null;operator=null;startNew=true;
      history="Kontrollera uträkningen";paint();
    }
    function calculate(a,b,op){
      let result;
      if(op==="+")result=a+b;
      else if(op==="−")result=a-b;
      else if(op==="×")result=a*b;
      else if(op==="÷")result=b===0?NaN:a/b;
      else return null;
      return Number.isFinite(result)?Number(result.toFixed(10)):null;
    }
    function press(key){
      if(key==="C"){clear();return;}
      if(key==="⌫"){
        if(startNew||shown==="Fel"){shown="0";startNew=false;}
        else shown=shown.length>1?shown.slice(0,-1):"0";
        paint();return;
      }
      if(/^\d$/.test(key)){
        if(startNew||shown==="Fel"){shown=key;startNew=false;history=operator===null?"":history;}
        else if(shown.replace(/\D/g,"").length<14)shown=shown==="0"?key:shown+key;
        paint();return;
      }
      if(key===","){
        if(startNew||shown==="Fel"){shown="0";startNew=false;}
        if(!shown.includes(","))shown+=",";
        paint();return;
      }
      if(["+","−","×","÷"].includes(key)){
        if(shown==="Fel"){clear();return;}
        if(operator!==null&&!startNew){
          const result=calculate(stored,parse(shown),operator);
          if(result===null){error();return;}
          stored=result;shown=formNumber(result);
        }else if(operator===null)stored=parse(shown);
        if(!Number.isFinite(stored)){error();return;}
        operator=key;startNew=true;history=formNumber(stored)+" "+operator;
        paint();return;
      }
      if(key==="="){
        if(operator===null||startNew)return;
        const previous=stored,second=shown;
        const result=calculate(previous,parse(second),operator);
        if(result===null){error();return;}
        history=formNumber(previous)+" "+operator+" "+second+" =";
        shown=formNumber(result);stored=null;operator=null;startNew=true;
        paint();
      }
    }
    details.addEventListener("toggle",()=>{if(active===session)active.calculatorOpen=details.open;});
    details.querySelectorAll("[data-pp-calc-key]").forEach(button=>
      button.addEventListener("click",()=>press(button.dataset.ppCalcKey))
    );
    output.addEventListener("keydown",event=>{
      const translate={"*":"×","x":"×","X":"×","/":"÷","-":"−",".":",","Escape":"C","Backspace":"⌫","Enter":"="};
      const key=translate[event.key]||event.key;
      if(/^\d$/.test(key)||[",","+","−","×","÷","C","⌫","="].includes(key)){
        event.preventDefault();press(key);
      }
    });
    paint();
  }

  function fieldHtml(field){
    return '<label class="pp-field"><span>'+field.title+'</span><div class="pp-field-row"><input data-pp-answer="'+field.key+'" type="text" inputmode="decimal" autocomplete="off" placeholder="Ditt svar" aria-label="'+field.title+'"/><strong>'+field.unit+'</strong></div></label>';
  }
  function render(){
    if(!active)return;
    const spec=specs[active.id],host=$(spec.view),q=active.questions[active.index];
    const title=active.id==="percentPart"?"delen = andelen · det hela":"räntan = räntesatsen · kapitalet";
    host.innerHTML='<div class="trainer-head pp-top"><div><button id="backFrom'+(active.id==="percentPart"?"PercentPart":"Interest")+'" type="button" class="secondary pp-back">← Till parkkontoret</button><h2>'+spec.icon+' '+spec.title+'</h2><div class="muted">'+spec.lesson+' · Fyra uppgifter ger 10 kottar</div></div><div class="pill">🌰 <span class="pp-cones">'+MZ.storage.getNaturePoints()+'</span> kottar</div></div>'
      +'<div class="trainer-panel pp-board"><div class="pp-progress"><strong>Uppgift '+(active.index+1)+' av 4</strong><span>'+((active.index+1)===1?'Vi börjar tillsammans':(active.index+1)===2?'Följ stegen':(active.index+1)===3?'Nu provar du mer själv':'Sista utmaningen')+'</span></div>'
      +'<div class="pp-track"><div style="width:'+(active.index/4*100)+'%"></div></div>'
      +'<div class="pp-scene"><div class="pp-icon" aria-hidden="true">'+q.icon+'</div><div class="pp-context"><h3>'+q.title+'</h3><p>'+(active.id==="percentPart"?q.story:interestStory(q))+'</p></div></div>'
      +'<div class="pp-formula">'+title+'</div>'
      +'<form class="pp-form"><div class="pp-fields">'+answers(q).map(fieldHtml).join("")+'</div><div class="pp-actions"><button class="primary pp-check" type="submit">Kontrollera svar ✓</button><button class="secondary pp-hint" type="button">💡 Ledtråd</button><button class="primary pp-next hidden" type="button">'+(active.index===3?'Se resultatet →':'Nästa uppgift →')+'</button></div></form>'
      +calculatorHtml()+'<div class="pp-feedback" aria-live="polite" role="status"></div><div class="pp-steps hidden"></div>'
      +'<p class="pp-small">Använd gärna räknehäftet. Decimaler kan skrivas med komma eller punkt. Ingen tidtagning.</p></div>';
    host.querySelector(".pp-back").addEventListener("click",back);
    host.querySelector(".pp-form").addEventListener("submit",check);
    host.querySelector(".pp-hint").addEventListener("click",hint);
    wireCalculator(host);
    host.querySelector(".pp-next").addEventListener("click",()=>{if(!active?.solved)return;if(active.index===3){result();return;}active.index++;active.solved=false;active.hints=0;render();});
    host.querySelector("[data-pp-answer]")?.focus({preventScroll:true});
  }
  function showText(message,success){
    const feedback=$(specs[active.id].view).querySelector(".pp-feedback");
    feedback.textContent=message;
    feedback.className="pp-feedback "+(success?"good":"bad");
  }
  function hint(){
    if(!active || active.solved)return;
    active.hints=Math.min(active.hints+1,3);
    const q=active.questions[active.index],first="Dela "+fmt(q.p)+" med 100 för att skriva räntesatsen/andelen i decimalform.";
    const next="Multiplicera decimalformen med "+fmt(q.n)+" för att hitta delen/räntan för ett år.";
    let extra="";
    if(active.id==="interest"&&q.months!==12)extra=" För "+q.months+" månader använder du "+q.months+"/12 av årsräntan.";
    if(active.id==="interest"&&q.kind==="loan")extra+=" För totalsumman lägger du räntan till lånebeloppet.";
    showText(active.hints===1?first:active.hints===2?next+extra:first+" "+next+extra,false);
  }
  function check(event){
    event.preventDefault();
    if(!active || active.solved)return;
    const spec=specs[active.id],host=$(spec.view),q=active.questions[active.index],fields=answers(q);
    const missing=fields.filter(f=>{
      const el=host.querySelector('[data-pp-answer="'+f.key+'"]');
      const n=parse(el?.value);
      const correct=Number.isFinite(n)&&Math.abs(n-f.value)<0.000001;
      el?.classList.toggle("pp-error",!correct);
      return !correct;
    });
    if(missing.length){
      showText("Försök igen. Kontrollera "+(missing.length===1?"det markerade steget.":"de markerade stegen.")+" Använd ledtråden om du vill.",false);
      return;
    }
    active.solved=true;
    MZ.math.recordQuestion({gameId:active.id,part:active.index+1});
    host.querySelectorAll("[data-pp-answer]").forEach(el=>{el.disabled=true;el.classList.remove("pp-error");});
    host.querySelector(".pp-check").classList.add("hidden");
    host.querySelector(".pp-hint").classList.add("hidden");
    host.querySelector(".pp-next").classList.remove("hidden");
    showText("✅ Rätt räknat! Bra jobbat med metoden.",true);
    const explanation=host.querySelector(".pp-steps");
    explanation.classList.remove("hidden");
    explanation.replaceChildren();
    const strong=document.createElement("strong");
    strong.textContent="Så här räknar du:";
    explanation.appendChild(strong);
    const ol=document.createElement("ol");
    calculation(q).forEach(line=>{const li=document.createElement("li");li.textContent=line;ol.appendChild(li);});
    explanation.appendChild(ol);
    const note=document.createElement("p");
    note.textContent="✏️ Skriv av stegen i ditt räknehäfte innan du går vidare.";
    explanation.appendChild(note);
    if(active.index===3&&!active.completed){
      active.completed=true;
      try{
        const done=MZ.math.completeActivity({gameId:active.id,type:spec.type,questions:4});
        active.reward=Math.max(0,Number(done?.rewardNP)||0);
        if(!done?.rewarded)showText("Alla uppgifterna är rätt! Belöningen kunde inte registreras. Be läraren kontrollera.",false);
      }catch(error){
        console.error(spec.title+" completion",error);
        active.reward=0;
        showText("Alla uppgifterna är rätt, men belöningen kunde inte registreras. Prova att kontakta läraren.",false);
      }
      updateCones();
    }
    host.querySelector(".pp-next").focus();
  }
  function result(){
    if(!active||!active.completed)return;
    const spec=specs[active.id],host=$(spec.view);
    host.innerHTML='<div class="trainer-head"><div><button id="backFrom'+(active.id==="percentPart"?"PercentPart":"Interest")+'" type="button" class="secondary pp-back">← Till parkkontoret</button><h2>'+spec.icon+' '+spec.title+'</h2></div><div class="pill">🌰 <span class="pp-cones">'+MZ.storage.getNaturePoints()+'</span> kottar</div></div>'
      +'<div class="trainer-panel pp-board pp-complete"><div class="pp-trophy">🌲🎉</div><h3>Fyra uppgifter klara!</h3><p>Du har övat på '+(active.id==="percentPart"?"att räkna ut delen.":"att räkna ut ränta för sparande och lån.")+'</p>'
      +'<div class="pp-reward">'+(active.reward?"+ "+active.reward+" kottar 🌰":"Ingen kottbelöning registrerad")+'</div><div class="pp-actions"><button class="primary pp-retry" type="button">Spela fyra nya</button><button class="secondary pp-exit" type="button">Till parkkontoret</button></div></div>';
    host.querySelector(".pp-back").addEventListener("click",back);
    host.querySelector(".pp-exit").addEventListener("click",back);
    host.querySelector(".pp-retry").addEventListener("click",()=>open(active.id));
  }
  for(const [id,spec] of Object.entries(specs)){
    MZ.math.registerGame({id,title:spec.title,description:spec.description});
    MZ.games=MZ.games||{};
    MZ.games[id]={init:()=>initGame(id),open:()=>open(id)};
  }
})();
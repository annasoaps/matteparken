/* Matteparken: gemensam miniräknare för alla mattespel.
   Fristående från svarsfält, kottar och progression. Utvärderar aldrig fri kod. */
(() => {
  "use strict";
  if(window.MatteparkenCalculator)return;

  const parse=value=>{
    const str=String(value??"").trim().replace(/[\s\u00a0\u202f]/g,"").replace(",",".");
    return /^-?\d+(?:\.\d+)?$/.test(str)?Number(str):NaN;
  };

  const keys=[
    ["7","7"],["8","8"],["9","9"],["÷","Division"],
    ["4","4"],["5","5"],["6","6"],["×","Multiplikation"],
    ["1","1"],["2","2"],["3","3"],["−","Subtraktion"],
    ["C","Rensa"],["0","0"],[",","Decimaltecken"],["+","Addition"],
    ["⌫","Radera sista siffran"],["=","Visa resultat"]
  ];

  function markup({open=false}={}){
    const buttons=keys.map(([key,label])=>
      '<button type="button" class="pp-calc-key'+(["+","−","×","÷"].includes(key)?" pp-calc-operator":"")
      +(key==="="?" pp-calc-equals":(key==="⌫"?" pp-calc-delete":""))
      +'" data-pp-calc-key="'+key+'" aria-label="'+label+'">'+key+'</button>'
    ).join("");
    return '<details class="pp-calculator"'+(open?" open":"")+'>'
      +'<summary>🧮 Miniräknare <span>Öppna för att räkna</span></summary>'
      +'<div class="pp-calc-body"><div class="pp-calc-screen">'
      +'<div class="pp-calc-expression" aria-hidden="true"></div>'
      +'<output class="pp-calc-display" tabindex="0" aria-label="Miniräknarens resultat">0</output></div>'
      +'<div class="pp-calc-keys">'+buttons+'</div>'
      +'<p class="pp-calc-help">Komma eller punkt fungerar. Du kan också skriva på tangentbordet när resultatet är markerat.</p></div></details>';
  }

  function bind(root,{onToggle}={}){
    const details=root?.matches?.(".pp-calculator")?root:root?.querySelector?.(".pp-calculator");
    if(!details)return null;
    // Bind högst en gång på samma knappuppsättning.
    if(details.dataset.calculatorBound==="true")return details;
    details.dataset.calculatorBound="true";

    const output=details.querySelector(".pp-calc-display");
    const expression=details.querySelector(".pp-calc-expression");
    if(!output||!expression)return null;
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
        if(startNew||shown==="Fel"){shown=key;startNew=false;}
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
    details.addEventListener("toggle",()=>onToggle?.(details.open));
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
    return details;
  }
  window.MatteparkenCalculator=Object.freeze({markup,bind});
})();
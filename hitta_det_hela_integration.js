/* Hitta det hela: spelhylla, iframe och Matteparkens poängsystem. */
(() => {
  "use strict";
  const MZ=window.Mattezoo;
  if(!MZ?.math)return;
  const $=(id)=>document.getElementById(id);
  function hide(id){$(id)?.classList.add("hidden");}
  function show(id){$(id)?.classList.remove("hidden");}
  function init(){
    const anchor=$("statisticsView");
    if(!anchor || $("wholeView"))return;
    const view=document.createElement("div");
    view.id="wholeView";view.className="hidden";
    view.innerHTML=[
      '<div class="trainer-head"><div><button class="secondary" id="wholeBack" type="button">← Till parkkontoret</button><h2 style="margin-top:16px">🌿 Hitta det hela</h2><div class="muted">Bråk och procent · Y-bokens sätt eller algebra · Fyra uppgifter för 10 kottar.</div></div><div class="pill">🌰 <span id="wholeNp">0</span> kottar</div></div>',
      '<iframe id="wholeFrame" title="Spelet Hitta det hela" style="display:block;width:100%;height:min(990px,81vh);min-height:560px;border:1px solid #d2ddcc;border-radius:13px;background:#eaf2e6;" loading="lazy"></iframe>'
    ].join("");
    anchor.parentElement.insertBefore(view,anchor);
    const card=$("openPercentChange")||$("openScientificNotation");
    card?.insertAdjacentHTML("afterend",'<button class="game-card" id="openWhole" type="button"><span class="shelf-cover" aria-hidden="true"><span class="shelf-volume">13</span><span class="shelf-symbol">3/5 → ?</span><span class="shelf-cover-rule"></span></span><strong>Hitta det hela</strong><span class="shelf-description">Räkna baklänges med bråk och procent. Välj Y-bokens sätt eller algebra. Fyra uppgifter ger 10 kottar.</span><span class="shelf-play" aria-hidden="true">Spela <span>↗</span></span></button>');
    $("openWhole")?.addEventListener("click",open);
    $("wholeBack")?.addEventListener("click",back);
    MZ.events.addEventListener("npchange",()=>{if($("wholeNp"))$("wholeNp").textContent=MZ.storage.getNaturePoints();});
  }
  function open(){
    ["officeHome","gameShelfDrawer","rewardShelfDrawer","fieldGuideView",
     "seedQuestView","dailyQuestView","multiplicationView","equationsView",
     "pow10View","fractionDecimalView","fractionArithmeticView","mgnView",
     "percentConvertView","sharePartView","prefixMatchView","unitConvertView",
     "statisticsView","scientificNotationView","percentChangeView",
     "activityView"].forEach(hide);
    show("wholeView");
    $("wholeNp").textContent=MZ.storage.getNaturePoints();
    // Ladda om inför varje besök så en avbruten omgång inte felaktigt får kottar.
    $("wholeFrame").src="hitta_det_hela.html?v=unified-20261019";
  }
  function back(){
    hide("wholeView");
    $("wholeFrame").src="about:blank";
    show("officeHome");
  }
  MZ.math.registerGame({id:"whole",title:"Hitta det hela",description:"Beräkna det hela med bråk och procent: Y-bokens sätt eller algebra."});
  MZ.games=MZ.games||{};
  MZ.games.whole={init,open};
})();
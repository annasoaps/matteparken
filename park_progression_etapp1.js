/* Matteparken Etapp 1: progression (feature branch only)
 * Extends the existing MZ.habitats engine without changing glade/forest unlock.
 * No UI changes or automatic area unlocks in this stage.
 */
(() => {
  "use strict";
  const MZ = window.Mattezoo;
  if(!MZ || !MZ.habitats || !MZ.rewards || !MZ.wildlife) throw new Error("Parkprogression: grundmoduler saknas.");
  const {state,storage} = MZ;
  const engine = MZ.habitats;
  const previous = {
    refreshMilestones:engine.refreshMilestones,
    snapshot:engine.snapshot,
    unlock:engine.unlock
  };
  const rules = Object.freeze({
    forest:Object.freeze({trees:3,uniqueObjects:5,species:3,mathRounds:35}),
    lake:Object.freeze({dock:1,uniqueObjects:5,fishSpecies:5,otherSpecies:2,mathRounds:50}),
    mountain:Object.freeze({heather:1,uniqueObjects:5,species:3})
  });
  const forestTrees = new Set(["birch","spruce","pine","oak"]);
  const forestBadgeIds = Object.freeze(["forestPlanter","forestKeeper","forestSpotter"]);
  const lakeBadgeIds = Object.freeze(["dockBuilder","lakeKeeper","lakeExpert"]);
  const mountainBadgeIds = Object.freeze(["mountainPlanter","mountainKeeper","mountainSpotter"]);

  // Include all existing badge IDs. Do not alter the Startgläntan's requirements.
  const badges = Object.freeze({
    ...engine.badgeDefinitions,
    forestPlanter:{id:"forestPlanter",icon:"🌱",name:"Skogsplanterare",description:"Placera tre träd i Skogsdungen."},
    forestKeeper:{id:"forestKeeper",icon:"🌳",name:"Skogsvårdare",description:"Placera fem olika skogsföremål utöver träden."},
    forestSpotter:{id:"forestSpotter",icon:"🐞",name:"Skogsspanare",description:"Upptäck tre olika skogsarter."},
    dockBuilder:{id:"dockBuilder",icon:"🪵",name:"Bryggbyggare",description:"Placera bryggan vid Sjön."},
    lakeKeeper:{id:"lakeKeeper",icon:"🌾",name:"Sjövårdare",description:"Placera fem olika sjöföremål utöver bryggan."},
    lakeExpert:{id:"lakeExpert",icon:"🐟",name:"Sjölivsexpert",description:"Fånga fem olika fiskarter och upptäck två andra sjöarter."},
    mountainPlanter:{id:"mountainPlanter",icon:"🌸",name:"Bergsplanterare",description:"Plantera ljung på Berget."},
    mountainKeeper:{id:"mountainKeeper",icon:"🪨",name:"Bergsvårdare",description:"Placera fem olika bergsföremål utöver ljungen."},
    mountainSpotter:{id:"mountainSpotter",icon:"🦅",name:"Bergsspanare",description:"Upptäck tre olika bergsarter."}
  });
  const areaDefinitions = Object.freeze({
    ...engine.habitats,
    southeast:{id:"southeast",name:"Sjön",icon:"💧",requires:"northwest",requirements:rules.forest},
    northeast:{id:"northeast",name:"Berget",icon:"⛰️",requires:"southeast",requirements:rules.lake}
  });

  function itemsAt(zoneId){
    return state.parkItems.filter(item => (item.zone || "southwest") === zoneId);
  }
  function distinctObjects(zoneId,excluded){
    const kinds = itemsAt(zoneId).map(item=>item.type==="starterSeed" ? item.variety : item.type);
    return new Set(kinds.filter(type => {
      if(!type || excluded.has(type)) return false;
      const definition = MZ.rewards.findItem(type);
      // An autumn decoration or an item from another zone cannot inflate a badge.
      return definition && definition.habitat === zoneId;
    })).size;
  }
  function measure(){
    const forestItems=itemsAt("northwest");
    const lakeItems=itemsAt("southeast");
    const mountainItems=itemsAt("northeast");
    return {
      forest:{
        trees:forestItems.filter(item=>forestTrees.has(item.type)).length,
        uniqueObjects:distinctObjects("northwest",forestTrees),
        species:MZ.wildlife.discoveryCountForHabitat("northwest")
      },
      lake:{
        dock:lakeItems.some(item=>item.type==="miniJetty") ? 1 : 0,
        uniqueObjects:distinctObjects("southeast",new Set(["miniJetty"])),
        fishSpecies:Object.entries(state.fishing.catches||{}).filter(([,count])=>Number(count)>0).length,
        otherSpecies:MZ.wildlife.discoveryCountForHabitat("southeast")
      },
      mountain:{
        heather:mountainItems.some(item=>item.type==="heather") ? 1 : 0,
        uniqueObjects:distinctObjects("northeast",new Set(["heather"])),
        species:MZ.wildlife.discoveryCountForHabitat("northeast")
      }
    };
  }
  function roundsSince(area){
    const baseline=state.habitats.mathBaselines?.[area];
    if(baseline===undefined || baseline===null || !Number.isFinite(Number(baseline)))return 0;
    return Math.max(0,(Number(state.habitats.mathRoundsTotal)||0)-Number(baseline));
  }
  function award(id){
    if(state.habitats.badges[id])return false;
    state.habitats.badges[id]=true;
    storage.saveHabitats();
    MZ.events.dispatchEvent(new CustomEvent("parkbadgeawarded",{detail:{badge:badges[id]}}));
    return true;
  }
  function refreshMilestones(){
    const awarded=previous.refreshMilestones();
    const counts=measure();
    function grant(condition,id){if(condition && award(id))awarded.push(id);}
    if(engine.isUnlocked("northwest")){
      grant(counts.forest.trees>=rules.forest.trees,"forestPlanter");
      grant(counts.forest.uniqueObjects>=rules.forest.uniqueObjects,"forestKeeper");
      grant(counts.forest.species>=rules.forest.species,"forestSpotter");
    }
    if(engine.isUnlocked("southeast")){
      grant(counts.lake.dock>=rules.lake.dock,"dockBuilder");
      grant(counts.lake.uniqueObjects>=rules.lake.uniqueObjects,"lakeKeeper");
      grant(counts.lake.fishSpecies>=rules.lake.fishSpecies && counts.lake.otherSpecies>=rules.lake.otherSpecies,"lakeExpert");
    }
    if(engine.isUnlocked("northeast")){
      grant(counts.mountain.heather>=rules.mountain.heather,"mountainPlanter");
      grant(counts.mountain.uniqueObjects>=rules.mountain.uniqueObjects,"mountainKeeper");
      grant(counts.mountain.species>=rules.mountain.species,"mountainSpotter");
    }
    return awarded;
  }
  function snapshot(area="northwest"){
    if(area!=="southeast" && area!=="northeast")return previous.snapshot(area);
    const lake=area==="southeast";
    const from=lake?"northwest":"southeast";
    const required=lake?forestBadgeIds:lakeBadgeIds;
    const requirements=lake?rules.forest:rules.lake;
    const current={...(lake?measure().forest:measure().lake),mathRounds:roundsSince(from)};
    const checks=Object.fromEntries(required.map(id=>[id,Boolean(state.habitats.badges[id])]));
    checks.mathRounds=current.mathRounds>=requirements.mathRounds;
    const requiredBadgesEarned=required.filter(id=>checks[id]).length;
    return {
      habitat:areaDefinitions[area],
      current:{...current,badges:requiredBadgesEarned},
      requirements,checks,requiredBadgeIds:required,requiredBadgesEarned,
      completed:Object.values(checks).filter(Boolean).length,total:4,
      ready:engine.isUnlocked(from) && Object.values(checks).every(Boolean),
      unlocked:engine.isUnlocked(area)
    };
  }
  function unlock(area){
    if(area!=="southeast" && area!=="northeast")return previous.unlock(area);
    if(engine.isUnlocked(area))return {ok:true,alreadyUnlocked:true};
    refreshMilestones();
    const progress=snapshot(area);
    if(!progress.ready)return {ok:false,reason:"requirements",progress};
    state.habitats.unlocked[area]=true;
    if(area==="southeast")state.habitats.mathBaselines.southeast=Math.max(0,Number(state.habitats.mathRoundsTotal)||0);
    storage.saveHabitats();
    return {ok:true,progress:snapshot(area)};
  }
  // Existing "northwest" unlock already stores its own math baseline.
  // For legacy/test unlocks with no baseline, count only NEW rounds.
  let legacyBaselineAdded=false;
  ["northwest","southeast"].forEach(area=>{
    if(engine.isUnlocked(area) && !Object.prototype.hasOwnProperty.call(state.habitats.mathBaselines,area)){
      state.habitats.mathBaselines[area]=Math.max(0,Number(state.habitats.mathRoundsTotal)||0);
      legacyBaselineAdded=true;
    }
  });
  if(legacyBaselineAdded)storage.saveHabitats();

  engine.habitats=areaDefinitions;
  engine.progressionRules=rules;
  engine.badgeDefinitions=badges;
  engine.forestBadgeIds=forestBadgeIds;
  engine.lakeBadgeIds=lakeBadgeIds;
  engine.mountainBadgeIds=mountainBadgeIds;
  engine.areaCounters=measure;
  engine.mathRoundsSince=roundsSince;
  engine.refreshMilestones=refreshMilestones;
  engine.snapshot=snapshot;
  engine.unlock=unlock;
  engine.badgeIds=()=>[
    ...Object.keys(badges).filter(id=>Boolean(state.habitats.badges[id])),
    ...Object.keys(state.habitats.badges).filter(id=>id.startsWith("testBadge")&&state.habitats.badges[id])
  ];
  engine.badgeCount=()=>engine.badgeIds().length;

  // Auto-award when an animal appears or a student places/moves/catches something.
  MZ.events.addEventListener("wildlifechange",refreshMilestones);
  ["saveParkItems","saveFishing"].forEach(method=>{
    const oldSave=storage[method].bind(storage);
    storage[method]=function(){
      const result=oldSave();
      refreshMilestones();
      return result;
    };
  });
})();

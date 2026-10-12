// Run from the repository root: node tests/park_progression_etapp1.test.cjs
// No third-party packages required.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const source = fs.readFileSync("park_progression_etapp1.js","utf8");
const registered = {};
const awards = [];
const species = {southwest:0,northwest:0,southeast:0,northeast:0};
const areas = {
  birch:"northwest",spruce:"northwest",fern:"northwest",
  fallenLog:"northwest",stump:"northwest",mushroomCluster:"northwest",
  blueberryBush:"northwest",miniJetty:"southeast",cattails:"southeast",
  reeds:"southeast",waterLily:"southeast",shoreGrass:"southeast",
  shoreStones:"southeast",heather:"northeast",sunRock:"northeast",
  rockThyme:"northeast",mountainShrub:"northeast",cairn:"northeast",
  cragRock:"northeast",autumnPot:"any"
};
const state = {
  parkItems:[],fishing:{catches:{}},
  habitats:{unlocked:{southwest:true,northwest:true,southeast:false,northeast:false},
    mathRoundsTotal:15,mathBaselines:{northwest:15},badges:{firstBloom:true}}
};
const engine = {
  habitats:{northwest:{id:"northwest"},southeast:{futureLocked:true},northeast:{futureLocked:true}},
  badgeDefinitions:{firstBloom:{id:"firstBloom",name:"Första odlingen"}},
  isUnlocked:id=>!!state.habitats.unlocked[id],
  refreshMilestones:()=>[],
  snapshot:id=>({original:id}),
  unlock:id=>({original:id})
};
const events = {
  addEventListener:(type,listener)=>(registered[type]??=[]).push(listener),
  dispatchEvent:event=>{
    if(event.type==="parkbadgeawarded")awards.push(event.detail.badge.id);
    (registered[event.type]||[]).forEach(listener=>listener(event));
  }
};
const storage = {
  saveHabitats:()=>{},saveParkItems:()=>{},saveFishing:()=>{}
};
const app = {
  habitats:engine,state,storage,events,
  rewards:{findItem:type=>areas[type]?{habitat:areas[type]}:null},
  wildlife:{discoveryCountForHabitat:habitat=>species[habitat]}
};
class FakeCustomEvent {
  constructor(type,options={}){this.type=type;this.detail=options.detail;}
}
vm.runInNewContext(source,{window:{Mattezoo:app},CustomEvent:FakeCustomEvent});
function add(zone,...types){
  types.forEach(type=>state.parkItems.push({zone,type}));
  storage.saveParkItems();
}
assert.equal(engine.snapshot("northwest").original,"northwest","Gläntan preserved");
assert.equal(engine.badgeCount(),1,"Old badge preserved");
add("northwest","birch","birch","spruce","fern","fallenLog","stump",
  "mushroomCluster","blueberryBush","autumnPot");
species.northwest=3; events.dispatchEvent({type:"wildlifechange"});
assert.equal(engine.areaCounters().forest.trees,3,"Three trees, repetitions allowed");
assert.equal(engine.areaCounters().forest.uniqueObjects,5,
  "Five different forest objects, trees/seasonal excluded");
for(const id of engine.forestBadgeIds)assert.equal(state.habitats.badges[id],true,id);
state.habitats.mathRoundsTotal=49;
assert.equal(engine.snapshot("southeast").current.mathRounds,34,"Forest baseline");
assert.equal(engine.unlock("southeast").ok,false,"Lake still locked after 34");
state.habitats.mathRoundsTotal=50;
assert.equal(engine.unlock("southeast").ok,true,"Lake unlock at 35");
assert.equal(state.habitats.mathBaselines.southeast,50,"Lake baseline stored");
add("southeast","miniJetty","cattails","reeds","waterLily","shoreGrass",
  "shoreStones","shoreStones");
state.fishing.catches={roach:3,perch:3,rudd:1,bream:1,crucian:1};
species.southeast=2;storage.saveFishing();events.dispatchEvent({type:"wildlifechange"});
assert.equal(engine.areaCounters().lake.fishSpecies,5,"Unique fish only");
assert.equal(engine.areaCounters().lake.uniqueObjects,5,"Distinct lake objects");
for(const id of engine.lakeBadgeIds)assert.equal(state.habitats.badges[id],true,id);
state.habitats.mathRoundsTotal=99;
assert.equal(engine.unlock("northeast").ok,false,"Mountain locked after 49");
state.habitats.mathRoundsTotal=100;
assert.equal(engine.unlock("northeast").ok,true,"Mountain unlock after 50");
add("northeast","heather","sunRock","rockThyme","mountainShrub","cairn","cragRock");
species.northeast=3;events.dispatchEvent({type:"wildlifechange"});
for(const id of engine.mountainBadgeIds)assert.equal(state.habitats.badges[id],true,id);
assert.equal(awards.length,9,"Badge event exactly once per badge");
console.log("Etapp 1: all progression assertions passed.");

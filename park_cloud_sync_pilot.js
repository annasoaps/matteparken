// Matteparken: automatisk säkerhetskopiering/återläsning, försiktig pilot.
// Aktiveras endast med ?parksync=1. Molnkopior är INTE bevis för äganderätt.
(() => {
  "use strict";
  const MZ = window.Mattezoo;
  if (!MZ) return;
  const enabled = new URLSearchParams(window.location.search).get("parksync") === "1";
  const ownerKey = "matteparken-park-sync-owner-v1";
  const backupPrefix = "matteparken-park-sync-before-restore-";
  let studentId = null, headId = null, ready = false, blocked = false;
  let syncing = null, connecting = null, timer = null, lastPushAt = 0;
  let lastCloudValues = null, notice = null, noticeText = null, actions = null;

  function keys() {
    return Object.entries(MZ.keys).filter(([name]) => name !== "naturePoints");
  }
  function localValues() {
    const result = {};
    for (const [name, key] of keys()) {
      const value = localStorage.getItem(key);
      if (value !== null) result[name] = { key, value };
    }
    return result;
  }
  function sameValues(a, b) {
    if (!a || !b) return false;
    const aNames = Object.keys(a), bNames = Object.keys(b);
    return aNames.length === bNames.length &&
      aNames.every(name => b[name]?.key === a[name]?.key &&
                           b[name]?.value === a[name]?.value);
  }
  function getPart(name, fallback) {
    try { return JSON.parse(localStorage.getItem(MZ.keys[name]) || ""); }
    catch { return fallback; }
  }
  function hasProgress() {
    const items = getPart("parkItems", []);
    if (Array.isArray(items) && items.length) return true;
    const stock = getPart("inventory", {});
    if (Object.values(stock || {}).some(n => Number(n) > 0)) return true;
    const tutorial = getPart("onboarding", {});
    if (["seedPlaced","seedGrown","tutorialComplete",
         "tutorialBirdhouseOrdered","tutorialBirdhousePlaced",
         "tutorialStarterRewardGranted"].some(n => tutorial?.[n])) return true;
    if (Number(tutorial?.seedQuestCorrect) > 0) return true;
    const rewards = getPart("rewards", {});
    if (["seedPacks","crates","bonusBlindBags"].some(n => Number(rewards?.[n]) > 0)) return true;
    if ((rewards?.deliveries || []).length || rewards?.deliveryChoice ||
        rewards?.pendingItem ||
        Object.values(rewards?.seasonalCrates || {}).some(n => Number(n) > 0) ||
        Object.keys(rewards?.activeSeasonal || {}).length ||
        rewards?.activeSeedChoices || rewards?.activeCrateChoices ||
        rewards?.activeBonusChoices) return true;
    const wildlife = getPart("wildlife", {});
    if (Object.values(wildlife?.discovered || {}).some(Boolean)) return true;
    const habitats = getPart("habitats", {});
    if (Object.entries(habitats?.unlocked || {}).some(([zone,active]) => zone !== "southwest" && active) ||
        Object.values(habitats?.badges || {}).some(Boolean) ||
        Number(habitats?.mathRoundsTotal) > 0) return true;
    const fish = getPart("fishing", {});
    if (Number(fish?.totalCatches) > 0 ||
        Object.values(fish?.catches || {}).some(n => Number(n) > 0)) return true;
    const daily = getPart("dailyChallenge", {});
    if (daily?.claimed || daily?.completed ||
        (daily?.tasks || []).some(task => Number(task?.progress) > 0)) return true;
    const stats = getPart("simpleGameStats", {});
    if (Object.values(stats || {}).some(g => Number(g?.rounds) > 0)) return true;
    const activity = getPart("activityLog", {});
    if (Object.values(activity?.days || {}).some(day =>
        Number(day?.activeSeconds) > 0 || Number(day?.mathNP) > 0 ||
        Object.values(day?.games || {}).some(g =>
          Number(g?.completed) > 0 || Number(g?.activities) > 0))) return true;
    if (Object.keys(getPart("multiplicationBest", {}) || {}).length ||
        Object.keys(getPart("multiplicationProgress", {}) || {}).length ||
        Number(localStorage.getItem(MZ.keys.equationProgress)) > 0) return true;
    return false;
  }

  function readOwner() {
    try { return JSON.parse(localStorage.getItem(ownerKey) || "null"); }
    catch { return null; }
  }
  function markOwner(id, snapshotId, values) {
    localStorage.setItem(ownerKey, JSON.stringify({
      studentId:id, snapshotId, savedValues:values
    }));
  }
  function validSnapshot(snap) {
    if (snap?.format !== "matteparken-localstorage-v1" ||
        !snap.values || typeof snap.values !== "object" ||
        Array.isArray(snap.values)) throw new Error("Ogiltig molnkopia");
    if (!snap.values.parkItems || !snap.values.onboarding)
      throw new Error("Molnkopian saknar park eller tutorial");
    const known = new Set(keys().map(([name]) => name));
    for (const [name, entry] of Object.entries(snap.values)) {
      if (!known.has(name) || entry?.key !== MZ.keys[name] ||
          typeof entry?.value !== "string") throw new Error("Okänd parkdel");
      if (!["parkDay","lastVisitDate","equationProgress"].includes(name)) {
        JSON.parse(entry.value);
      }
    }
    if (!Array.isArray(JSON.parse(snap.values.parkItems.value)))
      throw new Error("Ogiltiga parkföremål");
    return snap.values;
  }
  function message(text, needsAttention=false) {
    if (!notice) return;
    noticeText.textContent = text;
    notice.style.borderColor = needsAttention ? "#b76e42" : "#9bad9c";
    if (actions) actions.replaceChildren();
  }
  function action(label, fn) {
    if (!actions) return;
    const b = document.createElement("button");
    b.className = "secondary"; b.type = "button";
    b.style.margin = "4px";
    b.textContent = label;
    b.addEventListener("click", () => { b.disabled = true; Promise.resolve(fn()).finally(() => { b.disabled = false; }); });
    actions.appendChild(b);
  }
  function client() { return MZ.cloudStudent?.getClient?.(); }
  function sameStudent() {
    return Boolean(studentId && MZ.cloudStudent?.currentState?.()?.student?.id === studentId &&
      !MZ.teacherTest?.enabled);
  }
  async function latest() {
    const r = await client().from("student_park_snapshots")
      .select("id,saved_at,snapshot").order("saved_at", {ascending:false})
      .order("id",{ascending:false}).limit(1).maybeSingle();
    if (r.error) throw r.error;
    if (r.data) validSnapshot(r.data.snapshot);
    return r.data;
  }
  function snap(values) {
    return {format:"matteparken-localstorage-v1",
      clientSavedAt:new Date().toISOString(),values};
  }
  async function append(expectedId, values=localValues()) {
    if (!sameStudent()) throw new Error("Elevkontot har ändrats");
    const r = await client().rpc("student_append_park_snapshot",
      {p_snapshot:snap(values),p_expected_latest_id:expectedId});
    if (r.error) throw r.error;
    if (r.data?.ok !== true) {
      if (r.data?.reason === "newer_cloud_version") {
        blocked = true; ready = false;
        message("☁️ En annan dator har sparat en nyare park. Ingen park skrivs över.", true);
      }
      throw new Error(r.data?.reason || "Molnsparningen misslyckades");
    }
    return r.data.id;
  }

  async function restoreCloud(record) {
    if (!sameStudent() || hasProgress()) throw new Error("Befintlig park skyddas");
    const values = validSnapshot(record.snapshot);
    const previous = {};
    for (const [name,key] of keys()) previous[name] = localStorage.getItem(key);
    const before = JSON.stringify({studentId, createdAt:new Date().toISOString(),values:previous});
    const recovery = backupPrefix + Date.now();
    localStorage.setItem(recovery,before);
    if (localStorage.getItem(recovery) !== before)
      throw new Error("Säkerhetskopian kunde inte kontrolleras");
    try {
      for (const [name,key] of keys()) {
        if (values[name]) localStorage.setItem(key, values[name].value);
        else localStorage.removeItem(key);
      }
      if (!sameValues(localValues(),values)) throw new Error("Kopieringen misslyckades");
      markOwner(studentId,record.id,values);
    } catch (error) {
      for (const [name,key] of keys()) {
        if (previous[name] === null) localStorage.removeItem(key);
        else localStorage.setItem(key,previous[name]);
      }
      throw error;
    }
    ready = false;
    message("✓ Din park har hämtats från molnet! Sidan laddas om …");
    window.setTimeout(() => window.location.reload(),350);
  }

  async function push({force=false}={}) {
    if (!ready || blocked || !sameStudent() || syncing) return;
    if (!force && Date.now()-lastPushAt < 30000) return;
    const values = localValues();
    if (sameValues(values,lastCloudValues) || !hasProgress()) return;
    const head = headId;
    syncing = (async () => {
      try {
        const newHead = await append(head,values);
        if (!sameStudent()) return;
        headId = newHead; lastCloudValues = values;
        markOwner(studentId,headId,values);
        lastPushAt = Date.now();
        message("☁️ Parken sparad i molnet.");
      } catch (error) {
        console.warn("Matteparken molnsparning",error);
        if (!blocked) message("☁️ Molnet kunde inte nås. Parken finns kvar på datorn.",true);
      }
    })();
    try { await syncing; }
    finally {
      syncing = null;
      if (ready && !blocked && !sameValues(localValues(),lastCloudValues)) schedule();
    }
  }
  function schedule() {
    if (!enabled || !ready || blocked || !sameStudent()) return;
    if (timer) window.clearTimeout(timer);
    timer=window.setTimeout(() => {
      timer=null;
      if(Date.now()-lastPushAt < 30000) { schedule(); return; }
      void push();
    },4000);
  }

  async function onStudentReady() {
    if (!enabled || MZ.teacherTest?.enabled) return;
    const id = MZ.cloudStudent?.currentState?.()?.student?.id;
    if (!id) return;
    if (connecting) return connecting;
    if (studentId === id && ready) return;
    connecting = (async () => {
      try {
        if (studentId !== id) {
          ready=false; blocked=false; headId=null;lastCloudValues=null;
          studentId=id;
        }
        const savedOwner=readOwner();
        if (savedOwner?.studentId && savedOwner.studentId !== id) {
          blocked=true;
          message("⚠️ Den här datorn har en park kopplad till ett annat elevkonto. Ingenting flyttas.",true);
          return;
        }
        const record=await latest();
        if (!sameStudent()) return;
        const current=localValues();
        if (!record) {
          headId=null;
          if (hasProgress()) {
            const newHead=await append(null,current);
            headId=newHead;lastCloudValues=current;
            markOwner(id,newHead,current);lastPushAt=Date.now();
            message("✓ Din befintliga park har fått sin första molnbackup.");
          } else {
            lastCloudValues=current;
            markOwner(id,null,current);
            message("☁️ Parken sparas när du börjar bygga.");
          }
          ready=true;
          return;
        }
        headId=record.id;
        const remote=validSnapshot(record.snapshot);
        if (sameValues(current,remote)) {
          lastCloudValues=remote;
          markOwner(id,headId,remote);
          ready=true;
          message("✓ Din park är kopplad till molnet.");
          return;
        }
        if (!hasProgress() ||
            (savedOwner?.studentId===id &&
             savedOwner.snapshotId !== record.id &&
             sameValues(current,savedOwner.savedValues))) {
          await restoreCloud(record);
          return;
        }
        if (savedOwner?.studentId===id && savedOwner.snapshotId===record.id) {
          lastCloudValues=savedOwner.savedValues || remote;
          ready=true;
          message("☁️ Din park är kopplad till molnet. Senaste ändringarna säkerhetskopieras.");
          schedule();
          return;
        }

        // Två olika fungerande parkversioner. Ingen automatisk överskrivning.
        blocked=true;
        message("⚠️ Den lokala parken skiljer sig från molnkopian. Båda sparas orörda tills du väljer.",true);
        const seenHead=record.id;
        action("Använd parken på den här datorn",async () => {
          if (!sameStudent() || !window.confirm(
            "Spara den här datorns park som senaste molnversion? Den gamla molnkopian sparas som historik.")) return;
          try {
            const values=localValues();
            const newHead=await append(seenHead,values);
            blocked=false;ready=true;headId=newHead;lastCloudValues=values;
            markOwner(id,newHead,values);lastPushAt=Date.now();
            message("✓ Den här datorns park sparas nu automatiskt.");
          } catch(e) {
            message("⚠️ Nyare molnversion eller anslutningsfel. Ingenting ändrades.",true);
          }
        });
        action("Behåll båda, gör inget",async () => {
          message("Parkerna är oförändrade. Ingen automatisk synkning görs på den här datorn.",true);
        });
      } catch (error) {
        console.warn("Matteparken anslutning för park",error);
        blocked=true;
        message("⚠️ Molnsparningen kunde inte startas. Din park är kvar lokalt.",true);
      }
    })();
    try { await connecting; } finally { connecting=null; }
  }

  function init() {
    if (!enabled) return;
    notice=document.createElement("div");
    notice.setAttribute("role","status");
    notice.style.cssText="border:1px solid #9bad9c;border-radius:10px;padding:8px 12px;" +
      "margin:8px 10px;background:#f4f5e9;color:#30442f;font-size:13px;";
    noticeText=document.createElement("span");
    noticeText.textContent="☁️ Kopplar ihop parken med molnet …";
    actions=document.createElement("div");
    notice.append(noticeText,actions);
    document.querySelector("header.topbar")?.insertAdjacentElement("afterend",notice);

    for (const [name,fn] of Object.entries(MZ.storage)) {
      if (!name.startsWith("save") || typeof fn !== "function") continue;
      MZ.storage[name]=function(...args) {
        const result=fn.apply(this,args);
        schedule();
        return result;
      };
    }
    window.addEventListener("online",() => { if (ready) schedule(); else void onStudentReady(); });
    document.addEventListener("visibilitychange",() => {
      if (!document.hidden && ready) schedule();
    });
    window.setInterval(() => {
      if (ready) schedule();
      else if (!blocked) void onStudentReady();
    },60000);
  }

  MZ.cloudParkSync={init,onStudentReady,enabled:()=>enabled};
})();

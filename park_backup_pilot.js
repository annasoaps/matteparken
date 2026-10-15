// Matteparken parkbackup, pilotfas. Manuell kopiering samt skyddad återställning i separat testläge.
(() => {
  "use strict";

  function init() {
    const params = new URLSearchParams(window.location.search);
    const backupMode = params.get("parkbackup");
    if (!["1", "verify", "restore"].includes(backupMode)) return;

    const MZ = window.Mattezoo;
    const heading = document.querySelector("#officeHome .office-room-heading");
    if (!MZ?.keys || !heading) return;

    const panel = document.createElement("div");
    panel.style.cssText =
      "margin:10px 0 14px;padding:12px;border:1px solid #a8bca6;" +
      "border-radius:10px;background:#f4f5e9;color:#30442f;";
    const explanation = document.createElement("p");
    explanation.style.margin = "0 0 8px";
    explanation.textContent = backupMode === "restore"
      ? "☁️ Återställningstest: granska molnkopian först. Endast en tom park kan återställas, och den här datorns uppgifter säkerhetskopieras före import."
      : backupMode === "verify"
        ? "☁️ Kontrollera din befintliga molnkopia. Den här datorns park ändras inte."
        : "☁️ Test: spara en extra kopia av den här datorns park i molnet. " +
          "Ingen park eller dekoration ändras.";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "secondary";
    button.textContent = "Säkerhetskopiera min park";
    const checkButton = document.createElement("button");
    checkButton.type = "button";
    checkButton.className = "secondary";
    checkButton.textContent = backupMode === "restore"
      ? "Förhandsgranska molnkopian" : "Kontrollera min molnkopia";
    checkButton.style.marginLeft = "8px";
    const restoreButton = document.createElement("button");
    restoreButton.type = "button";
    restoreButton.className = "secondary";
    restoreButton.textContent = "Återställ denna park";
    restoreButton.hidden = true;
    restoreButton.style.marginTop = "8px";
    const feedback = document.createElement("p");
    feedback.setAttribute("role", "status");
    feedback.style.cssText = "margin:8px 0 0;font-size:0.9em;";
    if (backupMode === "verify") {
      panel.append(explanation, checkButton, feedback);
    } else if (backupMode === "restore") {
      panel.append(explanation, checkButton, restoreButton, feedback);
    } else {
      panel.append(explanation, button, checkButton, feedback);
    }
    heading.insertAdjacentElement("afterend", panel);

    const currentStudentId = () =>
      MZ.cloudStudent?.currentState?.()?.student?.id || null;
    const storableKeys = () =>
      Object.entries(MZ.keys).filter(([name]) => name !== "naturePoints");

    function localHasMeaningfulProgress() {
      const getPart = (name, fallback) => {
        const raw = localStorage.getItem(MZ.keys[name]);
        try { return raw === null ? fallback : JSON.parse(raw); }
        catch { return fallback; }
      };
      const items = getPart("parkItems", []);
      if (Array.isArray(items) && items.length > 0) return true;
      const inventory = getPart("inventory", {});
      if (Object.values(inventory || {}).some(count => Number(count) > 0)) return true;
      const onboarding = getPart("onboarding", {});
      if (["keyTaken", "seedBagTaken", "seedPlaced", "seedGrown",
            "tutorialBirdhouseOrdered", "tutorialComplete"].some(k => onboarding?.[k]))
        return true;
      if (onboarding?.selectedSeed) return true;
      const rewards = getPart("rewards", {});
      if (["seedPacks", "crates", "bonusBlindBags"].some(k => Number(rewards?.[k]) > 0))
        return true;
      if ((rewards?.deliveries || []).length || rewards?.deliveryChoice ||
          rewards?.pendingItem || Object.values(rewards?.seasonalCrates || {}).some(Boolean))
        return true;
      const wildlife = getPart("wildlife", {});
      if (Object.values(wildlife?.discovered || {}).some(Boolean)) return true;
      const fishing = getPart("fishing", {});
      if (Number(fishing?.totalCatches) > 0 ||
          Object.values(fishing?.catches || {}).some(n => Number(n) > 0))
        return true;
      const habitats = getPart("habitats", {});
      if (Object.entries(habitats?.unlocked || {}).some(([k,v]) => k !== "southwest" && v))
        return true;
      if (Object.values(habitats?.badges || {}).some(Boolean)) return true;
      if (Object.keys(getPart("multiplicationBest", {})).length > 0 ||
          Object.keys(getPart("multiplicationProgress", {})).length > 0 ||
          Number(localStorage.getItem(MZ.keys.equationProgress)) > 0) return true;
      const activity = getPart("activityLog", {});
      if (Object.values(activity?.days || {}).some(d =>
          Number(d?.activeSeconds)>0 || Number(d?.mathNP)>0 ||
          Object.values(d?.games || {}).some(g =>
            Number(g?.completed)>0 || Number(g?.activities)>0))) return true;
      const daily = getPart("dailyChallenge", {});
      if (daily?.claimed || daily?.completed) return true;
      const stats = getPart("simpleGameStats", {});
      if (Object.values(stats || {}).some(g => Number(g?.rounds)>0)) return true;
      return false;
    }

    function validateCloudCopy(snapshot) {
      if (snapshot?.format !== "matteparken-localstorage-v1" ||
          !snapshot.values || typeof snapshot.values !== "object" ||
          Array.isArray(snapshot.values))
        throw new Error("Okänt säkerhetskopieformat.");
      const keys = storableKeys();
      const allowed = new Set(keys.map(([name]) => name));
      const names = Object.keys(snapshot.values);
      if (!names.includes("parkItems") || !names.includes("onboarding"))
        throw new Error("Säkerhetskopian saknar viktig parkdata.");
      if (names.some(name => !allowed.has(name))) 
        throw new Error("Säkerhetskopian har okända nycklar.");
      for (const [name, storageKey] of keys) {
        const entry = snapshot.values[name];
        if (entry === undefined) continue;
        if (!entry || entry.key !== storageKey || typeof entry.value !== "string")
          throw new Error("Ogiltig sparad parkdel: " + name);
        if (!["parkDay", "lastVisitDate", "equationProgress"].includes(name)) {
          JSON.parse(entry.value);
        }
      }
      const items = JSON.parse(snapshot.values.parkItems.value);
      if (!Array.isArray(items)) throw new Error("Parkobjekten är ogiltiga.");
      return names.length;
    }

    // Kontrollera molnkopian utan att skriva något på den här datorn.
    let preview = null;
    checkButton.addEventListener("click", async () => {
      if (button.disabled || checkButton.disabled || restoreButton.disabled) return;
      preview = null;
      restoreButton.hidden = true;
      const currentStudent = MZ.cloudStudent?.currentState?.()?.student?.id;
      if (!currentStudent || MZ.teacherTest?.enabled) {
        feedback.textContent = "Logga in med samma elevkod som på första datorn.";
        return;
      }
      checkButton.disabled = true;
      feedback.textContent = "☁️ Hämtar uppgifter om din molnkopia …";
      try {
        const client = MZ.cloudStudent.getClient();
        const {data, error} = await client.from("student_park_snapshots")
          .select("id,saved_at,snapshot")
          .order("saved_at", {ascending:false}).limit(1).maybeSingle();
        if (error) throw error;
        if (MZ.cloudStudent?.currentState?.()?.student?.id !== currentStudent)
          throw new Error("Elevkontot ändrades under kontrollen.");
        if (!data) {
          feedback.textContent = "Det finns ännu ingen molnkopia för det här elevkontot.";
          return;
        }
        const snap = data.snapshot;
        validateCloudCopy(snap);
        const parsePart = (name, fallback) => {
          try { return JSON.parse(snap.values[name]?.value ?? ""); }
          catch { return fallback; }
        };
        const itemCount = Array.isArray(parsePart("parkItems", []))
          ? parsePart("parkItems", []).length : 0;
        const rewards = parsePart("rewards", {});
        const deliveries = Array.isArray(rewards?.deliveries)
          ? rewards.deliveries.length : 0;
        const wildlife = parsePart("wildlife", {});
        const discoveries = Object.values(wildlife?.discovered || {})
          .filter(Boolean).length;
        const when = new Date(data.saved_at).toLocaleString("sv-SE");
        feedback.textContent =
          "✓ Molnkopian hittad (" + when + "). " +
          Object.keys(snap.values).length + " sparade delar, " +
          itemCount + " utplacerade parksaker, " +
          discoveries + " upptäckta djur och " +
          deliveries + " väntande leveranser. " +
          "Ingenting på den här datorn har ändrats.";
        if (backupMode === "restore") {
          if (localHasMeaningfulProgress()) {
            feedback.textContent +=
              " ⚠️ Här finns redan parkframsteg. Återställning är spärrad för att skydda dem.";
          } else {
            preview = { id: data.id, studentId: currentStudent, when };
            restoreButton.hidden = false;
            feedback.textContent +=
              " Parken på den här datorn verkar tom. Du kan välja att återställa kopian.";
          }
        }
      } catch(error) {
        console.warn("Molnkopia kunde inte kontrolleras:", error);
        feedback.textContent = "⚠️ Kunde inte läsa kopian. Ingenting har ändrats.";
      } finally {
        checkButton.disabled = false;
      }
    });

    restoreButton.addEventListener("click", async () => {
      if (backupMode !== "restore" || restoreButton.hidden || restoreButton.disabled ||
          button.disabled || checkButton.disabled || !preview) return;
      const studentId = currentStudentId();
      if (!studentId || MZ.teacherTest?.enabled || studentId !== preview.studentId) {
        feedback.textContent = "Elevkontot har ändrats. Förhandsgranska kopian på nytt.";
        preview = null;
        restoreButton.hidden = true;
        return;
      }
      if (localHasMeaningfulProgress()) {
        feedback.textContent = "Den här datorn har redan parkframsteg. Ingenting återställdes.";
        restoreButton.hidden = true;
        return;
      }
      const accepted = window.confirm(
        "Återställa molnkopian från " + preview.when + "? " +
        "Befintliga lokala spelvärden säkerhetskopieras separat först. " +
        "Kottarna påverkas inte. Återställningen kräver omladdning av sidan."
      );
      if (!accepted) return;

      restoreButton.disabled = true;
      checkButton.disabled = true;
      feedback.textContent = "☁️ Kontrollhämtar kopian innan återställning …";
      try {
        const client = MZ.cloudStudent.getClient();
        const {data, error} = await client.from("student_park_snapshots")
          .select("id,snapshot").eq("id",preview.id).single();
        if (error) throw error;
        if (currentStudentId() !== studentId || MZ.teacherTest?.enabled)
          throw new Error("Elevkontot ändrades under hämtningen.");
        const copy = data?.snapshot;
        const partCount = validateCloudCopy(copy);
        if (localHasMeaningfulProgress())
          throw new Error("Det finns nya parkframsteg på den här datorn.");

        const keys = storableKeys();
        const before = {};
        for (const [name, key] of keys) before[name] = localStorage.getItem(key);

        // En separat och oföränderlig lokal återställningspunkt för datorns
        // tidigare värden. Om den inte får plats avbryts hela importen.
        const recoveryKey = "matteparken-pre-restore-" + Date.now();
        const recovery = JSON.stringify({
          format: "matteparken-pre-restore-v1", studentId,
          timestamp: new Date().toISOString(), values: before
        });
        localStorage.setItem(recoveryKey, recovery);
        if (localStorage.getItem(recoveryKey) !== recovery)
          throw new Error("Kunde inte verifiera lokal säkerhetskopia.");

        try {
          for (const [name, key] of keys) {
            const item = copy.values[name];
            if (item) localStorage.setItem(key, item.value);
            else localStorage.removeItem(key);
          }
          const correct = keys.every(([name,key]) =>
            localStorage.getItem(key) === (copy.values[name]?.value ?? null));
          if (!correct) throw new Error("Kunde inte verifiera återläsningen.");
        } catch (restoreError) {
          for (const [name, key] of keys) {
            if (before[name] === null) localStorage.removeItem(key);
            else localStorage.setItem(key, before[name]);
          }
          throw restoreError;
        }
        preview = null;
        feedback.textContent =
          "✓ " + partCount + " delar återställda! " +
          "En lokal säkerhetskopia av datorns tidigare värden har sparats. Sidan laddas om …";
        window.setTimeout(() => window.location.reload(), 700);
      } catch (error) {
        console.warn("Parkåterställning:", error);
        feedback.textContent =
          "⚠️ Återställningen avbröts: " + (error?.message || "okänt fel") +
          ". Kontrollera att parken är oförändrad.";
        restoreButton.disabled = false;
        checkButton.disabled = false;
      }
    });

    button.addEventListener("click", async () => {
      if (button.disabled) return;
      const studentId = MZ.cloudStudent?.currentState?.()?.student?.id;
      if (!studentId || MZ.teacherTest?.enabled) {
        feedback.textContent =
          "Logga in med ditt vanliga elevkonto först (inte lärartestläget).";
        return;
      }

      // Kottarna finns redan på servern och ska INTE kopieras från webbläsaren.
      // Råsträngar bevarar de lokala nycklarna exakt, även mellan kodversioner.
      const values = {};
      for (const [name, key] of Object.entries(MZ.keys)) {
        if (name === "naturePoints") continue;
        const value = localStorage.getItem(key);
        if (value !== null) values[name] = { key, value };
      }
      const parkKeys = ["onboarding", "parkItems", "inventory", "rewards",
        "habitats", "wildlife", "fishing"];
      if (!parkKeys.some(key => Object.hasOwn(values, key))) {
        feedback.textContent =
          "Hittar ingen lokal park att kopiera på den här datorn. " +
          "Ingenting har skickats eller ändrats.";
        return;
      }
      const snapshot = {
        format: "matteparken-localstorage-v1",
        clientSavedAt: new Date().toISOString(),
        values
      };

      button.disabled = true;
      feedback.textContent = "☁️ Sparar och kontrollerar kopian …";
      try {
        const client = MZ.cloudStudent.getClient();
        const { data: receipt, error } = await client
          .from("student_park_snapshots")
          .insert({ snapshot, schema_version: 1 })
          .select("id,saved_at").single();
        if (error) throw error;
        if (MZ.cloudStudent?.currentState?.()?.student?.id !== studentId) {
          throw new Error("Elevkontot ändrades under kopieringen.");
        }
        const { data: readback, error: readError } = await client
          .from("student_park_snapshots")
          .select("snapshot").eq("id", receipt.id).single();
        if (readError) throw readError;
        const copy = readback?.snapshot;
        const sourceNames = Object.keys(values);
        const copiedValues = copy?.values ?? {};
        const verified = copy?.format === snapshot.format &&
          sourceNames.length === Object.keys(copiedValues).length &&
          sourceNames.every(name =>
            copiedValues[name]?.key === values[name].key &&
            copiedValues[name]?.value === values[name].value
          );
        if (!verified) {
          throw new Error("Den sparade kopian kunde inte verifieras.");
        }
        feedback.textContent =
          "✓ Kopian är sparad och kontrollerad! " +
          "Den lokala parken är helt oförändrad. " +
          sourceNames.length + " delar säkerhetskopierades.";
      } catch (error) {
        console.warn("Matteparken parkbackup:", error);
        feedback.textContent =
          "⚠️ Kunde inte bekräfta säkerhetskopian. " +
          "Din lokala park är orörd. Prova igen senare.";
      } finally {
        button.disabled = false;
      }
    });
  }

  document.addEventListener("DOMContentLoaded", init);
})();

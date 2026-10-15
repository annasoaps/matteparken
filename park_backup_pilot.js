// Matteparken parkbackup, pilotfas. BARA manuell kopiering; aldrig återläsning.
(() => {
  "use strict";

  function init() {
    const params = new URLSearchParams(window.location.search);
    if (params.get("parkbackup") !== "1") return;

    const MZ = window.Mattezoo;
    const heading = document.querySelector("#officeHome .office-room-heading");
    if (!MZ?.keys || !heading) return;

    const panel = document.createElement("div");
    panel.style.cssText =
      "margin:10px 0 14px;padding:12px;border:1px solid #a8bca6;" +
      "border-radius:10px;background:#f4f5e9;color:#30442f;";
    const explanation = document.createElement("p");
    explanation.style.margin = "0 0 8px";
    explanation.textContent =
      "☁️ Test: spara en extra kopia av den här datorns park i molnet. " +
      "Ingen park eller dekoration ändras.";
    const button = document.createElement("button");
    button.type = "button";
    button.className = "secondary";
    button.textContent = "Säkerhetskopiera min park";
    const checkButton = document.createElement("button");
    checkButton.type = "button";
    checkButton.className = "secondary";
    checkButton.textContent = "Kontrollera min molnkopia";
    checkButton.style.marginLeft = "8px";
    const feedback = document.createElement("p");
    feedback.setAttribute("role", "status");
    feedback.style.cssText = "margin:8px 0 0;font-size:0.9em;";
    panel.append(explanation, button, checkButton, feedback);
    heading.insertAdjacentElement("afterend", panel);

    // Andra datorn: bara visa vad som finns i molnet. Inga lokala skrivningar.
    checkButton.addEventListener("click", async () => {
      if (button.disabled || checkButton.disabled) return;
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
          .select("saved_at,snapshot")
          .order("saved_at", {ascending:false}).limit(1).maybeSingle();
        if (error) throw error;
        if (MZ.cloudStudent?.currentState?.()?.student?.id !== currentStudent)
          throw new Error("Elevkontot ändrades under kontrollen.");
        if (!data) {
          feedback.textContent = "Det finns ännu ingen molnkopia för det här elevkontot.";
          return;
        }
        const snap = data.snapshot;
        if (snap?.format !== "matteparken-localstorage-v1" ||
            !snap.values || typeof snap.values !== "object")
          throw new Error("Okänt säkerhetskopieformat.");
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
      } catch(error) {
        console.warn("Molnkopia kunde inte kontrolleras:", error);
        feedback.textContent = "⚠️ Kunde inte läsa kopian. Ingenting har ändrats.";
      } finally {
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

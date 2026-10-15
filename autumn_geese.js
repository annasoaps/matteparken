/* Matteparken: tidsbegränsat höstevent med flyttgäss (15–25 oktober 2026).
   Fristående från mattepoäng, elevdata och Supabase. */
(() => {
  "use strict";

  const START_DAY = "2026-10-15";
  const LAST_DAY = "2026-10-25"; // Höstlovet (v.44) börjar 26 oktober.
  const MIN_FIRST_WAIT = 5 * 60 * 1000;
  const EXTRA_FIRST_WAIT = 3 * 60 * 1000;
  const MIN_NEXT_WAIT = 12 * 60 * 1000;
  const EXTRA_NEXT_WAIT = 4 * 60 * 1000;
  const MAX_FLOCKS = 2;
  const IDLE_AFTER = 2 * 60 * 1000;
  const GOOSE_SVG = [
    '<svg viewBox="0 0 64 46" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" focusable="false">',
    '<path d="M4 24L16 18H29L39 22L44 28L34 32H20L12 29L5 30L10 26Z" fill="#887861" stroke="#52483c" stroke-width="2" stroke-linejoin="round"/>',
    '<path d="M28 22L37 20L41 13L42 9L47 6L51 8L52 13L48 15L45 24L39 28Z" fill="#b6aa8c" stroke="#594c3c" stroke-width="2" stroke-linejoin="round"/>',
    '<path d="M51 10L61 12L52 16Z" fill="#e9ad52"/>',
    '<rect x="48" y="9" width="2.5" height="2.5" fill="#2b3029"/>',
    '<path d="M24 30L19 36M30 31L27 37" stroke="#b88955" stroke-width="2.5" stroke-linecap="square"/>',
    '<path class="mz-goose-wing" d="M19 24L10 5L15 3L30 22L35 28L26 29Z" fill="#675d50" stroke="#443f38" stroke-width="2" stroke-linejoin="round"/>',
    '<path d="M5 24L0 21L8 22" fill="#655b4d"/>',
    '</svg>'
  ].join("");

  let park, layer, scorePanel, scoreNumber, scoreCaption;
  let flock = null;
  let flockCount = 0;
  let totalPoints = 0;
  let activeMillis = 0;
  let dueAt = MIN_FIRST_WAIT + Math.random() * EXTRA_FIRST_WAIT;
  let lastTick = performance.now();
  let lastInput = performance.now();
  let messageTimer = 0;
  let timer = 0;
  const reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function stockholmToday() {
    try {
      const parts = new Intl.DateTimeFormat("en-GB", {
        timeZone: "Europe/Stockholm", year: "numeric", month: "2-digit", day: "2-digit"
      }).formatToParts(new Date());
      const values = Object.fromEntries(parts.filter(p => p.type !== "literal").map(p => [p.type, p.value]));
      return values.year + "-" + values.month + "-" + values.day;
    } catch {
      const d = new Date();
      return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }
  }

  function inSeason() {
    const today = stockholmToday();
    return today >= START_DAY && today <= LAST_DAY;
  }

  function hasStudent() {
    return Boolean(window.Mattezoo?.cloudStudent?.activeStudent?.());
  }

  function clearPark() {
    if (!park || !park.isConnected || park.clientWidth < 100) return false;
    if (document.hidden || document.querySelector(".modal-backdrop.open, .weekly-gate.open")) return false;
    const placement = document.getElementById("placementBanner");
    const action = document.getElementById("itemActionBanner");
    if (placement && getComputedStyle(placement).display !== "none") return false;
    if (action && getComputedStyle(action).display !== "none") return false;
    return true;
  }

  function updateScore() {
    scoreNumber.textContent = String(totalPoints);
  }

  function setCaption(value) {
    window.clearTimeout(messageTimer);
    scoreCaption.textContent = value;
  }

  function finishFlock() {
    if (!flock) return;
    const count = flock.hits;
    const total = flock.birds.length;
    flock = null;
    if (layer) layer.replaceChildren();
    setCaption("Sträcket är förbi: " + count + " av " + total + "!");
    messageTimer = window.setTimeout(() => {
      if (!flock && scoreCaption) scoreCaption.textContent = "Höstens flyttfåglar";
    }, 5200);
    if (flockCount < MAX_FLOCKS) {
      dueAt = activeMillis + MIN_NEXT_WAIT + Math.random() * EXTRA_NEXT_WAIT;
    }
  }

  function animate(now) {
    const f = flock;
    if (!f) return;
    if (!inSeason() || !clearPark()) {
      finishFlock();
      return;
    }
    const fraction = Math.min(1, (now - f.started) / f.duration);
    const leadX = f.fromX + (f.toX - f.fromX) * fraction;
    f.birds.forEach((bird, i) => {
      if (bird.hit) return;
      const x = reducedMotion ? f.width * 0.57 + bird.dx * f.direction : leadX + bird.dx * f.direction;
      const y = f.centerY + bird.dy + (reducedMotion ? 0 : Math.sin(now / 250 + i) * 2);
      bird.button.style.transform = "translate3d(" + Math.round(x) + "px," + Math.round(y) + "px,0)";
    });
    if (fraction >= 1) finishFlock();
    else window.requestAnimationFrame(animate);
  }

  function startFlock() {
    if (flock || !inSeason() || !clearPark()) return false;
    const width = park.clientWidth, height = park.clientHeight;
    const direction = Math.random() < 0.5 ? 1 : -1;
    const spacing = Math.max(52, Math.min(70, width * 0.08));
    const offsets = [[0, 0], [-1, -1], [-1, 1], [-2, -2], [-2, 2], [-3, -3], [-3, 3]];
    const centerY = Math.max(120, Math.min(height - 120, height * (0.35 + Math.random() * 0.17)));
    const f = {
      started: performance.now(), duration: reducedMotion ? 12500 : 10500,
      fromX: direction === 1 ? -75 : width + 75,
      toX: direction === 1 ? width + 3 * spacing + 95 : -(3 * spacing + 95),
      centerY, direction, width, hits: 0, birds: []
    };

    layer.replaceChildren();
    offsets.forEach((offset, index) => {
      const bird = document.createElement("button");
      bird.type = "button";
      bird.className = "mz-goose-target" + (direction === -1 ? " mz-goose-reverse" : "");
      bird.setAttribute("aria-label", "Pricka flyttgås " + (index + 1));
      bird.innerHTML = GOOSE_SVG;
      const item = {button: bird, dx: offset[0] * spacing, dy: offset[1] * 36, hit: false};
      bird.addEventListener("click", event => {
        event.preventDefault();
        event.stopPropagation();
        if (flock !== f || item.hit) return;
        item.hit = true;
        bird.disabled = true;
        bird.classList.add("mz-goose-hit");
        totalPoints += 1;
        f.hits += 1;
        updateScore();
        if (f.hits === f.birds.length) finishFlock();
      });
      f.birds.push(item);
      layer.appendChild(bird);
    });

    flock = f;
    flockCount += 1;
    scorePanel.hidden = false;
    updateScore();
    setCaption("Gässen kommer! Klicka på dem!");
    window.requestAnimationFrame(animate);
    return true;
  }

  function tick() {
    const now = performance.now();
    const delta = Math.max(0, Math.min(1500, now - lastTick));
    lastTick = now;
    if (!inSeason()) {
      finishFlock();
      if (scorePanel) scorePanel.hidden = true;
      window.clearInterval(timer);
      return;
    }
    if (!document.hidden && hasStudent() && now - lastInput <= IDLE_AFTER) {
      activeMillis += delta;
    }
    if (!flock && flockCount < MAX_FLOCKS && activeMillis >= dueAt && hasStudent()) startFlock();
  }

  function init() {
    park = document.querySelector("main.game > .park");
    if (!park || !inSeason()) return;

    layer = document.createElement("div");
    layer.className = "mz-geese-flight";
    layer.setAttribute("aria-label", "Flyttgäss över parken");
    park.appendChild(layer);

    scorePanel = document.createElement("div");
    scorePanel.className = "mz-goose-score";
    scorePanel.setAttribute("role", "status");
    scorePanel.setAttribute("aria-live", "polite");
    scorePanel.hidden = true;
    scorePanel.innerHTML = '<div class="mz-goose-title">🪿 Gåssträcket</div><div class="mz-goose-points"><strong>0</strong> poäng</div><div class="mz-goose-caption">Höstens flyttfåglar</div>';
    park.appendChild(scorePanel);
    scoreNumber = scorePanel.querySelector(".mz-goose-points strong");
    scoreCaption = scorePanel.querySelector(".mz-goose-caption");

    function recordInput() { lastInput = performance.now(); }
    document.addEventListener("pointerdown", recordInput, {passive: true});
    document.addEventListener("keydown", recordInput);
    document.addEventListener("visibilitychange", () => {
      lastTick = performance.now();
      if (document.hidden && flock) finishFlock();
    });
    timer = window.setInterval(tick, 1000);
    window.Mattezoo = window.Mattezoo || {};
    window.Mattezoo.autumnGeese = {
      preview: () => startFlock(), // För att prova direkt i webbläsarens konsol.
      getPoints: () => totalPoints
    };
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, {once: true});
  } else init();
})();

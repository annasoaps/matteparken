/* Mobilpilot för Matteparken: pan, nyp-zoom och översikt. */
(() => {
  "use strict";

  const portrait = window.matchMedia("(max-width: 760px) and (orientation: portrait)");
  const world = document.querySelector(".game > .park");
  if (!world) return;

  const parent = world.parentElement;
  let viewport = null;
  let controls = null;
  let hint = null;
  let scale = 1;
  let minScale = .4;
  const maxScale = 2.5;
  let offsetX = 0;
  let offsetY = 0;
  let worldWidth = 0;
  let active = false;
  const pointers = new Map();
  let dragStart = null;
  let pinchStart = null;
  let moved = false;
  let suppressClick = false;
  let suppressTimer = null;

  function isPlacing() {
    return world.classList.contains("carrying-item") ||
      document.getElementById("placementBanner")?.classList.contains("open");
  }

  function clampOffsets() {
    const vw = viewport.clientWidth, vh = viewport.clientHeight;
    const renderedW = world.offsetWidth * scale;
    const renderedH = world.offsetHeight * scale;
    offsetX = renderedW <= vw ? (vw - renderedW) / 2 :
      Math.min(0, Math.max(vw - renderedW, offsetX));
    offsetY = renderedH <= vh ? (vh - renderedH) / 2 :
      Math.min(0, Math.max(vh - renderedH, offsetY));
  }

  function render() {
    if (!active) return;
    clampOffsets();
    world.style.transform = `translate3d(${offsetX}px,${offsetY}px,0) scale(${scale})`;
    if (controls) {
      const meter = controls.querySelector(".mobile-park-zoom");
      meter.textContent = Math.round(scale * 100) + "%";
      controls.querySelector("[data-zoom='out']").disabled = scale <= minScale + .001;
      controls.querySelector("[data-zoom='in']").disabled = scale >= maxScale - .001;
    }
  }

  function zoomTo(next, anchorX, anchorY) {
    const newScale = Math.max(minScale, Math.min(maxScale, next));
    const ratio = newScale / scale;
    offsetX = anchorX - (anchorX - offsetX) * ratio;
    offsetY = anchorY - (anchorY - offsetY) * ratio;
    scale = newScale;
    render();
  }

  function showWholePark() {
    scale = minScale;
    offsetX = (viewport.clientWidth - world.offsetWidth * scale) / 2;
    offsetY = (viewport.clientHeight - world.offsetHeight * scale) / 2;
    render();
  }

  function updateSize(reset = false) {
    if (!active) return;
    const oldWidth = worldWidth || 1;
    const fraction = reset ? .5 :
      (viewport.clientWidth / 2 - offsetX) / (oldWidth * scale);
    const bg = world.querySelector(".park-background");
    const nativeRatio = bg?.naturalWidth && bg?.naturalHeight ?
      bg.naturalWidth / bg.naturalHeight : 1.65;
    const aspect = Math.max(1.3, Math.min(2.5, nativeRatio));
    worldWidth = Math.max(viewport.clientWidth, Math.round(viewport.clientHeight * aspect));
    world.style.width = worldWidth + "px";
    world.style.height = viewport.clientHeight + "px";
    minScale = Math.min(1, viewport.clientWidth / worldWidth);
    scale = Math.max(minScale, Math.min(maxScale, scale));
    offsetX = viewport.clientWidth / 2 - Math.max(0, Math.min(1, fraction)) * worldWidth * scale;
    if (reset) offsetY = 0;
    render();
  }

  function localPoint(event) {
    const rect = viewport.getBoundingClientRect();
    return { x: event.clientX - rect.left, y: event.clientY - rect.top };
  }

  function startPinch() {
    const points = [...pointers.values()];
    if (points.length < 2) return;
    const a = points[0], b = points[1];
    const centerX = (a.x + b.x) / 2, centerY = (a.y + b.y) / 2;
    pinchStart = {
      distance: Math.max(1, Math.hypot(a.x - b.x, a.y - b.y)),
      scale,
      worldX: (centerX - offsetX) / scale,
      worldY: (centerY - offsetY) / scale
    };
    moved = true;
  }

  function onPointerDown(event) {
    if (event.pointerType !== "touch" || isPlacing()) return;
    pointers.set(event.pointerId, localPoint(event));
    if (pointers.size === 1) {
      dragStart = {position: localPoint(event), x: offsetX, y: offsetY};
      moved = false;
    } else if (pointers.size === 2) {
      startPinch();
      event.preventDefault();
    }
  }

  function onPointerMove(event) {
    if (!pointers.has(event.pointerId)) return;
    pointers.set(event.pointerId, localPoint(event));
    if (pointers.size >= 2 && pinchStart) {
      const points = [...pointers.values()];
      const a = points[0], b = points[1];
      const distance = Math.max(1, Math.hypot(a.x - b.x, a.y - b.y));
      const newScale = Math.max(minScale, Math.min(maxScale,
        pinchStart.scale * distance / pinchStart.distance));
      scale = newScale;
      offsetX = (a.x + b.x) / 2 - pinchStart.worldX * scale;
      offsetY = (a.y + b.y) / 2 - pinchStart.worldY * scale;
      render();
      moved = true;
      event.preventDefault();
      return;
    }
    if (!dragStart || pointers.size !== 1) return;
    const point = localPoint(event);
    const dx = point.x - dragStart.position.x;
    const dy = point.y - dragStart.position.y;
    if (!moved && Math.hypot(dx, dy) < 9) return;
    if (!moved) {
      moved = true;
      hint?.classList.add("seen");
      try { viewport.setPointerCapture(event.pointerId); } catch (_) {}
    }
    offsetX = dragStart.x + dx;
    offsetY = dragStart.y + dy;
    render();
    event.preventDefault();
  }

  function onPointerEnd(event) {
    if (!pointers.has(event.pointerId)) return;
    pointers.delete(event.pointerId);
    if (moved) {
      suppressClick = true;
      clearTimeout(suppressTimer);
      suppressTimer = setTimeout(() => { suppressClick = false; }, 120);
    }
    if (pointers.size === 1) {
      const p = [...pointers.values()][0];
      dragStart = {position:p, x:offsetX, y:offsetY};
    } else dragStart = null;
    pinchStart = null;
    if (pointers.size === 2) startPinch();
    if (!pointers.size) moved = false;
  }

  function onClickCapture(event) {
    if (!suppressClick) return;
    suppressClick = false;
    event.preventDefault();
    event.stopImmediatePropagation();
  }

  function enable() {
    if (active) return;
    active = true;
    viewport = document.createElement("div");
    viewport.className = "mobile-park-viewport";
    parent.insertBefore(viewport, world);
    viewport.appendChild(world);
    controls = document.createElement("div");
    controls.className = "mobile-park-controls";
    controls.setAttribute("aria-label", "Kartkontroller");
    controls.innerHTML = `
      <button type="button" data-zoom="out" aria-label="Zooma ut" title="Zooma ut">−</button>
      <span class="mobile-park-zoom" aria-live="off">100%</span>
      <button type="button" data-zoom="in" aria-label="Zooma in" title="Zooma in">+</button>
      <button type="button" class="mobile-park-overview" data-zoom="overview" aria-label="Visa hela parken" title="Visa hela parken">⛶</button>`;
    hint = document.createElement("div");
    hint.className = "mobile-park-swipe-hint";
    hint.textContent = "↔ Svep för att utforska";
    viewport.append(hint, controls);
    controls.addEventListener("click", event => {
      const action = event.target.closest("button")?.dataset.zoom;
      if (!action) return;
      if (action === "overview") showWholePark();
      else zoomTo(scale + (action === "in" ? .25 : -.25),
        viewport.clientWidth / 2, viewport.clientHeight / 2);
    });
    viewport.addEventListener("pointerdown", onPointerDown);
    viewport.addEventListener("pointermove", onPointerMove);
    viewport.addEventListener("pointerup", onPointerEnd);
    viewport.addEventListener("pointercancel", onPointerEnd);
    viewport.addEventListener("click", onClickCapture, true);
    scale = 1;
    offsetX = 0;
    offsetY = 0;
    updateSize(true);
    const bg = world.querySelector(".park-background");
    if (bg && !bg.complete) bg.addEventListener("load", () => updateSize(false), {once:true});
  }

  function disable() {
    if (!active) return;
    active = false;
    pointers.clear();
    parent.insertBefore(world, viewport);
    viewport.remove();
    world.style.removeProperty("width");
    world.style.removeProperty("height");
    world.style.removeProperty("transform");
    viewport = null;
    controls = null;
    hint = null;
  }

  function sync() {
    if (portrait.matches) {
      if (!active) enable();
      else updateSize(false);
    } else disable();
  }

  // Den befintliga parkkoden och dess klicklyssnare hinner initieras först.
  window.addEventListener("DOMContentLoaded", () => {
    sync();
    portrait.addEventListener("change", sync);
    window.addEventListener("resize", () => {
      if (active) updateSize(false);
    });
  });
})();

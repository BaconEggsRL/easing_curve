"use strict";
const F = typeof module !== "undefined" ? require("./fixtures.js") : FIXTURES;
const SAMPLES = typeof module !== "undefined" ? require("./assets/curve_samples.js") : CURVE_SAMPLES;
const copy = F.clone;
const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));
function sampleCurve(values, progress) {
  const position = clamp(progress, 0, 1) * (values.length - 1);
  const index = Math.min(Math.floor(position), values.length - 2);
  return values[index] + (values[index + 1] - values[index]) * (position - index);
}
const mix = (a, b, t) => Array.isArray(a) ? a.map((v, i) => v + (b[i] - v) * t) : a + (b - a) * t;
const add = (a, b) => Array.isArray(a) ? a.map((v, i) => v + b[i]) : a + b;
const meta = (target, path) => F.targets[target]?.properties.find(p => p.path === path);
const componentIndex = part => ({x: 0, y: 1, z: 2, r: 0, g: 1, b: 2, a: 3})[part];
function read(scene, target, path) {
  if (!meta(target, path) || !scene[target]) throw new Error(`Unavailable property: ${target}.${path}`);
  const [base, part] = path.split(":");
  const value = scene[target][base];
  return copy(part ? value[componentIndex(part)] : value);
}
function write(scene, target, path, value) {
  if (!meta(target, path)) throw new Error(`Unavailable property: ${target}.${path}`);
  const [base, part] = path.split(":");
  if (part) scene[target][base][componentIndex(part)] = value;
  else scene[target][base] = copy(value);
}
function validValue(value, type) {
  const count = {Vector2: 2, Vector3: 3, Color: 4, Rect2: 4}[type];
  if (count) return Array.isArray(value) && value.length === count && value.every(Number.isFinite);
  return Number.isFinite(value) && (type !== "int" || Number.isInteger(value));
}
function resolveValue(mode, current, scene, type) {
  let value;
  if (mode.mode === "current") value = copy(current);
  else if (mode.mode === "value") value = copy(mode.value);
  else if (mode.mode === "relative") value = add(current, mode.value);
  else if (mode.mode === "property") {
    if (meta(mode.sourceTarget, mode.sourceProperty)?.type !== type) throw new Error("Source property must have the same type as the destination.");
    value = read(scene, mode.sourceTarget, mode.sourceProperty);
  } else throw new Error("Unknown value mode.");
  if (!validValue(value, type)) throw new Error(`Expected finite ${type} values${type === "int" ? " (whole numbers)" : ""}.`);
  return value;
}
function effective(config, track, key) {
  const ownership = config[`${key}Ownership`];
  return ownership === "per" || (ownership === "override" && track[`${key}Override`]) ? track[key] : config[key];
}
function playable(config) { return (config.layout === "simple" ? config.tracks.slice(0, 1) : config.tracks).filter(t => t.enabled); }
function validate(config, scene) {
  if (!Number.isFinite(config.speed) || config.speed <= 0) throw new Error("Speed must be a finite number greater than zero.");
  const active = playable(config);
  if (!active.length) throw new Error("Add or enable a track to preview.");
  const seen = [];
  for (const track of active) {
    const property = meta(track.target, track.property);
    if (!property) throw new Error(`Choose an available target/property for ${track.id}.`);
    const duration = effective(config, track, "duration");
    if (!Number.isFinite(duration) || duration < 0 || !Number.isFinite(track.delay) || track.delay < 0) throw new Error("Duration and delay must be finite, nonnegative seconds.");
    if (!SAMPLES[effective(config, track, "curve")]) throw new Error("Choose an available curve.");
    const [base, part] = track.property.split(":");
    if (seen.some(s => s.target === track.target && s.base === base && (!s.part || !part || s.part === part))) throw new Error(`Overlapping tracks write ${track.target}.${base}. Disable one or choose another property.`);
    seen.push({target: track.target, base, part});
    const current = read(scene, track.target, track.property);
    resolveValue(track.from, current, scene, property.type);
    resolveValue(track.to, current, scene, property.type);
  }
  return active;
}
function snapshotFor(tracks, scene) { return tracks.map(t => ({target: t.target, property: t.property, value: read(scene, t.target, t.property)})); }
function restoreSnapshot(snapshot, scene) { for (const item of snapshot || []) write(scene, item.target, item.property, item.value); }
function duplicateTrack(track) { return {...copy(track), id: F.track().id}; }
function reorderTrack(tracks, id, index) {
  const from = tracks.findIndex(t => t.id === id);
  if (from < 0) return;
  const [track] = tracks.splice(from, 1);
  tracks.splice(clamp(index, 0, tracks.length), 0, track);
}

// One bounded numeric/component simulator for every lab and architecture.
// It intentionally has no engine lifecycle, serialization, signal system, or timeline API.
class Playback {
  constructor(scene) { this.scene = scene; this.time = 0; this.total = 0; this.entries = []; this.running = false; this.direction = 1; }
  start(config) {
    const tracks = validate(config, this.scene);
    this.config = copy(config);
    this.time = 0; this.direction = 1; this.running = true;
    this.entries = tracks.map(track => ({track: copy(track), duration: effective(config, track, "duration"), curve: effective(config, track, "curve"), endpoints: null}));
    this.total = Math.max(...this.entries.map(e => e.track.delay + e.duration));
    if (config.capture === "play") this.capture(this.entries);
    this.apply();
    if (this.total === 0) this.running = false;
  }
  capture(entries) {
    // Resolve a boundary as a batch, before any of its target properties are written.
    const scene = copy(this.scene);
    for (const e of entries) {
      const type = meta(e.track.target, e.track.property).type;
      const current = read(scene, e.track.target, e.track.property);
      e.endpoints = {from: resolveValue(e.track.from, current, scene, type), to: resolveValue(e.track.to, current, scene, type)};
    }
  }
  apply() {
    this.capture(this.entries.filter(e => !e.endpoints && this.time >= e.track.delay && this.direction > 0));
    for (const e of this.entries) {
      if (!e.endpoints) continue;
      if (this.time < e.track.delay && this.direction > 0) continue;
      const progress = e.duration === 0 ? (this.time >= e.track.delay ? 1 : 0) : clamp((this.time - e.track.delay) / e.duration, 0, 1);
      const weight = sampleCurve(SAMPLES[e.curve], progress);
      let value = mix(e.endpoints.from, e.endpoints.to, weight);
      if (meta(e.track.target, e.track.property).type === "int") value = Math.round(value);
      write(this.scene, e.track.target, e.track.property, value);
    }
  }
  step(seconds) {
    if (!this.running) return;
    this.time = clamp(this.time + seconds * this.config.speed * this.direction, 0, this.total);
    this.apply();
    if (this.direction > 0 && this.time >= this.total || this.direction < 0 && this.time <= 0) this.running = false;
  }
  seek(progress) { this.running = false; this.time = clamp(progress, 0, 1) * this.total; this.apply(); }
  stop() { this.running = false; }
  reverse() { this.direction = -1; this.running = this.time > 0; }
}
if (typeof module !== "undefined") module.exports = {Playback, sampleCurve, resolveValue, effective, read, write, validate, validValue, snapshotFor, restoreSnapshot, duplicateTrack, reorderTrack};

if (typeof document !== "undefined") {
  const esc = value => String(value).replace(/[&<>"']/g, c => ({"&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"})[c]);
  const format = value => Array.isArray(value) ? `(${value.map(v => Number(v).toFixed(2)).join(", ")})` : Number(value).toFixed(2);
  const options = (values, selected) => Object.entries(values).map(([key, label]) => `<option value="${esc(key)}" ${key === String(selected) ? "selected" : ""}>${esc(label)}</option>`).join("");
  const select = (name, values, selected, attrs = "") => `<select data-field="${name}" ${attrs}>${options(values, selected)}</select>`;
  const field = (label, content) => `<label class="field"><span>${label}</span>${content}</label>`;
  const numeric = (name, value, attrs = "") => `<input type="number" step="0.01" data-field="${name}" value="${Number.isFinite(value) ? value : ""}" ${attrs}>`;
  const action = (name, text, attrs = "") => `<button type="button" data-action="${name}" ${attrs}>${text}</button>`;
  const ownershipOptions = {shared: "Shared", per: "Per track", override: "Shared + overrides"};
  const modes = {current: "Current", value: "Value", relative: "Relative · add offset", property: "Property"};
  const returnOptions = {exact: "Exact reverse", captured: "Return to captured values", fresh: "Return to fresh baseline", explicit: "Explicit From/To", paired: "Paired enter / exit", pingpong: "Ping-pong · one round", auto: "Restore on exit", reread: "Re-read animated current (drift example)"};
  const eventNames = {enter: "Hover enter", exit: "Hover exit", down: "Button down", up: "Button up", focus: "Focus enter", blur: "Focus exit", pressed: "Pressed"};
  function graph(curve) {
    const samples = SAMPLES[curve] || SAMPLES.linear;
    const min = Math.min(0, ...samples), max = Math.max(1, ...samples), span = max - min;
    const points = samples.map((v, i) => `${(i / (samples.length - 1) * 196 + 2).toFixed(1)},${(48 - (v - min) / span * 43).toFixed(1)}`).join(" ");
    return `<svg class="mini-curve" viewBox="0 0 200 52" role="img" aria-label="${esc(F.curves[curve])} curve, overshoot preserved"><path d="M2 48H198M2 5H198" stroke="#354352"/><polyline points="${points}" fill="none" stroke="#b2e8ce" stroke-width="1.5"/></svg>`;
  }
  const favorites = new Set(), recent = [];
  const picker = document.querySelector("#picker");
  let pickerRows = [], pickerChoose;
  function drawPicker() {
    const query = document.querySelector("#picker-search").value.toLowerCase();
    const visible = pickerRows.filter(row => `${row.label} ${row.detail} ${row.group}`.toLowerCase().includes(query));
    const groupMap = new Map();
    for (const row of visible) {
      const group = favorites.has(row.key) ? "Favorites" : recent.includes(row.key) ? "Recent" : row.group;
      if (!groupMap.has(group)) groupMap.set(group, []);
      groupMap.get(group).push(row);
    }
    const groups = [...groupMap.entries()].sort(([a], [b]) => (a === "Favorites" ? -2 : a === "Recent" ? -1 : 0) - (b === "Favorites" ? -2 : b === "Recent" ? -1 : 0));
    document.querySelector("#picker-results").innerHTML = groups.map(([group, rows]) => `<div class="picker-group"><h3>${esc(group)}</h3>${rows.map(row => `<div class="picker-item"><button type="button" data-pick="${esc(row.key)}">${esc(row.label)}<small>${esc(row.detail)}</small></button>${row.favorite ? `<button type="button" data-star="${esc(row.key)}" aria-label="${favorites.has(row.key) ? "Unfavorite" : "Favorite"} ${esc(row.label)}" aria-pressed="${favorites.has(row.key)}">${favorites.has(row.key) ? "★" : "☆"}</button>` : ""}</div>`).join("")}</div>`).join("") || '<p class="empty">No compatible matches. Try another search.</p>';
  }
  function openPicker(title, rows, choose) {
    pickerRows = rows; pickerChoose = choose;
    document.querySelector("#picker-title").textContent = title;
    document.querySelector("#picker-search").value = "";
    drawPicker(); picker.showModal(); document.querySelector("#picker-search").focus();
  }
  document.querySelector("#picker-search").addEventListener("input", drawPicker);
  document.querySelector("#picker-results").addEventListener("click", e => {
    const star = e.target.closest("[data-star]");
    if (star) { favorites.has(star.dataset.star) ? favorites.delete(star.dataset.star) : favorites.add(star.dataset.star); drawPicker(); return; }
    const item = e.target.closest("[data-pick]");
    if (!item) return;
    const row = pickerRows.find(r => r.key === item.dataset.pick);
    recent.unshift(row.key); if (recent.length > 12) recent.pop();
    picker.close(); pickerChoose(row);
  });
  const labs = [];
  class Lab {
    constructor(kind, side, host) {
      this.kind = kind; this.side = side; this.config = F.config(kind); this.scene = F.scene();
      this.baseline = {y: 0, scale: 1}; this.snapshot = null; this.playback = new Playback(this.scene); this.frame = null;
      this.interaction = {hover: false, pressed: false, focus: false}; this.pingpong = false; this.auditioning = false;
      this.message = "Ready · choose a variant and preview"; this.error = "";
      if (kind === "authoring" && side === 0) this.config.layout = "simple";
      if (kind === "values" && side === 0) this.config.capture = "play";
      if (kind === "buttons") this.config.architecture = side ? "D" : "B";
      if (kind === "restore") { this.config.returnPolicy = side ? "fresh" : "captured"; this.config.duration = .65; }
      this.selected = this.config.tracks[0].id;
      this.el = document.createElement("article"); this.el.className = "lab"; this.el.style.padding = "0";
      this.el.setAttribute("aria-label", `${kind} comparison ${side ? "B" : "A"}`); host.append(this.el);
      this.el.innerHTML = `<div class="lab-heading"><strong>${side ? "B / Compare" : "A / Reference"}</strong><span class="tag">CANDIDATE</span></div><div class="lab-body"><div class="variant-controls"></div><div class="stage"><span class="stage-caption">MOCK VIEWPORT · STABLE INPUT REGION</span><div class="baseline-marker">external baseline</div><div class="hit-region"><button class="motion-button">${kind === "buttons" ? "Try me" : "Preview target"}</button></div><div class="schematic" hidden></div><output class="stage-readout"></output></div><div class="transport">${action("preview", "▶ Preview")}${action("replay", "↻ Replay")}${action("stop", "■ Stop")}${action("reset", "Reset")}${action("reverse", "↶ Reverse")}</div><label class="progress-row"><span>Progress</span><input aria-label="Playback progress" type="range" min="0" max="1" step=".001" value="0" data-progress><output class="time-output">0.00 s</output></label><div class="error" role="alert"></div><div class="event-log" aria-live="polite"></div><div class="editor"></div></div>`;
      this.stageButton = this.el.querySelector(".motion-button");
      this.el.addEventListener("click", e => this.click(e));
      this.el.addEventListener("change", e => this.change(e));
      this.el.querySelector("[data-progress]").addEventListener("input", e => this.scrub(Number(e.target.value)));
      this.el.addEventListener("dragstart", e => {
        const node = e.target.closest("[data-node]"), track = e.target.closest("[data-track]");
        if (node) e.dataTransfer.setData("application/x-lab-node", node.dataset.node);
        else if (track) e.dataTransfer.setData("application/x-lab-track", track.dataset.track);
      });
      this.el.addEventListener("dragover", e => { if (e.target.closest(".target-drop,.track")) e.preventDefault(); });
      this.el.addEventListener("drop", e => this.drop(e));
      this.el.addEventListener("pointerover", e => {
        const button = e.target.closest("[data-audition]");
        if (button && this.config.audition && !this.auditioning) { this.auditioning = true; this.run(button.dataset.audition); }
      });
      this.el.addEventListener("pointerout", e => { if (e.target.closest("[data-audition]") && this.auditioning) { this.reset(); this.auditioning = false; } });
      this.bindButton(); this.renderEditor(); this.paint();
    }
    stop() { if (this.frame !== null) cancelAnimationFrame(this.frame); this.frame = null; this.playback.stop(); this.pingpong = false; }
    reset() {
      this.stop(); restoreSnapshot(this.snapshot, this.scene); this.snapshot = null;
      this.playback = new Playback(this.scene); this.interaction = {hover: false, pressed: false, focus: false};
      this.message = "Reset · preview snapshot restored"; this.paint();
    }
    edit() { if (this.snapshot || this.playback.entries.length) this.reset(); this.error = ""; }
    run(curve, overrideConfig) {
      this.stop(); this.error = "";
      const config = copy(overrideConfig || this.config);
      if (curve) { config.curve = curve; config.curveOwnership = "shared"; }
      try {
        const active = validate(config, this.scene);
        const added = snapshotFor(active, this.scene).filter(item => !(this.snapshot || []).some(s => s.target === item.target && s.property === item.property));
        this.snapshot = [...(this.snapshot || []), ...added];
        this.playback.start(config); this.message = `Playing · ${config.capture === "play" ? "Play-time" : "track-start"} capture`;
        this.animate();
      } catch (error) { this.error = error.message; this.playback.stop(); }
      this.paint();
    }
    animate() {
      if (this.frame !== null) cancelAnimationFrame(this.frame);
      let previous;
      const tick = now => {
        this.frame = null;
        try { if (previous !== undefined) this.playback.step((now - previous) / 1000); }
        catch (error) { this.error = error.message; this.playback.stop(); }
        previous = now;
        if (!this.playback.running && this.pingpong && this.playback.direction > 0) { this.pingpong = false; this.playback.reverse(); }
        this.paint();
        if (this.playback.running) this.frame = requestAnimationFrame(tick);
      };
      this.frame = requestAnimationFrame(tick);
    }
    scrub(progress) {
      if (!this.playback.entries.length) this.run();
      this.stop();
      if (!this.playback.entries.length) return;
      try { this.playback.seek(progress); this.message = "Manual sample · playback stopped"; } catch (error) { this.error = error.message; }
      this.paint();
    }
    paint() {
      const node = this.config.tracks.find(t => t.id === this.selected)?.target || "Button";
      const value = this.scene[node] || this.scene.Button;
      const simulated = value;
      const pos = simulated.position || [0, 0], scale = simulated.scale || [1, 1];
      const editingSelfColor = this.config.tracks.find(t => t.id === this.selected)?.property === "self_modulate";
      const color = node === "Material" ? value["shader_parameter/tint"] : editingSelfColor ? value.self_modulate : this.scene.Visual.self_modulate;
      const offset = this.config.transform === "offset";
      const external = this.kind === "restore" || this.kind === "buttons";
      const baseY = external && offset ? this.baseline.y : 0;
      const baseScale = external && offset ? this.baseline.scale : 1;
      this.stageButton.style.transform = `translate(${pos[0]}px,${pos[1] + baseY}px) scale(${scale[0] * baseScale},${scale[1] * baseScale}) rotate(${(simulated.rotation || 0) * 180 / Math.PI}deg)`;
      this.stageButton.style.background = `rgba(${color.slice(0, 3).map(v => clamp(v, 0, 1) * 255).join(",")},${clamp(color[3], 0, 1)})`;
      const tint = simulated.modulate || [1, 1, 1, 1];
      this.stageButton.style.opacity = tint[3];
      this.stageButton.style.filter = `brightness(${Math.max(.1, (tint[0] + tint[1] + tint[2]) / 2.43)})`;
      const glow = node === "Material" ? value["shader_parameter/glow"] : this.scene.Visual.glow;
      this.stageButton.style.boxShadow = `0 4px 0 #3e567b,0 0 ${Math.max(0, glow) * 24}px #b2e8ce`;
      this.stageButton.style.outline = this.interaction.focus ? "3px solid #b2e8ce" : "";
      const size = simulated.size || [148, 56], minimum = simulated.custom_minimum_size || [0, 0];
      this.stageButton.style.width = `${Math.max(1, size[0], minimum[0])}px`; this.stageButton.style.height = `${Math.max(1, size[1], minimum[1])}px`;
      const shape = this.el.querySelector(".schematic");
      const isShape = node === "Object3D" || node === "Panel" && this.config.tracks.some(t => t.property === "preview_rect");
      shape.hidden = !isShape; this.stageButton.style.visibility = isShape ? "hidden" : "visible";
      if (isShape) {
        shape.className = `schematic ${node === "Object3D" ? "cube" : ""}`;
        if (node === "Panel") { const r = value.preview_rect; shape.style.width = `${Math.max(1, r[2])}px`; shape.style.height = `${Math.max(1, r[3])}px`; shape.style.transform = `translate(${r[0]}px,${r[1]}px)`; }
        else { shape.style.width = "72px"; shape.style.height = "56px"; shape.style.transform = `translate(${pos[0]}px,${pos[1]}px) scale(${scale[0]},${scale[1]}) rotate(${pos[2] || 0}deg)`; }
      }
      this.el.querySelector(".baseline-marker").style.transform = `translateY(${this.baseline.y}px)`;
      const activeTrack = this.config.tracks.find(t => t.id === this.selected) || this.config.tracks[0];
      let label = "No tracks";
      if (activeTrack && meta(activeTrack.target, activeTrack.property)) label = `${activeTrack.target}.${activeTrack.property} = ${format(read(this.scene, activeTrack.target, activeTrack.property))}`;
      if (node === "Object3D") label += "\nVector3 schematic · z shown as rotation";
      if (node === "Material") label += "\nOwner: ShaderMaterial · assigned to Button/Visual";
      this.el.querySelector(".stage-readout").textContent = label;
      this.el.querySelector("[data-progress]").value = this.playback.total ? this.playback.time / this.playback.total : 0;
      this.el.querySelector(".time-output").textContent = `${this.playback.time.toFixed(2)} / ${this.playback.total.toFixed(2)} s`;
      this.el.querySelector(".error").textContent = this.error;
      this.el.querySelector(".event-log").textContent = this.message;
      const status = this.el.querySelector(".snapshots pre");
      if (status) status.textContent = JSON.stringify({authored: this.config.tracks.map(t => ({target: t.target, property: t.property, from: t.from.mode, to: t.to.mode})), current: activeTrack && meta(activeTrack.target, activeTrack.property) ? read(this.scene, activeTrack.target, activeTrack.property) : null, endpoints: this.playback.entries.map(e => ({property: e.track.property, ...e.endpoints})), previewSnapshot: this.snapshot, externalBaseline: this.baseline}, null, 2);
    }
    typedValue(track, endpoint) {
      const data = track[endpoint], type = meta(track.target, track.property)?.type;
      if (data.mode === "current") return '<p class="binding-note">Read once at the selected capture boundary.</p>';
      if (data.mode === "property") return action(`source-${endpoint}`, `${esc(data.sourceTarget)}.${esc(data.sourceProperty)} · choose source ↗`, 'class="source-choice"');
      const labels = {Vector2: ["x", "y"], Vector3: ["x", "y", "z"], Color: ["R", "G", "B", "A"], Rect2: ["x", "y", "w", "h"]}[type];
      const values = labels ? (Array.isArray(data.value) ? data.value : labels.map(() => 0)) : [data.value];
      let content = `<div class="value-controls">${values.map((v, i) => `<label><span>${labels ? labels[i] : type}</span><input aria-label="${endpoint} ${labels ? labels[i] : type}" type="number" step="${type === "int" ? "1" : ".01"}" data-endpoint="${endpoint}" data-component="${labels ? i : "scalar"}" value="${Number.isFinite(v) ? v : ""}"></label>`).join("")}</div>`;
      if (type === "Color") {
        const hex = "#" + values.slice(0, 3).map(v => Math.round(clamp(v || 0, 0, 1) * 255).toString(16).padStart(2, "0")).join("");
        content += `<label class="inline-check">RGB swatch <input aria-label="${endpoint} color swatch" type="color" data-color="${endpoint}" value="${hex}"><span>Alpha above · display clips to 0–1</span></label>`;
      }
      if (type === "Rect2") content += '<p class="binding-note">Position (x, y) + size (w, h). Schematic only.</p>';
      if (data.mode === "relative") content += '<p class="binding-note">Additive offset, not a scale multiplier.</p>';
      return content;
    }
    trackBody(track, simple) {
      const type = meta(track.target, track.property)?.type || "Unknown";
      const bindingText = {explicit: `Explicit target: ${track.target}`, parent: "Playback parent: Button → relative path: . → Button", owner: "Scene owner: Menu → path: Button/Visual → Visual (not parent)"}[track.binding];
      const endpoint = name => `<div class="value-block">${field(name === "from" ? "From" : "To", select(name + "Mode", modes, track[name].mode))}${this.typedValue(track, name)}</div>`;
      const hiddenSource = simple ? `<details class="annotation"><summary>Advanced values · From ${esc(modes[track.from.mode])}</summary>${endpoint("from")}</details>` : endpoint("from");
      return `<div class="track-body" data-track="${track.id}">${field("Binding", select("binding", {explicit: "Explicit node", parent: "Parent default", owner: "Scene owner binding"}, track.binding))}<div class="field"><span>Target</span><div class="target-drop">${action("target", `${esc(track.target)} · choose ↗`)}${action("missing", "×", 'aria-label="Simulate missing target" title="Simulate a removed target"')}</div></div><p class="binding-note">${esc(bindingText)}${track.target === "Material" ? " · Object: ShaderMaterial, assigned to Visual.material" : ""}</p><div class="field"><span>Property</span><div class="property-actions">${action("property", `${esc(track.property)} · ${type} ↗`)}</div></div><details class="annotation"><summary>Expert property path</summary><input aria-label="Manual property path" data-field="manualPath" value="${esc(track.property)}" style="width:100%"><p>Validated against fixture metadata; unsupported paths block playback.</p></details>${hiddenSource}${endpoint("to")}${this.config.curveOwnership !== "shared" ? field("Curve override", this.config.curveOwnership === "override" ? `<input type="checkbox" data-field="curveOverride" ${track.curveOverride ? "checked" : ""}>` : '<span class="muted">Per-track curve</span>') + `<div class="curve-picker">${select("trackCurve", F.curves, track.curve, `aria-label="Track curve" ${this.config.curveOwnership === "override" && !track.curveOverride ? "disabled" : ""}`)}${graph(track.curve)}</div>` : ""}${this.config.durationOwnership !== "shared" ? field("Time override", this.config.durationOwnership === "override" ? `<input type="checkbox" data-field="durationOverride" ${track.durationOverride ? "checked" : ""}>` : '<span class="muted">Per-track seconds</span>') + field("Duration", numeric("trackDuration", track.duration, `min="0" ${this.config.durationOwnership === "override" && !track.durationOverride ? "disabled" : ""}`)) : ""}${simple ? `<details class="annotation"><summary>Timing · delay</summary>${field("Delay (s)", numeric("delay", track.delay, 'min="0"'))}</details>` : field("Delay (s)", numeric("delay", track.delay, 'min="0"'))}</div>`;
    }
    renderTrack(track, detail = false, simple = false) {
      const description = `${modes[track.from.mode]} → ${track.to.mode === "value" ? format(track.to.value) : modes[track.to.mode]} · ${F.curves[effective(this.config, track, "curve")]}`;
      return `<div class="track ${track.id === this.selected ? "selected" : ""}" data-track="${track.id}" draggable="true"><div class="track-header"><input type="checkbox" data-field="enabled" aria-label="Enable ${esc(track.target)}.${esc(track.property)}" ${track.enabled ? "checked" : ""}><button class="track-title" data-action="expand" aria-expanded="${track.expanded}"><b>${detail ? "" : track.expanded ? "▾ " : "▸ "}${esc(track.target)}.${esc(track.property)}</b><small>${esc(description)}</small></button><div class="track-tools">${action("up", "↑", 'aria-label="Move track up"')}${action("down", "↓", 'aria-label="Move track down"')}${action("duplicate", "⧉", 'aria-label="Duplicate track"')}${action("delete", "×", 'aria-label="Delete track"')}</div></div>${!detail && (track.expanded || simple) ? this.trackBody(track, simple) : ""}</div>`;
    }
    renderEditor() {
      const editor = this.el.querySelector(".editor");
      const focused = this.el.contains(document.activeElement) ? document.activeElement : null;
      const focusKey = el => JSON.stringify([el.closest("[data-track]")?.dataset.track, el.dataset, el.getAttribute("aria-label")]);
      const previousFocus = focused ? focusKey(focused) : null;
      const detailKey = el => `${el.closest("[data-track]")?.dataset.track || "root"}|${el.querySelector("summary")?.textContent}`;
      const expanded = new Set([...editor.querySelectorAll("details[open]")].map(detailKey));
      const config = this.config;
      this.el.querySelector(".variant-controls").innerHTML = `<div class="variant-row"><label>Inspector layout${select("layout", {simple: "Simple · one track", rows: "Expandable rows", detail: "Selected-track detail"}, config.layout)}</label>${this.kind === "buttons" ? `<label>Trigger architecture${select("architecture", Object.fromEntries(Object.entries(F.architectures).map(([k, v]) => [k, `${k} · ${v.name}`])), config.architecture)}</label>` : `<label>Value capture${select("capture", {play: "When Play is requested", track: "When each track starts"}, config.capture)}</label>`}</div>`;
      const visibleTracks = config.layout === "simple" ? config.tracks.slice(0, 1) : config.tracks;
      const current = config.tracks.find(t => t.id === this.selected) || config.tracks[0];
      const trackHtml = config.layout === "detail" ? `<div class="selected-layout"><div>${visibleTracks.map(t => this.renderTrack(t, true)).join("")}</div>${current ? `<div><div class="track-tools">${action("up", "↑ Up", `data-track="${current.id}"`)}${action("down", "↓ Down", `data-track="${current.id}"`)}${action("duplicate", "Duplicate", `data-track="${current.id}"`)}${action("delete", "Delete", `data-track="${current.id}"`)}</div>${this.trackBody(current, false)}</div>` : ""}</div>` : visibleTracks.map(t => this.renderTrack(t, false, config.layout === "simple")).join("");
      const total = Math.max(.001, ...playable(config).map(t => t.delay + effective(config, t, "duration")));
      const strip = `<div class="timing-strip">READ-ONLY TIMING · ${total.toFixed(2)} s${playable(config).map(t => `<div class="timing-row"><span>${esc(t.target)}.${esc(t.property)}</span><div class="timing-bar"><i style="margin-left:${t.delay / total * 100}%;width:${effective(config, t, "duration") / total * 100}%"></i></div></div>`).join("")}</div>`;
      const runtime = `<div class="runtime-tools">${action("source", "Change destination ↔")}${action("baseline", "Layout +24 px")}${action("base-scale", "Base scale +0.1")}${action("half", "Interrupt at 50%")}</div><p class="binding-note">Character.target_position: ${format(this.scene.Character.target_position)} · external base: y=${this.baseline.y}, scale=${this.baseline.scale.toFixed(1)}</p>`;
      this.el.querySelector(".editor").innerHTML = `${this.kind === "buttons" ? this.renderArchitecture() : ""}<div class="ownership">${field("Curve ownership", select("curveOwnership", ownershipOptions, config.curveOwnership))}<div class="field"><span>Default curve</span><div class="curve-picker">${select("curve", F.curves, config.curve, `aria-label="Default curve" ${config.curveOwnership === "per" ? "disabled" : ""}`)}${graph(config.curve)}</div></div>${field("Time ownership", select("durationOwnership", ownershipOptions, config.durationOwnership))}${field("Duration (s)", numeric("duration", config.duration, `min="0" ${config.durationOwnership === "per" ? "disabled" : ""}`))}<details class="annotation"><summary>Advanced playback · working controls</summary>${field("Speed", numeric("speed", config.speed, 'min=".01"'))}${field("Capture", select("capture", {play: "Play-time", track: "Track-start"}, config.capture))}${field("Return", select("returnPolicy", returnOptions, config.returnPolicy))}${field("Visual binding", select("transform", {wrapper: "Wrapper + child (4.4.1+)", offset: "Offset transform (4.7+)"}, config.transform))}<p>Wrapper: animate child under a layout slot. Offset: browser adds visual offsets to the external base; input stays fixed, equivalent to visual-only enabled. This does not emulate container layout.</p><label class="inline-check"><input type="checkbox" data-field="audition" ${config.audition ? "checked" : ""}>Audition presets on pointer hover</label><div class="event-controls">${Object.entries(F.curves).map(([key, name]) => `<button data-audition="${key}" data-action="audition" title="Audition ${name}">${name}</button>`).join("")}</div></details></div><details class="scene"><summary>Scene tree · drag a target, or click to assign</summary><div class="scene-nodes">${Object.entries(F.targets).map(([id, target]) => `<button draggable="true" class="scene-node" data-node="${id}" data-action="assign-node">◇ ${id}<small> ${target.type}</small></button>`).join("")}</div></details><div class="tracks">${trackHtml || '<div class="empty">No tracks. Add a property to begin.</div>'}</div>${action("add", "+ Add track", 'class="add-track"')}${config.layout === "simple" && config.tracks.length > 1 ? `<p class="binding-note">${config.tracks.length - 1} additional tracks retained. Switch layout to edit/play them.</p>` : ""}${strip}${this.kind === "restore" || this.kind === "values" ? runtime : ""}${this.kind === "restore" ? field("Return behavior", select("returnPolicy", returnOptions, config.returnPolicy)) + field("Layout variant", select("transform", {wrapper: "Wrapper + animated child", offset: "4.7 offset transform"}, config.transform)) + action("return", "↶ Return using selected policy") : ""}<details class="snapshots"><summary>Inspect values, endpoints & snapshot</summary><pre></pre></details><details class="annotation"><summary>Engine-only settings · annotated mockup</summary><div class="engine-mock"><label class="inline-check"><input type="checkbox" data-engine>Autoplay on ready</label><label class="inline-check"><input type="checkbox" data-engine>Loop</label><label class="field"><span>Loop count</span><input type="number" min="0" value="2" data-engine></label><label class="inline-check"><input type="checkbox" data-engine>Ping-pong</label><label class="inline-check"><input type="checkbox" data-engine>Ignore time scale</label><label class="field"><span>Process</span><select data-engine><option>Idle</option><option>Physics</option></select></label><label class="field"><span>Pause</span><select data-engine><option>Bound node</option><option>Stop</option><option>Process</option></select></label></div><p class="engine-note">These controls annotate a possible Inspector only. No engine scheduling or lifecycle is executed. The Return policy has a separate working, finite ping-pong demonstration.</p></details><label class="inline-check"><input type="checkbox" data-field="manualMotion" ${this.manualMotion ? "checked" : ""}>Manual interaction motion · use progress to inspect</label>${action("reset-example", "Reset example", 'style="margin-top:12px;font-size:10px"')}`;
      editor.querySelectorAll("details").forEach(el => { if (expanded.has(detailKey(el))) el.open = true; });
      if (focused && !focused.isConnected) {
        const replacement = [...this.el.querySelectorAll("input,select,button")].find(el => focusKey(el) === previousFocus);
        (replacement || this.el.querySelector('[data-action="add"]')).focus({preventScroll: true});
      }
      this.paint();
    }
    renderArchitecture() {
      const c = this.config, arch = F.architectures[c.architecture];
      const labels = {A: "EasingTween · embedded trigger settings", B: "Selected: EasingInteraction → configured EasingTween", C: "Signal connection walkthrough · click to connect/disconnect", D: "JuicyInteraction · recipe event bindings"};
      const routeControls = Object.entries(eventNames).map(([key, name]) => c.architecture === "C" ? action("connect", `${c.routes[key] ? "●" : "○"} ${name} → handler`, `data-event="${key}" aria-pressed="${c.routes[key]}"`) : `<label><input type="checkbox" data-route="${key}" ${c.routes[key] ? "checked" : ""}>${name}</label>`).join("");
      return `<div class="architecture-card"><h3>${labels[c.architecture]}</h3><pre>${esc(arch.tree)}</pre><p>${esc(arch.flow)}</p><p><b>Benefit:</b> ${arch.benefit}<br><b>Cost:</b> ${arch.cost}</p><p>${arch.responsibility}</p><div class="routing">${routeControls}</div>${c.architecture === "C" ? '<pre># Candidate handler body\n$HoverTween.play()</pre>' : ""}${field("Recipe", select("recipe", {hover: "Hover", press: "Press / release", focus: "Focus", combined: "Combined"}, c.recipe))}${field("Hover scale", numeric("hoverScale", c.hoverScale))}${field("Press scale", numeric("pressScale", c.pressScale))}${field("Focus scale", numeric("focusScale", c.focusScale))}${field("Lift (px)", numeric("lift", c.lift))}<details><summary>Phase durations · seconds</summary>${field("Press", numeric("pressDuration", c.pressDuration, 'min="0"'))}${field("Release", numeric("releaseDuration", c.releaseDuration, 'min="0"'))}${field("Focus", numeric("focusDuration", c.focusDuration, 'min="0"'))}</details><div class="event-controls">${Object.entries(eventNames).map(([key, name]) => action("event", name, `data-event="${key}"`)).join("")}</div><div class="runtime-tools">${action("baseline", "Move layout +24")}${action("base-scale", "Base scale +0.1")}</div><p>Changing architecture preserves this recipe and uses the same simulator. Unchecking a route really disconnects it in this mock.</p></div>`;
    }
    change(e) {
      const input = e.target;
      if (input.matches("[data-engine]")) { this.el.querySelector(".engine-note").textContent = "Mock setting changed. Godot scheduling, serialization and lifecycle remain documentation only; playback is unchanged."; return; }
      const track = this.config.tracks.find(t => t.id === input.closest("[data-track]")?.dataset.track);
      if (input.dataset.route) { this.edit(); this.config.routes[input.dataset.route] = input.checked; this.renderEditor(); return; }
      if (!input.dataset.field && !input.dataset.endpoint && !input.dataset.color) return;
      this.edit();
      if (input.dataset.endpoint && track) {
        const value = input.value.trim() === "" ? NaN : Number(input.value);
        if (input.dataset.component === "scalar") track[input.dataset.endpoint].value = value;
        else track[input.dataset.endpoint].value[Number(input.dataset.component)] = value;
      } else if (input.dataset.color && track) {
        const value = track[input.dataset.color].value;
        for (let i = 0; i < 3; i++) value[i] = parseInt(input.value.slice(i * 2 + 1, i * 2 + 3), 16) / 255;
      } else {
        const key = input.dataset.field;
        const value = input.type === "checkbox" ? input.checked : input.type === "number" ? input.value.trim() === "" ? NaN : Number(input.value) : input.value;
        if (key === "manualMotion") this.manualMotion = value;
        else if (track && key === "binding") { track.binding = value; if (value !== "explicit") this.assignTarget(track, value === "parent" ? "Button" : "Visual", true); }
        else if (track && key === "manualPath") this.assignProperty(track, value);
        else if (track && key.endsWith("Mode")) {
          const endpoint = key.slice(0, -4); track[endpoint].mode = value;
          if (value === "relative") track[endpoint].value = Array.isArray(meta(track.target, track.property)?.value) ? meta(track.target, track.property).value.map(() => 0) : 0;
        } else if (track && ["enabled", "delay", "curveOverride", "durationOverride", "trackCurve", "trackDuration"].includes(key)) track[key === "trackCurve" ? "curve" : key === "trackDuration" ? "duration" : key] = value;
        else this.config[key] = value;
      }
      try { validate(this.config, this.scene); } catch (error) { this.error = error.message; }
      this.renderEditor();
    }
    assignTarget(track, target, preserveBinding = false) {
      track.target = target; if (!preserveBinding) track.binding = "explicit";
      const path = meta(target, track.property) ? track.property : F.targets[target].properties[0].path;
      this.assignProperty(track, path);
    }
    assignProperty(track, path) {
      const oldType = meta(track.target, track.property)?.type;
      track.property = path;
      const property = meta(track.target, path);
      if (!property) { this.error = "Unsupported property path. Choose a listed property."; return; }
      for (const endpoint of ["from", "to"]) {
        if (oldType !== property.type || !validValue(track[endpoint].value, property.type)) track[endpoint].value = copy(property.value);
        if (track[endpoint].mode === "property" && meta(track[endpoint].sourceTarget, track[endpoint].sourceProperty)?.type !== property.type) this.error = "Source type no longer matches. Choose a compatible source property.";
      }
    }
    chooseTarget(track) {
      openPicker("Choose a target", Object.entries(F.targets).map(([key, t]) => ({key, label: t.label, detail: t.type, group: t.type === "ShaderMaterial" ? "Resource owner" : "Scene nodes"})), row => { this.edit(); this.assignTarget(track, row.key); this.renderEditor(); });
    }
    chooseProperty(track, endpoint) {
      const rows = [];
      const type = meta(track.target, track.property)?.type;
      for (const [target, data] of Object.entries(F.targets)) {
        if (!endpoint && target !== track.target) continue;
        for (const p of data.properties) {
          if (endpoint && p.type !== type) continue;
          rows.push({key: `${target}|${p.path}`, target, path: p.path, label: endpoint ? `${target}.${p.path}` : p.path, detail: `${p.type} · ${data.type}`, group: p.category, favorite: true});
        }
      }
      openPicker(endpoint ? `Read ${endpoint} from a ${type} property` : "Choose a tweenable property", rows, row => {
        this.edit();
        if (endpoint) { track[endpoint].sourceTarget = row.target; track[endpoint].sourceProperty = row.path; }
        else this.assignProperty(track, row.path);
        this.renderEditor();
      });
    }
    click(e) {
      const button = e.target.closest("[data-action]"); if (!button) return;
      const name = button.dataset.action;
      const track = this.config.tracks.find(t => t.id === button.closest("[data-track]")?.dataset.track) || this.config.tracks.find(t => t.id === this.selected);
      if (name === "preview") this.run();
      else if (name === "replay") { this.reset(); this.run(); }
      else if (name === "stop") { this.stop(); this.message = "Stopped · values held, snapshot retained"; this.paint(); }
      else if (name === "reset") this.reset();
      else if (name === "reverse") { this.stop(); this.playback.reverse(); this.message = "Exact reverse · captured endpoints, original curve"; this.animate(); }
      else if (name === "target" && track) this.chooseTarget(track);
      else if (name === "property" && track) this.chooseProperty(track);
      else if (name.startsWith("source-") && track) this.chooseProperty(track, name.slice(7));
      else if (name === "source") this.changeSource();
      else if (name === "baseline") this.moveBaseline();
      else if (name === "base-scale") { this.baseline.scale = Math.round((this.baseline.scale + .1) * 10) / 10; this.message = `External scale changed to ${this.baseline.scale}; captured endpoints unchanged`; this.paint(); }
      else if (name === "half") this.scrub(.5);
      else if (name === "return") this.returnToBase();
      else if (name === "event") this.event(button.dataset.event);
      else if (name === "audition") { if (!this.auditioning) this.run(button.dataset.audition); }
      else {
        if (name === "expand" && track) { this.selected = track.id; track.expanded = !track.expanded; this.renderEditor(); return; }
        this.edit();
        if (name === "add") { const t = F.track("Button", "rotation", .12); this.config.tracks.push(t); this.selected = t.id; this.config.layout = "rows"; }
        else if (name === "assign-node" && track) this.assignTarget(track, button.dataset.node);
        else if (name === "missing" && track) { track.target = "MissingNode"; this.error = "Target removed. Choose an available node to continue."; }
        else if (name === "delete" && track) { this.config.tracks = this.config.tracks.filter(t => t.id !== track.id); this.selected = this.config.tracks[0]?.id; }
        else if (name === "duplicate" && track) { const t = duplicateTrack(track); t.enabled = false; this.config.tracks.splice(this.config.tracks.indexOf(track) + 1, 0, t); this.selected = t.id; this.message = "Duplicated independently · disabled to avoid overlapping writes"; }
        else if (["up", "down"].includes(name) && track) reorderTrack(this.config.tracks, track.id, this.config.tracks.indexOf(track) + (name === "up" ? -1 : 1));
        else if (name === "connect") this.config.routes[button.dataset.event] = !this.config.routes[button.dataset.event];
        else if (name === "reset-example") { this.config = F.config(this.kind); this.scene = F.scene(); this.baseline = {y: 0, scale: 1}; this.playback = new Playback(this.scene); this.selected = this.config.tracks[0].id; this.message = "Fixture defaults restored"; }
        this.renderEditor();
      }
    }
    drop(e) {
      const trackEl = e.target.closest("[data-track]"); if (!trackEl) return;
      e.preventDefault(); this.edit();
      const node = e.dataTransfer.getData("application/x-lab-node"), id = e.dataTransfer.getData("application/x-lab-track");
      const track = this.config.tracks.find(t => t.id === trackEl.dataset.track);
      if (node && F.targets[node]) this.assignTarget(track, node);
      else if (id) reorderTrack(this.config.tracks, id, this.config.tracks.indexOf(track));
      this.renderEditor();
    }
    changeSource() {
      const old = this.scene.Character.target_position;
      this.scene.Character.target_position = old[0] === 100 ? [-90, -25] : [100, 35];
      this.message = `Runtime destination is now ${format(this.scene.Character.target_position)} · existing endpoints stay captured`;
      this.paint();
    }
    moveBaseline() {
      this.baseline.y = this.baseline.y >= 48 ? -24 : this.baseline.y + 24;
      this.message = `External layout moved to y=${this.baseline.y} · snapshot and endpoints unchanged`;
      this.paint();
    }
    returnToBase() {
      const policy = this.config.returnPolicy;
      if (!this.playback.entries.length) { this.run(); if (policy === "pingpong") this.pingpong = true; return; }
      if (policy === "exact" || policy === "pingpong") { this.stop(); this.playback.reverse(); this.message = "Returning along the captured curve"; this.animate(); return; }
      if (policy === "auto") { this.reset(); return; }
      const config = copy(this.config); config.layout = "rows"; config.capture = "play";
      config.curve = policy === "paired" ? "elastic" : "cubic"; config.curveOwnership = "shared";
      config.duration = .5; config.durationOwnership = "shared";
      config.tracks = this.playback.entries.map(e => {
        const t = copy(e.track); t.delay = 0; t.from.mode = "current"; t.to.mode = "value";
        const original = this.snapshot?.find(s => s.target === t.target && s.property === t.property)?.value ?? read(this.scene, t.target, t.property);
        t.to.value = copy(e.endpoints?.from ?? original);
        if (policy === "fresh" || policy === "paired") {
          if (t.property === "scale") t.to.value = [this.config.transform === "offset" ? 1 : this.baseline.scale, this.config.transform === "offset" ? 1 : this.baseline.scale];
          else if (t.property === "position:y") t.to.value = this.config.transform === "offset" ? 0 : this.baseline.y;
        } else if (policy === "explicit") t.to.value = copy(meta(t.target, t.property).value);
        else if (policy === "reread") { const current = read(this.scene, t.target, t.property); t.to.value = t.property === "position:y" ? current + this.config.lift : current; }
        return t;
      });
      this.run(null, config); this.message = `${returnOptions[policy]} · new return animation, not exact reverse`; this.paint();
    }
    bindButton() {
      if (this.kind !== "buttons") return;
      const hit = this.el.querySelector(".hit-region");
      hit.addEventListener("pointerenter", () => this.event("enter"));
      hit.addEventListener("pointerleave", () => this.event("exit"));
      hit.addEventListener("pointerdown", e => { if (e.button === 0) { e.preventDefault(); this.event("down"); } });
      window.addEventListener("pointerup", e => {
        if (!this.interaction.pressed) return;
        const bounds = hit.getBoundingClientRect();
        if (e.clientX >= bounds.left && e.clientX <= bounds.right && e.clientY >= bounds.top && e.clientY <= bounds.bottom) this.event("pressed");
        this.event("up");
      });
      window.addEventListener("pointercancel", () => { if (this.interaction.pressed) this.event("up"); });
      this.stageButton.addEventListener("focus", () => this.event("focus"));
      this.stageButton.addEventListener("blur", () => { this.event("blur"); if (this.interaction.pressed) this.event("up"); });
      this.stageButton.addEventListener("keydown", e => { if ([" ", "Enter"].includes(e.key)) { e.preventDefault(); if (!e.repeat) this.event("down"); } });
      this.stageButton.addEventListener("keyup", e => { if ([" ", "Enter"].includes(e.key)) { e.preventDefault(); this.event("pressed"); this.event("up"); } });
    }
    event(name) {
      const c = this.config;
      if (!c.routes[name]) { this.message = `${eventNames[name]} is disconnected in architecture ${c.architecture}`; this.paint(); return; }
      if (name === "pressed") { this.message = `Pressed → ${F.architectures[c.architecture].name} · activation only`; this.paint(); return; }
      const keys = {enter: ["hover", true], exit: ["hover", false], down: ["pressed", true], up: ["pressed", false], focus: ["focus", true], blur: ["focus", false]};
      const [key, value] = keys[name]; this.interaction[key] = value;
      const press = this.interaction.pressed && ["press", "combined"].includes(c.recipe);
      const hover = this.interaction.hover && ["hover", "combined"].includes(c.recipe);
      const focus = this.interaction.focus && ["focus", "combined"].includes(c.recipe);
      const scale = press ? c.pressScale : hover ? c.hoverScale : focus ? c.focusScale : 1;
      const y = press ? 2 : hover ? -c.lift : 0;
      if (![scale, y, c.pressDuration, c.releaseDuration, c.focusDuration].every(Number.isFinite) || Math.min(c.pressDuration, c.releaseDuration, c.focusDuration) < 0) { this.error = "Recipe values must be finite and phase durations nonnegative."; this.paint(); return; }
      const config = copy(c); config.layout = "rows"; config.capture = "play";
      const offset = c.transform === "offset";
      // Recipe compilation changes targets, never the simulator or routing implementation.
      for (const t of config.tracks) {
        t.from.mode = "current"; t.to.mode = "value"; t.delay = 0;
        if (t.property === "scale") t.to.value = [scale * (offset ? 1 : this.baseline.scale), scale * (offset ? 1 : this.baseline.scale)];
        else if (t.property === "position:y") t.to.value = y + (offset ? 0 : this.baseline.y);
        else if (t.property === "self_modulate" || t.property === "modulate") t.to.value = hover || focus ? [.85, .9, 1, 1] : [.65, .78, 1, 1];
      }
      const glow = F.track("Visual", "glow", focus ? 1 : 0); glow.duration = c.focusDuration; config.tracks.push(glow);
      if (press) { config.duration = c.pressDuration; config.curve = "cubic"; }
      else if (name === "up") { config.duration = c.releaseDuration; config.curve = "spring"; }
      else if (focus && !hover) config.duration = c.focusDuration;
      this.run(null, config);
      if (this.manualMotion || matchMedia("(prefers-reduced-motion: reduce)").matches) { this.stop(); this.message = "Interaction captured · scrub progress (manual / reduced motion)"; }
      else this.message = `${eventNames[name]} → ${F.architectures[c.architecture].name} → shared playback`;
      if (name === "exit" && c.returnPolicy === "auto") this.reset();
      this.paint();
    }
  }
  for (const host of document.querySelectorAll("[data-lab]")) for (let side = 0; side < 2; side++) labs.push(new Lab(host.dataset.lab, side, host));
  const decisions = [
    ["Should EasingTween be a Node?", "Node + track data; compare one node/property and resource+host.", "Count setup steps and scene-tree clutter.", "architecture"],
    ["Should tracks be Resources?", "Try shareable authored data; keep playback state separate.", "Review target rebinding across instances.", "architecture"],
    ["One track or many by default?", "One-track entry; expandable rows for a full gesture.", "Author hover in all three layouts.", "authoring"],
    ["Where does duration live?", "Shared default with explicit optional overrides.", "Compare editing speed with per-track timing.", "authoring"],
    ["Where does the curve live?", "Shared default + override; phases remain another candidate.", "Compare a coordinated scale/lift/tint gesture.", "authoring"],
    ["How do value modes work?", "Current implicit in Simple; explicit modes in Advanced.", "Try typed values and delayed dynamic destinations.", "values"],
    ["Where do triggers live?", "Compare companion and built-in; no selection is final.", "Wire the same recipe in A/B/C/D.", "buttons"],
    ["Cleanest JuicyButton workflow?", "Compare helper convenience with generic node flexibility.", "Keyboard focus, rapid presses, release outside.", "buttons"],
    ["Preview / Reset / Reverse?", "Preview snapshot; Stop holds; Reset restores; Reverse retraces.", "Interrupt halfway and inspect all value readouts.", "restore"],
    ["Runtime changes to baseline?", "Explicit external baseline or independent visual offset.", "Move layout between enter and exit; expose drift.", "restore"],
    ["Which convenience APIs?", "Test a small tween_property helper; sample() may suffice.", "Compare discoverability, return types, Native parity.", "architecture"],
    ["v1.2.3 versus later?", "Propose only proven compact authoring; baking is future.", "A separate production plan and Godot feasibility checks.", "decisions"],
    ["Boundary with AnimationPlayer?", "Compact dynamic gestures vs long authored sequences.", "Attempt a multi-phase sequence and note friction.", "decisions"],
    ["Generic property support?", "Metadata-driven typed controls; bounded demonstrated types.", "Try Control, Node2D/3D, Rect2, int, and shader fixtures.", "values"]
  ];
  document.querySelector("#decision-rows").innerHTML = decisions.map(([q, r, e, link], i) => `<tr><td><a href="#${link}">${i + 1}. ${q}</a></td><td>${r}</td><td>${e}</td></tr>`).join("");
  document.addEventListener("click", e => {
    for (const [attribute, method] of [["data-run-pair", "run"], ["data-source-pair", "changeSource"], ["data-baseline-pair", "moveBaseline"], ["data-return-pair", "returnToBase"]]) {
      const button = e.target.closest(`[${attribute}]`);
      if (button) labs.filter(l => l.kind === button.getAttribute(attribute)).forEach(l => l[method]());
    }
  });
  function navigate() {
    const id = location.hash.slice(1) || "overview";
    const page = document.getElementById(id)?.classList.contains("page") ? id : "overview";
    for (const lab of labs) if (lab.kind !== page && (lab.snapshot || lab.playback.entries.length)) lab.reset();
    document.querySelectorAll(".page").forEach(el => { el.hidden = el.id !== page; });
    document.querySelectorAll("nav a").forEach(a => { a.classList.toggle("active", a.hash === `#${page}`); if (a.hash === `#${page}`) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current"); });
    window.scrollTo(0, 0);
  }
  window.addEventListener("hashchange", navigate);
  document.addEventListener("visibilitychange", () => { if (document.hidden) labs.forEach(l => { l.stop(); }); });
  navigate();
}

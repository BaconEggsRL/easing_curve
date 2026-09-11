"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const F = require("../fixtures.js");
const S = require("../assets/curve_samples.js");
const {Playback, sampleCurve, resolveValue, effective, read, write, validate, snapshotFor, restoreSnapshot, duplicateTrack, reorderTrack} = require("../script.js");
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-6, `${a} ≠ ${b}`);
for (const values of Object.values(S)) {
  assert.equal(values.length, 257); assert.ok(values.every(Number.isFinite));
  near(sampleCurve(values, -1), values[0]); near(sampleCurve(values, 2), values.at(-1));
  near(sampleCurve(values, .5 / 256), (values[0] + values[1]) / 2);
}
assert.ok(Math.max(...S.back) > 1); assert.ok(Math.max(...S.elastic) > 1);
// Verify reused samples stay byte-for-value identical to the original data when in the repo.
const docsPath = path.resolve(__dirname, "../../../..", "docs/curve_samples.js");
if (fs.existsSync(docsPath)) {
  const context = {window: {}}; vm.runInNewContext(fs.readFileSync(docsPath, "utf8"), context);
  for (const [key, original] of Object.entries({back: "popup", smoothstep: "sliding_door", css: "charge_meter"})) assert.equal(JSON.stringify(S[key]), JSON.stringify(context.window.CURVE_SAMPLES[original]));
}
const scene = F.scene();
near(resolveValue({mode: "relative", value: -4}, 20, scene, "float"), 16);
assert.deepEqual(resolveValue({mode: "current"}, [2, 3], scene, "Vector2"), [2, 3]);
assert.deepEqual(resolveValue({mode: "value", value: [4, 6]}, [2, 3], scene, "Vector2"), [4, 6]);
assert.deepEqual(resolveValue({mode: "relative", value: [4, -1]}, [2, 3], scene, "Vector2"), [6, 2]);
assert.deepEqual(resolveValue({mode: "property", sourceTarget: "Character", sourceProperty: "target_position"}, [0, 0], scene, "Vector2"), [100, 35]);
assert.throws(() => resolveValue({mode: "property", sourceTarget: "Character", sourceProperty: "score"}, [0, 0], scene, "Vector2"), /same type/);
assert.throws(() => resolveValue({mode: "value", value: Infinity}, 0, scene, "float"), /finite/);
assert.throws(() => resolveValue({mode: "value", value: 1.2}, 0, scene, "int"), /whole/);
write(scene, "Button", "position:y", 24); assert.deepEqual(read(scene, "Button", "position"), [0, 24]);
write(scene, "Button", "modulate:a", .4); near(read(scene, "Button", "modulate")[3], .4);
const config = F.config(); config.curve = "linear"; config.duration = 1;
config.tracks[0].curve = "spring"; config.tracks[0].duration = 2;
assert.equal(effective(config, config.tracks[0], "curve"), "linear");
config.curveOwnership = "override"; assert.equal(effective(config, config.tracks[0], "curve"), "linear");
config.tracks[0].curveOverride = true; assert.equal(effective(config, config.tracks[0], "curve"), "spring");
config.durationOwnership = "per"; assert.equal(effective(config, config.tracks[0], "duration"), 2);
config.durationOwnership = "override"; assert.equal(effective(config, config.tracks[0], "duration"), 1);
config.tracks[0].durationOverride = true; assert.equal(effective(config, config.tracks[0], "duration"), 2);
const duplicate = duplicateTrack(config.tracks[0]); duplicate.to.value[0] = 8;
assert.notEqual(duplicate.id, config.tracks[0].id); assert.equal(config.tracks[0].to.value[0], 1.08);
const ids = config.tracks.map(t => t.id); reorderTrack(config.tracks, ids[2], 0); assert.equal(config.tracks[0].id, ids[2]); assert.equal(config.tracks[1].id, ids[0]);
function scalarConfig() {
  const c = F.config(); c.tracks = [F.track("Button", "position:y", 100)]; c.duration = 1; c.curve = "linear"; return c;
}
const c = scalarConfig(), s = F.scene(), p = new Playback(s), snap = snapshotFor(c.tracks, s);
p.start(c); p.step(.4); near(s.Button.position[1], 40);
p.stop(); p.step(.3); near(s.Button.position[1], 40);
p.reverse(); p.step(.2); near(s.Button.position[1], 20); p.step(.2); near(s.Button.position[1], 0);
p.start(c); p.step(.4); c.tracks[0].to.value = -20; p.start(c); near(p.entries[0].endpoints.from, 40); p.step(.5); near(s.Button.position[1], 10);
restoreSnapshot(snap, s); near(s.Button.position[1], 0);
// A fresh return endpoint is separate from a captured start and editor snapshot.
s.Button.position[1] = -4; const externalBaseline = 24; c.tracks[0].to.value = externalBaseline; p.start(c); p.step(1); near(s.Button.position[1], 24); restoreSnapshot(snap, s); near(s.Button.position[1], 0);
for (const capture of ["play", "track"]) {
  const c = F.config("values"), s = F.scene(), p = new Playback(s); c.capture = capture; c.curve = "linear";
  p.start(c); s.Character.target_position = [-90, -25]; p.step(.7);
  assert.deepEqual(p.entries[0].endpoints.to, capture === "play" ? [100, 35] : [-90, -25]);
  s.Character.target_position = [900, 900]; p.step(.8); assert.deepEqual(s.Character.position, capture === "play" ? [100, 35] : [-90, -25]);
}
// Same delayed distinction for From Current, not just a source destination.
for (const capture of ["play", "track"]) {
  const c = scalarConfig(), s = F.scene(), p = new Playback(s); c.capture = capture; c.tracks[0].delay = 1;
  p.start(c); s.Button.position[1] = 50; p.step(1); near(p.entries[0].endpoints.from, capture === "play" ? 0 : 50);
}
const disabled = scalarConfig(); disabled.tracks[0].enabled = false; assert.throws(() => validate(disabled, F.scene()), /enable/);
const conflict = scalarConfig(); conflict.tracks.push(F.track("Button", "position", [1, 1])); assert.throws(() => validate(conflict, F.scene()), /Overlapping/);
const bad = scalarConfig(); bad.duration = -1; assert.throws(() => validate(bad, F.scene()), /nonnegative/);
bad.duration = 1; bad.tracks[0].property = "__proto__"; assert.throws(() => validate(bad, F.scene()), /available/);
const zero = scalarConfig(), zs = F.scene(), zp = new Playback(zs); zero.duration = 0; zp.start(zero); near(zs.Button.position[1], 100); assert.equal(zp.running, false);
const delayed = scalarConfig(), ds = F.scene(), dp = new Playback(ds); delayed.tracks[0].delay = .5; delayed.speed = 2; dp.start(delayed); dp.step(.125); near(ds.Button.position[1], 0); dp.step(.375); near(ds.Button.position[1], 50);
// Exact reversal uses the original nonlinear path, not a new return ease.
const nonlinear = scalarConfig(), ns = F.scene(), np = new Playback(ns); nonlinear.curve = "back"; np.start(nonlinear); np.step(.7); np.reverse(); np.step(.2); near(ns.Button.position[1], sampleCurve(S.back, .5) * 100);
for (const [target, property, value] of [["Character", "score", 9], ["Object3D", "position", [10, 20, 30]], ["Panel", "preview_rect", [5, 10, 180, 90]], ["Material", "shader_parameter/tint", [.8, .2, .5, .8]]]) {
  const c = scalarConfig(), s = F.scene(), p = new Playback(s); c.tracks = [F.track(target, property, value)]; p.start(c); p.step(1); assert.deepEqual(read(s, target, property), value);
}
const root = path.resolve(__dirname, "..");
const html = fs.readFileSync(path.join(root, "index.html"), "utf8");
const anchors = [...html.matchAll(/\bid="([^"]+)"/g)].map(m => m[1]); assert.equal(new Set(anchors).size, anchors.length);
for (const [, ref] of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
  if (ref.startsWith("#")) assert.ok(anchors.includes(ref.slice(1)), ref);
  else if (!ref.startsWith("https://")) assert.ok(fs.existsSync(path.join(root, ref)), ref);
}
assert.ok(!html.includes('type="module"')); assert.ok(!/https?:\/\/[^" ]+\.(?:js|css)/.test(html));
console.log("PASS: samples/reuse, types, all value modes, both capture boundaries, overrides, identity, cancellation, reverse, snapshot/fresh baseline, delays/speed, errors, links and local scripts.");

"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { sampleCurve, validDuration } = require("../../../docs/site.js");
const root = path.resolve(__dirname, "../../..");
const docs = path.join(root, "docs");
const context = { window: {} };
vm.runInNewContext(fs.readFileSync(path.join(docs, "curve_samples.js"), "utf8"), context);
const samples = context.window.CURVE_SAMPLES;
assert.deepEqual(Object.keys(samples).sort(), ["charge_meter", "popup", "sliding_door"]);
for (const values of Object.values(samples)) {
  assert.equal(values.length, 257);
  assert.ok(values.every(Number.isFinite));
  assert.ok(Math.abs(sampleCurve(values, -1)) < 1e-6);
  assert.ok(Math.abs(sampleCurve(values, 2) - 1) < 1e-6);
  for (let index = 0; index < 256; index++) {
    assert.ok(Math.abs(sampleCurve(values, (index + 0.5) / 256) - (values[index] + values[index + 1]) / 2) < 1e-12);
  }
}
assert.ok(Math.max(...samples.popup) > 1, "popup retains overshoot");
assert.ok(Math.abs(sampleCurve(samples.charge_meter, 0.5) - 0.25) < 1e-6);
assert.equal(validDuration("", 2), 2);
assert.equal(validDuration("garbage", 2), 2);
assert.equal(validDuration("Infinity", 2), 2);
assert.equal(validDuration("0", 2), 2);
assert.equal(validDuration("11", 2), 2);
assert.equal(validDuration("0.6", 2), 0.6);

const html = fs.readFileSync(path.join(docs, "index.html"), "utf8");
const ids = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
assert.equal(new Set(ids).size, ids.length, "unique HTML anchors");
for (const [, ref] of html.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
  if (ref.startsWith("#")) assert.ok(ids.includes(ref.slice(1)), `missing anchor ${ref}`);
  else if (!ref.startsWith("https://")) {
    assert.ok(!ref.startsWith("/"), "assets must work beneath /easing_curve/");
    assert.ok(fs.existsSync(path.join(docs, ref)), `missing asset ${ref}`);
  }
  const sourcePrefix = "https://github.com/BaconEggsRL/easing_curve/blob/master/";
  if (ref.startsWith(sourcePrefix)) assert.ok(fs.existsSync(path.join(root, ref.slice(sourcePrefix.length))), `missing example source ${ref}`);
}
for (const [, filename, encoded] of html.matchAll(/<code data-source="([^"]+)">([\s\S]*?)<\/code>/g)) {
  const snippet = encoded.replaceAll("&lt;", "<").replaceAll("&gt;", ">").replaceAll("&amp;", "&");
  const source = fs.readFileSync(path.join(root, "addons/easing_curve/examples", filename), "utf8").replaceAll("\r\n", "\n");
  assert.ok(source.includes(snippet), `${filename} recipe drifted from the runnable example`);
}
const allowlist = fs.readFileSync(path.join(root, "release/addon_files.txt"), "utf8").split(/\r?\n/);
for (const file of fs.readdirSync(path.join(root, "addons/easing_curve/examples"))) {
  assert.ok(allowlist.includes(`examples/${file}`), `${file} missing from release allowlist`);
}
assert.equal(fs.readFileSync(path.join(root, "README.md"), "utf8"), fs.readFileSync(path.join(root, "addons/easing_curve/README.md"), "utf8"), "README copies stay synchronized");
console.log("PASS: sampled browser interpolation, duration validation, links, snippets, and release entries");

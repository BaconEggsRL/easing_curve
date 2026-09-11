"use strict";
const FIXTURES = (() => {
  const curves = {back: "Back Out", cubic: "Cubic Out", spring: "Spring Out", elastic: "Elastic Out", bounce: "Bounce Out", smoothstep: "Smoothstep", css: "CSS Bézier", linear: "Linear"};
  const property = (path, type, value, category = "Transform") => ({path, type, value, category});
  function spatial(dim) {
    const vector = `Vector${dim}`;
    return [property("position", vector, Array(dim).fill(0)), ...["x", "y", "z"].slice(0, dim).map(axis => property(`position:${axis}`, "float", 0)), property("scale", vector, Array(dim).fill(1)), property("rotation", "float", 0)];
  }
  const colors = [property("modulate", "Color", [.65, .78, 1, 1], "Visibility"), property("modulate:a", "float", 1, "Visibility"), property("self_modulate", "Color", [.65, .78, 1, 1], "Visibility")];
  const control = [...spatial(2), ...colors, property("size", "Vector2", [148, 56], "Control"), property("custom_minimum_size", "Vector2", [120, 40], "Control")];
  const targets = {
    Button: {type: "Button", label: "Menu / Button", root: "Menu", properties: control},
    Visual: {type: "Control", label: "Menu / Button / Visual", root: "Button", properties: [...control, property("glow", "float", 0, "Script")]},
    Panel: {type: "Control", label: "Menu / Panel", root: "Menu", properties: [...control, property("preview_rect", "Rect2", [0, 0, 120, 60], "Script")]},
    Character: {type: "Node2D", label: "World / Character", root: "World", properties: [...spatial(2), property("target_position", "Vector2", [100, 35], "Script"), property("score", "int", 0, "Script")]},
    Object3D: {type: "Node3D", label: "World / Object3D", root: "World", properties: spatial(3)},
    Material: {type: "ShaderMaterial", label: "Button / Visual · material", root: "Visual", properties: [property("shader_parameter/glow", "float", 0, "Material / Shader"), property("shader_parameter/tint", "Color", [.4, .65, 1, 1], "Material / Shader")]}
  };
  let nextId = 0;
  const clone = value => JSON.parse(JSON.stringify(value));
  function track(target = "Button", path = "scale", value = [1.08, 1.08]) {
    return {id: `track-${++nextId}`, target, property: path, binding: "explicit", enabled: true, expanded: true, from: {mode: "current", value: clone(value), sourceTarget: target, sourceProperty: path}, to: {mode: "value", value: clone(value), sourceTarget: target, sourceProperty: path}, curve: "back", duration: .12, delay: 0, curveOverride: false, durationOverride: false};
  }
  function config(kind = "authoring") {
    const tracks = [track()];
    if (kind !== "values") {
      tracks.push(track("Button", "position:y", -4));
      tracks.push(track("Visual", "self_modulate", [.85, .9, 1, 1]));
      tracks.slice(1).forEach(t => { t.expanded = false; });
    } else {
      tracks[0] = track("Character", "position", [100, 35]);
      tracks[0].to.mode = "property";
      tracks[0].to.sourceProperty = "target_position";
      tracks[0].delay = .7;
    }
    return {tracks, curve: "back", duration: kind === "values" ? .8 : .12, curveOwnership: "shared", durationOwnership: "shared", speed: 1, capture: "track", layout: "rows", architecture: "A", recipe: "combined", returnPolicy: "fresh", transform: "wrapper", audition: false, routes: {enter: true, exit: true, down: true, up: true, focus: true, blur: true, pressed: true}, hoverScale: 1.08, pressScale: .95, focusScale: 1.05, lift: 4, pressDuration: .06, releaseDuration: .18, focusDuration: .15};
  }
  function scene() {
    return Object.fromEntries(Object.entries(targets).map(([id, t]) => [id, Object.fromEntries(t.properties.filter(p => !p.path.includes(":" )).map(p => [p.path, clone(p.value)]))]));
  }
  const architectures = {
    A: {name: "Built-in triggers", tree: "Button\n└─ EasingTween\n   └─ trigger settings", flow: "Button signals → EasingTween trigger rows → shared playback", benefit: "Everything is in one Inspector.", cost: "Generic playback acquires UI-specific settings.", responsibility: "EasingTween owns event bindings and overlap policy."},
    B: {name: "Companion node", tree: "Button\n├─ EasingTween\n└─ EasingInteraction", flow: "Button signals → EasingInteraction → EasingTween → shared playback", benefit: "Playback stays useful outside UI.", cost: "An extra node and references to connect.", responsibility: "EasingInteraction owns input state; EasingTween owns playback."},
    C: {name: "Signals only", tree: "Button\n└─ HoverTween\nScript: signal handlers", flow: "Button signals → user connection / handler → HoverTween.play()", benefit: "Uses normal Godot signal workflows.", cost: "Overlap and return rules require a little code.", responsibility: "The user's handler owns interaction arbitration."},
    D: {name: "Button helper", tree: "Button\n└─ JuicyInteraction\n   └─ configured tracks", flow: "Button signals → recipe helper → generic tracks → shared playback", benefit: "Fastest path to a complete button recipe.", cost: "More opinionated; another concept to maintain.", responsibility: "The helper owns recipes and overlap; generic playback is shared."}
  };
  return {curves, targets, track, config, scene, clone, architectures};
})();
if (typeof module !== "undefined") module.exports = FIXTURES;

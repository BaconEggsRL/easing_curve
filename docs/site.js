"use strict";

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function sampleCurve(values, progress) {
  const position = clamp(progress, 0, 1) * (values.length - 1);
  const index = Math.min(Math.floor(position), values.length - 2);
  return values[index] + (values[index + 1] - values[index]) * (position - index);
}

function validDuration(value, fallback) {
  const duration = Number(value);
  return Number.isFinite(duration) && duration >= 0.05 && duration <= 10 ? duration : fallback;
}

if (typeof module !== "undefined") module.exports = { sampleCurve, validDuration };

if (typeof document !== "undefined") {
  for (const demo of document.querySelectorAll(".demo")) {
    const slug = demo.dataset.example;
    const values = window.CURVE_SAMPLES[slug];
    const play = demo.querySelector(".play");
    const slider = demo.querySelector(".progress");
    const durationInput = demo.querySelector(".duration");
    const target = demo.querySelector(".motion-target");
    const readout = demo.querySelector(".readout");
    let duration = Number(demo.dataset.duration);
    let progress = 0;
    let frame = null;
    let previousTime = null;

    function render() {
      const value = sampleCurve(values, progress);
      if (slug === "popup") target.style.transform = `scale(${0.2 + 0.8 * value})`;
      if (slug === "sliding_door") target.style.transform = `translateX(${value * 280 / 180 * 100}%)`;
      if (slug === "charge_meter") {
        target.value = clamp(value, 0, 1) * 100;
        demo.querySelector(".charge-value").textContent = `${target.value.toFixed(1)}%`;
      }
      slider.value = String(progress);
      readout.value = `t ${progress.toFixed(2)} · sample ${value.toFixed(3)}`;
    }

    function pause() {
      if (frame !== null) cancelAnimationFrame(frame);
      frame = null;
      previousTime = null;
      play.textContent = "Play";
    }

    function tick(now) {
      if (previousTime !== null) progress = Math.min(1, progress + (now - previousTime) / (duration * 1000));
      previousTime = now;
      render();
      if (progress >= 1) pause();
      else frame = requestAnimationFrame(tick);
    }

    function start() {
      pause();
      if (progress >= 1) progress = 0;
      duration = validDuration(durationInput.value, duration);
      durationInput.value = String(duration);
      play.textContent = "Pause";
      frame = requestAnimationFrame(tick);
    }

    play.addEventListener("click", () => frame === null ? start() : pause());
    demo.querySelector(".replay").addEventListener("click", () => { progress = 0; render(); start(); });
    slider.addEventListener("input", () => { pause(); progress = Number(slider.value); render(); });
    durationInput.addEventListener("change", () => {
      duration = validDuration(durationInput.value, duration);
      durationInput.value = String(duration);
    });
    document.addEventListener("visibilitychange", () => { if (document.hidden) pause(); });
    // No autoplay, loops, or ambient animation; reduced-motion users can scrub instead.
    demo.querySelector(".demo-controls").hidden = false;
    render();
  }
}

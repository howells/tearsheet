// Motion for tearsheet.danielhowells.com. Styles and resting states live in app.css.
const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
const loadedAt = performance.now();

// The same curve as --ease-in-out-quart, so the readout counts in step with the frame.
function cubicBezier(x1, y1, x2, y2) {
  const at = (a, b, t) => ((1 - 3 * b + 3 * a) * t + (3 * b - 6 * a)) * t * t + 3 * a * t;
  const slope = (a, b, t) => 3 * (1 - 3 * b + 3 * a) * t * t + 2 * (3 * b - 6 * a) * t + 3 * a;
  return (x) => {
    let t = x;
    for (let i = 0; i < 8; i++) {
      const d = slope(x1, x2, t);
      if (Math.abs(d) < 1e-6) break;
      t -= (at(x1, x2, t) - x) / d;
    }
    return at(y1, y2, Math.min(1, Math.max(0, t)));
  };
}
const easeInOutQuart = cubicBezier(0.77, 0, 0.175, 1);

// Film -----------------------------------------------------------------------

const film = document.querySelector("[data-film]");
const figure = film.querySelector("figure");
const video = film.querySelector("[data-video]");
const toggle = film.querySelector("[data-toggle]");
const toggleIcon = film.querySelector("[data-toggle-icon]");
const readout = film.querySelector("[data-readout]");
const marks = Object.fromEntries([...film.querySelectorAll(".mark")].map((m) => [m.dataset.corner, m]));

let pausedByVisitor = still;
let selected = false;
let inView = false;

function renderToggle() {
  const playing = !video.paused;
  toggle.setAttribute("aria-label", playing ? "Pause film" : "Play film");
  toggleIcon.setAttribute("href", playing ? "#i-pause" : "#i-play");
}

function play() {
  if (selected && inView && !pausedByVisitor) video.play().catch(() => {});
}

toggle.addEventListener("click", () => {
  if (video.paused) { pausedByVisitor = false; video.play(); }
  else { pausedByVisitor = true; video.pause(); }
});
video.addEventListener("play", renderToggle);
video.addEventListener("pause", renderToggle);

// Drag the film out like a region selection, from its top left corner.
function select() {
  if (selected) return;
  selected = true;
  film.removeAttribute("data-waiting");

  if (still) {
    for (const el of [figure, readout, ...Object.values(marks)]) {
      el.animate([{ opacity: 0 }, { opacity: 1 }], { duration: 400, easing: "ease" });
    }
    return;
  }

  const { width: w, height: h } = figure.getBoundingClientRect();
  const timing = { duration: 1300, easing: "cubic-bezier(0.77, 0, 0.175, 1)" };
  const r = getComputedStyle(figure).borderRadius;
  figure.animate(
    [
      { clipPath: `inset(0 100% 100% 0 round ${r})`, opacity: 0, offset: 0 },
      { opacity: 1, offset: 0.1 },
      { clipPath: `inset(0 0 0 0 round ${r})`, opacity: 1, offset: 1 },
    ],
    timing,
  );
  marks.tr.animate([{ transform: `translateX(${-w}px)` }, { transform: "none" }], timing);
  marks.bl.animate([{ transform: `translateY(${-h}px)` }, { transform: "none" }], timing);
  marks.br.animate([{ transform: `translate(${-w}px, ${-h}px)` }, { transform: "none" }], timing);
  const follow = readout.animate(
    [
      { transform: `translate(${-w}px, ${-h}px)`, opacity: 0, offset: 0 },
      { opacity: 1, offset: 0.1 },
      { transform: "none", opacity: 1, offset: 1 },
    ],
    timing,
  );

  // The size readout counts up as the region grows, in the film's own pixels,
  // read from the animation's own clock so it stays in step if slowed or paused.
  const show = (p) => { readout.textContent = `${Math.round(1920 * p)} × ${Math.round(1080 * p)}`; };
  (function count() {
    if (follow.playState === "finished") return;
    show(easeInOutQuart((follow.currentTime ?? 0) / timing.duration));
    requestAnimationFrame(count);
  })();

  follow.finished.then(() => { show(1); play(); });
}

new IntersectionObserver(
  ([entry]) => {
    inView = entry.intersectionRatio >= 0.4;
    if (inView && !selected) {
      // Let the hero finish arriving before the selection starts.
      setTimeout(select, Math.max(0, 1100 - (performance.now() - loadedAt)));
    } else if (inView) {
      play();
    } else {
      video.pause();
    }
  },
  { threshold: [0, 0.4] },
).observe(film);

// Chapters --------------------------------------------------------------------

const list = document.querySelector(".chapters");
const chapters = [...list.querySelectorAll("[data-chapter]")].map((button) => ({
  button,
  item: button.closest("li"),
  fill: button.querySelector("[data-fill]"),
  start: Number(button.dataset.start),
  end: Number(button.dataset.end),
}));
let current = null;

function sync() {
  const t = video.currentTime;
  let active = null;
  for (const c of chapters) {
    const p = Math.min(1, Math.max(0, (t - c.start) / (c.end - c.start)));
    c.fill.style.scale = `${p} 1`;
    if (t >= c.start && t < c.end) active = c;
  }
  if (active !== current) {
    current?.item.removeAttribute("data-active");
    current?.item.removeAttribute("data-pressing");
    current?.button.removeAttribute("aria-current");
    current = active;
    // The closing card shows every shortcut, so all chapters light up together.
    list.toggleAttribute("data-live", Boolean(active));
    if (active) {
      active.item.setAttribute("data-active", "");
      active.button.setAttribute("aria-current", "true");
      if (!still) {
        active.item.removeAttribute("data-pressing");
        void active.item.offsetWidth;
        active.item.setAttribute("data-pressing", "");
      }
    }
  }
}

(function frame() {
  if (!video.paused) sync();
  requestAnimationFrame(frame);
})();
video.addEventListener("seeked", sync);

for (const c of chapters) {
  c.button.addEventListener("click", () => {
    video.currentTime = c.start + 0.05;
    pausedByVisitor = false;
    if (!selected) select();
    video.play().catch(() => {});
    if (!inView) film.scrollIntoView({ behavior: still ? "auto" : "smooth", block: "center" });
  });
}

// Reveal on scroll, once ------------------------------------------------------

const reveal = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.setAttribute("data-seen", "");
      reveal.unobserve(entry.target);
      if (entry.target.matches(".proof")) proofSeenAt = performance.now();
    }
  },
  { rootMargin: "0px 0px -12% 0px" },
);
document.querySelectorAll("[data-reveal]").forEach((el) => reveal.observe(el));

// Setup vignettes ---------------------------------------------------------------

const stages = [...document.querySelectorAll("[data-stage]")];

function playStage(stage) {
  stage.removeAttribute("data-play");
  void stage.offsetWidth;
  stage.setAttribute("data-play", "");
}

// Each step acts itself out once it is in view: after the panel has unrolled,
// and in turn when several arrive together, as they do side by side.
let proofSeenAt = null;
let nextSlot = 0;
const stageWatch = new IntersectionObserver(
  (entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      stageWatch.unobserve(entry.target);
      const now = performance.now();
      const at = still ? now : Math.max(now, (proofSeenAt ?? now) + 700, nextSlot);
      nextSlot = at + 900;
      setTimeout(() => playStage(entry.target), at - now);
    }
  },
  { threshold: 0.6 },
);
stages.forEach((stage) => stageWatch.observe(stage));

// Hovering a finished vignette plays it again.
const finePointer = matchMedia("(hover: hover) and (pointer: fine)");
for (const stage of stages) {
  stage.closest("li").addEventListener("pointerenter", () => {
    if (still || !finePointer.matches || !stage.hasAttribute("data-play")) return;
    const running = stage.getAnimations({ subtree: true }).some((a) => a.playState === "running");
    if (!running) playStage(stage);
  });
}

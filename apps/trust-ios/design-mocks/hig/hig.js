/* Trust Circle — HIG shell interactions */

const CIRCLE = [
  {
    id: "alex",
    name: "Alex",
    initial: "A",
    tone: "tone-a",
    perm: "sealed",
    presence: "away",
    label: "Away",
  },
  {
    id: "maya",
    name: "Maya",
    initial: "M",
    tone: "tone-b",
    perm: "sealed",
    presence: "overdue",
    label: "Overdue",
  },
  {
    id: "eli",
    name: "Eli",
    initial: "E",
    tone: "tone-c",
    perm: "live",
    presence: "home",
    label: "Home",
    place: { strong: "Capitol Hill", rest: "Seattle" },
    pin: { left: 48, top: 52 },
    map: "a",
  },
  {
    id: "sam",
    name: "Sam",
    initial: "S",
    tone: "tone-d",
    perm: "sealed",
    presence: "home",
    label: "Home",
  },
  {
    id: "rae",
    name: "Rae",
    initial: "R",
    tone: "tone-e",
    perm: "live",
    presence: "away",
    label: "Away",
    place: { strong: "Fremont Bridge", rest: "near canal" },
    pin: { left: 62, top: 44 },
    map: "b",
  },
  {
    id: "noa",
    name: "Noa",
    initial: "N",
    tone: "tone-f",
    perm: "sealed",
    presence: "away",
    label: "Away",
  },
  {
    id: "jules",
    name: "Jules",
    initial: "J",
    tone: "tone-a",
    perm: "live",
    presence: "away",
    label: "Away",
    place: { strong: "Pioneer Square", rest: "1st Ave" },
    pin: { left: 54, top: 56 },
    map: "c",
  },
];

const SHARING = [
  {
    id: "alex",
    name: "Alex",
    handle: "@alex",
    initial: "A",
    tone: "tone-a",
    mode: "until",
    duration: null,
    home: true,
  },
  {
    id: "maya",
    name: "Maya",
    handle: "@maya",
    initial: "M",
    tone: "tone-b",
    mode: "always",
    duration: null,
    home: true,
  },
  {
    id: "eli",
    name: "Eli",
    handle: "@eli",
    initial: "E",
    tone: "tone-c",
    mode: "while",
    duration: "1 hour",
    home: false,
  },
  {
    id: "sam",
    name: "Sam",
    handle: "@sam",
    initial: "S",
    tone: "tone-d",
    mode: "until",
    duration: null,
    home: true,
  },
  {
    id: "rio",
    name: "Rio",
    handle: "@rio",
    initial: "R",
    tone: "tone-e",
    mode: "until",
    duration: null,
    home: false,
  },
];

const MODE_LABELS = { until: "Until", always: "Always", while: "While" };

const MAPS = {
  a: `
    <svg viewBox="0 0 390 420" preserveAspectRatio="xMidYMid slice">
      <rect width="390" height="420" fill="#ececea"/>
      <rect x="0" y="220" width="390" height="120" fill="#d8d8d4" opacity="0.85"/>
      <rect x="48" y="70" width="96" height="72" fill="#e2e4dc"/>
      <rect x="210" y="110" width="120" height="88" fill="#e2e4dc" opacity="0.9"/>
      <g stroke="#2a2a2a" stroke-width="1.1" fill="none" opacity="0.5">
        <path d="M0 100 H390"/><path d="M0 180 H390"/><path d="M0 280 H390"/>
        <path d="M80 0 V420"/><path d="M170 0 V420"/><path d="M260 0 V420"/><path d="M340 0 V420"/>
      </g>
      <g stroke="#2a2a2a" stroke-width="2" fill="none" opacity="0.65">
        <path d="M-10 150 C90 130 130 210 210 190 S330 130 400 160"/>
      </g>
    </svg>`,
  b: `
    <svg viewBox="0 0 390 420" preserveAspectRatio="xMidYMid slice">
      <rect width="390" height="420" fill="#ececea"/>
      <path d="M0 250 Q100 210 180 240 T390 230 L390 360 L0 360 Z" fill="#d8d8d4"/>
      <rect x="30" y="50" width="80" height="60" fill="#e2e4dc"/>
      <rect x="240" y="130" width="100" height="70" fill="#e2e4dc"/>
      <g stroke="#2a2a2a" stroke-width="1.1" fill="none" opacity="0.48">
        <path d="M0 80 H390"/><path d="M0 160 H390"/><path d="M0 260 H390"/>
        <path d="M60 0 V420"/><path d="M150 0 V420"/><path d="M240 0 V420"/><path d="M320 0 V420"/>
      </g>
      <g stroke="#2a2a2a" stroke-width="2.1" fill="none" opacity="0.7">
        <path d="M-20 300 C70 280 150 340 230 315 S350 260 410 290"/>
      </g>
    </svg>`,
  c: `
    <svg viewBox="0 0 390 420" preserveAspectRatio="xMidYMid slice">
      <rect width="390" height="420" fill="#ececea"/>
      <rect x="0" y="200" width="390" height="100" fill="#d8d8d4" opacity="0.9"/>
      <rect x="180" y="60" width="130" height="90" fill="#e2e4dc"/>
      <rect x="40" y="300" width="70" height="55" fill="#e2e4dc"/>
      <g stroke="#2a2a2a" stroke-width="1.15" fill="none" opacity="0.5">
        <path d="M0 80 H390"/><path d="M0 160 H390"/><path d="M0 260 H390"/>
        <path d="M90 0 V420"/><path d="M190 0 V420"/><path d="M280 0 V420"/><path d="M350 0 V420"/>
      </g>
      <g stroke="#2a2a2a" stroke-width="2" fill="none" opacity="0.68">
        <path d="M-10 130 C70 110 140 180 220 160 S340 90 410 120"/>
      </g>
    </svg>`,
};

const phone = document.getElementById("phone");
const wordmark = document.getElementById("wordmark");
const circleList = document.getElementById("circleList");
const sharingList = document.getElementById("sharingList");
const surfaces = [...document.querySelectorAll(".shell > .surface")];
const tabs = [...document.querySelectorAll(".tab-bar .tab")];
const phoneUrlEl = document.getElementById("phoneUrl");

const lookOverlay = document.getElementById("lookOverlay");
const lookTitle = document.getElementById("lookTitle");
const lookDesc = document.getElementById("lookDesc");
const mapOverlay = document.getElementById("mapOverlay");
const mapCanvas = document.getElementById("mapCanvas");
const mapTitle = document.getElementById("mapTitle");
const mapPlace = document.getElementById("mapPlace");
const mapEyebrow = document.getElementById("mapEyebrow");
const mapPin = document.getElementById("mapPin");
const mapPinAvatar = document.getElementById("mapPinAvatar");
const durationOverlay = document.getElementById("durationOverlay");
const popoverEyebrow = document.getElementById("popoverEyebrow");
const durationChips = document.getElementById("durationChips");

let pendingLookId = null;
let pendingWhileId = null;
let pendingDuration = "1 hour";

const TAB_MARKS = {
  circle: "Trust",
  sharing: "Trust",
  invite: "Trust",
  you: "You",
};

function lanHost() {
  const host = location.hostname;
  if (host && host !== "127.0.0.1" && host !== "localhost") return host;
  return "10.0.0.116";
}

function setTab(tab) {
  if (!TAB_MARKS[tab]) return;
  hideAllOverlays();
  phone.dataset.tab = tab;

  surfaces.forEach((s) => {
    const on = s.dataset.surface === tab;
    s.classList.toggle("is-active", on);
    if (on) s.removeAttribute("hidden");
    else s.setAttribute("hidden", "");
  });

  tabs.forEach((t) => {
    t.setAttribute("aria-selected", t.dataset.tab === tab ? "true" : "false");
  });

  if (wordmark) wordmark.textContent = TAB_MARKS[tab];
}

function hideAllOverlays() {
  lookOverlay.hidden = true;
  mapOverlay.hidden = true;
  durationOverlay.hidden = true;
  pendingLookId = null;
  pendingWhileId = null;
}

function circleSubtitle(p) {
  if (p.perm === "live" && p.place) {
    return `${p.place.strong} · ${p.place.rest}`;
  }
  return p.label;
}

function circleSubClass(p) {
  if (p.perm === "live") return "row-sub is-live";
  if (p.presence === "overdue") return "row-sub is-overdue";
  if (p.presence === "home") return "row-sub is-home";
  return "row-sub is-away";
}

function renderCircle() {
  circleList.innerHTML = CIRCLE.map((p, i) => {
    const action =
      p.perm === "live"
        ? `<button type="button" class="btn-view" data-view="${p.id}">View</button>`
        : `<button type="button" class="btn-look" data-look="${p.id}">Look</button>`;
    return `
      <article class="person-row" data-id="${p.id}" role="listitem" style="animation-delay:${i * 30}ms">
        <div class="avatar ${p.tone}" aria-hidden="true">${p.initial}</div>
        <div class="row-copy">
          <p class="row-name">${p.name}</p>
          <p class="${circleSubClass(p)}"><span class="presence-dot" aria-hidden="true"></span>${circleSubtitle(p)}</p>
        </div>
        <div class="row-actions">${action}</div>
      </article>`;
  }).join("");
}

function renderSharing() {
  sharingList.innerHTML = SHARING.map((p) => {
    const whileOn = p.mode === "while";
    return `
      <article class="share-row" data-id="${p.id}" role="listitem">
        <div class="avatar ${p.tone}" aria-hidden="true">${p.initial}</div>
        <div class="share-main">
          <div>
            <p class="share-name">${p.name}</p>
            <p class="share-handle">${p.handle}</p>
          </div>
          <div class="mode-seg" role="radiogroup" aria-label="Share mode for ${p.name}">
            ${["until", "always", "while"]
              .map((mode) => {
                const on = p.mode === mode;
                const exception = mode !== "until";
                return `<button type="button" class="seg${on ? " is-on" : ""}${exception ? " is-exception" : ""}" data-mode="${mode}" role="radio" aria-checked="${on}">${MODE_LABELS[mode]}</button>`;
              })
              .join("")}
          </div>
          <div class="row-meta">
            <div class="presence">
              <button type="button" class="toggle${p.home ? "" : " off"}" role="switch" aria-checked="${p.home}" aria-label="Home presence for ${p.name}" data-toggle-home></button>
              <span class="presence-label"><strong>Home</strong> presence</span>
            </div>
            <button type="button" class="duration-pill" data-edit-duration ${whileOn ? "" : "hidden"}>
              ${p.duration || "1 hour"}
            </button>
          </div>
        </div>
      </article>`;
  }).join("");
}

function personById(list, id) {
  return list.find((p) => p.id === id);
}

function openLookConfirm(person) {
  pendingLookId = person.id;
  lookTitle.textContent = `Look at ${person.name}?`;
  lookDesc.textContent = `${person.name} will be notified. You’ll see live location plus the last two hours. This Look is logged and cannot be erased.`;
  lookOverlay.hidden = false;
}

function confirmLook() {
  const person = personById(CIRCLE, pendingLookId);
  if (!person || person.perm === "live") {
    hideAllOverlays();
    return;
  }

  person.perm = "live";
  person.presence = "away";
  person.label = "Away";
  person.place = { strong: "Seen just now", rest: "area on map" };
  person.pin = {
    left: 40 + Math.random() * 28,
    top: 40 + Math.random() * 18,
  };
  person.map = ["a", "b", "c"][Math.floor(Math.random() * 3)];

  hideAllOverlays();
  renderCircle();

  const row = circleList.querySelector(`[data-id="${person.id}"]`);
  if (row) {
    row.classList.add("flash");
    row.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  // Brief beat, then open the map sheet — same as confirming Look → reveal
  setTimeout(() => openMap(person), 280);
}

function openMap(person) {
  if (!person || person.perm !== "live") return;
  mapTitle.textContent = person.name;
  mapPlace.textContent = person.place
    ? `${person.place.strong} · ${person.place.rest}`
    : person.label;
  mapEyebrow.textContent = "Live";
  mapPinAvatar.textContent = person.initial;

  // Keep pin element; replace only map svg
  const existingSvg = mapCanvas.querySelector("svg");
  if (existingSvg) existingSvg.remove();
  mapCanvas.insertAdjacentHTML("afterbegin", MAPS[person.map] || MAPS.a);

  mapPin.style.left = `${person.pin?.left ?? 52}%`;
  mapPin.style.top = `${person.pin?.top ?? 46}%`;
  // retrigger pin animation
  mapPin.style.animation = "none";
  void mapPin.offsetWidth;
  mapPin.style.animation = "";

  mapOverlay.hidden = false;
}

function openDuration(person) {
  pendingWhileId = person.id;
  pendingDuration = person.duration || "1 hour";
  popoverEyebrow.textContent = `Exception · ${person.name}`;
  durationChips.querySelectorAll(".chip").forEach((chip) => {
    const on = chip.dataset.duration === pendingDuration;
    chip.classList.toggle("selected", on);
    chip.setAttribute("aria-checked", on ? "true" : "false");
  });
  durationOverlay.hidden = false;
}

function applyMode(person, mode) {
  if (mode === "while") {
    openDuration(person);
    return;
  }
  person.mode = mode;
  person.duration = null;
  renderSharing();
}

/* —— Events —— */

tabs.forEach((t) => {
  t.addEventListener("click", () => setTab(t.dataset.tab));
});

circleList.addEventListener("click", (e) => {
  const lookBtn = e.target.closest("[data-look]");
  if (lookBtn) {
    const person = personById(CIRCLE, lookBtn.dataset.look);
    if (person) openLookConfirm(person);
    return;
  }
  const viewBtn = e.target.closest("[data-view]");
  if (viewBtn) {
    const person = personById(CIRCLE, viewBtn.dataset.view);
    if (person) openMap(person);
  }
});

document.getElementById("lookConfirm").addEventListener("click", confirmLook);
document.getElementById("lookCancel").addEventListener("click", hideAllOverlays);
document.getElementById("lookScrim").addEventListener("click", hideAllOverlays);

document.getElementById("mapDone").addEventListener("click", () => {
  mapOverlay.hidden = true;
});
document.getElementById("mapScrim").addEventListener("click", () => {
  mapOverlay.hidden = true;
});

sharingList.addEventListener("click", (e) => {
  const row = e.target.closest(".share-row");
  if (!row) return;
  const person = personById(SHARING, row.dataset.id);
  if (!person) return;

  const seg = e.target.closest(".seg");
  if (seg) {
    const mode = seg.dataset.mode;
    if (mode === person.mode && mode === "while") {
      openDuration(person);
      return;
    }
    if (mode === person.mode) return;
    applyMode(person, mode);
    return;
  }

  const homeToggle = e.target.closest("[data-toggle-home]");
  if (homeToggle) {
    person.home = !person.home;
    homeToggle.classList.toggle("off", !person.home);
    homeToggle.setAttribute("aria-checked", person.home ? "true" : "false");
    return;
  }

  if (e.target.closest("[data-edit-duration]")) {
    openDuration(person);
  }
});

document.getElementById("bulkUntil").addEventListener("click", () => {
  SHARING.forEach((p) => {
    p.mode = "until";
    p.duration = null;
  });
  renderSharing();
});

durationChips.addEventListener("click", (e) => {
  const chip = e.target.closest(".chip");
  if (!chip) return;
  pendingDuration = chip.dataset.duration;
  durationChips.querySelectorAll(".chip").forEach((c) => {
    const on = c === chip;
    c.classList.toggle("selected", on);
    c.setAttribute("aria-checked", on ? "true" : "false");
  });
});

document.getElementById("durationStart").addEventListener("click", () => {
  const person = personById(SHARING, pendingWhileId);
  if (!person) return;
  person.mode = "while";
  person.duration = pendingDuration;
  durationOverlay.hidden = true;
  pendingWhileId = null;
  renderSharing();
});

document.getElementById("durationCancel").addEventListener("click", () => {
  durationOverlay.hidden = true;
  pendingWhileId = null;
});
document.getElementById("durationScrim").addEventListener("click", () => {
  durationOverlay.hidden = true;
  pendingWhileId = null;
});

document.querySelector(".toggle")?.addEventListener("click", (e) => {
  const el = e.currentTarget;
  const on = el.getAttribute("aria-checked") === "true";
  el.setAttribute("aria-checked", on ? "false" : "true");
  el.classList.toggle("off", on);
});

if (phoneUrlEl) {
  const url = `http://${lanHost()}:8766/hig/`;
  phoneUrlEl.innerHTML = `Phone · <a href="${url}">${url}</a>`;
}

renderCircle();
renderSharing();
setTab("circle");

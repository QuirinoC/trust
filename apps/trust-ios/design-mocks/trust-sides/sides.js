/* Trust Circle — People I trust (outbound sharing only) */

const OUTBOUND = [
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

const MODE_LABELS = {
  until: "Until",
  always: "Always",
  while: "While",
};

const phone = document.getElementById("phone");
const wordmark = document.getElementById("wordmark");
const outboundList = document.getElementById("outboundList");
const popover = document.getElementById("durationPopover");
const popoverScrim = document.getElementById("popoverScrim");
const popoverEyebrow = document.getElementById("popoverEyebrow");
const durationChips = document.getElementById("durationChips");
const surfaces = [...document.querySelectorAll(".shell > .surface")];
const tabs = [...document.querySelectorAll(".tab-bar .tab")];
const phoneUrlEl = document.getElementById("phoneUrl");

let pendingWhileId = null;
let pendingDuration = "1 hour";

const TAB_MARKS = {
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
  // Footer Home → inbound presence (contact-snap). This page is outbound only.
  if (tab === "home") {
    window.location.href = "../contact-snap/";
    return;
  }

  if (tab !== "invite" && tab !== "you") return;

  phone.dataset.tab = tab;
  hidePopover();

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

function showSharing() {
  phone.dataset.tab = "sharing";
  hidePopover();
  surfaces.forEach((s) => {
    const on = s.dataset.surface === "sharing";
    s.classList.toggle("is-active", on);
    if (on) s.removeAttribute("hidden");
    else s.setAttribute("hidden", "");
  });
  tabs.forEach((t) => t.setAttribute("aria-selected", "false"));
  if (wordmark) wordmark.textContent = "Trust";
}

function renderOutbound() {
  outboundList.innerHTML = OUTBOUND.map((p) => {
    const whileOn = p.mode === "while";
    return `
      <article class="share-row" data-id="${p.id}" role="listitem">
        <div class="avatar ${p.tone}" aria-hidden="true">${p.initial}</div>
        <div class="row-main">
          <div>
            <p class="row-name">${p.name}</p>
            <p class="row-handle">${p.handle}</p>
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
              <button type="button" class="toggle${p.home ? "" : " off"}" role="switch" aria-checked="${p.home}" aria-label="Home / Away for ${p.name}" data-toggle-home></button>
              <span class="presence-label"><strong>Home</strong> presence</span>
            </div>
            <button type="button" class="duration-pill" data-edit-duration ${whileOn ? "" : "hidden"}>
              ${p.duration || "1 hour"}
            </button>
          </div>
        </div>
      </article>
    `;
  }).join("");
}

function personById(id) {
  return OUTBOUND.find((p) => p.id === id);
}

function openPopover(person) {
  pendingWhileId = person.id;
  pendingDuration = person.duration || "1 hour";
  popoverEyebrow.textContent = `Exception · ${person.name}`;
  durationChips.querySelectorAll(".chip").forEach((chip) => {
    const on = chip.dataset.duration === pendingDuration;
    chip.classList.toggle("selected", on);
    chip.setAttribute("aria-checked", on ? "true" : "false");
  });
  popover.hidden = false;
  popoverScrim.hidden = false;
}

function hidePopover() {
  pendingWhileId = null;
  popover.hidden = true;
  popoverScrim.hidden = true;
}

function applyMode(person, mode) {
  if (mode === "while") {
    openPopover(person);
    return;
  }
  person.mode = mode;
  person.duration = null;
  renderOutbound();
}

outboundList.addEventListener("click", (e) => {
  const row = e.target.closest(".share-row");
  if (!row) return;
  const person = personById(row.dataset.id);
  if (!person) return;

  const seg = e.target.closest(".seg");
  if (seg) {
    const mode = seg.dataset.mode;
    if (mode === person.mode && mode === "while") {
      openPopover(person);
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

  const durationBtn = e.target.closest("[data-edit-duration]");
  if (durationBtn) {
    openPopover(person);
  }
});

tabs.forEach((t) => {
  t.addEventListener("click", () => setTab(t.dataset.tab));
});

document.getElementById("bulkUntil").addEventListener("click", () => {
  OUTBOUND.forEach((p) => {
    p.mode = "until";
    p.duration = null;
  });
  renderOutbound();
  outboundList.querySelectorAll(".share-row").forEach((row, i) => {
    row.classList.add("flash");
    setTimeout(() => row.classList.remove("flash"), 600 + i * 40);
  });
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
  const person = personById(pendingWhileId);
  if (!person) return;
  person.mode = "while";
  person.duration = pendingDuration;
  hidePopover();
  renderOutbound();
});

document.getElementById("durationCancel").addEventListener("click", hidePopover);
popoverScrim.addEventListener("click", hidePopover);

if (phoneUrlEl) {
  const url = `http://${lanHost()}:8766/trust-sides/`;
  phoneUrlEl.innerHTML = `Phone · <a href="${url}">${url}</a>`;
}

renderOutbound();
showSharing();

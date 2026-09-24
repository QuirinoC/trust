(() => {
  const CONTACTS = [
    {
      name: "Alex",
      perm: "sealed",
      presence: "away",
      label: "Away",
      chip: "Away",
    },
    {
      name: "Maya",
      perm: "sealed",
      presence: "overdue",
      label: "Overdue",
      chip: "Overdue",
    },
    {
      name: "Eli",
      perm: "live",
      presence: "home",
      label: "Home",
      chip: "Home",
      place: { strong: "Capitol Hill", rest: "Seattle" },
      pin: { left: 48, top: 52 },
      map: "a",
    },
    {
      name: "Sam",
      perm: "sealed",
      presence: "home",
      label: "Home",
      chip: "Home",
    },
    {
      name: "Rae",
      perm: "live",
      presence: "away",
      label: "Away",
      chip: "Away",
      place: { strong: "Fremont Bridge", rest: "near canal" },
      pin: { left: 62, top: 44 },
      map: "b",
    },
    {
      name: "Noa",
      perm: "sealed",
      presence: "away",
      label: "Away",
      chip: "Away",
    },
    {
      name: "Jules",
      perm: "live",
      presence: "away",
      label: "Away",
      chip: "Away",
      place: { strong: "Pioneer Square", rest: "1st Ave" },
      pin: { left: 54, top: 56 },
      map: "c",
    },
    {
      name: "Kai",
      perm: "sealed",
      presence: "home",
      label: "Home",
      chip: "Home",
    },
  ];

  const MAPS = {
    a: `
      <svg viewBox="0 0 390 520" preserveAspectRatio="xMidYMid slice">
        <rect width="390" height="520" fill="#ececea"/>
        <rect x="0" y="260" width="390" height="140" fill="#d8d8d4" opacity="0.85"/>
        <rect x="48" y="90" width="96" height="72" fill="#e2e4dc"/>
        <rect x="210" y="140" width="120" height="88" fill="#e2e4dc" opacity="0.9"/>
        <g stroke="#2a2a2a" stroke-width="1.1" fill="none" opacity="0.5">
          <path d="M0 120 H390"/><path d="M0 220 H390"/><path d="M0 340 H390"/>
          <path d="M80 0 V520"/><path d="M170 0 V520"/><path d="M260 0 V520"/><path d="M340 0 V520"/>
        </g>
        <g stroke="#2a2a2a" stroke-width="2" fill="none" opacity="0.65">
          <path d="M-10 180 C90 160 130 240 210 220 S330 160 400 190"/>
        </g>
      </svg>`,
    b: `
      <svg viewBox="0 0 390 520" preserveAspectRatio="xMidYMid slice">
        <rect width="390" height="520" fill="#ececea"/>
        <path d="M0 300 Q100 260 180 290 T390 280 L390 420 L0 420 Z" fill="#d8d8d4"/>
        <rect x="30" y="60" width="80" height="60" fill="#e2e4dc"/>
        <rect x="240" y="160" width="100" height="70" fill="#e2e4dc"/>
        <g stroke="#2a2a2a" stroke-width="1.1" fill="none" opacity="0.48">
          <path d="M0 100 H390"/><path d="M0 200 H390"/><path d="M0 320 H390"/>
          <path d="M60 0 V520"/><path d="M150 0 V520"/><path d="M240 0 V520"/><path d="M320 0 V520"/>
        </g>
        <g stroke="#2a2a2a" stroke-width="2.1" fill="none" opacity="0.7">
          <path d="M-20 360 C70 340 150 400 230 375 S350 320 410 350"/>
        </g>
      </svg>`,
    c: `
      <svg viewBox="0 0 390 520" preserveAspectRatio="xMidYMid slice">
        <rect width="390" height="520" fill="#ececea"/>
        <rect x="0" y="240" width="390" height="120" fill="#d8d8d4" opacity="0.9"/>
        <rect x="180" y="80" width="130" height="90" fill="#e2e4dc"/>
        <rect x="40" y="360" width="70" height="55" fill="#e2e4dc"/>
        <g stroke="#2a2a2a" stroke-width="1.15" fill="none" opacity="0.5">
          <path d="M0 100 H390"/><path d="M0 200 H390"/><path d="M0 320 H390"/>
          <path d="M90 0 V520"/><path d="M190 0 V520"/><path d="M280 0 V520"/><path d="M350 0 V520"/>
        </g>
        <g stroke="#2a2a2a" stroke-width="2" fill="none" opacity="0.68">
          <path d="M-10 160 C70 140 140 210 220 190 S340 120 410 150"/>
        </g>
      </svg>`,
  };

  const phone = document.getElementById("phone");
  const strip = document.getElementById("contactStrip");
  const detail = document.getElementById("detailPanel");
  const bgLayer = document.getElementById("bgLayer");
  const mapPlane = document.getElementById("mapPlane");
  const pin = document.getElementById("pin");
  const pinAvatar = document.getElementById("pinAvatar");
  const wordmark = document.getElementById("wordmark");
  const surfaces = [...document.querySelectorAll(".surface")];
  const tabs = [...document.querySelectorAll(".tab-bar .tab")];

  let active = 0;
  let currentTab = "home";
  let flashTimer = null;

  const TAB_MARKS = {
    home: "Trust",
    invite: "Trust",
    you: "You",
  };

  function setTab(tab) {
    if (!TAB_MARKS[tab]) return;
    currentTab = tab;
    phone.dataset.tab = tab;

    surfaces.forEach((s) => {
      const on = s.dataset.surface === tab;
      s.classList.toggle("is-active", on);
      if (on) s.removeAttribute("hidden");
      else s.setAttribute("hidden", "");
    });

    tabs.forEach((t) => {
      const on = t.dataset.tab === tab;
      t.setAttribute("aria-selected", on ? "true" : "false");
    });

    if (wordmark) wordmark.textContent = TAB_MARKS[tab];

    if (tab === "home") {
      requestAnimationFrame(() => {
        strip.focus({ preventScroll: true });
        scrollCardIntoView(active);
      });
    }
  }

  tabs.forEach((t) => {
    t.addEventListener("click", () => setTab(t.dataset.tab));
  });

  document.querySelector(".toggle")?.addEventListener("click", (e) => {
    const el = e.currentTarget;
    const on = el.getAttribute("aria-checked") === "true";
    el.setAttribute("aria-checked", on ? "false" : "true");
    el.classList.toggle("off", on);
  });

  function cardHTML(c, i) {
    return `
      <button
        type="button"
        class="person-card"
        role="option"
        data-i="${i}"
        aria-selected="${i === 0 ? "true" : "false"}"
        aria-label="${c.name}, ${c.chip}"
      >
        <span class="card-name">${c.name}</span>
        <span class="card-status ${c.presence}"><span class="dot" aria-hidden="true"></span>${c.chip}</span>
      </button>`;
  }

  function detailHTML(c) {
    if (c.perm === "live") {
      return `
        <div class="detail-body">
          <h2 class="who">${c.name}</h2>
          <p class="presence ${c.presence}"><span class="dot" aria-hidden="true"></span> ${c.label}</p>
          <p class="place"><strong>${c.place.strong}</strong> · ${c.place.rest}</p>
          <div class="actions">
            <button type="button" class="btn-ghost" data-map>Open map</button>
          </div>
        </div>`;
    }
    return `
      <div class="detail-body">
        <h2 class="who">${c.name}</h2>
        <p class="presence ${c.presence}"><span class="dot" aria-hidden="true"></span> ${c.label}</p>
        <div class="actions">
          <button type="button" class="btn-look" data-look="${c.name}">Look</button>
        </div>
      </div>`;
  }

  strip.innerHTML = CONTACTS.map(cardHTML).join("");
  const cards = [...strip.querySelectorAll(".person-card")];

  function hapticTick() {
    try {
      if (navigator.vibrate) navigator.vibrate(8);
    } catch (_) {}
  }

  function applyBackground(c) {
    const live = c.perm === "live";
    bgLayer.dataset.mode = live ? "live" : "sealed";
    if (live) {
      mapPlane.innerHTML = MAPS[c.map] || MAPS.a;
      pinAvatar.textContent = c.name[0] || "?";
      pin.style.left = `${c.pin?.left ?? 50}%`;
      pin.style.top = `${c.pin?.top ?? 48}%`;
      pin.style.opacity = "1";
    } else {
      pin.style.opacity = "0";
    }
  }

  function scrollCardIntoView(i) {
    const card = cards[i];
    if (!card) return;
    const left = card.offsetLeft - 18;
    const right = left + card.offsetWidth;
    const viewLeft = strip.scrollLeft;
    const viewRight = viewLeft + strip.clientWidth;
    if (left < viewLeft) {
      strip.scrollTo({ left: Math.max(0, left), behavior: "smooth" });
    } else if (right > viewRight - 18) {
      strip.scrollTo({ left: right - strip.clientWidth + 18, behavior: "smooth" });
    }
  }

  function refreshCardChip(i) {
    const c = CONTACTS[i];
    const card = cards[i];
    if (!card || !c) return;
    card.setAttribute("aria-label", `${c.name}, ${c.chip}`);
    const status = card.querySelector(".card-status");
    if (status) {
      status.className = `card-status ${c.presence}`;
      status.innerHTML = `<span class="dot" aria-hidden="true"></span>${c.chip}`;
    }
  }

  function setActive(i, { haptic = false, animate = true } = {}) {
    if (i < 0 || i >= CONTACTS.length) return;
    const changed = i !== active;
    active = i;
    const c = CONTACTS[i];

    cards.forEach((card, j) => {
      card.setAttribute("aria-selected", j === i ? "true" : "false");
    });

    phone.dataset.active = String(i);
    phone.classList.toggle("is-live", c.perm === "live");
    applyBackground(c);

    if (animate || changed) {
      detail.innerHTML = detailHTML(c);
    } else {
      detail.innerHTML = detailHTML(c);
    }

    scrollCardIntoView(i);

    if (changed) {
      if (haptic) hapticTick();
      phone.classList.add("snap-flash");
      clearTimeout(flashTimer);
      flashTimer = setTimeout(() => phone.classList.remove("snap-flash"), 220);
    }
  }

  function goTo(i) {
    setActive(i, { haptic: true });
  }

  strip.addEventListener("click", (e) => {
    const card = e.target.closest(".person-card");
    if (!card) return;
    const i = Number(card.dataset.i);
    if (Number.isNaN(i)) return;
    goTo(i);
  });

  strip.addEventListener("keydown", (e) => {
    if (currentTab !== "home") return;
    if (e.key === "ArrowRight" || e.key === "j" || e.key === "PageDown") {
      e.preventDefault();
      goTo(Math.min(CONTACTS.length - 1, active + 1));
    } else if (e.key === "ArrowLeft" || e.key === "k" || e.key === "PageUp") {
      e.preventDefault();
      goTo(Math.max(0, active - 1));
    } else if (e.key === "Home") {
      e.preventDefault();
      goTo(0);
    } else if (e.key === "End") {
      e.preventDefault();
      goTo(CONTACTS.length - 1);
    } else if (e.key === "Enter" || e.key === " ") {
      e.preventDefault();
      goTo(active);
    }
  });

  detail.addEventListener("click", (e) => {
    const look = e.target.closest("[data-look]");
    if (look) {
      revealLook(active);
      return;
    }
    if (e.target.closest("[data-map]")) {
      pin.animate(
        [
          { transform: "translate(-50%, -100%) scale(1)" },
          { transform: "translate(-50%, -108%) scale(1.08)" },
          { transform: "translate(-50%, -100%) scale(1)" },
        ],
        { duration: 380, easing: "cubic-bezier(0.22, 1, 0.36, 1)" }
      );
    }
  });

  function revealLook(i) {
    const c = CONTACTS[i];
    if (!c || c.perm === "live") return;

    c.perm = "live";
    c.presence = "away";
    c.label = "Away";
    c.chip = "Away";
    c.place = { strong: "Seen just now", rest: "area on map" };
    c.pin = {
      left: 40 + Math.random() * 30,
      top: 42 + Math.random() * 16,
    };
    c.map = ["a", "b", "c"][Math.floor(Math.random() * 3)];

    refreshCardChip(i);
    setActive(i, { haptic: true });
  }

  setActive(0, { animate: true });
  setTab("home");
  strip.focus({ preventScroll: true });
})();

(() => {
  'use strict';
  if (new URLSearchParams(location.search).has('embed')) document.body.classList.add('embedded');

  const paths = {
    circle: '<circle cx="12" cy="8" r="3"/><path d="M6 20v-2a6 6 0 0 1 12 0v2M18 5a3 3 0 0 1 0 6M21 19v-2a5 5 0 0 0-2-4M6 5a3 3 0 0 0 0 6M3 19v-2a5 5 0 0 1 2-4"/>',
    sharing: '<path d="M12 16V3m-4 4 4-4 4 4M5 12v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
    invite: '<circle cx="9" cy="8" r="3"/><path d="M3 21v-3a6 6 0 0 1 12 0v3M19 7v8m-4-4h8"/>',
    you: '<circle cx="12" cy="8" r="3"/><circle cx="12" cy="12" r="10"/><path d="M5 19a7 7 0 0 1 14 0"/>',
    lock: '<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V6a4 4 0 0 1 8 0v4M12 14v3"/>',
    eye: '<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
    arrow: '<path d="M5 12h14m-5-5 5 5-5 5"/>',
    back: '<path d="m14 6-6 6 6 6"/>',
    chevron: '<path d="m9 6 6 6-6 6"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    close: '<path d="m6 6 12 12M18 6 6 18"/>',
    home: '<path d="m3 10 9-7 9 7M5 9v12h14V9M9 21v-8h6v8"/>',
    map: '<path d="m3 5 6-2 6 2 6-2v16l-6 2-6-2-6 2V5Zm6-2v16m6-14v16"/>',
    bell: '<path d="M5 17h14l-2-3V9A5 5 0 0 0 7 9v5l-2 3Zm5 3a2 2 0 0 0 4 0M12 2v2"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    shield: '<path d="m12 2 8 3v6c0 5-8 11-8 11S4 16 4 11V5l8-3Z"/><path d="m8 11 3 3 5-6"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/>',
    link: '<path d="m10 14 4-4M8 16l-2 2a4 4 0 0 1-6-6l5-5a4 4 0 0 1 6 0M16 8l2-2a4 4 0 0 1 6 6l-5 5a4 4 0 0 1-6 0" transform="translate(2 0) scale(.85 1)"/>',
    refresh: '<path d="M20 10a8 8 0 1 0 0 5M20 3v7h-7"/>'
  };
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.circle}</svg>`;
  const people = [
    {id:'maya', name:'Maya Chen', initials:'MC', presence:'Home', city:'San Francisco', neighborhood:'Inner Sunset', distance:'2.4 miles from your home', color:'#e4e9dc', mode:'until', x:13, y:37},
    {id:'leo', name:'Leo Park', initials:'LP', presence:'Away', city:'Seattle', neighborhood:'Capitol Hill', distance:'680 miles from your home', color:'#e4e9e9', mode:'always', x:18, y:20},
    {id:'ines', name:'Inês Costa', initials:'IC', presence:'Hidden', city:'Lisbon', neighborhood:'Príncipe Real', distance:'5,670 miles from your home', color:'#efe3d7', mode:'until', x:42, y:41},
    {id:'jules', name:'Jules Morgan', initials:'JM', presence:'Away', city:'New York', neighborhood:'Fort Greene', distance:'2,570 miles from your home', color:'#e5e3ed', mode:'timed', x:31, y:28},
    {id:'sam', name:'Sam Rivera', initials:'SR', presence:'Home', city:'Austin', neighborhood:'Hyde Park', distance:'1,500 miles from your home', color:'#e8e3d5', mode:'until', x:26, y:45},
    {id:'eli', name:'Eli Brooks', initials:'EB', presence:'Hidden', city:'London', neighborhood:'Hackney', distance:'5,350 miles from your home', color:'#dfe8e1', mode:'always', x:51, y:20},
    {id:'ren', name:'Ren Tanaka', initials:'RT', presence:'Home', city:'Tokyo', neighborhood:'Shimokitazawa', distance:'5,130 miles from your home', color:'#e8e0d9', mode:'until', x:88, y:32},
    {id:'sofia', name:'Sofía López', initials:'SL', presence:'Away', city:'Mexico City', neighborhood:'Condesa', distance:'1,880 miles from your home', color:'#eadfdc', mode:'until', x:22, y:59},
    {id:'noah', name:'Noah Wilson', initials:'NW', presence:'Hidden', city:'Sydney', neighborhood:'Surry Hills', distance:'7,420 miles from your home', color:'#e0e5e9', mode:'until', x:90, y:77}
  ];
  const screen = document.getElementById('screen');
  const tabs = document.getElementById('tabs');
  const layer = document.getElementById('modal-layer');
  const state = {revealed:new Set(), receipts:[], outbound:{maya:'until', leo:'always', ines:'timed', jules:'until'}, durations:{ines:60}, deadlines:{ines:Date.now()+3600000}, myPresence:'home', selected:'maya', scenario:false, viewScenario:false, invited:'', inviteCode:false, mapUpdated:'Just now', route:'circle'};
  let lastFocus = null;
  let toastTimer;
  const safe = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;', "'":'&#39;'}[c]));
  const person = id => people.find(p => p.id === id) || people[0];
  const avatar = (p, large = false) => `<span class="avatar${large ? ' large' : ''}" style="--avatar:${p.color}" aria-hidden="true">${p.initials}</span>`;
  const modeLabel = mode => ({until:'Until they look', always:'Always', timed:'For a while', off:'Not sharing'})[mode];
  const presenceLabel = presence => ({Home:'Home', Away:'Away', Hidden:'Hidden', home:'Home', away:'Away', hidden:'Hidden'})[presence] || presence;
  const presenceLine = (p, {seen=false} = {}) => {
    if (seen) return `${icon('eye')}${isAvailable(p) ? 'Opened' : 'Looked'} · tap View`;
    if (isAvailable(p)) {
      if (p.presence === 'Hidden') return `${icon('eye')}Available · presence hidden`;
      return `<span class="presence-dot ${p.presence === 'Away' ? 'away' : ''}"></span>${p.presence} <span aria-hidden="true">·</span> Available`;
    }
    if (p.presence === 'Hidden') return `${icon('lock')}Sealed · presence hidden`;
    return `<span class="presence-dot ${p.presence === 'Away' ? 'away' : ''}"></span>${p.presence} <span aria-hidden="true">·</span> Sealed`;
  };
  const presenceBadge = p => {
    if (p.presence === 'Hidden') return `<span class="badge">${icon('lock')}Presence hidden</span>`;
    return `<span class="badge">${icon(p.presence === 'Home' ? 'home' : 'eye')}${p.presence}</span>`;
  };
  const outgoingDescription = p => {
    const mode = state.outbound[p.id];
    if (mode === 'off') return 'Not sharing. They can’t Look at you.';
    if (mode === 'until') return 'Sealed until they Look. You’re notified.';
    if (mode === 'always') return 'Location available to them. Every view is logged.';
    return `Available until ${new Date(state.deadlines[p.id]).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'})}. Then seals. Views are logged.`;
  };
  const effectiveMode = p => state.scenario ? 'always' : p.mode;
  const isAvailable = p => { const m = effectiveMode(p); return m === 'always' || m === 'timed'; };
  const isLive = p => isAvailable(p);
  function toast(message) {
    const el = document.getElementById('toast');
    clearTimeout(toastTimer); el.textContent = message; el.hidden = false;
    toastTimer = setTimeout(() => { el.hidden = true; }, 3800);
  }
  function go(route) {
    if (location.hash === `#${route}`) render(); else location.hash = route;
  }
  function nav(active) {
    tabs.innerHTML = ['circle','sharing','invite','you'].map(name => `<a href="#${name}" ${name === active ? 'aria-current="page"' : ''}>${icon(name)}<span>${name[0].toUpperCase()+name.slice(1)}</span></a>`).join('');
  }
  function circle() {
    return `<div class="screen-content">
      <h1 class="sr-only">Circle</h1>
      <div class="section-heading"><span class="eyebrow">SHARED WITH YOU</span><a class="text-link" href="#map">Map ${icon('arrow')}</a></div>
      ${people.map(p => {
        const seen = state.revealed.has(p.id);
        const open = seen || isAvailable(p);
        const action = open ? 'view' : 'look';
        const label = open ? 'View' : 'Look';
        return `<div class="person-row">${avatar(p)}<div class="person-info"><h3>${p.name}</h3><p>${presenceLine(p,{seen})}</p></div><button class="look-button${open ? ' seen' : ''}" data-action="${action}" data-id="${p.id}" aria-label="${open ? 'View' : 'Look at'} ${p.name}">${label}</button></div>`;
      }).join('')}
      <p class="footnote">${icon('shield')}Sealed needs Look (they’re notified). Available is Always or For a while — views are still logged. Add people from Invite.</p></div>`;
  }
  function showLook(id) {
    const p = person(id); state.selected = p.id; lastFocus = document.activeElement;
    layer.innerHTML = `<section class="look-sheet" role="dialog" aria-modal="true" aria-labelledby="look-title" aria-describedby="look-description"><div class="sheet-handle" aria-hidden="true"></div><div class="sheet-top">${avatar(p,true)}<button class="round-button" data-action="cancel-look" aria-label="Close confirmation">${icon('close')}</button></div><span class="eyebrow muted">CONFIRM</span><h2 id="look-title">Look at ${p.name.split(' ')[0]}?</h2><p class="intro" id="look-description"><strong>${p.name.split(' ')[0]} will be notified.</strong><br>${isLive(p) ? 'Then you’ll see their current location while their share is on.' : 'Then you’ll see one location snapshot — not a live feed.'}</p><div class="notification-preview"><span class="notification-logo">T<span class="sr-only">rust</span></span><div style="flex:1"><h3>TRUST <span>now</span></h3><p>Alex looked at your location.</p></div></div><p class="receipt-note">${icon('clock')}${effectiveMode(p)==='until' ? 'Their Until-they-look share ends after this.' : 'Every Look is recorded, even with Always.'}</p><button class="primary" data-action="confirm-look" data-id="${p.id}">${icon('eye')}Look · notify ${p.name.split(' ')[0]}</button><button class="quiet-button" data-action="cancel-look">Cancel</button><p class="scenario-label">Demo — notification is simulated.</p></section>`;
    layer.hidden = false;
    screen.inert = true; tabs.inert = true; document.querySelector('.app-header').inert = true;
    layer.querySelector('[data-action="cancel-look"]').focus({preventScroll:true});
  }
  function closeLook() {
    layer.hidden = true; layer.innerHTML = ''; screen.inert = false; tabs.inert = false; document.querySelector('.app-header').inert = false;
    if (lastFocus && lastFocus.isConnected) lastFocus.focus();
  }
  const localMap = p => `<div class="local-map" role="img" aria-label="Illustrative neighborhood map for ${p.name}; not real map data"><svg class="base" viewBox="0 0 330 172" preserveAspectRatio="none"><rect width="330" height="172" fill="#ebece3"/><path d="M0 0h87l30 172H0Z" fill="#d7e1c9"/><path d="M285 0h45v172h-68Z" fill="#d5e5e7"/><g stroke="#fffef7" stroke-width="7"><path d="m110-10 35 192M151-10l33 192M195-10l28 192M237-10l21 192M75 28l255-20M81 70l250-23M90 111l242-23M97 155l235-25"/></g><g stroke="#d5d7ca" stroke-width="1" fill="none"><path d="m110-10 35 192M195-10l28 192M81 70l250-23M97 155l235-25"/></g><text x="15" y="84" font-family="sans-serif" font-size="8" fill="#82926e">GREEN SPACE</text><text x="182" y="130" font-family="sans-serif" font-size="7" fill="#98998b" transform="rotate(-5 182 130)">NEIGHBORHOOD</text></svg><span class="avatar map-person">${p.initials}</span><span class="map-caption">Illustrative map · not navigation</span></div>`;
  function view() {
    const p = person(state.selected);
    const available = isAvailable(p);
    if (!state.revealed.has(p.id) && !available) return `<div class="screen-content empty-map"><h1 class="page-title">Sealed</h1><p>${p.name.split(' ')[0]} will be notified if you Look.</p><button class="primary" data-action="look" data-id="${p.id}">Look at ${p.name.split(' ')[0]}</button></div>`;
    const receipt = available
      ? `${p.name.split(' ')[0]} · view logged`
      : `${p.name.split(' ')[0]} notified · receipt saved`;
    const strip = available
      ? 'Location is available while their share is on. Every view is logged — same as production Look history.'
      : 'Snapshot only. Their Until-they-look share is used. No further updates.';
    return `<div class="screen-content"><a class="back-link" href="#circle">${icon('back')}Circle</a><div class="view-profile">${avatar(p,true)}<div><h1>${p.name.split(' ')[0]}<span class="red">.</span></h1><p>${available ? 'Location available · live share' : 'One-time Look'}</p></div></div>${presenceBadge(p)}<h2 class="location-title">${p.neighborhood}<br><span class="muted">${p.city}</span></h2><p class="location-meta">${p.distance}</p><p class="reveal-receipt">${icon('check')}${receipt}</p>${localMap(p)}<div class="view-actions"><a href="#map" class="secondary">${icon('map')}Circle map</a><a href="#circle" class="secondary">Back ${icon('arrow')}</a></div><div class="info-strip">${icon(available ? 'eye' : 'lock')}<p>${strip}</p></div>${state.viewScenario ? '<p class="scenario-label">Demo: Look confirmed; notification simulated.</p>' : ''}</div>`;
  }
  const world = `<svg class="world-map" viewBox="0 0 720 360" preserveAspectRatio="none" aria-hidden="true"><rect width="720" height="360" fill="#deebeb"/><g stroke="#d7e5e4" stroke-width=".6"><path d="M0 90h720M0 180h720M0 270h720M180 0v360M360 0v360M540 0v360"/></g><g class="land"><path d="m40 57 45-21 37 7 26-15 38 12 42-5 21 23-19 24-27 4-15 24-22 7-13 25-15 12-11-9-18-12-11-27-22-13-19-6-22 2-14-11Z"/><path d="m144 145 18 6 12 17 16 6 13 18 27 5 23 26-3 23-24 27-14 38-20 19-9-25 1-36-16-30-4-29-15-22-10-19Z"/><path d="m254 19 28-8 22 17-12 33-20 16-16-22Z"/><path d="m337 71 16-23 27-4 12 13 13-13 32-14 49 1 34-12 57 17 34-3 49 20 40 11-6 23-33 8-22 15-10 23-23 4-10 26-23 5-15-13-6-27-25-9-7 23-15 17-20-24-4-27-30-5-20-14-25-5-12 10-22-2-9-8-16 6Z"/><path d="m335 115 25-7 28 9 17-1 12 25 16 17-12 23-13 11-10 29-15 27-16-2-7-21-13-14-5-36-18-19 1-21Z"/><path d="m410 233 7-20 6 9-4 24-8 7Z"/><path d="m581 252 25-21 23 4 17-11 19 15 13 18-2 22-22 11-26-6-28 5-21-14Z"/><path d="m679 291 11-7-1 17-13 11-3-6ZM650 302l8-8 5 8-8 9Z"/><path d="m634 114 6-10 4 12-5 18-9 9-3-7Z"/><path d="m559 174 12 6 9 17-7 5-13-15ZM577 216l25 2 16 10-6 5-26-7ZM618 187l8 6 2 20-7-3Z"/><path d="m347 80-4-11 6-9 6 16-3 8Z"/></g><g class="border"><path d="m79 92 89 6 25-11M106 129l52 7M177 239l42-10 22 7M352 149l39-5 23 10M470 91l32-26 37 22 42-9M579 113l-26 20-33-8"/></g><text x="237" y="157">ATLANTIC</text><text x="31" y="249">PACIFIC</text><text x="467" y="245">INDIAN OCEAN</text></svg>`;
  function mapScreen() {
    const visible = people.filter(p => state.revealed.has(p.id) || isAvailable(p));
    if (!visible.length) return `<div class="screen-content"><a class="back-link" href="#circle">${icon('back')}Circle</a><div class="empty-map">${icon('lock')}<h2 style="margin-top:20px">No locations yet</h2><p>Sealed people don’t appear here. Look (they’re notified), or wait until someone shares Always / For a while.</p><a class="primary" href="#circle">Back to Circle</a><a class="quiet-button" href="#map-demo">Open 9-city demo</a></div></div>`;
    if (!visible.some(p => p.id === state.selected)) state.selected = visible[0].id;
    const p = person(state.selected);
    const sealedLeft = 9 - visible.length;
    return `<div class="map-header"><a class="back-link" href="#circle">${icon('back')}Circle</a><div class="title-row"><h1 class="page-title">Map<span class="red">.</span></h1></div><p class="title-sub">${state.scenario ? '9 cities · demo pins' : `${visible.length} on map · ${sealedLeft} sealed`}</p></div><div class="map-stage" role="group" aria-label="Interactive illustrative world map">${world}${visible.map(f => `<button class="map-pin" style="left:${f.x}%;top:${f.y}%" data-action="select-pin" data-id="${f.id}" aria-label="${f.name}, ${f.city}" aria-pressed="${p.id===f.id}"><span>${f.initials}</span></button>`).join('')}</div><div class="map-legend"><span>${state.scenario ? '● LIVE DEMO · SIMULATED' : '● AVAILABLE + OPENED'}</span><span>ILLUSTRATIVE · CITY LEVEL</span></div><div class="map-person-card"><div class="person-row">${avatar(p)}<div class="person-info"><h3>${p.name}</h3><p>${p.presence === 'Hidden' ? 'Presence hidden' : p.presence} · ${isAvailable(p) ? state.mapUpdated : 'Snapshot'}</p></div><span class="badge">${isAvailable(p) ? 'Available' : 'One look'}</span></div><h2>${p.neighborhood}</h2><p>${p.city} · ${p.distance}</p></div><div class="map-people" aria-label="Choose a friend">${visible.map(f => `<button class="map-person-chip" data-action="select-pin" data-id="${f.id}" aria-pressed="${p.id===f.id}">${f.name.split(' ')[0]}</button>`).join('')}</div>${state.scenario ? `<div style="padding:0 23px"><button class="secondary" data-action="refresh-map">${icon('refresh')}Refresh simulated locations</button></div><p class="scenario-banner">Demo scenario: all nine friends granted Always access; nine views logged. Sealed people stay off the map until Look.</p>` : `<div style="padding:0 23px"><button class="secondary" data-action="view" data-id="${p.id}">View ${p.name.split(' ')[0]}’s location ${icon('arrow')}</button><p class="footnote">${icon('lock')}${sealedLeft} sealed location${sealedLeft === 1 ? '' : 's'} not on this map.</p></div>`}`;
  }
  function sharing() {
    const outgoing = people.filter(p => p.id in state.outbound);
    return `<div class="screen-content"><div class="title-row"><h1 class="page-title">Sharing<span class="red">.</span></h1></div><p class="title-sub">What each person can see of you.</p><p class="sharing-intro">Sealed until Look, or Available with Always / For a while. Views and Looks are always logged.</p><div class="section-heading"><span class="eyebrow">YOU SHARE WITH · ${outgoing.length}</span></div>${outgoing.map(p => `<section class="outbound-row" aria-label="Sharing with ${p.name}"><div class="person-row">${avatar(p)}<div class="person-info"><h3>${p.name}</h3><p>${state.outbound[p.id]==='off' ? 'Not sharing' : state.outbound[p.id]==='until' ? 'Sealed until Look' : 'Location available'}</p></div><span class="inline-status">${icon(state.outbound[p.id]==='off' || state.outbound[p.id]==='until' ? 'lock' : 'eye')}</span></div><div class="mode-control" role="group" aria-label="Permission for ${p.name}">${['until','always','timed'].map(mode => `<button data-action="mode" data-id="${p.id}" data-mode="${mode}" aria-pressed="${state.outbound[p.id]===mode}">${modeLabel(mode)}</button>`).join('')}</div>${state.outbound[p.id]==='timed' ? `<div class="duration-control"><label for="duration-${p.id}">Duration</label><select id="duration-${p.id}" data-duration="${p.id}" aria-label="Sharing duration for ${p.name}">${[[15,'15 minutes'],[60,'1 hour'],[240,'4 hours'],[480,'8 hours']].map(([n,label]) => `<option value="${n}" ${state.durations[p.id]===n ? 'selected' : ''}>${label}</option>`).join('')}</select></div>` : ''}<div class="mode-description"><span>${outgoingDescription(p)}</span>${state.outbound[p.id]!=='off' ? `<button class="stop-sharing" data-action="stop" data-id="${p.id}">Stop</button>` : ''}</div></section>`).join('')}<div class="sharing-footer"><a class="secondary" href="#invite">${icon('plus')}Invite someone</a></div><div class="mode-key"><p><strong>Until they look</strong> — sealed; one Look, you’re notified.<br><strong>Always</strong> — location available until you stop; every view logged.<br><strong>For a while</strong> — available on a timer, then seals.<br>Nothing is invisible.</p></div></div>`;
  }
  function invite() {
    return `<div class="screen-content"><div class="title-row"><h1 class="page-title">Invite<span class="red">.</span></h1></div><p class="title-sub">Add someone to your circle.</p><div class="invite-art" aria-hidden="true"><span class="invite-orbit"></span><span class="invite-orbit second"></span><span class="avatar">A</span><span class="connection-mark">+</span><span class="avatar">?</span></div><h2 class="invite-heading">I trust you<br>with my location.</h2><p class="invite-description">They join the circle. Sharing stays off until each of you chooses a mode.</p>${state.invited ? `<div class="invite-success" role="status"><h2>Invite ready</h2><p>Prepared for <strong>${safe(state.invited)}</strong>. Nothing sent. No location shared.</p><button class="secondary" data-action="another-invite">Invite someone else</button></div>` : `<form class="invite-form" id="invite-form"><label for="invite-email">Email</label><input id="invite-email" name="email" type="email" placeholder="name@example.com" autocomplete="email" maxlength="254" required><button class="primary" type="submit">Prepare invite ${icon('arrow')}</button></form><div class="invite-divider">OR</div><button class="secondary" data-action="copy-invite">${icon('link')}${state.inviteCode ? 'Copy link again' : 'Copy demo invite link'}</button>${state.inviteCode ? '<code class="invite-code">https://trust.example/invite/alex-demo</code>' : ''}`}<p class="footnote">${icon('lock')}Invite ≠ permission. Modes are set after they join.</p><p class="scenario-label">Demo only. No email sent.</p></div>`;
  }
  function you() {
    const active = Object.values(state.outbound).filter(mode => mode!=='off').length;
    const presenceCopy = {home:'Your circle can see Home or Away — never coordinates.', away:'Shown as Away when you’re not at Home.', hidden:'Your circle sees no presence signal.'}[state.myPresence];
    return `<div class="screen-content"><div class="title-row"><h1 class="page-title">You<span class="red">.</span></h1></div><div class="profile-card">${avatar({initials:'AL',color:'#e3e5da'},true)}<div><h2>Alex Laurent</h2><p>San Francisco · Free plan</p></div></div><div class="privacy-summary"><span class="eyebrow">STATUS</span><h3>Sealed by default</h3><p>${active ? `Sharing with ${active} people.<br>Looks notify you. Available shares still log every view.` : 'No outbound location shares.<br>Nobody can Look at you.'}</p><a class="text-link" href="#sharing">Manage sharing ${icon('arrow')}</a></div>
      <div class="section-heading"><span class="eyebrow">PRESENCE</span></div>
      <p class="settings-note" style="margin-top:0">Home / Away / Hidden — separate from whether location is sealed or available.</p>
      <div class="mode-control presence-control" role="group" aria-label="My presence">${['home','away','hidden'].map(v => `<button data-action="my-presence" data-presence="${v}" aria-pressed="${state.myPresence===v}">${presenceLabel(v)}</button>`).join('')}</div>
      <p class="settings-note">${presenceCopy}</p>
      <div class="plus-card"><span class="eyebrow red">TRUST PLUS</span><h3>More room. Same rules.</h3><ul class="plus-list"><li><strong>Free</strong> — up to 5 people · Until they look · Look + notify · single map after Look</li><li><strong>Plus</strong> — up to 20 · Always &amp; For a while (location available) · circle map · full view log · Home/Work labels</li></ul><p class="plus-note">Privacy basics stay free. Plus is capacity and convenience — $7.99/mo or $69.99/yr.</p><button class="secondary" type="button" data-action="plus-toast">See Plus (demo)</button></div>
      <div class="section-heading"><span class="eyebrow">SETTINGS</span></div><div class="settings-row"><div><h3>Look notifications</h3><p>Always on for Sealed Looks. Available views are logged.</p></div>${icon('lock')}</div><div class="section-heading"><span class="eyebrow">VIEW LOG</span></div>${state.receipts.length ? state.receipts.slice().reverse().map(r => `<div class="receipt-row">${r.kind === 'view' ? `You viewed ${r.name}.` : `You looked at ${r.name}.`}<span>${r.time} · ${r.kind === 'view' ? 'view logged' : 'notification simulated'}</span></div>`).join('') : '<p class="receipt-empty">No views yet.</p>'}<button class="danger-link" data-action="stop-all">Stop all location sharing</button><div class="brand-signoff"><span class="wordmark">Trust<span class="brand-dot">.</span></span><p>Sealed until Look — or Available when you choose.</p></div></div>`;
  }
  function addReceipt(p, scenario = false, kind = 'look') {
    state.revealed.add(p.id);
    state.receipts.push({name:p.name, time:scenario ? 'Demo scenario' : new Date().toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}), kind: scenario ? 'look' : kind});
  }
  function seedScenario(route) {
    if (route === 'map-demo' && !state.scenario) {
      state.scenario = true;
      people.forEach(p => {if (!state.revealed.has(p.id)) addReceipt(p,true);});
    }
    if (route === 'view-demo' && !state.revealed.has('maya')) {state.viewScenario = true; state.selected = 'maya'; addReceipt(people[0],true);}
  }
  function render() {
    if (!layer.hidden) closeLook();
    const raw = location.hash.slice(1) || 'circle';
    seedScenario(raw);
    const route = ({'look':'circle','map-demo':'map','view-demo':'view'})[raw] || raw;
    state.route = ['circle','sharing','invite','you','view','map'].includes(route) ? route : 'circle';
    screen.innerHTML = ({circle,sharing,invite,you,view,map:mapScreen})[state.route]();
    nav(['map','view'].includes(state.route) ? 'circle' : state.route);
    document.querySelector('.header-caption').textContent = (state.route === 'view' ? 'circle' : state.route).toUpperCase();
    screen.scrollTop = 0;
    document.title = `Trust — ${state.route[0].toUpperCase()+state.route.slice(1)}`;
    if (raw === 'look') showLook('maya');
  }
  function rerenderAtScroll() {
    const scroll = screen.scrollTop;
    render(); screen.scrollTop = scroll;
  }
  document.addEventListener('click', async event => {
    const button = event.target.closest('[data-action]');
    if (!button) return;
    const {action,id,mode,presence} = button.dataset;
    if (action === 'look') showLook(id);
    if (action === 'cancel-look') {closeLook(); if (location.hash === '#look') go('circle');}
    if (action === 'confirm-look') {addReceipt(person(id), false, 'look'); closeLook(); state.viewScenario = false; go('view'); toast(`${person(id).name.split(' ')[0]} notified — simulated. Look receipt saved.`);}
    if (action === 'view') {
      const p = person(id);
      state.selected = id;
      if (!state.revealed.has(p.id) && isAvailable(p)) {
        addReceipt(p, false, 'view');
        toast(`${p.name.split(' ')[0]} · view logged. Location available while they share.`);
      }
      go('view');
    }
    if (action === 'select-pin') {
      const chipScroll = screen.querySelector('.map-people')?.scrollLeft || 0;
      state.selected = id; rerenderAtScroll();
      screen.querySelector('.map-people').scrollLeft = chipScroll;
      screen.querySelector(`.${button.classList.contains('map-pin') ? 'map-pin' : 'map-person-chip'}[data-id="${id}"]`).focus({preventScroll:true});
    }
    if (action === 'mode') {
      state.outbound[id] = mode;
      if (mode === 'timed') {state.durations[id] ||= 60; state.deadlines[id] = Date.now()+state.durations[id]*60000;}
      else delete state.deadlines[id];
      rerenderAtScroll(); screen.querySelector(`[data-action="mode"][data-id="${id}"][data-mode="${mode}"]`).focus({preventScroll:true});
      toast(`${person(id).name.split(' ')[0]}: ${modeLabel(mode)}. Permission updated.`);
    }
    if (action === 'stop') {state.outbound[id] = 'off'; delete state.deadlines[id]; rerenderAtScroll(); screen.querySelector(`[data-action="mode"][data-id="${id}"]`).focus({preventScroll:true}); toast(`Location sharing with ${person(id).name.split(' ')[0]} stopped.`);}
    if (action === 'my-presence') {
      state.myPresence = presence;
      rerenderAtScroll();
      screen.querySelector(`[data-action="my-presence"][data-presence="${presence}"]`).focus({preventScroll:true});
      toast(presence === 'hidden' ? 'Presence hidden from your circle.' : `Presence set to ${presenceLabel(presence)}. No coordinates shared.`);
    }
    if (action === 'stop-all') {Object.keys(state.outbound).forEach(key => {state.outbound[key] = 'off';}); state.deadlines = {}; rerenderAtScroll(); screen.querySelector('[data-action="stop-all"]').focus({preventScroll:true}); toast('All outbound location sharing stopped.');}
    if (action === 'another-invite') {state.invited = ''; render(); screen.querySelector('#invite-email').focus();}
    if (action === 'copy-invite') {
      state.inviteCode = true; rerenderAtScroll(); screen.querySelector('[data-action="copy-invite"]').focus({preventScroll:true});
      try {await navigator.clipboard.writeText('https://trust.example/invite/alex-demo'); toast('Demo invite copied. This is not an active invite link.');}
      catch {toast('Copy unavailable here. Select and copy the demo link below.');}
    }
    if (action === 'refresh-map') {state.mapUpdated = new Date().toLocaleTimeString([], {hour:'numeric',minute:'2-digit',second:'2-digit'}); rerenderAtScroll(); screen.querySelector('[data-action="refresh-map"]').focus({preventScroll:true}); toast('Simulated updates for 9 cities.');}
    if (action === 'plus-toast') toast('Plus is capacity & convenience. Look notify stays free.');
  });
  document.addEventListener('submit', event => {
    if (event.target.id !== 'invite-form') return;
    event.preventDefault(); state.invited = new FormData(event.target).get('email').trim(); render(); screen.focus({preventScroll:true});
  });
  document.addEventListener('change', event => {
    const id = event.target.dataset.duration;
    if (!id) return;
    state.durations[id] = Number(event.target.value); state.deadlines[id] = Date.now()+state.durations[id]*60000;
    rerenderAtScroll(); screen.querySelector(`[data-duration="${id}"]`).focus({preventScroll:true}); toast('Sharing timer updated. It will seal automatically.');
  });
  document.addEventListener('keydown', event => {
    if (layer.hidden) return;
    if (event.key === 'Escape') {event.preventDefault(); closeLook(); if (location.hash === '#look') go('circle');}
    if (event.key === 'Tab') {
      const controls = [...layer.querySelectorAll('button,a,input,select,[tabindex="0"]')];
      const first = controls[0], last = controls[controls.length-1];
      if (event.shiftKey && document.activeElement === first) {event.preventDefault(); last.focus();}
      else if (!event.shiftKey && document.activeElement === last) {event.preventDefault(); first.focus();}
    }
  });
  // Timed outbound permissions expire in-session; no browser storage or tracking is used.
  setInterval(() => {
    let expired = false;
    Object.entries(state.deadlines).forEach(([id,deadline]) => {
      if (state.outbound[id] === 'timed' && Date.now() >= deadline) {state.outbound[id] = 'off'; delete state.deadlines[id]; expired = true;}
    });
    if (expired) {if (state.route === 'sharing' || state.route === 'you') rerenderAtScroll(); toast('A timed permission ended. Your location is sealed again.');}
  }, 1000);
  window.addEventListener('hashchange', () => {render(); if (layer.hidden) screen.focus({preventScroll:true});});
  render();
})();

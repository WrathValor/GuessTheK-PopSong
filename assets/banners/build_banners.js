// Generates banners.html — 10 player banners, 1024x256 art space (rendered @2x).
const fs = require('fs');
const FONTS = '/home/claude/fonts/node_modules/@fontsource';
const INK = '#1E1B2E';

// ---------- shape helpers ----------
const star = (x, y, r, fill, sw = 3, rot = 0, stroke = INK) => {
  let p = [];
  for (let i = 0; i < 10; i++) {
    const a = (Math.PI / 5) * i - Math.PI / 2;
    const rr = i % 2 ? r * 0.48 : r;
    p.push(`${(Math.cos(a) * rr).toFixed(1)},${(Math.sin(a) * rr).toFixed(1)}`);
  }
  return `<polygon transform="translate(${x},${y}) rotate(${rot})" points="${p.join(' ')}" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" stroke-linejoin="round"/>`;
};
const sparkle = (x, y, r, fill, stroke = 'none', sw = 0) =>
  `<path transform="translate(${x},${y})" d="M0,${-r} Q0,0 ${r},0 Q0,0 0,${r} Q0,0 ${-r},0 Q0,0 0,${-r}Z" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" stroke-linejoin="round"/>`;
const heart = (x, y, s, fill, sw = 3, rot = 0, stroke = INK) =>
  `<path transform="translate(${x},${y}) rotate(${rot}) scale(${s / 80})" d="M0 30 C -42 2 -34 -36 0 -16 C 34 -36 42 2 0 30 Z" fill="${fill}" stroke="${stroke}" stroke-width="${(sw * 80) / s}" stroke-linejoin="round"/>`;
const flower = (x, y, r, n, fill, center, sw = 3, rot = 0) => {
  let s = `<g transform="translate(${x},${y}) rotate(${rot})">`;
  for (let i = 0; i < n; i++)
    s += `<ellipse cx="0" cy="${-r * 0.55}" rx="${r * 0.38}" ry="${r * 0.55}" transform="rotate(${(360 / n) * i})" fill="${fill}" stroke="${INK}" stroke-width="${sw}"/>`;
  return s + `<circle r="${r * 0.3}" fill="${center}" stroke="${INK}" stroke-width="${sw}"/></g>`;
};
const lily = (x, y, r, fill, stripe, rot = 0) => {
  let s = `<g transform="translate(${x},${y}) rotate(${rot})">`;
  for (let i = 0; i < 6; i++) {
    s += `<g transform="rotate(${i * 60})"><path d="M0,0 C${r * 0.4},${-r * 0.35} ${r * 0.25},${-r * 0.9} 0,${-r} C${-r * 0.25},${-r * 0.9} ${-r * 0.4},${-r * 0.35} 0,0Z" fill="${fill}" stroke="${INK}" stroke-width="2.5"/>`;
    s += `<path d="M0,${-r * 0.15} L0,${-r * 0.8}" stroke="${stripe}" stroke-width="${r * 0.08}" stroke-linecap="round"/></g>`;
  }
  for (let i = 0; i < 5; i++) {
    const a = -90 + (i - 2) * 18;
    const ex = Math.cos((a * Math.PI) / 180) * r * 0.75, ey = Math.sin((a * Math.PI) / 180) * r * 0.75;
    s += `<line x1="0" y1="0" x2="${ex}" y2="${ey}" stroke="${INK}" stroke-width="2"/><ellipse cx="${ex}" cy="${ey}" rx="${r * 0.07}" ry="${r * 0.12}" fill="#FFB547" stroke="${INK}" stroke-width="1.5"/>`;
  }
  return s + '</g>';
};
const leaf = (x, y, l, rot, fill = '#3DBE7A') =>
  `<g transform="translate(${x},${y}) rotate(${rot})"><path d="M0,0 C${l * 0.3},${-l * 0.25} ${l * 0.75},${-l * 0.2} ${l},0 C${l * 0.75},${l * 0.2} ${l * 0.3},${l * 0.25} 0,0Z" fill="${fill}" stroke="${INK}" stroke-width="2.5"/><path d="M${l * 0.05},0 L${l * 0.85},0" stroke="${INK}" stroke-width="1.5"/></g>`;
const cassette = (x, y, w, rot, body, label, text = '') => {
  const h = w * 0.64;
  return `<g transform="translate(${x},${y}) rotate(${rot})">
  <rect x="${-w / 2 + 4}" y="${-h / 2 + 4}" width="${w}" height="${h}" rx="${w * 0.07}" fill="${INK}"/>
  <rect x="${-w / 2}" y="${-h / 2}" width="${w}" height="${h}" rx="${w * 0.07}" fill="${body}" stroke="${INK}" stroke-width="3"/>
  <rect x="${-w * 0.4}" y="${-h * 0.36}" width="${w * 0.8}" height="${h * 0.5}" rx="${w * 0.03}" fill="${label}" stroke="${INK}" stroke-width="2.5"/>
  <rect x="${-w * 0.26}" y="${-h * 0.2}" width="${w * 0.52}" height="${h * 0.2}" rx="${h * 0.1}" fill="#2C2A40" stroke="${INK}" stroke-width="2"/>
  <circle cx="${-w * 0.16}" cy="${-h * 0.1}" r="${h * 0.07}" fill="#fff" stroke="${INK}" stroke-width="2"/>
  <circle cx="${w * 0.16}" cy="${-h * 0.1}" r="${h * 0.07}" fill="#fff" stroke="${INK}" stroke-width="2"/>
  <path d="M${-w * 0.3},${h / 2} L${-w * 0.22},${h * 0.26} L${w * 0.22},${h * 0.26} L${w * 0.3},${h / 2}" fill="${label}" stroke="${INK}" stroke-width="2.5"/>
  ${text ? `<text x="0" y="${-h * 0.24}" text-anchor="middle" font-family="Pacifico" font-size="${w * 0.1}" fill="${INK}">${text}</text>` : ''}
  </g>`;
};
const face = (x, y, s = 1, blush = '#FF8FB8') =>
  `<g transform="translate(${x},${y}) scale(${s})"><circle cx="-7" cy="0" r="2.6" fill="${INK}"/><circle cx="7" cy="0" r="2.6" fill="${INK}"/><path d="M-3.5,4 Q0,7.5 3.5,4" fill="none" stroke="${INK}" stroke-width="2" stroke-linecap="round"/><ellipse cx="-12" cy="5" rx="3.5" ry="2" fill="${blush}" opacity=".85"/><ellipse cx="12" cy="5" rx="3.5" ry="2" fill="${blush}" opacity=".85"/></g>`;
const dots = (id, color, gap = 14, r = 1.4) =>
  `<pattern id="${id}" width="${gap}" height="${gap}" patternUnits="userSpaceOnUse"><circle cx="${gap / 2}" cy="${gap / 2}" r="${r}" fill="${color}"/></pattern>`;
const rnd = (() => { let s = 7; return () => ((s = (s * 16807) % 2147483647) / 2147483647); })();

// ---------- banners ----------
const B = [];

// 1 RetroBloom — psychedelic flower collage + cassettes (poster 1)
B.push(['RetroBloom', (() => {
  let s = `<defs>${dots('d1', '#ffffff22', 12)}<linearGradient id="g1" x1="0" x2="1"><stop offset="0" stop-color="#3B2A8C"/><stop offset=".45" stop-color="#5B3FC4"/><stop offset="1" stop-color="#2FB7C4"/></linearGradient>
  <filter id="glow1"><feGaussianBlur stdDeviation="3" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
  <rect width="1024" height="256" fill="url(#g1)"/><rect width="1024" height="256" fill="url(#d1)"/>`;
  // rainbow arcs from bottom-right
  const arcCols = ['#FF5FA8', '#FF9A3D', '#FFE07A', '#3DD6C6', '#9B5CFF', '#FF5FA8', '#FF9A3D'];
  arcCols.forEach((c, i) => s += `<circle cx="1010" cy="300" r="${330 - i * 26}" fill="none" stroke="${c}" stroke-width="26"/>`);
  s += `<circle cx="1010" cy="300" r="${330 - 7 * 26 + 13}" fill="#2B2063"/>`;
  arcCols.forEach((c, i) => s += `<circle cx="1010" cy="300" r="${330 - i * 26 + 13}" fill="none" stroke="${INK}" stroke-width="2.5"/>`);
  // leaves + flowers
  [[470, 250, 70, -60], [560, 30, 60, 200], [700, 260, 80, -100], [880, 20, 70, 160], [640, 120, 60, 30], [990, 150, 60, 200], [430, 60, 50, -20]]
    .forEach(([x, y, l, r]) => s += leaf(x, y, l, r));
  s += lily(520, 200, 62, '#FF7EB8', '#FFC2DD', 10);
  s += flower(610, 60, 46, 5, '#FF9A3D', '#FFE07A', 3, 20);
  s += lily(770, 150, 70, '#B98BFF', '#E3D0FF', -15);
  s += flower(900, 225, 44, 6, '#FF5F7E', '#FFE07A');
  s += flower(965, 50, 34, 5, '#FFE07A', '#FF9A3D');
  s += flower(445, 128, 26, 5, '#3DD6C6', '#FFF');
  s += cassette(680, 52, 92, -12, '#FF9EC4', '#FFF4E0', '♥ mix');
  s += cassette(880, 120, 80, 14, '#7EE0D6', '#FFE07A');
  // neon swooshes
  s += `<g filter="url(#glow1)" fill="none" stroke-linecap="round"><path d="M560,140 C620,100 700,190 760,90" stroke="#FF8FE0" stroke-width="4"/><path d="M570,152 C630,112 710,202 770,102" stroke="#7FF6FF" stroke-width="3"/></g>`;
  // waveform
  for (let i = 0; i < 22; i++) { const h = 6 + Math.abs(Math.sin(i * 1.3)) * 28; s += `<rect x="${600 + i * 7}" y="${228 - h / 2}" width="3.5" height="${h}" rx="1.7" fill="#AEEBFF" opacity=".9"/>`; }
  // pixel heart
  const ph = ['01100110', '11111111', '11111111', '01111110', '00111100', '00011000'];
  ph.forEach((row, j) => [...row].forEach((c, i) => { if (c === '1') s += `<rect x="${830 + i * 6}" y="${190 + j * 6}" width="6" height="6" fill="#FF5FA8" stroke="${INK}" stroke-width="1"/>`; }));
  s += star(545, 110, 14, '#FFE07A', 2.5) + sparkle(740, 20, 10, '#fff') + sparkle(470, 190, 8, '#fff') + sparkle(990, 110, 9, '#fff');
  // stripe border bottom
  const sc = ['#FF5FA8', '#FF9A3D', '#FFE07A', '#3DD6C6', '#9B5CFF'];
  for (let i = 0; i < 64; i++) s += `<rect x="${i * 16}" y="246" width="16" height="10" fill="${sc[i % 5]}"/>`;
  s += `<rect y="244" width="1024" height="3" fill="${INK}"/>`;
  return s;
})()]);

// 2 ChromeDream — Y2K glossy chrome script on lilac (poster 2)
B.push(['ChromeDream', (() => {
  let s = `<defs>${dots('d2', '#ffffff55', 10, 1.3)}
  <linearGradient id="g2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#B9A6FF"/><stop offset=".6" stop-color="#D9B6F5"/><stop offset="1" stop-color="#FFB8DD"/></linearGradient>
  <linearGradient id="chrome" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".38" stop-color="#FFC3EC"/><stop offset=".52" stop-color="#E25FC9"/><stop offset=".62" stop-color="#FFB3E6"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient>
  <linearGradient id="puff" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset="1" stop-color="#F6C8FF"/></linearGradient>
  <filter id="soft2"><feGaussianBlur stdDeviation="6"/></filter></defs>
  <rect width="1024" height="256" fill="url(#g2)"/><rect width="1024" height="256" fill="url(#d2)"/>
  <ellipse cx="760" cy="128" rx="300" ry="110" fill="#fff" opacity=".35" filter="url(#soft2)"/>`;
  s += star(470, 70, 52, 'url(#puff)', 4, -12, '#C25BD8') + star(980, 200, 46, 'url(#puff)', 4, 14, '#C25BD8');
  // chrome text with layered outline
  const T = (dy, fill, stroke, sw) => `<text x="740" y="${168 + dy}" text-anchor="middle" font-family="Pacifico" font-size="112" fill="${fill}" stroke="${stroke}" stroke-width="${sw}" stroke-linejoin="round" transform="rotate(-6 740 140)">Encore</text>`;
  s += T(6, '#6B2A9E', '#6B2A9E', 14) + T(0, '#fff', '#fff', 14) + T(0, 'url(#chrome)', '#A03BBE', 3);
  s += `<text x="742" y="${108}" text-anchor="middle" font-family="Pacifico" font-size="22" fill="#fff" stroke="#A03BBE" stroke-width="1" transform="rotate(-6 740 140)">this one's for</text>`;
  // sticker
  s += `<g transform="translate(470,170) rotate(-8)"><rect x="-58" y="-20" width="116" height="40" rx="4" fill="${INK}"/><text x="0" y="-2" text-anchor="middle" font-family="Bungee" font-size="13" fill="#fff">LIVE ♥ DUEL</text><text x="0" y="13" text-anchor="middle" font-family="Fredoka" font-weight="600" font-size="9" fill="#FF9EC4">SEOUL · 7 ROUNDS</text></g>`;
  // mini polaroids
  const pol = (x, y, r, c, inner) => `<g transform="translate(${x},${y}) rotate(${r})"><rect x="-26" y="-30" width="52" height="60" rx="3" fill="#fff" stroke="#C25BD8" stroke-width="2.5"/><rect x="-21" y="-25" width="42" height="40" fill="${c}"/>${inner}</g>`;
  s += pol(600, 210, 8, '#9ED8F5', heart(0, -3, 26, '#FF9EC4', 2)) + pol(905, 60, -10, '#A7E9B8', star(0, -5, 13, '#FFE07A', 2));
  [[560, 40, 12], [870, 230, 10], [1000, 40, 14], [520, 230, 8], [690, 30, 7], [940, 140, 6]].forEach(([x, y, r]) => s += sparkle(x, y, r, '#fff'));
  [[640, 60], [820, 215], [975, 110]].forEach(([x, y]) => s += heart(x, y, 16, '#FF5FA8', 2));
  return s;
})()]);

// 3 LavenderStage — big comeback type + 7 mic stands (poster 3)
B.push(['LavenderStage', (() => {
  let s = `<defs><linearGradient id="g3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C9B8FF"/><stop offset=".7" stop-color="#F1EBFF"/><stop offset="1" stop-color="#FFFFFF"/></linearGradient>
  <linearGradient id="t3" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7A57E0"/><stop offset="1" stop-color="#A88BFF"/></linearGradient>
  <pattern id="swirl" width="26" height="26" patternUnits="userSpaceOnUse"><rect width="26" height="26" fill="#6E4BD6"/><path d="M4,13 a9,9 0 1 1 9,9" fill="none" stroke="#D9CCFF" stroke-width="2.5"/><circle cx="13" cy="13" r="2.5" fill="#FFE07A"/></pattern></defs>
  <rect width="1024" height="256" fill="url(#g3)"/>`;
  s += `<text x="704" y="120" text-anchor="middle" font-family="Dela Gothic One" font-size="108" fill="url(#t3)" letter-spacing="-2">STAGE</text>`;
  // floor
  s += `<rect y="214" width="1024" height="42" fill="#E7DEFF"/><rect y="214" width="1024" height="2" fill="#B9A6FF"/>`;
  for (let i = 0; i < 7; i++) {
    const x = 470 + i * 78;
    s += `<g transform="translate(${x},0)"><line x1="0" y1="150" x2="0" y2="212" stroke="#5B3FB0" stroke-width="4"/><path d="M-14,214 L0,204 L14,214" fill="none" stroke="#5B3FB0" stroke-width="4" stroke-linejoin="round"/><line x1="0" y1="150" x2="-10" y2="138" stroke="#5B3FB0" stroke-width="4"/><rect x="-17" y="126" width="12" height="18" rx="6" transform="rotate(-38 -11 135)" fill="#8E72EA"/>
    <line x1="0" y1="218" x2="0" y2="244" stroke="#5B3FB0" stroke-width="4" opacity=".18"/>
    <text x="0" y="236" text-anchor="middle" font-family="Dela Gothic One" font-size="11" fill="#7A57E0">${i + 1}</text></g>`;
  }
  // spot glow
  s += `<ellipse cx="740" cy="214" rx="300" ry="10" fill="#fff" opacity=".7"/>`;
  [[620, 140, 8], [990, 170, 10], [840, 150, 6]].forEach(([x, y, r]) => s += sparkle(x, y, r, '#fff'));
  return s;
})()]);

// 4 MascotParade — original cute mascots in a row (poster 4)
B.push(['MascotParade', (() => {
  let s = `<defs>${dots('d4', '#FFD3E4', 20, 3)}</defs><rect width="1024" height="256" fill="#FFF7EC"/><rect width="1024" height="256" fill="url(#d4)" opacity=".7"/>`;
  // rainbow ribbon
  ['#FF9EC4', '#FFE07A', '#A7E9B8', '#9ED8F5', '#B9A6FF'].forEach((c, i) => s += `<path d="M400,${200 + i * 9} C560,${150 + i * 9} 760,${250 + i * 9} 1024,${180 + i * 9}" fill="none" stroke="${c}" stroke-width="9" stroke-linecap="round"/>`);
  s += `<text x="1000" y="54" text-anchor="end" font-family="Dela Gothic One" font-size="30" fill="${INK}">FAN CLUB</text>`;
  const gY = 200, sh = (x, w) => `<ellipse cx="${x}" cy="${gY + 2}" rx="${w}" ry="5" fill="${INK}" opacity=".15"/>`;
  // cassette buddy
  let x = 470; s += sh(x, 30) + `<g transform="translate(${x},${gY - 30})"><rect x="-32" y="-26" width="64" height="44" rx="6" fill="#9ED8F5" stroke="${INK}" stroke-width="3"/><rect x="-24" y="-18" width="48" height="22" rx="3" fill="#fff" stroke="${INK}" stroke-width="2"/>${face(0, -8, .8)}<path d="M-10,18 L-10,28 M10,18 L10,28" stroke="${INK}" stroke-width="3" stroke-linecap="round"/></g>`;
  // mic buddy
  x = 555; s += sh(x, 18) + `<g transform="translate(${x},${gY})"><rect x="-7" y="-50" width="14" height="48" rx="5" fill="#B9A6FF" stroke="${INK}" stroke-width="3"/><circle cx="0" cy="-72" r="26" fill="#FFF" stroke="${INK}" stroke-width="3"/><path d="M-22,-82 L22,-60 M-16,-92 L24,-72 M-24,-68 L14,-50" stroke="#E8E2F7" stroke-width="2"/>${face(0, -72, .9)}</g>`;
  // note buddy
  x = 640; s += sh(x, 22) + `<g transform="translate(${x},${gY})"><path d="M10,-30 L10,-104 Q34,-96 40,-78" fill="none" stroke="${INK}" stroke-width="5" stroke-linecap="round"/><ellipse cx="-4" cy="-24" rx="24" ry="20" fill="#FFE07A" stroke="${INK}" stroke-width="3"/>${face(-4, -26, .85)}</g>`;
  // star buddy (big, centre)
  x = 735; s += sh(x, 34) + `<g transform="translate(${x},${gY - 46})">${star(0, 0, 50, '#FF9EC4', 3.5, -6)}${face(0, 4, 1)}</g>`;
  // vinyl buddy
  x = 830; s += sh(x, 28) + `<g transform="translate(${x},${gY - 36})"><circle r="36" fill="#2C2A40" stroke="${INK}" stroke-width="3"/><circle r="27" fill="none" stroke="#4A4766" stroke-width="2"/><circle r="17" fill="#A7E9B8" stroke="${INK}" stroke-width="2.5"/>${face(0, -2, .65)}</g>`;
  // boba buddy
  x = 915; s += sh(x, 24) + `<g transform="translate(${x},${gY})"><line x1="6" y1="-86" x2="14" y2="-112" stroke="#FF5F7E" stroke-width="6" stroke-linecap="round"/><path d="M-26,-84 L26,-84 L20,0 L-20,0Z" fill="#FFE9CC" stroke="${INK}" stroke-width="3" stroke-linejoin="round"/><rect x="-30" y="-92" width="60" height="10" rx="4" fill="#FF9EC4" stroke="${INK}" stroke-width="3"/><circle cx="-8" cy="-12" r="5" fill="#5A3B2E"/><circle cx="6" cy="-10" r="5" fill="#5A3B2E"/><circle cx="-1" cy="-20" r="5" fill="#5A3B2E"/>${face(0, -52, .8)}</g>`;
  // lightstick buddy
  x = 990; s += sh(x, 16) + `<g transform="translate(${x},${gY})"><rect x="-6" y="-56" width="12" height="54" rx="5" fill="#fff" stroke="${INK}" stroke-width="3"/><circle cx="0" cy="-78" r="24" fill="#B9A6FF" stroke="${INK}" stroke-width="3"/>${heart(0, -78, 22, '#fff', 2)}</g>`;
  [[515, 105], [690, 70], [870, 100], [600, 60]].forEach(([hx, hy], i) => s += heart(hx, hy, 16 - i * 2, '#FF5F7E', 2, (i - 1) * 12));
  s += sparkle(960, 120, 8, '#FFE07A', INK, 1.5) + sparkle(445, 60, 9, '#B9A6FF', INK, 1.5);
  return s;
})()]);

// 5 PastelGem — gem emblem with florals (poster 5)
B.push(['PastelGem', (() => {
  let s = `<defs><linearGradient id="g5" x1="0" x2="1"><stop offset="0" stop-color="#FFE3EF"/><stop offset=".55" stop-color="#E9E0FF"/><stop offset="1" stop-color="#D6ECFF"/></linearGradient>
  <linearGradient id="f1" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFC6DE"/><stop offset="1" stop-color="#F48FB8"/></linearGradient>
  <linearGradient id="f2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#D8CCFF"/><stop offset="1" stop-color="#9F88F0"/></linearGradient>
  <linearGradient id="f3" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#CFEFFF"/><stop offset="1" stop-color="#8CC8EE"/></linearGradient>
  <filter id="b5"><feGaussianBlur stdDeviation="8"/></filter></defs>
  <rect width="1024" height="256" fill="url(#g5)"/>`;
  [[520, 60, 50, '#FFFFFF'], [880, 210, 70, '#FFC6DE'], [980, 40, 40, '#C9E6FF'], [650, 230, 40, '#E2D6FF']].forEach(([x, y, r, c]) => s += `<circle cx="${x}" cy="${y}" r="${r}" fill="${c}" opacity=".7" filter="url(#b5)"/>`);
  // big gem
  const gx = 760, gy = 128;
  s += `<g transform="translate(${gx},${gy})">
  <polygon points="-70,-34 -40,-64 40,-64 70,-34 0,74" fill="url(#f2)" stroke="#6F5AC8" stroke-width="3" stroke-linejoin="round"/>
  <polygon points="-70,-34 70,-34 0,74" fill="url(#f3)" opacity=".85"/>
  <polygon points="-40,-64 -20,-34 0,-64 20,-34 40,-64" fill="#FFFFFF" opacity=".6"/>
  <path d="M-70,-34 L70,-34 M-20,-34 L0,74 L20,-34 M-40,-64 L-20,-34 L0,-64 L20,-34 L40,-64" fill="none" stroke="#6F5AC8" stroke-width="2"/>
  ${flower(-28, 10, 22, 6, '#FFD6E8', '#FFE07A', 1.5)}${flower(18, 22, 14, 5, '#FFFFFF', '#FF9EC4', 1.5)}${flower(30, -14, 12, 5, '#C9E6FF', '#FFF', 1.5)}
  </g>`;
  // rays
  for (let i = 0; i < 5; i++) { const a = (-150 + i * 30) * Math.PI / 180; s += `<line x1="${gx + Math.cos(a) * 84}" y1="${gy - 30 + Math.sin(a) * 84}" x2="${gx + Math.cos(a) * 108}" y2="${gy - 30 + Math.sin(a) * 108}" stroke="#8C7BD8" stroke-width="3" stroke-linecap="round"/>`; }
  // heart gem left
  s += `<g transform="translate(600,140) rotate(-10)"><path d="M0 34 C -48 4 -40 -40 0 -18 C 40 -40 48 4 0 34 Z" fill="url(#f1)" stroke="#D4558F" stroke-width="3"/><path d="M-22,-24 L0,-18 L22,-24 M0,-18 L0,34 M-38,-4 L0,-18 L38,-4" fill="none" stroke="#fff" stroke-width="2" opacity=".7"/></g>`;
  // round gem right
  s += `<g transform="translate(910,110)"><circle r="34" fill="url(#f3)" stroke="#4F96C9" stroke-width="3"/><polygon points="0,-34 22,-10 0,34 -22,-10" fill="#fff" opacity=".4"/><path d="M-34,0 L-22,-10 L0,-34 L22,-10 L34,0 M-22,-10 L22,-10" fill="none" stroke="#4F96C9" stroke-width="2"/></g>`;
  s += flower(500, 200, 22, 6, '#FFD6E8', '#FFE07A', 2) + flower(990, 200, 20, 5, '#E2D6FF', '#fff', 2) + flower(670, 40, 14, 5, '#C9E6FF', '#fff', 2);
  [[540, 120, 9], [690, 220, 8], [850, 30, 10], [990, 120, 7], [450, 40, 7]].forEach(([x, y, r]) => s += sparkle(x, y, r, '#fff', '#8C7BD8', 1.5));
  return s;
})()]);

// 6 NeonSeoul — night street neon signs
B.push(['NeonSeoul', (() => {
  let s = `<defs><linearGradient id="g6" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#140F36"/><stop offset="1" stop-color="#3A1F6E"/></linearGradient>
  <filter id="neon" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
  <rect width="1024" height="256" fill="url(#g6)"/>`;
  for (let i = 0; i < 40; i++) s += `<circle cx="${rnd() * 1024}" cy="${rnd() * 120}" r="${rnd() * 1.4 + .4}" fill="#fff" opacity="${.3 + rnd() * .6}"/>`;
  s += `<circle cx="560" cy="48" r="22" fill="#FFF3C4" opacity=".95"/><circle cx="569" cy="42" r="20" fill="#1A1440"/>`;
  // buildings
  const bl = [[400, 150], [460, 110], [540, 140], [600, 70], [700, 100], [790, 60], [880, 120], [950, 80]];
  bl.forEach(([x, top], i) => {
    const w = (bl[i + 1] ? bl[i + 1][0] : 1024) - x;
    s += `<rect x="${x}" y="${top}" width="${w + 1}" height="${256 - top}" fill="${i % 2 ? '#1B1540' : '#221A4E'}"/>`;
    for (let wy = top + 12; wy < 230; wy += 16) for (let wx = x + 8; wx < x + w - 10; wx += 14) if (rnd() > .55) s += `<rect x="${wx}" y="${wy}" width="6" height="8" fill="${rnd() > .3 ? '#FFD98A' : '#8EE7FF'}" opacity=".75"/>`;
  });
  // neon signs
  s += `<g filter="url(#neon)"><rect x="612" y="78" width="46" height="140" rx="8" fill="#1B1540" stroke="#FF5FA8" stroke-width="3"/>
  <text x="635" y="114" text-anchor="middle" font-family="Black Han Sans" font-size="30" fill="#FFC2E0">노</text><text x="635" y="152" text-anchor="middle" font-family="Black Han Sans" font-size="30" fill="#FFC2E0">래</text><text x="635" y="190" text-anchor="middle" font-family="Black Han Sans" font-size="30" fill="#FFC2E0">방</text></g>`;
  s += `<g filter="url(#neon)"><rect x="720" y="112" width="150" height="50" rx="10" fill="#1B1540" stroke="#5FF2FF" stroke-width="3"/><text x="795" y="148" text-anchor="middle" font-family="Black Han Sans" font-size="30" fill="#CFFBFF">1:1 대결</text></g>`;
  s += `<g filter="url(#neon)"><text x="960" y="50" text-anchor="middle" font-family="Black Han Sans" font-size="30" fill="#FFF6C8">맞혀봐!</text></g>`;
  s += `<g filter="url(#neon)">${heart(925, 185, 40, 'none', 3, 0, '#FF5FA8')}<path d="M450,128 l14,0 l-6,12 l14,0" fill="none" stroke="#A7FFB8" stroke-width="3"/><circle cx="510" cy="190" r="12" fill="none" stroke="#B9A6FF" stroke-width="3"/></g>`;
  // wet street
  s += `<rect y="230" width="1024" height="26" fill="#120D2C"/>`;
  [[635, '#FF5FA8'], [795, '#5FF2FF'], [925, '#FF5FA8']].forEach(([x, c]) => s += `<rect x="${x - 20}" y="234" width="40" height="3" fill="${c}" opacity=".6"/><rect x="${x - 12}" y="242" width="24" height="2" fill="${c}" opacity=".4"/>`);
  return s;
})()]);

// 7 LightstickCrowd — concert crowd, spotlights
B.push(['LightstickCrowd', (() => {
  let s = `<defs><linearGradient id="g7" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1D1238"/><stop offset=".7" stop-color="#4A1E6E"/><stop offset="1" stop-color="#C2378F"/></linearGradient>
  <linearGradient id="beam" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></linearGradient>
  <filter id="glow7" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>
  <rect width="1024" height="256" fill="url(#g7)"/>`;
  [[600, -20, '#B9A6FF'], [780, -20, '#FF9EC4'], [960, -20, '#9ED8F5']].forEach(([x, y, c], i) => s += `<polygon points="${x - 8},0 ${x + 8},0 ${x + 90 - i * 60},256 ${x - 60 - i * 40},256" fill="url(#beam)" opacity=".5"/><polygon points="${x - 8},0 ${x + 8},0 ${x + 90 - i * 60},256 ${x - 60 - i * 40},256" fill="${c}" opacity=".12"/>`);
  for (let i = 0; i < 30; i++) s += `<rect x="${420 + rnd() * 600}" y="${rnd() * 160}" width="5" height="9" transform="rotate(${rnd() * 90} ${0} ${0})" fill="${['#FFE07A', '#FF9EC4', '#9ED8F5', '#A7E9B8'][i % 4]}" opacity=".85"/>`;
  // lightsticks
  const tops = ['heart', 'orb', 'star', 'orb', 'heart', 'star', 'orb', 'heart', 'orb', 'star', 'heart', 'orb'];
  const cols = ['#FF9EC4', '#B9A6FF', '#FFE07A', '#9ED8F5', '#A7E9B8'];
  tops.forEach((t, i) => {
    const x = 430 + i * 50 + (rnd() * 16 - 8), y = 120 + rnd() * 50, r = (rnd() - .5) * 30, c = cols[i % 5];
    s += `<g transform="translate(${x},${y}) rotate(${r})"><rect x="-3.5" y="0" width="7" height="70" rx="3" fill="#2C2440"/><g filter="url(#glow7)">${t === 'heart' ? heart(0, -10, 30, c, 2, 0, '#fff') : t === 'star' ? star(0, -10, 16, c, 2, 0, '#fff') : `<circle cy="-10" r="14" fill="${c}" stroke="#fff" stroke-width="2"/>`}</g></g>`;
  });
  // crowd heads
  for (let i = 0; i < 26; i++) { const x = 390 + i * 26 + rnd() * 6, y = 210 + rnd() * 12; s += `<circle cx="${x}" cy="${y}" r="15" fill="#140B26"/><rect x="${x - 17}" y="${y + 8}" width="34" height="40" rx="12" fill="#140B26"/>`; }
  return s;
})()]);

// 8 Mixtape — 70s stripes + cassette with unspooling tape
B.push(['Mixtape', (() => {
  let s = `<rect width="1024" height="256" fill="#FFF1DC"/>`;
  const st = ['#FF5F4E', '#FF9A3D', '#FFC94A', '#3DBEAA', '#2E6F8E'];
  st.forEach((c, i) => s += `<path d="M${380 + i * 34},256 C${520 + i * 34},256 ${560 + i * 34},${120 - i * 0} ${700 + i * 34},${120} L1024,120 L1024,${154 + 0}" fill="none" stroke="${c}" stroke-width="34"/>`);
  s = `<rect width="1024" height="256" fill="#FFF1DC"/>`;
  st.forEach((c, i) => { const o = i * 30; s += `<path d="M${400 + o},270 Q${470 + o},${110 + o} ${640 + o / 2},${100 + o} L1040,${100 + o}" fill="none" stroke="${c}" stroke-width="30"/>`; });
  s += `<path d="M400,270 Q470,110 640,100 L1040,100" fill="none" stroke="${INK}" stroke-width="2" transform="translate(0,-15)"/>`;
  // tape ribbon heart swirl
  s += `<path d="M760,150 C720,175 690,205 650,190 C610,175 630,135 665,150 C700,165 660,215 600,215 C560,215 545,190 520,185" fill="none" stroke="#3A2A20" stroke-width="5" stroke-linecap="round"/>`;
  s += cassette(840, 128, 200, -8, '#FF9EC4', '#FFF8E8', 'mixtape vol.7');
  s += `<g transform="translate(470,60) rotate(-10)"><rect x="-44" y="-17" width="88" height="34" rx="17" fill="#FFE07A" stroke="${INK}" stroke-width="3"/><text x="0" y="6" text-anchor="middle" font-family="Bungee" font-size="15" fill="${INK}">SIDE A</text></g>`;
  for (let i = 0; i < 16; i++) { const h = 8 + Math.abs(Math.sin(i * .9 + 1)) * 34; s += `<rect x="${960 + (i % 8) * 0}" y="0" width="0" height="0"/>`; }
  for (let i = 0; i < 14; i++) { const h = 8 + Math.abs(Math.sin(i * .9 + 1)) * 30; s += `<rect x="${430 + i * 9}" y="${120 - h / 2}" width="5" height="${h}" rx="2.5" fill="${INK}"/>`; }
  s += star(985, 40, 18, '#FFE07A', 3, 10) + sparkle(560, 30, 10, '#FF5F4E') + heart(990, 215, 26, '#FF5F4E', 3, 12);
  return s;
})()]);

// 9 PhotocardSwap — scattered holo photocards, tape, stickers
B.push(['PhotocardSwap', (() => {
  let s = `<defs><pattern id="grid9" width="24" height="24" patternUnits="userSpaceOnUse"><path d="M24,0 L0,0 0,24" fill="none" stroke="#ffffff55" stroke-width="1.5"/></pattern>
  <linearGradient id="holo" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FFD1EC"/><stop offset=".3" stop-color="#D2C6FF"/><stop offset=".6" stop-color="#BFF0F5"/><stop offset="1" stop-color="#FFF2B8"/></linearGradient></defs>
  <rect width="1024" height="256" fill="#FF9EC4"/><rect width="1024" height="256" fill="url(#grid9)"/>`;
  const pc = (x, y, r, fill, icon, label) => `<g transform="translate(${x},${y}) rotate(${r})"><rect x="-41" y="-55" width="88" height="118" rx="10" fill="${INK}"/><rect x="-45" y="-59" width="88" height="118" rx="10" fill="#FFF8EC" stroke="${INK}" stroke-width="3"/><rect x="-37" y="-51" width="72" height="84" rx="6" fill="${fill}" stroke="${INK}" stroke-width="2"/>${icon}<text x="-1" y="50" text-anchor="middle" font-family="Fredoka" font-weight="600" font-size="11" fill="${INK}">${label}</text></g>`;
  s += pc(520, 132, -12, '#9ED8F5', star(-1, -10, 22, '#FFE07A', 2.5), 'No. 01');
  s += pc(640, 120, 6, 'url(#holo)', heart(-1, -10, 44, '#FF5FA8', 2.5), 'HOLO ✦');
  s += pc(765, 136, -4, '#A7E9B8', `<path d="M4,-30 L4,4 M4,-30 Q20,-26 22,-14" fill="none" stroke="${INK}" stroke-width="4" stroke-linecap="round"/><ellipse cx="-6" cy="6" rx="12" ry="9" fill="#B9A6FF" stroke="${INK}" stroke-width="2.5"/>`, 'No. 07');
  s += pc(890, 118, 10, '#FFE07A', `<path d="M-22,0 L-22,-24 L-10,-12 L-1,-30 L8,-12 L20,-24 L20,0Z" fill="#FF9EC4" stroke="${INK}" stroke-width="2.5" stroke-linejoin="round"/>`, 'RARE');
  // washi tape
  const tape = (x, y, r, c) => `<rect x="${x - 26}" y="${y - 9}" width="52" height="18" transform="rotate(${r} ${x} ${y})" fill="${c}" opacity=".8"/>`;
  s += tape(640, 58, -8, '#FFF4A8') + tape(890, 52, 14, '#B9F0D0') + tape(510, 70, 20, '#CFE6FF');
  s += `<g transform="translate(985,200) rotate(12)"><circle r="30" fill="#FFE07A" stroke="${INK}" stroke-width="3"/>${face(0, -2, 1.1)}</g>`;
  s += `<text x="975" y="62" text-anchor="middle" font-family="Pacifico" font-size="26" fill="#fff" stroke="${INK}" stroke-width="1" transform="rotate(-8 975 62)">trade?</text>`;
  s += sparkle(455, 210, 10, '#fff', INK, 1.5) + sparkle(700, 228, 8, '#fff', INK, 1.5) + heart(830, 230, 20, '#FF5F4E', 2.5, -10);
  return s;
})()]);

// 10 CityPop — retro sunset, grid floor, chrome type
B.push(['CityPop', (() => {
  let s = `<defs><linearGradient id="sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2B1B5A"/><stop offset=".55" stop-color="#C2378F"/><stop offset="1" stop-color="#FF9A6B"/></linearGradient>
  <linearGradient id="sun" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFE07A"/><stop offset="1" stop-color="#FF5FA8"/></linearGradient>
  <linearGradient id="cp" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFFFFF"/><stop offset=".48" stop-color="#9ED8F5"/><stop offset=".52" stop-color="#3A5BD0"/><stop offset="1" stop-color="#FF9EC4"/></linearGradient>
  <clipPath id="sunclip"><circle cx="800" cy="150" r="88"/></clipPath></defs>
  <rect width="1024" height="256" fill="url(#sky)"/>`;
  for (let i = 0; i < 30; i++) s += `<circle cx="${400 + rnd() * 624}" cy="${rnd() * 90}" r="${rnd() + .4}" fill="#fff" opacity=".7"/>`;
  s += `<g clip-path="url(#sunclip)"><rect x="700" y="60" width="200" height="180" fill="url(#sun)"/>`;
  for (let i = 0; i < 6; i++) s += `<rect x="700" y="${150 + i * 14}" width="200" height="${3 + i * 1.5}" fill="#C2378F"/>`;
  s += `</g>`;
  // skyline
  const sk = [[560, 150], [590, 120], [615, 160], [650, 105], [680, 140], [910, 130], [940, 100], [970, 145], [995, 118]];
  sk.forEach(([x, t], i) => s += `<rect x="${x}" y="${t}" width="${i === 3 ? 24 : 28}" height="${180 - t}" fill="#3B1650"/>`);
  s += `<rect x="660" y="80" width="3" height="26" fill="#3B1650"/>`;
  // grid floor
  s += `<rect y="178" width="1024" height="78" fill="#2A0F45"/>`;
  for (let i = 0; i < 6; i++) { const y = 178 + Math.pow(i / 5, 1.8) * 78; s += `<line x1="380" y1="${y}" x2="1024" y2="${y}" stroke="#FF5FA8" stroke-width="2" opacity=".8"/>`; }
  for (let i = -10; i <= 10; i++) s += `<line x1="${800 + i * 22}" y1="178" x2="${800 + i * 110}" y2="256" stroke="#FF5FA8" stroke-width="2" opacity=".8"/>`;
  s += `<rect x="0" y="0" width="460" height="256" fill="url(#sky)" opacity="0"/>`;
  // chrome title
  s += `<g transform="skewX(-10)"><text x="560" y="96" font-family="Bungee" font-size="54" fill="#1E1B2E" transform="translate(4,4)">CITY POP</text><text x="560" y="96" font-family="Bungee" font-size="54" fill="url(#cp)" stroke="#fff" stroke-width="1.5">CITY POP</text></g>`;
  s += `<text x="575" y="122" font-family="Pacifico" font-size="20" fill="#FFE07A">night drive ♪</text>`;
  s += sparkle(990, 30, 9, '#fff') + sparkle(520, 50, 7, '#fff');
  return s;
})()]);

// ---------- page ----------
const fontCss = ['dela-gothic-one/400.css', 'pacifico/400.css', 'bungee/400.css', 'fredoka/600.css', 'black-han-sans/400.css']
  .map(f => `<link rel="stylesheet" href="file://${FONTS}/${f}">`).join('');
let html = `<!doctype html><html><head><meta charset="utf-8">${fontCss}<style>
body{margin:0;background:#FBF6EE;font-family:Fredoka}
.art{width:1024px;height:256px;display:block}
.prev{position:relative;width:1024px;height:256px;margin:22px;border:4px solid ${INK};border-radius:22px;overflow:hidden}
.prev svg{display:block}
.card{position:absolute;left:56px;top:56px;width:104px;height:140px;background:#fff;border:4px solid ${INK};border-radius:12px;box-shadow:7px 7px 0 ${INK};transform:rotate(-3deg)}
.lbl{position:absolute;left:190px;top:100px;padding:4px 16px;background:#FFF8EC;border:3px solid ${INK};border-radius:10px;font:600 30px Fredoka;color:${INK}}
#sheet{padding:10px 0;width:1076px}
</style></head><body>`;
B.forEach(([n, svg]) => html += `<svg id="art-${n}" class="art" viewBox="0 0 1024 256" xmlns="http://www.w3.org/2000/svg">${svg}</svg>`);
html += `<div id="sheet">`;
B.forEach(([n, svg]) => html += `<div class="prev"><svg viewBox="0 0 1024 256" width="1024" height="256">${svg.replace(/id="/g, `id="p${n}`).replace(/url\(#/g, `url(#p${n}`)}</svg><div class="card"></div><div class="lbl">${n}</div></div>`);
html += `</div></body></html>`;
fs.writeFileSync(__dirname + '/banners.html', html);
console.log(B.map(b => b[0]).join(', '));

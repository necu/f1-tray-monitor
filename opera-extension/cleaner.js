/*!
 * F1 Player Cleaner - bloqueo estricto de popups y anuncios
 * Licencia MIT. Ver LICENSE en la raiz del proyecto.
 *
 * Se ejecuta en el mundo de la pagina (world: MAIN) y en todos los frames,
 * antes de que el sitio cargue su propio JavaScript. Su objetivo es que el
 * reproductor quede limpio: sin pestanas nuevas, sin dialogos y sin capas
 * publicitarias a pantalla completa, sin romper el video legitimo.
 */
(() => {
  'use strict';

  if (window.__f1Cleaner) { return; }
  try {
    Object.defineProperty(window, '__f1Cleaner', { value: true });
  } catch (e) {
    window.__f1Cleaner = true;
  }

  // --- 1. Popups -----------------------------------------------------------
  // Algunos reproductores hacen window.open(...).focus(): devolvemos un objeto
  // inerte en lugar de null para que no salten errores en su propio codigo.
  const fakeWindow = {
    closed: false,
    focus() { },
    blur() { },
    close() { },
    postMessage() { },
    moveTo() { },
    resizeTo() { },
    print() { },
    alert() { },
    confirm() { return false; },
    prompt() { return null; },
    document: { write() { }, close() { }, open() { return this; } }
  };
  try {
    window.open = function () { return fakeWindow; };
  } catch (e) { /* propiedad no configurable */ }

  function isAllowed(node) {
    return !!(node && node.getAttribute && node.getAttribute('data-f1-allow') !== null);
  }

  function anchorOf(ev) {
    const target = ev.target;
    return target && target.closest ? target.closest('a[href]') : null;
  }

  // Enlaces que intentan abrir pestana nueva o llevarse la ventana fuera del
  // reproductor (suelen ser anuncios). Los enlaces marcados se respetan.
  function guardClick(ev) {
    const path = ev.composedPath ? ev.composedPath() : [];
    for (const node of path) {
      if (isAllowed(node)) { return; }
    }
    const anchor = anchorOf(ev);
    if (!anchor) { return; }

    const rawTarget = (anchor.getAttribute('target') || '').toLowerCase();
    const href = (anchor.getAttribute('href') || '').trim();
    const opensNew = rawTarget === '_blank' || rawTarget === '_new';
    const external = /^(https?:)?\/\//i.test(href) && !isSameSite(href);

    if (opensNew || external) {
      ev.preventDefault();
      ev.stopImmediatePropagation();
      if (opensNew) { anchor.removeAttribute('target'); }
    }
  }

  function isSameSite(value) {
    try {
      const url = new URL(value, location.href);
      const here = new URL(location.href);
      const a = url.hostname.replace(/^www\./, '');
      const b = here.hostname.replace(/^www\./, '');
      return a === b || a.endsWith('.' + b) || b.endsWith('.' + a);
    } catch (e) {
      return true;
    }
  }

  document.addEventListener('click', guardClick, true);
  document.addEventListener('auxclick', guardClick, true);
  document.addEventListener('contextmenu', (ev) => {
    // El menu contextual no se usa dentro del reproductor; evita el clasico
    // "abrir en pestana nueva" de los popunders.
    ev.preventDefault();
  }, true);

  // --- 2. Dialogos y salidas ----------------------------------------------
  try {
    window.alert = function () { };
    window.confirm = function () { return false; };
    window.prompt = function () { return null; };
  } catch (e) { }

  // Los anuncios preguntan "¿seguro que quieres salir?" para retenerte.
  try {
    window.onbeforeunload = null;
    window.onunload = null;
  } catch (e) { }
  window.addEventListener('beforeunload', (ev) => {
    ev.stopImmediatePropagation();
    delete ev.returnValue;
  }, true);
  window.addEventListener('unload', (ev) => ev.stopImmediatePropagation(), true);

  // Notificaciones push: muchos reproductores las usan para publicidad.
  try {
    if (window.Notification) {
      window.Notification.requestPermission = function () { return Promise.resolve('denied'); };
    }
  } catch (e) { }

  // --- 3. Capas publicitarias ---------------------------------------------
  const AD_HOSTS = [
    'doubleclick.net', 'googlesyndication.com', 'googleadservices.com',
    'adservice.google.com', 'amazon-adsystem.com', 'media.net',
    'popads.net', 'popcash.net', 'propellerads.com', 'propellerclick.com',
    'exoclick.com', 'exosrv.com', 'juicyads.com', 'trafficjunky.net',
    'adnium.com', 'clickadu.com', 'hilltopads.net', 'onclckds.com',
    'revcontent.com', 'mgid.com', 'taboola.com', 'outbrain.com',
    'adsterra.com', 'cpmstar.com', 'adcash.com', 'adspyglass.com',
    'pemsrv.com', 'coinhive.com', 'cointraffic.io',
    'adnxs.com', 'rubiconproject.com', 'pubmatic.com', 'openx.net',
    'criteo.com', 'criteo.net', 'smartadserver.com', 'yieldmo.com',
    'bidvertiser.com', 'clickaine.com', 'popmyads.com', 'tsyndicate.com',
    'pushnami.com', 'sendpulse.com', 'zergnet.com', 'spoutable.com',
    'admaven.com', 'ad-maven.com', 'monetizze.com.br', 'adf.ly'
  ];

  const AD_SELECTOR = [
    '[id*="popunder"]', '[class*="popunder"]',
    '[id*="popup-ad"]', '[class*="popup-ad"]',
    '[id*="ad-overlay"]', '[class*="ad-overlay"]',
    '[class*="adsbox"]', '[id*="adsbox"]',
    '[class*="ad-banner"]', '[class*="advert-banner"]',
    '[data-ad-slot]', '[data-ad-client]',
    '.adsbygoogle',
    'iframe[src*="ads"]', 'iframe[src*="banner"]', 'iframe[src*="promo"]',
    'ins.adsbygoogle', '[id^="google_ads_"]', '[id^="div-gpt-ad"]',
    '.ad-container', '.ad-wrapper', '.ads-container', '.advert',
    '[class*="sponsor-box"]', '[id*="sponsor-box"]'
  ].join(',');

  const AD_URL_HINTS = /(^|[\/._-])(ads?|advert|adserver|prebid|vast|preroll|popunder|banner)([\/._-]|$)/i;

  function hostOf(value) {
    try {
      return new URL(value, location.href).hostname.toLowerCase();
    } catch (e) {
      return '';
    }
  }

  function isAdHost(host) {
    return !!host && AD_HOSTS.some((ad) => host === ad || host.endsWith('.' + ad));
  }

  function isAdUrl(value) {
    if (!value) { return false; }
    const host = hostOf(value);
    if (isAdHost(host)) { return true; }
    try {
      const url = new URL(value, location.href);
      return AD_URL_HINTS.test(url.pathname + url.search);
    } catch (e) {
      return false;
    }
  }

  function isAdFrame(el) {
    if (!el || el.tagName !== 'IFRAME') { return false; }
    const src = el.getAttribute('src') || el.getAttribute('data-src') || '';
    return src ? isAdUrl(src) : false;
  }

  function hide(el) {
    if (!el || el.nodeType !== 1 || el.dataset.f1Hidden === '1') { return; }
    el.dataset.f1Hidden = '1';
    el.style.setProperty('display', 'none', 'important');
    el.style.setProperty('visibility', 'hidden', 'important');
    el.style.setProperty('pointer-events', 'none', 'important');
  }

  // Capa fija, enorme y con altisimo z-index que no contiene el video:
  // es el patron tipico de los overlays publicitarios. Se permite un boton
  // (los "continuar" falsos) pero nunca si hay un reproductor dentro.
  function looksLikeAdOverlay(el) {
    if (!el || el.nodeType !== 1) { return false; }
    if (el.querySelector('video, audio')) { return false; }
    const idc = ((el.id || '') + ' ' + (el.className || '')).toLowerCase();
    if (/player|video|jw-|vjs-|plyr|media|stream/.test(idc)) { return false; }
    if (!el.querySelector('iframe, ins, script')) { return false; }

    let style;
    try { style = getComputedStyle(el); } catch (e) { return false; }
    if (style.position !== 'fixed') { return false; }
    const z = parseInt(style.zIndex, 10);
    if (!Number.isFinite(z) || z < 900) { return false; }

    const r = el.getBoundingClientRect();
    const vw = window.innerWidth || document.documentElement.clientWidth || 0;
    const vh = window.innerHeight || document.documentElement.clientHeight || 0;
    if (vw <= 0 || vh <= 0) { return false; }
    return (r.width * r.height) > (vw * vh * 0.45);
  }

  // Banners de cookies/consentimiento que tapan el video. No se pulsan: solo
  // se ocultan cuando el reproductor ya esta cargado.
  const CONSENT_SELECTOR = [
    '#onetrust-banner-sdk', '#onetrust-consent-sdk',
    '.fc-consent-root', '.qc-cmp2-container',
    '[id*="cookie-consent"]', '[class*="cookie-consent"]',
    '[id*="cookiebanner"]', '[class*="cookie-banner"]',
    '[class*="consent-banner"]'
  ].join(',');

  function pauseAdMedia(root) {
    if (!root || !root.querySelectorAll) { return; }
    root.querySelectorAll('video, audio').forEach((m) => {
      if (isAdUrl(m.currentSrc || m.src || '')) {
        try { m.pause(); } catch (e) { }
        hide(m);
      }
    });
  }

  function sweep(root) {
    if (!root || !root.querySelectorAll) { return; }
    try {
      root.querySelectorAll(AD_SELECTOR).forEach(hide);
      root.querySelectorAll('iframe').forEach((f) => { if (isAdFrame(f)) { hide(f); } });
      if (document.querySelector('video')) {
        root.querySelectorAll(CONSENT_SELECTOR).forEach(hide);
      }
      root.querySelectorAll('body *').forEach((el) => {
        if (looksLikeAdOverlay(el)) { hide(el); }
      });
      pauseAdMedia(root);
    } catch (e) { /* DOM cambiando */ }
    acceptAgeGate();
  }

  // --- 4. Puertas de edad ---------------------------------------------------
  // Algunos reproductores piden confirmar la mayoria de edad antes de mostrar
  // el video. Se acepta automaticamente para que el reproductor quede listo
  // sin pasos intermedios. Solo actua si la pagina menciona la edad.
  const AGE_TEXT = /18\+|are you 18|are you over 18|mayor de edad|age verification|verify your age|adult content|contenido para adultos/;
  const AGE_BUTTON = /^(ok|yes|s[ií]|aceptar|accept|entrar|enter|continuar|continue|i am 18|tengo 18|s[ií],?\s*tengo 18)\b/i;

  function acceptAgeGate() {
    let text = '';
    try { text = (document.body && document.body.innerText || '').toLowerCase(); } catch (e) { return; }
    if (!AGE_TEXT.test(text)) { return; }
    const nodes = document.querySelectorAll('button, a, [role="button"], input[type="button"], input[type="submit"]');
    for (const el of nodes) {
      if (el.closest('#deck')) { continue; }
      const label = ((el.innerText || el.value || '') + ' ' + (el.getAttribute('aria-label') || '')).trim();
      if (AGE_BUTTON.test(label)) {
        try { el.click(); } catch (e) { }
        return;
      }
    }
    // Checkbox "tengo 18 anos" + boton de continuar.
    const checks = document.querySelectorAll('input[type="checkbox"]');
    for (const c of checks) {
      if (!c.checked) { try { c.click(); } catch (e) { } }
    }
  }

  let scheduled = false;
  function scheduleSweep() {
    if (scheduled) { return; }
    scheduled = true;
    requestAnimationFrame(() => {
      scheduled = false;
      sweep(document);
    });
  }

  function start() {
    sweep(document);
    try {
      const mo = new MutationObserver(scheduleSweep);
      mo.observe(document.documentElement, { childList: true, subtree: true });
    } catch (e) { }
    // Red de seguridad para overlays que se insertan con temporizadores.
    setInterval(() => sweep(document), 2000);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', start, { once: true });
  } else {
    start();
  }
})();

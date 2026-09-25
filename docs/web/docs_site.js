(function () {
  var frame = document.getElementById('frame'),
      loading = document.getElementById('loading'),
      side = document.getElementById('side'),
      sideRight = document.getElementById('side-right'),
      // the header's "Resource page" button - site target only, absent on local (see
      // docs_site.html), so every use of it is guarded
      resLink = document.getElementById('resourcelink');

  // point the "Resource page" button at the cloud twin of whatever is open
  function setTwin(id) {
    if (resLink) resLink.href = id ? (BASE + '/Documentation/' + id + '.html') : (BASE + '/');
  }
  // BASE = the deployed resource; we frame its live Documentation embed pages,
  // which carry the full notebook viewer (collapse, copy, every section).
  // HOME = the resource landing page (hero + examples). ROOT = the main guide.
  var BASE = '`BASE`', HOME = '`HOME`', PAGE = '`PAGE`', ROOT = '`ROOT`', cur = null;

  // The framed embed pages (and the home page) carry the resource's own header
  // and nav sidebar; hide those (same-origin) so only the content shows in our shell.
  // Also hide the front page's Paclet Source section (a Definition Notebook link
  // only useful to the paclet's author, not to readers) - a home-page-only id, so
  // the selector is safe globally.
  // NOT the Examples section. The shingle ships #nbCollapseExampleNotebook with an
  // EMPTY #example-notebook div and fills it client-side, from
  // <resource>/Genome-ExampleNotebook_embed.nb, through the notebook embedder. Hiding
  // that wrapper because it looked empty in the served HTML is what made the paclet's
  // front-page examples invisible inside this shell: they are the one thing on the
  // front page a reader comes for, and they arrive a moment after the frame loads.
  var HIDE = [
    '#pg-header,#pac-nav-sidebar,#pac-nav-sidebar-frame,.page-sidebar-frame,.page-sidebar,',
    '.page-sidebar-toggle,#pageSidebar,#pageSidebarFrame{display:none!important}',
    '.shingle-content,main.shingle-content{margin-left:0!important;max-width:none!important;width:auto!important}',
    // the embed page caps its column at 830px; inside this shell the page already sits between two
    // rails, so that cap only wastes the space and makes the live embed narrower than the
    // pre-render it replaces - a visible jump on every page load
    '.wrap{max-width:none!important;padding:0 24px!important;margin:0!important}',
    '#Paclet-Source,#Paclet-Source+ul{display:none!important}'
  ].join('');

  function injectHide() {
    try {
      var d = frame.contentDocument;
      if (!d || !d.head || d.getElementById('gn-hide-chrome')) return;
      var s = d.createElement('style');
      s.id = 'gn-hide-chrome';
      s.textContent = HIDE;
      d.head.appendChild(s);
    } catch (e) {}
  }

  function openAnc(a) {
    var n = a.parentNode;
    while (n && n !== side) { if (n.tagName === 'DETAILS') n.open = true; n = n.parentNode; }
  }
  function setActive(a) {
    if (cur) cur.classList.remove('active');
    cur = a;
    if (a) { a.classList.add('active'); openAnc(a); a.scrollIntoView({ block: 'nearest' }); }
  }
  // A guide can legitimately appear under every area that links it, so a data-id can match several
  // nav nodes. Blindly taking the first one highlights (and expands) the wrong branch. Collect
  // every match and prefer the one NEAREST what is already open: most <details> ancestors shared
  // with the current selection, then the shallowest. An explicit click passes its own element and
  // skips this entirely. (This paclet ships one guide today, so the loop degenerates to a single
  // hit - it stays because the rail is built from the guide-to-guide link graph and grows.)
  function chain(a) {
    var c = [], n = a && a.parentNode;
    while (n && n !== side && n !== sideRight) { if (n.tagName === 'DETAILS') c.unshift(n); n = n.parentNode; }
    return c;
  }
  function findLink(id) {
    var e = document.querySelectorAll('#side a[data-id], #side-right a[data-id]'), hits = [];
    for (var i = 0; i < e.length; i++) { if (e[i].getAttribute('data-id') === id) hits.push(e[i]); }
    if (hits.length < 2) return hits[0] || null;
    var ref = chain(cur), best = hits[0], bestScore = -1;
    for (var j = 0; j < hits.length; j++) {
      var c = chain(hits[j]), k = 0;
      while (k < c.length && k < ref.length && c[k] === ref[k]) k++;
      var score = k * 1000 - c.length;               // shared depth first, then shallower
      if (score > bestScore) { bestScore = score; best = hits[j]; }
    }
    return best;
  }
  function show() { loading.classList.add('on'); }

  // id is 'guide/X' | 'ref/Y' | 'tutorial/Z' -> the live cloud embed page
  function pageURL(id) { return BASE + '/Documentation/' + id + '.html'; }

  // ---- doc pages load through our own host page --------------------------------------------
  // PAGE is a standalone document (docs_page.html) that injects the /statichtml pre-render INTO
  // the container it then calls the embedder on - the repository pages' pattern, and the only
  // arrangement the embedder is happy in: it wants a window-scrolled document (hydrating it
  // inside an overflow:auto div froze its lazy rendering), and in-place hydration is what makes
  // the swap invisible. Empty PAGE (the local target) falls back to framing the built page.
  var staticEl = document.getElementById('static'), content = document.getElementById('content');
  function clearStatic() {
    if (staticEl) { staticEl.innerHTML = ''; staticEl.classList.remove('on'); }
    if (content) content.classList.remove('staged');
  }
  function frameURL(id) {
    return PAGE ? PAGE + '?p=' + encodeURIComponent(id) : pageURL(id);
  }
  // the host page hands doc-link clicks up instead of reloading itself blind
  window.addEventListener('message', function (e) {
    if (e.data && typeof e.data.genomeNav === 'string') load(e.data.genomeNav, true);
  });

  // id is 'guide/X' | 'ref/Y' | 'tutorial/Z'; el: the clicked nav node, focused as-is
  function load(id, push, el) {
    if (!/^(guide|ref\/format|ref|tutorial)\/[A-Za-z0-9]+$/.test(id)) return false;
    show();
    clearStatic();
    frame.src = frameURL(id);
    setActive(el || findLink(id));
    setTwin(id);
    if (push && location.hash !== '#' + id) history.pushState(null, '', '#' + id);
    return true;
  }
  function goHome(push) {
    show();
    clearStatic();
    frame.src = HOME;
    setActive(null);
    setTwin(null);
    if (push && location.hash !== '') history.pushState(null, '', '#');
  }

  // Route in-content links (same-origin) through the loader so navigation stays in
  // our shell. Matches both our re-hosted pages and any resource Documentation links.
  function hookFrame() {
    try {
      var d = frame.contentDocument;
      if (!d) return;
      var as = d.querySelectorAll('a[href]');
      for (var i = 0; i < as.length; i++) {
        (function (a) {
          if (a.__gn) return;
          var h = a.getAttribute('href') || '';
          var m = h.match(/\/(guide|ref\/format|ref|tutorial)\/([A-Za-z0-9]+)\.(?:html|nb)(?:[?#].*)?$/);
          if (m) {
            a.__gn = 1;
            a.addEventListener('click', function (e) { e.preventDefault(); load(m[1] + '/' + m[2], true); });
          }
        })(as[i]);
      }
    } catch (e) {}
  }

  frame.addEventListener('load', function () {
    loading.classList.remove('on');
    // the vendor embed pages (home, and every doc page on the local target) carry chrome to hide
    // and links to reroute; our own host page handles both itself
    if (!(PAGE && frame.src.indexOf(PAGE) === 0)) {
      injectHide();
      hookFrame();
      var n = 0, t = setInterval(function () { injectHide(); hookFrame(); if (++n > 10) clearInterval(t); }, 400);
    }
  });

  // ---- filter -------------------------------------------------------------
  // Hide non-matching entries in place: guides stay in the guide tree, tech notes under the
  // delimiter, symbols in the right rail. A guide matches when it or anything below it matches,
  // so its branch survives and opens; clearing the box restores the tree exactly as it was.
  var qBox = document.getElementById('q'), openState = null;

  function railEmptyNote(root, on) {
    var note = root.querySelector('.nav-empty');
    if (on && !note) {
      note = document.createElement('div');
      note.className = 'nav-empty';
      note.textContent = 'no matches';
      root.appendChild(note);
    } else if (!on && note) { note.parentNode.removeChild(note); }
  }

  function filterRail(root, term) {
    if (!root) return;
    var lis = root.querySelectorAll('li'), i, li, a, n;
    for (i = 0; i < lis.length; i++) lis[i].__hit = false;
    var as = root.querySelectorAll('a[data-id]');
    for (i = 0; i < as.length; i++) {
      a = as[i];
      // title AND the page's frontmatter keywords, so "haplogroup" finds Ancestry and
      // "drug response" finds Pharmacogenomics, whose titles say none of it
      if (!term || (a.textContent + ' ' + (a.getAttribute('data-kw') || '')).toLowerCase().indexOf(term) !== -1) {
        n = a.closest('li');
        while (n && root.contains(n)) {          // keep the whole ancestor chain visible
          n.__hit = true;
          n = n.parentElement && n.parentElement.closest('li');
        }
      }
    }
    for (i = 0; i < lis.length; i++) { li = lis[i]; li.style.display = li.__hit ? '' : 'none'; }
    var ds = root.querySelectorAll('details');
    for (i = 0; i < ds.length; i++) {
      if (!term) { ds[i].open = !!(openState && openState.get(ds[i])); }
      else { li = ds[i].closest('li'); if (li && li.__hit) ds[i].open = true; }
    }
    railEmptyNote(root, !!term && root.querySelectorAll('li[style*="none"]').length === lis.length);
  }

  function runFilter() {
    var term = (qBox.value || '').trim().toLowerCase();
    if (term && !openState) {                    // remember the tree shape before the first filter
      openState = new Map();
      var ds = side.querySelectorAll('details');
      for (var i = 0; i < ds.length; i++) openState.set(ds[i], ds[i].open);
    }
    filterRail(side, term);
    filterRail(sideRight, term);
    if (!term) openState = null;
  }

  if (qBox) {
    qBox.addEventListener('input', runFilter);
    qBox.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') { qBox.value = ''; runFilter(); qBox.blur(); }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key === '/' && document.activeElement !== qBox) { e.preventDefault(); qBox.focus(); }
    });
  }

  // ---- drawers (narrow screens) --------------------------------------------------------------
  // The rails are off-canvas below 900px; these toggles are inert on desktop because the buttons
  // are display:none there. Selecting a page closes the drawer, which is what a reader expects
  // after tapping a link.
  var scrim = document.getElementById('scrim'),
      navToggle = document.getElementById('navToggle'),
      symToggle = document.getElementById('symToggle');
  function closeDrawers() {
    side.classList.remove('open');
    if (sideRight) sideRight.classList.remove('open');
    if (scrim) scrim.classList.remove('on');
  }
  function toggleDrawer(el) {
    if (!el) return;
    var open = el.classList.contains('open');
    closeDrawers();
    if (!open) { el.classList.add('open'); if (scrim) scrim.classList.add('on'); }
  }
  if (navToggle) navToggle.addEventListener('click', function () { toggleDrawer(side); });
  if (symToggle) symToggle.addEventListener('click', function () { toggleDrawer(sideRight); });
  if (scrim) scrim.addEventListener('click', closeDrawers);
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') closeDrawers(); });

  // ---- rail splitters ------------------------------------------------------------------------
  // Drag either divider to rebalance the columns; double-click restores the default. Widths persist
  // per browser. Pointer events are captured on the splitter and the iframe is made inert for the
  // duration - otherwise the pointer crosses into the frame's document and the drag stops dead.
  var main = document.getElementById('main'), DEFAULTS = { side: 300, sideRight: 250 };
  function railWidth(el, px) {
    var min = el === side ? 200 : 160, max = Math.max(min, window.innerWidth * 0.45);
    el.style.width = Math.round(Math.min(max, Math.max(min, px))) + 'px';
  }
  function storeWidths() {
    try {
      localStorage.setItem('genome-rails', JSON.stringify({
        side: parseInt(side.style.width, 10) || DEFAULTS.side,
        sideRight: sideRight ? (parseInt(sideRight.style.width, 10) || DEFAULTS.sideRight) : DEFAULTS.sideRight
      }));
    } catch (e) {}
  }
  (function restoreWidths() {
    try {
      var w = JSON.parse(localStorage.getItem('genome-rails') || 'null');
      if (!w) return;
      if (w.side) railWidth(side, w.side);
      if (w.sideRight && sideRight) railWidth(sideRight, w.sideRight);
    } catch (e) {}
  })();
  function dragSplitter(handle, el, fromLeft) {
    if (!handle || !el) return;
    handle.addEventListener('pointerdown', function (e) {
      e.preventDefault();
      handle.setPointerCapture(e.pointerId);
      handle.classList.add('dragging');
      if (main) main.classList.add('resizing');
      var startX = e.clientX, startW = el.getBoundingClientRect().width;
      function move(ev) { railWidth(el, startW + (fromLeft ? ev.clientX - startX : startX - ev.clientX)); }
      function up(ev) {
        handle.releasePointerCapture(ev.pointerId);
        handle.classList.remove('dragging');
        if (main) main.classList.remove('resizing');
        handle.removeEventListener('pointermove', move);
        handle.removeEventListener('pointerup', up);
        storeWidths();
      }
      handle.addEventListener('pointermove', move);
      handle.addEventListener('pointerup', up);
    });
    handle.addEventListener('dblclick', function () {
      railWidth(el, el === side ? DEFAULTS.side : DEFAULTS.sideRight);
      storeWidths();
    });
    // keyboard: the splitter is focusable, so arrows should move it too
    handle.addEventListener('keydown', function (e) {
      var step = e.shiftKey ? 40 : 12, w = el.getBoundingClientRect().width;
      if (e.key === 'ArrowLeft') { railWidth(el, w + (fromLeft ? -step : step)); }
      else if (e.key === 'ArrowRight') { railWidth(el, w + (fromLeft ? step : -step)); }
      else return;
      e.preventDefault();
      storeWidths();
    });
  }
  dragSplitter(document.getElementById('splitL'), side, true);
  dragSplitter(document.getElementById('splitR'), sideRight, false);

  function navClick(e) {
    var a = e.target.closest && e.target.closest('a[data-id]');
    if (!a) return;
    e.preventDefault();
    load(a.getAttribute('data-id'), true, a);   // focus the clicked instance, not the first match
    closeDrawers();
  }
  side.addEventListener('click', navClick);
  if (sideRight) sideRight.addEventListener('click', navClick);
  // HOME is the resource shingle - the one documentation artifact that is not a Documentation
  // page, carrying the install line and the References. The brand in the header is the way back
  // to it; the rail lists only the Documentation pages.
  var brand = document.getElementById('homelink');
  if (brand) brand.addEventListener('click', function (e) { e.preventDefault(); goHome(true); });
  window.addEventListener('popstate', function () {
    var id = location.hash.slice(1);
    if (id) load(id, false); else goHome(false);
  });

  var s = location.hash.slice(1);
  if (!(s && load(s, false))) goHome(false);

  // Speed: the embed pages pull a ~535 KB notebook-renderer bundle (cacheable for
  // a year). Prefetch it up front via the embedding resolve so the first page
  // click doesn't pay that cost. The local target's relative BASE has no /obj/,
  // so this self-skips there.
  (function preloadEmbedder() {
    try {
      var i = BASE.indexOf('/obj/');
      if (i < 0) return;
      var origin = BASE.slice(0, i), path = BASE.slice(i + 5) + '/Documentation/guide/' + ROOT + '.nb';
      var x = new XMLHttpRequest();
      x.open('GET', origin + '/notebooks/embedding?path=' + encodeURIComponent(path), true);
      x.onload = function () {
        if (x.status !== 200) return;
        try {
          var d = JSON.parse(x.responseText);
          [d.mainScript].concat(d.otherScripts || []).forEach(function (sc) {
            var l = document.createElement('link');
            l.rel = 'prefetch'; l.href = origin + sc;
            document.head.appendChild(l);
          });
        } catch (e) {}
      };
      x.send();
    } catch (e) {}
  })();
})();

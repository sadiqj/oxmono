(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** JavaScript strings for client-side interactivity. *)

let sidenotes_js = {|
// Sidenote positioning - keeps sidenotes aligned with their references.
// Each sidenote is placed at the Y position of its in-article ref,
// relative to the sidenotes-container. If it would overlap the previous
// sidenote, it is pushed down to sit just below it.
function positionSidenotes() {
  const container = document.getElementById('sidenotes-container');
  if (!container || window.innerWidth < 1024) return;

  // Collect all sidenote divs in DOM order (matches ref order in article)
  const sidenotes = container.querySelectorAll('.sidenote');
  if (!sidenotes.length) return;

  const containerRect = container.getBoundingClientRect();
  const containerPageTop = containerRect.top + window.scrollY;
  let lastBottom = 0;

  sidenotes.forEach(sidenote => {
    const id = sidenote.id.replace('sidenote-', '');
    const ref = document.querySelector('.sidenote-ref[data-sidenote="' + id + '"]');
    if (!ref) return;

    // Where the ref is on the page, relative to the container
    const refRect = ref.getBoundingClientRect();
    const refPageTop = refRect.top + window.scrollY;
    let targetTop = refPageTop - containerPageTop;

    // Clamp: never go above 0 (above the container)
    if (targetTop < 0) targetTop = 0;

    // Prevent overlap with previous sidenote
    if (targetTop < lastBottom + 8) {
      targetTop = lastBottom + 8;
    }

    sidenote.style.top = targetTop + 'px';

    // Use getBoundingClientRect for accurate height after positioning
    lastBottom = targetTop + sidenote.getBoundingClientRect().height;
  });
}

// Floating thumbnail overlay that follows cursor
var thumbOverlay = null;
function getThumbOverlay() {
  if (!thumbOverlay) {
    thumbOverlay = document.createElement('div');
    thumbOverlay.className = 'fixed pointer-events-none z-50 rounded shadow-lg border border-border-color bg-bg p-0.5 transition-opacity duration-150 opacity-0 overflow-hidden';
    thumbOverlay.style.width = '56px';
    thumbOverlay.style.height = '56px';
    document.body.appendChild(thumbOverlay);
  }
  return thumbOverlay;
}

function showThumbOverlay(src, e) {
  const ov = getThumbOverlay();
  ov.innerHTML = '<img src="' + src + '" style="width:100%;height:100%;object-fit:cover;border-radius:3px;">';
  ov.style.left = (e.clientX + 12) + 'px';
  ov.style.top = (e.clientY + 12) + 'px';
  ov.classList.remove('opacity-0');
  ov.classList.add('opacity-100');
}

function moveThumbOverlay(e) {
  if (!thumbOverlay) return;
  thumbOverlay.style.left = (e.clientX + 12) + 'px';
  thumbOverlay.style.top = (e.clientY + 12) + 'px';
}

function hideThumbOverlay() {
  if (!thumbOverlay) return;
  thumbOverlay.classList.remove('opacity-100');
  thumbOverlay.classList.add('opacity-0');
}

// Sidenote hover interaction
function setupSidenoteHover() {
  document.querySelectorAll('.sidenote').forEach(sidenote => {
    const id = sidenote.id.replace('sidenote-', '');
    const ref = document.querySelector('.sidenote-ref[data-sidenote="' + id + '"]');
    if (!ref) return;
    // Find thumbnail src stored as data attr (not rendered in DOM)
    const thumbSrc = sidenote.dataset.thumb || '';

    function activate(e) {
      sidenote.classList.add('!border-accent', '!text-text');
      ref.classList.add('highlighted');
      if (thumbSrc) showThumbOverlay(thumbSrc, e);
    }
    function deactivate() {
      sidenote.classList.remove('!border-accent', '!text-text');
      ref.classList.remove('highlighted');
      hideThumbOverlay();
    }

    sidenote.addEventListener('mouseenter', activate);
    sidenote.addEventListener('mousemove', moveThumbOverlay);
    sidenote.addEventListener('mouseleave', deactivate);

    // Inline refs highlight sidenote but do NOT show thumbnail
    function activateNoThumb() {
      sidenote.classList.add('!border-accent', '!text-text');
      ref.classList.add('highlighted');
    }
    ref.addEventListener('mouseenter', activateNoThumb);
    ref.addEventListener('mouseleave', deactivate);

    const toggle = document.querySelector('.sidenote-toggle[data-sidenote="' + id + '"]');
    if (toggle) {
      toggle.addEventListener('mouseenter', activateNoThumb);
      toggle.addEventListener('mouseleave', deactivate);
    }
  });
}

// Setup sidenote numbers and mobile toggles.
// Deduplicates: only the first ref for a given sidenote gets a number.
// Subsequent refs for the same slug reuse the same number.
function setupSidenoteNumbers() {
  let noteNumber = 1;
  const seen = {};  // slug -> { number, inlineNote }
  document.querySelectorAll('.sidenote-ref').forEach(ref => {
    const id = ref.dataset.sidenote;
    const sidenote = document.getElementById('sidenote-' + id);
    if (!sidenote) return;

    // Determine the number: first occurrence gets a new one, duplicates reuse
    let currentNumber;
    let inlineNote;
    const isFirst = !seen[id];
    if (isFirst) {
      currentNumber = noteNumber++;
      // Add number prefix to sidebar sidenote (only once)
      const numberSpan = document.createElement('span');
      numberSpan.className = 'text-accent font-semibold';
      numberSpan.textContent = currentNumber + '. ';
      sidenote.insertBefore(numberSpan, sidenote.firstChild);
      // Create mobile inline note (only once per sidenote)
      inlineNote = document.createElement('div');
      inlineNote.className = 'hidden lg:!hidden sidenote-inline text-sm leading-relaxed text-text bg-surface border-l-2 border-accent px-3 py-2 my-2 rounded-r';
      inlineNote.id = 'sidenote-inline-' + id;
      inlineNote.innerHTML = '<span class="text-accent font-semibold">' + currentNumber + '.</span> ' + sidenote.innerHTML.replace(/<span class="text-accent.*?<\/span>/, '');
      const paragraph = ref.closest('p, blockquote, li');
      if (paragraph && !document.getElementById('sidenote-inline-' + id)) {
        paragraph.insertAdjacentElement('afterend', inlineNote);
      }
      seen[id] = { number: currentNumber, inlineNote: inlineNote };
    } else {
      currentNumber = seen[id].number;
      inlineNote = seen[id].inlineNote;
    }

    // Add toggle badge to every ref (shows the same number)
    const toggle = document.createElement('span');
    toggle.className = 'sidenote-toggle inline-block w-4 h-4 text-[0.55rem] leading-4 text-center bg-surface-alt border border-border-color rounded-full text-muted ml-0.5 font-medium transition-colors duration-200 hover:bg-surface hover:border-faint cursor-pointer lg:cursor-default';
    toggle.textContent = currentNumber;
    toggle.dataset.sidenote = id;
    const anchor = ref.closest('.sidenote-anchor');
    if (anchor) anchor.appendChild(toggle);
    toggle.addEventListener('click', (e) => {
      e.stopPropagation();
      const wasActive = toggle.classList.contains('!bg-accent');
      document.querySelectorAll('.sidenote-toggle').forEach(t => t.classList.remove('!bg-accent', '!border-accent', '!text-white'));
      document.querySelectorAll('.sidenote-inline').forEach(n => n.classList.add('hidden'));
      if (!wasActive) {
        toggle.classList.add('!bg-accent', '!border-accent', '!text-white');
        inlineNote.classList.remove('hidden');
      }
    });
  });
  document.addEventListener('click', (e) => {
    if (!e.target.closest('.sidenote-toggle') && !e.target.closest('.sidenote-inline')) {
      document.querySelectorAll('.sidenote-toggle').forEach(t => t.classList.remove('!bg-accent', '!border-accent', '!text-white'));
      document.querySelectorAll('.sidenote-inline').forEach(n => n.classList.add('hidden'));
    }
  });
}

window.addEventListener('load', () => {
  // Setup numbers/toggles (modifies DOM)
  setupSidenoteNumbers();
  // Position after layout settles
  requestAnimationFrame(() => {
    positionSidenotes();
    setupSidenoteHover();
  });
  // Re-position again after images/fonts finish loading
  setTimeout(positionSidenotes, 500);
});
window.addEventListener('resize', positionSidenotes);
window.addEventListener('scroll', positionSidenotes, { passive: true });
|}

let toc_js = {|
// Table of Contents functionality (desktop only)
function setupTOC() {
  if (window.innerWidth < 1024) return;
  const tocRow = document.getElementById('toc-row');
  const navNotes = document.getElementById('nav-notes');
  const tocLinks = document.querySelectorAll('.toc-link');
  if (!tocRow) return;

  const sectionIds = [];
  tocLinks.forEach(link => { sectionIds.push(link.getAttribute('href').slice(1)); });
  const sectionElements = sectionIds.map(id => document.getElementById(id)).filter(Boolean);

  let tocVisible = false;
  const showThreshold = 200;

  function updateTOC() {
    const scrollY = window.scrollY;
    const header = document.getElementById('header');
    const headerHeight = header ? header.offsetHeight : 0;

    if (scrollY > showThreshold && !tocVisible) {
      tocVisible = true;
      tocRow.classList.add('visible');
      if (navNotes) navNotes.classList.add('emphasized');
    } else if (scrollY <= showThreshold && tocVisible) {
      tocVisible = false;
      tocRow.classList.remove('visible');
      if (navNotes) navNotes.classList.remove('emphasized');
    }

    const atBottom = (scrollY + window.innerHeight) >= document.documentElement.scrollHeight - 5;
    let currentIndex = 0;
    let progressInSection = 0;
    if (atBottom) {
      currentIndex = sectionElements.length - 1;
      progressInSection = 100;
    } else {
      for (let i = sectionElements.length - 1; i >= 0; i--) {
        const el = sectionElements[i];
        if (el && el.getBoundingClientRect().top <= headerHeight + 50) {
          currentIndex = i;
          const sectionTop = el.getBoundingClientRect().top + scrollY - headerHeight;
          const nextEl = sectionElements[i + 1];
          const sectionBottom = nextEl
            ? nextEl.getBoundingClientRect().top + scrollY - headerHeight
            : document.documentElement.scrollHeight;
          const sectionHeight = sectionBottom - sectionTop;
          const scrollInSection = scrollY - sectionTop + headerHeight;
          progressInSection = Math.min(Math.max((scrollInSection / sectionHeight) * 100, 0), 100);
          break;
        }
      }
    }

    let activeLink = null;
    tocLinks.forEach((link, index) => {
      const linkIndex = parseInt(link.dataset.index);
      link.classList.remove('passed', 'active');
      if (linkIndex < currentIndex) {
        link.classList.add('passed');
        link.style.setProperty('--progress', '100%');
      } else if (linkIndex === currentIndex) {
        link.classList.add('active');
        link.style.setProperty('--progress', progressInSection + '%');
        activeLink = link;
      } else {
        link.style.setProperty('--progress', '0%');
      }
    });

    // Scroll active TOC link into view horizontally
    if (activeLink && tocRow.scrollWidth > tocRow.clientWidth) {
      const linkLeft = activeLink.offsetLeft;
      const linkWidth = activeLink.offsetWidth;
      const rowWidth = tocRow.clientWidth;
      const scrollTarget = linkLeft - (rowWidth / 2) + (linkWidth / 2);
      tocRow.scrollTo({ left: scrollTarget, behavior: 'smooth' });
    }
  }

  const scrollToSection = (targetId) => {
    const target = document.getElementById(targetId);
    if (target) {
      const header = document.getElementById('header');
      const headerHeight = header ? header.offsetHeight : 0;
      const targetPosition = target.getBoundingClientRect().top + window.scrollY - headerHeight - 20;
      window.scrollTo({ top: targetPosition, behavior: 'smooth' });
    }
  };

  tocLinks.forEach(link => {
    link.addEventListener('click', (e) => {
      e.preventDefault();
      scrollToSection(link.getAttribute('href').slice(1));
    });
  });

  const tocRoot = document.getElementById('toc-root');
  if (tocRoot) {
    tocRoot.addEventListener('click', (e) => {
      e.preventDefault();
      scrollToSection('intro');
    });
  }

  window.addEventListener('scroll', updateTOC, { passive: true });
  updateTOC();
}

window.addEventListener('load', () => { setTimeout(setupTOC, 150); });
|}

let search_js = {|
// Search functionality
(function() {
  const toggleBtn = document.getElementById('search-toggle-btn');
  const overlay = document.getElementById('search-modal-overlay');
  if (!toggleBtn || !overlay) return;

  const input = overlay.querySelector('#search-input');
  const body = overlay.querySelector('#search-modal-body');
  const statusText = overlay.querySelector('.search-status-text');
  const filters = overlay.querySelectorAll('.search-filter');

  function openSearch() {
    overlay.classList.add('active');
    if (input) { input.value = ''; input.focus(); }
    document.body.style.overflow = 'hidden';
  }

  function closeSearch() {
    overlay.classList.remove('active');
    document.body.style.overflow = '';
  }

  toggleBtn.addEventListener('click', openSearch);
  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) closeSearch();
  });

  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
      e.preventDefault();
      if (overlay.classList.contains('active')) closeSearch();
      else openSearch();
    }
    if (e.key === 'Escape' && overlay.classList.contains('active')) closeSearch();
  });

  filters.forEach(f => {
    f.addEventListener('click', () => f.classList.toggle('active'));
  });
})();
|}

let hljs_init = {|
(function() {
  function updateHljsTheme() {
    var isDark = document.documentElement.classList.contains('dark');
    var light = document.getElementById('hljs-light');
    var dark = document.getElementById('hljs-dark');
    if (light && dark) {
      if (isDark) { light.disabled = true; dark.disabled = false; }
      else { light.disabled = false; dark.disabled = true; }
    }
  }
  updateHljsTheme();
  hljs.highlightAll();
  // Re-check theme when it changes
  var observer = new MutationObserver(function(mutations) {
    mutations.forEach(function(m) {
      if (m.attributeName === 'class') updateHljsTheme();
    });
  });
  observer.observe(document.documentElement, { attributes: true });
})();
|}

let pagination_js = {|
// Pagination - lazy load more entries
(function() {
  const article = document.querySelector('[data-pagination="true"]');
  if (!article) return;

  const totalCount = parseInt(article.dataset.totalCount || '0');
  const collectionType = article.dataset.collectionType || 'entries';
  const types = article.dataset.types || '';
  let currentCount = parseInt(article.dataset.currentCount || '0');
  let loading = false;

  function loadMore() {
    if (loading || currentCount >= totalCount) return;
    loading = true;

    fetch('/api/pagination?collection=' + collectionType + '&type=' + encodeURIComponent(types) + '&offset=' + currentCount + '&limit=25')
      .then(r => r.json())
      .then(data => {
        if (data.html) {
          const temp = document.createElement('div');
          temp.innerHTML = data.html;
          while (temp.firstChild) article.appendChild(temp.firstChild);
          currentCount += data.count || 0;
          article.dataset.currentCount = currentCount;
          if (currentCount >= totalCount && sentinel) sentinel.remove();
        }
        loading = false;
      })
      .catch(() => { loading = false; });
  }

  if (currentCount < totalCount) {
    var sentinel = document.createElement('div');
    sentinel.style.height = '1px';
    article.after(sentinel);
    const observer = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting) loadMore();
    }, { rootMargin: '200px' });
    observer.observe(sentinel);
  }
})();
|}

let lightbox_js = {|
(function() {
  // Create lightbox overlay
  const overlay = document.createElement('div');
  overlay.id = 'lightbox-overlay';
  overlay.innerHTML = `
    <div class="lightbox-content">
      <img class="lightbox-img" />
      <div class="lightbox-below">
        <div class="lightbox-caption"></div>
        <div class="lightbox-downloads"></div>
      </div>
    </div>
    <button class="lightbox-close" aria-label="Close">&times;</button>
  `;
  document.body.appendChild(overlay);

  const img = overlay.querySelector('.lightbox-img');
  const caption = overlay.querySelector('.lightbox-caption');
  const downloads = overlay.querySelector('.lightbox-downloads');
  const closeBtn = overlay.querySelector('.lightbox-close');

  function open(trigger) {
    const src = trigger.dataset.lightbox;
    const cap = trigger.dataset.caption || '';
    let variants = [];
    try { variants = JSON.parse(trigger.dataset.variants || '[]'); } catch(e) {}

    img.src = src;
    img.alt = cap;
    caption.textContent = cap;
    caption.style.display = cap ? '' : 'none';

    // Build download links sorted by width descending
    variants.sort((a,b) => b.w - a.w);
    downloads.innerHTML = variants.map(v =>
      `<a href="${v.url}" download class="lightbox-dl">${v.w}&times;${v.h}</a>`
    ).join('');

    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
  }

  function close() {
    overlay.classList.remove('active');
    document.body.style.overflow = '';
    img.src = '';
  }

  // Attach to all lightbox triggers and expand buttons
  document.addEventListener('click', (e) => {
    const trigger = e.target.closest('.lightbox-trigger');
    if (trigger) { e.preventDefault(); open(trigger); return; }
    const expand = e.target.closest('.lightbox-expand');
    if (expand) { e.preventDefault(); e.stopPropagation(); open(expand); return; }
    if (e.target === overlay || e.target === closeBtn) { close(); }
  });

  overlay.addEventListener('click', (e) => {
    if (e.target === overlay) close();
  });

  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && overlay.classList.contains('active')) close();
  });
})();
|}

let theme_toggle_js = {|
(function() {
  var btn = document.getElementById('theme-toggle-btn');
  if (!btn) return;

  var iconSystem = btn.querySelector('.theme-icon-system');
  var iconLight = btn.querySelector('.theme-icon-light');
  var iconDark = btn.querySelector('.theme-icon-dark');

  function getEffective(pref) {
    if (pref === 'light') return 'light';
    if (pref === 'dark') return 'dark';
    return matchMedia('(prefers-color-scheme:dark)').matches ? 'dark' : 'light';
  }

  function apply(pref) {
    var eff = getEffective(pref);
    var html = document.documentElement;
    if (eff === 'dark') html.classList.add('dark');
    else html.classList.remove('dark');

    // Update meta theme-color
    var meta = document.getElementById('meta-theme-color');
    if (meta) meta.content = eff === 'dark' ? '#0d1117' : '#fffffc';

    // Update icons
    if (iconSystem && iconLight && iconDark) {
      iconSystem.classList.add('hidden');
      iconLight.classList.add('hidden');
      iconDark.classList.add('hidden');
      if (pref === 'light') iconLight.classList.remove('hidden');
      else if (pref === 'dark') iconDark.classList.remove('hidden');
      else iconSystem.classList.remove('hidden');
    }
  }

  // Read current preference
  var current = localStorage.getItem('theme') || 'system';
  apply(current);

  // Cycle: system -> light -> dark -> system
  btn.addEventListener('click', function() {
    var next;
    if (current === 'system') next = 'light';
    else if (current === 'light') next = 'dark';
    else next = 'system';
    current = next;
    if (next === 'system') localStorage.removeItem('theme');
    else localStorage.setItem('theme', next);
    apply(next);
  });

  // Listen for OS preference changes (only matters in system mode)
  matchMedia('(prefers-color-scheme:dark)').addEventListener('change', function() {
    if (!localStorage.getItem('theme')) apply('system');
  });
})();
|}

let status_filter_js = {|
// Idea status filter checkboxes
(function() {
  const checkboxes = document.querySelectorAll('.status-checkbox');
  if (!checkboxes.length) return;

  checkboxes.forEach(cb => {
    cb.addEventListener('change', () => {
      const status = cb.dataset.status;
      const items = document.querySelectorAll('.idea-item[data-status="' + status + '"]');
      items.forEach(item => {
        item.style.display = cb.checked ? '' : 'none';
      });
    });
  });
})();
|}

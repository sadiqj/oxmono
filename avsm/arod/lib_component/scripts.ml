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
    // Contact sidenotes have a CSS popover — skip the JS floating thumbnail
    const hasPopover = sidenote.querySelector('.contact-popover') !== null;

    function activate(e) {
      sidenote.classList.add('!border-accent', '!text-text');
      ref.classList.add('highlighted');
      if (thumbSrc && !hasPopover) showThumbOverlay(thumbSrc, e);
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

let links_modal_js = {|
(function() {
  var btn = document.getElementById('links-expand-btn');
  var overlay = document.getElementById('links-modal-overlay');
  if (!btn || !overlay) return;
  var closeBtn = document.getElementById('links-modal-close');
  function open() {
    overlay.classList.add('active');
    document.body.style.overflow = 'hidden';
  }
  function close() {
    overlay.classList.remove('active');
    document.body.style.overflow = '';
  }
  btn.addEventListener('click', open);
  if (closeBtn) closeBtn.addEventListener('click', close);
  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) close();
  });
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && overlay.classList.contains('active')) close();
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

    fetch('/api/entries?collection=' + collectionType + '&type=' + encodeURIComponent(types) + '&offset=' + currentCount + '&limit=25')
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

let classification_filter_js = {|
// Paper classification filter checkboxes
(function() {
  const checkboxes = document.querySelectorAll('.classification-checkbox');
  if (!checkboxes.length) return;

  checkboxes.forEach(cb => {
    cb.addEventListener('change', () => {
      const cls = cb.dataset.classification;
      const items = document.querySelectorAll('.paper-item[data-classification="' + cls + '"]');
      items.forEach(item => {
        item.style.display = cb.checked ? '' : 'none';
      });
    });
  });
})();
|}

let notes_calendar_js = {|
// Notes calendar — year heatmap + month grid, syncs with scroll
(function() {
  var container = document.getElementById('notes-calendar');
  if (!container) return;

  var data;
  try { data = JSON.parse(container.dataset.calendarMonths || '{}'); } catch(e) { return; }
  var currentMonth = container.dataset.currentMonth || '';
  var allMonths = Object.keys(data).sort().reverse();
  if (!allMonths.length) return;
  if (!currentMonth) currentMonth = allMonths[0];

  var heatmapEl = container.querySelector('.heatmap-strip');
  var headerEl = container.querySelector('.cal-header');
  var gridEl = container.querySelector('.cal-grid');

  var shortMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];

  // Determine today's YYYY-MM for future detection
  var now = new Date();
  var todayYM = now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0');

  // Compute a 12-month YYYY-MM key centered on currentMonth
  function ymAdd(ym, offset) {
    var parts = ym.split('-');
    var y = parseInt(parts[0]);
    var m = parseInt(parts[1]) - 1 + offset;
    var ny = y + Math.floor(m / 12);
    var nm = ((m % 12) + 12) % 12;
    return ny + '-' + String(nm + 1).padStart(2, '0');
  }

  // Count posts for a YYYY-MM key from the full data object
  function countForMonth(ym) {
    return data[ym] ? data[ym].length : 0;
  }

  // Build the 12-month window: 5 months before currentMonth, currentMonth, 6 months after
  function getHeatmapWindow() {
    var window = [];
    for (var i = -5; i <= 6; i++) {
      window.push(ymAdd(currentMonth, i));
    }
    return window;
  }

  // Render year heatmap — 12 months around currentMonth
  function renderHeatmap() {
    heatmapEl.innerHTML = '';
    var windowMonths = getHeatmapWindow();
    var maxCount = 1;
    windowMonths.forEach(function(ym) {
      var c = countForMonth(ym);
      if (c > maxCount) maxCount = c;
    });

    var strip = document.createElement('div');
    strip.className = 'heatmap-grid';
    windowMonths.forEach(function(ym) {
      var count = countForMonth(ym);
      var parts = ym.split('-');
      var month = parseInt(parts[1]);
      var isFuture = ym > todayYM;
      var cell = document.createElement('div');
      cell.className = 'heatmap-cell';
      if (ym === currentMonth) cell.classList.add('heatmap-current');

      if (isFuture) {
        cell.dataset.state = 'future';
        cell.dataset.level = 0;
        cell.title = shortMonths[month - 1] + ': upcoming';
      } else if (count === 0) {
        cell.dataset.state = 'empty';
        cell.dataset.level = 0;
        cell.title = shortMonths[month - 1] + ': no notes';
      } else {
        cell.dataset.state = 'active';
        var level = Math.min(4, Math.ceil(count / maxCount * 4));
        cell.dataset.level = level;
        cell.title = shortMonths[month - 1] + ': ' + count + ' note' + (count !== 1 ? 's' : '');
      }

      if (!isFuture) {
        (function(targetYm) {
          cell.addEventListener('click', function() {
            currentMonth = targetYm;
            renderMonth(currentMonth);
            renderHeatmap();
            var section = document.getElementById('month-' + targetYm);
            if (section) section.scrollIntoView({ behavior: 'smooth', block: 'start' });
          });
        })(ym);
      }

      var label = document.createElement('span');
      label.className = 'heatmap-label';
      label.textContent = shortMonths[month - 1];

      // Single circle: colored background (heatmap) with count or icon inside
      var circle = document.createElement('div');
      circle.className = 'heatmap-circle';
      if (isFuture) {
        circle.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12a9 9 0 1 0 18 0a9 9 0 0 0 -18 0"/><path d="M12 7v5l3 3"/></svg>';
      } else if (count === 0) {
        circle.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round"><path d="M5 12h14"/></svg>';
      } else {
        circle.textContent = count;
      }

      cell.appendChild(label);
      cell.appendChild(circle);
      strip.appendChild(cell);
    });
    heatmapEl.appendChild(strip);
  }

  function daysInMonth(y, m) {
    return new Date(y, m, 0).getDate();
  }

  function firstDayOfWeek(y, m) {
    var d = new Date(y, m - 1, 1).getDay();
    return d === 0 ? 6 : d - 1;
  }

  function renderMonth(ym) {
    var parts = ym.split('-');
    var year = parseInt(parts[0]);
    var month = parseInt(parts[1]);
    var days = data[ym] || [];
    var daySet = new Set(days);
    var total = daysInMonth(year, month);
    var offset = firstDayOfWeek(year, month);

    headerEl.innerHTML = '';
    var prevBtn = document.createElement('button');
    prevBtn.className = 'cal-nav';
    prevBtn.textContent = '\u25C0';
    prevBtn.addEventListener('click', function() { navigate(-1); });
    var nextBtn = document.createElement('button');
    nextBtn.className = 'cal-nav';
    nextBtn.textContent = '\u25B6';
    nextBtn.addEventListener('click', function() { navigate(1); });
    var title = document.createElement('span');
    title.className = 'cal-title';
    title.textContent = shortMonths[month - 1] + ' ' + year;
    headerEl.appendChild(prevBtn);
    headerEl.appendChild(title);
    headerEl.appendChild(nextBtn);

    gridEl.innerHTML = '';
    var weekdays = ['Mo','Tu','We','Th','Fr','Sa','Su'];
    weekdays.forEach(function(wd) {
      var cell = document.createElement('span');
      cell.className = 'cal-weekday';
      cell.textContent = wd;
      gridEl.appendChild(cell);
    });

    for (var i = 0; i < offset; i++) {
      var empty = document.createElement('span');
      empty.className = 'cal-day cal-day-empty';
      gridEl.appendChild(empty);
    }

    for (var d = 1; d <= total; d++) {
      var cell = document.createElement('span');
      if (daySet.has(d)) {
        cell.className = 'cal-day cal-day-active';
        cell.textContent = d;
        (function(day) {
          cell.addEventListener('click', function() {
            var id = 'note-' + ym + '-' + String(day).padStart(2, '0');
            var el = document.getElementById(id);
            if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
          });
        })(d);
      } else {
        cell.className = 'cal-day cal-day-empty';
        cell.textContent = d;
      }
      gridEl.appendChild(cell);
    }

    // Pad to 6 rows (42 cells) to keep constant height
    var totalCells = offset + total;
    while (totalCells < 42) {
      var pad = document.createElement('span');
      pad.className = 'cal-day cal-day-pad';
      gridEl.appendChild(pad);
      totalCells++;
    }
  }

  function navigate(dir) {
    var idx = allMonths.indexOf(currentMonth);
    var next = idx - dir;
    if (next >= 0 && next < allMonths.length) {
      currentMonth = allMonths[next];
      renderMonth(currentMonth);
      renderHeatmap();
    }
  }

  renderHeatmap();
  renderMonth(currentMonth);

  // Scroll tracking
  var sections = document.querySelectorAll('[data-month-id]');
  if (sections.length && 'IntersectionObserver' in window) {
    var observer = new IntersectionObserver(function(entries) {
      entries.forEach(function(entry) {
        if (entry.isIntersecting) {
          var monthId = entry.target.dataset.monthId;
          if (monthId && monthId !== currentMonth) {
            currentMonth = monthId;
            renderMonth(currentMonth);
            renderHeatmap();
          }
        }
      });
    }, { rootMargin: '-80px 0px -60% 0px' });
    sections.forEach(function(s) { observer.observe(s); });
  }
})();
|}

let tag_cloud_filter_js = {|
// Tag cloud filter for notes list
(function() {
  var buttons = document.querySelectorAll('.tag-cloud-btn');
  if (!buttons.length) return;

  var activeTags = new Set();

  function applyFilter() {
    var items = document.querySelectorAll('.note-item');
    if (activeTags.size === 0) {
      items.forEach(function(item) { item.style.display = ''; });
      return;
    }
    items.forEach(function(item) {
      var itemTags = (item.dataset.tags || '').split(',').filter(Boolean);
      var match = false;
      itemTags.forEach(function(t) {
        if (activeTags.has(t)) match = true;
      });
      item.style.display = match ? '' : 'none';
    });
  }

  buttons.forEach(function(btn) {
    btn.addEventListener('click', function() {
      var tag = btn.dataset.tag;
      if (activeTags.has(tag)) {
        activeTags.delete(tag);
        btn.classList.remove('active');
      } else {
        activeTags.add(tag);
        btn.classList.add('active');
      }
      applyFilter();
    });
  });
})();
|}

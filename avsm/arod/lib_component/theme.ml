(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Design tokens and theme constants for the Arod site.

    CSS custom properties for light/dark mode, typography, and spacing. *)

(** {1 Tailwind CDN Config}

    Injected as an inline script after the Tailwind CDN <script> tag. *)

let tailwind_config = {|
    tailwind.config = {
      darkMode: 'class',
      theme: {
        extend: {
          fontFamily: {
            sans: ['system-ui', '-apple-system', 'sans-serif'],
            serif: ['"Source Serif 4"', 'Georgia', 'serif'],
          },
          colors: {
            bg: 'var(--color-bg)',
            text: 'var(--color-text)',
            link: 'var(--color-link)',
            'link-underline': 'var(--color-link-ul)',
            secondary: 'var(--color-secondary)',
            surface: 'var(--color-surface)',
            'surface-alt': 'var(--color-surface-alt)',
            muted: 'var(--color-muted)',
            faint: 'var(--color-faint)',
            dim: 'var(--color-dim)',
            accent: 'var(--color-accent)',
            'border-color': 'var(--color-border)',
          },
          fontSize: {
            'body': ['0.88rem', '1.45'],
          },
        }
      }
    }
|}

(** {1 Theme Init Script}

    Tiny synchronous script for <head> that prevents FOUC by applying
    the .dark class before any CSS/rendering happens. *)

let theme_init_js = {|
(function(){
  var t = localStorage.getItem('theme');
  if (t === 'dark' || (!t && matchMedia('(prefers-color-scheme:dark)').matches)) {
    document.documentElement.classList.add('dark');
  }
})();
|}

(** {1 Custom CSS}

    Styles that can't be expressed purely via Tw utilities:
    - CSS custom properties for light/dark mode
    - Source Serif 4 font import
    - Link underline styling with underline-offset
    - Blockquote green border
    - Sidenote CSS
    - Scrollbar-hide
    - TOC link gradient progress
    - Nav emphasis brackets *)

let custom_css = {|
@import url('https://fonts.googleapis.com/css2?family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;1,8..60,400&display=swap');

/* CSS Custom Properties for light/dark theming */
:root {
  --color-bg: #fffffc;
  --color-surface: #f6f8fa;
  --color-surface-alt: #f3f4f6;
  --color-nav-from: #f8faf8;
  --color-nav-to: #f6f8f6;
  --color-text: #000000;
  --color-secondary: #555555;
  --color-muted: #777777;
  --color-faint: #999999;
  --color-dim: #444444;
  --color-link: #090c8d;
  --color-link-ul: #bbbbff;
  --color-border: #e5e7eb;
  --color-border-nav: #e0e2e0;
  --color-border-light: #dddddd;
  --color-border-faint: #cccccc;
  --color-accent: #22c55e;
  --color-st-avail: #22c55e;
  --color-st-discuss: #3b82f6;
  --color-st-ongoing: #f59e0b;
  --color-st-done: #6b7280;
  --color-st-expired: #ef4444;
  --color-sidenote-ref: #333399;
  --color-highlight: #fde68a;
  --color-toc-bg: #e0e7ff;
  --color-bq-text: #4a4a4a;
}

.dark {
  --color-bg: #0d1117;
  --color-surface: #161b22;
  --color-surface-alt: #1c2128;
  --color-nav-from: #0d1117;
  --color-nav-to: #111518;
  --color-text: #e6edf3;
  --color-secondary: #8b949e;
  --color-muted: #6e7681;
  --color-faint: #8b949e;
  --color-dim: #b1bac4;
  --color-link: #7ee787;
  --color-link-ul: #2ea04366;
  --color-border: #30363d;
  --color-border-nav: #21262d;
  --color-border-light: #30363d;
  --color-border-faint: #21262d;
  --color-accent: #3fb950;
  --color-st-avail: #3fb950;
  --color-st-discuss: #58a6ff;
  --color-st-ongoing: #d29922;
  --color-st-done: #8b949e;
  --color-st-expired: #f85149;
  --color-sidenote-ref: #7ee787;
  --color-highlight: #634d15;
  --color-toc-bg: #1c2654;
  --color-bq-text: #b1bac4;
}

/* Base element styles — in @layer base so Tailwind utilities can override */
@layer base {
  html {
    scroll-behavior: smooth;
  }
  body {
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    font-size: 0.88rem;
    line-height: 1.45;
  }
  code {
    font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
    font-size: 0.78rem;
  }
  pre {
    font-size: 0.78rem;
    line-height: 1.5;
    background: var(--color-surface);
    border: 1px solid var(--color-border);
    border-radius: 4px;
    padding: 0.75rem 1rem;
    overflow-x: auto;
  }
  pre code {
    background: none;
    border: none;
    padding: 0;
    border-radius: 0;
  }
  :not(pre) > code {
    background: var(--color-surface-alt);
    padding: 0.15em 0.35em;
    border-radius: 3px;
    border: 1px solid var(--color-border);
  }
  a {
    color: var(--color-link);
    text-decoration: underline dotted;
    text-decoration-color: var(--color-link-ul);
    text-underline-offset: 2px;
  }
  a:hover {
    text-decoration-style: solid;
    text-decoration-color: var(--color-link);
  }
  blockquote {
    position: relative;
    border-left: 3px solid var(--color-accent);
    padding: 0.5rem 1rem;
    margin-left: 0;
    color: var(--color-bq-text);
    font-style: italic;
  }
  blockquote::before {
    content: "\201C";
    position: absolute;
    top: -0.2rem;
    left: 0.35rem;
    font-size: 2.5rem;
    line-height: 1;
    color: var(--color-accent);
    opacity: 0.18;
    font-style: normal;
    pointer-events: none;
  }
  blockquote cite {
    display: block;
    font-style: normal;
    font-size: 0.78rem;
    margin-top: 0.35rem;
    color: var(--color-muted);
    letter-spacing: 0.01em;
  }
  article p {
    margin-bottom: 1.1em;
  }
  article p:last-child {
    margin-bottom: 0;
  }
  figcaption {
    font-style: italic;
    font-size: 0.78rem;
    color: var(--color-secondary);
    margin-top: 0.3rem;
    line-height: 1.4;
  }
}

/* Component/utility styles — in @layer components so they override base but
   can still be overridden by utilities */
@layer components {
  a.no-underline, a.no-underline:hover {
    text-decoration: none;
  }
  .scrollbar-hide {
    -ms-overflow-style: none;
    scrollbar-width: none;
  }
  .scrollbar-hide::-webkit-scrollbar {
    display: none;
  }
  .sidenote-ref {
    cursor: help;
  }
  .sidenote-toggle {
    vertical-align: baseline;
    position: relative;
    top: -0.35em;
  }
  .sidenote-anchor {
    position: relative;
  }
  .toc-link {
    background: linear-gradient(to right, var(--color-toc-bg) 0%, var(--color-toc-bg) var(--progress, 0%), transparent var(--progress, 0%), transparent 100%);
    transition: all 0.15s ease;
  }
  .toc-link.passed {
    background: var(--color-toc-bg);
    color: var(--color-link);
  }
  .toc-link.active {
    color: var(--color-link);
    font-weight: 500;
  }
  .text-body { font-size: 0.88rem; line-height: 1.45; }
  .idea-available { color: var(--color-st-avail); font-weight: 500; }
  .idea-discussion { color: var(--color-st-discuss); font-weight: 500; }
  .idea-ongoing { color: var(--color-st-ongoing); font-weight: 500; }
  .idea-completed { color: var(--color-st-done); font-weight: 500; }
  .idea-expired { color: var(--color-st-expired); font-weight: 500; }
  /* Idea list page — project cards */
  .idea-project-card {
    margin-bottom: 2rem;
    padding-bottom: 1.5rem;
    border-bottom: 1px solid var(--color-border);
  }
  .idea-project-card:last-child { border-bottom: none; }
  .idea-project-body {
    margin-bottom: 0.75rem;
  }
  .idea-project-desc {
    margin-bottom: 0.5rem;
    color: var(--color-secondary);
  }
  .idea-view-project {
    display: inline-flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.78rem;
    font-weight: 500;
    color: var(--color-accent) !important;
    text-decoration: none !important;
    padding: 0.2rem 0.5rem 0.2rem 0.25rem;
    border: 1px solid var(--color-accent);
    border-radius: 3px;
    transition: background 0.15s, color 0.15s;
  }
  .idea-view-project:hover {
    background: var(--color-accent);
    color: var(--color-bg) !important;
  }
  /* Idea list items */
  .idea-list {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    margin-top: 0.75rem;
  }
  .idea-row {
    display: flex;
    align-items: flex-start;
    gap: 0.5rem;
    padding: 0.35rem 0.5rem;
    border-radius: 3px;
    transition: background 0.1s;
  }
  .idea-row:hover {
    background: var(--color-surface);
  }
  .idea-dot {
    display: inline-flex;
    align-items: center;
    flex-shrink: 0;
    margin-top: 0.35rem;
  }
  .idea-row-content {
    min-width: 0;
    flex: 1;
  }
  .idea-row-title {
    font-weight: 500;
    text-decoration: none !important;
    color: var(--color-text) !important;
  }
  .idea-row-title:hover {
    color: var(--color-link) !important;
    text-decoration: underline dotted !important;
    text-decoration-color: var(--color-link-ul) !important;
  }
  .idea-row-meta {
    display: block;
    font-size: 0.78rem;
    color: var(--color-secondary);
  }
  /* Idea sidebar — filter rows with inline stats */
  .idea-filter-row {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.05rem 0;
    cursor: pointer;
  }
  .idea-filter-row input[type="checkbox"] {
    flex-shrink: 0;
  }
  .idea-filter-row:has(input:not(:checked)) {
    opacity: 0.4;
  }
  .idea-filter-label {
    color: var(--color-dim);
    flex: 1;
  }
  .idea-stat-count {
    color: var(--color-secondary);
    font-variant-numeric: tabular-nums;
    font-size: 0.68rem;
  }
  /* Idea sidebar — project jump list */
  .idea-jump-list {
    display: flex;
    flex-direction: column;
  }
  .idea-jump-link {
    display: flex;
    align-items: center;
    padding: 0.15rem 0;
    color: var(--color-dim) !important;
    text-decoration: none !important;
    transition: color 0.1s;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.72rem;
  }
  .idea-jump-link:hover {
    color: var(--color-link) !important;
  }
  .idea-jump-title {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .idea-jump-count {
    color: var(--color-secondary);
    font-variant-numeric: tabular-nums;
    margin-left: 0.3rem;
    flex-shrink: 0;
  }
  .hash-prefix { opacity: 0.5; }
  /* Paper sidebar — filter rows and year jump */
  .paper-filter-row {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.05rem 0;
    cursor: pointer;
  }
  .paper-filter-row input[type="checkbox"] {
    flex-shrink: 0;
  }
  .paper-filter-row:has(input:not(:checked)) {
    opacity: 0.4;
  }
  .paper-filter-label {
    color: var(--color-dim);
    flex: 1;
  }
  .paper-stat-count {
    color: var(--color-secondary);
    font-variant-numeric: tabular-nums;
    font-size: 0.68rem;
  }
  .paper-full circle { fill: var(--color-accent); }
  .paper-short circle { fill: #e6a817; }
  .paper-preprint circle { fill: #8b8b8b; }
  .paper-jump-list {
    display: flex;
    flex-direction: column;
  }
  .paper-jump-link {
    display: flex;
    align-items: center;
    padding: 0.15rem 0;
    color: var(--color-dim) !important;
    text-decoration: none !important;
    transition: color 0.1s;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.72rem;
  }
  .paper-jump-link:hover {
    color: var(--color-link) !important;
  }
  .paper-jump-title {
    flex: 1;
    min-width: 0;
  }
  .paper-jump-count {
    color: var(--color-secondary);
    font-variant-numeric: tabular-nums;
    margin-left: 0.3rem;
    flex-shrink: 0;
  }
  /* Sidebar avatar thumbnails — text-sized */
  .sidebar-avatar-row {
    display: inline-flex;
    align-items: center;
    gap: 0.15rem;
    flex-wrap: nowrap;
    vertical-align: middle;
  }
  .sidebar-avatar-wrap {
    position: relative;
    display: inline-flex;
  }
  .sidebar-avatar-wrap-link {
    display: inline-flex;
  }
  .sidebar-avatar {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 0.9rem;
    height: 0.9rem;
    border-radius: 50%;
    overflow: hidden;
    border: 1px solid var(--color-border);
    background: var(--color-surface-alt);
    flex-shrink: 0;
    transition: border-color 0.15s, box-shadow 0.15s;
    cursor: pointer;
  }
  .sidebar-avatar-wrap:hover .sidebar-avatar {
    border-color: var(--color-accent);
    box-shadow: 0 0 0 1px var(--color-accent);
  }
  .sidebar-avatar-img {
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: 50%;
  }
  .sidebar-avatar-initials {
    font-size: 0.38rem;
    font-weight: 700;
    color: var(--color-muted);
    line-height: 1;
    text-transform: uppercase;
    letter-spacing: -0.03em;
  }
  /* Contact popover card — hover-triggered */
  .contact-popover {
    display: none;
    position: absolute;
    left: 50%;
    bottom: calc(100% + 1px);
    transform: translateX(-50%);
    z-index: 50;
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 5px;
    box-shadow: 0 4px 16px rgba(0,0,0,0.15);
    padding: 0.25rem 0.4rem;
    width: max-content;
    max-width: 14rem;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.72rem;
    line-height: 1.35;
  }
  /* Invisible bridge so mouse can travel from avatar to popover */
  .contact-popover::after {
    content: "";
    position: absolute;
    top: 100%;
    left: 0;
    width: 100%;
    height: 6px;
  }
  /* Small arrow on the bridge */
  .contact-popover::before {
    content: "";
    position: absolute;
    top: 100%;
    left: 50%;
    transform: translateX(-50%);
    border: 5px solid transparent;
    border-top-color: var(--color-border);
  }
  .sidebar-avatar-wrap:hover .contact-popover,
  .sidenote:hover .contact-popover {
    display: block;
  }
  /* Sidenote popover positions above the sidenote text */
  .sidenote .contact-popover {
    left: 0;
    transform: none;
    bottom: calc(100% + 2px);
  }
  .sidenote .contact-popover::before {
    left: 1rem;
    transform: none;
  }
  .sidenote .contact-popover::after {
    left: 0;
  }
  .popover-row {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }
  .popover-photo {
    width: 1.8rem;
    height: 1.8rem;
    border-radius: 50%;
    object-fit: cover;
    border: 1px solid var(--color-border);
    flex-shrink: 0;
  }
  .popover-photo-initials {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 1.8rem;
    height: 1.8rem;
    border-radius: 50%;
    background: var(--color-surface-alt);
    border: 1px solid var(--color-border);
    font-size: 0.6rem;
    font-weight: 700;
    color: var(--color-muted);
    text-transform: uppercase;
    flex-shrink: 0;
  }
  .popover-info {
    min-width: 0;
  }
  .popover-name {
    font-weight: 600;
    color: var(--color-text) !important;
    text-decoration: none !important;
    display: block;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .popover-org {
    display: block;
    color: var(--color-secondary);
    font-size: 0.65rem;
    margin: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .popover-socials {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    margin-top: 0.15rem;
    padding-top: 0.15rem;
    border-top: 1px dashed var(--color-border);
  }
  .popover-social-link {
    color: var(--color-muted) !important;
    text-decoration: none !important;
    display: inline-flex;
    transition: color 0.1s;
  }
  .popover-social-link:hover {
    color: var(--color-link) !important;
  }
  .sidebar-meta-box {
    font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
    font-size: 0.72rem;
    line-height: 1.5;
    border: 1px solid var(--color-border);
    border-left: 2px solid var(--color-accent);
    border-radius: 3px;
    background: var(--color-surface);
    overflow: visible;
  }
  .sidebar-meta-header {
    padding: 0.3rem 0.5rem;
    background: var(--color-surface-alt);
    border-bottom: 1px solid var(--color-border);
    border-radius: 3px 3px 0 0;
    color: var(--color-secondary);
  }
  .sidebar-meta-prompt {
    color: var(--color-accent);
    font-weight: 600;
  }
  .sidebar-meta-body {
    padding: 0.35rem 0.5rem;
  }
  .sidebar-meta-line {
    margin: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    display: flex;
    align-items: center;
  }
  .sidebar-meta-line:has(.sidebar-avatar-row) {
    overflow: visible;
  }
  .sidebar-meta-icon {
    display: inline-flex;
    align-items: center;
    color: var(--color-muted);
    margin-right: 0.3rem;
    flex-shrink: 0;
    vertical-align: middle;
  }
  .sidebar-meta-val {
    color: var(--color-dim);
  }
  .sidebar-meta-link {
    color: var(--color-dim) !important;
    text-decoration: underline dotted var(--color-border-faint) !important;
  }
  .sidebar-meta-synopsis {
    font-style: italic;
    color: var(--color-secondary);
    margin: 0 0 0.3rem 0;
    padding-bottom: 0.3rem;
    border-bottom: 1px dashed var(--color-border);
    white-space: normal;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.78rem;
    line-height: 1.4;
  }
  .sidebar-meta-link:hover {
    color: var(--color-link) !important;
    text-decoration-color: var(--color-link) !important;
    text-decoration-style: solid !important;
  }
  .sidebar-meta-links {
    margin-top: 0.25rem;
    padding-top: 0.25rem;
    border-top: 1px dashed var(--color-border);
  }
  .sidebar-meta-linkline {
    margin: 0;
    display: flex;
    align-items: center;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.72rem;
  }
  .sidebar-meta-expand {
    display: block;
    width: 100%;
    margin-top: 0.15rem;
    padding: 0.15rem 0;
    background: none;
    border: none;
    color: var(--color-muted);
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.72rem;
    cursor: pointer;
    text-align: left;
    transition: color 0.15s;
  }
  .sidebar-meta-expand:hover {
    color: var(--color-link);
  }
  .links-modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.55);
    z-index: 60;
    display: none;
    align-items: center;
    justify-content: center;
    padding: 2rem;
  }
  .links-modal-overlay.active { display: flex; }
  .links-modal {
    background: var(--color-bg);
    border: 1px solid var(--color-border);
    border-radius: 6px;
    width: 100%;
    max-width: 40rem;
    max-height: 80vh;
    display: flex;
    flex-direction: column;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.82rem;
    box-shadow: 0 8px 30px rgba(0,0,0,0.25);
  }
  .links-modal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--color-border);
    color: var(--color-secondary);
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
  .links-modal-close-btn {
    background: none;
    border: none;
    color: var(--color-muted);
    font-size: 1.1rem;
    cursor: pointer;
    line-height: 1;
    padding: 0 0.25rem;
  }
  .links-modal-close-btn:hover { color: var(--color-text); }
  .links-modal-body {
    overflow-y: auto;
    padding: 0.4rem 0;
  }
  .links-modal-row {
    display: flex;
    align-items: baseline;
    gap: 0.35rem;
    padding: 0.3rem 0.75rem;
    transition: background 0.1s;
  }
  .links-modal-row:hover {
    background: var(--color-surface);
  }
  .links-modal-icon {
    display: inline-flex;
    flex-shrink: 0;
    color: var(--color-muted);
  }
  .links-modal-link {
    color: var(--color-dim) !important;
    text-decoration: none !important;
    flex: 1;
    min-width: 0;
  }
  .links-modal-link:hover {
    color: var(--color-link) !important;
    text-decoration: underline dotted !important;
  }
  .links-modal-date {
    color: var(--color-faint);
    font-size: 0.65rem;
    flex-shrink: 0;
    margin-left: auto;
  }
  .references-block {
    border-left: 2px solid var(--color-link);
    border-radius: 0 3px 3px 0;
    padding: 0.6rem 0.85rem;
    font-size: 0.78rem;
    line-height: 1.5;
  }
  .ref-header {
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: var(--color-link);
    font-weight: 600;
    margin-bottom: 0.4rem;
    padding-bottom: 0.3rem;
    border-bottom: 1px dashed var(--color-border-light);
  }
  .ref-item {
    margin-bottom: 0.3rem;
    display: flex;
    gap: 0.35rem;
    align-items: baseline;
  }
  .ref-item:last-child { margin-bottom: 0; }
  .ref-num {
    color: var(--color-link);
    font-weight: 600;
    flex-shrink: 0;
  }
  .ref-body {
    color: var(--color-dim);
  }
  .ref-doi {
    font-size: 0.72rem;
    color: var(--color-faint) !important;
    text-decoration: none !important;
    word-break: break-all;
  }
  .ref-doi:hover {
    color: var(--color-link) !important;
    text-decoration: underline dotted !important;
  }
  .heading-number {
    color: var(--color-muted);
    font-weight: 400;
    font-variant-numeric: tabular-nums;
    text-decoration: none !important;
    transition: color 0.15s;
    margin-right: 0.15em;
  }
  .heading-number::after {
    content: "\2002\007C\2002";
    color: var(--color-border);
  }
  a.heading-number:hover { color: var(--color-link) !important; }
  /* Ensure floated images in article content clear properly */
  article::after, .space-y-4::after, .space-y-3::after {
    content: "";
    display: table;
    clear: both;
  }
  .lightbox-trigger { cursor: zoom-in; }
  figure img {
    border: 1px solid var(--color-border);
    border-radius: 3px;
  }
  .float-img {
    margin: 0;
  }
  .float-img img {
    border: 2px solid var(--color-secondary);
    transition: filter 0.3s ease, border-color 0.3s ease, box-shadow 0.3s ease;
  }
  .float-img:hover img {
    border-color: var(--color-accent);
    filter: saturate(0.3) contrast(1.1);
    box-shadow: 0 0 8px rgba(34,197,94,0.3);
  }
  .lightbox-expand {
    position: absolute;
    bottom: 2px;
    right: 2px;
    width: 1.25rem;
    height: 1.25rem;
    background: rgba(0,0,0,0.4);
    color: white;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-weight: bold;
    line-height: 1;
    cursor: zoom-in;
    opacity: 0;
    transition: opacity 0.15s;
    text-decoration: none !important;
    z-index: 5;
  }
  figure:hover .lightbox-expand {
    opacity: 0.7;
  }
  .lightbox-expand:hover {
    opacity: 1 !important;
    background: rgba(0,0,0,0.7);
  }
  #lightbox-overlay {
    position: fixed;
    inset: 0;
    z-index: 70;
    background: rgba(0,0,0,0.85);
    display: none;
    align-items: center;
    justify-content: center;
    flex-direction: column;
    padding: 2rem;
  }
  #lightbox-overlay.active { display: flex; }
  .lightbox-content {
    max-width: 90vw;
    max-height: 85vh;
    display: flex;
    flex-direction: column;
    align-items: center;
  }
  .lightbox-img {
    max-width: 90vw;
    max-height: 75vh;
    object-fit: contain;
    border-radius: 4px;
    box-shadow: 0 4px 30px rgba(0,0,0,0.4);
  }
  .lightbox-below {
    margin-top: 0.75rem;
    text-align: center;
    max-width: 90vw;
  }
  .lightbox-caption {
    color: #ddd;
    font-size: 0.85rem;
    margin-bottom: 0.5rem;
  }
  .lightbox-downloads {
    display: flex;
    gap: 0.4rem;
    flex-wrap: wrap;
    justify-content: center;
  }
  .lightbox-dl {
    font-family: ui-monospace, 'SF Mono', monospace;
    font-size: 0.7rem;
    color: #aaa !important;
    text-decoration: none !important;
    background: rgba(255,255,255,0.1);
    padding: 0.15rem 0.4rem;
    border-radius: 3px;
    transition: background 0.15s, color 0.15s;
  }
  .lightbox-dl:hover {
    background: rgba(255,255,255,0.25);
    color: #fff !important;
  }
  .lightbox-close {
    position: fixed;
    top: 1rem;
    right: 1.5rem;
    color: #999;
    font-size: 2rem;
    background: none;
    border: none;
    cursor: pointer;
    line-height: 1;
    transition: color 0.15s;
    z-index: 71;
  }
  .lightbox-close:hover { color: #fff; }
  .search-modal-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.5);
    z-index: 60;
    display: none;
  }
  .search-modal-overlay.active { display: flex; }
  .timeline-dot {
    background-color: var(--color-link);
  }
  .timeline-duration {
    background-color: var(--color-border-faint);
  }
  /* Compact note cards */
  .note-compact {
    padding: 0.35rem 0.5rem;
    border-radius: 3px;
    transition: background 0.1s;
  }
  .note-compact:hover {
    background: var(--color-surface);
  }
  .note-compact-row {
    display: flex;
    align-items: baseline;
    gap: 0.4rem;
  }
  .note-compact-title {
    flex: 1;
    min-width: 0;
    font-weight: 500;
    color: var(--color-text) !important;
    text-decoration: none !important;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .note-compact-title:hover {
    color: var(--color-link) !important;
    text-decoration: underline dotted !important;
    text-decoration-color: var(--color-link-ul) !important;
  }
  .note-compact-meta {
    flex-shrink: 0;
    font-size: 0.72rem;
    color: var(--color-secondary);
    white-space: nowrap;
    font-variant-numeric: tabular-nums;
  }
  .note-compact-synopsis {
    font-size: 0.78rem;
    color: var(--color-secondary);
    line-height: 1.4;
    margin-top: 0.1rem;
  }
  .note-compact-tags {
    display: flex;
    flex-wrap: wrap;
    gap: 0.2rem;
    margin-top: 0.15rem;
  }
  .note-tag-chip {
    font-size: 0.65rem;
    color: var(--color-muted);
    padding: 0 0.25rem;
    border: 1px solid var(--color-border);
    border-radius: 2px;
    line-height: 1.5;
  }
  .note-month-header {
    font-size: 1rem;
    font-weight: 600;
    margin-bottom: 0.5rem;
    border-bottom: 1px solid var(--color-border);
    padding-bottom: 0.25rem;
  }
  .note-month-list {
    display: flex;
    flex-direction: column;
    gap: 0.1rem;
  }
  /* Year heatmap strip */
  .heatmap-strip {
    margin-bottom: 0.15rem;
  }
  .heatmap-grid {
    display: grid;
    grid-template-columns: repeat(12, 1fr);
    gap: 0.15rem;
  }
  .heatmap-cell {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.15rem;
    cursor: pointer;
    padding: 0.15rem 0;
    border-radius: 2px;
    transition: background 0.1s;
  }
  .heatmap-cell:hover {
    background: var(--color-surface-alt);
  }
  .heatmap-cell.heatmap-current {
    background: var(--color-surface-alt);
    outline: 1.5px solid var(--color-dim);
    outline-offset: -1px;
    border-radius: 3px;
  }
  .heatmap-cell.heatmap-current .heatmap-label {
    color: var(--color-text);
    font-weight: 700;
  }
  .heatmap-label {
    font-size: 0.5rem;
    color: var(--color-muted);
    line-height: 1;
    letter-spacing: -0.03em;
  }
  /* Heatmap circle — single element: colored bg (heatmap) + count inside */
  .heatmap-circle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.15rem;
    height: 1.15rem;
    border-radius: 50%;
    font-size: 0.5rem;
    font-weight: 700;
    color: white;
    background: var(--color-border);
    line-height: 1;
    font-variant-numeric: tabular-nums;
    transition: background 0.15s, transform 0.1s;
  }
  .heatmap-cell:hover .heatmap-circle {
    transform: scale(1.15);
  }
  /* Green (idle) → orange → red (hot) gradient */
  .heatmap-cell[data-level="1"] .heatmap-circle { background: var(--color-accent); }
  .heatmap-cell[data-level="2"] .heatmap-circle { background: #b8a33a; }
  .heatmap-cell[data-level="3"] .heatmap-circle { background: #e08a30; }
  .heatmap-cell[data-level="4"] .heatmap-circle { background: #e04040; }
  .dark .heatmap-cell[data-level="1"] .heatmap-circle { background: var(--color-accent); }
  .dark .heatmap-cell[data-level="2"] .heatmap-circle { background: #a09030; }
  .dark .heatmap-cell[data-level="3"] .heatmap-circle { background: #c07828; }
  .dark .heatmap-cell[data-level="4"] .heatmap-circle { background: #c83838; }
  /* Level 0 — muted fill, no count */
  .heatmap-cell[data-level="0"] .heatmap-circle {
    color: var(--color-muted);
  }
  /* Past months with no posts — dashed hollow circle, en-dash inside */
  .heatmap-cell[data-state="empty"] .heatmap-circle {
    background: var(--color-surface-alt);
    border: 2px dashed var(--color-muted);
    box-sizing: border-box;
    color: var(--color-secondary);
    font-weight: 800;
  }
  .heatmap-cell[data-state="empty"] .heatmap-label {
    color: var(--color-secondary);
  }
  /* Future months — dotted hollow circle, double-dot inside */
  .heatmap-cell[data-state="future"] {
    cursor: default;
  }
  .heatmap-cell[data-state="future"] .heatmap-circle {
    background: none;
    border: 2px dotted var(--color-border-faint);
    box-sizing: border-box;
    color: var(--color-muted);
    font-size: 0.45rem;
    letter-spacing: -0.05em;
  }
  .heatmap-cell[data-state="future"] .heatmap-label {
    color: var(--color-muted);
    opacity: 0.5;
  }
  .heatmap-cell[data-state="future"]:hover {
    background: none;
  }
  .heatmap-cell[data-state="future"]:hover .heatmap-circle {
    transform: none;
  }
  .cal-divider {
    border-top: 1px dashed var(--color-border);
    margin: 0.35rem 0;
  }
  /* Notes calendar */
  .notes-calendar {
    font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
  }
  .cal-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 0.3rem;
  }
  .cal-title {
    font-size: 0.72rem;
    font-weight: 600;
    color: var(--color-dim);
  }
  .cal-nav {
    background: none;
    border: none;
    color: var(--color-muted);
    cursor: pointer;
    font-size: 0.55rem;
    padding: 0.1rem 0.2rem;
    line-height: 1;
    transition: color 0.15s;
  }
  .cal-nav:hover {
    color: var(--color-link);
  }
  .cal-grid {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    grid-auto-rows: minmax(1.17rem, auto);
    gap: 0;
    text-align: center;
    font-size: 0.65rem;
    line-height: 1.8;
  }
  .cal-weekday {
    color: var(--color-muted);
    font-size: 0.6rem;
    font-weight: 600;
    line-height: 1.8;
  }
  .cal-day {
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 2px;
    line-height: 1.8;
  }
  .cal-day-active {
    cursor: pointer;
    font-weight: 700;
    color: var(--color-link);
    transition: color 0.1s;
  }
  .cal-day-active:hover {
    background: var(--color-surface-alt);
  }
  .cal-day-empty {
    color: var(--color-border);
    font-size: 0.58rem;
  }
  /* Tag cloud */
  .tag-cloud {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem 0.3rem;
    justify-content: space-between;
  }
  .tag-cloud-btn {
    display: inline-flex;
    align-items: center;
    gap: 0.2rem;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.6rem;
    color: var(--color-dim);
    background: none;
    border: 1px solid var(--color-border);
    border-radius: 3px;
    padding: 0.15rem 0.25rem 0.15rem 0.35rem;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s, background 0.15s;
    line-height: 1.4;
  }
  .tag-cloud-btn:hover {
    border-color: var(--color-faint);
    color: var(--color-text);
  }
  .tag-cloud-btn.active {
    border-color: var(--color-accent);
    color: var(--color-accent);
    background: var(--color-surface);
  }
  .tag-count {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 0.95rem;
    height: 0.95rem;
    font-size: 0.5rem;
    font-weight: 600;
    color: var(--color-muted);
    background: var(--color-surface-alt);
    border-radius: 50%;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }
  .tag-cloud-btn:hover .tag-count {
    color: var(--color-dim);
    background: var(--color-border);
  }
  .tag-cloud-btn.active .tag-count {
    color: white;
    background: var(--color-accent);
  }
}

/* These need higher specificity than layered rules */
@media (min-width: 1024px) {
  .sidenote-toggle { pointer-events: none; }
}
#nav-notes.emphasized {
  color: var(--color-link);
}
#toc-row.visible {
  opacity: 1;
  max-height: 2rem;
  overflow-x: auto;
  overflow-y: hidden;
}
/* Unlayered — wins over Tailwind utility classes */
article a:not(.no-underline):not(.heading-anchor):not(.lightbox-trigger) {
  color: var(--color-link);
  text-decoration: underline dotted;
  text-decoration-color: var(--color-link-ul);
  text-underline-offset: 2px;
}
article a:not(.no-underline):not(.heading-anchor):not(.lightbox-trigger):hover {
  text-decoration-style: solid;
  text-decoration-color: var(--color-link);
}
.ref-backlink {
  color: var(--color-link);
  text-decoration: none;
}
.ref-backlink:hover {
  text-decoration: underline dotted;
  text-decoration-color: var(--color-link-ul);
}
/* Nav bar */
.nav-bg {
  background: linear-gradient(to bottom, var(--color-nav-from), var(--color-nav-to));
}
.nav-prompt {
  font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
  color: var(--color-accent);
  font-weight: 400;
  font-size: 0.85em;
  letter-spacing: -0.05em;
}
.nav-border {
  border-bottom: 1px solid var(--color-border-nav);
  box-shadow: 0 1px 2px rgba(0,0,0,0.03);
}
.nav-caret {
  color: var(--color-accent);
}
.page-title {
  border-left: 3px solid var(--color-accent);
  padding-left: 0.6rem;
}
|}

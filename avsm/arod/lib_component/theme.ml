(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Design tokens and theme constants for the Arod site.

    Colors, typography, and spacing matching the reference design. *)

(** {1 Custom Colors} *)

let c_bg = "#fffffc"
let c_text = "#000000"
let c_link = "#090c8d"
let _c_link_underline = "#bbbbff"
let c_secondary = "#555555"

(** {1 Tailwind CDN Config}

    Injected as an inline script after the Tailwind CDN <script> tag. *)

let tailwind_config = {|
    tailwind.config = {
      theme: {
        extend: {
          fontFamily: {
            sans: ['system-ui', '-apple-system', 'sans-serif'],
            serif: ['"Source Serif 4"', 'Georgia', 'serif'],
          },
          colors: {
            bg: '#fffffc',
            text: '#000000',
            link: '#090c8d',
            'link-underline': '#bbbbff',
            secondary: '#555555',
            'tag-light': '#fcfffc',
          },
          fontSize: {
            'body': ['0.88rem', '1.45'],
          },
        }
      }
    }
|}

(** {1 Custom CSS}

    Styles that can't be expressed purely via Tw utilities:
    - Source Serif 4 font import
    - Link underline styling with underline-offset
    - Blockquote green border
    - Sidenote CSS
    - Scrollbar-hide
    - TOC link gradient progress
    - Nav emphasis brackets *)

let custom_css = {|
@import url('https://fonts.googleapis.com/css2?family=Source+Serif+4:ital,opsz,wght@0,8..60,400;0,8..60,600;1,8..60,400&display=swap');

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
    background: #f6f8fa;
    border: 1px solid #e5e7eb;
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
    background: #f3f4f6;
    padding: 0.15em 0.35em;
    border-radius: 3px;
    border: 1px solid #e5e7eb;
  }
  a {
    color: #090c8d;
    text-decoration: underline dotted;
    text-decoration-color: #bbbbff;
    text-underline-offset: 2px;
  }
  a:hover {
    text-decoration-style: solid;
    text-decoration-color: #090c8d;
  }
  blockquote {
    border-left: 3px solid #22c55e;
    padding-left: 1rem;
    margin-left: 0;
    color: #4a4a4a;
    font-style: italic;
  }
  blockquote cite {
    display: block;
    font-style: normal;
    font-size: 0.85rem;
    margin-top: 0.5rem;
    color: #555;
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
    color: #333399;
    background: linear-gradient(to bottom, transparent 60%, #f3f4f6 60%);
    text-decoration: none;
    cursor: help;
  }
  .sidenote-ref:hover,
  .sidenote-ref.highlighted {
    background: linear-gradient(to bottom, transparent 50%, #fde68a 50%);
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
    background: linear-gradient(to right, #e0e7ff 0%, #e0e7ff var(--progress, 0%), transparent var(--progress, 0%), transparent 100%);
    transition: all 0.15s ease;
  }
  .toc-link.passed {
    background: #e0e7ff;
    color: #090c8d;
  }
  .toc-link.active {
    color: #090c8d;
    font-weight: 500;
  }
  .text-body { font-size: 0.88rem; line-height: 1.45; }
  .idea-available { color: #22c55e; font-weight: 500; }
  .idea-discussion { color: #3b82f6; font-weight: 500; }
  .idea-ongoing { color: #f59e0b; font-weight: 500; }
  .idea-completed { color: #6b7280; font-weight: 500; }
  .idea-expired { color: #ef4444; font-weight: 500; }
  .hash-prefix { opacity: 0.5; }
  .sidebar-meta-box {
    font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
    font-size: 0.72rem;
    line-height: 1.5;
    border: 1px solid #e5e7eb;
    border-left: 2px solid #22c55e;
    border-radius: 3px;
    background: #fafbfc;
    overflow: hidden;
  }
  .sidebar-meta-header {
    padding: 0.3rem 0.5rem;
    background: #f3f4f6;
    border-bottom: 1px solid #e5e7eb;
    color: #555;
  }
  .sidebar-meta-prompt {
    color: #22c55e;
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
  }
  .sidebar-meta-key {
    color: #777;
  }
  .sidebar-meta-key::after {
    content: " ";
  }
  .sidebar-meta-val {
    color: #444;
  }
  .sidebar-meta-link {
    color: #444 !important;
    text-decoration: underline dotted #ccc !important;
  }
  .sidebar-meta-synopsis {
    font-style: italic;
    color: #555;
    margin: 0 0 0.3rem 0;
    padding-bottom: 0.3rem;
    border-bottom: 1px dashed #e5e7eb;
    white-space: normal;
    font-family: system-ui, -apple-system, sans-serif;
    font-size: 0.78rem;
    line-height: 1.4;
  }
  .sidebar-meta-link:hover {
    color: #090c8d !important;
    text-decoration-color: #090c8d !important;
    text-decoration-style: solid !important;
  }
  .references-block {
    border-left: 2px solid #090c8d;
    border-radius: 0 3px 3px 0;
    padding: 0.6rem 0.85rem;
    font-size: 0.78rem;
    line-height: 1.5;
  }
  .ref-header {
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.12em;
    color: #090c8d;
    font-weight: 600;
    margin-bottom: 0.4rem;
    padding-bottom: 0.3rem;
    border-bottom: 1px dashed #ddd;
  }
  .ref-item {
    margin-bottom: 0.3rem;
    display: flex;
    gap: 0.35rem;
    align-items: baseline;
  }
  .ref-item:last-child { margin-bottom: 0; }
  .ref-num {
    color: #090c8d;
    font-weight: 600;
    flex-shrink: 0;
  }
  .ref-body {
    color: #444;
  }
  .ref-doi {
    font-size: 0.72rem;
    color: #999 !important;
    text-decoration: none !important;
    word-break: break-all;
  }
  .ref-doi:hover {
    color: #090c8d !important;
    text-decoration: underline dotted !important;
  }
  .heading-anchor {
    font-size: 0.7em;
    font-weight: 400;
    font-style: italic;
    color: #ddd;
    text-decoration: none !important;
    transition: color 0.15s;
    font-variant-numeric: tabular-nums;
    margin-left: 0.75em;
    cursor: default;
  }
  .group:hover .heading-anchor { color: #777; cursor: pointer; }
  .heading-anchor:hover { color: #090c8d !important; }
  /* Ensure floated images in article content clear properly */
  article::after, .space-y-3::after {
    content: "";
    display: table;
    clear: both;
  }
  .lightbox-trigger { cursor: zoom-in; }
  .float-img {
    margin: 0;
  }
  .float-img img {
    border: 2px solid #555;
    transition: filter 0.3s ease, border-color 0.3s ease, box-shadow 0.3s ease;
  }
  .float-img:hover img {
    border-color: #22c55e;
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
}

/* These need higher specificity than layered rules */
@media (min-width: 1024px) {
  .sidenote-toggle { pointer-events: none; }
}
#nav-notes.emphasized {
  color: #090c8d;
}
#toc-row.visible {
  opacity: 1;
  max-height: 2rem;
  overflow-x: auto;
  overflow-y: hidden;
}
/* Unlayered — wins over Tailwind utility classes */
article a:not(.sidenote-ref):not(.no-underline):not(.heading-anchor):not(.lightbox-trigger) {
  color: #090c8d;
  text-decoration: underline dotted;
  text-decoration-color: #bbbbff;
  text-underline-offset: 2px;
}
article a:not(.sidenote-ref):not(.no-underline):not(.heading-anchor):not(.lightbox-trigger):hover {
  text-decoration-style: solid;
  text-decoration-color: #090c8d;
}
.ref-backlink {
  color: #090c8d;
  text-decoration: none;
}
.ref-backlink:hover {
  text-decoration: underline dotted;
  text-decoration-color: #bbbbff;
}
/* Nav bar */
.nav-bg {
  background: linear-gradient(to bottom, #f8faf8, #f6f8f6);
}
.nav-prompt {
  font-family: ui-monospace, 'SF Mono', 'Cascadia Code', 'Consolas', monospace;
  color: #22c55e;
  font-weight: 400;
  font-size: 0.85em;
  letter-spacing: -0.05em;
}
.nav-border {
  border-bottom: 1px solid #e0e2e0;
  box-shadow: 0 1px 2px rgba(0,0,0,0.03);
}
.nav-caret {
  color: #22c55e;
}
|}

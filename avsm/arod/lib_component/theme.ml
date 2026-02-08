(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Design tokens and theme constants for the Arod site.

    Colors, typography, and spacing matching the reference design. *)

(** {1 Custom Colors} *)

let c_bg = "#fffffc"
let c_text = "#1a1a1a"
let c_link = "#090c8d"
let _c_link_underline = "#bbbbff"
let c_secondary = "#666666"

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
            text: '#1a1a1a',
            link: '#090c8d',
            'link-underline': '#bbbbff',
            secondary: '#666666',
            'tag-light': '#fcfffc',
          },
          fontSize: {
            'body': ['0.95rem', '1.55'],
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
    font-size: 0.95rem;
    line-height: 1.55;
  }
  a {
    color: #090c8d;
    text-decoration: underline;
    text-decoration-color: #bbbbff;
    text-underline-offset: 2px;
  }
  a:hover {
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
    color: #666;
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
  .text-body { font-size: 0.95rem; line-height: 1.55; }
  .idea-available { color: #22c55e; font-weight: 500; }
  .idea-discussion { color: #3b82f6; font-weight: 500; }
  .idea-ongoing { color: #f59e0b; font-weight: 500; }
  .idea-completed { color: #6b7280; font-weight: 500; }
  .idea-expired { color: #ef4444; font-weight: 500; }
  .hash-prefix { opacity: 0.5; }
  /* Ensure floated images in article content clear properly */
  article::after, .space-y-5::after {
    content: "";
    display: table;
    clear: both;
  }
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
#nav-notes.emphasized #nav-notes-bracket-l,
#nav-notes.emphasized #nav-notes-bracket-r {
  opacity: 1;
  color: #22c55e;
  font-family: monospace;
  font-weight: bold;
}
#toc-row.visible {
  opacity: 1;
  max-height: 2rem;
}
|}

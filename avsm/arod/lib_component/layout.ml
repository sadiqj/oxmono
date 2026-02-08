(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Page shell layout component for the Arod website.

    Provides the overall page structure: head meta tags, header navigation,
    content grid with optional sidebar, footer, and scripts. *)

open Htmlit

(** {1 Footer} *)

let footer_el =
  El.footer ~at:[At.class' "max-w-6xl mx-auto px-6 py-6 border-t border-gray-200"]
    [ El.div ~at:[At.class' "flex items-center justify-between text-sm text-secondary"]
        [ El.p [El.txt {|© 1998–2026 Anil Madhavapeddy. No third-party trackers.|}]
        ]
    ]

(** {1 Head Elements} *)

let meta_tag ~name ~content =
  El.meta ~at:[ At.name name; At.content content ] ()

let og_tag ~property ~content =
  El.meta ~at:[ At.v "property" property; At.content content ] ()

let head_elements ~config ~title ~description ?image ?jsonld ?standardsite () =
  let site = config.Arod.Config.site in
  let base_url = site.base_url in
  let head_els =
    [ (* Basic meta *)
      meta_tag ~name:"description" ~content:description;
      meta_tag ~name:"author" ~content:site.author_name;
      El.meta ~at:[ At.name "theme-color"; At.content "#fffffc" ] ();

      (* Open Graph *)
      og_tag ~property:"og:type" ~content:"website";
      og_tag ~property:"og:title" ~content:title;
      og_tag ~property:"og:description" ~content:description;
      og_tag ~property:"og:site_name" ~content:site.name;
      og_tag ~property:"og:url" ~content:base_url;

      (* Twitter Card *)
      meta_tag ~name:"twitter:card" ~content:"summary";
      meta_tag ~name:"twitter:title" ~content:title;
      meta_tag ~name:"twitter:description" ~content:description;

      (* Feeds *)
      El.link ~at:[ At.rel "alternate"; At.v "type" "application/atom+xml";
                 At.v "title" (site.name ^ " (Atom)");
                 At.href "/feed.xml" ] ();
      El.link ~at:[ At.rel "alternate"; At.v "type" "application/rss+xml";
                 At.v "title" (site.name ^ " (RSS)");
                 At.href "/rss.xml" ] ();

      (* Favicon *)
      El.link ~at:[ At.rel "icon"; At.v "type" "image/svg+xml";
                 At.href "/favicon.svg" ] ();
      El.link ~at:[ At.rel "icon"; At.v "type" "image/png";
                 At.href "/favicon.png" ] ();
      El.link ~at:[ At.rel "apple-touch-icon";
                 At.href "/apple-touch-icon.png" ] ();

      (* Fonts *)
      El.link ~at:[ At.rel "preconnect";
                 At.href "https://fonts.googleapis.com" ] ();
      El.link ~at:[ At.rel "preconnect";
                 At.href "https://fonts.gstatic.com";
                 At.v "crossorigin" "" ] ();

      (* Tailwind CDN *)
      El.script ~at:[ At.src "https://cdn.tailwindcss.com" ] [];
      El.script [El.unsafe_raw Theme.tailwind_config];

      (* Highlight.js *)
      El.link ~at:[ At.rel "stylesheet";
                 At.href "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" ] ();
      El.script ~at:[ At.src "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js" ] [];

      (* Custom CSS *)
      El.style [El.unsafe_raw Theme.custom_css];
    ]
  in
  (* Optional image OG tag *)
  let head_els = match image with
    | Some img_url ->
      head_els @ [ og_tag ~property:"og:image" ~content:img_url;
                   meta_tag ~name:"twitter:image" ~content:img_url ]
    | None -> head_els
  in
  (* Optional JSON-LD *)
  let head_els = match jsonld with
    | Some ld ->
      head_els @ [
        El.script ~at:[ At.v "type" "application/ld+json" ] [ El.unsafe_raw ld ]
      ]
    | None -> head_els
  in
  (* Optional standardsite link *)
  let head_els = match standardsite with
    | Some ss_url ->
      head_els @ [
        El.link ~at:[ At.rel "standardsite"; At.href ss_url ] ()
      ]
    | None -> head_els
  in
  head_els

(** {1 Livereload Script} *)

let livereload_script =
  let enabled =
    match Sys.getenv_opt "SITE_LIVERELOAD" with
    | Some "true" -> true
    | _ -> false
  in
  if not enabled then El.void
  else
    let endpoint =
      match Sys.getenv_opt "SITE_LIVERELOAD_ENDPOINT" with
      | Some e -> e
      | None -> "ws://localhost:8080"
    in
    El.script [El.unsafe_raw (Printf.sprintf {|
(function() {
  const ws = new WebSocket('%s');
  ws.onmessage = (event) => {
    if (event.data === 'reload') {
      location.reload();
    }
  };
})();
|} endpoint)]

(** {1 Script Elements} *)

let script_elements =
  [ El.script [ El.unsafe_raw Scripts.sidenotes_js ];
    El.script [ El.unsafe_raw Scripts.toc_js ];
    El.script [ El.unsafe_raw Scripts.search_js ];
    El.script [ El.unsafe_raw Scripts.pagination_js ];
    El.script [ El.unsafe_raw Scripts.status_filter_js ];
    El.script [ El.unsafe_raw Scripts.hljs_init ];
    livereload_script;
  ]

(** {1 Content Grid} *)

let content_grid ~article ?sidebar () =
  let sidebar_el = match sidebar with
    | Some sb -> [ sb ]
    | None -> []
  in
  El.div
    ~at:[At.class' "max-w-6xl mx-auto px-6 py-8 flex flex-col lg:flex-row gap-6"]
    ([ El.main
         ~at:[At.class' "text-body flex-1 max-w-2xl"]
         [ article ] ]
     @ sidebar_el)

(** {1 Page Assembly} *)

let page ~ctx ~title ~description ?image ?jsonld ?standardsite ?current_page ?toc_sections ~article ?sidebar () =
  let config = Arod.Ctx.config ctx in
  let full_title = title ^ " | " ^ config.Arod.Config.site.name in
  let head_els =
    head_elements ~config ~title ~description ?image ?jsonld ?standardsite ()
  in
  let body_content =
    [ Nav.header ?current_page ?toc_sections ctx;
      content_grid ~article ?sidebar ();
      footer_el ]
    @ script_elements
  in
  let head_el =
    El.head
      ([ El.meta ~at:[At.charset "utf-8"] ();
         El.meta ~at:[At.name "viewport"; At.content "width=device-width, initial-scale=1.0"] ();
         El.title [El.txt full_title] ]
       @ head_els)
  in
  let body_el =
    El.body ~at:[At.class' "bg-bg text-text font-sans"] body_content
  in
  El.to_string ~doctype:true
    (El.html ~at:[At.lang "en"] [head_el; body_el])

let simple_page ~ctx ~title ~description ?current_page ~content () =
  page ~ctx ~title ~description ?current_page ~article:content ()

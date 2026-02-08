(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Navigation header component for the Arod site.

    Sticky header with navigation links, search button, and TOC breadcrumb
    row matching the Tailwind CSS reference design. *)

open Htmlit

(** {1 Search Icon} *)

let search_icon =
  El.unsafe_raw {|<svg class="w-4 h-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><circle cx="11" cy="11" r="7"/><path d="M21 21l-4.35-4.35" stroke-linecap="round"/></svg>|}

(** {1 Flow Line SVG}

    Decorative gradient line connecting nav items, visible only on desktop. *)

let flow_svg =
  El.unsafe_raw {|<svg class="hidden lg:block absolute top-1/2 left-0 w-full h-8 -translate-y-1/2 pointer-events-none" preserveAspectRatio="none">
  <defs>
    <linearGradient id="flow-grad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#e5e7eb" stop-opacity="0"/>
      <stop offset="15%" stop-color="#e5e7eb"/>
      <stop offset="85%" stop-color="#e5e7eb"/>
      <stop offset="100%" stop-color="#e5e7eb" stop-opacity="0"/>
    </linearGradient>
  </defs>
  <line x1="0" y1="50%" x2="100%" y2="50%" stroke="url(#flow-grad)" stroke-width="1"/>
</svg>|}

(** {1 Nav Items} *)

type nav_item = {
  label : string;
  href : string;
  id : string option;
}

let nav_items =
  [
    { label = "Papers"; href = "/papers"; id = None };
    { label = "Projects"; href = "/projects"; id = None };
    { label = "Notes"; href = "/notes"; id = Some "nav-notes" };
    { label = "Talks"; href = "/videos"; id = None };
    { label = "Ideas"; href = "/ideas"; id = None };
    { label = "About"; href = "/"; id = None };
  ]

let nav_link ~current_page item =
  let is_current =
    match current_page with
    | Some page ->
      String.lowercase_ascii page = String.lowercase_ascii item.label
    | None -> false
  in
  let base_class =
    "px-1.5 sm:px-2 py-1 rounded-md text-secondary hover:text-link hover:bg-gray-50 no-underline transition-all"
  in
  let cls = if is_current then base_class ^ " text-link" else base_class in
  let at =
    [ At.href item.href;
      At.class' cls ]
    @ (match item.id with Some id -> [ At.id id ] | None -> [])
    @ (if is_current then [ At.v "aria-current" "page" ] else [])
  in
  let children =
    match item.id with
    | Some "nav-notes" ->
      [
        El.span ~at:[ At.id "nav-notes-bracket-l";
                       At.class' "opacity-0 transition-opacity duration-200" ]
          [ El.txt "[" ];
        El.txt item.label;
        El.span ~at:[ At.id "nav-notes-bracket-r";
                       At.class' "opacity-0 transition-opacity duration-200" ]
          [ El.txt "]" ];
      ]
    | _ -> [ El.txt item.label ]
  in
  El.li [ El.a ~at children ]

(** {1 TOC Row} *)

let toc_row ~sections =
  El.div
    ~at:[ At.id "toc-row";
          At.class' "hidden lg:flex items-center gap-0.5 mt-2 opacity-0 max-h-0 overflow-hidden transition-all duration-300" ]
    ([ El.a
        ~at:[
          At.id "toc-root";
          At.href "#intro";
          At.class' "text-sm text-secondary hover:text-link no-underline transition-colors";
        ]
        [ El.txt "Top" ];
    ]
    @ List.concat
        (List.mapi
           (fun i (id, short_label) ->
             [
               El.span ~at:[At.class' "text-gray-300 mx-auto select-none px-1"]
                 [ El.txt "/" ];
               El.a
                 ~at:[
                   At.href ("#" ^ id);
                   At.class' "toc-link no-underline text-sm px-1 py-0 rounded-md text-secondary hover:text-link transition-all whitespace-nowrap";
                   At.v "data-index" (string_of_int i);
                 ]
                 [ El.txt short_label ];
             ])
           sections))

(** {1 Search Modal} *)

let search_modal =
  El.div
    ~at:[
      At.id "search-modal-overlay";
      At.class' "search-modal-overlay items-center justify-center p-4";
    ]
    [
      El.div
        ~at:[At.class' "bg-white rounded-xl w-full max-w-2xl overflow-hidden"]
        [
          (* Search header *)
          El.div
            ~at:[At.class' "flex items-center gap-3 px-4 py-3 border-b border-gray-200"]
            [
              search_icon;
              El.input
                ~at:[
                  At.id "search-input";
                  At.type' "text";
                  At.v "placeholder" "Search papers, notes, videos, projects...";
                  At.autocomplete "off";
                  At.class' "shrink w-full text-sm border-transparent";
                ] ();
              El.span ~at:[At.class' "text-sm text-gray-400 shrink-0"]
                [ El.txt "ESC" ];
            ];
          (* Search filters *)
          El.div
            ~at:[At.class' "flex items-center gap-2 px-4 py-2 border-b border-gray-100 text-sm"]
            [
              El.span ~at:[At.class' "text-gray-400"] [ El.txt "Filter:" ];
              El.button
                ~at:[ At.class' "search-filter active px-2 py-0 rounded-md text-sm transition-colors";
                      At.v "data-collection" "papers" ]
                [ El.txt "Papers" ];
              El.button
                ~at:[ At.class' "search-filter active px-2 py-0 rounded-md text-sm transition-colors";
                      At.v "data-collection" "notes" ]
                [ El.txt "Notes" ];
              El.button
                ~at:[ At.class' "search-filter active px-2 py-0 rounded-md text-sm transition-colors";
                      At.v "data-collection" "videos" ]
                [ El.txt "Videos" ];
              El.button
                ~at:[ At.class' "search-filter active px-2 py-0 rounded-md text-sm transition-colors";
                      At.v "data-collection" "projects" ]
                [ El.txt "Projects" ];
              El.button
                ~at:[ At.class' "search-filter active px-2 py-0 rounded-md text-sm transition-colors";
                      At.v "data-collection" "ideas" ]
                [ El.txt "Ideas" ];
            ];
          (* Search results body *)
          El.div
            ~at:[ At.id "search-modal-body";
                  At.class' "px-4 py-3 overflow-y-auto" ]
            [
              El.p ~at:[ At.class' "search-status-text text-sm text-gray-400" ]
                [ El.txt "Type to search..." ];
            ];
          (* Search footer *)
          El.div
            ~at:[At.class' "flex items-center justify-between px-4 py-2 border-b border-gray-100 text-sm text-gray-400"]
            [
              El.div ~at:[At.class' "flex items-center gap-3"]
                [
                  El.span
                    [
                      El.unsafe_raw {|<kbd class="px-1.5 py-0.5 bg-gray-100 rounded text-xs">&uarr;</kbd> <kbd class="px-1.5 py-0.5 bg-gray-100 rounded text-xs">&darr;</kbd>|};
                      El.txt " navigate";
                    ];
                  El.span
                    [
                      El.unsafe_raw {|<kbd class="px-1.5 py-0.5 bg-gray-100 rounded text-xs">&crarr;</kbd>|};
                      El.txt " select";
                    ];
                  El.span
                    [
                      El.unsafe_raw {|<kbd class="px-1.5 py-0.5 bg-gray-100 rounded text-xs">esc</kbd>|};
                      El.txt " close";
                    ];
                ];
            ];
        ];
    ]

(** {1 Header} *)

let header ?(current_page : string option) ctx =
  let config = Arod.Ctx.config ctx in
  let site_name = config.Arod.Config.site.name in
  El.header
    ~at:[ At.id "header";
          At.class' "sticky top-0 z-50 bg-bg border-b border-gray-100 overflow-hidden" ]
    [
      El.div ~at:[At.class' "max-w-6xl mx-auto px-6 py-5"]
        [
          El.nav ~at:[At.class' "relative"]
            [
              (* Flow line SVG - desktop only *)
              flow_svg;

              (* Main nav row *)
              El.div ~at:[At.class' "flex items-center gap-3 sm:gap-6"]
                [
                  (* Site name / link *)
                  El.a
                    ~at:[
                      At.href "/";
                      At.class' "shrink-0 text-lg font-semibold no-underline text-text hover:text-link transition-colors whitespace-nowrap";
                    ]
                    [
                      El.span ~at:[At.class' "hidden sm:inline"]
                        [ El.txt site_name ];
                      El.span ~at:[At.class' "sm:hidden"]
                        [ El.txt "@avsm" ];
                    ];

                  (* Separator *)
                  El.span ~at:[At.class' "hidden lg:block text-gray-300 select-none"]
                    [ El.txt "/" ];

                  (* Nav items *)
                  El.ul
                    ~at:[ At.class' "scrollbar-hide flex items-center sm:gap-1 text-sm overflow-x-auto" ]
                    (List.map (nav_link ~current_page) nav_items);

                  (* Search button *)
                  El.button
                    ~at:[
                      At.id "search-toggle-btn";
                      At.v "aria-label" "Search";
                      At.class' "shrink-0 ml-auto p-2 rounded-md text-secondary hover:text-link hover:bg-gray-50 transition-all";
                    ]
                    [ search_icon ];
                ];

              (* TOC row - populated per-page *)
              toc_row ~sections:[];
            ];
        ];
      search_modal;
    ]

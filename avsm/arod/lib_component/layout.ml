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

(** Citation metadata for Google Scholar. *)
type citation = {
  citation_title : string;
  citation_authors : string list;
  citation_date : string; (** YYYY/MM/DD format *)
  citation_doi : string option;
  citation_pdf_url : string option;
  citation_journal : string option;
}

let ptime_to_iso (y, m, d) =
  Printf.sprintf "%04d-%02d-%02d" y m d

let ptime_to_citation_date (y, m, d) =
  Printf.sprintf "%04d/%02d/%02d" y m d

let head_elements ~config ~title ~description ?url ?image ?jsonld ?standardsite
    ?(og_type="website") ?published ?modified ?(tags=[]) ?citation () =
  let site = config.Arod.Config.site in
  let base_url = site.base_url in
  let page_url = match url with Some u -> base_url ^ u | None -> base_url in
  let head_els =
    [ (* Basic meta *)
      meta_tag ~name:"description" ~content:description;
      meta_tag ~name:"author" ~content:site.author_name;
      El.meta ~at:[ At.name "theme-color"; At.content "#fffffc"; At.id "meta-theme-color" ] ();

      (* Canonical URL *)
      El.link ~at:[ At.rel "canonical"; At.href page_url ] ();

      (* Open Graph *)
      og_tag ~property:"og:type" ~content:og_type;
      og_tag ~property:"og:title" ~content:title;
      og_tag ~property:"og:description" ~content:description;
      og_tag ~property:"og:site_name" ~content:site.name;
      og_tag ~property:"og:url" ~content:page_url;

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

      (* rel=me verification *)
      El.link ~at:[ At.rel "me"; At.href "https://bsky.app/profile/anil.recoil.org" ] ();
      El.link ~at:[ At.rel "me"; At.href "https://amok.recoil.org/@avsm" ] ();
      El.link ~at:[ At.rel "me"; At.href "https://github.com/avsm" ] ();

      (* rel=author and blogroll *)
      El.link ~at:[ At.rel "author"; At.href "/about" ] ();
      El.link ~at:[ At.rel "blogroll"; At.v "type" "text/x-opml";
                 At.v "title" "Blogroll"; At.href "/network/blogroll.opml" ] ();

      (* Fonts *)
      El.link ~at:[ At.rel "preconnect";
                 At.href "https://fonts.googleapis.com" ] ();
      El.link ~at:[ At.rel "preconnect";
                 At.href "https://fonts.gstatic.com";
                 At.v "crossorigin" "" ] ();

      (* Theme init — must be before Tailwind CDN to prevent FOUC *)
      El.script [El.unsafe_raw Theme.theme_init_js];

      (* Tailwind CDN *)
      El.script ~at:[ At.src "https://cdn.tailwindcss.com?plugins=typography" ] [];
      El.script [El.unsafe_raw Theme.tailwind_config];

      (* Highlight.js — both themes, JS toggles which one is active *)
      El.link ~at:[ At.rel "stylesheet"; At.id "hljs-light";
                 At.href "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" ] ();
      El.link ~at:[ At.rel "stylesheet"; At.id "hljs-dark"; At.v "disabled" "true";
                 At.href "https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" ] ();
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
  (* Article OG tags when og_type = "article" *)
  let head_els =
    if og_type = "article" then
      let article_els = [] in
      let article_els = match published with
        | Some date -> article_els @ [
            og_tag ~property:"article:published_time" ~content:(ptime_to_iso date)]
        | None -> article_els
      in
      let article_els = match modified with
        | Some date -> article_els @ [
            og_tag ~property:"article:modified_time" ~content:(ptime_to_iso date)]
        | None -> article_els
      in
      let article_els =
        article_els @ [og_tag ~property:"article:author" ~content:site.author_name]
      in
      let article_els =
        article_els @ List.map (fun tag ->
          og_tag ~property:"article:tag" ~content:tag
        ) tags
      in
      head_els @ article_els
    else head_els
  in
  (* Google Scholar citation tags *)
  let head_els = match citation with
    | Some c ->
      let cite_els =
        [ meta_tag ~name:"citation_title" ~content:c.citation_title ]
        @ List.map (fun a ->
            meta_tag ~name:"citation_author" ~content:a
          ) c.citation_authors
        @ [ meta_tag ~name:"citation_publication_date" ~content:c.citation_date ]
      in
      let cite_els = match c.citation_doi with
        | Some doi -> cite_els @ [ meta_tag ~name:"citation_doi" ~content:doi ]
        | None -> cite_els
      in
      let cite_els = match c.citation_pdf_url with
        | Some pdf -> cite_els @ [ meta_tag ~name:"citation_pdf_url" ~content:pdf ]
        | None -> cite_els
      in
      let cite_els = match c.citation_journal with
        | Some j -> cite_els @ [ meta_tag ~name:"citation_journal_title" ~content:j ]
        | None -> cite_els
      in
      head_els @ cite_els
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
    El.script [ El.unsafe_raw Scripts.links_modal_js ];
    El.script [ El.unsafe_raw Scripts.pagination_js ];
    El.script [ El.unsafe_raw Scripts.status_filter_js ];
    El.script [ El.unsafe_raw Scripts.classification_filter_js ];
    El.script [ El.unsafe_raw Scripts.lightbox_js ];
    El.script [ El.unsafe_raw Scripts.hljs_init ];
    El.script [ El.unsafe_raw Scripts.theme_toggle_js ];
    El.script [ El.unsafe_raw Scripts.notes_calendar_js ];
    El.script [ El.unsafe_raw Scripts.papers_calendar_js ];
    El.script [ El.unsafe_raw Scripts.links_calendar_js ];
    El.script [ El.unsafe_raw Scripts.network_calendar_js ];
    El.script [ El.unsafe_raw Scripts.tag_cloud_filter_js ];
    El.script [ El.unsafe_raw Scripts.feed_dropdown_js ];
    El.script [ El.unsafe_raw Scripts.mobile_menu_js ];
    El.script [ El.unsafe_raw Scripts.masonry_js ];
    livereload_script;
  ]

(** {1 Content Grid} *)

let content_grid ~article ?sidebar () =
  let sidebar_el = match sidebar with
    | Some sb -> [ sb ]
    | None -> []
  in
  El.div
    ~at:[At.class' "max-w-6xl mx-auto px-6 py-8 flex flex-col lg:flex-row gap-6 lg:gap-10"]
    ([ El.main
         ~at:[At.class' "prose text-body flex-1 max-w-2xl"]
         [ article ] ]
     @ sidebar_el)

(** {1 Page Assembly} *)

let page ~ctx ~title ~description ?url ?image ?jsonld ?standardsite ?current_page ?toc_sections
    ?og_type ?published ?modified ?tags ?citation ~article ?sidebar () =
  let config = Arod.Ctx.config ctx in
  let full_title = title ^ " | " ^ config.Arod.Config.site.name in
  let og_type = Option.value ~default:"website" og_type in
  let tags = Option.value ~default:[] tags in
  let head_els =
    head_elements ~config ~title ~description ?url ?image ?jsonld ?standardsite
      ~og_type ?published ?modified ~tags ?citation ()
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

let simple_page ~ctx ~title ~description ?url ?current_page ~content () =
  page ~ctx ~title ~description ?url ?current_page ~article:content ()

let wide_page ~ctx ~title ~description ?url ?current_page ~article () =
  let config = Arod.Ctx.config ctx in
  let full_title = title ^ " | " ^ config.Arod.Config.site.name in
  let head_els = head_elements ~config ~title ~description ?url () in
  let body_content =
    [ Nav.header ?current_page ctx;
      El.div ~at:[At.class' "max-w-screen-xl mx-auto px-6 py-8"]
        [El.main ~at:[At.class' "prose text-body"] [article]];
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

let graph_page ~ctx () =
  let title = "Bushel Link Graph" in
  let description = "Interactive force-directed graph visualization of links and backlinks in the Bushel dataset" in
  let graph_html = El.div [
    El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "Bushel Link Graph"];
    El.div ~at:[At.id "controls"; At.class' "mb-5 p-4 bg-gray-50 dark:bg-gray-800 rounded-lg"] [
      El.div ~at:[At.class' "mb-2.5"] [
        El.strong [El.txt "Filter by type: "];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-paper"; At.checked; At.class' "type-filter"] ();
          El.txt " Papers"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-project"; At.checked; At.class' "type-filter"] ();
          El.txt " Projects"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-note"; At.checked; At.class' "type-filter"] ();
          El.txt " Notes"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-idea"; At.checked; At.class' "type-filter"] ();
          El.txt " Ideas"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-video"; At.checked; At.class' "type-filter"] ();
          El.txt " Videos"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-contact"; At.checked; At.class' "type-filter"] ();
          El.txt " Contacts"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-domain"; At.checked; At.class' "type-filter"] ();
          El.txt " Domains"]];
      El.div ~at:[At.class' "mb-2.5"] [
        El.strong [El.txt "Link type: "];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-internal"; At.checked; At.class' "link-filter"] ();
          El.txt " Internal"];
        El.label ~at:[At.class' "mx-2.5"] [
          El.input ~at:[At.type' "checkbox"; At.id "filter-external"; At.checked; At.class' "link-filter"] ();
          El.txt " External"]];
      El.div [
        El.button ~at:[At.id "reset-filters"; At.class' "px-4 py-1 cursor-pointer rounded border"] [El.txt "Reset Filters"]]];
    El.div ~at:[At.id "graph"; At.class' "w-full border border-gray-200 dark:border-gray-700";
                At.v "style" "height: 800px"] [];
    El.script ~at:[At.src "https://d3js.org/d3.v7.min.js"] [];
    El.script [El.unsafe_raw {|
fetch('/bushel/graph.json')
  .then(response => response.json())
  .then(data => { initGraph(data); })
  .catch(error => {
    console.error('Error loading graph data:', error);
    document.getElementById('graph').innerHTML = '<p style="color: red;">Error loading graph data</p>';
  });

function initGraph(graphData) {
  const width = document.getElementById('graph').offsetWidth;
  const height = 800;
  const colors = {
    'paper': '#4285f4', 'project': '#ea4335', 'note': '#fbbc04',
    'idea': '#34a853', 'video': '#ff6d00', 'contact': '#9c27b0', 'domain': '#607d8b'
  };
  const svg = d3.select('#graph').append('svg').attr('width', width).attr('height', height);
  const g = svg.append('g');
  svg.call(d3.zoom().scaleExtent([0.1, 4]).on('zoom', (event) => g.attr('transform', event.transform)));
  const simulation = d3.forceSimulation(graphData.nodes)
    .force('link', d3.forceLink(graphData.links).id(d => d.id).distance(d => d.type === 'external' ? 150 : 100))
    .force('charge', d3.forceManyBody().strength(-300))
    .force('center', d3.forceCenter(width / 2, height / 2))
    .force('collision', d3.forceCollide().radius(30));
  const link = g.append('g').selectAll('line').data(graphData.links).join('line')
    .attr('class', d => 'link link-' + d.type)
    .attr('stroke', d => d.type === 'internal' ? '#999' : '#ccc')
    .attr('stroke-opacity', 0.6).attr('stroke-width', 1);
  const node = g.append('g').selectAll('g').data(graphData.nodes).join('g')
    .attr('class', d => 'node node-' + d.type).style('cursor', 'pointer')
    .call(d3.drag().on('start', dragstarted).on('drag', dragged).on('end', dragended));
  node.append('circle').attr('r', d => d.group === 'domain' ? 8 : 10)
    .attr('fill', d => colors[d.type] || '#999').attr('stroke', '#fff').attr('stroke-width', 2);
  node.append('text').text(d => d.group === 'domain' ? d.title : d.id)
    .attr('x', 12).attr('y', 4).attr('font-size', '10px').attr('fill', '#333');
  node.append('title').text(d => d.title + '\nType: ' + d.type);
  simulation.on('tick', () => {
    link.attr('x1', d => d.source.x).attr('y1', d => d.source.y).attr('x2', d => d.target.x).attr('y2', d => d.target.y);
    node.attr('transform', d => 'translate(' + d.x + ',' + d.y + ')');
  });
  function dragstarted(event) { if (!event.active) simulation.alphaTarget(0.3).restart(); event.subject.fx = event.subject.x; event.subject.fy = event.subject.y; }
  function dragged(event) { event.subject.fx = event.x; event.subject.fy = event.y; }
  function dragended(event) { if (!event.active) simulation.alphaTarget(0); event.subject.fx = null; event.subject.fy = null; }
  function updateFilters() {
    const activeTypes = new Set();
    document.querySelectorAll('.type-filter').forEach(cb => { if (cb.checked) activeTypes.add(cb.id.replace('filter-', '')); });
    const activeLinks = new Set();
    document.querySelectorAll('.link-filter').forEach(cb => { if (cb.checked) activeLinks.add(cb.id.replace('filter-', '')); });
    node.style('display', d => activeTypes.has(d.type) ? null : 'none');
    link.style('display', d => (activeTypes.has(d.source.type) && activeTypes.has(d.target.type) && activeLinks.has(d.type)) ? null : 'none');
    simulation.alpha(0.3).restart();
  }
  document.querySelectorAll('.type-filter, .link-filter').forEach(cb => cb.addEventListener('change', updateFilters));
  document.getElementById('reset-filters').addEventListener('click', () => {
    document.querySelectorAll('.type-filter, .link-filter').forEach(cb => cb.checked = true);
    updateFilters();
  });
}
|}]] in
  wide_page ~ctx ~title ~description ~article:graph_html ()

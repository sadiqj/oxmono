(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Pure route handlers for arod using context-based state *)

module R = Httpz_server.Route
module Entry = Bushel.Entry
module Paper = Bushel.Paper
module C = Arod_component

(** {1 Response Helpers} *)

let to_page el = Htmlit.El.to_string ~doctype:true el

(* Response helpers that work with local_ respond - call respond with all args at once *)
let[@inline] send_html (local_ respond) s =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "text/html; charset=utf-8")]
    (R.String s)

let[@inline] send_html_empty (local_ respond) =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "text/html; charset=utf-8")]
    R.Empty

let[@inline] send_atom (local_ respond) s =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "application/atom+xml; charset=utf-8")]
    (R.String s)

let[@inline] send_atom_empty (local_ respond) =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "application/atom+xml; charset=utf-8")]
    R.Empty

let[@inline] send_json (local_ respond) s =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "application/json; charset=utf-8")]
    (R.String s)

let[@inline] send_json_empty (local_ respond) =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, "application/json; charset=utf-8")]
    R.Empty

let[@inline] send_file (local_ respond) ~mime s =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, mime)]
    (R.String s)

let[@inline] send_file_empty (local_ respond) ~mime =
  respond ~status:Httpz.Res.Success
    ~headers:[(Httpz.Header_name.Content_type, mime)]
    R.Empty

let[@inline] not_found (local_ respond) =
  respond ~status:Httpz.Res.Not_found ~headers:[] (R.String "Not Found")

(** {1 File Serving} *)

let mime_type_of_path path =
  if String.ends_with ~suffix:".pdf" path then "application/pdf"
  else if String.ends_with ~suffix:".html" path then "text/html"
  else if String.ends_with ~suffix:".css" path then "text/css"
  else if String.ends_with ~suffix:".js" path then "text/javascript"
  else if String.ends_with ~suffix:".svg" path then "image/svg+xml"
  else if String.ends_with ~suffix:".png" path then "image/png"
  else if String.ends_with ~suffix:".jpg" path then "image/jpeg"
  else if String.ends_with ~suffix:".jpeg" path then "image/jpeg"
  else if String.ends_with ~suffix:".webp" path then "image/webp"
  else if String.ends_with ~suffix:".xml" path then "application/xml"
  else if String.ends_with ~suffix:".wasm" path then "application/wasm"
  else if String.ends_with ~suffix:".ico" path then "image/x-icon"
  else if String.ends_with ~suffix:".woff" path then "font/woff"
  else if String.ends_with ~suffix:".woff2" path then "font/woff2"
  else if String.ends_with ~suffix:".bib" path then "application/x-bibtex"
  else if String.ends_with ~suffix:".webmanifest" path then "application/manifest+json"
  else "application/octet-stream"

let static_file ~dir path rctx (local_ respond) =
  let clean_path =
    let parts = String.split_on_char '/' path in
    let safe_parts = List.filter (fun s -> s <> ".." && s <> ".") parts in
    String.concat "/" safe_parts
  in
  let file_path = Filename.concat dir clean_path in
  try
    if Sys.file_exists file_path && not (Sys.is_directory file_path) then begin
      let mime = mime_type_of_path file_path in
      if R.is_head rctx then
        send_file_empty respond ~mime
      else begin
        let ic = open_in_bin file_path in
        let len = in_channel_length ic in
        let content = really_input_string ic len in
        close_in ic;
        send_file respond ~mime content
      end
    end
    else not_found respond
  with _ -> not_found respond

(** {1 Embedded Asset Serving} *)

let embedded_file path rctx (local_ respond) =
  match Arod_assets.read path with
  | Some content ->
    let mime = mime_type_of_path path in
    if R.is_head rctx then
      send_file_empty respond ~mime
    else
      send_file respond ~mime content
  | None -> not_found respond

(** {1 Cached Handler Wrapper} *)

let cached ~cache ~key rctx f (local_ respond) =
  if R.is_head rctx then
    send_html_empty respond
  else
    match Arod.Cache.get cache key with
    | Some html -> send_html respond html
    | None ->
      let html = f () in
      Arod.Cache.set cache key html;
      send_html respond html

(** {1 Content Negotiation} *)

let wants_markdown = function
  | Some accept ->
    let parts = String.split_on_char ',' accept in
    List.exists (fun s ->
      let t = String.trim s in
      t = "text/markdown" || String.starts_with ~prefix:"text/markdown;" t
    ) parts
  | None -> false

let[@inline] send_markdown (local_ respond) s =
  respond ~status:Httpz.Res.Success
    ~headers:[
      (Httpz.Header_name.Content_type, "text/markdown; charset=utf-8");
      (Httpz.Header_name.Vary, "Accept")]
    (R.String s)

let[@inline] send_html_vary (local_ respond) s =
  respond ~status:Httpz.Res.Success
    ~headers:[
      (Httpz.Header_name.Content_type, "text/html; charset=utf-8");
      (Httpz.Header_name.Vary, "Accept")]
    (R.String s)

let negotiated ~cache ~key rctx accept ~html_fn ~md_fn (local_ respond) =
  if R.is_head rctx then send_html_empty respond
  else if wants_markdown accept then
    let md_key = key ^ ":md" in
    (match Arod.Cache.get cache md_key with
     | Some md -> send_markdown respond md
     | None ->
       let md = md_fn () in
       Arod.Cache.set cache md_key md;
       send_markdown respond md)
  else
    (match Arod.Cache.get cache key with
     | Some html -> send_html_vary respond html
     | None ->
       let html = html_fn () in
       Arod.Cache.set cache key html;
       send_html_vary respond html)

(** {1 Cached Content Handlers} *)

let index ~ctx ~cache accept rctx (local_ respond) =
  let key = "/" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx "index" with
      | None -> ""
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        let sidebar =
          Htmlit.El.aside
            ~at:[Htmlit.At.class' "hidden lg:block lg:w-72 shrink-0"]
            [C.Sidebar.socials_box ~ctx]
        in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~current_page:"About" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.index_md ~ctx)
  respond

let papers_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/papers" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article, sidebar = C.Paper.papers_list ~ctx in
      C.Layout.page ~ctx ~title:"Papers" ~description:"Academic papers" ~current_page:"Papers" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.papers_list_md ~ctx)
  respond

let paper ~ctx ~cache slug accept rctx (local_ respond) =
  let cfg = Arod.Ctx.config ctx in
  match slug with
  | slug when String.ends_with ~suffix:".pdf" slug ->
    static_file ~dir:cfg.paths.papers_dir slug rctx respond
  | slug when String.ends_with ~suffix:".bib" slug ->
    let paper_slug = Filename.chop_extension slug in
    begin match Arod.Ctx.lookup ctx paper_slug with
     | Some (`Paper p) -> R.plain_gen rctx respond (fun () -> Paper.bib p)
     | _ -> not_found respond
    end
  | _ ->
    let key = "/papers/" ^ slug in
    negotiated ~cache ~key rctx accept
      ~html_fn:(fun () ->
        match Arod.Ctx.lookup ctx slug with
        | None -> ""
        | Some (`Paper p) ->
          let paper_el, sidenotes = C.Paper.full ~ctx p in
          let related = C.Sidebar.related_stream ~ctx (Paper.slug p) in
          let article = Htmlit.El.div [paper_el; C.Paper.extra ~ctx p; related] in
          let sidebar = C.Sidebar.for_entry ~ctx ~sidenotes (`Paper p) in
          C.Layout.page ~ctx ~title:(Paper.title p) ~description:"" ~article ~sidebar ()
        | Some ent ->
          let article = C.Entry.full_body ~ctx ent in
          C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
      ~md_fn:(fun () ->
        match Arod.Ctx.lookup ctx slug with
        | None -> ""
        | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
    respond

let notes_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/notes" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article, sidebar = C.Note.notes_list ~ctx in
      C.Layout.page ~ctx ~title:"Notes" ~description:"Notes and blog posts" ~current_page:"Notes" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.notes_list_md ~ctx)
  respond

let note ~ctx ~cache slug accept rctx (local_ respond) =
  let key = "/notes/" ^ slug in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some (`Note n) ->
        let article_el, sidenotes, headings = C.Note.full_page ~ctx n in
        let refs = C.Note.references ~ctx n in
        let related = C.Sidebar.related_stream ~ctx (Bushel.Note.slug n) in
        let full_article = Htmlit.El.div [article_el; refs; related] in
        let sidebar = C.Sidebar.for_entry ~ctx ~sidenotes (`Note n) in
        C.Layout.page ~ctx ~title:(Bushel.Note.title n) ~description:"" ~toc_sections:headings ~article:full_article ~sidebar ()
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
    ~md_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
  respond

let ideas_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/ideas" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article, sidebar = C.Idea.ideas_list ~ctx in
      C.Layout.page ~ctx ~title:"Research Ideas" ~description:"Research ideas by year" ~current_page:"Ideas" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.ideas_list_md ~ctx)
  respond

let idea ~ctx ~cache slug accept rctx (local_ respond) =
  let key = "/ideas/" ^ slug in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some (`Idea i) ->
        let article_el, sidenotes, headings = C.Idea.full_page ~ctx i in
        let related = C.Sidebar.related_stream ~ctx i.Bushel.Idea.slug in
        let full_article = Htmlit.El.div [article_el; related] in
        let sidebar = C.Sidebar.for_entry ~ctx ~sidenotes (`Idea i) in
        C.Layout.page ~ctx ~title:(Bushel.Idea.title i) ~description:"" ~toc_sections:headings ~article:full_article ~sidebar ()
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
    ~md_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
  respond

let projects_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/projects" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article = C.Project.projects_list ~ctx in
      C.Layout.wide_page ~ctx ~title:"Projects" ~description:"Research projects" ~current_page:"Projects" ~article ())
    ~md_fn:(fun () -> C.Markdown_export.projects_list_md ~ctx)
  respond

let project ~ctx ~cache slug accept rctx (local_ respond) =
  let key = "/projects/" ^ slug in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some (`Project p) ->
        let article, sidenotes = C.Project.full ~ctx p in
        let sidebar = C.Sidebar.for_entry ~ctx ~sidenotes (`Project p) in
        C.Layout.page ~ctx ~title:(Bushel.Project.title p) ~description:"" ~article ~sidebar ()
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
    ~md_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
  respond

let videos_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/videos" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article = C.Video.videos_list ~ctx in
      C.Layout.wide_page ~ctx ~title:"Talks" ~description:"Conference talks and presentations" ~current_page:"Talks" ~article ())
    ~md_fn:(fun () -> C.Markdown_export.videos_list_md ~ctx)
  respond

let video ~ctx ~cache slug accept rctx (local_ respond) =
  let key = "/videos/" ^ slug in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some (`Video v) ->
        let article_el, sidebar = C.Video.full_page ~ctx v in
        let related = C.Sidebar.related_stream ~ctx (Bushel.Video.slug v) in
        let article = Htmlit.El.div [article_el; related] in
        C.Layout.page ~ctx ~title:(Bushel.Video.title v) ~description:"" ~article ~sidebar ()
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
    ~md_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
  respond

let content ~ctx ~cache slug accept rctx (local_ respond) =
  let key = "/content/" ^ slug in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent ->
        let article = C.Entry.full_body ~ctx ent in
        C.Layout.page ~ctx ~title:(Bushel.Entry.title ent) ~description:"" ~article ())
    ~md_fn:(fun () ->
      match Arod.Ctx.lookup ctx slug with
      | None -> ""
      | Some ent -> C.Markdown_export.entry_to_markdown ~ctx ent)
  respond

(** {1 Legacy Handlers} *)

let news_redirect slug _rctx (local_ respond) =
  R.redirect respond ~status:Httpz.Res.Moved_permanently ~location:("/notes/" ^ slug)

let links_list ~ctx ~cache accept rctx (local_ respond) =
  let key = "/links" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article, sidebar = C.Links.links_list ~ctx in
      C.Layout.page ~ctx ~title:"Links" ~description:"Outbound links" ~current_page:"Links" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.links_list_md ~ctx)
  respond

let network_page ~ctx ~cache accept rctx (local_ respond) =
  let key = "/network" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article, sidebar = C.Network.network_page ~ctx in
      C.Layout.page ~ctx ~title:"Network" ~description:"Network activity" ~current_page:"Network" ~article ~sidebar ())
    ~md_fn:(fun () -> C.Markdown_export.network_md ~ctx)
  respond

let wiki ~ctx ~cache accept rctx (local_ respond) =
  let key = "/wiki" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article = C.List_view.entries_page ~ctx ~title:"All Entries" ~types:[`Paper; `Note; `Video; `Idea; `Project] in
      C.Layout.simple_page ~ctx ~title:"Wiki" ~description:"All entries" ~content:article ())
    ~md_fn:(fun () -> C.Markdown_export.wiki_md ~ctx)
  respond

let news ~ctx ~cache accept rctx (local_ respond) =
  let key = "/news" in
  negotiated ~cache ~key rctx accept
    ~html_fn:(fun () ->
      let article = C.List_view.feed_page ~ctx ~title:"News" ~types:[`Note] in
      C.Layout.simple_page ~ctx ~title:"News" ~description:"News" ~content:article ())
    ~md_fn:(fun () -> C.Markdown_export.news_md ~ctx)
  respond

(** {1 Feed Handlers} *)

(* Cached wrapper for atom feeds - uses atom content type *)
let cached_atom ~cache ~key rctx f (local_ respond) =
  if R.is_head rctx then
    send_atom_empty respond
  else
    match Arod.Cache.get cache key with
    | Some xml -> send_atom respond xml
    | None ->
      let xml = f () in
      Arod.Cache.set cache key xml;
      send_atom respond xml

(* Cached wrapper for json feeds *)
let cached_json ~cache ~key rctx f (local_ respond) =
  if R.is_head rctx then
    send_json_empty respond
  else
    match Arod.Cache.get cache key with
    | Some json -> send_json respond json
    | None ->
      let json = f () in
      Arod.Cache.set cache key json;
      send_json respond json

let atom_feed ~ctx ~cache rctx (local_ respond) =
  let path = R.path rctx in
  let key = "feed:" ^ path in
  cached_atom ~cache ~key rctx (fun () ->
    let cfg = Arod.Ctx.config ctx in
    let feed = Arod.Render.get_entries ~ctx ~types:[] in
    Arod.Feed.feed_string ~ctx cfg path feed
  ) respond

let json_feed ~ctx ~cache rctx (local_ respond) =
  let key = "feed:/feed.json" in
  cached_json ~cache ~key rctx (fun () ->
    let cfg = Arod.Ctx.config ctx in
    let feed = Arod.Render.get_entries ~ctx ~types:[] in
    Arod.Jsonfeed.feed_string ~ctx cfg "/feed.json" feed
  ) respond

let perma_atom ~ctx ~cache rctx (local_ respond) =
  let key = "feed:/perma.xml" in
  cached_atom ~cache ~key rctx (fun () ->
    let cfg = Arod.Ctx.config ctx in
    let feed = Arod.Render.perma_entries ~ctx in
    Arod.Feed.feed_string ~ctx cfg "/perma.xml" feed
  ) respond

let perma_json ~ctx ~cache rctx (local_ respond) =
  let key = "feed:/perma.json" in
  cached_json ~cache ~key rctx (fun () ->
    let cfg = Arod.Ctx.config ctx in
    let feed = Arod.Render.perma_entries ~ctx in
    Arod.Jsonfeed.feed_string ~ctx cfg "/perma.json" feed
  ) respond

(** {1 Utility Handlers (Dynamic - not cached)} *)

let sitemap ~ctx rctx (local_ respond) =
  R.xml_gen rctx respond (fun () ->
    let cfg = Arod.Ctx.config ctx in
    let all_feed =
      Arod.Ctx.all_entries ctx
      |> List.sort Entry.compare
      |> List.rev
    in
    let url_of_entry ent =
      let lastmod = Entry.date ent in
      let loc = cfg.site.base_url ^ Entry.site_url ent in
      Sitemap.v ~lastmod loc
    in
    List.map url_of_entry all_feed |> Sitemap.output
  )

let blogroll_opml ~ctx rctx (local_ respond) =
  let module Contact = Sortal_schema.Contact in
  let module Feed = Sortal_schema.Feed in
  let contacts = Arod.Ctx.contacts ctx in
  let contacts_with_feeds = List.filter_map (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> Some (contact, feeds)
    | _ -> None
  ) contacts in
  let contacts_with_feeds = List.sort (fun (a, _) (b, _) ->
    String.compare (Contact.name a) (Contact.name b)
  ) contacts_with_feeds in
  let outlines = List.map (fun (contact, feeds) ->
    let name = Contact.name contact in
    let html_url = Option.map Uri.of_string (Contact.best_url contact) in
    let sub_outlines = List.map (fun feed ->
      let feed_type_str = match Feed.feed_type feed with
        | Feed.Atom -> "rss" | Feed.Rss -> "rss" | Feed.Json -> "rss"
      in
      Syndic.Opml1.outline ~typ:feed_type_str
        ~xml_url:(Uri.of_string (Feed.url feed))
        ?html_url
        (Option.value ~default:name (Feed.name feed))
    ) feeds in
    Syndic.Opml1.outline ?html_url ~outlines:sub_outlines name
  ) contacts_with_feeds in
  let head = Syndic.Opml1.head
    ~date_modified:(Ptime_clock.now ())
    ~owner_name:"Anil Madhavapeddy"
    ~owner_email:"anil@recoil.org"
    "Blogroll"
  in
  let opml : Syndic.Opml1.t = { version = "1.0"; head; body = outlines } in
  let buf = Buffer.create 4096 in
  Syndic.Opml1.output opml (`Buffer buf);
  send_file respond ~mime:"text/x-opml+xml; charset=utf-8" (Buffer.contents buf)

let bushel_graph ~ctx ~cache rctx (local_ respond) =
  let key = "/bushel" in
  cached ~cache ~key rctx (fun () ->
    to_page (Arod.Page.bushel_graph ~ctx ())
  ) respond

let bushel_graph_data ~ctx rctx (local_ respond) =
  R.json_gen rctx respond (fun () ->
    let entries = Arod.Ctx.entries ctx in
    match Bushel.Link_graph.get_graph () with
    | None -> {|{"error": "Link graph not initialized"}|}
    | Some graph ->
      let json = Bushel.Link_graph.to_json graph entries in
      Ezjsonm.value_to_string json
  )

let slice_list offset limit l =
  l
  |> (fun l -> List.filteri (fun i _ -> i >= offset) l)
  |> (fun l -> List.filteri (fun i _ -> i < limit) l)

let pagination_api ~ctx rctx (local_ respond) =
  R.json_gen rctx respond (fun () ->
    try
      let collection_type =
        match R.query_param rctx "collection" with
        | Some t -> t
        | None -> failwith "Missing collection parameter"
      in
      let offset =
        match R.query_param rctx "offset" with
        | Some o -> int_of_string o
        | None -> 0
      in
      let limit =
        match R.query_param rctx "limit" with
        | Some l -> int_of_string l
        | None -> 25
      in
      let total, rendered_html = match collection_type with
        | "links" ->
          let all = C.Links.all_groups ~ctx in
          let total = List.length all in
          let slice = slice_list offset limit all in
          (total, C.Links.render_groups_html ~ctx slice)
        | "network" ->
          let all = C.Network.all_months ~ctx in
          let total = List.length all in
          let slice = slice_list offset limit all in
          (total, C.Network.render_months_html ~ctx slice)
        | _ ->
          let type_strings = R.query_params rctx "type" in
          let types = List.filter_map C.List_view.entry_type_of_string type_strings in
          let all_items = C.List_view.get_entries ~ctx ~types in
          let total = List.length all_items in
          let slice = slice_list offset limit all_items in
          let render_fn = match collection_type with
            | "feed" -> C.List_view.render_feeds_html ~ctx
            | "entries" -> C.List_view.render_entries_html ~ctx
            | _ -> failwith "Invalid collection type"
          in
          (total, render_fn slice)
      in
      let count = min limit (total - offset) in
      let count = max 0 count in
      let has_more = offset + count < total in
      let json =
        `O [
          ("html", `String rendered_html);
          ("total", `Float (float_of_int total));
          ("offset", `Float (float_of_int offset));
          ("limit", `Float (float_of_int limit));
          ("count", `Float (float_of_int count));
          ("has_more", `Bool has_more);
        ]
      in
      Ezjsonm.to_string json
    with e ->
      let error_json = `O [ ("error", `String (Printexc.to_string e)) ] in
      Ezjsonm.to_string error_json
  )

let well_known ~ctx key rctx (local_ respond) =
  let cfg = Arod.Ctx.config ctx in
  match List.find_opt (fun e -> e.Arod.Config.key = key) cfg.well_known with
  | Some entry -> R.plain_gen rctx respond (fun () -> entry.value)
  | None -> not_found respond

let robots_txt ~ctx rctx (local_ respond) =
  let cfg = Arod.Ctx.config ctx in
  R.plain_gen rctx respond (fun () ->
    Printf.sprintf "User-agent: *\nAllow: /\n\nSitemap: %s/sitemap.xml\n"
      cfg.site.base_url)

(** {1 Search API} *)

let search_api ~ctx ~search rctx (local_ respond) =
  R.json_gen rctx respond (fun () ->
    let q = match R.query_param rctx "q" with Some q -> q | None -> "" in
    let limit = match R.query_param rctx "limit" with
      | Some l -> (try int_of_string l with _ -> 20) | None -> 20 in
    Logs.info (fun m -> m "Search API: q=%S limit=%d" q limit);
    if q = "" then {|{"results":[]}|}
    else
      let entries = Arod.Ctx.entries ctx in
      let results = Arod_search.search search ~limit q in
      Logs.info (fun m -> m "Search API: %d results for %S" (List.length results) q);
      let json_results = List.map (fun (r : Arod_search.result) ->
        let parent_entries = List.filter_map (fun slug ->
          match Arod.Ctx.lookup ctx slug with
          | Some ent ->
            Some (`O [
              ("slug", `String slug);
              ("title", `String (Bushel.Entry.title ent));
              ("url", `String (Bushel.Entry.site_url ent));
              ("kind", `String (Bushel.Entry.to_type_string ent));
            ])
          | None -> None
        ) r.parent_slugs in
        let thumbnail = match r.kind with
          | "link" ->
            (match Arod.Ctx.link_for_url ctx r.url with
             | Some link ->
               let meta = match link.karakeep with Some k -> k.metadata | None -> [] in
               (match List.assoc_opt "favicon" meta with
                | Some f when f <> "" -> Some f
                | _ -> None)
             | None -> None)
          | _ ->
            (match Arod.Ctx.lookup ctx r.slug with
             | Some ent -> Bushel.Entry.thumbnail entries ent
             | None -> None)
        in
        `O ([ ("slug", `String r.slug); ("kind", `String r.kind);
              ("url", `String r.url); ("title", `String r.title);
              ("snippet", `String r.snippet); ("date", `String r.date) ]
             @ (if r.tags <> [] then
                  [("tags", `A (List.map (fun t -> `String t) r.tags))]
                else [])
             @ (match thumbnail with Some t -> [("thumbnail", `String t)] | None -> [])
             @ (if parent_entries <> [] then
                  [("parents", `A parent_entries)]
                else []))
      ) results in
      Ezjsonm.to_string (`O [("results", `A json_results)])
  )

(** {1 Route Collection} *)

let all_routes ~ctx ~cache ~search =
  let cfg = Arod.Ctx.config ctx in
  let open R in
  let lits segs = List.fold_right lit segs root in
  of_list [
    (* Index routes — content-negotiated *)
    get_h1 root Accept (fun () -> index ~ctx ~cache);
    get_h1 (lits ["about"]) Accept (fun () -> index ~ctx ~cache);
    (* Atom feeds *)
    get_ [ "wiki.xml" ] (atom_feed ~ctx ~cache);
    get_ [ "news.xml" ] (atom_feed ~ctx ~cache);
    get_ [ "feeds"; "atom.xml" ] (atom_feed ~ctx ~cache);
    get_ [ "notes"; "atom.xml" ] (atom_feed ~ctx ~cache);
    get_ [ "perma.xml" ] (perma_atom ~ctx ~cache);
    (* JSON feeds *)
    get_ [ "feed.json" ] (json_feed ~ctx ~cache);
    get_ [ "feeds"; "feed.json" ] (json_feed ~ctx ~cache);
    get_ [ "notes"; "feed.json" ] (json_feed ~ctx ~cache);
    get_ [ "perma.json" ] (perma_json ~ctx ~cache);
    (* Sitemap *)
    get_ [ "sitemap.xml" ] (sitemap ~ctx);
    (* Papers — content-negotiated *)
    get_h1 ("papers" / seg root) Accept (fun (slug, ()) -> paper ~ctx ~cache slug);
    get_h1 (lits ["papers"]) Accept (fun () -> papers_list ~ctx ~cache);
    (* Ideas — content-negotiated *)
    get_h1 ("ideas" / seg root) Accept (fun (slug, ()) -> idea ~ctx ~cache slug);
    get_h1 (lits ["ideas"]) Accept (fun () -> ideas_list ~ctx ~cache);
    (* Notes — content-negotiated *)
    get_h1 ("notes" / seg root) Accept (fun (slug, ()) -> note ~ctx ~cache slug);
    get_h1 (lits ["notes"]) Accept (fun () -> notes_list ~ctx ~cache);
    (* Videos/Talks — content-negotiated *)
    get_h1 ("videos" / seg root) Accept (fun (slug, ()) -> video ~ctx ~cache slug);
    get_h1 (lits ["talks"]) Accept (fun () -> videos_list ~ctx ~cache);
    get_h1 (lits ["videos"]) Accept (fun () -> videos_list ~ctx ~cache);
    (* Projects — content-negotiated *)
    get_h1 ("projects" / seg root) Accept (fun (slug, ()) -> project ~ctx ~cache slug);
    get_h1 (lits ["projects"]) Accept (fun () -> projects_list ~ctx ~cache);
    (* Tag search redirect — handles /tags/foo from ##tag markdown links *)
    get ("tags" / seg root) (fun (tag, ()) _rctx (local_ respond) ->
      R.redirect respond ~status:Httpz.Res.Found ~location:("/#tag=" ^ tag));
    (* Legacy news redirect *)
    get ("news" / seg root) (fun (slug, ()) -> news_redirect slug);
    (* Links and Feeds — content-negotiated *)
    get_h1 (lits ["links"]) Accept (fun () -> links_list ~ctx ~cache);
    get_h1 (lits ["network"]) Accept (fun () -> network_page ~ctx ~cache);
    get_ [ "network"; "blogroll.opml" ] (blogroll_opml ~ctx);
    get_ ["feeds"] (fun _rctx (local_ respond) ->
      R.redirect respond ~status:Httpz.Res.Moved_permanently ~location:"/network");
    (* Wiki/News legacy — redirects *)
    get_ ["wiki"] (fun _rctx (local_ respond) ->
      R.redirect respond ~status:Httpz.Res.Moved_permanently ~location:"/notes");
    get_ ["news"] (fun _rctx (local_ respond) ->
      R.redirect respond ~status:Httpz.Res.Moved_permanently ~location:"/notes");
    (* Pagination API - dynamic, not cached *)
    get_ [ "api"; "entries" ] (pagination_api ~ctx);
    (* Search API - dynamic, not cached *)
    get_ [ "api"; "search" ] (search_api ~ctx ~search);
    (* Bushel link graph *)
    get_ [ "bushel" ] (bushel_graph ~ctx ~cache);
    get_ [ "bushel"; "graph.json" ] (bushel_graph_data ~ctx);
    (* Well-known endpoints *)
    get (".well-known" / seg root) (fun (key, ()) -> well_known ~ctx key);
    (* Robots.txt *)
    get_ [ "robots.txt" ] (robots_txt ~ctx);
    (* Embedded favicon/asset routes *)
    get_ [ "favicon.svg" ] (fun rctx respond -> embedded_file "favicon.svg" rctx respond);
    get_ [ "favicon.ico" ] (fun rctx respond -> embedded_file "favicon.ico" rctx respond);
    get_ [ "favicon.png" ] (fun rctx respond -> embedded_file "favicon-32x32.png" rctx respond);
    get_ [ "favicon-32x32.png" ] (fun rctx respond -> embedded_file "favicon-32x32.png" rctx respond);
    get_ [ "favicon-16x16.png" ] (fun rctx respond -> embedded_file "favicon-16x16.png" rctx respond);
    get_ [ "apple-touch-icon.png" ] (fun rctx respond -> embedded_file "apple-touch-icon.png" rctx respond);
    get_ [ "site.webmanifest" ] (fun rctx respond -> embedded_file "site.webmanifest" rctx respond);
    (* Static files - not cached *)
    get ("images" / tail) (fun path -> static_file ~dir:cfg.paths.images_dir (String.concat "/" path));
  ]

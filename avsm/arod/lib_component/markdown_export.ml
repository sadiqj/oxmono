(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Markdown export for content negotiation.

    Produces markdown representations of pages for AI agents and tools.
    Uses Bushel's original markdown content with links resolved to absolute
    URLs via {!Bushel.Md.to_markdown}. *)

module Entry = Bushel.Entry
module Paper = Bushel.Paper
module Contact = Sortal_schema.Contact
module Feed = Sortal_schema.Feed

(** {1 Helpers} *)

let date_str (y, m, d) =
  Printf.sprintf "%04d-%02d-%02d" y m d

let entry_url ~ctx ent =
  Arod.Ctx.base_url ctx ^ Entry.site_url ent

let render_body ~ctx body =
  let base_url = Arod.Ctx.base_url ctx in
  let entries = Arod.Ctx.entries ctx in
  Bushel.Md.to_markdown ~base_url ~image_base:"/images" ~entries body

let tags_line ~ctx ent =
  match Arod.Ctx.tags_of_ent ctx ent with
  | [] -> ""
  | tags ->
    let strs = List.map Bushel.Tags.to_string tags in
    "Tags: " ^ String.concat ", " strs ^ "\n"

let footer ~ctx ent =
  let url = entry_url ~ctx ent in
  let type_str = Entry.to_type_string ent in
  Printf.sprintf "\n---\nCanonical: %s\nType: %s\n%s"
    url type_str (tags_line ~ctx ent)

(** {1 Entry to Markdown} *)

let entry_to_markdown ~ctx ent =
  let title = Entry.title ent in
  let d = Entry.date ent in
  let type_str = Entry.to_type_string ent in
  let header = Printf.sprintf "# %s\n\n*%s — %s*\n\n" title (date_str d) type_str in
  let body_md = match ent with
    | `Paper p ->
      let abs = Paper.abstract p in
      let authors = String.concat ", " (Paper.authors p) in
      let doi_line = match Paper.doi p with
        | Some doi -> Printf.sprintf "DOI: %s\n" doi
        | None -> ""
      in
      Printf.sprintf "Authors: %s\n\n%s%s" authors
        (if abs <> "" then render_body ~ctx abs ^ "\n\n" else "")
        doi_line
    | `Video v ->
      let desc = Bushel.Video.description v in
      if desc <> "" then render_body ~ctx desc else ""
    | _ ->
      let body = Entry.body ent in
      if body <> "" then render_body ~ctx body else ""
  in
  header ^ body_md ^ footer ~ctx ent

(** {1 List Page Helpers} *)

let list_header ~ctx ~title ~description ~path =
  let base = Arod.Ctx.base_url ctx in
  let footer = Printf.sprintf "\n---\nCanonical: %s%s\nFeeds: [Atom](%s/feeds/atom.xml), [JSON](%s/feed.json)\n"
    base path base base
  in
  (Printf.sprintf "# %s\n\n%s\n\n" title description, footer)

let entry_bullet ~ctx ent =
  let title = Entry.title ent in
  let url = entry_url ~ctx ent in
  let d = date_str (Entry.date ent) in
  Printf.sprintf "- [%s](%s) (%s)" title url d

(** {1 List Pages} *)

let papers_list_md ~ctx =
  let papers = Arod.Ctx.papers ctx in
  let header, footer = list_header ~ctx ~title:"Papers" ~description:"Academic papers." ~path:"/papers" in
  let items = List.map (fun paper ->
    let ent = `Paper paper in
    let title = Paper.title paper in
    let url = entry_url ~ctx ent in
    let (y, _, _) = Entry.date ent in
    let authors = String.concat ", " (Paper.authors paper) in
    Printf.sprintf "- [%s](%s) (%d) — %s" title url y authors
  ) papers in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let notes_list_md ~ctx =
  let notes = Arod.Ctx.notes ctx in
  let header, footer = list_header ~ctx ~title:"Notes" ~description:"Notes and blog posts." ~path:"/notes" in
  let items = List.map (fun note ->
    entry_bullet ~ctx (`Note note)
  ) notes in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let ideas_list_md ~ctx =
  let ideas = Arod.Ctx.ideas ctx in
  let header, footer = list_header ~ctx ~title:"Research Ideas" ~description:"Research ideas." ~path:"/ideas" in
  let items = List.map (fun idea ->
    entry_bullet ~ctx (`Idea idea)
  ) ideas in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let projects_list_md ~ctx =
  let projects = Arod.Ctx.projects ctx in
  let header, footer = list_header ~ctx ~title:"Projects" ~description:"Research projects." ~path:"/projects" in
  let items = List.map (fun proj ->
    entry_bullet ~ctx (`Project proj)
  ) projects in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let videos_list_md ~ctx =
  let videos = Arod.Ctx.videos ctx in
  let header, footer = list_header ~ctx ~title:"Talks" ~description:"Conference talks and presentations." ~path:"/videos" in
  let items = List.map (fun vid ->
    entry_bullet ~ctx (`Video vid)
  ) videos in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let links_list_md ~ctx =
  let entries = Arod.Ctx.entries ctx in
  let all_links = Bushel.Link_graph.all_external_links () in
  let by_source : (string, Bushel.Link_graph.external_link list) Hashtbl.t =
    Hashtbl.create 128 in
  List.iter (fun (link : Bushel.Link_graph.external_link) ->
    let cur = try Hashtbl.find by_source link.source with Not_found -> [] in
    if List.exists (fun (l : Bushel.Link_graph.external_link) -> l.url = link.url) cur then ()
    else Hashtbl.replace by_source link.source (link :: cur)
  ) all_links;
  let groups = Hashtbl.fold (fun slug links acc ->
    match Entry.lookup entries slug with
    | Some ent -> (ent, links) :: acc
    | None -> acc
  ) by_source [] in
  let groups = List.sort (fun (a, _) (b, _) ->
    compare (Entry.date b) (Entry.date a)
  ) groups in
  let base = Arod.Ctx.base_url ctx in
  let header = "# Links\n\nOutbound links grouped by source entry.\n\n" in
  let sections = List.map (fun (ent, links) ->
    let title = Entry.title ent in
    let url = entry_url ~ctx ent in
    let link_lines = List.map (fun (link : Bushel.Link_graph.external_link) ->
      let label = match Arod.Ctx.link_for_url ctx link.url with
        | Some l ->
          let meta = match l.karakeep with Some k -> k.metadata | None -> [] in
          (match List.assoc_opt "title" meta with Some t -> t | None -> link.domain)
        | None -> link.domain
      in
      Printf.sprintf "  - [%s](%s)" label link.url
    ) links in
    Printf.sprintf "- **[%s](%s)**\n%s" title url (String.concat "\n" link_lines)
  ) groups in
  let footer = Printf.sprintf "\n---\nCanonical: %s/links\n" base in
  header ^ String.concat "\n" sections ^ "\n" ^ footer

let network_md ~ctx =
  let all_contacts = Arod.Ctx.contacts ctx in
  let contacts_with_feeds = List.filter_map (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> Some (contact, feeds)
    | _ -> None
  ) all_contacts in
  let contacts_with_feeds = List.sort (fun (a, _) (b, _) ->
    String.compare (Contact.name a) (Contact.name b)
  ) contacts_with_feeds in
  let base = Arod.Ctx.base_url ctx in
  let header = "# Network\n\nUnified timeline of activity and contact feeds.\n\n" in
  let items = List.map (fun (contact, feeds) ->
    let name = Contact.name contact in
    let feed_links = List.map (fun feed ->
      let ft = match Feed.feed_type feed with
        | Feed.Atom -> "Atom" | Feed.Rss -> "RSS" | Feed.Json -> "JSON"
      in
      Printf.sprintf "[%s](%s)" ft (Feed.url feed)
    ) feeds in
    Printf.sprintf "- **%s**: %s" name (String.concat ", " feed_links)
  ) contacts_with_feeds in
  let footer = Printf.sprintf "\n---\nCanonical: %s/network\n" base in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let index_md ~ctx =
  match Arod.Ctx.lookup ctx "index" with
  | None -> ""
  | Some ent ->
    let title = Entry.title ent in
    let body = Entry.body ent in
    let base = Arod.Ctx.base_url ctx in
    let body_md = if body <> "" then render_body ~ctx body else "" in
    Printf.sprintf "# %s\n\n%s\n\n---\nCanonical: %s\n" title body_md base

let wiki_md ~ctx =
  let all = Arod.Ctx.all_entries ctx in
  let all = List.sort (fun a b -> compare (Entry.date b) (Entry.date a)) all in
  let base = Arod.Ctx.base_url ctx in
  let header = "# All Entries\n\n" in
  let items = List.map (fun ent ->
    let type_str = Entry.to_type_string ent in
    let title = Entry.title ent in
    let url = entry_url ~ctx ent in
    let d = date_str (Entry.date ent) in
    Printf.sprintf "- [%s](%s) (%s, %s)" title url type_str d
  ) all in
  let footer = Printf.sprintf "\n---\nCanonical: %s/wiki\n" base in
  header ^ String.concat "\n" items ^ "\n" ^ footer

let news_md ~ctx =
  let notes = Arod.Ctx.notes ctx in
  let base = Arod.Ctx.base_url ctx in
  let header = "# News\n\n" in
  let items = List.map (fun note ->
    entry_bullet ~ctx (`Note note)
  ) notes in
  let footer = Printf.sprintf "\n---\nCanonical: %s/news\n" base in
  header ^ String.concat "\n" items ^ "\n" ^ footer

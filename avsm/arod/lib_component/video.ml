(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Video component rendering using htmlit. *)

open Htmlit

module Video = Bushel.Video
module I = Arod.Icons

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let full_month_name = function
  | 1 -> "January" | 2 -> "February" | 3 -> "March" | 4 -> "April"
  | 5 -> "May" | 6 -> "June" | 7 -> "July" | 8 -> "August"
  | 9 -> "September" | 10 -> "October" | 11 -> "November" | 12 -> "December"
  | _ -> ""

(** {1 Video Card} *)

(** Terminal-style video card for listings. *)
let video_card ~ctx v =
  let (y, m, _d) = Video.date v in
  let date_str = Printf.sprintf "%s %d" (month_name m) y in
  let slug = Video.slug v in
  let url = "/videos/" ^ slug in
  (* Inline embed — rendered via bushel markdown, scaled down in CSS *)
  let embed_md = Printf.sprintf "![%%c](:%s)" slug in
  let embed_html = fst (Arod.Md.to_html ~ctx embed_md) in
  let embed_el =
    El.div ~at:[At.class' "vid-card-embed"]
      [El.unsafe_raw embed_html]
  in
  (* Description — rendered through bushel resolver *)
  let desc = Video.description v in
  let desc_el =
    if desc = "" then El.void
    else
      El.div ~at:[At.class' "vid-card-desc"]
        [El.unsafe_raw (Arod.Md.to_plain_html ~ctx desc)]
  in
  (* Tags *)
  let tags = Video.tags v in
  let tags_el =
    if tags = [] then El.void
    else
      El.div ~at:[At.class' "vid-card-tags"]
        (List.map (fun t ->
          El.span ~at:[At.class' "proj-card-tag"] [El.txt t]
        ) tags)
  in
  (* Linked project/paper *)
  let links_els = List.filter_map Fun.id [
    (match Video.project v with
     | Some proj_slug ->
       let title = match Arod.Ctx.lookup ctx proj_slug with
         | Some (`Project proj) -> Bushel.Project.title proj
         | _ -> proj_slug
       in
       Some (El.div ~at:[At.class' "vid-card-ref"] [
         El.span ~at:[At.class' "vid-card-ref-icon"]
           [El.unsafe_raw (I.outline ~size:11 I.folder_o)];
         El.a ~at:[At.href ("/projects/" ^ proj_slug);
                   At.class' "project-entry-link"]
           [El.txt title]])
     | None -> None);
    (match Video.paper v with
     | Some paper_slug ->
       let title = match Arod.Ctx.lookup ctx paper_slug with
         | Some (`Paper paper) -> Bushel.Paper.title paper
         | _ -> paper_slug
       in
       Some (El.div ~at:[At.class' "vid-card-ref"] [
         El.span ~at:[At.class' "vid-card-ref-icon"]
           [El.unsafe_raw (I.outline ~size:11 I.paper_o)];
         El.a ~at:[At.href ("/papers/" ^ paper_slug);
                   At.class' "project-entry-link"]
           [El.txt title]])
     | None -> None);
  ] in
  (* Backlinks — other entries that reference this video *)
  let entries = Arod.Ctx.entries ctx in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug slug in
  let all_linked = List.filter_map (fun s ->
    match Bushel.Entry.lookup entries s with
    | Some ent -> Some ent
    | None -> None
  ) (backlink_slugs @ outbound_slugs) in
  (* Deduplicate and exclude self + already-shown project/paper *)
  let seen = Hashtbl.create 8 in
  let exclude_slugs = List.filter_map Fun.id [
    Video.project v; Video.paper v
  ] in
  List.iter (fun s -> Hashtbl.replace seen s ()) (slug :: exclude_slugs);
  let backlink_rows = List.filter_map (fun ent ->
    let s = Bushel.Entry.slug ent in
    if Hashtbl.mem seen s then None
    else begin
      Hashtbl.replace seen s ();
      let type_icon = Sidebar.entry_type_icon ~size:11 ent in
      Some (El.div ~at:[At.class' "vid-card-ref"] [
        El.span ~at:[At.class' "vid-card-ref-icon"]
          [El.unsafe_raw type_icon];
        El.a ~at:[At.href (Bushel.Entry.site_url ent);
                  At.class' "project-entry-link"]
          [El.txt (Bushel.Entry.title ent)]])
    end
  ) all_linked in
  let all_refs = links_els @ backlink_rows in
  let refs_el = match all_refs with
    | [] -> El.void
    | els -> El.div ~at:[At.class' "vid-card-refs"] els
  in
  El.div ~at:[At.class' "vid-card not-prose"] [
    (* Header — terminal style with ▶ prompt *)
    El.div ~at:[At.class' "vid-card-header"] [
      El.span ~at:[At.class' "vid-card-prompt"]
        [El.txt "\xe2\x96\xb6"];
      El.a ~at:[At.href url;
                At.class' "vid-card-title no-underline"]
        [El.txt (Video.title v)];
      El.span ~at:[At.class' "proj-card-date"] [El.txt date_str]];
    (* Embed *)
    embed_el;
    (* Body *)
    El.div ~at:[At.class' "vid-card-body"] [
      desc_el; tags_el; refs_el]]

(** {1 Videos List Page} *)

(** Masonry grid of talk cards (talks only, no year grouping). *)
let videos_list ~ctx =
  let all_entries = Arod.Ctx.all_entries ctx in
  let talks = List.filter_map (fun e ->
    match e with
    | `Video v when Video.talk v -> Some v
    | _ -> None
  ) all_entries in
  let talks = List.sort (fun a b ->
    compare (Video.date b) (Video.date a)
  ) talks in
  let cards = List.map (fun v -> video_card ~ctx v) talks in
  El.article [
    El.h1 ~at:[At.class' "page-title text-2xl font-semibold mb-4"]
      [El.txt "Talks"];
    El.div ~at:[At.class' "vid-grid"] cards]

(** {1 Full Video Page} *)

(** Full video page with embed and sidebar infobox.
    Returns [(article, sidebar)]. *)
let full_page ~ctx v =
  let slug = Video.slug v in
  let (y, m, d) = Video.date v in
  (* Video embed *)
  let embed_md = Printf.sprintf "![%%c](:%s)" slug in
  let embed_html = fst (Arod.Md.to_html ~ctx embed_md) in
  (* Description rendered as markdown *)
  let desc_html = Arod.Md.to_plain_html ~ctx (Video.description v) in
  let article = El.div [
    El.h1 ~at:[At.class' "page-title text-xl font-semibold mb-3"]
      [El.txt (Video.title v)];
    El.div ~at:[At.class' "vid-embed mb-6"] [El.unsafe_raw embed_html];
    El.div [El.unsafe_raw desc_html]]
  in
  (* Sidebar infobox *)
  let datetime_str = Printf.sprintf "%04d-%02d-%02d" y m d in
  let date_el =
    Sidebar.meta_line
      ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o)
      (El.time ~at:[At.v "datetime" datetime_str]
         [El.txt (Printf.sprintf "%d %s %d" d (full_month_name m) y)])
  in
  let type_el =
    let label = if Video.talk v then "Conference talk" else "Video" in
    let icon = if Video.talk v then I.presentation_o else I.video_o in
    Sidebar.meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 icon)
      (El.txt label)
  in
  let url_el =
    let host =
      let u = Video.url v in
      if String.length u > 8 then
        let after_scheme =
          try
            let i = String.index_from u 8 '/' in
            String.sub u 0 i
          with Not_found -> u
        in
        (* Strip https:// *)
        let prefix = "https://" in
        if String.length after_scheme > String.length prefix
           && String.sub after_scheme 0 (String.length prefix) = prefix then
          String.sub after_scheme (String.length prefix)
            (String.length after_scheme - String.length prefix)
        else after_scheme
      else "Watch"
    in
    Sidebar.meta_line
      ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.external_link_o)
      (El.a ~at:[At.href (Video.url v);
                 At.class' "sidebar-meta-link"]
         [El.txt host])
  in
  let proj_el = match Video.project v with
    | Some proj_slug ->
      let title = match Arod.Ctx.lookup ctx proj_slug with
        | Some (`Project proj) -> Bushel.Project.title proj
        | _ -> proj_slug
      in
      Sidebar.meta_line
        ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.folder_o)
        (El.a ~at:[At.href ("/projects/" ^ proj_slug);
                   At.class' "sidebar-meta-link"]
           [El.txt title])
    | None -> El.void
  in
  let paper_el = match Video.paper v with
    | Some paper_slug ->
      let title = match Arod.Ctx.lookup ctx paper_slug with
        | Some (`Paper paper) -> Bushel.Paper.title paper
        | _ -> paper_slug
      in
      Sidebar.meta_line
        ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.paper_o)
        (El.a ~at:[At.href ("/papers/" ^ paper_slug);
                   At.class' "sidebar-meta-link"]
           [El.txt title])
    | None -> El.void
  in
  let tags_el = match Video.tags v with
    | [] -> El.void
    | tags ->
      let tag_chips = List.map (fun tag ->
        El.span ~at:[At.class' "sidebar-tag"] [El.txt tag]
      ) tags in
      Sidebar.meta_line_block
        ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o)
        (El.div ~at:[At.class' "sidebar-meta-tags"] tag_chips)
  in
  let links_el, links_modal_el = Sidebar.entry_links ~ctx slug in
  (* Abbreviated URL for header — strip scheme, truncate path *)
  let abbrev_url =
    let u = Video.url v in
    let stripped =
      if String.length u > 8 && String.sub u 0 8 = "https://" then
        String.sub u 8 (String.length u - 8)
      else if String.length u > 7 && String.sub u 0 7 = "http://" then
        String.sub u 7 (String.length u - 7)
      else u
    in
    if String.length stripped > 30 then
      String.sub stripped 0 30 ^ "\xe2\x80\xa6"
    else stripped
  in
  let sidebar =
    El.div [
      El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
        El.div ~at:[At.class' "sidebar-meta-header"] [
          El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
          El.txt " ";
          El.a ~at:[At.href (Video.url v);
                    At.class' "sidebar-meta-link"] [El.txt abbrev_url]];
        El.div ~at:[At.class' "sidebar-meta-body"]
          [date_el; type_el; url_el; proj_el; paper_el; tags_el; links_el]];
      links_modal_el]
  in
  (article, sidebar)

(** Brief video rendering with embed/image and description. *)
let brief ~ctx v =
  let md =
    Printf.sprintf "![%%c](:%s)\n\n%s" v.Video.slug v.Video.description
  in
  let heading =
    El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
      El.a ~at:[At.href (Bushel.Entry.site_url (`Video v))] [
        El.txt (Video.title v)];
      El.span ~at:[At.class' "text-sm text-secondary"] [
        El.txt " / ";
        El.txt (Printf.sprintf "%s %4d"
          (month_name (let (_, m, _) = Video.date v in m))
          (let (y, _, _) = Video.date v in y))]]
  in
  let body = [
    heading;
    El.unsafe_raw (fst (Arod.Md.to_html ~ctx md))] in
  (El.div body, None)

(** Kept for backward compat — simple rendering for use in other contexts. *)
let full ~ctx v = fst (full_page ~ctx v)

(** Video for feeds. *)
let for_feed ~ctx v =
  let md = Printf.sprintf "![%%c](:%s)\n\n" v.Video.slug in
  (El.unsafe_raw (fst (Arod.Md.to_html ~ctx md)), None)

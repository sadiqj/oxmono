(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Sidebar component for entry pages.

    Shows contextual information including thumbnail, DOI link,
    related entries via backlinks, PDF download link for papers,
    and a container for JS-populated sidenotes. *)

open Htmlit

module Entry = Bushel.Entry
module Paper = Bushel.Paper
module Note = Bushel.Note
module I = Arod.Icons

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_full (y, m, d) =
  Printf.sprintf "%d %s %4d" d (month_name m) y

let meta_line ~label value =
  El.p ~at:[At.class' "sidebar-meta-line"] [
    El.span ~at:[At.class' "sidebar-meta-key"] [El.txt label];
    El.span ~at:[At.class' "sidebar-meta-val"] [value]]

(** Note-specific metadata for sidebar. *)
let note_meta ~ctx n =
  let (y, m, d) = Bushel.Entry.date (`Note n) in
  let datetime_str = Printf.sprintf "%04d-%02d-%02d" y m d in
  let date_el =
    meta_line ~label:"date" (El.span [
      El.time ~at:[At.v "datetime" datetime_str]
        [El.txt datetime_str];
      (match n.Note.updated with
       | Some (uy, um, ud) ->
         let udt = Printf.sprintf "%04d-%02d-%02d" uy um ud in
         El.span [El.txt " ";
                  El.span ~at:[At.class' "sidebar-meta-key"] [El.txt "upd "];
                  El.time ~at:[At.v "datetime" udt]
                    [El.txt udt]]
       | None -> El.void)])
  in
  let words_el =
    let wc = Bushel.Note.words n in
    if wc > 0 then
      meta_line ~label:"words" (El.txt (string_of_int wc))
    else El.void
  in
  let category_el = match Bushel.Note.category n with
    | Some cat -> meta_line ~label:"type" (El.txt cat)
    | None -> El.void
  in
  let source_el = match Bushel.Note.source n, Bushel.Note.author n with
    | Some src, Some auth ->
      meta_line ~label:"via" (El.span [
        El.txt auth; El.txt " / ";
        (match Bushel.Note.url n with
         | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt src]
         | None -> El.txt src)])
    | Some src, None ->
      meta_line ~label:"via" (
        match Bushel.Note.url n with
         | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt src]
         | None -> El.txt src)
    | None, _ -> El.void
  in
  let doi_el = match Bushel.Note.doi n with
    | Some doi_str ->
      meta_line ~label:"doi" (
        El.a ~at:[At.href ("https://doi.org/" ^ doi_str);
                  At.class' "sidebar-meta-link"] [El.txt doi_str])
    | None -> El.void
  in
  let tags_el =
    let all_tags = Arod.Ctx.tags_of_ent ctx (`Note n) in
    match all_tags with
    | [] -> El.void
    | tags ->
      meta_line ~label:"tags" (El.span (
        List.concat (List.mapi (fun i tag ->
          let tag_str = Bushel.Tags.to_raw_string tag in
          let el = El.txt tag_str in
          if i > 0 then [El.txt " "; el] else [el]
        ) tags)))
  in
  let slug = Bushel.Note.slug n in
  let synopsis_el = match Bushel.Note.synopsis n with
    | Some syn ->
      El.p ~at:[At.class' "sidebar-meta-synopsis"] [El.txt syn]
    | None -> El.void
  in
  El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
    El.div ~at:[At.class' "sidebar-meta-header"] [
      El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
      El.txt " ";
      El.a ~at:[At.href (Bushel.Entry.site_url (`Note n));
                At.class' "sidebar-meta-link"] [El.txt slug]];
    El.div ~at:[At.class' "sidebar-meta-body"]
      [synopsis_el; date_el; words_el; category_el; source_el; doi_el; tags_el]]

let for_entry ~ctx ?(sidenotes=[]) ent =
  let entries = Arod.Ctx.entries ctx in

  (* Note-specific metadata *)
  let note_meta_el = match ent with
    | `Note n -> note_meta ~ctx n
    | _ -> El.void
  in

  (* DOI section (for non-notes) *)
  let doi_el =
    match ent with
    | `Note _ -> El.void  (* handled in note_meta *)
    | _ -> El.void
  in

  (* Related links from backlinks *)
  let slug = Entry.slug ent in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let related_el =
    let backlink_items = List.filter_map (fun backlink_slug ->
      match Entry.lookup entries backlink_slug with
      | Some entry ->
        let title = Entry.title entry in
        let url = Entry.site_url entry in
        let link = El.a ~at:[At.href url;
            At.class' "text-gray-600 hover:text-gray-900"]
            [El.txt title] in
        Some (El.li [link])
      | None -> None
    ) backlink_slugs in
    match backlink_items with
    | [] -> El.void
    | items ->
      El.div ~at:[At.class' "space-y-1 mt-2"] [
        El.h3 ~at:[At.class' "flex items-center gap-1 text-xs font-semibold text-gray-500 uppercase tracking-wide"]
          [El.unsafe_raw (I.outline ~size:14 I.tag_o); El.txt "Related"];
        El.ul ~at:[At.class' "text-sm space-y-0.5"] items]
  in

  (* PDF download link for papers *)
  let pdf_el =
    match ent with
    | `Paper paper ->
      let config = Arod.Ctx.config ctx in
      let pdf_path = Filename.concat config.paths.static_dir
        (Printf.sprintf "papers/%s.pdf" (Paper.slug paper)) in
      if Sys.file_exists pdf_path then
        El.a ~at:[At.href (Printf.sprintf "/papers/%s.pdf" (Paper.slug paper));
                  At.class' "mt-3 inline-flex items-center gap-1.5 text-sm text-green-600 font-medium"]
          [El.unsafe_raw (I.outline ~size:16 I.download_o); El.txt "Download PDF"]
      else El.void
    | _ -> El.void
  in

  (* Sidenotes container - rendered server-side *)
  let sidenotes_el =
    let sidenote_divs = List.map (fun (sn : Arod.Md.sidenote) ->
      let thumb_attr = match sn.thumb_url with
        | Some url -> [At.v "data-thumb" url]
        | None -> []
      in
      El.div ~at:([At.id ("sidenote-" ^ sn.slug);
                    At.class' Arod.Md.sidenote_div_class] @ thumb_attr)
        [El.unsafe_raw sn.content_html]
    ) sidenotes in
    El.div ~at:[At.id "sidenotes-container"; At.class' "relative"] sidenote_divs
  in

  (* Assemble sidebar *)
  El.aside
    ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
    [El.div ~at:[At.class' "relative h-full"]
       [El.div ~at:[At.class' "mb-6 pb-4 border-b border-gray-200"]
          [note_meta_el; doi_el; related_el; pdf_el];
        sidenotes_el]]

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

let meta_line ~icon value =
  El.p ~at:[At.class' "sidebar-meta-line"] [
    El.span ~at:[At.class' "sidebar-meta-icon"] [El.unsafe_raw icon];
    El.span ~at:[At.class' "sidebar-meta-val"] [value]]

(** Note-specific metadata for sidebar. *)
let note_meta ~ctx n =
  let (y, m, d) = n.Note.date in
  let datetime_str = Printf.sprintf "%04d-%02d-%02d" y m d in
  let date_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o) (El.span [
      El.time ~at:[At.v "datetime" datetime_str]
        [El.txt datetime_str];
      (match n.Note.updated with
       | Some (uy, um, ud) ->
         let udt = Printf.sprintf "%04d-%02d-%02d" uy um ud in
         El.span [El.txt " ";
                  El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:10 I.clock_o);
                  El.txt " ";
                  El.time ~at:[At.v "datetime" udt]
                    [El.txt udt]]
       | None -> El.void)])
  in
  let words_el =
    let wc = Bushel.Note.words n in
    if wc > 0 then
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.writing_o) (El.txt (string_of_int wc))
    else El.void
  in
  let category_el = match Bushel.Note.category n with
    | Some cat -> meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.category_o) (El.txt cat)
    | None -> El.void
  in
  let source_el = match Bushel.Note.source n, Bushel.Note.author n with
    | Some src, Some auth ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.link_o) (El.span [
        El.txt auth; El.txt " / ";
        (match Bushel.Note.url n with
         | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt src]
         | None -> El.txt src)])
    | Some src, None ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.link_o) (
        match Bushel.Note.url n with
         | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt src]
         | None -> El.txt src)
    | None, _ -> El.void
  in
  let doi_el = match Bushel.Note.doi n with
    | Some doi_str ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.fingerprint_o) (
        El.a ~at:[At.href ("https://doi.org/" ^ doi_str);
                  At.class' "sidebar-meta-link"] [El.txt doi_str])
    | None -> El.void
  in
  let tags_el =
    let all_tags = Arod.Ctx.tags_of_ent ctx (`Note n) in
    match all_tags with
    | [] -> El.void
    | tags ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o) (El.span (
        List.concat (List.mapi (fun i tag ->
          let tag_str = Bushel.Tags.to_raw_string tag in
          let el = El.txt tag_str in
          if i > 0 then [El.txt " "; el] else [el]
        ) tags)))
  in
  let slug = Bushel.Note.slug n in
  let entries = Arod.Ctx.entries ctx in
  let synopsis_el = match Bushel.Note.synopsis n with
    | Some syn ->
      El.p ~at:[At.class' "sidebar-meta-synopsis"] [El.txt syn]
    | None -> El.void
  in
  (* Collect forward links (→) and backlinks (←), resolve to entries with direction *)
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug slug in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let resolve_links dir slugs = List.filter_map (fun s ->
    match Entry.lookup entries s with
    | Some entry -> Some (dir, entry)
    | None -> None
  ) slugs in
  let all_links =
    resolve_links `Forward outbound_slugs @ resolve_links `Back backlink_slugs in
  (* Sort by date descending *)
  let all_links = List.sort (fun (_, a) (_, b) ->
    let (ay, am, ad) = Entry.date b and (by, bm, bd) = Entry.date a in
    compare (ay, am, ad) (by, bm, bd)
  ) all_links in
  let total = List.length all_links in
  let max_shown = 5 in
  let render_link_row (dir, entry) =
    let icon = match dir with
      | `Forward -> I.outline ~cl:"opacity-40" ~size:10 I.arrow_right_o
      | `Back -> I.outline ~cl:"opacity-40" ~size:10 I.arrow_left_o
    in
    El.p ~at:[At.class' "sidebar-meta-linkline"] [
      El.span ~at:[At.class' "sidebar-meta-icon"] [El.unsafe_raw icon];
      El.a ~at:[At.href (Entry.site_url entry);
                At.class' "sidebar-meta-link"] [El.txt (Entry.title entry)]]
  in
  let links_el = match all_links with
    | [] -> El.void
    | _ ->
      let shown = List.filteri (fun i _ -> i < max_shown) all_links in
      let rows = List.map render_link_row shown in
      let expand_btn =
        if total > max_shown then
          El.button ~at:[At.id "links-expand-btn";
                         At.class' "sidebar-meta-expand"]
            [El.txt (Printf.sprintf "+ %d more" (total - max_shown))]
        else El.void
      in
      El.div ~at:[At.class' "sidebar-meta-links"]
        (rows @ [expand_btn])
  in
  (* Full links modal (rendered server-side, hidden until JS activates) *)
  let links_modal_el =
    if total > max_shown then
      let all_rows = List.map (fun (dir, entry) ->
        let icon = match dir with
          | `Forward -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_right_o
          | `Back -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_left_o
        in
        let (ey, em, _ed) = Entry.date entry in
        let date_str = Printf.sprintf "%s %d" (month_name em) ey in
        El.div ~at:[At.class' "links-modal-row"] [
          El.span ~at:[At.class' "links-modal-icon"] [El.unsafe_raw icon];
          El.a ~at:[At.href (Entry.site_url entry);
                    At.class' "links-modal-link"] [El.txt (Entry.title entry)];
          El.span ~at:[At.class' "links-modal-date"] [El.txt date_str]]
      ) all_links in
      El.div ~at:[At.id "links-modal-overlay";
                  At.class' "links-modal-overlay"] [
        El.div ~at:[At.class' "links-modal"] [
          El.div ~at:[At.class' "links-modal-header"] [
            El.span [El.txt (Printf.sprintf "Links (%d)" total)];
            El.button ~at:[At.id "links-modal-close";
                           At.class' "links-modal-close-btn"]
              [El.txt "\xC3\x97"]];
          El.div ~at:[At.class' "links-modal-body"] all_rows]]
    else El.void
  in
  El.div [
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Note n));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        [synopsis_el; date_el; words_el; category_el; source_el; doi_el; tags_el;
         links_el]];
    links_modal_el]

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

  (* Related links from backlinks — for non-note entries only (notes have links in meta box) *)
  let related_el = match ent with
    | `Note _ -> El.void
    | _ ->
      let slug = Entry.slug ent in
      let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
      let backlink_items = List.filter_map (fun backlink_slug ->
        match Entry.lookup entries backlink_slug with
        | Some entry ->
          let title = Entry.title entry in
          let url = Entry.site_url entry in
          let link = El.a ~at:[At.href url;
              At.class' "text-secondary"]
              [El.txt title] in
          Some (El.li [link])
        | None -> None
      ) backlink_slugs in
      match backlink_items with
      | [] -> El.void
      | items ->
        El.div ~at:[At.class' "space-y-1 mt-2"] [
          El.h3 ~at:[At.class' "flex items-center gap-1 text-xs font-semibold text-muted uppercase tracking-wide"]
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
                  At.class' "mt-3 inline-flex items-center gap-1.5 text-sm text-accent font-medium"]
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
       [El.div ~at:[At.class' "mb-4"]
          [note_meta_el; doi_el; related_el; pdf_el];
        sidenotes_el]]

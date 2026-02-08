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

let for_entry ~ctx ?(sidenotes=[]) ent =
  let entries = Arod.Ctx.entries ctx in

  (* Thumbnail section *)
  let thumbnail_el =
    match Entry.thumbnail entries ent with
    | Some thumb_url ->
      El.img ~at:[At.src thumb_url; At.alt (Entry.title ent);
               At.v "loading" "lazy";
               At.class' "rounded-lg mb-4 w-full"] ()
    | None ->
      (* Gradient placeholder *)
      El.div
        ~at:[At.class' "aspect-video rounded-lg mb-4 bg-gradient-to-br from-green-100 to-emerald-200"]
        []
  in

  (* DOI section *)
  let doi_el =
    match ent with
    | `Note n when Note.perma n ->
      (match Note.doi n with
       | Some doi_str ->
         El.p ~at:[At.class' "text-xs text-gray-500 mb-3"] [
           El.txt "DOI: ";
           El.a ~at:[At.href ("https://doi.org/" ^ doi_str);
                     At.class' "text-gray-500"]
             [El.txt doi_str]]
       | None -> El.void)
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
      El.div ~at:[At.class' "space-y-2"] [
        El.h3 ~at:[At.class' "text-xs font-semibold text-gray-500 uppercase tracking-wide"]
          [El.txt "Related"];
        El.ul ~at:[At.class' "text-sm space-y-1"] items]
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
                  At.class' "mt-4 flex items-center gap-2 text-sm text-green-600 font-medium"]
          [El.txt "Download PDF"]
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
       [El.div ~at:[At.class' "mb-8 pb-6 border-b border-gray-200"]
          [thumbnail_el; doi_el; related_el; pdf_el];
        sidenotes_el]]

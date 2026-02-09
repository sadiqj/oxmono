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

(** Like [meta_line] but uses div elements so block-level children
    (e.g. popover cards) are valid HTML and don't get restructured
    by the browser. *)
let meta_line_block ~icon value =
  El.div ~at:[At.class' "sidebar-meta-line"] [
    El.span ~at:[At.class' "sidebar-meta-icon"] [El.unsafe_raw icon];
    El.div ~at:[At.class' "sidebar-meta-val"] [value]]

(** {1 Shared Links Section}

    Resolves forward + backlinks for a slug, renders a compact list
    with overflow modal. Returns [(links_el, modal_el)]. *)

(** Icon for an entry's type (note, paper, idea, etc.). *)
let entry_type_icon ?(size=10) entry =
  let svg = match entry with
    | `Note _ -> I.writing_o
    | `Paper _ -> I.paper_o
    | `Idea _ -> I.bulb_o
    | `Project _ -> I.folder_o
    | `Video _ -> I.video_o
  in
  I.outline ~cl:"opacity-40" ~size svg

let entry_links ~ctx slug =
  let entries = Arod.Ctx.entries ctx in
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug slug in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let resolve dir slugs = List.filter_map (fun s ->
    match Entry.lookup entries s with
    | Some entry -> Some (dir, entry)
    | None -> None
  ) slugs in
  let all_links =
    resolve `Forward outbound_slugs @ resolve `Back backlink_slugs in
  (* Deduplicate by slug, keeping first occurrence *)
  let seen = Hashtbl.create 16 in
  let all_links = List.filter (fun (_, entry) ->
    let s = Entry.slug entry in
    if Hashtbl.mem seen s then false
    else (Hashtbl.add seen s (); true)
  ) all_links in
  let all_links = List.sort (fun (_, a) (_, b) ->
    let (ay, am, ad) = Entry.date b and (by, bm, bd) = Entry.date a in
    compare (ay, am, ad) (by, bm, bd)
  ) all_links in
  let total = List.length all_links in
  let max_shown = 5 in
  let render_link_row (dir, entry) =
    let dir_icon = match dir with
      | `Forward -> I.outline ~cl:"opacity-40" ~size:10 I.arrow_right_o
      | `Back -> I.outline ~cl:"opacity-40" ~size:10 I.arrow_left_o
    in
    let type_icon = entry_type_icon ~size:10 entry in
    El.p ~at:[At.class' "sidebar-meta-linkline"] [
      El.span ~at:[At.class' "sidebar-meta-icon"] [El.unsafe_raw dir_icon];
      El.span ~at:[At.class' "sidebar-link-type-icon"] [El.unsafe_raw type_icon];
      El.a ~at:[At.href (Entry.site_url entry);
                At.class' "sidebar-meta-link sidebar-link-title"]
        [El.txt (Entry.title entry)]]
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
  let modal_el =
    if total > max_shown then
      let all_rows = List.map (fun (dir, entry) ->
        let dir_icon = match dir with
          | `Forward -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_right_o
          | `Back -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_left_o
        in
        let type_icon = entry_type_icon ~size:12 entry in
        let (ey, em, _ed) = Entry.date entry in
        let date_str = Printf.sprintf "%s %d" (month_name em) ey in
        El.div ~at:[At.class' "links-modal-row"] [
          El.span ~at:[At.class' "links-modal-icon"] [El.unsafe_raw dir_icon];
          El.span ~at:[At.class' "links-modal-type-icon"] [El.unsafe_raw type_icon];
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
  (links_el, modal_el)

(** {1 Contact Popover}

    Shared hover card for contacts. Shows photo, name, current org,
    and social links. Reusable from sidebar avatars and sidenotes. *)

module Contact = Sortal_schema.Contact

let contact_initials name =
  match String.split_on_char ' ' name with
  | f :: l :: _ when String.length f > 0 && String.length l > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
    ^ String.make 1 (Char.uppercase_ascii l.[0])
  | f :: _ when String.length f > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
  | _ -> "?"

let contact_popover_card contact ~thumb =
  let name = Contact.name contact in
  let org_el = match Contact.current_organization contact with
    | Some org ->
      let title_str = match org.Contact.title with
        | Some t -> t ^ ", "
        | None -> ""
      in
      [El.p ~at:[At.class' "popover-org"] [El.txt (title_str ^ org.Contact.name)]]
    | None -> []
  in
  let social_icons =
    let open Arod.Icons in
    let items = List.filter_map Fun.id [
      (match Contact.github_handle contact with
       | Some g -> Some (El.a ~at:[At.href ("https://github.com/" ^ g);
           At.v "title" "GitHub"; At.class' "popover-social-link"]
           [El.unsafe_raw (brand ~size:14 github_brand)])
       | None -> None);
      (match Contact.twitter_handle contact with
       | Some t -> Some (El.a ~at:[At.href ("https://twitter.com/" ^ t);
           At.v "title" "X"; At.class' "popover-social-link"]
           [El.unsafe_raw (brand ~size:14 x_brand)])
       | None -> None);
      (match Contact.bluesky_handle contact with
       | Some b -> Some (El.a ~at:[At.href ("https://bsky.app/profile/" ^ b);
           At.v "title" "Bluesky"; At.class' "popover-social-link"]
           [El.unsafe_raw (brand ~size:14 bluesky_brand)])
       | None -> None);
      (match Contact.current_url contact with
       | Some u -> Some (El.a ~at:[At.href u;
           At.v "title" "Website"; At.class' "popover-social-link"]
           [El.unsafe_raw (outline ~size:14 world_o)])
       | None -> None);
      (match Contact.orcid contact with
       | Some o -> Some (El.a ~at:[At.href ("https://orcid.org/" ^ o);
           At.v "title" "ORCID"; At.class' "popover-social-link"]
           [El.unsafe_raw (brand ~size:14 orcid_brand)])
       | None -> None);
    ] in
    match items with
    | [] -> []
    | _ -> [El.div ~at:[At.class' "popover-socials"] items]
  in
  let photo_el = match thumb with
    | Some src ->
      El.img ~at:[At.src src; At.v "alt" name;
                  At.class' "popover-photo"] ()
    | None ->
      El.span ~at:[At.class' "popover-photo-initials"]
        [El.txt (contact_initials name)]
  in
  let name_el = match Contact.best_url contact with
    | Some u -> El.a ~at:[At.href u; At.class' "popover-name"] [El.txt name]
    | None -> El.span ~at:[At.class' "popover-name"] [El.txt name]
  in
  El.div ~at:[At.class' "contact-popover"]
    ([El.div ~at:[At.class' "popover-row"]
        [photo_el;
         El.div ~at:[At.class' "popover-info"]
           ([name_el] @ org_el)]]
     @ social_icons)

(** Inline avatar with hover popover. *)
let contact_avatar ~ctx contact =
  let entries = Arod.Ctx.entries ctx in
  let name = Contact.name contact in
  let thumb = Bushel.Entry.contact_thumbnail entries contact in
  let img_el = match thumb with
    | Some src ->
      El.img ~at:[At.src src; At.v "alt" name;
                  At.class' "sidebar-avatar-img"] ()
    | None ->
      El.span ~at:[At.class' "sidebar-avatar-initials"]
        [El.txt (contact_initials name)]
  in
  let popover = contact_popover_card contact ~thumb in
  let wrapper =
    El.div ~at:[At.class' "sidebar-avatar-wrap"] [
      El.div ~at:[At.class' "sidebar-avatar"] [img_el];
      popover]
  in
  match Contact.best_url contact with
  | Some u -> El.a ~at:[At.href u; At.class' "no-underline sidebar-avatar-wrap-link"] [wrapper]
  | None -> wrapper

(** {1 Entry-type Meta Boxes} *)

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
      let tag_chips = List.map (fun tag ->
        El.span ~at:[At.class' "sidebar-tag"]
          [El.txt (Bushel.Tags.to_raw_string tag)]
      ) tags in
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o)
        (El.div ~at:[At.class' "sidebar-meta-tags"] tag_chips)
  in
  let slug = Bushel.Note.slug n in
  let synopsis_el = match Bushel.Note.synopsis n with
    | Some syn ->
      El.p ~at:[At.class' "sidebar-meta-synopsis"] [El.txt syn]
    | None -> El.void
  in
  let links_el, links_modal_el = entry_links ~ctx slug in
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

module Idea = Bushel.Idea

(** Idea-specific metadata for sidebar. *)
let idea_meta ~ctx i =
  let slug = Idea.slug i in
  let status_el =
    let label = Idea.status_to_string (Idea.status i) in
    let cls = match Idea.status i with
      | Idea.Available -> "idea-available"
      | Discussion -> "idea-discussion"
      | Ongoing -> "idea-ongoing"
      | Completed -> "idea-completed"
      | Expired -> "idea-expired"
    in
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.bulb_o)
      (El.span ~at:[At.class' cls] [El.txt label])
  in
  let year_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o)
      (El.txt (string_of_int (Idea.year i)))
  in
  let level_str = match Idea.level i with
    | Idea.Any -> "Any" | PartII -> "Part II" | MPhil -> "MPhil"
    | PhD -> "PhD" | Postdoc -> "Postdoc"
  in
  let level_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.category_o)
      (El.txt level_str)
  in
  let render_avatars handles =
    let avatars = List.filter_map (fun handle ->
      match Arod.Ctx.lookup_by_handle ctx handle with
      | Some contact -> Some (contact_avatar ~ctx contact)
      | None ->
        Some (El.div ~at:[At.class' "sidebar-avatar-wrap"] [
          El.div ~at:[At.class' "sidebar-avatar"] [
            El.span ~at:[At.class' "sidebar-avatar-initials"] [El.txt "?"]]])
    ) handles in
    El.div ~at:[At.class' "sidebar-avatar-row"] avatars
  in
  let sups_el = match i.Idea.supervisor_handles with
    | [] -> El.void
    | handles ->
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
        (render_avatars handles)
  in
  let studs_el = match i.Idea.student_handles with
    | [] -> El.void
    | handles ->
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
        (render_avatars handles)
  in
  let proj_el =
    let proj_slug = Idea.project i in
    let proj_title = match Arod.Ctx.lookup ctx proj_slug with
      | Some (`Project p) -> Bushel.Project.title p
      | _ -> proj_slug
    in
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.folder_o)
      (El.a ~at:[At.href ("/projects/" ^ proj_slug);
                 At.class' "sidebar-meta-link"] [El.txt proj_title])
  in
  let tags_el = match Idea.tags i with
    | [] -> El.void
    | tags ->
      let tag_chips = List.map (fun tag ->
        El.span ~at:[At.class' "sidebar-tag"] [El.txt tag]
      ) tags in
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o)
        (El.div ~at:[At.class' "sidebar-meta-tags"] tag_chips)
  in
  let url_el = match Idea.url i with
    | None -> El.void
    | Some u ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.link_o)
        (El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt u])
  in
  let links_el, links_modal_el = entry_links ~ctx slug in
  El.div [
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Idea i));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        [status_el; year_el; level_el; sups_el; studs_el; proj_el; tags_el; url_el;
         links_el]];
    links_modal_el]

(** Paper-specific metadata for sidebar. *)
let paper_meta ~ctx paper =
  let slug = Paper.slug paper in
  let (y, m, _) = Paper.date paper in
  let cfg = Arod.Ctx.config ctx in
  let entries = Arod.Ctx.entries ctx in

  (* Classification *)
  let cls_label = match Paper.classification paper with
    | Paper.Full -> "Full paper"
    | Short -> "Short / workshop"
    | Preprint -> "Preprint / tech report"
  in
  let cls_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.paper_o)
      (El.txt cls_label)
  in
  (* Date *)
  let month_name_short = function
    | 1 -> "January" | 2 -> "February" | 3 -> "March" | 4 -> "April"
    | 5 -> "May" | 6 -> "June" | 7 -> "July" | 8 -> "August"
    | 9 -> "September" | 10 -> "October" | 11 -> "November" | 12 -> "December"
    | _ -> ""
  in
  let date_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o)
      (El.txt (Printf.sprintf "%s %d" (month_name_short m) y))
  in
  (* Venue/publisher *)
  let venue_el =
    let bibty = String.lowercase_ascii (Paper.bibtype paper) in
    let venue = match bibty with
      | "inproceedings" | "abstract" -> Paper.booktitle paper
      | "article" | "journal" -> Paper.journal paper
      | "book" -> Paper.publisher paper
      | "techreport" -> Paper.institution paper
      | _ -> Paper.publisher paper
    in
    if venue <> "" then
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.presentation_o)
        (match Paper.url paper with
         | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt venue]
         | None -> El.txt venue)
    else El.void
  in
  (* DOI *)
  let doi_el = match Paper.doi paper with
    | Some doi_str ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.fingerprint_o)
        (El.a ~at:[At.href ("https://doi.org/" ^ doi_str);
                   At.class' "sidebar-meta-link"] [El.txt doi_str])
    | None -> El.void
  in
  (* Tags *)
  let tags_el =
    let all_tags = Arod.Ctx.tags_of_ent ctx (`Paper paper) in
    match all_tags with
    | [] -> El.void
    | tags ->
      let tag_chips = List.map (fun tag ->
        El.span ~at:[At.class' "sidebar-tag"]
          [El.txt (Bushel.Tags.to_raw_string tag)]
      ) tags in
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o)
        (El.div ~at:[At.class' "sidebar-meta-tags"] tag_chips)
  in
  (* Authors with avatars *)
  let author_names = Paper.authors paper in
  let author_els = List.map (fun name ->
    match Arod.Ctx.lookup_by_name ctx name with
    | Some contact ->
      let avatar = contact_avatar ~ctx contact in
      El.div ~at:[At.class' "sidebar-meta-line"] [
        El.span ~at:[At.class' "sidebar-meta-icon"] [avatar];
        El.span ~at:[At.class' "sidebar-meta-val"] [
          match Contact.best_url contact with
          | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt name]
          | None -> El.txt name]]
    | None ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
        (El.txt name)
  ) author_names in
  (* Action links *)
  let action_links =
    let links = List.filter_map Fun.id [
      (let pdf_path = Filename.concat cfg.paths.static_dir
        (Printf.sprintf "papers/%s.pdf" slug) in
       if Sys.file_exists pdf_path then
         Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.pdf" slug);
                         At.class' "sidebar-meta-link"]
                 [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.file_pdf_o);
                  El.txt " PDF"])
       else None);
      Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.bib" slug);
                       At.class' "sidebar-meta-link"]
              [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.braces_o);
               El.txt " BIB"]);
      (match Paper.url paper with
       | Some u -> Some (El.a ~at:[At.href u; At.class' "sidebar-meta-link"]
                           [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.external_link_o);
                            El.txt " URL"])
       | None -> None);
      (match Paper.doi paper with
       | Some d -> Some (El.a ~at:[At.href ("https://doi.org/" ^ d);
                                   At.class' "sidebar-meta-link"]
                           [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.fingerprint_o);
                            El.txt " DOI"])
       | None -> None);
    ] in
    match links with
    | [] -> El.void
    | _ ->
      El.div ~at:[At.class' "sidebar-meta-links"]
        (List.map (fun l ->
          El.p ~at:[At.class' "sidebar-meta-linkline"] [l]
        ) links)
  in
  (* Volume/issue/ISBN *)
  let vol_el = match Paper.volume paper, Paper.number paper with
    | Some v, Some n ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.hash_o)
        (El.txt (Printf.sprintf "Vol %s, Issue %s" v n))
    | Some v, None ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.hash_o)
        (El.txt (Printf.sprintf "Vol %s" v))
    | None, Some n ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.hash_o)
        (El.txt (Printf.sprintf "Issue %s" n))
    | None, None -> El.void
  in
  (* Related projects *)
  let proj_els = List.filter_map (fun proj_slug ->
    match Arod.Ctx.lookup ctx proj_slug with
    | Some (`Project proj) ->
      Some (meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.folder_o)
        (El.a ~at:[At.href ("/projects/" ^ proj_slug);
                   At.class' "sidebar-meta-link"]
           [El.txt (Bushel.Project.title proj)]))
    | _ -> None
  ) (Paper.project_slugs paper) in
  (* Forward/backlinks *)
  let links_el, links_modal_el = entry_links ~ctx slug in
  (* Older versions count *)
  let old_papers = Bushel.Entry.old_papers entries
    |> List.filter (fun op -> Paper.slug op = slug) in
  let versions_el = match old_papers with
    | [] -> El.void
    | revs ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.clock_o)
        (El.a ~at:[At.href "#older-versions"; At.class' "sidebar-meta-link"]
           [El.txt (Printf.sprintf "%d older version%s"
              (List.length revs) (if List.length revs > 1 then "s" else ""))])
  in
  El.div [
    (* Meta box *)
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        ([cls_el; date_el; venue_el; vol_el; doi_el; tags_el; versions_el]
         @ proj_els @ [action_links; links_el])];
    (* Authors box *)
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %d author%s"
          (List.length author_names) (if List.length author_names > 1 then "s" else ""))];
      El.div ~at:[At.class' "sidebar-meta-body"] author_els];
    links_modal_el]

let for_entry ~ctx ?(sidenotes=[]) ent =
  let entries = Arod.Ctx.entries ctx in

  (* Entry-specific metadata *)
  let note_meta_el = match ent with
    | `Note n -> note_meta ~ctx n
    | `Idea i -> idea_meta ~ctx i
    | `Paper p -> paper_meta ~ctx p
    | _ -> El.void
  in

  (* DOI section (for non-notes) *)
  let doi_el =
    match ent with
    | `Note _ -> El.void  (* handled in note_meta *)
    | _ -> El.void
  in

  (* Related links from backlinks — for entries without links in meta box *)
  let related_el = match ent with
    | `Note _ | `Idea _ | `Paper _ -> El.void
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

  (* PDF download link for papers — handled in paper_meta now *)
  let pdf_el = El.void in

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

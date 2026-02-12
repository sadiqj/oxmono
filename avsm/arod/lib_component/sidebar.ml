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

let contact_initials name =
  match String.split_on_char ' ' name with
  | f :: l :: _ when String.length f > 0 && String.length l > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
    ^ String.make 1 (Char.uppercase_ascii l.[0])
  | f :: _ when String.length f > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
  | _ -> "?"

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

let truncate_str n s =
  if String.length s <= n then s
  else String.sub s 0 n ^ "\xe2\x80\xa6"

let entry_links ~ctx slug =
  let entries = Arod.Ctx.entries ctx in
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug slug in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let feed_bls = Arod.Ctx.feed_backlinks_for_slug ctx slug in
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
  (* Convert feed backlinks into the same link-row format using `Feed dir *)
  let feed_link_rows = List.filter_map (fun (bl : Arod.Ctx.feed_backlink) ->
    let fe = bl.feed_entry in
    let title = match fe.Sortal_feed.Entry.title with
      | Some t -> t | None -> "(untitled)" in
    let url = match fe.Sortal_feed.Entry.url with
      | Some u -> Uri.to_string u | None -> "" in
    if String.length url > 0 then
      Some (`Feed, title, url)
    else None
  ) feed_bls in
  (* Merge all link types into one list *)
  let entry_rows = List.map (fun (dir, entry) ->
    let d = match dir with `Forward -> `Forward | `Back -> `Back in
    (d, Entry.title entry, Entry.site_url entry, Some (Entry.date entry), Some entry)
  ) all_links in
  let feed_rows = List.map (fun (dir, title, url) ->
    (dir, title, url, None, None)
  ) feed_link_rows in
  let combined = entry_rows @ feed_rows in
  let total = List.length combined in
  let max_shown = 5 in
  let render_row ~size (dir, title, url, _date, entry_opt) =
    let dir_icon = match dir with
      | `Forward -> I.outline ~cl:"opacity-40" ~size I.arrow_right_o
      | `Back -> I.outline ~cl:"opacity-40" ~size I.arrow_left_o
      | `Feed -> I.outline ~cl:"opacity-40" ~size I.arrow_up_o
    in
    let type_icon_el = match dir, entry_opt with
      | `Feed, _ ->
        [El.span ~at:[At.class' "sidebar-link-type-icon"]
          [El.unsafe_raw (I.brand ~cl:"opacity-40" ~size I.rss_brand)]]
      | _, Some entry ->
        [El.span ~at:[At.class' "sidebar-link-type-icon"]
          [El.unsafe_raw (entry_type_icon ~size entry)]]
      | _, None -> []
    in
    El.p ~at:[At.class' "sidebar-meta-linkline"]
      ([El.span ~at:[At.class' "sidebar-meta-icon"] [El.unsafe_raw dir_icon]]
       @ type_icon_el
       @ [El.a ~at:[At.href url;
                    At.class' "sidebar-meta-link sidebar-link-title"]
            [El.txt title]])
  in
  let links_el = match combined with
    | [] -> El.void
    | _ ->
      let shown = List.filteri (fun i _ -> i < max_shown) combined in
      let rows = List.map (render_row ~size:10) shown in
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
      let all_rows = List.map (fun (dir, title, url, date_opt, entry_opt) ->
        let dir_icon = match dir with
          | `Forward -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_right_o
          | `Back -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_left_o
          | `Feed -> I.outline ~cl:"opacity-40" ~size:12 I.arrow_up_o
        in
        let type_icon_el = match dir, entry_opt with
          | `Feed, _ ->
            [El.span ~at:[At.class' "links-modal-type-icon"]
              [El.unsafe_raw (I.brand ~cl:"opacity-40" ~size:12 I.rss_brand)]]
          | _, Some entry ->
            [El.span ~at:[At.class' "links-modal-type-icon"]
              [El.unsafe_raw (entry_type_icon ~size:12 entry)]]
          | _, None -> []
        in
        let date_str = match date_opt with
          | Some (ey, em, _ed) -> Printf.sprintf "%s %d" (month_name em) ey
          | None -> ""
        in
        El.div ~at:[At.class' "links-modal-row"]
          ([El.span ~at:[At.class' "links-modal-icon"] [El.unsafe_raw dir_icon]]
           @ type_icon_el
           @ [El.a ~at:[At.href url;
                        At.class' "links-modal-link"] [El.txt title];
              El.span ~at:[At.class' "links-modal-date"] [El.txt date_str]])
      ) combined in
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

(** {1 Activity Stream}

    Shared rendering for activity rows used by project and paper detail pages. *)

let ptime_date_short (y, m, _d) =
  Printf.sprintf "%s %4d" (month_name m) y

(** Render a single activity row with type icon, title, date, and detail. *)
let activity_row ~ctx ent =
  let open Htmlit in
  let contacts = Arod.Ctx.contacts ctx in
  let contact_name handle =
    List.find_map (fun c ->
      if Sortal_schema.Contact.handle c = handle
      then Some (Sortal_schema.Contact.name c)
      else None
    ) contacts
  in
  let plain md = Bushel.Md.plain_text_of_markdown ~contact_name md in
  let type_icon = entry_type_icon ~size:12 ent in
  let date_str = ptime_date_short (Entry.date ent) in
  let detail_el = match ent with
    | `Paper paper ->
      let authors = Paper.authors paper in
      let author_str = match authors with
        | [] -> ""
        | [a] -> a
        | a :: b :: _ -> a ^ ", " ^ b ^
          (if List.length authors > 2 then " et al." else "")
      in
      let venue = Paper.booktitle paper in
      let venue_str = if venue <> "" then venue else Paper.journal paper in
      let parts = List.filter (fun s -> s <> "") [author_str; venue_str] in
      if parts = [] then El.void
      else El.div ~at:[At.class' "project-activity-detail"]
        [El.txt (truncate_str 80 (String.concat " \xe2\x80\x94 " parts))]
    | `Idea i ->
      let status = Bushel.Idea.status_to_string (Bushel.Idea.status i) in
      let level = match Bushel.Idea.level i with
        | Bushel.Idea.Any -> "" | PartII -> "Part II"
        | MPhil -> "MPhil" | PhD -> "PhD" | Postdoc -> "Postdoc"
      in
      let parts = List.filter (fun s -> s <> "") [status; level] in
      El.div ~at:[At.class' "project-activity-detail"]
        [El.txt (String.concat " \xc2\xb7 " parts)]
    | `Note n ->
      (match Bushel.Note.synopsis n with
       | Some syn ->
         El.div ~at:[At.class' "project-activity-detail"]
           [El.txt (truncate_str 100 (plain syn))]
       | None ->
         let wc = Bushel.Note.words n in
         if wc > 0 then
           El.div ~at:[At.class' "project-activity-detail"]
             [El.txt (Printf.sprintf "%d words" wc)]
         else El.void)
    | `Video v ->
      let desc = Bushel.Video.description v in
      if desc <> "" then
        El.div ~at:[At.class' "project-activity-detail"]
          [El.txt (truncate_str 100 (plain desc))]
      else El.void
    | `Project _ -> El.void
  in
  El.div ~at:[At.class' "project-activity-row"] [
    El.span ~at:[At.class' "project-activity-icon"]
      [El.unsafe_raw type_icon];
    El.div ~at:[At.class' "project-activity-content"] [
      El.div ~at:[At.class' "project-activity-header"] [
        El.a ~at:[At.href (Entry.site_url ent);
                  At.class' "project-activity-title"]
          [El.txt (Entry.title ent)];
        El.span ~at:[At.class' "project-activity-date"]
          [El.txt date_str]];
      detail_el]]

(** Build an activity stream section from a list of entries.
    Returns [El.void] if the list is empty. *)
let activity_stream ~ctx ~title entries =
  let open Htmlit in
  match entries with
  | [] -> El.void
  | _ ->
    El.div ~at:[At.class' "mt-6"] [
      El.h2 ~at:[At.class' "text-lg font-semibold mb-3"] [El.txt title];
      El.div ~at:[At.class' "project-activity-list not-prose"]
        (List.map (activity_row ~ctx) entries)]

(** {1 Related Stream}

    Unified "Related" section combining bushel entry backlinks and feed
    backlinks at the very bottom of article pages, using type icons
    for entries and RSS icons for feed items. *)

(** Render a feed backlink as an activity row with RSS icon and contact name. *)
let feed_backlink_row (bl : Arod.Ctx.feed_backlink) =
  let open Htmlit in
  let fe = bl.feed_entry in
  let title_str = match fe.Sortal_feed.Entry.title with
    | Some t -> t | None -> "(untitled)"
  in
  let title_el = match fe.Sortal_feed.Entry.url with
    | Some u ->
      El.a ~at:[At.href (Uri.to_string u);
                At.class' "project-activity-title no-underline";
                At.v "rel" "noopener"]
        [El.txt title_str]
    | None ->
      El.span ~at:[At.class' "project-activity-title"]
        [El.txt title_str]
  in
  let date_str = match fe.Sortal_feed.Entry.date with
    | Some d ->
      let (y, m, _d), _ = Ptime.to_date_time d in
      ptime_date_short (y, m, 0)
    | None -> ""
  in
  let name = Sortal_schema.Contact.name bl.contact in
  let summary_el =
    let raw = match fe.Sortal_feed.Entry.summary with
      | Some s when String.length s > 0 -> Some s
      | _ -> match fe.Sortal_feed.Entry.content with
        | Some c when String.length c > 0 -> Some c
        | _ -> None
    in
    match Option.bind raw (Arod.Text.plain_summary ~max_len:100) with
    | Some text ->
      El.div ~at:[At.class' "project-activity-detail"]
        [El.txt text]
    | None -> El.void
  in
  El.div ~at:[At.class' "project-activity-row"] [
    El.span ~at:[At.class' "project-activity-icon"]
      [El.unsafe_raw (I.brand ~size:12 I.rss_brand)];
    El.div ~at:[At.class' "project-activity-content"] [
      El.div ~at:[At.class' "project-activity-header"] [
        title_el;
        El.span ~at:[At.class' "project-activity-date"]
          [El.txt date_str]];
      El.div ~at:[At.class' "project-activity-detail"]
        [El.txt name];
      summary_el]]

(** A unified item for sorting entry backlinks and feed backlinks together. *)
type related_item =
  | Entry_item of Entry.entry * (int * int * int)
  | Feed_item of Arod.Ctx.feed_backlink * (int * int * int)

(** Build a unified "Related" section combining bushel entry backlinks
    and feed backlinks, sorted newest-first.
    Returns [El.void] if there are no related items. *)
let related_stream ~ctx slug =
  let open Htmlit in
  let entries = Arod.Ctx.entries ctx in
  (* Bushel entry backlinks *)
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug slug in
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug slug in
  let seen = Hashtbl.create 16 in
  Hashtbl.replace seen slug ();
  let resolve_unique slugs =
    List.filter_map (fun s ->
      if Hashtbl.mem seen s then None
      else match Bushel.Entry.lookup entries s with
      | Some ent -> Hashtbl.replace seen s (); Some ent
      | None -> None
    ) slugs
  in
  let entry_items =
    (resolve_unique backlink_slugs @ resolve_unique outbound_slugs)
    |> List.map (fun ent -> Entry_item (ent, Entry.date ent))
  in
  (* Feed backlinks *)
  let feed_bls = Arod.Ctx.feed_backlinks_for_slug ctx slug in
  let feed_items = List.map (fun (bl : Arod.Ctx.feed_backlink) ->
    let d = match bl.feed_entry.Sortal_feed.Entry.date with
      | Some pt -> let (y, m, d), _ = Ptime.to_date_time pt in (y, m, d)
      | None -> (0, 0, 0)
    in
    Feed_item (bl, d)
  ) feed_bls in
  let all = List.sort (fun a b ->
    let da = match a with Entry_item (_, d) -> d | Feed_item (_, d) -> d in
    let db = match b with Entry_item (_, d) -> d | Feed_item (_, d) -> d in
    compare db da
  ) (entry_items @ feed_items) in
  match all with
  | [] -> El.void
  | items ->
    let rows = List.map (fun item ->
      match item with
      | Entry_item (ent, _) -> activity_row ~ctx ent
      | Feed_item (bl, _) -> feed_backlink_row bl
    ) items in
    El.div ~at:[At.class' "related-stream not-prose"] [
      El.h3 ~at:[At.class' "text-sm font-semibold text-secondary uppercase tracking-wide mb-2"]
        [El.txt "Related"];
      El.div ~at:[At.class' "project-activity-list"] rows]

(** {1 Contact Popover}

    Shared hover card for contacts. Shows photo, name, current org,
    and social links. Reusable from sidebar avatars and sidenotes. *)

module Contact = Sortal_schema.Contact

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
      (match Contact.linkedin contact with
       | Some svc -> Some (El.a ~at:[At.href svc.Contact.url;
           At.v "title" "LinkedIn"; At.class' "popover-social-link"]
           [El.unsafe_raw (brand ~size:14 linkedin_brand)])
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

(** Inline contact row with name + social icons (no popover). *)
let contact_inline ~ctx contact =
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
  let avatar_el =
    El.div ~at:[At.class' "sidebar-avatar"] [img_el]
  in
  let name_el = match Contact.best_url contact with
    | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt name]
    | None -> El.txt name
  in
  let social_icons =
    let open Arod.Icons in
    List.filter_map Fun.id [
      (match Contact.github_handle contact with
       | Some g -> Some (El.a ~at:[At.href ("https://github.com/" ^ g);
           At.v "title" "GitHub"; At.class' "contact-social-icon"]
           [El.unsafe_raw (brand ~size:12 github_brand)])
       | None -> None);
      (match Contact.twitter_handle contact with
       | Some t -> Some (El.a ~at:[At.href ("https://twitter.com/" ^ t);
           At.v "title" "X"; At.class' "contact-social-icon"]
           [El.unsafe_raw (brand ~size:12 x_brand)])
       | None -> None);
      (match Contact.bluesky_handle contact with
       | Some b -> Some (El.a ~at:[At.href ("https://bsky.app/profile/" ^ b);
           At.v "title" "Bluesky"; At.class' "contact-social-icon"]
           [El.unsafe_raw (brand ~size:12 bluesky_brand)])
       | None -> None);
      (match Contact.linkedin contact with
       | Some svc -> Some (El.a ~at:[At.href svc.Contact.url;
           At.v "title" "LinkedIn"; At.class' "contact-social-icon"]
           [El.unsafe_raw (brand ~size:12 linkedin_brand)])
       | None -> None);
      (match Contact.current_url contact with
       | Some u -> Some (El.a ~at:[At.href u;
           At.v "title" "Website"; At.class' "contact-social-icon"]
           [El.unsafe_raw (outline ~size:12 world_o)])
       | None -> None);
    ]
  in
  El.div ~at:[At.class' "sidebar-meta-line contact-inline-row"] [
    El.span ~at:[At.class' "sidebar-meta-icon"] [avatar_el];
    El.span ~at:[At.class' "sidebar-meta-val"] [name_el];
    El.span ~at:[At.class' "contact-inline-socials"] (social_icons)]

(** {1 Entry-type Meta Boxes} *)

(** Note-specific metadata for sidebar. *)
(** Shared social discussion icons for sidebar infoboxes. *)
let social_icons_el (social : Bushel.Types.social option) =
  match social with
  | None -> El.void
  | Some soc ->
    let icon_link ~icon ~label urls = List.map (fun url ->
      El.a ~at:[At.href url; At.class' "no-underline social-icon";
               At.v "title" label]
        [El.unsafe_raw icon]
    ) urls in
    let icons =
      icon_link ~label:"Bluesky" ~icon:(I.brand ~size:12 I.bluesky_brand) soc.bluesky
      @ icon_link ~label:"Hacker News" ~icon:(I.brand ~size:12 I.ycombinator_brand) soc.hn
      @ icon_link ~label:"LinkedIn" ~icon:(I.brand ~size:12 I.linkedin_brand) soc.linkedin
      @ icon_link ~label:"Lobsters" ~icon:(I.brand ~size:12 I.lobsters_brand) soc.lobsters
      @ icon_link ~label:"Mastodon" ~icon:(I.brand ~size:12 I.mastodon_brand) soc.mastodon
      @ icon_link ~label:"X" ~icon:(I.brand ~size:12 I.x_brand) soc.twitter
    in
    match icons with
    | [] -> El.void
    | _ ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.quote_o)
        (El.span ~at:[At.class' "flex items-center gap-2"] icons)

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
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.writing_o) (El.txt (Printf.sprintf "%d words" wc))
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
  let standardsite_el = match Bushel.Note.standardsite n with
    | Some ss_uri ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.world_o) (
        El.a ~at:[At.href ("https://pdsls.dev/" ^ ss_uri);
                  At.class' "sidebar-meta-link"] [El.txt "StandardSite"])
    | None -> El.void
  in
  let social_el = social_icons_el (Bushel.Note.social n) in
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
        [synopsis_el; date_el; words_el; category_el; source_el; doi_el;
         standardsite_el; social_el; links_el]];
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
  let render_people_box ~label handles =
    let els = List.filter_map (fun handle ->
      match Arod.Ctx.lookup_by_handle ctx handle with
      | Some contact -> Some (contact_inline ~ctx contact)
      | None ->
        Some (meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
          (El.txt ("@" ^ handle)))
    ) handles in
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %s" label)];
      El.div ~at:[At.class' "sidebar-meta-body"] els]
  in
  let sups_el = match i.Idea.supervisor_handles with
    | [] -> El.void
    | handles ->
      let n = List.length handles in
      render_people_box
        ~label:(Printf.sprintf "%d supervisor%s" n (if n > 1 then "s" else ""))
        handles
  in
  let studs_el = match i.Idea.student_handles with
    | [] -> El.void
    | handles ->
      let n = List.length handles in
      render_people_box
        ~label:(Printf.sprintf "%d student%s" n (if n > 1 then "s" else ""))
        handles
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
        El.a ~at:[At.class' "sidebar-tag"; At.v "data-tag" tag;
                  At.href ("#tag=" ^ tag)]
          [El.txt tag]
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
  let social_el = social_icons_el (Bushel.Idea.social i) in
  El.div [
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Idea i));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        [status_el; year_el; level_el; proj_el; tags_el; url_el;
         social_el; links_el]];
    sups_el;
    studs_el;
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
      El.p ~at:[At.class' "sidebar-meta-line sidebar-meta-wrap"] [
        El.span ~at:[At.class' "sidebar-meta-icon"]
          [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.presentation_o)];
        El.span ~at:[At.class' "sidebar-meta-val"]
          [match Paper.url paper with
           | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt venue]
           | None -> El.txt venue]]
    else El.void
  in
  (* DOI is shown inline with action links below *)

  (* Authors with inline social icons *)
  let author_names = Paper.authors paper in
  let author_els = List.map (fun name ->
    match Arod.Ctx.lookup_by_name ctx name with
    | Some contact -> contact_inline ~ctx contact
    | None ->
      meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
        (El.txt name)
  ) author_names in
  (* Human-readable file size *)
  let human_size bytes =
    if bytes < 1024 then Printf.sprintf "%d B" bytes
    else if bytes < 1024 * 1024 then Printf.sprintf "%d KB" (bytes / 1024)
    else Printf.sprintf "%.1f MB" (float_of_int bytes /. (1024.0 *. 1024.0))
  in
  (* Action links *)
  let bibtype = Paper.bibtype paper in
  let action_links =
    let links = List.filter_map Fun.id [
      (let pdf_path = Filename.concat cfg.paths.papers_dir
        (Printf.sprintf "%s.pdf" slug) in
       if Sys.file_exists pdf_path then
         let size = (Unix.stat pdf_path).Unix.st_size in
         Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.pdf" slug);
                         At.class' "sidebar-meta-link"]
                 [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.file_pdf_o);
                  El.txt (Printf.sprintf " PDF (%s)" (human_size size))])
       else None);
      Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.bib" slug);
                       At.class' "sidebar-meta-link"]
              [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.braces_o);
               El.txt (Printf.sprintf " BIB (%s)" bibtype)]);
      (match Paper.url paper with
       | Some u ->
         let host = match Uri.host (Uri.of_string u) with
           | None -> ""
           | Some h ->
             if String.starts_with ~prefix:"www." h then
               String.sub h 4 (String.length h - 4)
             else h
         in
         let label = if host <> "" then Printf.sprintf " URL (%s)" host else " URL" in
         Some (El.a ~at:[At.href u; At.class' "sidebar-meta-link"]
                 [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.external_link_o);
                  El.txt label])
       | None -> None);
      (match Paper.doi paper with
       | Some d -> Some (El.a ~at:[At.href ("https://doi.org/" ^ d);
                                   At.class' "sidebar-meta-link"]
                           [El.unsafe_raw (I.outline ~cl:"opacity-50" ~size:12 I.fingerprint_o);
                            El.txt (Printf.sprintf " DOI (%s)" d)])
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
  let social_el = social_icons_el (Bushel.Paper.social paper) in
  El.div [
    (* Meta box *)
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        ([cls_el; date_el; venue_el; vol_el; versions_el]
         @ proj_els @ [social_el; action_links; links_el])];
    (* Authors box *)
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %d author%s"
          (List.length author_names) (if List.length author_names > 1 then "s" else ""))];
      El.div ~at:[At.class' "sidebar-meta-body"] author_els];
    links_modal_el]

module Project = Bushel.Project

(** Project-specific metadata for sidebar. *)
let project_meta ~ctx proj =
  let slug = Project.slug proj in
  let all_entries = Arod.Ctx.all_entries ctx in
  (* Date range *)
  let date_range = match proj.Project.finish with
    | Some y -> Printf.sprintf "%d\xe2\x80\x93%d" proj.Project.start y
    | None -> Printf.sprintf "%d\xe2\x80\x93present" proj.Project.start
  in
  let date_el =
    meta_line ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o)
      (El.txt date_range)
  in
  (* Tags *)
  let tags_el = match Project.tags proj with
    | [] -> El.void
    | tags ->
      let tag_chips = List.map (fun tag ->
        El.a ~at:[At.class' "sidebar-tag"; At.v "data-tag" tag;
                  At.href ("#tag=" ^ tag)]
          [El.txt tag]
      ) tags in
      meta_line_block ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.tag_o)
        (El.div ~at:[At.class' "sidebar-meta-tags"] tag_chips)
  in
  (* Collect people from related ideas *)
  let related_ideas =
    List.filter_map (fun e ->
      match e with
      | `Idea i when Bushel.Idea.project i = slug -> Some i
      | _ -> None
    ) all_entries
  in
  let seen_handles = Hashtbl.create 16 in
  let collect_handles handles =
    List.filter_map (fun handle ->
      if Hashtbl.mem seen_handles handle then None
      else begin
        Hashtbl.replace seen_handles handle ();
        match Arod.Ctx.lookup_by_handle ctx handle with
        | Some contact -> Some (contact_inline ~ctx contact)
        | None -> None
      end
    ) handles
  in
  let sup_els = collect_handles
    (List.concat_map (fun i -> Bushel.Idea.supervisor_handles i) related_ideas) in
  let stu_els = collect_handles
    (List.concat_map (fun i -> Bushel.Idea.student_handles i) related_ideas) in
  let people_els = sup_els @ stu_els in
  (* Forward/backlinks *)
  let links_el, links_modal_el = entry_links ~ctx slug in
  let social_el = social_icons_el (Bushel.Project.social proj) in
  El.div [
    (* Meta box *)
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " ";
        El.a ~at:[At.href (Bushel.Entry.site_url (`Project proj));
                  At.class' "sidebar-meta-link"] [El.txt slug]];
      El.div ~at:[At.class' "sidebar-meta-body"]
        [date_el; tags_el; social_el; links_el]];
    (* People box *)
    (if people_els = [] then El.void
     else
       El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
         El.div ~at:[At.class' "sidebar-meta-header"] [
           El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
           El.txt (Printf.sprintf " %d %s"
             (List.length people_els)
             (if List.length people_els > 1 then "people" else "person"))];
         El.div ~at:[At.class' "sidebar-meta-body"] people_els]);
    links_modal_el]

(** {1 Socials Box}

    Renders a sidebar box with the author's social links from Sortal contact data. *)

let socials_box ~ctx =
  match Arod.Ctx.author ctx with
  | None -> El.void
  | Some author_contact ->
    let open Arod.Icons in
    let social_link ~icon ~title ~label url =
      El.a ~at:[At.href url;
          At.v "title" title; At.class' "social-box-link no-underline"]
          [El.unsafe_raw icon;
           El.span ~at:[At.class' "social-box-label"] [El.txt label]]
    in
    let group_label label =
      El.div ~at:[At.class' "social-group-label"] [El.txt label]
    in
    let group_opt label items =
      match items with
      | [] -> None
      | _ -> Some (El.div ~at:[At.class' "social-group"]
                     (group_label label :: items))
    in
    (* Code group: GitHub + Tangled *)
    let code_items = List.filter_map Fun.id [
      (match Contact.github_handle author_contact with
       | Some g ->
         Some (social_link ~icon:(brand ~size:16 github_brand)
           ~title:"GitHub" ~label:g ("https://github.com/" ^ g))
       | None -> None);
      (let open Contact in
       let tangled_svc = List.find_opt (fun (s : atproto_service) ->
         s.atp_type = ATTangled) (Contact.atproto_services author_contact) in
       match tangled_svc with
       | Some svc ->
         let label = match Uri.host (Uri.of_string svc.atp_url) with
           | Some h -> (match Uri.path (Uri.of_string svc.atp_url) with
             | "" | "/" -> h
             | p -> h ^ p)
           | None -> "Tangled"
         in
         Some (social_link ~icon:(brand ~size:16 tangled_brand)
           ~title:"Tangled" ~label svc.atp_url)
       | None -> None);
    ] in
    (* Identities group: ORCID + emails + website *)
    let id_items =
      List.filter_map Fun.id [
        (match Contact.orcid author_contact with
         | Some o ->
           Some (social_link ~icon:(brand ~size:16 orcid_brand)
             ~title:"ORCID" ~label:o ("https://orcid.org/" ^ o))
         | None -> None);
      ]
      @ (let current_emails = List.filter (fun (e : Contact.email) ->
           Sortal_schema.Temporal.is_current e.range
         ) (Contact.emails author_contact) in
         List.map (fun (e : Contact.email) ->
           let label = match e.type_ with
             | Some Work -> e.address ^ " (work)"
             | Some Personal -> e.address ^ " (personal)"
             | Some Other -> e.address ^ " (other)"
             | None -> e.address
           in
           social_link ~icon:(outline ~size:16 mail_o)
             ~title:"Email" ~label ("mailto:" ^ e.address)
         ) current_emails)
      @ List.filter_map Fun.id [
        (match Contact.current_url author_contact with
         | Some u ->
           let label = match Uri.host (Uri.of_string u) with
             | Some h -> h | None -> u
           in
           Some (social_link ~icon:(outline ~size:16 world_o)
             ~title:"Website" ~label u)
         | None -> None);
      ]
    in
    (* Social group: Bluesky + Mastodon + X + LinkedIn *)
    let social_items = List.filter_map Fun.id [
      (match Contact.bluesky_handle author_contact with
       | Some b ->
         Some (social_link ~icon:(brand ~size:16 bluesky_brand)
           ~title:"Bluesky" ~label:b ("https://bsky.app/profile/" ^ b))
       | None -> None);
      (match Contact.mastodon author_contact with
       | Some svc ->
         let handle = match Contact.mastodon_handle author_contact with
           | Some h -> h | None -> "Mastodon"
         in
         let url = svc.Contact.url in
         if url <> "" then
           Some (social_link ~icon:(brand ~size:16 mastodon_brand)
             ~title:"Mastodon" ~label:handle url)
         else None
       | None -> None);
      (match Contact.twitter_handle author_contact with
       | Some t ->
         Some (social_link ~icon:(brand ~size:16 x_brand)
           ~title:"X" ~label:("@" ^ t) ("https://twitter.com/" ^ t))
       | None -> None);
      (match Contact.linkedin author_contact with
       | Some svc ->
         let label = match Contact.linkedin_handle author_contact with
           | Some h -> h | None -> "LinkedIn"
         in
         Some (social_link ~icon:(brand ~size:16 linkedin_brand)
           ~title:"LinkedIn" ~label svc.Contact.url)
       | None -> None);
    ] in
    (* Office group: current organizations *)
    let office_items =
      let orgs = Contact.current_organizations author_contact in
      List.concat_map (fun (org : Contact.organization) ->
        let title_str = match org.title with
          | Some t -> t ^ ", " ^ org.name
          | None -> org.name
        in
        let org_el = match org.url with
          | Some u ->
            social_link ~icon:(outline ~size:16 home_o)
              ~title:org.name ~label:title_str u
          | None ->
            El.div ~at:[At.class' "social-box-link"] [
              El.unsafe_raw (outline ~size:16 home_o);
              El.span ~at:[At.class' "social-box-label"] [El.txt title_str]]
        in
        let addr_el = match org.address with
          | Some addr ->
            [El.div ~at:[At.class' "social-box-address"] [El.txt addr]]
          | None -> []
        in
        org_el :: addr_el
      ) orgs
    in
    let groups = List.filter_map Fun.id [
      group_opt "Identities" id_items;
      group_opt "Social" social_items;
      group_opt "Code" code_items;
      group_opt "Locations" office_items;
    ] in
    match groups with
    | [] -> El.void
    | _ ->
      El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
        El.div ~at:[At.class' "sidebar-meta-header"] [
          El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
          El.txt " 'bout ye?"];
        El.div ~at:[At.class' "sidebar-meta-body social-box-body"]
          groups]

let for_entry ~ctx ?(sidenotes=[]) ent =
  let entries = Arod.Ctx.entries ctx in

  (* Entry-specific metadata *)
  let note_meta_el = match ent with
    | `Note n -> note_meta ~ctx n
    | `Idea i -> idea_meta ~ctx i
    | `Paper p -> paper_meta ~ctx p
    | `Project p -> project_meta ~ctx p
    | _ -> El.void
  in

  (* Related links from backlinks — for entries without links in meta box *)
  let related_el = match ent with
    | `Note _ | `Idea _ | `Paper _ | `Project _ -> El.void
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
    ~at:[At.class' "lg:w-72 shrink-0"]
    [El.div ~at:[At.class' "relative h-full"]
       [(* Meta boxes + related: visible on all screens *)
        El.div ~at:[At.class' "mb-4 lg:mb-4 border-t border-border-color pt-4 mt-2 lg:border-t-0 lg:pt-0 lg:mt-0"]
          [note_meta_el; related_el];
        (* Sidenotes: desktop only — on mobile they appear inline *)
        El.div ~at:[At.class' "hidden lg:block"]
          [sidenotes_el]]]

(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Network page component.

    Unified chronological timeline grouped by month. Each month section
    shows collaborators (overlapping 36px avatar circles) then interleaves
    bushel entries and external feed entries chronologically. Paginated
    via infinite scrolling. *)

open Htmlit

module Entry = Bushel.Entry
module Paper = Bushel.Paper
module Contact = Sortal_schema.Contact
module Feed = Sortal_schema.Feed
module FeedEntry = Sortal_feed.Entry
module I = Arod.Icons

(** {1 Helpers} *)

let month_name_full = function
  | 1 -> "January" | 2 -> "February" | 3 -> "March" | 4 -> "April"
  | 5 -> "May" | 6 -> "June" | 7 -> "July" | 8 -> "August"
  | 9 -> "September" | 10 -> "October" | 11 -> "November" | 12 -> "December"
  | _ -> ""

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let truncate n s =
  if String.length s <= n then s
  else String.sub s 0 n ^ "\xe2\x80\xa6"

let strip_html s =
  let buf = Buffer.create (String.length s) in
  let in_tag = ref false in
  String.iter (fun c ->
    if c = '<' then in_tag := true
    else if c = '>' then in_tag := false
    else if not !in_tag then Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let take n l =
  let rec aux i acc = function
    | [] -> List.rev acc
    | _ when i >= n -> List.rev acc
    | x :: xs -> aux (i + 1) (x :: acc) xs
  in
  aux 0 [] l

(** {1 Timeline Item} *)

type timeline_item =
  | Bushel of Entry.entry * (int * int * int)
  | Feed_item of Arod.Ctx.feed_item * (int * int * int)

let timeline_date = function
  | Bushel (_, d) -> d
  | Feed_item (_, d) -> d

(** {1 Month Section Data} *)

type month_section = {
  year : int;
  month : int;
  collaborators : Contact.t list;
  items : timeline_item list;
}

(** {1 Collaborator Computation} *)

(** Compute collaborators for a given month from three sources:
    1. @Contact tags on bushel entries
    2. Paper co-authors matched to known contacts
    3. Contacts whose feed entries appear that month *)
let month_collaborators ~ctx bushel_entries feed_items =
  let seen = Hashtbl.create 16 in
  let contacts = ref [] in
  let add_contact contact =
    let h = Contact.handle contact in
    if not (Hashtbl.mem seen h) then begin
      Hashtbl.replace seen h true;
      contacts := contact :: !contacts
    end
  in
  (* 1. @Contact tags on bushel entries *)
  List.iter (fun ent ->
    let tags = Arod.Ctx.tags_of_ent ctx ent in
    List.iter (function
      | `Contact handle ->
        (match Arod.Ctx.lookup_by_handle ctx handle with
         | Some c -> add_contact c
         | None -> ())
      | _ -> ()
    ) tags
  ) bushel_entries;
  (* 2. Paper co-authors *)
  List.iter (fun ent ->
    match ent with
    | `Paper paper ->
      List.iter (fun author_name ->
        match Arod.Ctx.lookup_by_name ctx author_name with
        | Some c -> add_contact c
        | None -> ()
      ) (Paper.authors paper)
    | _ -> ()
  ) bushel_entries;
  (* 3. Contacts from feed items *)
  List.iter (fun (item : Arod.Ctx.feed_item) ->
    add_contact item.contact
  ) feed_items;
  List.rev !contacts

(** {1 Rendering} *)

let feed_type_badge ft =
  let icon = match (ft : Feed.feed_type) with
    | Atom | Rss -> I.brand ~size:10 I.rss_brand
    | Json -> I.brand ~size:10 I.jsonfeed_brand
  in
  El.span ~at:[At.class' "feed-type-badge"]
    [El.unsafe_raw icon]

(** Render a collaborator avatar (36px overlapping circle). *)
let render_avatar ~entries contact =
  let name = Contact.name contact in
  let thumb = Entry.contact_thumbnail entries contact in
  match thumb with
  | Some src ->
    El.a ~at:[At.href (match Contact.best_url contact with Some u -> u | None -> "#");
              At.class' "network-avatar-wrap";
              At.v "title" name]
      [El.img ~at:[At.src src; At.v "alt" name;
                    At.class' "network-avatar"] ()]
  | None ->
    let initials = Sidebar.contact_initials name in
    El.a ~at:[At.href (match Contact.best_url contact with Some u -> u | None -> "#");
              At.class' "network-avatar-wrap";
              At.v "title" name]
      [El.span ~at:[At.class' "network-avatar-initials"]
         [El.txt initials]]

(** Render a bushel entry row in the network timeline. *)
let render_bushel_entry ent =
  let type_icon = Sidebar.entry_type_icon ~size:12 ent in
  let title = Entry.title ent in
  let (_y, _m, d) = Entry.date ent in
  El.div ~at:[At.class' "network-entry"] [
    El.span ~at:[At.class' "project-activity-icon"]
      [El.unsafe_raw type_icon];
    El.div ~at:[At.class' "project-activity-content"] [
      El.div ~at:[At.class' "project-activity-header"] [
        El.a ~at:[At.href (Entry.site_url ent);
                  At.class' "project-activity-title"]
          [El.txt title];
        El.span ~at:[At.class' "project-activity-date"]
          [El.txt (string_of_int d)]]]]

(** Render a feed entry row in the network timeline. *)
let render_feed_item ~entries (item : Arod.Ctx.feed_item) =
  let fe = item.entry in
  let contact = item.contact in
  let name = Contact.name contact in
  let thumb = Entry.contact_thumbnail entries contact in
  (* Avatar *)
  let avatar_el = match thumb with
    | Some src ->
      El.img ~at:[At.src src; At.v "alt" name;
                  At.class' "network-feed-avatar"] ()
    | None ->
      El.span ~at:[At.class' "network-avatar-initials network-feed-avatar"]
        [El.txt (Sidebar.contact_initials name)]
  in
  (* Title *)
  let title_str = match fe.FeedEntry.title with
    | Some t -> t | None -> "(untitled)"
  in
  let title_el = match fe.FeedEntry.url with
    | Some u ->
      El.a ~at:[At.href (Uri.to_string u);
                At.class' "project-activity-title no-underline";
                At.v "rel" "noopener"]
        [El.txt title_str]
    | None ->
      El.span ~at:[At.class' "project-activity-title"]
        [El.txt title_str]
  in
  (* Badge *)
  let badge_el = feed_type_badge fe.FeedEntry.source_type in
  (* Date *)
  let date_el = match fe.FeedEntry.date with
    | Some d ->
      let (_y, _m, day), _ = Ptime.to_date_time d in
      El.span ~at:[At.class' "project-activity-date"]
        [El.txt (string_of_int day)]
    | None -> El.void
  in
  (* Summary *)
  let summary_el =
    let raw = match fe.FeedEntry.summary with
      | Some s when String.length s > 0 -> Some s
      | _ ->
        match fe.FeedEntry.content with
        | Some c when String.length c > 0 -> Some c
        | _ -> None
    in
    match raw with
    | Some s ->
      let plain = strip_html s in
      let trimmed = truncate 150 (String.trim plain) in
      if String.length trimmed > 0 then
        El.div ~at:[At.class' "network-feed-summary"]
          [El.txt trimmed]
      else El.void
    | None -> El.void
  in
  (* Contact name *)
  let contact_el = match Contact.best_url contact with
    | Some u ->
      El.a ~at:[At.href u; At.class' "link-backlink-chip no-underline"]
        [El.txt name]
    | None ->
      El.span ~at:[At.class' "link-backlink-chip"]
        [El.txt name]
  in
  El.div ~at:[At.class' "network-feed-item"] [
    avatar_el;
    El.div ~at:[At.class' "project-activity-content"] [
      El.div ~at:[At.class' "project-activity-header"] [
        title_el; badge_el; date_el];
      summary_el;
      El.div ~at:[At.class' "feed-item-source"] [contact_el]]]

(** Render a single month section. *)
let render_month ~entries section =
  let people_els = List.map (render_avatar ~entries) section.collaborators in
  let item_els = List.map (fun item ->
    match item with
    | Bushel (ent, _) -> render_bushel_entry ent
    | Feed_item (fi, _) -> render_feed_item ~entries fi
  ) section.items in
  El.div ~at:[At.class' "network-month"] [
    El.div ~at:[At.class' "network-month-header"] [
      El.h2 ~at:[At.class' "network-month-title"]
        [El.txt (Printf.sprintf "%s %d" (month_name_full section.month) section.year)];
      El.div ~at:[At.class' "network-month-people"] people_els];
    El.div ~at:[At.class' "network-month-body"] item_els]

(** {1 Month Section Computation} *)

let compute_month_sections ~ctx =
  let all_entries = Arod.Ctx.all_entries ctx in
  let all_feed_items = Arod.Ctx.feed_items ctx in

  (* Group bushel entries by (year, month) *)
  let bushel_by_month : (int * int, Entry.entry list) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun ent ->
    let (y, m, _d) = Entry.date ent in
    let key = (y, m) in
    let cur = try Hashtbl.find bushel_by_month key with Not_found -> [] in
    Hashtbl.replace bushel_by_month key (ent :: cur)
  ) all_entries;

  (* Group feed items by (year, month) *)
  let feed_by_month : (int * int, Arod.Ctx.feed_item list) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (item : Arod.Ctx.feed_item) ->
    match item.entry.FeedEntry.date with
    | Some d ->
      let (y, m, _d), _ = Ptime.to_date_time d in
      let key = (y, m) in
      let cur = try Hashtbl.find feed_by_month key with Not_found -> [] in
      Hashtbl.replace feed_by_month key (item :: cur)
    | None -> ()
  ) all_feed_items;

  (* Merge month keys, sort descending *)
  let all_months = Hashtbl.create 64 in
  Hashtbl.iter (fun k _ -> Hashtbl.replace all_months k true) bushel_by_month;
  Hashtbl.iter (fun k _ -> Hashtbl.replace all_months k true) feed_by_month;
  let months =
    Hashtbl.fold (fun k _ acc -> k :: acc) all_months []
    |> List.sort (fun (y1, m1) (y2, m2) ->
      let c = compare y2 y1 in if c <> 0 then c else compare m2 m1)
  in

  (* Build month sections *)
  List.map (fun (y, m) ->
    let bushel_ents = try List.rev (Hashtbl.find bushel_by_month (y, m)) with Not_found -> [] in
    let feed_items = try List.rev (Hashtbl.find feed_by_month (y, m)) with Not_found -> [] in
    let collaborators = month_collaborators ~ctx bushel_ents feed_items in
    let timeline =
      let b = List.map (fun ent -> Bushel (ent, Entry.date ent)) bushel_ents in
      let f = List.map (fun (item : Arod.Ctx.feed_item) ->
        let d = match item.entry.FeedEntry.date with
          | Some pt -> let (y, m, d), _ = Ptime.to_date_time pt in (y, m, d)
          | None -> (y, m, 1)
        in
        Feed_item (item, d)
      ) feed_items in
      List.sort (fun a b ->
        compare (timeline_date b) (timeline_date a)
      ) (b @ f)
    in
    { year = y; month = m; collaborators; items = timeline }
  ) months

(** Render a slice of month sections as an HTML string for the pagination API. *)
let render_months_html ~ctx sections =
  let entries = Arod.Ctx.entries ctx in
  let els = List.map (render_month ~entries) sections in
  El.to_string ~doctype:false (El.div els)

(** Return all computed month sections for use by the pagination API. *)
let all_months ~ctx = compute_month_sections ~ctx

(** {1 Network Page} *)

let page_size = 6

let network_page ~ctx =
  let entries = Arod.Ctx.entries ctx in
  let all_entries = Arod.Ctx.all_entries ctx in
  let all_feed_items = Arod.Ctx.feed_items ctx in
  let all_contacts = Arod.Ctx.contacts ctx in

  let sections = compute_month_sections ~ctx in

  (* Stats *)
  let total_bushel = List.length all_entries in
  let total_feed = List.length all_feed_items in
  let contacts_with_feeds = List.filter (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> true
    | _ -> false
  ) all_contacts in
  let total_contacts = List.length contacts_with_feeds in
  let total_months = List.length sections in

  (* Render only first page of month sections *)
  let visible_sections =
    if List.length sections > page_size then take page_size sections
    else sections
  in
  let month_els = List.map (render_month ~entries) visible_sections in

  let article =
    El.div ~at:[
      At.v "data-pagination" "true";
      At.v "data-collection-type" "network";
      At.v "data-total-count" (string_of_int total_months);
      At.v "data-current-count" (string_of_int (List.length visible_sections));
      At.v "data-types" ""] [
      El.h1 ~at:[At.class' "page-title"] [El.txt "Network"];
      El.p ~at:[At.class' "text-secondary text-sm mb-4"]
        [El.txt (Printf.sprintf "%d entries, %d feed items from %d contacts."
                   total_bushel total_feed total_contacts)];
      El.div ~at:[At.class' "network-timeline"] month_els]
  in

  (* Sidebar *)
  let stats_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " network"];
      El.div ~at:[At.class' "sidebar-meta-body"] [
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.note_o)
          (El.txt (Printf.sprintf "%d entries" total_bushel));
        Sidebar.meta_line
          ~icon:(I.brand ~cl:"opacity-50" ~size:12 I.rss_brand)
          (El.txt (Printf.sprintf "%d feed items" total_feed));
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
          (El.txt (Printf.sprintf "%d contacts" total_contacts));
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.calendar_o)
          (El.txt (Printf.sprintf "%d months" total_months))]]
  in

  (* Blogroll *)
  let blogroll_contacts = List.filter_map (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> Some (contact, feeds)
    | _ -> None
  ) all_contacts in
  let blogroll_contacts = List.sort (fun (a, _) (b, _) ->
    String.compare (Contact.name a) (Contact.name b)
  ) blogroll_contacts in
  let blogroll =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " blogroll"];
      El.div ~at:[At.class' "sidebar-meta-body"]
        (List.map (fun (contact, feeds) ->
          let name = Contact.name contact in
          let thumb = Entry.contact_thumbnail entries contact in
          let img_el = match thumb with
            | Some src ->
              El.img ~at:[At.src src; At.v "alt" name;
                          At.class' "network-blogroll-avatar"] ()
            | None ->
              El.span ~at:[At.class' "network-blogroll-initials"]
                [El.txt (Sidebar.contact_initials name)]
          in
          let name_el = match Contact.best_url contact with
            | Some u -> El.a ~at:[At.href u; At.class' "sidebar-meta-link"] [El.txt name]
            | None -> El.txt name
          in
          let feed_badges = List.map (fun feed ->
            let ft = Feed.feed_type feed in
            let icon = match ft with
              | Feed.Atom | Feed.Rss -> I.brand ~size:8 I.rss_brand
              | Feed.Json -> I.brand ~size:8 I.jsonfeed_brand
            in
            El.a ~at:[At.href (Feed.url feed); At.class' "feed-type-badge";
                      At.v "title" (Feed.url feed)]
              [El.unsafe_raw icon]
          ) feeds in
          El.div ~at:[At.class' "sidebar-meta-line feed-blogroll-row"] [
            El.span ~at:[At.class' "sidebar-meta-icon"] [img_el];
            El.span ~at:[At.class' "sidebar-meta-val"] [name_el];
            El.span ~at:[At.class' "feed-blogroll-badges"] feed_badges]
        ) blogroll_contacts)]
  in

  let sidebar =
    El.aside ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
      [El.div ~at:[At.class' "sticky top-20"] [stats_box; blogroll]]
  in
  (article, sidebar)

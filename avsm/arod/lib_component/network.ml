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

(** Compute collaborators for a given month, sorted by appearance count
    (most frequent first). Sources:
    1. @Contact tags on bushel entries
    2. Paper co-authors matched to known contacts
    3. Contacts whose feed entries appear that month *)
let month_collaborators ~ctx bushel_entries feed_items =
  let counts : (string, int) Hashtbl.t = Hashtbl.create 16 in
  let contact_map : (string, Contact.t) Hashtbl.t = Hashtbl.create 16 in
  let bump contact =
    let h = Contact.handle contact in
    Hashtbl.replace contact_map h contact;
    let cur = try Hashtbl.find counts h with Not_found -> 0 in
    Hashtbl.replace counts h (cur + 1)
  in
  (* 1. @Contact tags on bushel entries *)
  List.iter (fun ent ->
    let tags = Arod.Ctx.tags_of_ent ctx ent in
    List.iter (function
      | `Contact handle ->
        (match Arod.Ctx.lookup_by_handle ctx handle with
         | Some c -> bump c
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
        | Some c -> bump c
        | None -> ()
      ) (Paper.authors paper)
    | _ -> ()
  ) bushel_entries;
  (* 3. Contacts from feed items *)
  List.iter (fun (item : Arod.Ctx.feed_item) ->
    bump item.contact
  ) feed_items;
  (* Sort by count descending *)
  let contacts_with_counts =
    Hashtbl.fold (fun h count acc ->
      match Hashtbl.find_opt contact_map h with
      | Some c -> (c, count) :: acc
      | None -> acc
    ) counts []
  in
  let sorted = List.sort (fun (_, a) (_, b) -> compare b a) contacts_with_counts in
  List.map fst sorted

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

(** Render a feed entry row in the network timeline. *)
let render_feed_item ~entries (item : Arod.Ctx.feed_item) ((_y, _m, day) : int * int * int) =
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
  (* Contact name on the right *)
  let name_el = match Contact.best_url contact with
    | Some u ->
      El.a ~at:[At.href u; At.class' "network-feed-name no-underline"]
        [El.txt name]
    | None ->
      El.span ~at:[At.class' "network-feed-name"]
        [El.txt name]
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
    match Option.bind raw (Arod.Text.plain_summary ~max_len:150) with
    | Some text ->
      El.div ~at:[At.class' "network-feed-summary"]
        [El.txt text]
    | None -> El.void
  in
  (* Mentions of local bushel entries *)
  let mention_els = match item.mentions with
    | [] -> El.void
    | mentions ->
      El.div ~at:[At.class' "feed-item-mentions"]
        (List.map (fun entry ->
          let type_icon = Sidebar.entry_type_icon ~size:10 entry in
          El.a ~at:[At.href (Entry.site_url entry);
                    At.class' "link-backlink-chip no-underline"]
            [El.unsafe_raw type_icon;
             El.txt (Entry.title entry)]
        ) mentions)
  in
  El.div ~at:[At.class' "network-feed-item";
              At.v "data-month-id" (Printf.sprintf "%04d-%02d" _y _m);
              At.v "data-day" (string_of_int day)] [
    avatar_el;
    El.div ~at:[At.class' "project-activity-content"] [
      El.div ~at:[At.class' "project-activity-header"] [
        title_el; badge_el; name_el];
      summary_el;
      mention_els]]

(** Render a single month section (feed items only, bushel entries skipped). *)
let render_month ~entries section =
  let people_els = List.map (render_avatar ~entries) section.collaborators in
  let item_els = List.filter_map (fun item ->
    match item with
    | Bushel _ -> None
    | Feed_item (fi, d) -> Some (render_feed_item ~entries fi d)
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

  (* Only include months that have feed items *)
  let all_months = Hashtbl.create 64 in
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
  let all_feed_items = Arod.Ctx.feed_items ctx in
  let all_contacts = Arod.Ctx.contacts ctx in

  let sections = compute_month_sections ~ctx in

  (* Stats *)
  let total_feed = List.length all_feed_items in
  let contacts_with_feeds = List.filter (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> true
    | _ -> false
  ) all_contacts in
  let total_contacts = List.length contacts_with_feeds in
  let total_months = List.length sections in

  (* Build calendar data: { "YYYY-MM": [day1, day2, ...], ... } *)
  let month_days : (string, int list) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun section ->
    let key = Printf.sprintf "%04d-%02d" section.year section.month in
    let days = List.filter_map (fun item ->
      match item with
      | Feed_item (_, (_y, _m, d)) -> Some d
      | Bushel _ -> None
    ) section.items in
    let days = List.sort_uniq compare days in
    Hashtbl.replace month_days key days
  ) sections;
  let calendar_months =
    Hashtbl.fold (fun k _ acc -> k :: acc) month_days []
    |> List.sort (fun a b -> compare b a)
  in
  let calendar_json =
    let entries_json = List.map (fun key ->
      let days = Hashtbl.find month_days key in
      let day_strs = List.map string_of_int days in
      Printf.sprintf {|"%s":[%s]|} key (String.concat "," day_strs)
    ) calendar_months in
    "{" ^ String.concat "," entries_json ^ "}"
  in
  let first_month = match calendar_months with
    | m :: _ -> m | [] -> ""
  in

  (* Render only first page of month sections *)
  let visible_sections =
    if List.length sections > page_size then take page_size sections
    else sections
  in
  let month_els = List.map (render_month ~entries) visible_sections in

  let intro =
    El.p ~at:[At.class' "text-sm text-gray-600 dark:text-gray-400 mb-6"] [
      El.txt "I track a number of online blogs and connect relevant ones to things I am working on. You can grab my blogroll ";
      El.a ~at:[At.href "/network/blogroll.opml";
                At.class' "text-accent hover:underline"] [
        El.txt "OPML here"];
      El.txt ", or just browse it below. If you have your own blog that I've missed, do ";
      El.a ~at:[At.href "mailto:anil@recoil.org";
                At.class' "text-accent hover:underline"] [
        El.txt "let me know"];
      El.txt "!"]
  in

  let article =
    El.div ~at:[
      At.v "data-pagination" "true";
      At.v "data-collection-type" "network";
      At.v "data-total-count" (string_of_int total_months);
      At.v "data-current-count" (string_of_int (List.length visible_sections));
      At.v "data-types" ""] [
      intro;
      El.div ~at:[At.class' "network-timeline"] month_els]
  in

  (* Sidebar — calendar *)
  let calendar_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3";
                At.id "network-calendar";
                At.v "data-calendar-months" calendar_json;
                At.v "data-current-month" first_month] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %d posts \xC2\xB7 %d contacts"
          total_feed total_contacts)];
      El.div ~at:[At.class' "sidebar-meta-body notes-calendar"] [
        El.div ~at:[At.class' "cal-header"] [];
        El.div ~at:[At.class' "heatmap-strip"] [];
        El.div ~at:[At.class' "cal-divider"] [];
        El.div ~at:[At.class' "cal-grid"] []]]
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
        El.txt " blogroll ";
        El.a ~at:[At.href "/network/blogroll.opml";
                  At.class' "text-xs opacity-60 hover:opacity-100";
                  At.v "title" "Download OPML"] [El.txt "[opml]"]];
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
      [El.div ~at:[At.class' "sticky top-20"] [calendar_box; blogroll]]
  in
  (article, sidebar)

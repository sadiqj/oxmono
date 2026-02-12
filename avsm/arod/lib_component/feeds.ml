(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Feeds page component.

    Shows aggregated feed entries from contacts ordered by date,
    forming a planet-style feed reader. Also includes a blogroll
    sidebar of contacts with registered feeds. *)

open Htmlit

module Contact = Sortal_schema.Contact
module Feed = Sortal_schema.Feed
module FeedEntry = Sortal_feed.Entry
module I = Arod.Icons

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_str (ptime : Ptime.t) =
  let (y, m, d), _ = Ptime.to_date_time ptime in
  Printf.sprintf "%d %s %d" d (month_name m) y


(** Render a feed type badge (icon only). *)
let feed_type_badge ft =
  let icon = match (ft : Feed.feed_type) with
    | Atom | Rss -> I.brand ~size:10 I.rss_brand
    | Json -> I.brand ~size:10 I.jsonfeed_brand
  in
  El.span ~at:[At.class' "feed-type-badge"]
    [El.unsafe_raw icon]

(** {1 Feeds List Page} *)

let feeds_list ~ctx =
  let all_items = Arod.Ctx.feed_items ctx in
  let entries = Arod.Ctx.entries ctx in
  let all_contacts = Arod.Ctx.contacts ctx in

  (* Contacts with feeds for sidebar blogroll *)
  let contacts_with_feeds = List.filter_map (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> Some (contact, feeds)
    | _ -> None
  ) all_contacts in
  let contacts_with_feeds = List.sort (fun (a, _) (b, _) ->
    String.compare (Contact.name a) (Contact.name b)
  ) contacts_with_feeds in

  (* Stats *)
  let total_items = List.length all_items in
  let total_contacts = List.length contacts_with_feeds in
  let total_feeds = List.fold_left (fun acc (_, feeds) ->
    acc + List.length feeds
  ) 0 contacts_with_feeds in

  (* Render feed entry rows — show all items, newest first *)
  let item_rows = List.map (fun (item : Arod.Ctx.feed_item) ->
    let fe = item.entry in
    let contact = item.contact in
    let name = Contact.name contact in

    (* Title *)
    let title_str = match fe.FeedEntry.title with
      | Some t -> t
      | None -> "(untitled)"
    in
    let title_el = match fe.FeedEntry.url with
      | Some u ->
        El.a ~at:[At.href (Uri.to_string u);
                  At.class' "note-compact-title no-underline";
                  At.v "rel" "noopener"]
          [El.txt title_str]
      | None ->
        El.span ~at:[At.class' "note-compact-title"]
          [El.txt title_str]
    in

    (* Date *)
    let date_el = match fe.FeedEntry.date with
      | Some d ->
        El.span ~at:[At.class' "note-compact-meta"]
          [El.txt (ptime_date_str d)]
      | None -> El.void
    in

    (* Feed type badge *)
    let badge_el = feed_type_badge fe.FeedEntry.source_type in

    (* Summary *)
    let summary_el =
      let raw = match fe.FeedEntry.summary with
        | Some s when String.length s > 0 -> Some s
        | _ ->
          match fe.FeedEntry.content with
          | Some c when String.length c > 0 -> Some c
          | _ -> None
      in
      match Option.bind raw (Arod.Text.plain_summary ~max_len:200) with
      | Some text ->
        El.div ~at:[At.class' "note-compact-synopsis"]
          [El.txt text]
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

    (* Mentions of local bushel entries *)
    let mention_els = match item.mentions with
      | [] -> El.void
      | mentions ->
        El.div ~at:[At.class' "feed-item-mentions"]
          (List.map (fun entry ->
            let type_icon = Sidebar.entry_type_icon ~size:10 entry in
            El.a ~at:[At.href (Bushel.Entry.site_url entry);
                      At.class' "link-backlink-chip no-underline"]
              [El.unsafe_raw type_icon;
               El.txt (Sidebar.truncate_str 30 (Bushel.Entry.title entry))]
          ) mentions)
    in

    El.div ~at:[At.class' "feed-item"] [
      El.div ~at:[At.class' "note-compact-row"] [
        title_el;
        badge_el;
        date_el];
      summary_el;
      El.div ~at:[At.class' "feed-item-source"] [contact_el];
      mention_els]
  ) all_items in

  let article =
    El.div ~at:[] [
      El.div ~at:[At.class' "feed-list"] item_rows]
  in

  (* Sidebar *)
  let stats_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " feeds"];
      El.div ~at:[At.class' "sidebar-meta-body"] [
        Sidebar.meta_line
          ~icon:(I.brand ~cl:"opacity-50" ~size:12 I.rss_brand)
          (El.txt (Printf.sprintf "%d entries" total_items));
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.user_o)
          (El.txt (Printf.sprintf "%d contacts" total_contacts));
        Sidebar.meta_line
          ~icon:(I.brand ~cl:"opacity-50" ~size:12 I.rss_brand)
          (El.txt (Printf.sprintf "%d feeds" total_feeds))]]
  in

  (* Blogroll: contacts with their feeds *)
  let blogroll =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " blogroll"];
      El.div ~at:[At.class' "sidebar-meta-body"]
        (List.map (fun (contact, feeds) ->
          let name = Contact.name contact in
          let thumb = Bushel.Entry.contact_thumbnail entries contact in
          let img_el = match thumb with
            | Some src ->
              El.img ~at:[At.src src; At.v "alt" name;
                          At.class' "feed-blogroll-avatar"] ()
            | None ->
              El.span ~at:[At.class' "feed-blogroll-avatar-initials"]
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
        ) contacts_with_feeds)]
  in

  let sidebar =
    El.aside ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
      [El.div ~at:[At.class' "sticky top-20"] [stats_box; blogroll]]
  in
  (article, sidebar)

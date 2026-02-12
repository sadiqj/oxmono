(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Common utilities shared across Arod components.

    Centralises date formatting, list helpers, feed rendering,
    and other functions that were previously duplicated across
    multiple component files. *)

open Htmlit

module I = Arod.Icons
module Contact = Sortal_schema.Contact
module Feed = Sortal_schema.Feed
module FeedEntry = Sortal_feed.Entry

(** {1 Date Formatting} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let month_name_full = function
  | 1 -> "January" | 2 -> "February" | 3 -> "March" | 4 -> "April"
  | 5 -> "May" | 6 -> "June" | 7 -> "July" | 8 -> "August"
  | 9 -> "September" | 10 -> "October" | 11 -> "November" | 12 -> "December"
  | _ -> ""

let ptime_date_short (y, m, _d) =
  Printf.sprintf "%s %4d" (month_name m) y

let ptime_date_full (y, m, d) =
  Printf.sprintf "%d %s %4d" d (month_name_full m) y

(** {1 List Utilities} *)

let take n l =
  let[@tail_mod_cons] rec aux n l =
    match n, l with
    | 0, _ | _, [] -> []
    | n, x :: rest -> x :: aux (n - 1) rest
  in
  if n < 0 then invalid_arg "take"; aux n l

let map_and fn l =
  let ll = List.length l in
  List.mapi (fun i v ->
    match i with
    | 0 -> fn v
    | _ when i + 1 = ll -> " and " ^ (fn v)
    | _ -> ", " ^ (fn v)
  ) l |> String.concat ""

(** {1 String Utilities} *)

let strip_www h =
  if String.length h > 4 && String.sub h 0 4 = "www."
  then String.sub h 4 (String.length h - 4) else h

let contact_initials name =
  match String.split_on_char ' ' name with
  | f :: l :: _ when String.length f > 0 && String.length l > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
    ^ String.make 1 (Char.uppercase_ascii l.[0])
  | f :: _ when String.length f > 0 ->
    String.make 1 (Char.uppercase_ascii f.[0])
  | _ -> "?"

(** {1 Paper Helpers} *)

let venue_of_paper paper =
  let bibty = String.lowercase_ascii (Bushel.Paper.bibtype paper) in
  match bibty with
  | "inproceedings" | "abstract" -> Bushel.Paper.booktitle paper
  | "article" | "journal" -> Bushel.Paper.journal paper
  | "book" -> Bushel.Paper.publisher paper
  | "techreport" -> Bushel.Paper.institution paper
  | _ -> Bushel.Paper.publisher paper

(** {1 Idea Helpers} *)

let idea_level_to_string = function
  | Bushel.Idea.Any -> "Any" | PartII -> "Part II" | MPhil -> "MPhil"
  | PhD -> "PhD" | Postdoc -> "Postdoc"

(** {1 Feed Helpers} *)

let feed_entry_title_str fe =
  Option.value ~default:"(untitled)" fe.FeedEntry.title

let feed_entry_title_el ?(cls="project-activity-title") fe =
  let title_str = feed_entry_title_str fe in
  match fe.FeedEntry.url with
  | Some u ->
    El.a ~at:[At.href (Uri.to_string u);
              At.class' (cls ^ " no-underline");
              At.v "rel" "noopener"]
      [El.txt title_str]
  | None ->
    El.span ~at:[At.class' cls]
      [El.txt title_str]

let feed_entry_raw_text fe =
  match fe.FeedEntry.summary with
  | Some s when String.length s > 0 -> Some s
  | _ ->
    match fe.FeedEntry.content with
    | Some c when String.length c > 0 -> Some c
    | _ -> None

let feed_entry_summary ~max_len fe =
  Option.bind (feed_entry_raw_text fe) (Arod.Text.plain_summary ~max_len)

let feed_type_badge ft =
  let icon = match (ft : Feed.feed_type) with
    | Atom | Rss -> I.brand ~size:10 I.rss_brand
    | Json -> I.brand ~size:10 I.jsonfeed_brand
  in
  El.span ~at:[At.class' "feed-type-badge"]
    [El.unsafe_raw icon]

let contacts_with_feeds contacts =
  let with_feeds = List.filter_map (fun contact ->
    match Contact.feeds contact with
    | Some feeds when feeds <> [] -> Some (contact, feeds)
    | _ -> None
  ) contacts in
  List.sort (fun (a, _) (b, _) ->
    String.compare (Contact.name a) (Contact.name b)
  ) with_feeds

(** {1 Body Truncation} *)

let truncate_body_parts ent =
  let body = Bushel.Entry.body ent in
  let first, last = Bushel.Util.first_and_last_hunks body in
  let remaining_words = Bushel.Util.count_words last in
  let total_words = Bushel.Util.count_words first + remaining_words in
  let is_note = match ent with `Note _ -> true | _ -> false in
  let is_truncated = remaining_words > 1 in
  let word_count_info =
    if is_truncated || (is_note && total_words > 0) then
      Some (total_words, is_truncated)
    else None
  in
  let footnote_lines = Bushel.Util.find_footnote_lines last in
  let footnotes_text =
    if footnote_lines = [] then ""
    else "\n\n" ^ String.concat "\n" footnote_lines
  in
  (first ^ footnotes_text, word_count_info)

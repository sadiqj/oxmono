(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** List and feed view components using htmlit. *)

open Htmlit

(** {1 Entry Types} *)

type entry_type = [ `Paper | `Note | `Video | `Idea | `Project ]

let entry_type_to_string = function
  | `Paper -> "paper" | `Note -> "note" | `Video -> "video"
  | `Idea -> "idea" | `Project -> "project"

let entry_type_of_string = function
  | "paper" -> Some `Paper | "note" -> Some `Note | "video" -> Some `Video
  | "idea" -> Some `Idea | "project" -> Some `Project | _ -> None

(** {1 Utilities} *)

let take n l =
  let[@tail_mod_cons] rec aux n l =
    match n, l with
    | 0, _ | _, [] -> []
    | n, x :: rest -> x :: aux (n - 1) rest
  in
  if n < 0 then invalid_arg "take"; aux n l

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_short ?(with_d = false) (y, m, d) =
  if with_d then
    let suffix =
      if d mod 10 = 1 && d mod 100 <> 11 then "st"
      else if d mod 10 = 2 && d mod 100 <> 12 then "nd"
      else if d mod 10 = 3 && d mod 100 <> 13 then "rd"
      else "th"
    in
    Printf.sprintf "%d%s %s %4d" d suffix (month_name m) y
  else
    Printf.sprintf "%s %4d" (month_name m) y

(** Truncate the body of an entry. *)
let truncated_body ~ctx ent =
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
  let markdown_with_link =
    match word_count_info with
    | Some (total, true) ->
      let url = Bushel.Entry.site_url ent in
      first ^ "\n\n*[Read full note... (" ^ string_of_int total ^
      " words](" ^ url ^ "))*\n" ^ footnotes_text
    | _ -> first ^ footnotes_text
  in
  (El.unsafe_raw (fst (Arod.Md.to_html ~ctx markdown_with_link)), word_count_info)

(** {1 Entry Filtering} *)

let entry_matches_type types ent =
  if types = [] then true
  else List.exists (fun typ ->
    match typ, ent with
    | `Paper, `Paper _ -> true | `Note, `Note _ -> true
    | `Video, `Video _ -> true | `Idea, `Idea _ -> true
    | `Project, `Project _ -> true | _ -> false
  ) types

let get_entries ~(ctx : Arod.Ctx.t) ~types =
  let filterent = entry_matches_type types in
  let select ent =
    let only_talks = function
      | `Video { Bushel.Video.talk; _ } -> talk
      | _ -> true
    in
    let not_index_page = function
      | `Note { Bushel.Note.index_page; _ } -> not index_page
      | _ -> true
    in
    only_talks ent && not_index_page ent
  in
  Arod.Ctx.all_entries ctx
  |> List.filter (fun ent -> select ent && filterent ent)
  |> List.sort Bushel.Entry.compare
  |> List.rev

(** {1 Entry Heading} *)

let entry_heading ~ctx:_ ent =
  let via, via_url = match ent with
    | `Note n ->
      (match n.Bushel.Note.via with
       | None -> None, None
       | Some (t, u) -> Some t, Some u)
    | _ -> None, None
  in
  let via_el = match via, via_url with
    | Some t, Some u when t <> "" ->
      El.a ~at:[At.href u; At.class' "text-sm text-secondary"]
        [El.txt (Printf.sprintf "(via %s)" t)]
    | _, Some u ->
      El.a ~at:[At.href u; At.class' "text-sm text-secondary"]
        [El.txt "(via)"]
    | _ -> El.void
  in
  match ent with
  | `Note { index_page = true; _ } -> El.void
  | _ ->
    let doi_el = match ent with
      | `Note n when Bushel.Note.perma n ->
        (match Bushel.Note.doi n with
         | Some doi_str ->
           El.span ~at:[At.class' "text-sm text-secondary"] [
             El.txt " / ";
             El.a ~at:[At.href ("https://doi.org/" ^ doi_str)] [El.txt "DOI"]]
         | None -> El.void)
      | _ -> El.void
    in
    El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
      El.a ~at:[At.href (Bushel.Entry.site_url ent)] [
        El.txt (Bushel.Entry.title ent)];
      El.txt " "; via_el;
      El.span ~at:[At.class' "text-sm text-secondary"] [
        El.txt " / ";
        El.txt (ptime_date_short (Bushel.Entry.date ent))];
      doi_el]

(** {1 Tags Metadata} *)

let tags_meta ~ctx ent =
  let all_tags = Arod.Ctx.tags_of_ent ctx ent in
  let date_str = ptime_date_short ~with_d:true (Bushel.Entry.date ent) in
  let link_el =
    El.a ~at:[At.href (Bushel.Entry.site_url ent);
              At.class' "text-sm text-secondary"] [El.txt "#"]
  in
  let bullet = El.span ~at:[At.class' "mx-2 text-gray-400"] [El.txt "\u{2022}"] in
  let tag_els = match all_tags with
    | [] -> El.void
    | tags ->
      let tag_spans = List.map (fun tag ->
        let tag_str = Bushel.Tags.to_raw_string tag in
        El.span ~at:[At.v "data-tag" tag_str;
                     At.class' "text-xs bg-gray-100 px-2 py-1 rounded"] [El.txt tag_str]
      ) tags in
      let rec intersperse_comma = function
        | [] -> [] | [x] -> [x]
        | x :: xs -> x :: El.txt " " :: intersperse_comma xs
      in
      El.span (bullet :: intersperse_comma tag_spans)
  in
  El.div ~at:[At.class' "text-sm text-secondary mt-2 flex items-center flex-wrap"] [
    link_el; El.txt " "; El.txt date_str; tag_els]

(** {1 Single Entry Rendering} *)

let render_entry ~ctx ent =
  let entry_html = match ent with
    | `Paper p -> Paper.card ~ctx p
    | `Note n -> fst (Note.brief ~ctx n)
    | `Video v -> fst (Video.brief ~ctx v)
    | `Idea i -> fst (Idea.brief ~ctx i)
    | `Project p -> fst (Project.for_feed ~ctx p)
  in
  El.div [entry_html; tags_meta ~ctx ent]

(** Render an entry for feed view. *)
let render_feed ~ctx ent =
  let entry_html = match ent with
    | `Paper p -> Paper.for_feed ~ctx p
    | `Note n -> fst (Note.for_feed ~ctx n)
    | `Video v -> fst (Video.for_feed ~ctx v)
    | `Idea i -> fst (Idea.for_feed ~ctx i)
    | `Project p -> fst (Project.for_feed ~ctx p)
  in
  El.div [entry_heading ~ctx ent; entry_html; tags_meta ~ctx ent]

(** {1 Page Functions} *)

(** Paginated entry list page content. *)
let entries_page ~ctx ~title:page_title ~types =
  let ents = get_entries ~ctx ~types in
  let ents' = if List.length ents > 25 then take 25 ents else ents in
  let rendered = List.map (render_entry ~ctx) ents' in
  let rec add_separators = function
    | [] -> [] | [x] -> [x]
    | x :: xs -> x :: El.hr ~at:[At.class' "my-4 border-t"] () :: add_separators xs
  in
  let main_content = add_separators rendered in
  let types_str = String.concat "," (List.map entry_type_to_string types) in
  El.article ~at:[
    At.v "data-pagination" "true";
    At.v "data-collection-type" "entries";
    At.v "data-total-count" (string_of_int (List.length ents));
    At.v "data-current-count" (string_of_int (List.length ents'));
    At.v "data-types" types_str] [
    El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt page_title];
    El.div main_content]

(** Chronological feed view page content. *)
let feed_page ~ctx ~title:page_title ~types =
  let feed = get_entries ~ctx ~types in
  let feed' = if List.length feed > 25 then take 25 feed else feed in
  let rec intersperse_hr = function
    | [] -> [] | [x] -> [render_feed ~ctx x]
    | x :: xs -> render_feed ~ctx x :: El.hr ~at:[At.class' "my-4 border-t"] () :: intersperse_hr xs
  in
  let main_content = intersperse_hr feed' in
  let types_str = String.concat "," (List.map entry_type_to_string types) in
  El.article ~at:[
    At.v "data-pagination" "true";
    At.v "data-collection-type" "feed";
    At.v "data-total-count" (string_of_int (List.length feed));
    At.v "data-current-count" (string_of_int (List.length feed'));
    At.v "data-types" types_str] [
    El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt page_title];
    El.div main_content]

(** HTML string fragment for pagination API (entry list). *)
let render_entries_html ~ctx ents =
  let rendered = List.map (render_entry ~ctx) ents in
  let rec add_separators = function
    | [] -> [] | [x] -> [x]
    | x :: xs -> x :: El.hr ~at:[At.class' "my-4 border-t"] () :: add_separators xs
  in
  let html_elements = El.hr ~at:[At.class' "my-4 border-t"] () :: add_separators rendered in
  El.to_string ~doctype:false (El.div html_elements)

(** HTML string fragment for pagination API (feed view). *)
let render_feeds_html ~ctx feeds =
  let rec intersperse_hr = function
    | [] -> [] | [x] -> [render_feed ~ctx x]
    | x :: xs -> render_feed ~ctx x :: El.hr ~at:[At.class' "my-4 border-t"] () :: intersperse_hr xs
  in
  let html_elements = El.hr ~at:[At.class' "my-4 border-t"] () :: intersperse_hr feeds in
  El.to_string ~doctype:false (El.div html_elements)

(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Note component rendering using htmlit. *)

open Htmlit

module Note = Bushel.Note

(** {1 Helpers} *)

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

(** Truncate the body of a note, returning HTML and optional word count info. *)
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

(** Render a heading for an entry with date, via link, and DOI. *)
let heading ~ctx ent =
  let via, via_url = match ent with
    | `Note n ->
      (match n.Note.via with
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
      | `Note n when Note.perma n ->
        (match Note.doi n with
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

(** Brief note for lists with truncated body. *)
let brief ~ctx n =
  let body_html, word_count_info = truncated_body ~ctx (`Note n) in
  let children = [heading ~ctx (`Note n); body_html] in
  (El.div children, word_count_info)

(** Full note rendering with parent reference link. *)
let full ~ctx n =
  let body = Note.body n in
  let body_with_ref = match Note.slug_ent n with
    | None -> body
    | Some slug_ent ->
      let parent_ent = Arod.Ctx.lookup_exn ctx slug_ent in
      let parent_title = Bushel.Entry.title parent_ent in
      body ^ "\n\nRead more about [" ^ parent_title ^ "](:" ^ slug_ent ^ ")."
  in
  let html, sidenotes = Arod.Md.to_html ~ctx body_with_ref in
  (El.div ~at:[At.class' "mb-4"] [
    heading ~ctx (`Note n);
    El.unsafe_raw html], sidenotes)

(** Full note page with proper header and article structure. *)
let full_page ~ctx n =
  let (y, m, d) = Bushel.Entry.date (`Note n) in
  let date_str = ptime_date_full (y, m, d) in
  let datetime_str = Printf.sprintf "%04d-%02d-%02d" y m d in
  let all_tags = Arod.Ctx.tags_of_ent ctx (`Note n) in
  (* Date + tags meta row *)
  let tag_els = match all_tags with
    | [] -> []
    | tags ->
      [El.txt " \xC2\xB7 "] @
      List.concat (List.mapi (fun i tag ->
        let tag_str = Bushel.Tags.to_raw_string tag in
        let el = El.txt ("#" ^ tag_str) in
        if i > 0 then [El.txt " "; el] else [el]
      ) tags)
  in
  let doi_el = match Note.doi n with
    | Some doi_str ->
      [El.txt " \xC2\xB7 ";
       El.txt "DOI: ";
       El.a ~at:[At.href ("https://doi.org/" ^ doi_str)] [El.txt doi_str]]
    | None -> []
  in
  (* Meta row — hidden on desktop where sidebar shows this info *)
  let meta_row =
    El.p ~at:[At.class' "text-sm text-secondary mb-2 lg:hidden"]
      ([El.time ~at:[At.v "datetime" datetime_str] [El.txt date_str]] @ tag_els @ doi_el)
  in
  (* H1 title (no self-link) *)
  let title_el =
    El.h1 ~at:[At.class' "page-title text-xl font-semibold tracking-tight mb-3"]
      [El.txt (Note.title n)]
  in
  (* Synopsis — hidden on desktop where sidebar shows it *)
  let synopsis_el = match Note.synopsis n with
    | Some syn ->
      [El.p ~at:[At.class' "text-lg leading-relaxed text-secondary lg:hidden"] [El.txt syn]]
    | None -> []
  in
  (* Header *)
  let header_el =
    El.header ~at:[At.id "intro"; At.class' "mb-6"]
      ([meta_row; title_el] @ synopsis_el)
  in
  (* Body with parent reference *)
  let body = Note.body n in
  let body_with_ref = match Note.slug_ent n with
    | None -> body
    | Some slug_ent ->
      let parent_ent = Arod.Ctx.lookup_exn ctx slug_ent in
      let parent_title = Bushel.Entry.title parent_ent in
      body ^ "\n\nRead more about [" ^ parent_title ^ "](:" ^ slug_ent ^ ")."
  in
  let body_html, sidenotes = Arod.Md.to_html ~ctx body_with_ref in
  let headings = Arod.Md.extract_headings body_with_ref in
  let article_el =
    El.article ~at:[At.class' "space-y-3"] [El.unsafe_raw body_html]
  in
  (El.div [header_el; article_el], sidenotes, headings)

(** Truncated note for feeds. *)
let for_feed ~ctx n = truncated_body ~ctx (`Note n)

(** Citation references section for permanent notes. *)
let references ~ctx n =
  let is_perma = Note.perma n in
  let has_doi = match Note.doi n with Some _ -> true | None -> false in
  if not (is_perma || has_doi) then El.void
  else
    let cfg = Arod.Ctx.config ctx in
    let me = Arod.Ctx.lookup_by_handle ctx cfg.site.author_handle in
    match me with
    | None -> El.void
    | Some author_contact ->
      let entries = Arod.Ctx.entries ctx in
      let refs = Bushel.Md.note_references entries author_contact n in
      if List.length refs > 0 then
        let ref_items = List.mapi (fun i (doi, citation, is_paper) ->
          let num = i + 1 in
          let doi_url = Printf.sprintf "https://doi.org/%s" doi in
          let cite_id = Arod.Md.doi_to_id doi in
          let icon = match is_paper with
            | Bushel.Md.Paper -> Arod.Icons.(outline ~cl:"opacity-40" ~size:12 paper_o)
            | Bushel.Md.Note -> Arod.Icons.(outline ~cl:"opacity-40" ~size:12 note_o)
            | Bushel.Md.External -> Arod.Icons.(outline ~cl:"opacity-40" ~size:12 external_link_o)
          in
          El.div ~at:[At.id (Printf.sprintf "ref-%d" num);
                      At.class' "ref-item"] [
            El.span ~at:[At.class' "ref-num"] [
              El.a ~at:[At.href ("#" ^ cite_id); At.class' "ref-backlink no-underline";
                        At.v "title" "Jump to citation"]
                [El.txt (Printf.sprintf "[%d]" num)]];
            El.unsafe_raw icon;
            El.span ~at:[At.class' "ref-body"] [
              El.txt (citation ^ " ");
              El.a ~at:[At.href doi_url; At.v "target" "_blank";
                        At.class' "ref-doi"] [El.txt doi]]]
        ) refs in
        El.div ~at:[At.class' "references-block mt-8"] [
          El.div ~at:[At.class' "ref-header"] [El.txt "references"];
          El.div ~at:[At.class' "ref-list"] ref_items]
      else El.void

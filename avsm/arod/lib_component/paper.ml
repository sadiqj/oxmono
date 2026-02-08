(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Paper component rendering using htmlit. *)

open Htmlit

module Paper = Bushel.Paper
module Contact = Sortal_schema.Contact

(** Render a single author with optional link from contacts. *)
let one_author ~ctx author_name_str =
  match Arod.Ctx.lookup_by_name ctx author_name_str with
  | None ->
    El.span ~at:[At.class' "whitespace-nowrap"] [El.txt author_name_str]
  | Some contact ->
    let name = Contact.name contact in
    (match Contact.best_url contact with
     | None -> El.span ~at:[At.class' "whitespace-nowrap"] [El.txt name]
     | Some url -> El.a ~at:[At.href url; At.class' "whitespace-nowrap"] [El.txt name])

(** Render the full author list with commas and "and". *)
let authors ~ctx paper =
  let author_names = Paper.authors paper in
  let author_els = List.map (one_author ~ctx) author_names in
  match author_els with
  | [] -> El.void
  | [single] -> single
  | els ->
    let rec make_list = function
      | [] -> []
      | [x] -> [El.txt " and "; x]
      | x :: xs -> x :: El.txt ", " :: make_list xs
    in
    let children = make_list els in
    El.span children

(** Extract hostname without www. prefix from a URL. *)
let host_without_www u =
  match Uri.host (Uri.of_string u) with
  | None -> ""
  | Some h ->
    if String.starts_with ~prefix:"www." h then
      String.sub h 4 (String.length h - 4)
    else h

(** Render publisher description based on bibtype. *)
let publisher paper =
  let bibty = Paper.bibtype paper in
  let ourl l = function
    | None -> l
    | Some u -> Printf.sprintf {|<a href="%s">%s</a>|} u l
  in
  let string_of_vol_issue paper =
    match Paper.volume paper, Paper.number paper with
    | Some v, Some n -> Printf.sprintf " (vol %s issue %s)" v n
    | Some v, None -> Printf.sprintf " (vol %s)" v
    | None, Some n -> Printf.sprintf " (issue %s)" n
    | _ -> ""
  in
  let result =
    match String.lowercase_ascii bibty with
    | "misc" ->
      Printf.sprintf {|Working paper at %s|} (ourl (Paper.publisher paper) (Paper.url paper))
    | "inproceedings" ->
      Printf.sprintf {|Paper in the %s|} (ourl (Paper.booktitle paper) (Paper.url paper))
    | "proceedings" ->
      Printf.sprintf {|%s|} (ourl (Paper.title paper) (Paper.url paper))
    | "abstract" ->
      Printf.sprintf {|Abstract in the %s|} (ourl (Paper.booktitle paper) (Paper.url paper))
    | "article" | "journal" ->
      Printf.sprintf {|Journal paper in %s%s|}
        (ourl (Paper.journal paper) (Paper.url paper)) (string_of_vol_issue paper)
    | "book" ->
      Printf.sprintf {|Book published by %s|} (ourl (Paper.publisher paper) (Paper.url paper))
    | "techreport" ->
      Printf.sprintf {|Technical report%s at %s|}
        (match Paper.number paper with None -> "" | Some n -> " (" ^ n ^ ")")
        (ourl (Paper.institution paper) (Paper.url paper))
    | _ ->
      Printf.sprintf {|Publication in %s|} (ourl (Paper.publisher paper) (Paper.url paper))
  in
  El.unsafe_raw result

(** Render PDF/BIB/DOI/URL links inline. *)
let bar ~ctx ?(nopdf = false) paper =
  let cfg = Arod.Ctx.config ctx in
  let sep = El.txt " \u{00a0} " in
  let pdf =
    let pdf_path =
      Filename.concat cfg.paths.static_dir
        (Printf.sprintf "papers/%s.pdf" (Paper.slug paper))
    in
    if Sys.file_exists pdf_path && not nopdf then
      Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.pdf" (Paper.slug paper))] [
        El.span ~at:[At.class' "whitespace-nowrap"] [
          El.txt "PDF";
          El.img ~at:[At.alt "pdf"; At.src "/assets/pdf.svg";
                      At.class' "inline-block h-4 w-4 ml-1"] ()]])
    else None
  in
  let bib =
    if nopdf then None
    else
      Some (El.a ~at:[At.href (Printf.sprintf "/papers/%s.bib" (Paper.slug paper))] [El.txt "BIB"])
  in
  let url_el =
    match Paper.url paper with
    | None -> None
    | Some u ->
      Some (El.span [
        El.a ~at:[At.href u] [El.txt "URL"];
        El.txt " ";
        El.span ~at:[At.class' "text-sm italic text-secondary"] [
          El.txt (Printf.sprintf "(%s)" (host_without_www u))]])
  in
  let doi =
    match Paper.doi paper with
    | None -> None
    | Some d ->
      Some (El.a ~at:[At.href ("https://doi.org/" ^ d)] [El.txt "DOI"])
  in
  let bits = [url_el; doi; bib; pdf] |> List.filter_map Fun.id in
  let rec intersperse = function
    | [] -> []
    | [x] -> [x]
    | x :: xs -> x :: sep :: intersperse xs
  in
  El.div ~at:[At.class' "flex items-center gap-4 flex-wrap"] (intersperse bits)

(** Brief paper card for lists. *)
let card ~ctx paper =
  El.div ~at:[At.class' "mb-4"] [
    El.div [
      El.p ~at:[At.class' "font-semibold"] [
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper))] [El.txt (Paper.title paper)]];
      El.p [authors ~ctx paper; El.txt "."];
      El.p [publisher paper; El.txt "."];
      El.p [bar ~ctx paper]]]

(** Full paper view with abstract and image. *)
let full ~ctx paper =
  let img_el =
    match Arod.Ctx.lookup_image ctx (Paper.slug paper) with
    | Some img_ent ->
      let origin_url =
        Printf.sprintf "/images/%s.webp"
          (Filename.chop_extension (Srcsetter.origin img_ent))
      in
      El.p ~at:[At.class' "my-4"] [
        El.a ~at:[At.href (Option.value ~default:"#" (Paper.best_url paper))] [
          El.img ~at:[At.src origin_url; At.v "loading" "lazy"; At.alt (Paper.title paper)] ()]]
    | None -> El.void
  in
  let abstract_text = Paper.abstract paper in
  let abstract_html, sidenotes =
    if abstract_text <> "" then
      let html, sns = Arod.Md.to_html ~ctx abstract_text in
      (El.p ~at:[At.class' "mt-4"] [El.unsafe_raw html], sns)
    else (El.void, [])
  in
  (El.div ~at:[At.class' "mb-4"] [
    El.div [
      El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [El.txt (Paper.title paper)];
      El.p [authors ~ctx paper; El.txt "."];
      El.p [publisher paper; El.txt "."];
      El.p [bar ~ctx paper]];
    img_el;
    abstract_html], sidenotes)

(** Render older versions section. *)
let extra ~ctx paper =
  let entries = Arod.Ctx.entries ctx in
  let all =
    Bushel.Entry.old_papers entries
    |> List.filter (fun op -> Paper.slug op = Paper.slug paper)
  in
  match all with
  | [] -> El.void
  | all ->
    let month_name = function
      | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
      | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
      | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
      | _ -> ""
    in
    let ptime_date (y, m, _d) =
      Printf.sprintf "%s %4d" (month_name m) y
    in
    let older_versions = List.map (fun op ->
      El.div ~at:[At.class' "mb-4"] [
        El.hr ();
        El.p [El.txt ("This is " ^ op.Paper.ver ^ " of the publication from " ^
                    ptime_date (Paper.date op) ^ ".")];
        El.blockquote ~at:[At.class' "border-l pl-4 ml-0"] [card ~ctx op]]
    ) all in
    El.div ([
      El.h1 ~at:[At.class' "text-2xl font-semibold mt-8 mb-4"] [El.txt "Older versions"];
      El.p ~at:[At.class' "mb-4"] [
        El.txt "There are earlier revisions of this paper available below for historical reasons. ";
        El.txt "Please cite the latest version of the paper above instead of these."]]
      @ older_versions)

(** Paper entry for feeds. *)
let for_feed ~ctx paper =
  El.blockquote ~at:[At.class' "border-l pl-4 ml-0"] [
    El.div [
      El.p ~at:[At.class' "font-semibold"] [
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper))] [El.txt (Paper.title paper)]];
      El.p [authors ~ctx paper; El.txt "."];
      El.p [publisher paper; El.txt "."];
      El.p [bar ~ctx paper]]]

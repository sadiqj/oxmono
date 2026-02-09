(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Paper component rendering using htmlit. *)

open Htmlit

module Paper = Bushel.Paper
module Contact = Sortal_schema.Contact
module I = Arod.Icons

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

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

(** Render PDF/BIB/DOI/URL links inline with icons. *)
let bar ~ctx ?(nopdf = false) paper =
  let cfg = Arod.Ctx.config ctx in
  let icon_link ~icon ~label ~href =
    El.a ~at:[At.href href;
              At.class' "inline-flex items-center gap-1 text-secondary hover:text-link transition-colors whitespace-nowrap"]
      [El.unsafe_raw (I.outline ~size:14 icon); El.txt label]
  in
  let pdf =
    let pdf_path =
      Filename.concat cfg.paths.static_dir
        (Printf.sprintf "papers/%s.pdf" (Paper.slug paper))
    in
    if Sys.file_exists pdf_path && not nopdf then
      Some (icon_link ~icon:I.file_pdf_o ~label:"PDF"
              ~href:(Printf.sprintf "/papers/%s.pdf" (Paper.slug paper)))
    else None
  in
  let bib =
    if nopdf then None
    else
      Some (icon_link ~icon:I.braces_o ~label:"BIB"
              ~href:(Printf.sprintf "/papers/%s.bib" (Paper.slug paper)))
  in
  let url_el =
    match Paper.url paper with
    | None -> None
    | Some u ->
      Some (El.a ~at:[At.href u;
                At.class' "inline-flex items-center gap-1 text-secondary hover:text-link transition-colors whitespace-nowrap"]
        [El.unsafe_raw (I.outline ~size:14 I.external_link_o);
         El.txt "URL";
         El.span ~at:[At.class' "text-xs italic text-gray-400"] [
           El.txt (Printf.sprintf "(%s)" (host_without_www u))]])
  in
  let doi =
    match Paper.doi paper with
    | None -> None
    | Some d ->
      Some (icon_link ~icon:I.fingerprint_o ~label:"DOI"
              ~href:("https://doi.org/" ^ d))
  in
  let bits = [url_el; doi; bib; pdf] |> List.filter_map Fun.id in
  El.div ~at:[At.class' "flex items-center gap-4 flex-wrap text-sm mt-1"] bits

(** Brief paper card for lists. *)
let card ~ctx paper =
  let entries = Arod.Ctx.entries ctx in
  let thumb_el =
    match Bushel.Entry.thumbnail entries (`Paper paper) with
    | Some thumb_url ->
      [ El.div ~at:[At.class' "shrink-0 hidden sm:block"]
          [ El.img ~at:[At.src thumb_url; At.alt (Paper.title paper);
                        At.v "loading" "lazy";
                        At.class' "w-16 h-16 rounded object-cover"] () ] ]
    | None -> []
  in
  let content =
    El.div ~at:[At.class' "flex-1 min-w-0"] [
      El.p ~at:[At.class' "font-semibold leading-snug"] [
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper))] [El.txt (Paper.title paper)]];
      El.p ~at:[At.class' "text-sm text-secondary leading-snug mt-0.5"]
        [authors ~ctx paper; El.txt "."];
      El.p ~at:[At.class' "text-sm text-secondary"]
        [publisher paper; El.txt "."];
      bar ~ctx paper]
  in
  El.div ~at:[At.class' "flex gap-4 items-start"] (content :: thumb_el)

(** Full paper view with abstract and image.
    Metadata (authors, publisher, links) is now in the sidebar. *)
let full ~ctx paper =
  let img_el =
    match Arod.Ctx.lookup_image ctx (Paper.slug paper) with
    | Some img_ent ->
      let origin_url =
        Printf.sprintf "/images/%s.webp"
          (Filename.chop_extension (Srcsetter.origin img_ent))
      in
      El.div ~at:[At.class' "my-4"] [
        El.a ~at:[At.href (Option.value ~default:"#" (Paper.best_url paper))] [
          El.img ~at:[At.src origin_url; At.v "loading" "lazy"; At.alt (Paper.title paper);
                      At.class' "rounded shadow-sm max-w-full"] ()]]
    | None -> El.void
  in
  let abstract_text = Paper.abstract paper in
  let abstract_html, sidenotes =
    if abstract_text <> "" then
      let html, sns = Arod.Md.to_html ~ctx abstract_text in
      (El.div ~at:[At.class' "mt-4"] [
        El.h3 ~at:[At.class' "text-sm font-semibold text-secondary uppercase tracking-wide mb-2"]
          [El.txt "Abstract"];
        El.div [El.unsafe_raw html]], sns)
    else (El.void, [])
  in
  (El.div ~at:[At.class' "mb-4"] [
    El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [El.txt (Paper.title paper)];
    El.p ~at:[At.class' "text-secondary text-sm"] [authors ~ctx paper; El.txt "."];
    El.p ~at:[At.class' "text-secondary text-sm"] [publisher paper; El.txt "."];
    img_el;
    abstract_html], sidenotes)

(** Render older versions section as a timeline. *)
let extra ~ctx paper =
  let entries = Arod.Ctx.entries ctx in
  let all =
    Bushel.Entry.old_papers entries
    |> List.filter (fun op -> Paper.slug op = Paper.slug paper)
  in
  match all with
  | [] -> El.void
  | all ->
    let ptime_date (y, m, _d) =
      Printf.sprintf "%s %d" (month_name m) y
    in
    let older_versions = List.map (fun op ->
      let (y, m, _) = Paper.date op in
      let date_str = ptime_date (y, m, 0) in
      let ver_label = op.Paper.ver in
      let abstract_preview =
        let abs = Paper.abstract op in
        if abs <> "" then
          let truncated = if String.length abs > 150 then
            String.sub abs 0 150 ^ "..."
          else abs in
          El.p ~at:[At.class' "text-sm text-secondary mt-1 leading-snug"]
            [El.txt truncated]
        else El.void
      in
      El.div ~at:[At.class' "paper-version-item"; At.id (Printf.sprintf "older-versions")] [
        El.div ~at:[At.class' "paper-version-dot"] [];
        El.div ~at:[At.class' "flex-1 min-w-0"] [
          El.div ~at:[At.class' "flex items-baseline gap-2 flex-wrap"] [
            El.span ~at:[At.class' "paper-version-badge"] [El.txt ver_label];
            El.span ~at:[At.class' "text-sm text-secondary"] [El.txt date_str]];
          El.p ~at:[At.class' "text-sm mt-0.5"] [
            El.txt (Paper.title op)];
          (let venue =
            let bibty = String.lowercase_ascii (Paper.bibtype op) in
            match bibty with
            | "inproceedings" | "abstract" -> Paper.booktitle op
            | "article" | "journal" -> Paper.journal op
            | _ -> Paper.publisher op
          in
          if venue <> "" then
            El.p ~at:[At.class' "text-xs text-secondary mt-0.5"] [El.txt venue]
          else El.void);
          abstract_preview;
          bar ~ctx ~nopdf:true op]]
    ) all in
    El.div ~at:[At.class' "mt-8"] [
      El.h3 ~at:[At.class' "text-sm font-semibold text-secondary uppercase tracking-wide mb-3"]
        [El.txt "Older versions"];
      El.p ~at:[At.class' "text-sm text-secondary mb-4"]
        [El.txt "Earlier revisions are shown below. Please cite the latest version above."];
      El.div ~at:[At.class' "paper-version-timeline"] older_versions]

(** {1 Papers List Page} *)

let classification_label = function
  | Paper.Full -> "Full paper"
  | Short -> "Short / workshop"
  | Preprint -> "Preprint / tech report"

let classification_class = function
  | Paper.Full -> "paper-full"
  | Short -> "paper-short"
  | Preprint -> "paper-preprint"

let classification_dot cls =
  El.unsafe_raw (I.filled ~size:8
    (Printf.sprintf {|<circle cx="12" cy="12" r="10" class="%s"/>|} cls))

(** Filter/stats sidebar for papers list page. *)
let classification_filter_box ~total ~counts =
  let rows = List.map (fun (cls, count) ->
    let label = classification_label cls in
    let cls_str = classification_class cls in
    let data_cls = match cls with
      | Paper.Full -> "full" | Short -> "short" | Preprint -> "preprint"
    in
    El.label ~at:[At.class' "paper-filter-row"] [
      El.input ~at:[At.type' "checkbox"; At.checked;
                    At.v "data-classification" data_cls;
                    At.class' "classification-checkbox sr-only"] ();
      classification_dot cls_str;
      El.span ~at:[At.class' "paper-filter-label"] [El.txt label];
      El.span ~at:[At.class' "paper-stat-count"] [El.txt (string_of_int count)]]
  ) counts in
  El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
    El.div ~at:[At.class' "sidebar-meta-header"] [
      El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
      El.txt " ";
      El.span [El.txt (Printf.sprintf "filter: %d papers" total)]];
    El.div ~at:[At.class' "sidebar-meta-body"] rows]

(** Compact paper card for list view. *)
let compact_card ~ctx paper =
  let (y, m, _) = Bushel.Entry.date (`Paper paper) in
  let cls = Paper.classification paper in
  let cls_str = match cls with
    | Full -> "full" | Short -> "short" | Preprint -> "preprint"
  in
  let url = Bushel.Entry.site_url (`Paper paper) in
  let all_tags = Arod.Ctx.tags_of_ent ctx (`Paper paper) in
  let tag_strs = List.map Bushel.Tags.to_raw_string all_tags in
  let tags_data = String.concat "," tag_strs in
  El.div ~at:[At.class' "note-compact paper-item note-item";
              At.v "data-classification" cls_str;
              At.v "data-tags" tags_data;
              At.v "data-year" (string_of_int y)] [
    (* Row 1: title + date *)
    El.div ~at:[At.class' "note-compact-row"] [
      El.a ~at:[At.href url; At.class' "note-compact-title no-underline"]
        [El.txt (Paper.title paper)];
      El.span ~at:[At.class' "note-compact-meta"]
        [El.txt (Printf.sprintf "%s %d" (month_name m) y)]];
    (* Row 2: authors + publisher *)
    El.div ~at:[At.class' "note-compact-synopsis"]
      [authors ~ctx paper; El.txt ". "; publisher paper; El.txt "."];
    (* Row 3: action links *)
    bar ~ctx paper]

(** Full papers list page grouped by year, returns (article, sidebar). *)
let papers_list ~ctx =
  let entries = Arod.Ctx.entries ctx in
  let all_papers =
    Bushel.Entry.all_entries entries
    |> List.filter_map (function `Paper p -> Some p | _ -> None)
    |> List.sort (fun a b -> Paper.compare a b)
  in
  let total = List.length all_papers in
  (* Count by classification *)
  let count_full = List.length (List.filter (fun p -> Paper.classification p = Paper.Full) all_papers) in
  let count_short = List.length (List.filter (fun p -> Paper.classification p = Paper.Short) all_papers) in
  let count_preprint = List.length (List.filter (fun p -> Paper.classification p = Paper.Preprint) all_papers) in
  let counts = [Paper.Full, count_full; Short, count_short; Preprint, count_preprint] in
  (* Build tag frequency map *)
  let tag_counts = Hashtbl.create 64 in
  List.iter (fun p ->
    let tags = Arod.Ctx.tags_of_ent ctx (`Paper p) in
    List.iter (fun tag ->
      let t = Bushel.Tags.to_raw_string tag in
      let cur = try Hashtbl.find tag_counts t with Not_found -> 0 in
      Hashtbl.replace tag_counts t (cur + 1)
    ) tags
  ) all_papers;
  let sorted_tags =
    Hashtbl.fold (fun t c acc -> (t, c) :: acc) tag_counts []
    |> List.sort (fun (_, a) (_, b) -> compare b a)
  in
  let top_tags = List.filteri (fun i _ -> i < 20) sorted_tags in
  (* Group by year *)
  let by_year = Hashtbl.create 32 in
  List.iter (fun p ->
    let y = Paper.year p in
    let cur = try Hashtbl.find by_year y with Not_found -> [] in
    Hashtbl.replace by_year y (p :: cur)
  ) all_papers;
  let years = Hashtbl.fold (fun y _ acc -> y :: acc) by_year []
    |> List.sort (fun a b -> compare b a) in
  (* Build calendar data JSON: { "YYYY": [month, month, ...], ... }
     Each paper contributes its month number; JS uses length for count
     and Set for unique months. *)
  let calendar_json =
    let year_entries = List.map (fun y ->
      let papers = Hashtbl.find by_year y in
      let months = List.map (fun p ->
        let (_, m, _) = Bushel.Entry.date (`Paper p) in m
      ) papers in
      let month_strs = List.map string_of_int months in
      Printf.sprintf {|"%d":[%s]|} y (String.concat "," month_strs)
    ) years in
    "{" ^ String.concat "," year_entries ^ "}"
  in
  (* Render year sections *)
  let year_sections = List.map (fun y ->
    let papers = List.rev (Hashtbl.find by_year y) in
    let paper_cards = List.map (fun p -> compact_card ~ctx p) papers in
    El.div ~at:[At.id (Printf.sprintf "year-%d" y);
                At.v "data-year-id" (string_of_int y);
                At.class' "mb-6"] [
      El.h2 ~at:[At.class' "note-month-header sticky top-0 bg-bg z-10 py-0.5"] [
        El.txt (string_of_int y)];
      El.div ~at:[At.class' "note-month-list"] paper_cards]
  ) years in
  let article =
    El.article [
      El.h1 ~at:[At.class' "page-title text-2xl font-semibold mb-4"] [El.txt "Papers"];
      El.div year_sections]
  in
  (* Sidebar: classification filter *)
  let filter_box = classification_filter_box ~total ~counts in
  (* Sidebar: calendar box — year heatmap + month grid *)
  let first_year = match years with
    | y :: _ -> string_of_int y
    | [] -> ""
  in
  let calendar_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3";
                At.id "papers-calendar";
                At.v "data-calendar-years" calendar_json;
                At.v "data-current-year" first_year] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %d papers" total)];
      El.div ~at:[At.class' "sidebar-meta-body notes-calendar"] [
        El.div ~at:[At.class' "cal-header"] [];
        El.div ~at:[At.class' "heatmap-strip"] [];
        El.div ~at:[At.class' "cal-divider"] [];
        El.div ~at:[At.class' "cal-grid"] []]]
  in
  (* Sidebar: tag cloud box *)
  let tag_cloud_box = match top_tags with
    | [] -> El.void
    | _ ->
      let tag_btns = List.map (fun (tag, count) ->
        El.button ~at:[At.class' "tag-cloud-btn";
                       At.v "data-tag" tag] [
          El.txt tag;
          El.span ~at:[At.class' "tag-count"] [
            El.txt (string_of_int count)]]
      ) top_tags in
      El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
        El.div ~at:[At.class' "sidebar-meta-header"] [
          El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
          El.txt " tags"];
        El.div ~at:[At.class' "sidebar-meta-body tag-cloud"]
          tag_btns]
  in
  let sidebar =
    El.aside ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
      [El.div ~at:[At.class' "sticky top-16"]
         [filter_box; calendar_box; tag_cloud_box]]
  in
  (article, sidebar)

(** Paper entry for feeds. *)
let for_feed ~ctx paper =
  El.blockquote ~at:[At.class' "border-l pl-4 ml-0"] [
    El.div [
      El.p ~at:[At.class' "font-semibold"] [
        El.a ~at:[At.href (Bushel.Entry.site_url (`Paper paper))] [El.txt (Paper.title paper)]];
      El.p [authors ~ctx paper; El.txt "."];
      El.p [publisher paper; El.txt "."];
      El.p [bar ~ctx paper]]]

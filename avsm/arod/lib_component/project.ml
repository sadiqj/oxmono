(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Project component rendering using htmlit. *)

open Htmlit

module Project = Bushel.Project
module B_paper = Bushel.Paper

module StringSet = Set.Make(String)

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_short (y, m, _d) =
  Printf.sprintf "%s %4d" (month_name m) y

let take n l =
  let[@tail_mod_cons] rec aux n l =
    match n, l with
    | 0, _ | _, [] -> []
    | n, x :: rest -> x :: aux (n - 1) rest
  in
  if n < 0 then invalid_arg "take"; aux n l

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

(** Icon filename for an entry type. *)
let ent_to_icon = function
  | `Paper _ -> "paper.svg"
  | `Note _ -> "note.svg"
  | `Project _ -> "project.svg"
  | `Idea _ -> "idea.svg"
  | `Video _ -> "video.svg"

(** {1 Main Rendering Functions} *)

(** Project card with recent papers/notes. *)
let card ~ctx proj =
  let all_entries = Arod.Ctx.all_entries ctx in
  let project_slug = proj.Project.slug in
  let recent_papers =
    List.filter (fun e ->
      match e with
      | `Paper paper -> List.mem project_slug (B_paper.project_slugs paper)
      | _ -> false
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
    |> (fun l -> take 3 l)
  in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug project_slug in
  let backlink_set =
    List.fold_left (fun acc slug -> StringSet.add slug acc) StringSet.empty backlink_slugs
  in
  let recent_notes =
    List.filter (fun e ->
      match e with
      | `Note _ -> StringSet.mem (Bushel.Entry.slug e) backlink_set
      | _ -> false
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
    |> (fun l -> take 3 l)
  in
  let paper_items = List.map (fun ent ->
    let link = El.a ~at:[At.href (Bushel.Entry.site_url ent)] [El.txt (Bushel.Entry.title ent)] in
    El.li [link]
  ) recent_papers in
  let note_items = List.map (fun ent ->
    let link = El.a ~at:[At.href (Bushel.Entry.site_url ent)] [El.txt (Bushel.Entry.title ent)] in
    El.li [link]
  ) recent_notes in
  let recent_items_display =
    if paper_items = [] && note_items = [] then El.void
    else
      El.div ~at:[At.class' "mt-4 grid grid-cols-2 gap-4"] [
        (if paper_items <> [] then
           El.div [
             El.h4 ~at:[At.class' "font-semibold text-sm mb-1"] [El.txt "Recent papers"];
             El.ul ~at:[At.class' "text-sm ml-4"] paper_items]
         else El.void);
        (if note_items <> [] then
           El.div [
             El.h4 ~at:[At.class' "font-semibold text-sm mb-1"] [El.txt "Recent notes"];
             El.ul ~at:[At.class' "text-sm ml-4"] note_items]
         else El.void)]
  in
  let body_html, _wc = truncated_body ~ctx (`Project proj) in
  El.div ~at:[At.class' "mb-6 border rounded-lg p-4"] [
    El.h3 ~at:[At.class' "text-lg font-semibold mb-2"] [
      El.a ~at:[At.href ("/projects/" ^ proj.Project.slug)] [El.txt proj.Project.title]];
    El.div ~at:[At.class' "mb-2"] [body_html];
    recent_items_display]

(** Full project with activity and references. *)
let full ~ctx proj =
  let entries = Arod.Ctx.entries ctx in
  let project_slug = proj.Project.slug in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug project_slug in
  let backlink_set =
    List.fold_left (fun acc slug -> StringSet.add slug acc) StringSet.empty backlink_slugs
  in
  let all_entries = Arod.Ctx.all_entries ctx in
  let project_papers =
    List.filter (fun e ->
      match e with
      | `Paper paper -> List.mem project_slug (B_paper.project_slugs paper)
      | _ -> false
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  let recent_activity =
    List.filter (fun e ->
      match e with
      | `Paper _ -> false
      | _ -> StringSet.mem (Bushel.Entry.slug e) backlink_set
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  let activity_section =
    if recent_activity = [] then El.void
    else
      let activity_items = List.map (fun ent ->
        let icon_name = ent_to_icon ent in
        let date_str = ptime_date_short (Bushel.Entry.date ent) in
        let lookup_title slug =
          match Bushel.Entry.lookup entries slug with
          | Some ent -> Some (Bushel.Entry.title ent)
          | None -> None
        in
        let description = match ent with
          | `Paper paper -> Bushel.Description.paper_description paper ~date_str
          | `Note n -> Bushel.Description.note_description n ~date_str ~lookup_fn:lookup_title
          | `Idea i -> Bushel.Description.idea_description i ~date_str
          | `Video v -> Bushel.Description.video_description v ~date_str ~lookup_fn:lookup_title
          | `Project pr -> Bushel.Description.project_description pr
        in
        El.li ~at:[At.class' "flex items-center gap-2 mb-2"] [
          El.img ~at:[At.alt "icon"; At.src (Printf.sprintf "/assets/%s" icon_name);
                      At.class' "w-4 h-4 inline-block"] ();
          El.a ~at:[At.href (Bushel.Entry.site_url ent)] [El.txt (Bushel.Entry.title ent)];
          El.txt " \u{2013} ";
          El.span ~at:[At.class' "text-sm text-secondary"] [El.txt description]]
      ) recent_activity in
      El.div ~at:[At.class' "mt-8"] [
        El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "Activity"];
        El.ul activity_items]
  in
  let references_section =
    if project_papers = [] then El.void
    else
      let paper_items = List.map (fun ent ->
        match ent with
        | `Paper paper -> Paper.card ~ctx paper
        | _ -> El.void
      ) project_papers in
      El.div ~at:[At.class' "mt-8"] [
        El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "References"];
        El.div paper_items]
  in
  let body_html, sidenotes = Arod.Md.to_html ~ctx (Project.body proj) in
  (El.div ~at:[At.class' "mb-4"] [
    El.h1 ~at:[At.class' "page-title text-xl font-semibold mb-3"] [El.txt (Project.title proj)];
    El.p [El.unsafe_raw body_html];
    activity_section;
    references_section], sidenotes)

(** Vertical timeline with project cards. *)
let timeline ~ctx =
  let all_projects =
    Arod.Ctx.projects ctx |> List.sort Project.compare |> List.rev
  in
  if all_projects = [] then
    El.div [El.txt "No projects found"]
  else
    let current_year =
      let (y, _, _), _ = Ptime.to_date_time (Ptime_clock.now ()) in y
    in
    let project_cards = List.map (fun proj ->
      let start_year = proj.Project.start in
      let end_year = match proj.Project.finish with
        | Some y -> y | None -> current_year
      in
      let duration = end_year - start_year in
      let all_entries = Arod.Ctx.all_entries ctx in
      let project_slug = proj.Project.slug in
      let recent_papers =
        List.filter (fun e ->
          match e with
          | `Paper paper -> List.mem project_slug (B_paper.project_slugs paper)
          | _ -> false
        ) all_entries
        |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
        |> (fun l -> take 3 l)
      in
      let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug project_slug in
      let backlink_set =
        List.fold_left (fun acc slug ->
          StringSet.add slug acc) StringSet.empty backlink_slugs
      in
      let recent_notes =
        List.filter (fun e ->
          match e with
          | `Note _ -> StringSet.mem (Bushel.Entry.slug e) backlink_set
          | _ -> false
        ) all_entries
        |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
        |> (fun l -> take 3 l)
      in
      let paper_items = List.map (fun ent ->
        let link = El.a ~at:[At.href (Bushel.Entry.site_url ent)] [
          El.txt (Bushel.Entry.title ent)] in
        El.li [link]
      ) recent_papers in
      let note_items = List.map (fun ent ->
        let link = El.a ~at:[At.href (Bushel.Entry.site_url ent)] [
          El.txt (Bushel.Entry.title ent)] in
        El.li [link]
      ) recent_notes in
      let recent_items_display =
        if paper_items = [] && note_items = [] then El.void
        else
          El.div ~at:[At.class' "mt-4 grid grid-cols-2 gap-4"] [
            (if paper_items <> [] then
               El.div [
                 El.h4 ~at:[At.class' "font-semibold text-sm mb-1"] [El.txt "Recent papers"];
                 El.ul ~at:[At.class' "text-sm ml-4"] paper_items]
             else El.void);
            (if note_items <> [] then
               El.div [
                 El.h4 ~at:[At.class' "font-semibold text-sm mb-1"] [El.txt "Recent notes"];
                 El.ul ~at:[At.class' "text-sm ml-4"] note_items]
             else El.void)]
      in
      let thumbnail_md =
        Printf.sprintf "![%%lc](:project-%s \"%s\")"
          proj.Project.slug proj.Project.title
      in
      let thumbnail_html = El.unsafe_raw (fst (Arod.Md.to_html ~ctx thumbnail_md)) in
      let date_range = match proj.Project.finish with
        | Some y -> Printf.sprintf "%d\u{2013}%d" start_year y
        | None -> Printf.sprintf "%d\u{2013}present" start_year
      in
      let duration_height = max 40 (duration * 8) in
      let body_html, _wc = truncated_body ~ctx (`Project proj) in
      El.div ~at:[At.class' "flex gap-4 mb-8"] [
        (* Timeline marker column *)
        El.div ~at:[At.class' "flex-none w-16 flex flex-col items-center"] [
          El.div ~at:[At.class' "w-3 h-3 rounded-full timeline-dot"] [];
          El.div ~at:[At.class' "timeline-duration"; At.v "style" (Printf.sprintf "height: %dpx; width: 1px" duration_height)] [];
          El.span ~at:[At.class' "text-xs text-secondary mt-1"] [
            El.txt (string_of_int start_year)]];
        (* Project card *)
        El.div ~at:[At.class' "flex-1 border rounded-lg p-4"] [
          El.div ~at:[At.class' "flex justify-between items-center mb-2"] [
            El.h3 ~at:[At.class' "text-lg font-semibold"] [
              El.a ~at:[At.href ("/projects/" ^ proj.Project.slug)] [
                El.txt proj.Project.title]];
            El.span ~at:[At.class' "text-sm text-secondary"] [El.txt date_range]];
          thumbnail_html;
          El.div ~at:[At.class' "mb-2"] [body_html];
          recent_items_display]]
    ) all_projects in
    let intro = El.p ~at:[At.class' "mb-6"] [
      El.txt "Research projects and relevant publications, ideas and notes."]
    in
    El.div [
      El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "Projects"];
      intro;
      El.div project_cards]

(** Project for feeds. *)
let for_feed ~ctx proj =
  truncated_body ~ctx (`Project proj)

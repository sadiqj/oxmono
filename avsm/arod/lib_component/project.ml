(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Project component rendering using htmlit. *)

open Htmlit

module Project = Bushel.Project
module B_paper = Bushel.Paper
module I = Arod.Icons

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

(** Truncate the body of an entry, returning (body_html, read_more_el, word_count_info). *)
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
  let markdown_content = first ^ footnotes_text in
  let body_html = El.unsafe_raw (fst (Arod.Md.to_html ~ctx markdown_content)) in
  let read_more_el = match word_count_info with
    | Some (total, true) ->
      let url = Bushel.Entry.site_url ent in
      El.a ~at:[At.href url; At.class' "project-read-more"]
        [El.unsafe_raw (I.outline ~size:14 I.arrow_right_sm_o);
         El.txt (Printf.sprintf " Read more (%d words)" total)]
    | _ -> El.void
  in
  (El.div [body_html; read_more_el], word_count_info)

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
  let entry_row icon_svg ent =
    El.div ~at:[At.class' "project-entry-row"] [
      El.span ~at:[At.class' "project-entry-icon"]
        [El.unsafe_raw (I.outline ~size:12 icon_svg)];
      El.a ~at:[At.href (Bushel.Entry.site_url ent);
                At.class' "project-entry-link"]
        [El.txt (Bushel.Entry.title ent)]]
  in
  let paper_items = List.map (entry_row I.paper_o) recent_papers in
  let note_items = List.map (entry_row I.writing_o) recent_notes in
  let recent_items_display =
    if paper_items = [] && note_items = [] then El.void
    else
      El.div ~at:[At.class' "project-entries not-prose"] (paper_items @ note_items)
  in
  let body_html, _wc = truncated_body ~ctx (`Project proj) in
  El.div ~at:[At.class' "mb-6 border rounded-lg p-4"] [
    El.h3 ~at:[At.class' "text-lg font-semibold mb-2"] [
      El.a ~at:[At.href ("/projects/" ^ proj.Project.slug)] [El.txt proj.Project.title]];
    El.div ~at:[At.class' "mb-2"] [body_html];
    recent_items_display]

(** Full project with activity stream and references. *)
let full ~ctx proj =
  let project_slug = proj.Project.slug in
  let backlink_slugs = Bushel.Link_graph.get_backlinks_for_slug project_slug in
  let outbound_slugs = Bushel.Link_graph.get_outbound_for_slug project_slug in
  let backlink_set =
    List.fold_left (fun acc slug -> StringSet.add slug acc) StringSet.empty backlink_slugs
  in
  let all_entries = Arod.Ctx.all_entries ctx in
  let entries = Arod.Ctx.entries ctx in
  (* Papers explicitly tagged with this project *)
  let project_papers =
    List.filter (fun e ->
      match e with
      | `Paper paper -> List.mem project_slug (B_paper.project_slugs paper)
      | _ -> false
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  (* Ideas belonging to this project *)
  let project_ideas =
    List.filter (fun e ->
      match e with
      | `Idea i -> Bushel.Idea.project i = project_slug
      | _ -> false
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  (* Backlinked entries (notes, videos, etc.) *)
  let backlinked_entries =
    List.filter (fun e ->
      match e with
      | `Paper _ -> false  (* papers shown separately *)
      | `Idea _ -> false   (* ideas shown separately *)
      | _ -> StringSet.mem (Bushel.Entry.slug e) backlink_set
    ) all_entries
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  (* Outbound entries not already covered *)
  let covered = Hashtbl.create 32 in
  List.iter (fun e -> Hashtbl.replace covered (Bushel.Entry.slug e) ()) project_papers;
  List.iter (fun e -> Hashtbl.replace covered (Bushel.Entry.slug e) ()) project_ideas;
  List.iter (fun e -> Hashtbl.replace covered (Bushel.Entry.slug e) ()) backlinked_entries;
  Hashtbl.replace covered project_slug ();
  let outbound_entries =
    List.filter_map (fun s ->
      if Hashtbl.mem covered s then None
      else match Bushel.Entry.lookup entries s with
      | Some ent -> Hashtbl.replace covered s (); Some ent
      | None -> None
    ) outbound_slugs
    |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  (* Unified activity stream — all related entries sorted by date *)
  let all_activity =
    (project_papers @ project_ideas @ backlinked_entries @ outbound_entries)
    |> List.sort (fun a b ->
      compare (Bushel.Entry.date b) (Bushel.Entry.date a))
  in
  let activity_section = Sidebar.activity_stream ~title:"Activity" all_activity in
  let body_html, sidenotes = Arod.Md.to_html ~ctx (Project.body proj) in
  (El.div ~at:[At.class' "mb-4"] [
    El.h1 ~at:[At.class' "page-title text-xl font-semibold mb-3"] [El.txt (Project.title proj)];
    El.div [El.unsafe_raw body_html];
    activity_section], sidenotes)

(** Masonry-style two-column project grid with terminal-inspired cards. *)
let projects_list ~ctx =
  let all_projects =
    Arod.Ctx.projects ctx |> List.sort Project.compare |> List.rev
  in
  let all_entries = Arod.Ctx.all_entries ctx in
  let project_card proj =
    let project_slug = proj.Project.slug in
    let start_year = proj.Project.start in
    let date_range = match proj.Project.finish with
      | Some y -> Printf.sprintf "%d\u{2013}%d" start_year y
      | None -> Printf.sprintf "%d\u{2013}now" start_year
    in
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
    let recent_ideas =
      List.filter (fun e ->
        match e with
        | `Idea i -> Bushel.Idea.project i = project_slug
        | _ -> false
      ) all_entries
      |> List.sort (fun a b -> compare (Bushel.Entry.date b) (Bushel.Entry.date a))
      |> (fun l -> take 3 l)
    in
    let entry_row icon_svg ent =
      El.div ~at:[At.class' "project-entry-row"] [
        El.span ~at:[At.class' "project-entry-icon"]
          [El.unsafe_raw (I.outline ~size:11 icon_svg)];
        El.a ~at:[At.href (Bushel.Entry.site_url ent);
                  At.class' "project-entry-link"]
          [El.txt (Bushel.Entry.title ent)]]
    in
    let all_recent =
      (List.map (fun e -> (I.paper_o, e)) recent_papers) @
      (List.map (fun e -> (I.writing_o, e)) recent_notes) @
      (List.map (fun e -> (I.bulb_o, e)) recent_ideas)
    in
    let all_recent =
      List.sort (fun (_, a) (_, b) ->
        compare (Bushel.Entry.date b) (Bushel.Entry.date a)) all_recent
      |> (fun l -> take 5 l)
    in
    let recent_items =
      if all_recent = [] then El.void
      else
        El.div ~at:[At.class' "proj-card-recent"] (
          (El.div ~at:[At.class' "proj-card-section-label"]
            [El.txt "recent"]) ::
          List.map (fun (icon, ent) -> entry_row icon ent) all_recent)
    in
    (* Thumbnail *)
    let thumbnail_md =
      Printf.sprintf "![%%lc](:project-%s \"%s\")"
        proj.Project.slug proj.Project.title
    in
    let thumbnail_html = El.unsafe_raw (fst (Arod.Md.to_html ~ctx thumbnail_md)) in
    (* Summary — first paragraph *)
    let body = Project.body proj in
    let first, _ = Bushel.Util.first_and_last_hunks body in
    let summary_html = El.unsafe_raw (Arod.Md.to_plain_html ~ctx first) in
    (* Tags *)
    let tags = Project.tags proj in
    let tags_el =
      if tags = [] then El.void
      else
        El.div ~at:[At.class' "proj-card-tags"]
          (List.map (fun t ->
            El.span ~at:[At.class' "proj-card-tag"] [El.txt t]
          ) tags)
    in
    El.div ~at:[At.class' "proj-card not-prose"] [
      (* Header *)
      El.div ~at:[At.class' "proj-card-header"] [
        El.span ~at:[At.class' "proj-card-prompt"] [El.txt ">_"];
        El.a ~at:[At.href ("/projects/" ^ project_slug);
                  At.class' "proj-card-title no-underline"]
          [El.txt proj.Project.title];
        El.span ~at:[At.class' "proj-card-date"] [El.txt date_range]];
      (* Body *)
      El.div ~at:[At.class' "proj-card-body"] [
        El.div ~at:[At.class' "proj-card-thumb"] [thumbnail_html];
        El.div ~at:[At.class' "proj-card-summary"] [summary_html];
        tags_el];
      (* Recent items *)
      recent_items]
  in
  let cards = List.map project_card all_projects in
  let intro = El.p ~at:[At.class' "mb-6"] [
    El.txt "Research projects and relevant publications, ideas and notes."]
  in
  let article = El.article [
    El.h1 ~at:[At.class' "page-title text-2xl font-semibold mb-4"] [El.txt "Projects"];
    intro;
    El.div ~at:[At.class' "proj-grid"] cards]
  in
  article

(** Project for feeds. *)
let for_feed ~ctx proj =
  truncated_body ~ctx (`Project proj)

(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Idea component rendering using htmlit. *)

open Htmlit

module Idea = Bushel.Idea
module Contact = Sortal_schema.Contact
module I = Arod.Icons

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let ptime_date_short (y, m, _d) =
  Printf.sprintf "%s %4d" (month_name m) y

let map_and fn l =
  let ll = List.length l in
  List.mapi (fun i v ->
    match i with
    | 0 -> fn v
    | _ when i + 1 = ll -> " and " ^ (fn v)
    | _ -> ", " ^ (fn v)
  ) l |> String.concat ""

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

(** Render a heading for an entry. *)
let heading ~ctx:_ ent =
  El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
    El.a ~at:[At.href (Bushel.Entry.site_url ent)] [
      El.txt (Bushel.Entry.title ent)];
    El.span ~at:[At.class' "text-sm text-secondary"] [
      El.txt " / ";
      El.txt (ptime_date_short (Bushel.Entry.date ent))]]

(** {1 Status and Level Descriptions} *)

let status_class = function
  | Idea.Available -> "idea-available"
  | Discussion -> "idea-discussion"
  | Ongoing -> "idea-ongoing"
  | Completed -> "idea-completed"
  | Expired -> "idea-expired"

(** Colored status indicator span. *)
let status_badge status =
  let label = Idea.status_to_string status in
  El.span ~at:[At.class' (status_class status)] [El.txt label]

let status_to_long_string s = function
  | Idea.Available ->
    Printf.sprintf "is <span class=\"idea-available\">available</span> for being worked on"
  | Discussion ->
    Printf.sprintf "is <span class=\"idea-discussion\">under discussion</span> with a student but not yet confirmed"
  | Ongoing ->
    Printf.sprintf "is currently <span class=\"idea-ongoing\">being worked on</span> by %s" s
  | Completed ->
    Printf.sprintf "has been <span class=\"idea-completed\">completed</span> by %s" s
  | Expired ->
    Printf.sprintf "has <span class=\"idea-expired\">expired</span>"

let level_to_long_string = function
  | Idea.Any -> " as a good starter project"
  | PartII -> " as a Cambridge Computer Science Part II project"
  | MPhil -> " as a Cambridge Computer Science Part III or MPhil project"
  | PhD -> " as a Cambridge Computer Science PhD topic"
  | Postdoc -> " as a postdoctoral project"

let sups_for i =
  let v = match Idea.status i with
    | Idea.Completed -> "was" | Ongoing -> "is" | _ -> "may be"
  in
  let sups = List.filter (fun x -> x <> "avsm") i.Idea.supervisor_handles in
  match sups with
  | [] -> ""
  | s -> " It " ^ v ^ " co-supervised with " ^ (map_and (Printf.sprintf "[@%s]") s) ^ "."

(** {1 Contact Rendering} *)

let render_contacts ~ctx contacts =
  match contacts with
  | [] -> El.void
  | cs ->
    let contact_links = List.filter_map (fun handle ->
      match Arod.Ctx.lookup_by_handle ctx handle with
      | Some contact ->
        let name = Contact.name contact in
        (match Contact.best_url contact with
         | Some url -> Some (El.a ~at:[At.href url] [El.txt name])
         | None -> Some (El.txt name))
      | None -> Some (El.txt ("@" ^ handle))
    ) cs in
    let rec intersperse_and = function
      | [] -> [] | [x] -> [x] | [x; y] -> [x; El.txt " and "; y]
      | x :: xs -> x :: El.txt ", " :: intersperse_and xs
    in
    let children = intersperse_and contact_links in
    El.span children

(** Small filled status dot icon with the appropriate status colour class. *)
let status_dot status =
  let cls = "idea-dot " ^ status_class status in
  El.span ~at:[At.class' cls]
    [El.unsafe_raw (I.filled ~size:8 I.circle_f)]

(** Render an idea as a compact list row for project listings.
    Uses a coloured dot icon as the bullet; text stays neutral. *)
let to_html_no_sidenotes ~ctx idea =
  let idea_url = "/ideas/" ^ idea.Idea.slug in
  let sups = List.filter (fun x -> x <> "avsm") idea.Idea.supervisor_handles in
  let lev = match idea.Idea.level with
    | Idea.Any -> "" | PartII -> "Part II" | MPhil -> "MPhil"
    | PhD -> "PhD" | Postdoc -> "Postdoc"
  in
  let status_text = match idea.Idea.status with
    | Available -> "Available"
    | Discussion -> "Discussion"
    | Ongoing -> "Ongoing"
    | Completed -> "Completed"
    | Expired -> "Expired"
  in
  let detail_parts =
    [status_text] @
    (if lev <> "" then [lev] else []) @
    (match idea.Idea.status with
     | Ongoing | Completed when idea.Idea.student_handles <> [] -> []
     | _ -> [])
  in
  let detail_text = String.concat " \xC2\xB7 " detail_parts in
  let people_el = match idea.Idea.status with
    | Ongoing ->
      (match idea.Idea.student_handles with
       | [] -> El.void
       | _ -> El.span [El.txt " with "; render_contacts ~ctx idea.Idea.student_handles])
    | Completed ->
      (match idea.Idea.student_handles with
       | [] -> El.void
       | _ -> El.span [El.txt " by "; render_contacts ~ctx idea.Idea.student_handles;
                        El.txt (Printf.sprintf " (%d)" idea.Idea.year)])
    | _ -> El.void
  in
  let cosup_el = match sups with
    | [] -> El.void
    | _ -> El.span ~at:[At.class' "text-secondary"] [
        El.txt " + "; render_contacts ~ctx sups]
  in
  El.div ~at:[At.class' "idea-row"] [
    status_dot (Idea.status idea);
    El.div ~at:[At.class' "idea-row-content"] [
      El.a ~at:[At.href idea_url; At.class' "idea-row-title"]
        [El.txt (Idea.title idea)];
      El.span ~at:[At.class' "idea-row-meta"]
        [El.txt detail_text; people_el; cosup_el]]]

(** {1 Main Rendering Functions} *)

(** Brief idea with status/level info. *)
let brief ~ctx i =
  let studs = map_and (Printf.sprintf "[@%s]") (Idea.student_handles i) in
  let r = Printf.sprintf "This is an idea proposed in %d%s, and %s.%s"
    (Idea.year i) (level_to_long_string (Idea.level i))
    (status_to_long_string studs (Idea.status i)) (sups_for i)
  in
  let body_html, word_count_info = truncated_body ~ctx (`Idea i) in
  (El.div [
    heading ~ctx (`Idea i);
    El.div ~at:[At.class' "mb-4"] [El.unsafe_raw (fst (Arod.Md.to_html ~ctx r)); body_html]
  ], word_count_info)

(** Full idea page with structured header and article. *)
let full_page ~ctx i =
  let level_str = match Idea.level i with
    | Idea.Any -> "Any" | PartII -> "Part II" | MPhil -> "MPhil"
    | PhD -> "PhD" | Postdoc -> "Postdoc"
  in
  let sups = List.filter (fun x -> x <> "avsm") i.Idea.supervisor_handles in
  (* Mobile-only meta row *)
  let meta_row =
    El.p ~at:[At.class' "text-sm text-secondary mb-2 lg:hidden"]
      [status_badge (Idea.status i);
       El.txt (Printf.sprintf " \xC2\xB7 %s \xC2\xB7 %d" level_str (Idea.year i));
       (match sups with
        | [] -> El.void
        | _ -> El.span [El.txt " \xC2\xB7 "; render_contacts ~ctx sups])]
  in
  let title_el =
    El.h1 ~at:[At.class' "page-title text-xl font-semibold tracking-tight mb-3"]
      [El.txt (Idea.title i)]
  in
  let header_el =
    El.header ~at:[At.id "intro"; At.class' "mb-6"]
      [meta_row; title_el]
  in
  let body = Idea.body i in
  let body_html, sidenotes = Arod.Md.to_html ~ctx body in
  let headings = Arod.Md.extract_headings body in
  let article_el =
    El.article ~at:[At.class' "space-y-4"] [El.unsafe_raw body_html]
  in
  (El.div [header_el; article_el], sidenotes, headings)

(** Combined status filter + stats sidebar box. *)
let status_filter_box ~total ~counts =
  let checkbox ~id ~label_text ~checked:is_checked ~status_name ~cls ~count =
    El.label ~at:[At.class' "idea-filter-row"] [
      El.input ~at:([At.type' "checkbox"; At.id id;
        At.class' "status-checkbox";
        At.v "data-status" status_name]
        @ (if is_checked then [At.checked] else [])) ();
      El.span ~at:[At.class' ("idea-dot " ^ cls)]
        [El.unsafe_raw (I.filled ~size:7 I.circle_f)];
      El.span ~at:[At.class' "idea-filter-label"] [El.txt label_text];
      El.span ~at:[At.class' "idea-stat-count"] [El.txt (string_of_int count)]]
  in
  let (n_avail, n_discuss, n_ongoing, n_done, n_expired) = counts in
  El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
    El.div ~at:[At.class' "sidebar-meta-header"] [
      El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
      El.txt (Printf.sprintf " filter: %d ideas" total)];
    El.div ~at:[At.class' "sidebar-meta-body"] [
      checkbox ~id:"filter-available" ~label_text:"Available"
        ~checked:true ~status_name:"Available" ~cls:"idea-available" ~count:n_avail;
      checkbox ~id:"filter-discussion" ~label_text:"Discussion"
        ~checked:true ~status_name:"Discussion" ~cls:"idea-discussion" ~count:n_discuss;
      checkbox ~id:"filter-ongoing" ~label_text:"Ongoing"
        ~checked:true ~status_name:"Ongoing" ~cls:"idea-ongoing" ~count:n_ongoing;
      checkbox ~id:"filter-completed" ~label_text:"Completed"
        ~checked:true ~status_name:"Completed" ~cls:"idea-completed" ~count:n_done;
      checkbox ~id:"filter-expired" ~label_text:"Expired"
        ~checked:false ~status_name:"Expired" ~cls:"idea-expired" ~count:n_expired]]

(** Ideas grouped by project with status filter.
    Returns [(article, sidebar)] where sidebar contains stats, filter,
    and a project quick-jump list. *)
let by_project ~ctx =
  let all_ideas = Arod.Ctx.ideas ctx in
  let all_projects =
    Arod.Ctx.projects ctx
    |> List.sort Bushel.Project.compare
    |> List.rev
  in
  let ideas_by_project = Hashtbl.create 32 in
  List.iter (fun i ->
    let proj_slug = Idea.project i in
    let existing =
      try Hashtbl.find ideas_by_project proj_slug with Not_found -> []
    in
    Hashtbl.replace ideas_by_project proj_slug (i :: existing)
  ) all_ideas;
  Hashtbl.iter (fun proj_slug ideas ->
    Hashtbl.replace ideas_by_project proj_slug (List.sort Idea.compare ideas)
  ) ideas_by_project;
  (* Collect projects that have ideas, for sidebar list *)
  let projects_with_ideas = List.filter_map (fun proj ->
    let proj_slug = proj.Bushel.Project.slug in
    match Hashtbl.find_opt ideas_by_project proj_slug with
    | None -> None
    | Some ideas -> Some (proj, ideas)
  ) all_projects in
  let project_sections = List.map (fun (proj, ideas) ->
    let proj_slug = proj.Bushel.Project.slug in
    let idea_items = List.map (fun i ->
      El.div ~at:[At.v "data-status" (Idea.status_to_string (Idea.status i));
                  At.class' "idea-item"] [
        to_html_no_sidenotes ~ctx i]
    ) ideas in
    let thumbnail_md =
      Printf.sprintf "![%%lc](:project-%s \"%s\")"
        proj_slug proj.Bushel.Project.title
    in
    let thumbnail_html = El.unsafe_raw (fst (Arod.Md.to_html ~ctx thumbnail_md)) in
    let body_html, _wc = truncated_body ~ctx (`Project proj) in
    let view_link =
      El.a ~at:[At.href ("/projects/" ^ proj_slug);
                At.class' "idea-view-project"]
        [El.unsafe_raw (I.outline ~size:14 I.arrow_right_sm_o);
         El.txt " View project"]
    in
    El.div ~at:[At.id ("proj-" ^ proj_slug); At.class' "idea-project-card"] [
      El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
        El.a ~at:[At.href ("/projects/" ^ proj_slug)] [
          El.txt proj.Bushel.Project.title]];
      El.div ~at:[At.class' "idea-project-body"] [
        thumbnail_html;
        El.div ~at:[At.class' "idea-project-desc"] [body_html];
        view_link];
      El.div ~at:[At.class' "idea-list"] idea_items]
  ) projects_with_ideas in
  let intro = El.p ~at:[At.class' "mb-6"] [
    El.txt "These are research ideas for students at various levels \
         (Part II, MPhil, PhD, and postdoctoral). Browse through the ideas \
         below to find projects that interest you. You're also welcome to \
         propose your own research ideas that align with our ongoing projects."]
  in
  let article = El.div [
    El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "Research Ideas"];
    intro;
    El.div project_sections]
  in
  (* Sidebar: combined filter/stats + project jump list *)
  let total = List.length all_ideas in
  let count_status s = List.length (List.filter (fun i -> Idea.status i = s) all_ideas) in
  let counts = (count_status Idea.Available, count_status Idea.Discussion,
                count_status Idea.Ongoing, count_status Idea.Completed,
                count_status Idea.Expired) in
  let filter_box = status_filter_box ~total ~counts in
  let proj_jump_items = List.map (fun (proj, ideas) ->
    let proj_slug = proj.Bushel.Project.slug in
    let n = List.length ideas in
    El.a ~at:[At.href ("#proj-" ^ proj_slug);
              At.class' "idea-jump-link no-underline"]
      [El.span ~at:[At.class' "idea-jump-title"]
         [El.txt proj.Bushel.Project.title];
       El.span ~at:[At.class' "idea-jump-count"]
         [El.txt (string_of_int n)]]
  ) projects_with_ideas in
  let proj_jump_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " projects"];
      El.div ~at:[At.class' "sidebar-meta-body idea-jump-list"]
        proj_jump_items]
  in
  let sidebar =
    El.aside ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
      [El.div ~at:[At.class' "sticky top-16"]
         [filter_box; proj_jump_box]]
  in
  (article, sidebar)

(** Idea for feeds. *)
let for_feed ~ctx i =
  let studs = map_and (Printf.sprintf "[@%s]") (Idea.student_handles i) in
  let r = Printf.sprintf "This is an idea proposed %s, and %s.%s"
    (level_to_long_string (Idea.level i))
    (status_to_long_string studs (Idea.status i)) (sups_for i)
  in
  let body_html, word_count_info = truncated_body ~ctx (`Idea i) in
  (El.div [El.unsafe_raw (fst (Arod.Md.to_html ~ctx r)); body_html], word_count_info)

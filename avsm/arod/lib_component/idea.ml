(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Idea component rendering using htmlit. *)

open Htmlit

module Idea = Bushel.Idea
module Contact = Sortal_schema.Contact

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

let status_color = function
  | Idea.Available -> "#22c55e"
  | Discussion -> "#3b82f6"
  | Ongoing -> "#f59e0b"
  | Completed -> "#6b7280"
  | Expired -> "#ef4444"

(** Colored status indicator span. *)
let status_badge status =
  let label = Idea.status_to_string status in
  El.span ~at:[At.class' "font-medium"; At.style ("color:" ^ status_color status)] [El.txt label]

let status_to_long_string s = function
  | Idea.Available ->
    Printf.sprintf "is <span style=\"color:#22c55e;font-weight:500\">available</span> for being worked on"
  | Discussion ->
    Printf.sprintf "is <span style=\"color:#3b82f6;font-weight:500\">under discussion</span> with a student but not yet confirmed"
  | Ongoing ->
    Printf.sprintf "is currently <span style=\"color:#f59e0b;font-weight:500\">being worked on</span> by %s" s
  | Completed ->
    Printf.sprintf "has been <span style=\"color:#6b7280;font-weight:500\">completed</span> by %s" s
  | Expired ->
    Printf.sprintf "has <span style=\"color:#ef4444;font-weight:500\">expired</span>"

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

(** Render an idea without sidenotes (for project listings). *)
let to_html_no_sidenotes ~ctx idea =
  let idea_url = "/ideas/" ^ idea.Idea.slug in
  let sups = List.filter (fun x -> x <> "avsm") idea.Idea.supervisor_handles in
  let sups_el = match sups with
    | [] -> El.void
    | _ -> El.span [El.txt " and cosupervised with "; render_contacts ~ctx sups]
  in
  let studs_el = match idea.Idea.student_handles with
    | [] -> El.void
    | _ -> El.span [render_contacts ~ctx idea.Idea.student_handles]
  in
  let lev = match idea.Idea.level with
    | Idea.Any -> "" | PartII -> " (Part II)" | MPhil -> " (MPhil)"
    | PhD -> " (PhD)" | Postdoc -> ""
  in
  match idea.Idea.status with
  | Available ->
    El.span [
      El.a ~at:[At.href idea_url] [El.txt (Idea.title idea)]; El.txt " "; El.br ();
      El.span ~at:[At.class' "font-medium"; At.style "color:#22c55e"]
        [El.txt ("Available" ^ lev)];
      El.txt " "; sups_el]
  | Discussion ->
    El.span [
      El.a ~at:[At.href idea_url] [El.txt (Idea.title idea)]; El.txt " "; El.br ();
      El.span ~at:[At.class' "font-medium"; At.style "color:#3b82f6"]
        [El.txt ("Under discussion" ^ lev)];
      El.txt " "; sups_el]
  | Ongoing ->
    El.span [
      El.a ~at:[At.href idea_url] [El.txt (Idea.title idea)]; El.txt " "; El.br ();
      El.span ~at:[At.class' "font-medium"; At.style "color:#f59e0b"]
        [El.txt ("Currently ongoing" ^ lev)];
      El.txt " with "; studs_el; El.txt " "; sups_el]
  | Completed ->
    El.span [
      El.a ~at:[At.href idea_url] [El.txt (Idea.title idea)]; El.txt " "; El.br ();
      El.span ~at:[At.class' "font-medium"; At.style "color:#6b7280"]
        [El.txt ("Completed" ^ lev)];
      El.txt " by "; studs_el; El.txt " "; sups_el;
      El.txt (" in " ^ string_of_int idea.Idea.year)]
  | Expired ->
    El.span [
      El.a ~at:[At.href idea_url] [El.txt (Idea.title idea)]; El.txt " "; El.br ();
      El.span ~at:[At.class' "font-medium"; At.style "color:#ef4444"]
        [El.txt ("Expired" ^ lev)];
      El.txt " "; sups_el]

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

(** Full idea rendering. *)
let full ~ctx i =
  let studs = map_and (Printf.sprintf "[@%s]") (Idea.student_handles i) in
  let r = Printf.sprintf "# %s\n\nThis is an idea proposed in %d%s, and %s.%s\n\n%s"
    (Idea.title i) (Idea.year i) (level_to_long_string (Idea.level i))
    (status_to_long_string studs (Idea.status i)) (sups_for i) (Idea.body i)
  in
  El.div ~at:[At.class' "mb-4"] [El.unsafe_raw (fst (Arod.Md.to_html ~ctx r))]

(** Ideas grouped by project with status filter. *)
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
  let project_sections = List.filter_map (fun proj ->
    let proj_slug = proj.Bushel.Project.slug in
    match Hashtbl.find_opt ideas_by_project proj_slug with
    | None -> None
    | Some ideas ->
      let idea_items = List.map (fun i ->
        El.li ~at:[At.v "data-status" (Idea.status_to_string (Idea.status i));
                   At.class' "mb-2"] [
          to_html_no_sidenotes ~ctx i]
      ) ideas in
      let thumbnail_md =
        Printf.sprintf "![%%lc](:project-%s \"%s\")"
          proj_slug proj.Bushel.Project.title
      in
      let thumbnail_html = El.unsafe_raw (fst (Arod.Md.to_html ~ctx thumbnail_md)) in
      let body_html, _wc = truncated_body ~ctx (`Project proj) in
      Some (El.div ~at:[At.class' "mb-8"] [
        El.h2 ~at:[At.class' "text-xl font-semibold mb-2"] [
          El.a ~at:[At.href ("/projects/" ^ proj_slug)] [
            El.txt proj.Bushel.Project.title]];
        thumbnail_html;
        El.p ~at:[At.class' "mb-4"] [body_html];
        El.ul ~at:[At.class' "ml-4"] idea_items])
  ) all_projects in
  let status_filter =
    let checkbox ~id ~label_text ~checked:is_checked ~status_name ~color =
      El.label ~at:[At.class' "flex items-center gap-2 mb-1"] [
        El.input ~at:([At.type' "checkbox"; At.id id;
          At.v "data-status" status_name]
          @ (if is_checked then [At.checked] else [])) ();
        El.span ~at:[At.class' "font-medium"; At.style ("color:" ^ color)] [El.txt label_text]]
    in
    El.aside ~at:[At.class' "mb-8"] [
      El.h3 ~at:[At.class' "text-lg font-semibold mb-2"] [El.txt "Filter by status:"];
      checkbox ~id:"filter-available" ~label_text:"Available"
        ~checked:true ~status_name:"Available" ~color:"#22c55e";
      checkbox ~id:"filter-discussion" ~label_text:"Discussion"
        ~checked:true ~status_name:"Discussion" ~color:"#3b82f6";
      checkbox ~id:"filter-ongoing" ~label_text:"Ongoing"
        ~checked:true ~status_name:"Ongoing" ~color:"#f59e0b";
      checkbox ~id:"filter-completed" ~label_text:"Completed"
        ~checked:true ~status_name:"Completed" ~color:"#6b7280";
      checkbox ~id:"filter-expired" ~label_text:"Expired"
        ~checked:false ~status_name:"Expired" ~color:"#ef4444"]
  in
  let intro = El.p ~at:[At.class' "mb-6"] [
    El.txt "These are research ideas for students at various levels \
         (Part II, MPhil, PhD, and postdoctoral). Browse through the ideas \
         below to find projects that interest you. You're also welcome to \
         propose your own research ideas that align with our ongoing projects."]
  in
  El.div [
    El.h1 ~at:[At.class' "text-2xl font-semibold mb-4"] [El.txt "Research Ideas"];
    intro;
    status_filter;
    El.div project_sections]

(** Idea for feeds. *)
let for_feed ~ctx i =
  let studs = map_and (Printf.sprintf "[@%s]") (Idea.student_handles i) in
  let r = Printf.sprintf "This is an idea proposed %s, and %s.%s"
    (level_to_long_string (Idea.level i))
    (status_to_long_string studs (Idea.status i)) (sups_for i)
  in
  let body_html, word_count_info = truncated_body ~ctx (`Idea i) in
  (El.div [El.unsafe_raw (fst (Arod.Md.to_html ~ctx r)); body_html], word_count_info)

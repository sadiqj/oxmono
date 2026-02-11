(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Links page component.

    Shows all outbound external links ordered by date (newest first),
    with enriched display: GitHub shortnames, arxiv IDs, contact
    associations, karakeep titles, and favicons. Paginated via
    infinite scrolling. *)

open Htmlit

module Entry = Bushel.Entry
module Contact = Sortal_schema.Contact
module I = Arod.Icons

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

let take n l =
  let rec aux i acc = function
    | [] -> List.rev acc
    | _ when i >= n -> List.rev acc
    | x :: xs -> aux (i + 1) (x :: acc) xs
  in
  aux 0 [] l

(** Format a URL as "domain /path" with truncated path. *)
let domain_and_path url =
  let u = Uri.of_string url in
  let domain = match Uri.host u with Some h -> h | None -> "" in
  let path = match Uri.path u with "" | "/" -> "" | p -> p in
  let path =
    if String.length path > 50 then String.sub path 0 50 ^ "\xe2\x80\xa6"
    else path
  in
  (domain, path)

(** {1 URL Classification} *)

type link_display = {
  label : string;
  secondary : string option;
  kind : string;
  favicon : string option;
  contact : Contact.t option;
  contact_url : string option;
}

(** Extract path segments from a URL. *)
let path_segments url =
  let u = Uri.of_string url in
  match Uri.path u with
  | "" | "/" -> []
  | path ->
    String.split_on_char '/' path
    |> List.filter (fun s -> s <> "")

(** Try to extract an RFC number from a URL path. *)
let extract_rfc_number url =
  let segs = path_segments url in
  let rec find = function
    | [] -> None
    | seg :: rest ->
      let s = String.lowercase_ascii seg in
      if String.length s > 3 && String.sub s 0 3 = "rfc" then
        let num = String.sub s 3 (String.length s - 3) in
        if String.length num > 0 && num.[0] >= '0' && num.[0] <= '9' then
          Some num
        else find rest
      else find rest
  in
  find segs

(** Shared platforms that should not be contact-matched. *)
let shared_platforms = [
  "github.com"; "gitlab.com"; "bitbucket.org";
  "twitter.com"; "x.com"; "bsky.app"; "bsky.social";
  "mastodon.social"; "mastodon.online"; "hachyderm.io";
  "linkedin.com"; "youtube.com"; "youtu.be";
  "arxiv.org"; "doi.org"; "orcid.org";
  "reddit.com"; "news.ycombinator.com";
  "medium.com"; "substack.com"; "wordpress.com";
  "en.wikipedia.org"; "wikipedia.org";
  "scholar.google.com"; "google.com";
  "stackoverflow.com"; "stackexchange.com";
  "researchgate.net"; "academia.edu";
  "amazon.com"; "goodreads.com";
]

let strip_www h =
  if String.length h > 4 && String.sub h 0 4 = "www."
  then String.sub h 4 (String.length h - 4) else h

(** Build a domain-to-contact hashtable, excluding shared platforms. *)
let build_contact_by_domain contacts =
  let tbl = Hashtbl.create 64 in
  let is_shared h = List.mem h shared_platforms in
  List.iter (fun c ->
    List.iter (fun (u : Contact.url_entry) ->
      match Uri.host (Uri.of_string u.url) with
      | Some h ->
        let bare = strip_www (String.lowercase_ascii h) in
        if not (is_shared bare) then Hashtbl.replace tbl bare c
      | None -> ()
    ) (Contact.urls c);
    List.iter (fun (s : Contact.service) ->
      match Uri.host (Uri.of_string s.url) with
      | Some h ->
        let bare = strip_www (String.lowercase_ascii h) in
        if not (is_shared bare) then Hashtbl.replace tbl bare c
      | None -> ()
    ) (Contact.current_services c)
  ) contacts;
  tbl

(** Classify a URL into a structured display. *)
let classify_url ~contact_by_domain ~ctx url =
  let u = Uri.of_string url in
  let host = match Uri.host u with Some h -> h | None -> "" in
  let host_lc = String.lowercase_ascii host in
  let bare_host = strip_www host_lc in
  (* Get favicon from links.yml if available *)
  let favicon = match Arod.Ctx.link_for_url ctx url with
    | Some l ->
      let meta = match l.karakeep with Some k -> k.metadata | None -> [] in
      (match List.assoc_opt "favicon" meta with
       | Some f when f <> "" -> Some f
       | _ -> None)
    | None -> None
  in
  (* Get title from links.yml *)
  let karakeep_title = match Arod.Ctx.link_for_url ctx url with
    | Some l ->
      let meta = match l.karakeep with Some k -> k.metadata | None -> [] in
      (match List.assoc_opt "title" meta with
       | Some t when t <> "" -> Some t
       | _ -> None)
    | None -> None
  in
  let segs = path_segments url in
  let mk ?secondary kind label =
    { label; secondary; kind; favicon; contact = None; contact_url = None }
  in
  (* 1. Contact match *)
  match Hashtbl.find_opt contact_by_domain bare_host with
  | Some contact ->
    let name = Contact.name contact in
    let label = match karakeep_title with
      | Some t -> t
      | None -> name
    in
    { label; secondary = None; kind = "contact"; favicon;
      contact = Some contact;
      contact_url = Contact.best_url contact }
  | None ->
  (* 2. GitHub — intelligent URL breakdown *)
  if bare_host = "github.com" then begin
    match segs with
    | user :: repo :: "issues" :: num :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" (Printf.sprintf "Issue #%s" num)
    | user :: repo :: "pull" :: num :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" (Printf.sprintf "PR #%s" num)
    | user :: repo :: "releases" :: "tag" :: tag :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" tag
    | user :: repo :: "tree" :: branch :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" branch
    | user :: repo :: "blob" :: _branch :: rest ->
      let file = match rest with
        | [] -> ""
        | parts -> List.nth parts (List.length parts - 1)
      in
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" (if file <> "" then file else repo)
    | user :: repo :: "wiki" :: page :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" (Printf.sprintf "Wiki: %s" page)
    | user :: repo :: "actions" :: _ ->
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" "Actions"
    | user :: repo :: "commit" :: sha :: _ ->
      let short_sha = if String.length sha > 7 then String.sub sha 0 7 else sha in
      mk ~secondary:(Printf.sprintf "%s/%s" user repo)
        "github" short_sha
    | user :: repo :: _ ->
      mk "github" (Printf.sprintf "%s/%s" user repo)
    | [user] -> mk "github" user
    | [] -> mk "github" "github.com"
  end
  (* 3. ArXiv *)
  else if bare_host = "arxiv.org" then begin
    let label, secondary = match segs with
      | ("abs" | "pdf") :: id :: _ ->
        ("arXiv:" ^ id, karakeep_title)
      | _ -> ("arxiv.org", None)
    in
    mk ?secondary "arxiv" label
  end
  (* 4. DOI *)
  else if bare_host = "doi.org" then begin
    let path = Uri.path u in
    let id =
      if String.length path > 1 then String.sub path 1 (String.length path - 1)
      else ""
    in
    let label = if id <> "" then "doi:" ^ id else "doi.org" in
    mk ?secondary:karakeep_title "doi" label
  end
  (* 5. IETF / RFC *)
  else if bare_host = "datatracker.ietf.org" || bare_host = "rfc-editor.org"
          || bare_host = "www.rfc-editor.org" then begin
    let label = match extract_rfc_number url with
      | Some n -> "RFC " ^ n
      | None -> host
    in
    mk ?secondary:karakeep_title "rfc" label
  end
  (* 6. Title from links.yml *)
  else match karakeep_title with
  | Some title ->
    mk "web" title
  (* 7. Fallback *)
  | None ->
    let (domain, path) = domain_and_path url in
    let label = if path = "" then domain else domain ^ " " ^ path in
    mk "web" label

(** {1 Kind Badge} *)

let kind_badge ~entries display =
  match display.kind with
  | "github" ->
    El.span ~at:[At.class' "link-kind-badge link-kind-github";
                 At.v "title" "GitHub"]
      [El.unsafe_raw (I.brand ~cl:"" ~size:12 I.github_brand)]
  | "arxiv" ->
    El.span ~at:[At.class' "link-kind-badge link-kind-arxiv";
                 At.v "title" "arXiv"]
      [El.unsafe_raw (I.brand ~cl:"" ~size:12 I.arxiv_brand)]
  | "doi" ->
    El.span ~at:[At.class' "link-kind-badge link-kind-doi";
                 At.v "title" "DOI"]
      [El.unsafe_raw (I.brand ~cl:"" ~size:12 I.doi_brand)]
  | "rfc" ->
    El.span ~at:[At.class' "link-kind-badge link-kind-rfc";
                 At.v "title" "RFC"]
      [El.unsafe_raw (I.outline ~cl:"" ~size:12 I.file_certificate_o)]
  | "contact" ->
    let thumb = match display.contact with
      | Some c -> Entry.contact_thumbnail entries c
      | None -> None
    in
    (match thumb with
     | Some src ->
       El.img ~at:[At.src src;
                   At.class' "link-contact-thumb";
                   At.v "width" "14"; At.v "height" "14";
                   At.v "loading" "lazy";
                   At.v "alt" ""] ()
     | None ->
       match display.favicon with
       | Some favicon_url ->
         El.img ~at:[At.src favicon_url;
                     At.class' "link-favicon";
                     At.v "width" "14"; At.v "height" "14";
                     At.v "loading" "lazy";
                     At.v "alt" ""] ()
       | None ->
         El.span ~at:[At.class' "link-kind-badge link-kind-contact";
                      At.v "title" "Contact"]
           [El.unsafe_raw (I.outline ~cl:"" ~size:12 I.user_o)])
  | _ ->
    match display.favicon with
    | Some favicon_url ->
      El.img ~at:[At.src favicon_url;
                  At.class' "link-favicon";
                  At.v "width" "14"; At.v "height" "14";
                  At.v "loading" "lazy";
                  At.v "alt" ""] ()
    | None -> El.span ~at:[At.class' "link-kind-badge"] [El.txt "\xc2\xb7"]

(** {1 Group Computation} *)

type link_group = {
  ent : Entry.entry;
  links : Bushel.Link_graph.external_link list;
}

(** Compute all link groups sorted by entry date descending. *)
let compute_groups ~ctx =
  let entries = Arod.Ctx.entries ctx in
  let all_links = Bushel.Link_graph.all_external_links () in
  let by_source : (string, Bushel.Link_graph.external_link list) Hashtbl.t =
    Hashtbl.create 128 in
  List.iter (fun (link : Bushel.Link_graph.external_link) ->
    let cur = try Hashtbl.find by_source link.source with Not_found -> [] in
    if List.exists (fun (l : Bushel.Link_graph.external_link) -> l.url = link.url) cur then ()
    else Hashtbl.replace by_source link.source (link :: cur)
  ) all_links;
  let groups = Hashtbl.fold (fun slug links acc ->
    match Entry.lookup entries slug with
    | Some ent -> { ent; links } :: acc
    | None -> acc
  ) by_source [] in
  List.sort (fun a b ->
    compare (Entry.date b.ent) (Entry.date a.ent)
  ) groups

(** {1 Group Rendering} *)

(** Render a single link group with a data-month-id for scroll tracking. *)
let render_group ~contact_by_domain ~entries ~ctx group =
  let (y, m, d) = Entry.date group.ent in
  let date_str = Printf.sprintf "%s %d" (month_name m) y in
  let month_id = Printf.sprintf "%04d-%02d" y m in
  let day_str = string_of_int d in
  let type_icon = Sidebar.entry_type_icon ~size:12 group.ent in
  let header =
    El.div ~at:[At.class' "link-group-header"] [
      El.unsafe_raw type_icon;
      El.a ~at:[At.href (Entry.site_url group.ent);
                At.class' "link-group-title no-underline"]
        [El.txt (Entry.title group.ent)];
      El.span ~at:[At.class' "note-compact-meta"] [El.txt date_str]]
  in
  let link_rows = List.map (fun (link : Bushel.Link_graph.external_link) ->
    let display = classify_url ~contact_by_domain ~ctx link.url in
    let badge = kind_badge ~entries display in
    let label_children =
      let primary = El.txt display.label in
      match display.secondary with
      | Some sec ->
        [primary;
         El.span ~at:[At.class' "link-label-secondary"]
           [El.txt (" " ^ sec)]]
      | None -> [primary]
    in
    let label_el = match display.contact, display.contact_url with
      | Some _, Some curl ->
        El.a ~at:[At.href curl;
                  At.class' "link-label no-underline"]
          label_children
      | _ ->
        El.a ~at:[At.href link.url;
                  At.class' "link-label no-underline";
                  At.v "rel" "noopener"]
          label_children
    in
    let show_hint = display.kind <> "web" || display.favicon <> None in
    let domain_hint =
      if show_hint then
        El.span ~at:[At.class' "link-domain-hint"]
          [El.txt link.domain]
      else El.void
    in
    El.div ~at:[At.class' "link-row"] [badge; label_el; domain_hint]
  ) group.links in
  El.div ~at:[At.class' "link-group";
              At.v "data-month-id" month_id;
              At.v "data-day" day_str]
    (header :: link_rows)

(** Render a slice of link groups as an HTML string for the pagination API. *)
let render_groups_html ~ctx groups =
  let contacts = Arod.Ctx.contacts ctx in
  let entries = Arod.Ctx.entries ctx in
  let contact_by_domain = build_contact_by_domain contacts in
  let els = List.map (render_group ~contact_by_domain ~entries ~ctx) groups in
  El.to_string ~doctype:false (El.div els)

(** Return all computed groups for use by the pagination API. *)
let all_groups ~ctx = compute_groups ~ctx

(** {1 Links List Page} *)

let page_size = 25

let links_list ~ctx =
  let groups = compute_groups ~ctx in
  let entries = Arod.Ctx.entries ctx in
  let contacts = Arod.Ctx.contacts ctx in
  let contact_by_domain = build_contact_by_domain contacts in

  (* Domain stats for sidebar (computed over all groups) *)
  let url_set = Hashtbl.create 256 in
  let domain_tbl : (string, int) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun group ->
    List.iter (fun (link : Bushel.Link_graph.external_link) ->
      if not (Hashtbl.mem url_set link.url) then begin
        Hashtbl.add url_set link.url ();
        let cur = try Hashtbl.find domain_tbl link.domain with Not_found -> 0 in
        Hashtbl.replace domain_tbl link.domain (cur + 1)
      end
    ) group.links
  ) groups;
  let domain_counts = Hashtbl.fold (fun d c acc -> (d, c) :: acc) domain_tbl [] in
  let domain_counts = List.sort (fun (_, a) (_, b) -> compare b a) domain_counts in

  let total_urls = Hashtbl.length url_set in
  let total_domains = List.length domain_counts in
  let total_groups = List.length groups in

  (* Build calendar data: { "YYYY-MM": [link_count_day1, ...], ... } *)
  let month_links : (string, int list) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun group ->
    let (y, m, d) = Entry.date group.ent in
    let key = Printf.sprintf "%04d-%02d" y m in
    let cur = try Hashtbl.find month_links key with Not_found -> [] in
    Hashtbl.replace month_links key (d :: cur)
  ) groups;
  let calendar_months =
    Hashtbl.fold (fun k _ acc -> k :: acc) month_links []
    |> List.sort (fun a b -> compare b a)
  in
  let calendar_json =
    let entries = List.map (fun key ->
      let days = Hashtbl.find month_links key in
      let days = List.sort_uniq compare days in
      let day_strs = List.map string_of_int days in
      Printf.sprintf {|"%s":[%s]|} key (String.concat "," day_strs)
    ) calendar_months in
    "{" ^ String.concat "," entries ^ "}"
  in
  let first_month = match calendar_months with
    | m :: _ -> m | [] -> ""
  in

  (* Render only first page of groups *)
  let visible_groups =
    if List.length groups > page_size then take page_size groups
    else groups
  in
  let group_els = List.map (render_group ~contact_by_domain ~entries ~ctx) visible_groups in

  let article =
    El.div ~at:[
      At.v "data-pagination" "true";
      At.v "data-collection-type" "links";
      At.v "data-total-count" (string_of_int total_groups);
      At.v "data-current-count" (string_of_int (List.length visible_groups));
      At.v "data-types" ""] [
      El.h1 ~at:[At.class' "page-title"] [El.txt "Links"];
      El.p ~at:[At.class' "text-secondary text-sm mb-4"]
        [El.txt (Printf.sprintf "%d links across %d domains." total_urls total_domains)];
      El.div ~at:[At.class' "link-list"] group_els]
  in

  (* Sidebar *)
  let calendar_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3";
                At.id "links-calendar";
                At.v "data-calendar-months" calendar_json;
                At.v "data-current-month" first_month] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt (Printf.sprintf " %d links \xC2\xB7 %d domains"
          total_urls total_domains)];
      El.div ~at:[At.class' "sidebar-meta-body notes-calendar"] [
        El.div ~at:[At.class' "cal-header"] [];
        El.div ~at:[At.class' "heatmap-strip"] [];
        El.div ~at:[At.class' "cal-divider"] [];
        El.div ~at:[At.class' "cal-grid"] []]]
  in
  let top_domains =
    let top = List.filteri (fun i _ -> i < 20) domain_counts in
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " top domains"];
      El.div ~at:[At.class' "sidebar-meta-body"]
        (List.map (fun (domain, count) ->
          El.p ~at:[At.class' "sidebar-meta-line"] [
            El.txt domain;
            El.span ~at:[At.class' "text-muted ml-auto"]
              [El.txt (string_of_int count)]]
        ) top)]
  in
  let sidebar =
    El.aside ~at:[At.class' "hidden lg:block lg:w-72 shrink-0"]
      [El.div ~at:[At.class' "sticky top-20"] [calendar_box; top_domains]]
  in
  (article, sidebar)

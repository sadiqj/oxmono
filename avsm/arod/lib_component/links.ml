(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Links page component.

    Shows all outbound external links ordered by date (newest first),
    each displaying the domain, a shortened path, the source entry
    backlink, and the date. *)

open Htmlit

module Entry = Bushel.Entry
module I = Arod.Icons

(** {1 Helpers} *)

let month_name = function
  | 1 -> "Jan" | 2 -> "Feb" | 3 -> "Mar" | 4 -> "Apr"
  | 5 -> "May" | 6 -> "Jun" | 7 -> "Jul" | 8 -> "Aug"
  | 9 -> "Sep" | 10 -> "Oct" | 11 -> "Nov" | 12 -> "Dec"
  | _ -> ""

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

(** {1 Links List Page} *)

let links_list ~ctx =
  let entries = Arod.Ctx.entries ctx in
  let all_links = Bushel.Link_graph.all_external_links () in

  (* Group links by source slug *)
  let by_source : (string, Bushel.Link_graph.external_link list) Hashtbl.t =
    Hashtbl.create 128 in
  List.iter (fun (link : Bushel.Link_graph.external_link) ->
    let cur = try Hashtbl.find by_source link.source with Not_found -> [] in
    if List.exists (fun (l : Bushel.Link_graph.external_link) -> l.url = link.url) cur then ()
    else Hashtbl.replace by_source link.source (link :: cur)
  ) all_links;

  (* Build (entry, links) pairs, sorted by entry date descending *)
  let groups = Hashtbl.fold (fun slug links acc ->
    match Entry.lookup entries slug with
    | Some ent -> (ent, links) :: acc
    | None -> acc
  ) by_source [] in
  let groups = List.sort (fun (a, _) (b, _) ->
    compare (Entry.date b) (Entry.date a)
  ) groups in

  (* Domain stats for sidebar *)
  let url_set = Hashtbl.create 256 in
  let domain_tbl : (string, int) Hashtbl.t = Hashtbl.create 64 in
  List.iter (fun (_, links) ->
    List.iter (fun (link : Bushel.Link_graph.external_link) ->
      if not (Hashtbl.mem url_set link.url) then begin
        Hashtbl.add url_set link.url ();
        let cur = try Hashtbl.find domain_tbl link.domain with Not_found -> 0 in
        Hashtbl.replace domain_tbl link.domain (cur + 1)
      end
    ) links
  ) groups;
  let domain_counts = Hashtbl.fold (fun d c acc -> (d, c) :: acc) domain_tbl [] in
  let domain_counts = List.sort (fun (_, a) (_, b) -> compare b a) domain_counts in

  let total_urls = Hashtbl.length url_set in
  let total_domains = List.length domain_counts in

  (* Render groups *)
  let group_els = List.map (fun (ent, links) ->
    let (y, m, _d) = Entry.date ent in
    let date_str = Printf.sprintf "%s %d" (month_name m) y in
    let type_icon = Sidebar.entry_type_icon ~size:12 ent in
    let header =
      El.div ~at:[At.class' "link-group-header"] [
        El.unsafe_raw type_icon;
        El.a ~at:[At.href (Entry.site_url ent);
                  At.class' "link-group-title no-underline"]
          [El.txt (Entry.title ent)];
        El.span ~at:[At.class' "note-compact-meta"] [El.txt date_str]]
    in
    let link_rows = List.map (fun (link : Bushel.Link_graph.external_link) ->
      let (domain, path) = domain_and_path link.url in
      El.div ~at:[At.class' "link-row"] [
        El.a ~at:[At.href link.url;
                  At.class' "link-url no-underline";
                  At.v "rel" "noopener"]
          [El.span ~at:[At.class' "link-url-domain"] [El.txt domain];
           El.span ~at:[At.class' "link-url-path"] [El.txt path]]]
    ) links in
    El.div ~at:[At.class' "link-group"]
      (header :: link_rows)
  ) groups in

  let article =
    El.div ~at:[] [
      El.h1 ~at:[At.class' "page-title"] [El.txt "Links"];
      El.p ~at:[At.class' "text-secondary text-sm mb-4"]
        [El.txt (Printf.sprintf "%d links across %d domains." total_urls total_domains)];
      El.div ~at:[At.class' "link-list"] group_els]
  in

  (* Sidebar *)
  let stats_box =
    El.div ~at:[At.class' "sidebar-meta-box mb-3"] [
      El.div ~at:[At.class' "sidebar-meta-header"] [
        El.span ~at:[At.class' "sidebar-meta-prompt"] [El.txt ">_"];
        El.txt " links"];
      El.div ~at:[At.class' "sidebar-meta-body"] [
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.link_o)
          (El.txt (Printf.sprintf "%d links" total_urls));
        Sidebar.meta_line
          ~icon:(I.outline ~cl:"opacity-50" ~size:12 I.world_o)
          (El.txt (Printf.sprintf "%d domains" total_domains))]]
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
      [El.div ~at:[At.class' "sticky top-20"] [stats_box; top_domains]]
  in
  (article, sidebar)

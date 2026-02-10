(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

open Karakeep

let print_bookmark bookmark =
  let title = bookmark_title bookmark in
  let url =
    match bookmark.content with
    | Link lc -> lc.url
    | Text tc -> Option.value tc.source_url ~default:"(text content)"
    | Asset ac -> Option.value ac.source_url ~default:"(asset content)"
    | Unknown -> "(unknown content)"
  in
  let tags_str =
    String.concat ", "
      (List.map (fun (tag : bookmark_tag) -> tag.name) bookmark.tags)
  in
  Printf.printf "- %s\n  URL: %s\n  Created: %s\n  Tags: %s\n---\n\n" title url
    (Ptime.to_rfc3339 bookmark.created_at)
    tags_str

let () =
  (* Suppress verbose TLS/HTTP logging *)
  Requests.Cmd.setup_log_sources (Some Logs.Warning);

  (* Load API key from file *)
  let api_key =
    try
      let ic = open_in ".karakeep-api" in
      let key = input_line ic in
      close_in ic;
      String.trim key
    with _ ->
      Printf.eprintf "Error: Could not load API key from .karakeep-api file\n";
      exit 1
  in

  (* Test configuration *)
  let base_url = "https://hoard.recoil.org" in

  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->

  let client = Karakeep.create ~sw ~env ~base_url ~api_key in

  (* Test 1: fetch_bookmarks - get a single page with pagination info *)
  Printf.printf "=== Test 1: fetch_bookmarks (paginated) ===\n";
  (try
     let response = fetch_bookmarks client ~limit:3 () in
     Printf.printf "Found bookmarks, showing %d (page 1)\n"
       (List.length response.bookmarks);
     Printf.printf "Next cursor: %s\n\n"
       (match response.next_cursor with Some c -> c | None -> "none");
     List.iter print_bookmark response.bookmarks;

     (* Test 2: fetch_all_bookmarks - get multiple pages automatically *)
     Printf.printf "=== Test 2: fetch_all_bookmarks (with limit) ===\n";
     let all_bookmarks = fetch_all_bookmarks client ~page_size:2 ~max_pages:2 () in
     Printf.printf "Fetched %d bookmarks from up to 2 pages\n\n"
       (List.length all_bookmarks);

     List.iter print_bookmark
       (List.fold_left
          (fun acc x -> if List.length acc < 4 then acc @ [ x ] else acc)
          [] all_bookmarks);
     Printf.printf "... and %d more bookmarks\n\n"
       (max 0 (List.length all_bookmarks - 4));

     (* Test 3: fetch_bookmark_details - get a specific bookmark *)
     (match response.bookmarks with
      | first_bookmark :: _ ->
          Printf.printf "=== Test 3: fetch_bookmark_details ===\n";
          Printf.printf "Fetching details for bookmark ID: %s\n\n"
            first_bookmark.id;

          (try
             let bookmark = fetch_bookmark_details client first_bookmark.id in
             print_bookmark bookmark
           with e ->
             Printf.printf "Error fetching bookmark details: %s\n" (Printexc.to_string e))
      | [] ->
          Printf.printf "No bookmarks found to test fetch_bookmark_details\n")
   with e ->
     Printf.printf "Error in basic tests: %s\n" (Printexc.to_string e);
     Printf.printf "Skipping remaining tests due to API error.\n")

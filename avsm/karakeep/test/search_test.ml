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

  Printf.printf "=== Test: search_bookmarks ===\n";

  (* Use a reliable search term that should return results *)
  let search_term = "ocaml" in

  Printf.printf "Searching for bookmarks with query: \"%s\"\n\n" search_term;

  (try
     (* Search for bookmarks with the search term *)
     let search_results = search_bookmarks client ~query:search_term ~limit:3 () in

     Printf.printf "Found %d matching bookmarks\n" (List.length search_results.bookmarks);
     Printf.printf "Next cursor: %s\n\n"
       (match search_results.next_cursor with Some c -> c | None -> "none");

     (* Display the search results *)
     List.iter print_bookmark search_results.bookmarks;

     (* Test pagination if we have a next page *)
     (match search_results.next_cursor with
      | Some cursor ->
          Printf.printf "=== Testing search pagination ===\n";
          Printf.printf "Fetching next page with cursor: %s\n\n" cursor;

          let next_page = search_bookmarks client ~query:search_term ~limit:3 ~cursor () in

          Printf.printf "Found %d more bookmarks on next page\n\n"
            (List.length next_page.bookmarks);

          List.iter print_bookmark next_page.bookmarks
      | None ->
          Printf.printf "No more pages available for this search query.\n")
   with e ->
     Printf.printf "An error occurred while searching: %s\n" (Printexc.to_string e);
     Printf.printf "\nFalling back to testing with a simple search term: \"ocaml\"\n\n";

     try
       (* Try again with a simple, reliable search term *)
       let search_results = search_bookmarks client ~query:"ocaml" ~limit:3 () in

       Printf.printf "Found %d matching bookmarks\n" (List.length search_results.bookmarks);
       Printf.printf "Next cursor: %s\n\n"
         (match search_results.next_cursor with Some c -> c | None -> "none");

       (* Display the search results *)
       List.iter print_bookmark search_results.bookmarks
     with e ->
       Printf.printf "Fallback search also failed: %s\n" (Printexc.to_string e))

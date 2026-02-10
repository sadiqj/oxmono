(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

open Karakeep

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

  (* Test creating a new bookmark *)
  Printf.printf "Creating a new bookmark...\n";

  let url = "https://ocaml.org" in
  let title = "OCaml Programming Language" in
  let tags = [ "programming"; "ocaml"; "functional" ] in

  (try
     let bookmark = create_bookmark client ~url ~title ~tags () in
     Printf.printf "Successfully created bookmark:\n";
     Printf.printf "- ID: %s\n" bookmark.id;
     Printf.printf "- Title: %s\n" (bookmark_title bookmark);

     let url =
       match bookmark.content with
       | Link lc -> lc.url
       | Text tc -> Option.value tc.source_url ~default:"(text content)"
       | Asset ac -> Option.value ac.source_url ~default:"(asset content)"
       | Unknown -> "(unknown content)"
     in
     Printf.printf "- URL: %s\n" url;
     Printf.printf "- Created: %s\n" (Ptime.to_rfc3339 bookmark.created_at);
     Printf.printf "- Tags: %s\n"
       (String.concat ", "
          (List.map (fun (tag : bookmark_tag) -> tag.name) bookmark.tags))
   with e ->
     Printf.printf "Error creating bookmark: %s\n" (Printexc.to_string e);
     Printf.printf "Skipping the creation test due to API error.\n")

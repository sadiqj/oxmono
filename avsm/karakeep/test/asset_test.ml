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

  (* Test asset URL and optionally fetch asset *)
  Printf.printf "Fetching bookmarks with assets...\n";

  (try
     let response = fetch_bookmarks client ~limit:5 () in
     (* Find a bookmark with assets *)
     let bookmark_with_assets =
       List.find_opt (fun b -> List.length b.assets > 0) response.bookmarks
     in

     match bookmark_with_assets with
     | None ->
         Printf.printf "No bookmarks with assets found in the first 5 results.\n"
     | Some bookmark -> (
         (* Print assets info *)
         let bookmark_title_str = bookmark_title bookmark in
         let url =
           match bookmark.content with
           | Link lc -> lc.url
           | Text tc -> Option.value tc.source_url ~default:"(text content)"
           | Asset ac -> Option.value ac.source_url ~default:"(asset content)"
           | Unknown -> "(unknown content)"
         in
         Printf.printf "Found bookmark \"%s\" with %d assets: %s\n"
           bookmark_title_str
           (List.length bookmark.assets)
           url;

         List.iter
           (fun (asset : asset) ->
             let asset_type_str =
               match asset.asset_type with
               | Screenshot -> "screenshot"
               | AssetScreenshot -> "assetScreenshot"
               | BannerImage -> "bannerImage"
               | FullPageArchive -> "fullPageArchive"
               | Video -> "video"
               | BookmarkAsset -> "bookmarkAsset"
               | PrecrawledArchive -> "precrawledArchive"
               | Unknown -> "unknown"
             in
             Printf.printf "- Asset ID: %s, Type: %s\n" asset.id asset_type_str;

             (* Get asset URL *)
             let asset_url = get_asset_url client asset.id in
             Printf.printf "  URL: %s\n" asset_url)
           bookmark.assets;

         (* Optionally fetch one asset to verify it works *)
         match bookmark.assets with
         | asset :: _ -> (
             Printf.printf "\nFetching asset %s...\n" asset.id;
             try
               let data = fetch_asset client asset.id in
               Printf.printf "Successfully fetched asset. Size: %d bytes\n"
                 (String.length data)
             with e ->
               Printf.printf "Error fetching asset: %s\n" (Printexc.to_string e))
         | [] -> ())
   with e ->
     Printf.printf "Error in asset test: %s\n" (Printexc.to_string e);
     Printf.printf "Skipping the asset test due to API error.\n")

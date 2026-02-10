(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

open Cmdliner

type config = {
  base_url : string;
  api_key : string;
}

(* Helper to read API key from file *)
let read_api_key_file path =
  try
    let ic = open_in path in
    let key = input_line ic in
    close_in ic;
    String.trim key
  with _ -> ""

(* Profile term - shared with karakeep_auth_cmd *)
let profile_term = Karakeep_auth_cmd.profile_term

(* Base URL term - only used as override *)
let base_url_opt_term =
  let doc = "Base URL of the Karakeep instance (overrides profile)." in
  let env = Cmd.Env.info "KARAKEEP_BASE_URL" ~doc in
  Arg.(
    value
    & opt (some string) None
    & info [ "base-url"; "u" ] ~docv:"URL" ~doc ~env)

(* API key file term - legacy support *)
let api_key_file_term =
  let doc = "File containing the API key (legacy, use 'auth login' instead)." in
  Arg.(
    value
    & opt string ".karakeep-api"
    & info [ "api-key-file" ] ~docv:"FILE" ~doc)

(* API key direct term *)
let api_key_direct_term =
  let doc = "API key for authentication (overrides profile)." in
  let env = Cmd.Env.info "KARAKEEP_API_KEY" ~doc in
  Arg.(value & opt (some string) None & info [ "api-key"; "k" ] ~docv:"KEY" ~doc ~env)

(* Config options from CLI - not yet resolved *)
type config_opt = {
  api_key_direct : string option;
  base_url_opt : string option;
  profile : string option;
  api_key_file : string;
}

let config_opt_term =
  let make api_key_direct base_url_opt profile api_key_file =
    { api_key_direct; base_url_opt; profile; api_key_file }
  in
  Term.(const make $ api_key_direct_term $ base_url_opt_term $ profile_term $ api_key_file_term)

(* Resolve config with Eio filesystem *)
let resolve_config ~fs (opt : config_opt) : config =
  (* Priority:
     1. --api-key flag (if provided)
     2. KARAKEEP_API_KEY env var
     3. XDG profile credentials
     4. Legacy .karakeep-api file *)
  let api_key, base_url =
    match opt.api_key_direct with
    | Some key ->
        (* Direct API key provided, use default or env base URL *)
        let url = match opt.base_url_opt with
          | Some u -> u
          | None -> Karakeep_config.default_base_url
        in
        (key, url)
    | None ->
        (* Check environment variable *)
        let env_key = try Sys.getenv "KARAKEEP_API_KEY" with Not_found -> "" in
        if env_key <> "" then begin
          let url = match opt.base_url_opt with
            | Some u -> u
            | None -> try Sys.getenv "KARAKEEP_BASE_URL"
                      with Not_found -> Karakeep_config.default_base_url
          in
          (env_key, url)
        end else begin
          (* Try XDG profile credentials *)
          let profile_name = match opt.profile with
            | Some p -> p
            | None -> Karakeep_config.get_current_profile fs
          in
          match Karakeep_config.load_credentials fs ~profile:profile_name () with
          | Some creds ->
              (* Apply base_url override if provided *)
              let url = match opt.base_url_opt with
                | Some u -> u
                | None -> creds.Karakeep_config.base_url
              in
              (creds.Karakeep_config.api_key, url)
          | None ->
              (* Fall back to legacy .karakeep-api file *)
              let file_key = read_api_key_file opt.api_key_file in
              if file_key <> "" then begin
                let url = match opt.base_url_opt with
                  | Some u -> u
                  | None -> Karakeep_config.default_base_url
                in
                (file_key, url)
              end else
                failwith "No credentials found. Use 'karakeep auth login' or --api-key"
        end
  in
  { base_url; api_key }

(* Pagination terms *)
let limit_term =
  let doc = "Maximum number of items to return." in
  Arg.(value & opt (some int) None & info [ "limit"; "n" ] ~docv:"N" ~doc)

let cursor_term =
  let doc = "Pagination cursor for fetching next page." in
  Arg.(value & opt (some string) None & info [ "cursor"; "c" ] ~docv:"CURSOR" ~doc)

(* Filter terms *)
let archived_term =
  let doc = "Filter for archived items." in
  let archived = (Some true, Arg.info [ "archived" ] ~doc) in
  let not_archived =
    (Some false, Arg.info [ "no-archived" ] ~doc:"Filter for non-archived items.")
  in
  Arg.(value & vflag None [ archived; not_archived ])

let favourited_term =
  let doc = "Filter for favourited items." in
  let fav = (Some true, Arg.info [ "favourited"; "fav" ] ~doc) in
  let not_fav =
    (Some false, Arg.info [ "no-favourited"; "no-fav" ] ~doc:"Filter for non-favourited items.")
  in
  Arg.(value & vflag None [ fav; not_fav ])

let include_content_term =
  let doc = "Include full content in response." in
  let include_it = (true, Arg.info [ "include-content" ] ~doc) in
  let exclude_it = (false, Arg.info [ "no-content" ] ~doc:"Exclude content from response.") in
  Arg.(value & vflag true [ include_it; exclude_it ])

(* Entity ID terms *)
let bookmark_id_term =
  let doc = "Bookmark ID." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"BOOKMARK_ID" ~doc)

let tag_id_term =
  let doc = "Tag ID." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"TAG_ID" ~doc)

let list_id_term =
  let doc = "List ID." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"LIST_ID" ~doc)

let highlight_id_term =
  let doc = "Highlight ID." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"HIGHLIGHT_ID" ~doc)

(* Bookmark terms *)
let url_term =
  let doc = "URL to bookmark." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"URL" ~doc)

let title_term =
  let doc = "Title for the bookmark." in
  Arg.(value & opt (some string) None & info [ "title"; "t" ] ~docv:"TITLE" ~doc)

let note_term =
  let doc = "Note to attach to the bookmark." in
  Arg.(value & opt (some string) None & info [ "note" ] ~docv:"NOTE" ~doc)

let summary_term =
  let doc = "Summary text for the bookmark." in
  Arg.(value & opt (some string) None & info [ "summary" ] ~docv:"TEXT" ~doc)

let tags_term =
  let doc = "Tag to attach (can be repeated)." in
  Arg.(value & opt_all string [] & info [ "tag" ] ~docv:"TAG" ~doc)

(* List terms *)
let name_term =
  let doc = "Name for the list." in
  Arg.(required & opt (some string) None & info [ "name" ] ~docv:"NAME" ~doc)

let name_opt_term =
  let doc = "Name for the list." in
  Arg.(value & opt (some string) None & info [ "name" ] ~docv:"NAME" ~doc)

let icon_term =
  let doc = "Icon for the list (emoji or identifier)." in
  Arg.(required & opt (some string) None & info [ "icon" ] ~docv:"ICON" ~doc)

let icon_opt_term =
  let doc = "Icon for the list (emoji or identifier)." in
  Arg.(value & opt (some string) None & info [ "icon" ] ~docv:"ICON" ~doc)

let description_term =
  let doc = "Description for the list." in
  Arg.(value & opt (some string) None & info [ "description"; "d" ] ~docv:"TEXT" ~doc)

let parent_id_term =
  let doc = "Parent list ID for nesting." in
  Arg.(value & opt (some string) None & info [ "parent-id" ] ~docv:"ID" ~doc)

let query_term =
  let doc = "Query for smart list." in
  Arg.(value & opt (some string) None & info [ "query"; "q" ] ~docv:"QUERY" ~doc)

let search_query_term =
  let doc = "Search query." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"QUERY" ~doc)

(* Highlight terms *)
let color_term =
  let color_conv =
    let parse s =
      match String.lowercase_ascii s with
      | "yellow" -> Ok Karakeep.Yellow
      | "red" -> Ok Karakeep.Red
      | "green" -> Ok Karakeep.Green
      | "blue" -> Ok Karakeep.Blue
      | _ -> Error (`Msg "Invalid color. Use: yellow, red, green, blue")
    in
    let print fmt c =
      let s =
        match c with
        | Karakeep.Yellow -> "yellow"
        | Karakeep.Red -> "red"
        | Karakeep.Green -> "green"
        | Karakeep.Blue -> "blue"
      in
      Format.pp_print_string fmt s
    in
    Arg.conv (parse, print)
  in
  let doc = "Highlight color (yellow, red, green, blue)." in
  Arg.(value & opt (some color_conv) None & info [ "color" ] ~docv:"COLOR" ~doc)

(* Output format *)
type output_format = Text | Json | Quiet

let output_format_term =
  let json = (Json, Arg.info [ "json"; "J" ] ~doc:"Output in JSON format.") in
  let ids_only = (Quiet, Arg.info [ "ids-only" ] ~doc:"Output only IDs (one per line).") in
  Arg.(value & vflag Text [ json; ids_only ])

(* Logging setup *)
let logs_term = Logs_cli.level ()
let fmt_styler_term = Fmt_cli.style_renderer ()

let verbose_http_term =
  let doc = "Enable verbose HTTP-level logging (hexdumps, TLS details)." in
  Arg.(value & flag & info [ "verbose-http" ] ~doc)

let setup_logging =
  let setup style_renderer level verbose_http =
    Fmt_tty.setup_std_outputs ?style_renderer ();
    Logs.set_level level;
    Logs.set_reporter (Logs_fmt.reporter ());
    (* Configure Requests log sources - suppress HTTP noise unless --verbose-http *)
    Requests.Cmd.setup_log_sources ~verbose_http level
  in
  Term.(const setup $ fmt_styler_term $ logs_term $ verbose_http_term)

(* Client helper - takes env and config_opt, resolves and creates client *)
let with_client ~env ~sw config_opt f =
  let config = resolve_config ~fs:env#fs config_opt in
  let client =
    Karakeep.create ~sw ~env ~base_url:config.base_url ~api_key:config.api_key
  in
  f client

(* JSON encoding helpers using jsont *)
let encode_json codec v =
  match Jsont_bytesrw.encode_string codec v with
  | Ok s -> s
  | Error e -> raise (Karakeep.err (Karakeep.Json_error { reason = e }))

let json_of_bookmark b = encode_json Karakeep.bookmark_jsont b
let json_of_tag t = encode_json Karakeep.tag_jsont t
let json_of_list l = encode_json Karakeep.list_jsont l
let json_of_highlight h = encode_json Karakeep.highlight_jsont h
let json_of_user u = encode_json Karakeep.user_info_jsont u
let json_of_stats s = encode_json Karakeep.user_stats_jsont s

(* Output helpers *)

let print_json_array to_json items =
  print_string "[";
  List.iteri (fun i item ->
    if i > 0 then print_string ",";
    print_string (to_json item)) items;
  print_endline "]"

let print_bookmark fmt (b : Karakeep.bookmark) =
  match fmt with
  | Text ->
      let title = Karakeep.bookmark_title b in
      let status =
        (if b.archived then "[A]" else "")
        ^ if b.favourited then "[*]" else ""
      in
      Printf.printf "%s  %s %s\n" b.id title status
  | Json -> print_endline (json_of_bookmark b)
  | Quiet -> print_endline b.id

let print_bookmarks fmt bookmarks =
  match fmt with
  | Json -> print_json_array json_of_bookmark bookmarks
  | _ -> List.iter (print_bookmark fmt) bookmarks

let print_tag fmt (t : Karakeep.tag) =
  match fmt with
  | Text -> Printf.printf "%s  %s (%d)\n" t.id t.name t.num_bookmarks
  | Json -> print_endline (json_of_tag t)
  | Quiet -> print_endline t.id

let print_tags fmt tags =
  match fmt with
  | Json -> print_json_array json_of_tag tags
  | _ -> List.iter (print_tag fmt) tags

let print_list fmt (l : Karakeep._list) =
  match fmt with
  | Text ->
      let type_str =
        match l.list_type with Karakeep.Manual -> "" | Karakeep.Smart -> "[smart]"
      in
      Printf.printf "%s  %s %s %s\n" l.id l.icon l.name type_str
  | Json -> print_endline (json_of_list l)
  | Quiet -> print_endline l.id

let print_lists fmt lists =
  match fmt with
  | Json -> print_json_array json_of_list lists
  | _ -> List.iter (print_list fmt) lists

let print_highlight fmt (h : Karakeep.highlight) =
  match fmt with
  | Text ->
      let text = Option.value ~default:"" h.text in
      let note = Option.value ~default:"" h.note in
      Printf.printf "%s  \"%s\" %s\n" h.id text note
  | Json -> print_endline (json_of_highlight h)
  | Quiet -> print_endline h.id

let print_highlights fmt highlights =
  match fmt with
  | Json -> print_json_array json_of_highlight highlights
  | _ -> List.iter (print_highlight fmt) highlights

let print_user fmt (u : Karakeep.user_info) =
  match fmt with
  | Text ->
      Printf.printf "User: %s\n" (Option.value ~default:"(no name)" u.name);
      Printf.printf "Email: %s\n" (Option.value ~default:"(no email)" u.email);
      Printf.printf "ID: %s\n" u.id
  | Json -> print_endline (json_of_user u)
  | Quiet -> print_endline u.id

let print_stats fmt (s : Karakeep.user_stats) =
  match fmt with
  | Text ->
      Printf.printf "Bookmarks: %d\n" s.num_bookmarks;
      Printf.printf "Favorites: %d\n" s.num_favorites;
      Printf.printf "Archived: %d\n" s.num_archived;
      Printf.printf "Tags: %d\n" s.num_tags;
      Printf.printf "Lists: %d\n" s.num_lists;
      Printf.printf "Highlights: %d\n" s.num_highlights
  | Json -> print_endline (json_of_stats s)
  | Quiet ->
      Printf.printf "%d %d %d %d %d %d\n" s.num_bookmarks s.num_favorites
        s.num_archived s.num_tags s.num_lists s.num_highlights

(* Error handling *)
let handle_errors f =
  try f () with
  | Eio.Io (Karakeep.E err, _) ->
      Logs.err (fun m -> m "Karakeep error: %s" (Karakeep.error_to_string err));
      (match err with
      | Karakeep.Api_error { status; _ } when status = 404 -> 2
      | Karakeep.Api_error { status; _ } when status >= 400 && status < 500 -> 2
      | Karakeep.Api_error _ -> 2
      | Karakeep.Json_error _ -> 1)
  | Eio.Io (Eio.Net.E _, _) as e ->
      Logs.err (fun m -> m "Network error: %a" Eio.Exn.pp e);
      3
  | Failure msg ->
      Logs.err (fun m -> m "Error: %s" msg);
      1
  | e ->
      Logs.err (fun m -> m "Unexpected error: %s" (Printexc.to_string e));
      1

(* Re-export modules for public access *)
module Karakeep_config = Karakeep_config
module Karakeep_auth_cmd = Karakeep_auth_cmd

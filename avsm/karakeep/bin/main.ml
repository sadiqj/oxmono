open Cmdliner
open Karakeep_cmd

(* Helper to run with Eio env *)
let run_with_client config_opt f =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  with_client ~env ~sw config_opt f

(* Bookmark commands *)

let list_bookmarks_cmd =
  let run config_opt fmt () limit cursor archived favourited include_content =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let result =
              Karakeep.fetch_bookmarks client ?limit ?cursor ~include_content
                ?archived ?favourited ()
            in
            print_bookmarks fmt result.bookmarks;
            Option.iter
              (fun c -> Logs.info (fun m -> m "Next cursor: %s" c))
              result.next_cursor);
        0)
  in
  let doc = "List bookmarks with optional filters." in
  let info = Cmd.info "list" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ limit_term
      $ cursor_term $ archived_term $ favourited_term $ include_content_term)

let list_all_bookmarks_cmd =
  let run config_opt fmt () archived favourited =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmarks =
              Karakeep.fetch_all_bookmarks client ?archived ?favourited ()
            in
            print_bookmarks fmt bookmarks);
        0)
  in
  let doc = "List all bookmarks (handles pagination automatically)." in
  let info = Cmd.info "list-all" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging
      $ archived_term $ favourited_term)

let get_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark = Karakeep.fetch_bookmark_details client bookmark_id in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Get details of a specific bookmark." in
  let info = Cmd.info "get" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let create_bookmark_cmd =
  let run config_opt fmt () url title note summary tags favourited archived =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tags = if tags = [] then None else Some tags in
            let bookmark =
              Karakeep.create_bookmark client ~url ?title ?note ?summary ?tags
                ?favourited ?archived ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Create a new bookmark." in
  let info = Cmd.info "create" ~doc in
  let fav_term =
    Arg.(value & flag & info [ "fav"; "favourited" ] ~doc:"Mark as favourite.")
  in
  let arch_term =
    Arg.(value & flag & info [ "archive"; "archived" ] ~doc:"Mark as archived.")
  in
  let fav_opt = Term.(const (fun b -> if b then Some true else None) $ fav_term) in
  let arch_opt = Term.(const (fun b -> if b then Some true else None) $ arch_term) in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ url_term
      $ title_term $ note_term $ summary_term $ tags_term $ fav_opt $ arch_opt)

let update_bookmark_cmd =
  let run config_opt fmt () bookmark_id title note summary =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark =
              Karakeep.update_bookmark client bookmark_id ?title ?note ?summary ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Update a bookmark." in
  let info = Cmd.info "update" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging
      $ bookmark_id_term $ title_term $ note_term $ summary_term)

let delete_bookmark_cmd =
  let run config_opt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.delete_bookmark client bookmark_id;
            Logs.app (fun m -> m "Deleted bookmark %s" bookmark_id));
        0)
  in
  let doc = "Delete a bookmark." in
  let info = Cmd.info "delete" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ bookmark_id_term)

let archive_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark =
              Karakeep.update_bookmark client bookmark_id ~archived:true ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Archive a bookmark." in
  let info = Cmd.info "archive" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let unarchive_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark =
              Karakeep.update_bookmark client bookmark_id ~archived:false ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Unarchive a bookmark." in
  let info = Cmd.info "unarchive" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let favourite_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark =
              Karakeep.update_bookmark client bookmark_id ~favourited:true ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Mark a bookmark as favourite." in
  let info = Cmd.info "fav" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let unfavourite_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let bookmark =
              Karakeep.update_bookmark client bookmark_id ~favourited:false ()
            in
            print_bookmark fmt bookmark);
        0)
  in
  let doc = "Remove favourite mark from a bookmark." in
  let info = Cmd.info "unfav" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let summarize_bookmark_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let response = Karakeep.summarize_bookmark client bookmark_id in
            match fmt with
            | Text -> print_endline response.summary
            | Json ->
                let json = Jsont_bytesrw.encode_string Karakeep.summarize_response_jsont response in
                (match json with
                 | Ok s -> print_endline s
                 | Error e -> Logs.err (fun m -> m "JSON encoding error: %s" e))
            | Quiet -> print_endline response.summary);
        0)
  in
  let doc = "Generate an AI summary for a bookmark." in
  let info = Cmd.info "summarize" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let search_bookmarks_cmd =
  let run config_opt fmt () query limit cursor =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let result =
              Karakeep.search_bookmarks client ~query ?limit ?cursor ()
            in
            print_bookmarks fmt result.bookmarks;
            Option.iter
              (fun c -> Logs.info (fun m -> m "Next cursor: %s" c))
              result.next_cursor);
        0)
  in
  let doc = "Search bookmarks." in
  let info = Cmd.info "search" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging
      $ search_query_term $ limit_term $ cursor_term)

let bookmarks_cmd =
  let doc = "Bookmark operations." in
  let info = Cmd.info "bookmarks" ~doc in
  Cmd.group info
    [
      list_bookmarks_cmd;
      list_all_bookmarks_cmd;
      get_bookmark_cmd;
      create_bookmark_cmd;
      update_bookmark_cmd;
      delete_bookmark_cmd;
      archive_bookmark_cmd;
      unarchive_bookmark_cmd;
      favourite_bookmark_cmd;
      unfavourite_bookmark_cmd;
      summarize_bookmark_cmd;
      search_bookmarks_cmd;
    ]

(* Tag commands *)

let list_tags_cmd =
  let run config_opt fmt () =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tags = Karakeep.fetch_all_tags client in
            print_tags fmt tags);
        0)
  in
  let doc = "List all tags." in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ output_format_term $ setup_logging)

let get_tag_cmd =
  let run config_opt fmt () tag_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tag = Karakeep.fetch_tag_details client tag_id in
            print_tag fmt tag);
        0)
  in
  let doc = "Get details of a specific tag." in
  let info = Cmd.info "get" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ tag_id_term)

let tag_bookmarks_cmd =
  let run config_opt fmt () tag_id limit cursor =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let result =
              Karakeep.fetch_bookmarks_with_tag client ?limit ?cursor tag_id
            in
            print_bookmarks fmt result.bookmarks);
        0)
  in
  let doc = "List bookmarks with a specific tag." in
  let info = Cmd.info "bookmarks" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ tag_id_term
      $ limit_term $ cursor_term)

let rename_tag_cmd =
  let run config_opt fmt () tag_id name =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tag = Karakeep.update_tag client ~name tag_id in
            print_tag fmt tag);
        0)
  in
  let doc = "Rename a tag." in
  let info = Cmd.info "rename" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ tag_id_term
      $ name_term)

let delete_tag_cmd =
  let run config_opt () tag_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.delete_tag client tag_id;
            Logs.app (fun m -> m "Deleted tag %s" tag_id));
        0)
  in
  let doc = "Delete a tag." in
  let info = Cmd.info "delete" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ tag_id_term)

let attach_tags_cmd =
  let run config_opt () bookmark_id tags =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tag_refs = List.map (fun t -> `TagName t) tags in
            let _ = Karakeep.attach_tags client ~tag_refs bookmark_id in
            Logs.app (fun m ->
                m "Attached %d tags to bookmark %s" (List.length tags) bookmark_id));
        0)
  in
  let doc = "Attach tags to a bookmark." in
  let info = Cmd.info "attach" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ setup_logging $ bookmark_id_term $ tags_term)

let detach_tags_cmd =
  let run config_opt () bookmark_id tags =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let tag_refs = List.map (fun t -> `TagName t) tags in
            let _ = Karakeep.detach_tags client ~tag_refs bookmark_id in
            Logs.app (fun m ->
                m "Detached %d tags from bookmark %s" (List.length tags) bookmark_id));
        0)
  in
  let doc = "Detach tags from a bookmark." in
  let info = Cmd.info "detach" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ setup_logging $ bookmark_id_term $ tags_term)

let tags_cmd =
  let doc = "Tag operations." in
  let info = Cmd.info "tags" ~doc in
  Cmd.group info
    [
      list_tags_cmd;
      get_tag_cmd;
      tag_bookmarks_cmd;
      rename_tag_cmd;
      delete_tag_cmd;
      attach_tags_cmd;
      detach_tags_cmd;
    ]

(* List commands *)

let list_lists_cmd =
  let run config_opt fmt () =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let lists = Karakeep.fetch_all_lists client in
            print_lists fmt lists);
        0)
  in
  let doc = "List all lists." in
  let info = Cmd.info "list" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ output_format_term $ setup_logging)

let get_list_cmd =
  let run config_opt fmt () list_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let lst = Karakeep.fetch_list_details client list_id in
            print_list fmt lst);
        0)
  in
  let doc = "Get details of a specific list." in
  let info = Cmd.info "get" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ list_id_term)

let create_list_cmd =
  let run config_opt fmt () name icon description parent_id query =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let list_type =
              match query with Some _ -> Some Karakeep.Smart | None -> None
            in
            let lst =
              Karakeep.create_list client ~name ~icon ?description ?parent_id
                ?list_type ?query ()
            in
            print_list fmt lst);
        0)
  in
  let doc = "Create a new list." in
  let info = Cmd.info "create" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ name_term
      $ icon_term $ description_term $ parent_id_term $ query_term)

let update_list_cmd =
  let run config_opt fmt () list_id name icon description query =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let lst =
              Karakeep.update_list client ?name ?icon ?description ?query list_id
            in
            print_list fmt lst);
        0)
  in
  let doc = "Update a list." in
  let info = Cmd.info "update" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ list_id_term
      $ name_opt_term $ icon_opt_term $ description_term $ query_term)

let delete_list_cmd =
  let run config_opt () list_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.delete_list client list_id;
            Logs.app (fun m -> m "Deleted list %s" list_id));
        0)
  in
  let doc = "Delete a list." in
  let info = Cmd.info "delete" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ list_id_term)

let list_bookmarks_in_list_cmd =
  let run config_opt fmt () list_id limit cursor =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let result =
              Karakeep.fetch_bookmarks_in_list client ?limit ?cursor list_id
            in
            print_bookmarks fmt result.bookmarks);
        0)
  in
  let doc = "List bookmarks in a list." in
  let info = Cmd.info "bookmarks" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ list_id_term
      $ limit_term $ cursor_term)

let add_to_list_cmd =
  let run config_opt () list_id bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.add_bookmark_to_list client list_id bookmark_id;
            Logs.app (fun m ->
                m "Added bookmark %s to list %s" bookmark_id list_id));
        0)
  in
  let doc = "Add a bookmark to a list." in
  let info = Cmd.info "add" ~doc in
  let bid_term =
    let doc = "Bookmark ID to add." in
    Arg.(required & pos 1 (some string) None & info [] ~docv:"BOOKMARK_ID" ~doc)
  in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ list_id_term $ bid_term)

let remove_from_list_cmd =
  let run config_opt () list_id bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.remove_bookmark_from_list client list_id bookmark_id;
            Logs.app (fun m ->
                m "Removed bookmark %s from list %s" bookmark_id list_id));
        0)
  in
  let doc = "Remove a bookmark from a list." in
  let info = Cmd.info "remove" ~doc in
  let bid_term =
    let doc = "Bookmark ID to remove." in
    Arg.(required & pos 1 (some string) None & info [] ~docv:"BOOKMARK_ID" ~doc)
  in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ list_id_term $ bid_term)

let lists_cmd =
  let doc = "List operations." in
  let info = Cmd.info "lists" ~doc in
  Cmd.group info
    [
      list_lists_cmd;
      get_list_cmd;
      create_list_cmd;
      update_list_cmd;
      delete_list_cmd;
      list_bookmarks_in_list_cmd;
      add_to_list_cmd;
      remove_from_list_cmd;
    ]

(* Highlight commands *)

let list_highlights_cmd =
  let run config_opt fmt () limit cursor =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let result = Karakeep.fetch_all_highlights client ?limit ?cursor () in
            print_highlights fmt result.highlights);
        0)
  in
  let doc = "List all highlights." in
  let info = Cmd.info "list" ~doc in
  Cmd.v info
    Term.(
      const run $ config_opt_term $ output_format_term $ setup_logging $ limit_term
      $ cursor_term)

let get_highlight_cmd =
  let run config_opt fmt () highlight_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let highlight = Karakeep.fetch_highlight_details client highlight_id in
            print_highlight fmt highlight);
        0)
  in
  let doc = "Get details of a specific highlight." in
  let info = Cmd.info "get" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ highlight_id_term)

let bookmark_highlights_cmd =
  let run config_opt fmt () bookmark_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let highlights = Karakeep.fetch_bookmark_highlights client bookmark_id in
            print_highlights fmt highlights);
        0)
  in
  let doc = "List highlights for a bookmark." in
  let info = Cmd.info "for-bookmark" ~doc in
  Cmd.v info
    Term.(const run $ config_opt_term $ output_format_term $ setup_logging $ bookmark_id_term)

let delete_highlight_cmd =
  let run config_opt () highlight_id =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            Karakeep.delete_highlight client highlight_id;
            Logs.app (fun m -> m "Deleted highlight %s" highlight_id));
        0)
  in
  let doc = "Delete a highlight." in
  let info = Cmd.info "delete" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ setup_logging $ highlight_id_term)

let highlights_cmd =
  let doc = "Highlight operations." in
  let info = Cmd.info "highlights" ~doc in
  Cmd.group info
    [
      list_highlights_cmd;
      get_highlight_cmd;
      bookmark_highlights_cmd;
      delete_highlight_cmd;
    ]

(* User commands *)

let whoami_cmd =
  let run config_opt fmt () =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let user = Karakeep.get_current_user client in
            print_user fmt user);
        0)
  in
  let doc = "Show current user info." in
  let info = Cmd.info "whoami" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ output_format_term $ setup_logging)

let stats_cmd =
  let run config_opt fmt () =
    handle_errors (fun () ->
        run_with_client config_opt (fun client ->
            let stats = Karakeep.get_user_stats client in
            print_stats fmt stats);
        0)
  in
  let doc = "Show user statistics." in
  let info = Cmd.info "stats" ~doc in
  Cmd.v info Term.(const run $ config_opt_term $ output_format_term $ setup_logging)

(* Main command *)

let main_cmd =
  let doc = "Karakeep CLI - interact with a Karakeep bookmark service." in
  let man =
    [
      `S Manpage.s_description;
      `P
        "karakeep is a command-line tool for interacting with a Karakeep \
         bookmark service instance.";
      `S "AUTHENTICATION";
      `P "Credentials are stored in XDG-compliant locations:";
      `P "    ~/.config/karakeep/profiles/<profile>/credentials.toml";
      `P "Use $(b,karakeep auth login) to configure credentials interactively.";
      `P "Multiple profiles are supported for different Karakeep instances.";
      `S Manpage.s_common_options;
      `P "These options are common to all commands.";
      `P "$(b,--profile)=$(i,NAME), $(b,-P) $(i,NAME)";
      `Noblank;
      `P "    Use a specific profile (default: current profile).";
      `P "$(b,--base-url)=$(i,URL), $(b,-u) $(i,URL)";
      `Noblank;
      `P "    Base URL of the Karakeep instance (overrides profile).";
      `P "$(b,--api-key)=$(i,KEY), $(b,-k) $(i,KEY)";
      `Noblank;
      `P "    API key for authentication (overrides profile).";
      `P "$(b,--api-key-file)=$(i,FILE)";
      `Noblank;
      `P "    Legacy: Read API key from file (default: .karakeep-api).";
      `P "$(b,-v), $(b,--verbose)";
      `Noblank;
      `P "    Increase verbosity. Repeatable.";
      `P "$(b,-q), $(b,--quiet)";
      `Noblank;
      `P "    Be quiet. Takes over $(b,-v).";
      `P "$(b,--verbose-http)";
      `Noblank;
      `P "    Enable verbose HTTP-level logging including TLS details and hexdumps.";
      `P "$(b,--json), $(b,-J)";
      `Noblank;
      `P "    Output in JSON format.";
      `P "$(b,--ids-only)";
      `Noblank;
      `P "    Output only IDs (one per line).";
      `S "ENVIRONMENT";
      `P "$(b,KARAKEEP_BASE_URL) - Base URL of the Karakeep instance.";
      `P "$(b,KARAKEEP_API_KEY) - API key for authentication.";
      `S Manpage.s_bugs;
      `P "Report bugs at https://github.com/avsm/ocaml-karakeep/issues";
    ]
  in
  let info = Cmd.info "karakeep" ~version:"0.1.0" ~doc ~man in
  Cmd.group info
    [
      Karakeep_auth_cmd.auth_cmd ();
      bookmarks_cmd;
      tags_cmd;
      lists_cmd;
      highlights_cmd;
      whoami_cmd;
      stats_cmd;
    ]

let () = exit (Cmd.eval' main_cmd)

(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Arod webserver - an httpz-based server for Bushel content *)

(** {1 Logging} *)

let src = Logs.Src.create "arod" ~doc:"Arod webserver"

module Log = (val Logs.src_log src : Logs.LOG)

(** {1 CLI} *)

open Cmdliner

let setup_logging style_renderer level =
  Fmt_tty.setup_std_outputs ?style_renderer ();
  Logs.set_level level;
  Logs.set_reporter (Logs_fmt.reporter ())

let logging_t =
  let open Cmdliner in
  Term.(const setup_logging $ Fmt_cli.style_renderer () $ Logs_cli.level ())

let config_file =
  let doc = "Path to config file (default: ~/.config/arod/config.toml)." in
  Arg.(value & opt (some file) None & info [ "c"; "config" ] ~docv:"FILE" ~doc)

let serve_cmd =
  let run () config_file =
    let cfg = Arod.Config.load_or_default ?path:config_file () in
    Log.info (fun m -> m "Starting Arod server...");
    Log.info (fun m -> m "Config:@.%a" Arod.Config.pp cfg);
    Eio_main.run @@ fun env ->
    let fs = Eio.Stdenv.fs env in
    let net = Eio.Stdenv.net env in
    Log.info (fun m -> m "Loading entries from %s" cfg.paths.data_dir);
    (* Create context (loads Bushel entries) *)
    let ctx = Arod.Ctx.create ~config:cfg fs in
    Log.info (fun m ->
        m "Loaded %d notes, %d papers, %d projects, %d ideas, %d videos, %d images, %d feed items"
          (List.length (Arod.Ctx.notes ctx))
          (List.length (Arod.Ctx.papers ctx))
          (List.length (Arod.Ctx.projects ctx))
          (List.length (Arod.Ctx.ideas ctx))
          (List.length (Arod.Ctx.videos ctx))
          (List.length (Arod.Ctx.images ctx))
          (List.length (Arod.Ctx.feed_items ctx)));
    (* Create cache with 5 minute TTL *)
    let cache = Arod.Cache.create ~ttl:300.0 in
    (* Run inside switch so search DB stays open for server lifetime *)
    Eio.Switch.run @@ fun sw ->
    (* Build in-memory search index on startup *)
    let search = Arod_search.create_memory ~sw () in
    Arod_search.rebuild search ctx;
    Log.info (fun m -> m "Search index built (%d entries)"
      (List.length (Arod.Ctx.all_entries ctx) + List.length (Arod.Ctx.all_links ctx)));
    (* Get all routes with ctx, cache and search *)
    let routes = Arod_handlers.all_routes ~ctx ~cache ~search in
    Arod_server.run ~sw ~net ~config:cfg routes;
    0
  in
  let doc = "Start the Arod webserver." in
  let info = Cmd.info "serve" ~doc in
  Cmd.v info Term.(const run $ logging_t $ config_file)

let init_cmd =
  let run () =
    let path = Arod.Config.config_file () in
    let dir = Filename.dirname path in
    if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
    if Sys.file_exists path then begin
      Printf.eprintf "Config file already exists: %s\n" path;
      1
    end
    else begin
      let oc = open_out path in
      output_string oc Arod.Config.sample_config;
      close_out oc;
      Printf.printf "Created config file: %s\n" path;
      0
    end
  in
  let doc = "Initialize a default configuration file." in
  let info = Cmd.info "init" ~doc in
  Cmd.v info Term.(const run $ const ())

let config_cmd =
  let run () config_file =
    let cfg = Arod.Config.load_or_default ?path:config_file () in
    Fmt.pr "%a\n" Arod.Config.pp cfg;
    0
  in
  let doc = "Show current configuration." in
  let info = Cmd.info "config" ~doc in
  Cmd.v info Term.(const run $ logging_t $ config_file)

let search_cmd =
  let run () _config_file limit query_words =
    let input = String.concat " " query_words in
    if input = "" then begin
      Printf.eprintf "Usage: arod search [kind:TYPE] QUERY...\n\n";
      Printf.eprintf "Search syntax:\n";
      Printf.eprintf "  words            search for words in title, body, tags\n";
      Printf.eprintf "  \"exact phrase\"   match exact phrase\n";
      Printf.eprintf "  prefix*          prefix matching\n";
      Printf.eprintf "  kind:TYPE        restrict to type (%s)\n"
        (String.concat ", " Arod_search.kinds);
      Printf.eprintf "\nExamples:\n";
      Printf.eprintf "  arod search ocaml runtime\n";
      Printf.eprintf "  arod search kind:paper \"memory safety\"\n";
      Printf.eprintf "  arod search kind:note unikernel*\n";
      1
    end else begin
      Eio_main.run @@ fun env ->
      let fs = Eio.Stdenv.fs env in
      Eio.Switch.run @@ fun sw ->
      let xdg = Xdge.create fs "arod" in
      let db_path = Eio.Path.(Xdge.cache_dir xdg / "search.db") in
      let search = Arod_search.open_readonly ~sw db_path in
      let results = Arod_search.search search ?limit input in
      if results = [] then begin
        Printf.printf "No results.\n";
        0
      end else begin
        List.iter (fun r ->
          Fmt.pr "%a@.@." Arod_search.pp_result r
        ) results;
        Printf.printf "(%d result%s)\n"
          (List.length results)
          (if List.length results = 1 then "" else "s");
        0
      end
    end
  in
  let limit =
    let doc = "Maximum number of results." in
    Arg.(value & opt (some int) None & info [ "n"; "limit" ] ~docv:"N" ~doc)
  in
  let query_words =
    Arg.(value & pos_all string [] & info [] ~docv:"QUERY")
  in
  let doc = "Search the full-text index." in
  let man = [
    `S Manpage.s_description;
    `P "Search across all indexed content (notes, papers, projects, \
        ideas, videos, links) using the FTS5 full-text search engine.";
    `P "Use $(b,kind:TYPE) to restrict results to a specific type. \
        Valid types are: paper, note, project, idea, video, link.";
    `S Manpage.s_examples;
    `P "Search for OCaml-related content:";
    `Pre "  arod search ocaml";
    `P "Search only papers:";
    `Pre "  arod search kind:paper garbage collection";
    `P "Prefix matching:";
    `Pre "  arod search unikernel*";
  ] in
  let info = Cmd.info "search" ~doc ~man in
  Cmd.v info Term.(const run $ logging_t $ config_file $ limit $ query_words)

let index_cmd =
  let run () config_file =
    let cfg = Arod.Config.load_or_default ?path:config_file () in
    Eio_main.run @@ fun env ->
    let fs = Eio.Stdenv.fs env in
    let ctx = Arod.Ctx.create ~config:cfg fs in
    Eio.Switch.run @@ fun sw ->
    let xdg = Xdge.create fs "arod" in
    let db_path = Eio.Path.(Xdge.cache_dir xdg / "search.db") in
    let search = Arod_search.create ~sw db_path in
    Arod_search.rebuild search ctx;
    Log.info (fun m -> m "Search index built at %a" Eio.Path.pp db_path);
    0
  in
  let doc = "Build the full-text search index." in
  let info = Cmd.info "index" ~doc in
  Cmd.v info Term.(const run $ logging_t $ config_file)

let annotate_cmd =
  let run () config_file entry_url slug =
    let cfg = Arod.Config.load_or_default ?path:config_file () in
    (* Validate bushel slug exists *)
    Eio_main.run @@ fun env ->
    let fs = Eio.Stdenv.fs env in
    let ctx = Arod.Ctx.create ~config:cfg fs in
    (match Arod.Ctx.lookup ctx slug with
     | None ->
       Printf.eprintf "Error: Bushel slug '%s' not found.\n" slug;
       1
     | Some _ ->
       (* Find the feed entry URL across all contacts/feeds *)
       let xdg = Xdge.create fs "sortal" in
       let feed_store = Sortal_feed.Store.create_from_xdg xdg in
       let contacts = Arod.Ctx.contacts ctx in
       let normalize_url s =
         let s = if String.length s > 0 && s.[String.length s - 1] = '/' then
           String.sub s 0 (String.length s - 1)
         else s in
         (* Normalize www. prefix: strip it for comparison *)
         let s = match String.split_on_char '/' s with
           | proto :: "" :: host :: rest when String.length host > 4
             && String.sub host 0 4 = "www." ->
             String.concat "/" (proto :: "" :: String.sub host 4 (String.length host - 4) :: rest)
           | _ -> s
         in
         String.lowercase_ascii s
       in
       let norm_entry_url = normalize_url entry_url in
       let found = ref false in
       List.iter (fun contact ->
         if not !found then
           let handle = Sortal_schema.Contact.handle contact in
           match Sortal_schema.Contact.feeds contact with
           | Some feeds when feeds <> [] ->
             List.iter (fun feed ->
               if not !found then
                 let entries = Sortal_feed.Store.entries_of_feed feed_store ~handle feed in
                 List.iter (fun (fe : Sortal_feed.Entry.t) ->
                   if not !found then
                     match fe.url with
                     | Some u when normalize_url (Uri.to_string u) = norm_entry_url ->
                       let feed_url = Uri.to_string u in
                       let ann_path = Sortal_feed.Store.annotations_file feed_store handle feed in
                       let ann = Sortal_feed.Annotations.load ann_path in
                       Sortal_feed.Annotations.add_slug ann ~url:feed_url ~slug;
                       Sortal_feed.Annotations.save ann_path ann;
                       Printf.printf "Associated %s with %s (contact: %s)\n"
                         feed_url slug (Sortal_schema.Contact.name contact);
                       found := true
                     | _ -> ()
                 ) entries
             ) feeds
           | _ -> ()
       ) contacts;
       if not !found then begin
         Printf.eprintf "Error: URL '%s' not found in any feed.\n" entry_url;
         1
       end else
         0)
  in
  let entry_url =
    let doc = "URL of the feed entry to annotate." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"URL" ~doc)
  in
  let slug =
    let doc = "Bushel slug to associate with the feed entry." in
    Arg.(required & pos 1 (some string) None & info [] ~docv:"SLUG" ~doc)
  in
  let doc = "Associate a feed entry with a bushel slug." in
  let man = [
    `S Manpage.s_description;
    `P "Creates a persistent annotation linking a feed entry URL to a \
        bushel slug. The annotation survives feed syncs and causes the \
        entry to show a mention chip on the network page.";
    `S Manpage.s_examples;
    `P "Associate a blog post with a paper:";
    `Pre "  arod annotate https://example.com/post my-paper-slug";
  ] in
  let info = Cmd.info "annotate" ~doc ~man in
  Cmd.v info Term.(const run $ logging_t $ config_file $ entry_url $ slug)

let main_cmd =
  let doc = "Arod - a webserver for Bushel content" in
  let man =
    [
      `S Manpage.s_description;
      `P
        "Arod is an httpz-based webserver that serves Bushel content \
         (notes, papers, projects, ideas, videos) as a website.";
      `S "CONFIGURATION";
      `P "Configuration is read from ~/.config/arod/config.toml";
      `P "Run $(b,arod init) to create a default config file.";
    ]
  in
  let info = Cmd.info "arod" ~version:"0.1.0" ~doc ~man in
  Cmd.group info [ serve_cmd; init_cmd; config_cmd; index_cmd; search_cmd; annotate_cmd ]

let () =
  match Cmd.eval_value main_cmd with
  | Ok (`Ok exit_code) -> exit exit_code
  | Ok `Help | Ok `Version -> exit 0
  | Error _ -> exit 1

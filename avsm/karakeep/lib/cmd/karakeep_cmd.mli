(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep CLI support library

    This module provides cmdliner terms and utilities for building command-line
    tools that interact with the Karakeep API. It can be used standalone or
    embedded into larger applications.

    {2 Basic Usage}

    {[
      open Cmdliner

      let my_command =
        let open Karakeep_cmd in
        let run config =
          with_client config (fun client ->
              let bookmarks = Karakeep.fetch_all_bookmarks client () in
              List.iter (fun b -> print_endline (Karakeep.bookmark_title b)) bookmarks)
        in
        Cmd.v (Cmd.info "my-command") Term.(const run $ config_term)
    ]} *)

(** {1 Configuration} *)

type config = {
  base_url : string;  (** Base URL of the Karakeep instance *)
  api_key : string;   (** API key for authentication *)
}
(** Configuration for connecting to a Karakeep instance. *)

type config_opt
(** Configuration options from CLI, not yet resolved.
    Use {!resolve_config} or {!with_client} with an Eio env to resolve. *)

val config_opt_term : config_opt Cmdliner.Term.t
(** Cmdliner term that parses configuration options from command-line arguments.
    The actual credentials are resolved at runtime by {!resolve_config} or
    {!with_client} when given an Eio environment.

    Configuration is resolved in priority order:
    1. [--api-key KEY] flag
    2. [KARAKEEP_API_KEY] environment variable
    3. XDG profile credentials (~/.config/karakeep/profiles/...)
    4. Legacy [--api-key-file FILE] (default: .karakeep-api)

    Options:
    - [--profile NAME] or [-P NAME]: Select a specific profile
    - [--base-url URL] or [KARAKEEP_BASE_URL]: Override instance URL
    - [--api-key KEY] or [KARAKEEP_API_KEY]: Override API key
    - [--api-key-file FILE]: Legacy API key file (default: .karakeep-api) *)

val resolve_config : fs:Eio.Fs.dir_ty Eio.Path.t -> config_opt -> config
(** [resolve_config ~fs config_opt] resolves credentials using the filesystem.
    @raise Failure if no credentials are found. *)

(** {1 Common Terms} *)

val profile_term : string option Cmdliner.Term.t
(** Term for [--profile NAME] / [-P NAME] option to select a profile. *)

(** {1 Pagination Terms} *)

val limit_term : int option Cmdliner.Term.t
(** Term for [--limit N] pagination option. *)

val cursor_term : string option Cmdliner.Term.t
(** Term for [--cursor CURSOR] pagination option. *)

(** {1 Filter Terms} *)

val archived_term : bool option Cmdliner.Term.t
(** Term for [--archived] / [--no-archived] filter. *)

val favourited_term : bool option Cmdliner.Term.t
(** Term for [--favourited] / [--no-favourited] filter. *)

val include_content_term : bool Cmdliner.Term.t
(** Term for [--include-content] / [--no-content] option. *)

(** {1 Entity ID Terms} *)

val bookmark_id_term : Karakeep.bookmark_id Cmdliner.Term.t
(** Positional argument for bookmark ID. *)

val tag_id_term : Karakeep.tag_id Cmdliner.Term.t
(** Positional argument for tag ID. *)

val list_id_term : Karakeep.list_id Cmdliner.Term.t
(** Positional argument for list ID. *)

val highlight_id_term : Karakeep.highlight_id Cmdliner.Term.t
(** Positional argument for highlight ID. *)

(** {1 Bookmark Terms} *)

val url_term : string Cmdliner.Term.t
(** Positional argument for URL. *)

val title_term : string option Cmdliner.Term.t
(** Term for [--title TITLE] option. *)

val note_term : string option Cmdliner.Term.t
(** Term for [--note NOTE] option. *)

val summary_term : string option Cmdliner.Term.t
(** Term for [--summary TEXT] option. *)

val tags_term : string list Cmdliner.Term.t
(** Term for [--tag TAG] option (repeatable). *)

(** {1 List Terms} *)

val name_term : string Cmdliner.Term.t
(** Term for [--name NAME] required option. *)

val name_opt_term : string option Cmdliner.Term.t
(** Term for [--name NAME] optional option. *)

val icon_term : string Cmdliner.Term.t
(** Term for [--icon ICON] required option. *)

val icon_opt_term : string option Cmdliner.Term.t
(** Term for [--icon ICON] optional option. *)

val description_term : string option Cmdliner.Term.t
(** Term for [--description TEXT] option. *)

val parent_id_term : Karakeep.list_id option Cmdliner.Term.t
(** Term for [--parent-id ID] option. *)

val query_term : string option Cmdliner.Term.t
(** Term for [--query QUERY] smart list option. *)

val search_query_term : string Cmdliner.Term.t
(** Positional argument for search query. *)

(** {1 Highlight Terms} *)

val color_term : Karakeep.highlight_color option Cmdliner.Term.t
(** Term for [--color COLOR] option. *)

(** {1 Output Terms} *)

type output_format =
  | Text   (** Human-readable text output *)
  | Json   (** JSON output *)
  | Quiet  (** Minimal output (IDs only) *)

val output_format_term : output_format Cmdliner.Term.t
(** Term for [--json] / [--ids-only] output format options. *)

(** {1 Logging Setup} *)

val setup_logging : unit Cmdliner.Term.t
(** Term that sets up logging based on verbosity flags.
    Use with [Logs_cli] and [Fmt_cli] for standard options. *)

val logs_term : Logs.level option Cmdliner.Term.t
(** Term for log level from [Logs_cli]. *)

val fmt_styler_term : Fmt.style_renderer option Cmdliner.Term.t
(** Term for formatter style from [Fmt_cli]. *)

(** {1 Client Helpers} *)

val with_client :
  env:< clock : _ Eio.Time.clock ; fs : Eio.Fs.dir_ty Eio.Path.t ; net : _ Eio.Net.t ; .. > ->
  sw:Eio.Switch.t ->
  config_opt ->
  (Karakeep.t -> 'a) ->
  'a
(** [with_client ~env ~sw config_opt f] resolves configuration and runs [f]
    with a Karakeep client.

    {[
      let run config_opt =
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        with_client ~env ~sw config_opt (fun client ->
            let bookmarks = Karakeep.fetch_all_bookmarks client () in
            (* ... *))
    ]}

    @raise Failure if no credentials are found. *)

(** {1 Output Helpers} *)

val print_bookmark : output_format -> Karakeep.bookmark -> unit
(** Print a bookmark in the specified format. *)

val print_bookmarks : output_format -> Karakeep.bookmark list -> unit
(** Print a list of bookmarks in the specified format. *)

val print_tag : output_format -> Karakeep.tag -> unit
(** Print a tag in the specified format. *)

val print_tags : output_format -> Karakeep.tag list -> unit
(** Print a list of tags in the specified format. *)

val print_list : output_format -> Karakeep._list -> unit
(** Print a list in the specified format. *)

val print_lists : output_format -> Karakeep._list list -> unit
(** Print lists in the specified format. *)

val print_highlight : output_format -> Karakeep.highlight -> unit
(** Print a highlight in the specified format. *)

val print_highlights : output_format -> Karakeep.highlight list -> unit
(** Print highlights in the specified format. *)

val print_user : output_format -> Karakeep.user_info -> unit
(** Print user info in the specified format. *)

val print_stats : output_format -> Karakeep.user_stats -> unit
(** Print user stats in the specified format. *)

(** {1 Error Handling} *)

val handle_errors : (unit -> int) -> int
(** [handle_errors f] runs [f ()] and catches Karakeep errors,
    printing them to stderr and returning appropriate exit codes.

    Exit codes:
    - 0: Success
    - 1: General error
    - 2: API error (e.g., not found, unauthorized)
    - 3: Network error *)

(** {1 Re-exported Modules} *)

module Karakeep_config = Karakeep_config
(** Configuration storage with XDG support. *)

module Karakeep_auth_cmd = Karakeep_auth_cmd
(** Authentication CLI commands. *)

(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep API client

    This module provides a client for interacting with the Karakeep bookmark
    service API using Eio for structured concurrency.

    {2 Logging}

    Enable debug logging to trace API calls:
    {[
      Logs.Src.set_level Karakeep.src (Some Logs.Debug);
      Logs.set_reporter (Logs_fmt.reporter ())
    ]}

    {2 Basic Usage}

    {[
      Eio_main.run @@ fun env ->
      Eio.Switch.run @@ fun sw ->

      (* Create the client *)
      let client =
        Karakeep.create ~sw ~env ~base_url:"https://hoard.recoil.org"
          ~api_key:"your_api_key"
      in

      (* Fetch recent bookmarks *)
      let { bookmarks; next_cursor } = Karakeep.fetch_bookmarks client () in

      (* Fetch all bookmarks (handles pagination automatically) *)
      let all_bookmarks = Karakeep.fetch_all_bookmarks client () in

      (* Get a specific bookmark by ID *)
      let bookmark = Karakeep.fetch_bookmark_details client "bookmark_id" in

      (* Create a new bookmark *)
      let new_bookmark =
        Karakeep.create_bookmark client ~url:"https://ocaml.org"
          ~title:"OCaml Programming Language" ()
      in
    ]}

    {2 Error Handling}

    All operations may raise [Eio.Io] exceptions with {!E} error payload:

    {[
      try
        let bookmarks = Karakeep.fetch_bookmarks client () in
        (* ... *)
      with
      | Eio.Io (Karakeep.E err, _) ->
          Printf.eprintf "Karakeep error: %s\n" (Karakeep.error_to_string err)
    ]}

    {2 API Key}

    All operations require an API key that can be obtained from your Karakeep
    instance settings. *)

(** {1 Protocol Types}

    Re-export all protocol types and codecs from {!Karakeep_proto}. *)

include module type of Karakeep_proto

(** {1 Logging} *)

val src : Logs.Src.t
(** Logs source for Karakeep API client. Configure with:
    {[
      Logs.Src.set_level Karakeep.src (Some Logs.Debug)
    ]} *)

(** {1 Error Handling} *)

type error =
  | Api_error of { status : int; code : string; message : string }
      (** HTTP error from the API *)
  | Json_error of { reason : string }  (** JSON parsing or encoding error *)

(** Eio error type extension *)
type Eio.Exn.err += E of error

val err : error -> exn
(** [err e] creates an Eio exception from an error.
    Usage: [raise (err (Api_error { status = 404; code = "not_found"; message = "..." }))] *)

val is_api_error : error -> bool
(** [is_api_error e] returns [true] if the error is an API error. *)

val is_not_found : error -> bool
(** [is_not_found e] returns [true] if the error is a 404 Not Found error. *)

val error_to_string : error -> string
(** [error_to_string e] returns a human-readable description of the error. *)

val pp_error : Format.formatter -> error -> unit
(** Pretty printer for errors. *)

(** {1 Client} *)

type t
(** The Karakeep client type. Wraps a Requests session with the base URL
    and authentication. *)

val create :
  sw:Eio.Switch.t ->
  env:< clock : _ Eio.Time.clock ; net : _ Eio.Net.t ; fs : Eio.Fs.dir_ty Eio.Path.t ; .. > ->
  base_url:string ->
  api_key:string ->
  t
(** [create ~sw ~env ~base_url ~api_key] creates a new Karakeep client.

    @param sw Switch for resource management
    @param env Eio environment providing clock and network
    @param base_url Base URL of the Karakeep instance (e.g., "https://hoard.recoil.org")
    @param api_key API key for authentication *)

(** {1 Bookmark Operations} *)

val fetch_bookmarks :
  t ->
  ?limit:int ->
  ?cursor:string ->
  ?include_content:bool ->
  ?archived:bool ->
  ?favourited:bool ->
  unit ->
  paginated_bookmarks
(** [fetch_bookmarks client ()] fetches a page of bookmarks.

    @param limit Number of bookmarks to fetch per page (default: 50)
    @param cursor Optional pagination cursor
    @param include_content Whether to include full content (default: true)
    @param archived Filter for archived bookmarks
    @param favourited Filter for favourited bookmarks
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_all_bookmarks :
  t ->
  ?page_size:int ->
  ?max_pages:int ->
  ?archived:bool ->
  ?favourited:bool ->
  unit ->
  bookmark list
(** [fetch_all_bookmarks client ()] fetches all bookmarks, handling pagination.

    @param page_size Number of bookmarks per page (default: 50)
    @param max_pages Maximum number of pages to fetch
    @param archived Filter for archived bookmarks
    @param favourited Filter for favourited bookmarks
    @raise Eio.Io with {!E} on API or network errors *)

val search_bookmarks :
  t ->
  query:string ->
  ?limit:int ->
  ?cursor:string ->
  ?include_content:bool ->
  unit ->
  paginated_bookmarks
(** [search_bookmarks client ~query ()] searches for bookmarks.

    @param query Search query string
    @param limit Number of results per page (default: 50)
    @param cursor Optional pagination cursor
    @param include_content Whether to include full content (default: true)
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_bookmark_details : t -> bookmark_id -> bookmark
(** [fetch_bookmark_details client id] fetches a single bookmark by ID.
    @raise Eio.Io with {!E} on API or network errors *)

val create_bookmark :
  t ->
  url:string ->
  ?title:string ->
  ?note:string ->
  ?summary:string ->
  ?favourited:bool ->
  ?archived:bool ->
  ?created_at:Ptime.t ->
  ?tags:string list ->
  unit ->
  bookmark
(** [create_bookmark client ~url ()] creates a new URL bookmark.

    @param url The URL to bookmark
    @param title Optional title
    @param note Optional note
    @param summary Optional summary
    @param favourited Whether to mark as favourite
    @param archived Whether to archive
    @param created_at Optional creation timestamp
    @param tags Optional list of tag names to add
    @raise Eio.Io with {!E} on API or network errors *)

val update_bookmark :
  t ->
  bookmark_id ->
  ?title:string ->
  ?note:string ->
  ?summary:string ->
  ?favourited:bool ->
  ?archived:bool ->
  unit ->
  bookmark
(** [update_bookmark client id ()] updates a bookmark.
    @raise Eio.Io with {!E} on API or network errors *)

val delete_bookmark : t -> bookmark_id -> unit
(** [delete_bookmark client id] deletes a bookmark.
    @raise Eio.Io with {!E} on API or network errors *)

val summarize_bookmark : t -> bookmark_id -> summarize_response
(** [summarize_bookmark client id] generates an AI summary for a bookmark.
    Returns a response containing the summary text.
    @raise Eio.Io with {!E} on API or network errors *)

(** {1 Tag Operations} *)

val attach_tags :
  t -> tag_refs:[ `TagId of tag_id | `TagName of string ] list -> bookmark_id -> tag_id list
(** [attach_tags client ~tag_refs bookmark_id] attaches tags to a bookmark.
    @raise Eio.Io with {!E} on API or network errors *)

val detach_tags :
  t -> tag_refs:[ `TagId of tag_id | `TagName of string ] list -> bookmark_id -> tag_id list
(** [detach_tags client ~tag_refs bookmark_id] detaches tags from a bookmark.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_all_tags : t -> tag list
(** [fetch_all_tags client] fetches all tags.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_tag_details : t -> tag_id -> tag
(** [fetch_tag_details client id] fetches a single tag by ID.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_bookmarks_with_tag :
  t ->
  ?limit:int ->
  ?cursor:string ->
  ?include_content:bool ->
  tag_id ->
  paginated_bookmarks
(** [fetch_bookmarks_with_tag client tag_id] fetches bookmarks with a tag.
    @raise Eio.Io with {!E} on API or network errors *)

val update_tag : t -> name:string -> tag_id -> tag
(** [update_tag client ~name tag_id] updates a tag's name.
    @raise Eio.Io with {!E} on API or network errors *)

val delete_tag : t -> tag_id -> unit
(** [delete_tag client id] deletes a tag.
    @raise Eio.Io with {!E} on API or network errors *)

(** {1 List Operations} *)

val fetch_all_lists : t -> _list list
(** [fetch_all_lists client] fetches all lists.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_list_details : t -> list_id -> _list
(** [fetch_list_details client id] fetches a single list by ID.
    @raise Eio.Io with {!E} on API or network errors *)

val create_list :
  t ->
  name:string ->
  icon:string ->
  ?description:string ->
  ?parent_id:list_id ->
  ?list_type:list_type ->
  ?query:string ->
  unit ->
  _list
(** [create_list client ~name ~icon ()] creates a new list.
    @raise Eio.Io with {!E} on API or network errors *)

val update_list :
  t ->
  ?name:string ->
  ?description:string ->
  ?icon:string ->
  ?parent_id:list_id option ->
  ?query:string ->
  list_id ->
  _list
(** [update_list client list_id] updates a list.
    @raise Eio.Io with {!E} on API or network errors *)

val delete_list : t -> list_id -> unit
(** [delete_list client id] deletes a list.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_bookmarks_in_list :
  t ->
  ?limit:int ->
  ?cursor:string ->
  ?include_content:bool ->
  list_id ->
  paginated_bookmarks
(** [fetch_bookmarks_in_list client list_id] fetches bookmarks in a list.
    @raise Eio.Io with {!E} on API or network errors *)

val add_bookmark_to_list : t -> list_id -> bookmark_id -> unit
(** [add_bookmark_to_list client list_id bookmark_id] adds a bookmark to a list.
    @raise Eio.Io with {!E} on API or network errors *)

val remove_bookmark_from_list : t -> list_id -> bookmark_id -> unit
(** [remove_bookmark_from_list client list_id bookmark_id] removes a bookmark from a list.
    @raise Eio.Io with {!E} on API or network errors *)

(** {1 Highlight Operations} *)

val fetch_all_highlights :
  t -> ?limit:int -> ?cursor:string -> unit -> paginated_highlights
(** [fetch_all_highlights client ()] fetches all highlights with pagination.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_bookmark_highlights : t -> bookmark_id -> highlight list
(** [fetch_bookmark_highlights client bookmark_id] fetches highlights for a bookmark.
    @raise Eio.Io with {!E} on API or network errors *)

val fetch_highlight_details : t -> highlight_id -> highlight
(** [fetch_highlight_details client id] fetches a single highlight by ID.
    @raise Eio.Io with {!E} on API or network errors *)

val create_highlight :
  t ->
  bookmark_id:bookmark_id ->
  start_offset:int ->
  end_offset:int ->
  text:string ->
  ?note:string ->
  ?color:highlight_color ->
  unit ->
  highlight
(** [create_highlight client ~bookmark_id ~start_offset ~end_offset ~text ()]
    creates a new highlight.
    @raise Eio.Io with {!E} on API or network errors *)

val update_highlight : t -> ?color:highlight_color -> highlight_id -> highlight
(** [update_highlight client highlight_id] updates a highlight.
    @raise Eio.Io with {!E} on API or network errors *)

val delete_highlight : t -> highlight_id -> unit
(** [delete_highlight client id] deletes a highlight.
    @raise Eio.Io with {!E} on API or network errors *)

(** {1 Asset Operations} *)

val fetch_asset : t -> asset_id -> string
(** [fetch_asset client id] fetches an asset's binary data.
    @raise Eio.Io with {!E} on API or network errors *)

val get_asset_url : t -> asset_id -> string
(** [get_asset_url client id] returns the URL for an asset. Pure function. *)

val attach_asset :
  t -> asset_id:asset_id -> asset_type:asset_type -> bookmark_id -> asset
(** [attach_asset client ~asset_id ~asset_type bookmark_id] attaches an asset.
    @raise Eio.Io with {!E} on API or network errors *)

val replace_asset : t -> new_asset_id:asset_id -> bookmark_id -> asset_id -> unit
(** [replace_asset client ~new_asset_id bookmark_id asset_id] replaces an asset.
    @raise Eio.Io with {!E} on API or network errors *)

val detach_asset : t -> bookmark_id -> asset_id -> unit
(** [detach_asset client bookmark_id asset_id] detaches an asset.
    @raise Eio.Io with {!E} on API or network errors *)

(** {1 User Operations} *)

val get_current_user : t -> user_info
(** [get_current_user client] gets the current user's info.
    @raise Eio.Io with {!E} on API or network errors *)

val get_user_stats : t -> user_stats
(** [get_user_stats client] gets the current user's statistics.
    @raise Eio.Io with {!E} on API or network errors *)

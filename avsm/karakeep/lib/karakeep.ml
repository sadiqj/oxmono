(*---------------------------------------------------------------------------
  Copyright (c) 2025 Anil Madhavapeddy <anil@recoil.org>. All rights reserved.
  SPDX-License-Identifier: ISC
 ---------------------------------------------------------------------------*)

(** Karakeep API client implementation *)

include Karakeep_proto

(** {1 Logging} *)

let src = Logs.Src.create "karakeep" ~doc:"Karakeep API client"

module Log = (val Logs.src_log src : Logs.LOG)

(** {1 Error Handling} *)

type error =
  | Api_error of { status : int; code : string; message : string }
  | Json_error of { reason : string }

type Eio.Exn.err += E of error

let err e = Eio.Exn.create (E e)

let is_api_error = function Api_error _ -> true | _ -> false

let is_not_found = function
  | Api_error { status = 404; _ } -> true
  | _ -> false

let error_to_string = function
  | Api_error { status; code; message } ->
      Printf.sprintf "API error %d (%s): %s" status code message
  | Json_error { reason } -> Printf.sprintf "JSON error: %s" reason

let pp_error fmt e = Format.pp_print_string fmt (error_to_string e)

(** {1 Client} *)

type t = {
  session : Requests.t;
  base_url : string;
}

let create ~sw ~env ~base_url ~api_key =
  let session = Requests.create ~sw env in
  let session =
    Requests.set_auth session (Requests.Auth.bearer ~token:api_key)
  in
  { session; base_url }

(** {1 Internal Helpers} *)

let ( / ) base path =
  let base =
    if String.ends_with ~suffix:"/" base then
      String.sub base 0 (String.length base - 1)
    else base
  in
  let path =
    if String.starts_with ~prefix:"/" path then
      String.sub path 1 (String.length path - 1)
    else path
  in
  base ^ "/" ^ path

let query_string params =
  match params with
  | [] -> ""
  | _ ->
      "?"
      ^ String.concat "&"
          (List.map (fun (k, v) -> Uri.pct_encode k ^ "=" ^ Uri.pct_encode v) params)

(** Helpers for building query parameters *)

let add_param key f = function
  | None -> Fun.id
  | Some v -> fun params -> (key, f v) :: params

let add_opt key = add_param key Fun.id
let add_int key = add_param key string_of_int
let add_bool key = add_param key (function true -> "true" | false -> "false")

let decode_json codec body_str =
  match Jsont_bytesrw.decode_string' codec body_str with
  | Ok v -> v
  | Error e ->
      raise (err (Json_error { reason = Jsont.Error.to_string e }))

let encode_json codec value =
  match Jsont_bytesrw.encode_string' codec value with
  | Ok s -> s
  | Error e ->
      raise (err (Json_error { reason = Jsont.Error.to_string e }))

let handle_error_response status body =
  match Jsont_bytesrw.decode_string' error_response_jsont body with
  | Ok err_resp ->
      raise (err (Api_error { status; code = err_resp.code; message = err_resp.message }))
  | Error _ ->
      raise (err (Api_error { status; code = "unknown"; message = body }))

let get_json t url codec =
  let response = Requests.get t.session url in
  let body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) body;
  decode_json codec body

let post_json t url req_codec req_value resp_codec =
  let body_str = encode_json req_codec req_value in
  let body = Requests.Body.of_string Requests.Mime.json body_str in
  let response = Requests.post t.session url ~body in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body;
  decode_json resp_codec resp_body

let post_json_no_body t url resp_codec =
  let response = Requests.post t.session url in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body;
  decode_json resp_codec resp_body

let patch_json t url req_codec req_value resp_codec =
  let body_str = encode_json req_codec req_value in
  let body = Requests.Body.of_string Requests.Mime.json body_str in
  let response = Requests.patch t.session url ~body in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body;
  decode_json resp_codec resp_body

let delete_json t url =
  let response = Requests.delete t.session url in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body

let put_json t url req_codec req_value =
  let body_str = encode_json req_codec req_value in
  let body = Requests.Body.of_string Requests.Mime.json body_str in
  let response = Requests.put t.session url ~body in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body;
  resp_body

(** {1 Bookmark Operations} *)

let fetch_bookmarks t ?limit ?cursor ?include_content ?archived ?favourited () =
  let params =
    []
    |> add_int "limit" limit
    |> add_opt "cursor" cursor
    |> add_bool "includeContent" include_content
    |> add_bool "archived" archived
    |> add_bool "favourited" favourited
  in
  let url = t.base_url / "api/v1/bookmarks" ^ query_string params in
  get_json t url paginated_bookmarks_jsont

let fetch_all_bookmarks t ?page_size ?max_pages ?archived ?favourited () =
  let limit = Option.value page_size ~default:50 in
  let rec fetch_all acc cursor pages_fetched =
    match max_pages with
    | Some max when pages_fetched >= max -> List.rev acc
    | _ ->
        let result = fetch_bookmarks t ~limit ?cursor ?archived ?favourited () in
        let acc = List.rev_append result.bookmarks acc in
        (match result.next_cursor with
         | None -> List.rev acc
         | Some c -> fetch_all acc (Some c) (pages_fetched + 1))
  in
  fetch_all [] None 0

let search_bookmarks t ~query ?limit ?cursor ?include_content () =
  let params =
    [ ("q", query) ]
    |> add_int "limit" limit
    |> add_opt "cursor" cursor
    |> add_bool "includeContent" include_content
  in
  let url = t.base_url / "api/v1/bookmarks/search" ^ query_string params in
  get_json t url paginated_bookmarks_jsont

let fetch_bookmark_details t bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id in
  get_json t url bookmark_jsont

let tag_ref_of_poly = function `TagId id -> TagId id | `TagName name -> TagName name

let rec create_bookmark t ~url ?title ?note ?summary ?favourited ?archived ?created_at
    ?tags () =
  let api_url = t.base_url / "api/v1/bookmarks" in
  let req : create_bookmark_request =
    {
      type_ = "link";
      url = Some url;
      text = None;
      title;
      note;
      summary;
      archived;
      favourited;
      created_at;
    }
  in
  let bookmark = post_json t api_url create_bookmark_request_jsont req bookmark_jsont in
  (* Attach tags if provided *)
  match tags with
  | None | Some [] -> bookmark
  | Some tag_names ->
      let tag_refs = List.map (fun n -> `TagName n) tag_names in
      let _ = attach_tags t ~tag_refs bookmark.id in
      (* Refetch the bookmark to get updated tags *)
      fetch_bookmark_details t bookmark.id

and attach_tags t ~tag_refs bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "tags" in
  let tags = List.map tag_ref_of_poly tag_refs in
  let req = { tags } in
  let resp = post_json t url attach_tags_request_jsont req attach_tags_response_jsont in
  resp.attached

let update_bookmark t bookmark_id ?title ?note ?summary ?favourited ?archived () =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id in
  let req : update_bookmark_request = { title; note; summary; archived; favourited } in
  patch_json t url update_bookmark_request_jsont req bookmark_jsont

let delete_bookmark t bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id in
  delete_json t url

let summarize_bookmark t bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "summarize" in
  post_json_no_body t url summarize_response_jsont

(** {1 Tag Operations} *)

let detach_tags t ~tag_refs bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "tags" in
  let tags = List.map tag_ref_of_poly tag_refs in
  let req = { tags } in
  (* DELETE with body - use request function directly *)
  let body_str = encode_json attach_tags_request_jsont req in
  let body = Requests.Body.of_string Requests.Mime.json body_str in
  let response = Requests.request t.session ~method_:`DELETE ~body url in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body;
  let resp = decode_json detach_tags_response_jsont resp_body in
  resp.detached

let fetch_all_tags t =
  let url = t.base_url / "api/v1/tags" in
  let resp = get_json t url tags_response_jsont in
  resp.tags

let fetch_tag_details t tag_id =
  let url = t.base_url / "api/v1/tags" / tag_id in
  get_json t url tag_jsont

let fetch_bookmarks_with_tag t ?limit ?cursor ?include_content tag_id =
  let params =
    []
    |> add_int "limit" limit
    |> add_opt "cursor" cursor
    |> add_bool "includeContent" include_content
  in
  let url = t.base_url / "api/v1/tags" / tag_id / "bookmarks" ^ query_string params in
  get_json t url paginated_bookmarks_jsont

let update_tag t ~name tag_id =
  let url = t.base_url / "api/v1/tags" / tag_id in
  let req : update_tag_request = { name } in
  patch_json t url update_tag_request_jsont req tag_jsont

let delete_tag t tag_id =
  let url = t.base_url / "api/v1/tags" / tag_id in
  delete_json t url

(** {1 List Operations} *)

let fetch_all_lists t =
  let url = t.base_url / "api/v1/lists" in
  let resp = get_json t url lists_response_jsont in
  resp.lists

let fetch_list_details t list_id =
  let url = t.base_url / "api/v1/lists" / list_id in
  get_json t url list_jsont

let create_list t ~name ~icon ?description ?parent_id ?list_type ?query () =
  let url = t.base_url / "api/v1/lists" in
  let type_ =
    match list_type with
    | Some Manual -> Some "manual"
    | Some Smart -> Some "smart"
    | None -> None
  in
  let req : create_list_request = { name; icon; description; parent_id; type_; query } in
  post_json t url create_list_request_jsont req list_jsont

let update_list t ?name ?description ?icon ?parent_id ?query list_id =
  let url = t.base_url / "api/v1/lists" / list_id in
  let req : update_list_request = { name; icon; description; parent_id; query } in
  patch_json t url update_list_request_jsont req list_jsont

let delete_list t list_id =
  let url = t.base_url / "api/v1/lists" / list_id in
  delete_json t url

let fetch_bookmarks_in_list t ?limit ?cursor ?include_content list_id =
  let params =
    []
    |> add_int "limit" limit
    |> add_opt "cursor" cursor
    |> add_bool "includeContent" include_content
  in
  let url = t.base_url / "api/v1/lists" / list_id / "bookmarks" ^ query_string params in
  get_json t url paginated_bookmarks_jsont

let add_bookmark_to_list t list_id bookmark_id =
  let url = t.base_url / "api/v1/lists" / list_id / "bookmarks" / bookmark_id in
  let response = Requests.put t.session url in
  let resp_body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) resp_body

let remove_bookmark_from_list t list_id bookmark_id =
  let url = t.base_url / "api/v1/lists" / list_id / "bookmarks" / bookmark_id in
  delete_json t url

(** {1 Highlight Operations} *)

let fetch_all_highlights t ?limit ?cursor () =
  let params =
    []
    |> add_int "limit" limit
    |> add_opt "cursor" cursor
  in
  let url = t.base_url / "api/v1/highlights" ^ query_string params in
  get_json t url paginated_highlights_jsont

let fetch_bookmark_highlights t bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "highlights" in
  let resp = get_json t url highlights_response_jsont in
  resp.highlights

let fetch_highlight_details t highlight_id =
  let url = t.base_url / "api/v1/highlights" / highlight_id in
  get_json t url highlight_jsont

let create_highlight t ~bookmark_id ~start_offset ~end_offset ~text ?note ?color () =
  let url = t.base_url / "api/v1/highlights" in
  let req : create_highlight_request =
    { bookmark_id; start_offset; end_offset; text; note; color }
  in
  post_json t url create_highlight_request_jsont req highlight_jsont

let update_highlight t ?color highlight_id =
  let url = t.base_url / "api/v1/highlights" / highlight_id in
  let req : update_highlight_request = { color } in
  patch_json t url update_highlight_request_jsont req highlight_jsont

let delete_highlight t highlight_id =
  let url = t.base_url / "api/v1/highlights" / highlight_id in
  delete_json t url

(** {1 Asset Operations} *)

let fetch_asset t asset_id =
  let url = t.base_url / "api/assets" / asset_id in
  let response = Requests.get t.session url in
  let body = Requests.Response.text response in
  if not (Requests.Response.ok response) then
    handle_error_response (Requests.Response.status_code response) body;
  body

let get_asset_url t asset_id = t.base_url / "api/assets" / asset_id

let attach_asset t ~asset_id ~asset_type bookmark_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "assets" in
  let req : attach_asset_request = { id = asset_id; asset_type } in
  post_json t url attach_asset_request_jsont req asset_jsont

let replace_asset t ~new_asset_id bookmark_id asset_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "assets" / asset_id in
  let req : replace_asset_request = { asset_id = new_asset_id } in
  let _ = put_json t url replace_asset_request_jsont req in
  ()

let detach_asset t bookmark_id asset_id =
  let url = t.base_url / "api/v1/bookmarks" / bookmark_id / "assets" / asset_id in
  delete_json t url

(** {1 User Operations} *)

let get_current_user t =
  let url = t.base_url / "api/v1/users/me" in
  get_json t url user_info_jsont

let get_user_stats t =
  let url = t.base_url / "api/v1/users/me/stats" in
  get_json t url user_stats_jsont

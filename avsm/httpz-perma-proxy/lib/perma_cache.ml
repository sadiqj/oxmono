(* Range tracking *)

type range = { start : int; stop : int }

let merge_range ranges new_range =
  (* Insert the new range and sweep to coalesce overlapping/adjacent intervals *)
  let merged = ref [] in
  let cur_start = ref new_range.start in
  let cur_stop = ref new_range.stop in
  let inserted = ref false in
  List.iter
    (fun r ->
      if !inserted then begin
        (* After insertion point, just append remaining *)
        merged := r :: !merged
      end else if r.stop < !cur_start then begin
        (* r is entirely before current; keep it *)
        merged := r :: !merged
      end else if r.start > !cur_stop then begin
        (* r is entirely after current; emit current, then r *)
        merged := r :: { start = !cur_start; stop = !cur_stop } :: !merged;
        inserted := true
      end else begin
        (* Overlap or adjacent: extend current *)
        cur_start := min !cur_start r.start;
        cur_stop := max !cur_stop r.stop
      end)
    ranges;
  if not !inserted then
    merged := { start = !cur_start; stop = !cur_stop } :: !merged;
  List.rev !merged

let is_range_cached ranges ~start ~len =
  let stop = start + len in
  List.exists (fun r -> r.start <= start && stop <= r.stop) ranges

let is_complete ranges ~total_len =
  match ranges with
  | [ r ] -> r.start = 0 && r.stop >= total_len
  | _ -> false

(* Metadata *)

type meta = {
  content_length : int;
  content_type : string;
  headers : (string * string) list;
  ranges : range list;
  complete : bool;
}

(* JSON type descriptors using jsont *)

let range_jsont : range Jsont.t =
  Jsont.Object.map ~kind:"Range" (fun start stop -> { start; stop })
  |> Jsont.Object.mem "start" Jsont.int ~enc:(fun r -> r.start)
  |> Jsont.Object.mem "stop" Jsont.int ~enc:(fun r -> r.stop)
  |> Jsont.Object.finish

let header_pair_jsont : (string * string) Jsont.t =
  Jsont.Object.map ~kind:"HeaderPair" (fun k v -> (k, v))
  |> Jsont.Object.mem "name" Jsont.string ~enc:(fun (k, _) -> k)
  |> Jsont.Object.mem "value" Jsont.string ~enc:(fun (_, v) -> v)
  |> Jsont.Object.finish

let meta_jsont : meta Jsont.t =
  Jsont.Object.map ~kind:"Meta"
    (fun content_length content_type headers ranges complete ->
      { content_length; content_type; headers; ranges; complete })
  |> Jsont.Object.mem "content_length" Jsont.int
       ~enc:(fun m -> m.content_length)
  |> Jsont.Object.mem "content_type" Jsont.string
       ~enc:(fun m -> m.content_type)
  |> Jsont.Object.mem "headers" (Jsont.list header_pair_jsont)
       ~enc:(fun m -> m.headers)
       ~dec_absent:[]
  |> Jsont.Object.mem "ranges" (Jsont.list range_jsont)
       ~enc:(fun m -> m.ranges)
       ~dec_absent:[]
  |> Jsont.Object.mem "complete" Jsont.bool
       ~enc:(fun m -> m.complete)
       ~dec_absent:false
  |> Jsont.Object.finish

(* Filesystem helpers *)

let ensure_parent_dirs (fs : Eio.Fs.dir_ty Eio.Path.t) path =
  let dir = Filename.dirname path in
  if dir <> "." && dir <> "/" then
    Eio.Path.mkdirs ~exists_ok:true ~perm:0o755 Eio.Path.(fs / dir)

let read_meta fs key =
  let path = key ^ ".meta" in
  match Eio.Path.load Eio.Path.(fs / path) with
  | contents ->
    (match Jsont_bytesrw.decode_string meta_jsont contents with
     | Ok meta -> Some meta
     | Error _msg -> None)
  | exception _exn -> None

let write_meta fs key meta =
  let path = key ^ ".meta" in
  ensure_parent_dirs fs path;
  match Jsont_bytesrw.encode_string ~format:Jsont.Indent meta_jsont meta with
  | Ok json_str ->
    Eio.Path.save ~create:(`Or_truncate 0o644) Eio.Path.(fs / path) json_str
  | Error msg -> failwith ("write_meta: " ^ msg)

(* Cache file I/O *)

let cache_path ~host ~url_path =
  (* Strip leading slash from url_path, use host as top-level directory *)
  let trimmed =
    if String.length url_path > 0 && url_path.[0] = '/' then
      String.sub url_path 1 (String.length url_path - 1)
    else url_path
  in
  let path = if trimmed = "" then "index" else trimmed in
  host ^ "/" ^ path

let data_file_path (fs : Eio.Fs.dir_ty Eio.Path.t) key =
  let path = key ^ ".data" in
  let full = Eio.Path.native_exn Eio.Path.(fs / path) in
  (path, full)

let write_data fs key ~off data =
  let path, full = data_file_path fs key in
  ensure_parent_dirs fs path;
  let fd =
    Unix.openfile full
      [ Unix.O_WRONLY; Unix.O_CREAT ]
      0o644
  in
  Fun.protect
    ~finally:(fun () -> Unix.close fd)
    (fun () ->
      let (_ : int) = Unix.lseek fd off Unix.SEEK_SET in
      let len = String.length data in
      let written = ref 0 in
      while !written < len do
        let n =
          Unix.write_substring fd data !written (len - !written)
        in
        written := !written + n
      done)

let read_data fs key ~off ~len =
  let _path, full = data_file_path fs key in
  let fd = Unix.openfile full [ Unix.O_RDONLY ] 0 in
  Fun.protect
    ~finally:(fun () -> Unix.close fd)
    (fun () ->
      let (_ : int) = Unix.lseek fd off Unix.SEEK_SET in
      let buf = Bytes.create len in
      let nread = ref 0 in
      while !nread < len do
        let n = Unix.read fd buf !nread (len - !nread) in
        if n = 0 then failwith "read_data: unexpected EOF";
        nread := !nread + n
      done;
      Bytes.to_string buf)

let write_file fs path contents =
  ensure_parent_dirs fs path;
  Eio.Path.save ~create:(`Or_truncate 0o644) Eio.Path.(fs / path) contents

let read_file fs path =
  Eio.Path.load Eio.Path.(fs / path)

(* Range header parsing *)

let parse_range_header s =
  (* Parse "bytes=START-END" or "bytes=START-" *)
  let prefix = "bytes=" in
  let prefix_len = String.length prefix in
  if String.length s < prefix_len then None
  else if String.sub s 0 prefix_len <> prefix then None
  else begin
    let rest = String.sub s prefix_len (String.length s - prefix_len) in
    match String.index_opt rest '-' with
    | None -> None
    | Some dash_pos ->
      let start_str = String.sub rest 0 dash_pos in
      let end_str =
        String.sub rest (dash_pos + 1)
          (String.length rest - dash_pos - 1)
      in
      (match int_of_string_opt start_str with
       | None -> None
       | Some start_val ->
         if end_str = "" then Some (start_val, None)
         else
           match int_of_string_opt end_str with
           | None -> None
           | Some end_val -> Some (start_val, Some end_val))
  end

(* URL mapping *)

type url_map = {
  prefix : string;
  upstream : string;
  upstream_host : string;
}

let parse_map s =
  match String.index_opt s '=' with
  | None -> None
  | Some eq_pos ->
    let prefix = String.sub s 0 eq_pos in
    let upstream = String.sub s (eq_pos + 1) (String.length s - eq_pos - 1) in
    (* Extract host from upstream URL *)
    let host =
      (* Strip scheme: "https://host/path" -> "host/path" *)
      let after_scheme =
        match String.index_opt upstream ':' with
        | None -> upstream
        | Some colon_pos ->
          let rest = String.sub upstream (colon_pos + 1)
              (String.length upstream - colon_pos - 1) in
          (* Skip "//" after scheme *)
          if String.length rest >= 2
             && rest.[0] = '/' && rest.[1] = '/' then
            String.sub rest 2 (String.length rest - 2)
          else rest
      in
      (* Take up to first '/' *)
      match String.index_opt after_scheme '/' with
      | None -> after_scheme
      | Some slash_pos -> String.sub after_scheme 0 slash_pos
    in
    Some { prefix; upstream; upstream_host = host }

let find_map maps request_path =
  let rec try_maps = function
    | [] -> None
    | map :: rest ->
      let prefix_len = String.length map.prefix in
      if prefix_len <= String.length request_path
         && String.sub request_path 0 prefix_len = map.prefix then
        let suffix = String.sub request_path prefix_len
            (String.length request_path - prefix_len) in
        Some (map, suffix)
      else
        try_maps rest
  in
  try_maps maps

(* Content-Range header parsing *)

let parse_content_range s =
  (* Parse "bytes START-END/TOTAL" -> Some total *)
  let prefix = "bytes " in
  let prefix_len = String.length prefix in
  if String.length s < prefix_len then None
  else if String.sub s 0 prefix_len <> prefix then None
  else begin
    let rest = String.sub s prefix_len (String.length s - prefix_len) in
    match String.index_opt rest '/' with
    | None -> None
    | Some slash_pos ->
      let total_str = String.sub rest (slash_pos + 1)
          (String.length rest - slash_pos - 1) in
      if total_str = "*" then None
      else int_of_string_opt total_str
  end

(* Map header name strings to Httpz.Header_name.t *)

let header_name_of_string s =
  match String.lowercase_ascii s with
  | "content-type" -> Httpz.Header_name.Content_type
  | "content-length" -> Httpz.Header_name.Content_length
  | "content-range" -> Httpz.Header_name.Content_range
  | "accept-ranges" -> Httpz.Header_name.Accept_ranges
  | "etag" -> Httpz.Header_name.Etag
  | "last-modified" -> Httpz.Header_name.Last_modified
  | "cache-control" -> Httpz.Header_name.Cache_control
  | "content-encoding" -> Httpz.Header_name.Content_encoding
  | "content-disposition" -> Httpz.Header_name.Content_disposition
  | "vary" -> Httpz.Header_name.Vary
  | "access-control-allow-origin" -> Httpz.Header_name.Access_control_allow_origin
  | _ -> Httpz.Header_name.Other

(* Build response headers from metadata *)

let cors_headers =
  [ (Httpz.Header_name.Access_control_allow_origin, "*");
    (Httpz.Header_name.Access_control_allow_methods, "GET, HEAD, OPTIONS");
    (Httpz.Header_name.Access_control_allow_headers, "Range") ]

let resp_headers_of_meta meta =
  let mapped = List.filter_map (fun (name, value) ->
    let hn = header_name_of_string name in
    (* Skip Other headers since they cannot be serialized *)
    if hn = Httpz.Header_name.Other then None
    else Some (hn, value))
    meta.headers
  in
  mapped @ cors_headers

(* Upstream URL path portion for cache key computation *)

let url_path_of_upstream upstream =
  (* Extract path from "https://host/path" -> "/path" *)
  match String.index_opt upstream ':' with
  | None -> upstream
  | Some colon_pos ->
    let rest = String.sub upstream (colon_pos + 1)
        (String.length upstream - colon_pos - 1) in
    let after_scheme =
      if String.length rest >= 2 && rest.[0] = '/' && rest.[1] = '/' then
        String.sub rest 2 (String.length rest - 2)
      else rest
    in
    match String.index_opt after_scheme '/' with
    | None -> "/"
    | Some slash_pos ->
      String.sub after_scheme slash_pos
        (String.length after_scheme - slash_pos)

(* Response type returned by handle_request *)

type response = {
  status : Httpz.Res.status;
  resp_headers : Httpz_server.Route.resp_header list;
  body : Httpz_server.Route.body;
}

(* Handle HEAD requests *)

let handle_head ~(fs : Eio.Fs.dir_ty Eio.Path.t) ~session ~cp ~upstream_url =
  (* Try to serve from cached .meta *)
  match read_meta fs cp with
  | Some meta ->
    let headers =
      (Httpz.Header_name.Content_length, string_of_int meta.content_length)
      :: (Httpz.Header_name.Content_type, meta.content_type)
      :: (Httpz.Header_name.Accept_ranges, "bytes")
      :: cors_headers
    in
    { status = Httpz.Res.Success; resp_headers = headers;
      body = Httpz_server.Route.Empty }
  | None ->
    (* Fetch upstream HEAD and cache .meta *)
    (try
       let resp = Requests.head session upstream_url in
       let status_code = Requests.Response.status_code resp in
       let status = match Httpz.Res.status_of_int status_code with
         | Some s -> s
         | None -> Httpz.Res.Bad_gateway
       in
       let ct = match Requests.Response.header_string "content-type" resp with
         | Some s -> s | None -> "application/octet-stream" in
       let cl = match Requests.Response.header_string "content-length" resp with
         | Some s -> (match int_of_string_opt s with Some n -> n | None -> 0)
         | None -> 0 in
       (* Collect interesting upstream headers for .meta *)
       let resp_headers = Requests.Response.headers resp in
       let header_pairs =
         List.filter_map (fun (name, value) ->
           let ln = String.lowercase_ascii name in
           match ln with
           | "content-type" | "etag" | "last-modified" | "cache-control"
           | "accept-ranges" | "content-encoding" | "content-disposition"
           | "vary" -> Some (ln, value)
           | _ -> None)
           (Requests.Headers.to_list resp_headers)
       in
       (* Persist .meta so subsequent HEAD/GET can serve from cache *)
       let meta = {
         content_length = cl; content_type = ct;
         headers = header_pairs; ranges = []; complete = false;
       } in
       write_meta fs cp meta;
       let headers =
         (Httpz.Header_name.Content_length, string_of_int cl)
         :: (Httpz.Header_name.Content_type, ct)
         :: (Httpz.Header_name.Accept_ranges, "bytes")
         :: cors_headers
       in
       { status; resp_headers = headers; body = Httpz_server.Route.Empty }
     with exn ->
       let msg = Printexc.to_string exn in
       { status = Httpz.Res.Bad_gateway; resp_headers = cors_headers;
         body = Httpz_server.Route.String ("Upstream error: " ^ msg) })

(* Fetch full resource from upstream and cache it *)

let fetch_and_cache_full ~(fs : Eio.Fs.dir_ty Eio.Path.t) ~session ~cp
    ~upstream_url ~verbose =
  let resp = Requests.get session upstream_url in
  let status_code = Requests.Response.status_code resp in
  let body = Requests.Response.text resp in
  let body_len = String.length body in
  let content_type =
    match Requests.Response.header_string "content-type" resp with
    | Some ct -> ct
    | None -> "application/octet-stream"
  in
  (* Collect interesting upstream headers *)
  let resp_headers = Requests.Response.headers resp in
  let header_pairs =
    List.filter_map (fun (name, value) ->
      let ln = String.lowercase_ascii name in
      match ln with
      | "content-type" | "etag" | "last-modified" | "cache-control"
      | "accept-ranges" | "content-encoding" | "content-disposition"
      | "vary" ->
        Some (ln, value)
      | _ -> None)
      (Requests.Headers.to_list resp_headers)
  in
  if verbose then
    Printf.printf "    fetched %d bytes (status %d)\n%!" body_len status_code;
  (* Write data and meta *)
  write_data fs cp ~off:0 body;
  let meta = {
    content_length = body_len;
    content_type;
    headers = header_pairs;
    ranges = [ { start = 0; stop = body_len } ];
    complete = true;
  } in
  write_meta fs cp meta;
  (meta, body, status_code)

(* Fetch a range from upstream *)

let fetch_and_cache_range ~(fs : Eio.Fs.dir_ty Eio.Path.t) ~session ~cp
    ~upstream_url ~range_start ~range_end ~verbose =
  let headers =
    Requests.Headers.empty
    |> Requests.Headers.range
         ~start:(Int64.of_int range_start)
         ?end_:(Option.map Int64.of_int range_end)
         ()
  in
  let resp = Requests.get session ~headers upstream_url in
  let status_code = Requests.Response.status_code resp in
  let body = Requests.Response.text resp in
  let body_len = String.length body in
  if verbose then
    Printf.printf "    range response: %d bytes (status %d)\n%!" body_len status_code;
  (* Determine the actual range we got *)
  let actual_start, actual_end, total_size =
    if status_code = 206 then begin
      (* Parse Content-Range header *)
      let total = match Requests.Response.header_string "content-range" resp with
        | Some cr -> parse_content_range cr
        | None -> None
      in
      let total_size = match total with
        | Some t -> t
        | None ->
          (* Fallback: use content-length from upstream or body length *)
          match Requests.Response.header_string "content-length" resp with
          | Some cl -> (match int_of_string_opt cl with Some n -> n | None -> body_len)
          | None -> body_len
      in
      (range_start, range_start + body_len, total_size)
    end else begin
      (* Server returned 200 instead of 206 — full body *)
      (0, body_len, body_len)
    end
  in
  let content_type =
    match Requests.Response.header_string "content-type" resp with
    | Some ct -> ct
    | None -> "application/octet-stream"
  in
  let resp_headers = Requests.Response.headers resp in
  let header_pairs =
    List.filter_map (fun (name, value) ->
      let ln = String.lowercase_ascii name in
      match ln with
      | "content-type" | "etag" | "last-modified" | "cache-control"
      | "accept-ranges" | "content-encoding" | "content-disposition"
      | "vary" ->
        Some (ln, value)
      | _ -> None)
      (Requests.Headers.to_list resp_headers)
  in
  (* Write data at the actual offset *)
  write_data fs cp ~off:actual_start body;
  (* Update meta *)
  let existing_meta = read_meta fs cp in
  let old_ranges = match existing_meta with
    | Some m -> m.ranges
    | None -> []
  in
  let new_ranges = merge_range old_ranges
      { start = actual_start; stop = actual_end } in
  let is_complete = status_code = 200 || is_complete new_ranges ~total_len:total_size in
  let meta = {
    content_length = total_size;
    content_type;
    headers = header_pairs;
    ranges = new_ranges;
    complete = is_complete;
  } in
  write_meta fs cp meta;
  (meta, body, actual_start, actual_end, total_size, status_code)

(* Main handler — returns a response tuple *)

let handle_request ~(fs : Eio.Fs.dir_ty Eio.Path.t) ~cache_dir ~session ~maps
    ~verbose ~path ~is_head ~range_header =
  match find_map maps path with
  | None ->
    { status = Httpz.Res.Not_found; resp_headers = cors_headers;
      body = Httpz_server.Route.String "Not Found" }
  | Some (map, suffix) ->
    let upstream_url = map.upstream ^ suffix in
    let upstream_path = url_path_of_upstream map.upstream in
    let url_path =
      if String.length upstream_path > 1 then
        upstream_path ^ suffix
      else
        suffix
    in
    let cp = cache_dir ^ "/" ^ cache_path ~host:map.upstream_host ~url_path in
    if verbose then
      Printf.printf "  -> upstream: %s  cache: %s\n%!" upstream_url cp;
    if is_head then
      handle_head ~fs ~session ~cp ~upstream_url
    else begin
      match range_header with
      | None ->
        (* Full GET — serve from cache if complete, else fetch *)
        (match read_meta fs cp with
         | Some meta when meta.complete ->
           if verbose then
             Printf.printf "    cache HIT (complete, %d bytes)\n%!" meta.content_length;
           let body = read_data fs cp ~off:0 ~len:meta.content_length in
           let headers =
             (Httpz.Header_name.Content_length, string_of_int meta.content_length)
             :: (Httpz.Header_name.Content_type, meta.content_type)
             :: (Httpz.Header_name.Accept_ranges, "bytes")
             :: resp_headers_of_meta meta
           in
           { status = Httpz.Res.Success; resp_headers = headers;
             body = Httpz_server.Route.String body }
         | _ ->
           if verbose then
             Printf.printf "    cache MISS, fetching full\n%!";
           (try
              let (meta, body, status_code) =
                fetch_and_cache_full ~fs ~session ~cp ~upstream_url ~verbose in
              let status = match Httpz.Res.status_of_int status_code with
                | Some s -> s
                | None -> Httpz.Res.Success
              in
              let headers =
                (Httpz.Header_name.Content_length, string_of_int meta.content_length)
                :: (Httpz.Header_name.Content_type, meta.content_type)
                :: (Httpz.Header_name.Accept_ranges, "bytes")
                :: cors_headers
              in
              { status; resp_headers = headers;
                body = Httpz_server.Route.String body }
            with exn ->
              let msg = Printexc.to_string exn in
              { status = Httpz.Res.Bad_gateway; resp_headers = cors_headers;
                body = Httpz_server.Route.String ("Upstream error: " ^ msg) }))
      | Some range_str ->
        (* Range GET *)
        (match parse_range_header range_str with
         | None ->
           { status = Httpz.Res.Bad_request; resp_headers = cors_headers;
             body = Httpz_server.Route.String "Invalid Range header" }
         | Some (range_start, range_end_opt) ->
           let cached_meta = read_meta fs cp in
           let range_end = match range_end_opt with
             | Some e -> e
             | None ->
               (match cached_meta with
                | Some meta when meta.content_length > 0 ->
                  meta.content_length - 1
                | _ -> max_int)
           in
           let range_len = range_end - range_start + 1 in
           let can_serve_from_cache =
             match cached_meta with
             | Some meta ->
               range_end < max_int
               && is_range_cached meta.ranges ~start:range_start ~len:range_len
             | None -> false
           in
           if can_serve_from_cache then begin
             let meta = match cached_meta with Some m -> m | None -> assert false in
             if verbose then
               Printf.printf "    cache HIT (range %d-%d)\n%!" range_start range_end;
             let body = read_data fs cp ~off:range_start ~len:range_len in
             let content_range =
               Printf.sprintf "bytes %d-%d/%d" range_start range_end
                 meta.content_length
             in
             let headers =
               (Httpz.Header_name.Content_length, string_of_int range_len)
               :: (Httpz.Header_name.Content_type, meta.content_type)
               :: (Httpz.Header_name.Content_range, content_range)
               :: (Httpz.Header_name.Accept_ranges, "bytes")
               :: cors_headers
             in
             { status = Httpz.Res.Partial_content; resp_headers = headers;
               body = Httpz_server.Route.String body }
           end else begin
             if verbose then
               Printf.printf "    cache MISS (range %d-%d), fetching\n%!"
                 range_start range_end;
             try
               let (meta', body, actual_start, actual_end, total_size,
                    status_code) =
                 fetch_and_cache_range ~fs ~session ~cp ~upstream_url
                   ~range_start ~range_end:(Some range_end) ~verbose
               in
               if status_code = 200 then begin
                 let headers =
                   (Httpz.Header_name.Content_length,
                    string_of_int (String.length body))
                   :: (Httpz.Header_name.Content_type, meta'.content_type)
                   :: (Httpz.Header_name.Accept_ranges, "bytes")
                   :: cors_headers
                 in
                 { status = Httpz.Res.Success; resp_headers = headers;
                   body = Httpz_server.Route.String body }
               end else begin
                 let content_range =
                   Printf.sprintf "bytes %d-%d/%d" actual_start
                     (actual_end - 1) total_size
                 in
                 let headers =
                   (Httpz.Header_name.Content_length,
                    string_of_int (String.length body))
                   :: (Httpz.Header_name.Content_type, meta'.content_type)
                   :: (Httpz.Header_name.Content_range, content_range)
                   :: (Httpz.Header_name.Accept_ranges, "bytes")
                   :: cors_headers
                 in
                 { status = Httpz.Res.Partial_content; resp_headers = headers;
                   body = Httpz_server.Route.String body }
               end
             with exn ->
               let msg = Printexc.to_string exn in
               { status = Httpz.Res.Bad_gateway; resp_headers = cors_headers;
                 body = Httpz_server.Route.String ("Upstream error: " ^ msg) }
           end)
    end

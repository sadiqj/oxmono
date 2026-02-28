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

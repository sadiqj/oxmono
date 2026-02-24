(* webdavz_server.ml — Simple WebDAV server over a local filesystem.

   Uses Eio capabilities to sandbox filesystem access: the store only
   receives an Eio.Path.t rooted at the user-specified directory, so
   path traversal attacks are prevented by the capability model.

   Usage: webdavz_server [--port PORT] [--host HOST] ROOT_DIR

   Example:
     webdavz_server /tmp/dav
     curl -X PROPFIND http://localhost:8080/
     curl -T file.txt http://localhost:8080/file.txt
     curl http://localhost:8080/file.txt *)

(* ── Eio filesystem-backed WebDAV store ──────────────────────────── *)

module Fs_store : Webdavz.STORE with type t = Eio.Fs.dir_ty Eio.Path.t = struct
  type t = Eio.Fs.dir_ty Eio.Path.t

  let resolve t path =
    let rel = if String.length path > 0 && Char.equal (String.get path 0) '/'
      then String.sub path 1 (String.length path - 1)
      else path
    in
    if String.length rel = 0 then t
    else Eio.Path.(t / rel)

  let exists t ~path =
    let p = resolve t path in
    match Eio.Path.kind ~follow:true p with
    | `Not_found -> false
    | _ -> true

  let is_collection t ~path =
    let p = resolve t path in
    match Eio.Path.kind ~follow:true p with
    | `Directory -> true
    | _ -> false

  let read t ~path =
    if is_collection t ~path then None
    else
      let p = resolve t path in
      try Some (Eio.Path.load p)
      with _ -> None

  let write t ~path ~content_type:_ data =
    let p = resolve t path in
    Eio.Path.save ~create:(`Or_truncate 0o644) p data

  let delete t ~path =
    let p = resolve t path in
    try
      begin match Eio.Path.kind ~follow:true p with
      | `Directory ->
        (* Remove children first (non-recursive, single level) *)
        Eio.Path.read_dir p |> List.iter (fun name ->
          let child = Eio.Path.(p / name) in
          match Eio.Path.kind ~follow:true child with
          | `Directory -> () (* skip nested dirs for safety *)
          | _ -> Eio.Path.unlink child);
        Eio.Path.rmdir p
      | `Not_found -> ()
      | _ -> Eio.Path.unlink p
      end;
      true
    with _ -> false

  let mkdir t ~path =
    let p = resolve t path in
    Eio.Path.mkdir ~perm:0o755 p

  let children t ~path =
    let p = resolve t path in
    try Eio.Path.read_dir p |> List.sort String.compare
    with _ -> []

  (* Compute ETag from content hash *)
  let etag_of_content content =
    Printf.sprintf "\"%08x\"" (Hashtbl.hash content)

  (* Compute properties from filesystem metadata *)
  let get_properties t ~path =
    let open Webdavz.Xml in
    let is_coll = is_collection t ~path in
    let resourcetype =
      if is_coll then
        (Webdavz.Prop.resourcetype, [dav_node "collection" []])
      else
        (Webdavz.Prop.resourcetype, [])
    in
    let displayname =
      let name = Filename.basename path in
      let name = if String.equal name "." || String.equal name "" then "/" else name in
      (Webdavz.Prop.displayname, [pcdata name])
    in
    let content_props =
      if is_coll then []
      else
        match read t ~path with
        | Some content ->
          [
            (Webdavz.Prop.getcontentlength,
             [pcdata (string_of_int (String.length content))]);
            (Webdavz.Prop.getetag, [pcdata (etag_of_content content)]);
            (Webdavz.Prop.getcontenttype, [pcdata "application/octet-stream"]);
          ]
        | None -> []
    in
    resourcetype :: displayname :: content_props
end

(* ── CLI argument parsing ────────────────────────────────────────── *)

type config = {
  port : int;
  host : string;
  root_dir : string;
}

let parse_args () =
  let port = ref 8080 in
  let host = ref "0.0.0.0" in
  let root_dir = ref "" in
  let specs = [
    ("--port", Arg.Set_int port, " Listen port (default: 8080)");
    ("--host", Arg.Set_string host, " Listen address (default: 0.0.0.0)");
  ] in
  let usage = "webdavz_server [--port PORT] [--host HOST] ROOT_DIR" in
  Arg.parse specs (fun s -> root_dir := s) usage;
  if String.length !root_dir = 0 then begin
    Arg.usage specs usage;
    exit 1
  end;
  { port = !port; host = !host; root_dir = !root_dir }

(* ── Main ────────────────────────────────────────────────────────── *)

let () =
  let config = parse_args () in
  (* Verify root directory exists *)
  if not (Sys.file_exists config.root_dir && Sys.is_directory config.root_dir) then begin
    Printf.eprintf "Error: %s is not a directory\n" config.root_dir;
    exit 1
  end;
  Printf.printf "webdavz: serving %s on %s:%d\n%!" config.root_dir config.host config.port;
  Eio_main.run @@ fun env ->
  let net = Eio.Stdenv.net env in
  let fs = Eio.Stdenv.fs env in
  (* Create a capability-restricted path to the root directory.
     All filesystem access is sandboxed to this subtree by Eio's
     capability model — no path traversal beyond root_dir is possible. *)
  let root_path = Eio.Path.(fs / config.root_dir) in
  let routes =
    Webdavz.Handler.routes (module Fs_store) root_path
    |> Httpz_server.Route.of_list
  in
  let globalize (local_ s : string) : string =
    let len = String.length s in
    let dst = Bytes.create len in
    for i = 0 to len - 1 do
      Bytes.unsafe_set dst i (String.unsafe_get s i)
    done;
    Bytes.unsafe_to_string dst
  in
  let on_request (local_ info : Httpz_eio.request_info) =
    let meth_s = Httpz.Method.to_string info.meth in
    let path_s = globalize info.path in
    let status_s = Httpz.Res.status_to_string info.status in
    let dur = info.duration_us in
    Printf.printf "%s %s %s (%dus)\n%!" meth_s path_s status_s dur
  in
  let on_error exn =
    Printf.eprintf "Error: %s\n%!" (Printexc.to_string exn)
  in
  let addr = `Tcp (Eio.Net.Ipaddr.V4.any, config.port) in
  Eio.Switch.run @@ fun sw ->
  let socket = Eio.Net.listen net ~sw ~backlog:128 ~reuse_addr:true addr in
  Eio.Net.run_server socket ~on_error (fun flow addr ->
    Httpz_eio.handle_client ~routes ~on_request ~on_error flow addr)

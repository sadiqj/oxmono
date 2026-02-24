(* webdavz_handler.ml - STORE module type + WebDAV route generation
   RFC 4918 — HTTP Extensions for Web Distributed Authoring and Versioning *)

open Webdavz_xml

module type RO_STORE = sig
  type t
  val is_collection : t -> path:string -> bool
  val exists : t -> path:string -> bool
  val get_properties : t -> path:string -> (fqname * tree list) list
  val read : t -> path:string -> string option
  val children : t -> path:string -> string list
end

module type STORE = sig
  include RO_STORE
  val write : t -> path:string -> content_type:string -> string -> unit
  val delete : t -> path:string -> bool
  val mkdir : t -> path:string -> unit
end

(* Respond with a DAV:error XML body (RFC 4918 Section 16) *)
let xml_error status element (local_ respond) =
  let open Httpz_server.Route in
  respond_string respond ~status
    ~headers:[(Httpz.Header_name.Content_type, "application/xml; charset=utf-8")]
    (serialize (error_xml element))

(* Compute parent path: "/foo/bar" -> "/foo", "/" -> "/" *)
let parent_path path =
  match String.rindex_opt path '/' with
  | None | Some 0 -> "/"
  | Some i -> String.sub path 0 i

(* Build PROPFIND responses for a resource and optionally its children.
   RFC 4918 Section 9.1 — PROPFIND *)
let propfind_response (type s) (module S : RO_STORE with type t = s) store ~path ~depth ~pf =
  let open Webdavz_response in
  let open Webdavz_request in
  if not (S.exists store ~path) then []
  else
    let make_response path =
      let all_props = S.get_properties store ~path in
      match pf with
      | Propname ->
        let prop_names = List.map (fun (name, _) ->
          empty_prop_node name) all_props
        in
        { href = path; propstats = [propstat_ok prop_names] }
      | Allprop _include ->
        let found = List.map (fun (name, values) ->
          prop_node name values) all_props
        in
        { href = path; propstats = [propstat_ok found] }
      | Props requested ->
        let found, not_found = List.partition_map (fun name ->
          match Webdavz_prop.find name all_props with
          | Some values -> Either.Left (prop_node name values)
          | None -> Either.Right (empty_prop_node name))
          requested
        in
        let propstats = [] in
        let propstats = if found <> [] then propstat_ok found :: propstats else propstats in
        let propstats = if not_found <> [] then propstat_not_found not_found :: propstats else propstats in
        { href = path; propstats = List.rev propstats }
    in
    let self = make_response path in
    (* Depth: 0 returns only the resource itself.
       Depth: 1 or infinity includes children of collections.
       RFC 4918 Section 9.1: "A client may submit a Depth header with a
       value of '0', '1', or 'infinity'." *)
    match depth with
    | Zero -> [self]
    | One | Infinity when S.is_collection store ~path ->
      let child_names = S.children store ~path in
      let child_prefix = if String.equal path "/" then "/" else path ^ "/" in
      let child_responses = List.map (fun name ->
        make_response (child_prefix ^ name)) child_names
      in
      self :: child_responses
    | One | Infinity -> [self]

(* Shared PROPFIND handler for both rw and ro routes *)
let propfind_handler (type s) (module S : RO_STORE with type t = s) store
    path_segs (depth_hdr, ()) ctx (local_ respond) =
  let open Httpz_server.Route in
  let path = "/" ^ String.concat "/" path_segs in
  match Webdavz_request.parse_depth depth_hdr with
  | Error `Bad_request ->
    respond_string respond ~status:Httpz.Res.Bad_request "Invalid Depth header"
  | Ok depth ->
    let pf = Webdavz_request.propfind_of_body (body_string ctx) in
    if not (S.exists store ~path) then
      respond_string respond ~status:Httpz.Res.Not_found "Not Found"
    else begin
      let responses = propfind_response (module S) store ~path ~depth ~pf in
      xml_multistatus respond (Webdavz_response.multistatus responses)
    end

(* RFC 4918 Section 18.1 — class 1 compliance *)
let routes (type s) (module S : STORE with type t = s) (store : s) =
  let open Httpz_server.Route in
  [
    (* PROPFIND — retrieve properties (RFC 4918 Section 9.1) *)
    propfind_h tail (Httpz.Header_name.Depth +> h0)
      (propfind_handler (module S) store);

    (* PROPPATCH — set/remove properties (RFC 4918 Section 9.2)
       Stub: returns 403. Full implementation would call S.set_property. *)
    proppatch tail (fun path_segs _ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      if not (S.exists store ~path) then
        respond_string respond ~status:Httpz.Res.Not_found "Not Found"
      else
        xml_error Httpz.Res.Forbidden "cannot-modify-protected-property" respond);

    (* MKCOL — create collection (RFC 4918 Section 9.3) *)
    mkcol tail (fun path_segs ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      if S.exists store ~path then
        (* RFC 4918 Section 9.3.1: MKCOL on existing resource *)
        xml_error Httpz.Res.Method_not_allowed "resource-must-be-null" respond
      else if not (S.exists store ~path:(parent_path path)) then
        (* RFC 4918 Section 9.3.1: 409 Conflict — intermediate collections *)
        respond_string respond ~status:Httpz.Res.Conflict
          "Parent collection does not exist"
      else begin
        match body_string ctx with
        | Some _ ->
          respond_string respond ~status:Httpz.Res.Unsupported_media_type
            "Request body not supported for MKCOL"
        | None ->
          S.mkdir store ~path;
          respond_string respond ~status:Httpz.Res.Created "Created"
      end);

    (* GET — read resource (RFC 4918 Section 9.4) *)
    get tail (fun path_segs _ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      match S.read store ~path with
      | Some content -> respond_string respond ~status:Httpz.Res.Success content
      | None -> not_found respond);

    (* PUT — write resource (RFC 4918 Section 9.7) *)
    put tail (fun path_segs ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      if not (S.exists store ~path:(parent_path path)) then
        (* RFC 4918 Section 9.7.1: parent collection must exist *)
        respond_string respond ~status:Httpz.Res.Conflict
          "Parent collection does not exist"
      else
        match body_string ctx with
        | None ->
          respond_string respond ~status:Httpz.Res.Bad_request "No body"
        | Some content ->
          let existed = S.exists store ~path in
          let ct = "application/octet-stream" in
          S.write store ~path ~content_type:ct content;
          let etag = Printf.sprintf "\"%08x\"" (Hashtbl.hash content) in
          if existed then
            respond_string respond ~status:Httpz.Res.No_content
              ~headers:[(Httpz.Header_name.Etag, etag)] ""
          else
            respond_string respond ~status:Httpz.Res.Created
              ~headers:[
                (Httpz.Header_name.Etag, etag);
                (Httpz.Header_name.Location, path);
              ] "Created");

    (* DELETE — remove resource (RFC 4918 Section 9.6) *)
    delete tail (fun path_segs _ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      if S.delete store ~path then
        respond_string respond ~status:Httpz.Res.No_content ""
      else
        not_found respond);

    (* LOCK — not implemented (class 1 does not require locking)
       RFC 4918 Section 18.1 *)
    lock tail (fun _path_segs _ctx respond ->
      respond_string respond ~status:Httpz.Res.Not_implemented
        "LOCK not implemented");

    (* UNLOCK — not implemented
       RFC 4918 Section 18.1 *)
    unlock tail (fun _path_segs _ctx respond ->
      respond_string respond ~status:Httpz.Res.Not_implemented
        "UNLOCK not implemented");

    (* OPTIONS — advertise DAV class 1 compliance
       RFC 4918 Section 18.1 + Section 10.1 (DAV header) *)
    route Httpz.Method.Options tail h0
      (fun _path_segs () _ctx respond ->
        respond_string respond ~status:Httpz.Res.Success
          ~headers:[
            (Httpz.Header_name.Allow,
             "OPTIONS, GET, HEAD, PUT, DELETE, PROPFIND, PROPPATCH, MKCOL");
            (Httpz.Header_name.Dav, "1");
          ] "");
  ]

(* Read-only WebDAV routes — PROPFIND, GET, OPTIONS only.
   PUT/DELETE/MKCOL/PROPPATCH return 403 Forbidden. *)
let read_only_routes (type s) (module S : RO_STORE with type t = s) (store : s) =
  let open Httpz_server.Route in
  let forbidden _path_segs _ctx respond =
    respond_string respond ~status:Httpz.Res.Forbidden "Read-only"
  in
  [
    propfind_h tail (Httpz.Header_name.Depth +> h0)
      (propfind_handler (module S) store);
    get tail (fun path_segs _ctx respond ->
      let path = "/" ^ String.concat "/" path_segs in
      match S.read store ~path with
      | Some content -> respond_string respond ~status:Httpz.Res.Success content
      | None -> not_found respond);
    put tail forbidden;
    delete tail forbidden;
    mkcol tail forbidden;
    proppatch tail forbidden;
    lock tail (fun _path_segs _ctx respond ->
      respond_string respond ~status:Httpz.Res.Not_implemented "Not implemented");
    unlock tail (fun _path_segs _ctx respond ->
      respond_string respond ~status:Httpz.Res.Not_implemented "Not implemented");
    route Httpz.Method.Options tail h0
      (fun _path_segs () _ctx respond ->
        respond_string respond ~status:Httpz.Res.Success
          ~headers:[
            (Httpz.Header_name.Allow, "OPTIONS, GET, HEAD, PROPFIND");
            (Httpz.Header_name.Dav, "1");
          ] "");
  ]

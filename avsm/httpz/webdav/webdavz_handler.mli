(** WebDAV handler generation from a STORE module type.

    Provides a generic WebDAV server by plugging in a storage backend
    that implements the {!STORE} module type.

    {{:https://datatracker.ietf.org/doc/html/rfc4918}RFC 4918} *)

(** {1 Storage Interface} *)

module type STORE = sig
  type t
  val is_collection : t -> path:string -> bool
  val exists : t -> path:string -> bool
  val get_properties : t -> path:string -> (Webdavz_xml.fqname * Webdavz_xml.tree list) list
  val read : t -> path:string -> string option
  val write : t -> path:string -> content_type:string -> string -> unit
  val delete : t -> path:string -> bool
  val mkdir : t -> path:string -> unit
  val children : t -> path:string -> string list
end

(** {1 Route Generation} *)

val routes :
  (module STORE with type t = 's) -> 's -> Httpz_server.Route.route list
(** [routes (module S) store] generates WebDAV routes for [store].

    Handles PROPFIND, PROPPATCH, MKCOL, GET, PUT, DELETE, and OPTIONS.
    LOCK/UNLOCK return 501 Not Implemented. *)

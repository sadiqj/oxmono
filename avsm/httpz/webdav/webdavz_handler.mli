(** WebDAV handler generation from a storage backend.

    Given any module implementing the {!STORE} interface, this module
    generates a complete set of {{:https://datatracker.ietf.org/doc/html/rfc4918}RFC 4918}
    WebDAV routes suitable for use with {!Httpz_server.Route}.

    {2 Supported Methods}

    {v
      Method     Section    Status
      ────────   ────────   ──────────────────────────
      PROPFIND   9.1        207 Multi-Status
      PROPPATCH  9.2        403 Forbidden (stub)
      MKCOL      9.3        201 Created
      GET        9.4        200 OK / 404 Not Found
      PUT        9.7        201 Created / 204 No Content
      DELETE     9.6        204 No Content / 404 Not Found
      OPTIONS    9.8        200 OK (DAV: 1)
      LOCK       9.10       501 Not Implemented
      UNLOCK     9.11       501 Not Implemented
    v}

    COPY and MOVE are not yet implemented. LOCK/UNLOCK return 501 per
    {{:https://datatracker.ietf.org/doc/html/rfc4918#section-6}Section 6}
    which permits class-1 compliance without locking.

    @see <https://datatracker.ietf.org/doc/html/rfc4918> RFC 4918 — WebDAV
    @see <https://datatracker.ietf.org/doc/html/rfc4918#section-18> RFC 4918 Section 18 — DAV compliance classes *)

(** {1 Storage Interface}

    The STORE module type abstracts the backend that holds WebDAV resources.
    Implementations might use a local filesystem (see {!Carddavz_store}),
    an in-memory map, or a database. *)

module type STORE = sig
  type t
  (** The store handle. *)

  val is_collection : t -> path:string -> bool
  (** [is_collection store ~path] returns [true] if [path] is a collection
      (directory).
      @see <https://datatracker.ietf.org/doc/html/rfc4918#section-3> RFC 4918 Section 3 — terminology *)

  val exists : t -> path:string -> bool
  (** [exists store ~path] returns [true] if [path] exists as any resource type. *)

  val get_properties : t -> path:string -> (Webdavz_xml.fqname * Webdavz_xml.tree list) list
  (** [get_properties store ~path] returns all properties for the resource.
      Called by PROPFIND handlers.
      @see <https://datatracker.ietf.org/doc/html/rfc4918#section-9.1> RFC 4918 Section 9.1 *)

  val read : t -> path:string -> string option
  (** [read store ~path] returns the resource content, or [None] if
      the resource doesn't exist or is a collection. *)

  val write : t -> path:string -> content_type:string -> string -> unit
  (** [write store ~path ~content_type data] creates or overwrites a
      non-collection resource.
      @see <https://datatracker.ietf.org/doc/html/rfc4918#section-9.7> RFC 4918 Section 9.7 *)

  val delete : t -> path:string -> bool
  (** [delete store ~path] removes a resource (or collection with contents).
      Returns [true] on success, [false] if the resource doesn't exist.
      @see <https://datatracker.ietf.org/doc/html/rfc4918#section-9.6> RFC 4918 Section 9.6 *)

  val mkdir : t -> path:string -> unit
  (** [mkdir store ~path] creates a collection.
      @see <https://datatracker.ietf.org/doc/html/rfc4918#section-9.3> RFC 4918 Section 9.3 — MKCOL *)

  val children : t -> path:string -> string list
  (** [children store ~path] returns the names of immediate children
      of a collection. Returns [\[\]] for non-collections. *)
end

(** {1 Route Generation} *)

val routes :
  (module STORE with type t = 's) -> 's -> Httpz_server.Route.route list
(** [routes (module S) store] generates httpz routes implementing WebDAV
    class-1 compliance for the given [store].

    All routes use the {!Httpz_server.Route.tail} pattern, so they match
    any path. Mount them at a prefix using literal path segments:

    {[
      let dav_routes = Webdavz_handler.routes (module My_store) store in
      (* Mount at /dav/... *)
      let all_routes = Httpz_server.Route.of_list (
        List.map (fun r -> ...) dav_routes  (* prefix not yet supported *)
      )
    ]}

    @see <https://datatracker.ietf.org/doc/html/rfc4918#section-18.1> RFC 4918 Section 18.1 — class 1 *)

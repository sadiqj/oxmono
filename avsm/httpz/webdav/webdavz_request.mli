(** WebDAV request body parsing.

    Parses PROPFIND and PROPPATCH XML request bodies per
    {{:https://datatracker.ietf.org/doc/html/rfc4918}RFC 4918}. *)

(** {1 PROPFIND} *)

type propfind =
  | Allprop of Webdavz_xml.fqname list
  | Propname
  | Props of Webdavz_xml.fqname list

val parse_propfind : string -> propfind option
(** [parse_propfind xml] parses a PROPFIND request body.
    Returns [None] on parse error. An empty body implies [Allprop []]. *)

val propfind_of_body : string option -> propfind
(** [propfind_of_body body] parses a propfind body, defaulting to
    [Allprop []] for [None] or empty string. *)

(** {1 PROPPATCH} *)

type propupdate =
  | Set of Webdavz_xml.fqname * Webdavz_xml.tree list
  | Remove of Webdavz_xml.fqname

val parse_proppatch : string -> propupdate list option
(** [parse_proppatch xml] parses a PROPPATCH request body.
    Returns [None] on parse error. *)

(** {1 Depth Header} *)

type depth = Zero | One | Infinity

val parse_depth : string option -> depth
(** [parse_depth header_value] parses the Depth header.
    Defaults to [Infinity] for [None]. *)

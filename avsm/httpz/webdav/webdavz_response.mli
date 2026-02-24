(** WebDAV 207 Multi-Status response generation.

    Generates XML multistatus responses per
    {{:https://datatracker.ietf.org/doc/html/rfc4918#section-13}RFC 4918 Section 13}. *)

(** {1 Types} *)

type propstat = {
  status : Httpz.Res.status;
  props : Webdavz_xml.tree list;
}
(** A property status grouping: all [props] share the same [status]. *)

type response = {
  href : string;
  propstats : propstat list;
}
(** A single response element within a multistatus. *)

(** {1 Generation} *)

val multistatus : response list -> string
(** [multistatus responses] generates the complete XML multistatus body. *)

val propstat_ok : Webdavz_xml.tree list -> propstat
(** [propstat_ok props] creates a propstat with status 200. *)

val propstat_not_found : Webdavz_xml.tree list -> propstat
(** [propstat_not_found props] creates a propstat with status 404. *)

val prop_node : Webdavz_xml.fqname -> Webdavz_xml.tree list -> Webdavz_xml.tree
(** [prop_node (ns, name) values] creates a property element. *)

val empty_prop_node : Webdavz_xml.fqname -> Webdavz_xml.tree
(** [empty_prop_node (ns, name)] creates an empty property element.
    Used in propname responses and 404 propstats. *)

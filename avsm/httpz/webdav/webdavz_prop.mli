(** WebDAV property types.

    Properties are identified by fully-qualified names (namespace + local name)
    and hold XML tree values. *)

type t = (Webdavz_xml.fqname * Webdavz_xml.tree list) list
(** A property set: list of [(name, value_trees)]. *)

(** {1 Well-known Properties} *)

val resourcetype : Webdavz_xml.fqname
val displayname : Webdavz_xml.fqname
val getcontenttype : Webdavz_xml.fqname
val getcontentlength : Webdavz_xml.fqname
val getetag : Webdavz_xml.fqname
val getlastmodified : Webdavz_xml.fqname
val creationdate : Webdavz_xml.fqname

(** {1 Accessors} *)

val find : Webdavz_xml.fqname -> t -> Webdavz_xml.tree list option
(** [find name props] returns the value trees for [name], or [None]. *)

val is_collection : t -> bool
(** [is_collection props] returns [true] if [resourcetype] contains a
    [DAV:collection] element. *)

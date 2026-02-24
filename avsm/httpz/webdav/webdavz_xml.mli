(** WebDAV XML tree types and xmlm codec.

    Provides a simple XML tree representation used throughout the WebDAV
    protocol for property values, request bodies, and multistatus responses.

    Based on the tree model from
    {{:https://datatracker.ietf.org/doc/html/rfc4918}RFC 4918}. *)

(** {1 Types} *)

type fqname = string * string
(** Fully qualified name: [(namespace, local_name)].
    Use [("DAV:", "prop")] for standard WebDAV elements. *)

type attribute = fqname * string
(** XML attribute: [(name, value)]. *)

type tree =
  | Pcdata of string
  | Node of string * string * attribute list * tree list
(** XML tree node.
    [Node (namespace, local_name, attributes, children)] or [Pcdata text]. *)

(** {1 Namespaces} *)

val dav_ns : string
(** ["DAV:"] — the WebDAV namespace. *)

val carddav_ns : string
(** ["urn:ietf:params:xml:ns:carddav"] — the CardDAV namespace. *)

(** {1 Parsing and Serialization} *)

val parse : string -> tree option
(** [parse xml_string] parses an XML string into a tree.
    Returns [None] on parse error. *)

val serialize : tree -> string
(** [serialize tree] serializes a tree to an XML string. *)

(** {1 Helpers} *)

val dav_node : string -> tree list -> tree
(** [dav_node local_name children] creates a DAV: namespaced node. *)

val pcdata : string -> tree
(** [pcdata s] creates a text node. *)

val find_children : string -> string -> tree list -> tree list
(** [find_children ns name children] finds child nodes matching [ns:name]. *)

val node_name : tree -> fqname option
(** [node_name tree] returns the [(namespace, local_name)] for a Node,
    or [None] for Pcdata. *)

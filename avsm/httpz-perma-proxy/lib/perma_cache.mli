(** Permanent cache library for HTTP proxy.

    Provides range tracking, metadata serialization, and cache file I/O. *)

(** {1 Range tracking} *)

type range = { start : int; stop : int }
(** A byte range [\[start, stop)], exclusive of [stop]. *)

val merge_range : range list -> range -> range list
(** [merge_range ranges r] merges range [r] into [ranges], a sorted
    non-overlapping range list. Returns a new sorted, non-overlapping list
    with [r] coalesced into the existing ranges. *)

val is_range_cached : range list -> start:int -> len:int -> bool
(** [is_range_cached ranges ~start ~len] returns [true] if the byte range
    [\[start, start+len)] is fully covered by [ranges]. *)

val is_complete : range list -> total_len:int -> bool
(** [is_complete ranges ~total_len] returns [true] if [ranges] covers
    [\[0, total_len)]. *)

(** {1 Metadata} *)

type meta = {
  content_length : int;
  content_type : string;
  headers : (string * string) list;
  ranges : range list;
  complete : bool;
}
(** Cache entry metadata, persisted as JSON alongside cached data files. *)

val meta_jsont : meta Jsont.t
(** JSON type descriptor for {!meta}. *)

val read_meta : Eio.Fs.dir_ty Eio.Path.t -> string -> meta option
(** [read_meta fs key] loads the [.meta] JSON file for cache key [key]
    from the filesystem rooted at [fs]. Returns [None] if the file does
    not exist or cannot be parsed. *)

val write_meta : Eio.Fs.dir_ty Eio.Path.t -> string -> meta -> unit
(** [write_meta fs key meta] saves [meta] as a [.meta] JSON file for
    cache key [key] under [fs]. Creates parent directories as needed. *)

(** {1 Cache file I/O} *)

val cache_path : host:string -> url_path:string -> string
(** [cache_path ~host ~url_path] computes the relative filesystem path
    for a cached resource. *)

val write_data : Eio.Fs.dir_ty Eio.Path.t -> string -> off:int -> string -> unit
(** [write_data fs key ~off data] writes [data] at byte offset [off]
    in the data file for [key]. Uses [Unix.openfile] with [lseek]
    for random-access writes. *)

val read_data : Eio.Fs.dir_ty Eio.Path.t -> string -> off:int -> len:int -> string
(** [read_data fs key ~off ~len] reads [len] bytes starting at byte
    offset [off] from the data file for [key]. *)

val write_file : Eio.Fs.dir_ty Eio.Path.t -> string -> string -> unit
(** [write_file fs path contents] writes [contents] to [path] under [fs],
    creating parent directories as needed. *)

val read_file : Eio.Fs.dir_ty Eio.Path.t -> string -> string
(** [read_file fs path] reads the entire contents of [path] under [fs]. *)

(** {1 Range header parsing} *)

val parse_range_header : string -> (int * int option) option
(** [parse_range_header s] parses an HTTP Range header value of the form
    ["bytes=START-END"] or ["bytes=START-"]. Returns
    [Some (start, Some end_inclusive)] or [Some (start, None)],
    or [None] if the header cannot be parsed. *)

(** A module demonstrating polymorphic variants for markdown output testing. *)

(** A polymorphic variant type with many constructors. *)
type color = [
  | `Red                                    (** Primary red color *)
  | `Green                                  (** Primary green color *)
  | `Blue                                   (** Primary blue color *)
  | `Yellow                                 (** Yellow color *)
  | `Orange                                 (** Orange color *)
  | `Purple                                 (** Purple color *)
  | `RGB of int * int * int                 (** RGB values *)
  | `Named of string                        (** Named color *)
]

(** Simple fixed polymorphic variant. *)
type status = [ `Active | `Inactive of string ]

(** Another simple polymorphic variant. *)
type simple = [ `A | `B | `C ]
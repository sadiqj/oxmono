(** Module B includes A.S with a type substitution.

    The substitution flows through [fragmap] in tools.ml. When the inline
    include's decl has been stripped, [map_include_decl] needs the
    reconstructed decl to correctly wrap the substitution. Without
    reconstruction, the empty decl produces [With(subst, empty_sig)]
    which loses the vals from the include. *)

module M : A.S with type t := int

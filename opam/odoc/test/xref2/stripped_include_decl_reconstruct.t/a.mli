(** Module A defines a signature with an inline include. *)

module type S = sig
  type t

  include sig
    val x : t
    val y : t -> t
  end
end

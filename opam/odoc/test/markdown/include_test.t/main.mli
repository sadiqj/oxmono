(** Main module that includes Base *)

type base_t = int
val base_value : base_t
val base_function : base_t -> base_t

include module type of Base
(** This includes all definitions from Base module *)

val additional_function : base_t -> base_t
(** An additional function in the main module *)
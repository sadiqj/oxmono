
(** This is a docstring with a {{:https://sherlocode.com}link} *)
val foo : int

(** This is a docstring with a ref to {!foo} *)
val bar : int

(** [hello name] returns a greeting for [name].

    For example:
    {[
      hello "world" = "Hello, world!"
    ]}
*)
val hello : string -> string

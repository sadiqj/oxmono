After compilation, odoc sets expanded=true on all includes to mark
them as "already derived". This prevents re-derivation from the decl
in dependent modules. The fragmap in tools.ml preserves this flag,
ensuring expansions remain authoritative through strengthening.

The pattern that exercises this: lib.mli defines module types and a
destructible module (Private). mid.mli includes lib with a destructive
module substitution (module Private :=). top.mli includes mid with
@inline, which strengthens mid's signature.

  $ cat lib.mli
  module type Pretty = sig
    type output
    val pp : int -> output
    val pp_hum : int -> output
  end
  
  module type Pretty_helpers = sig
    include Pretty with type output := string
    val default_indent : int
  end
  
  include Pretty_helpers
  
  module Make (X : Pretty) : Pretty_helpers
  
  module Private : sig
    val internal : int
  end









  $ cat mid.mli
  include
    module type of Lib
    with module Private := Lib.Private

  $ cat top.mli
  (** @inline *)
  include module type of struct
    include Mid
  end

Compile and link:

  $ compile lib.mli mid.mli top.mli

Generate HTML for Top:

  $ odoc html-generate top.odocl -o html --indent

Top's module type declarations should reference Mid (the source module
via strengthening). Nested includes within the expansion use Top's own
module types (Top.Pretty, Top.Pretty_helpers) since expanded=true
skips re-derivation and paths resolve in Top's context.

  $ grep 'Mid\.Pretty' html/test/Top/index.html
           <a href="../Mid/module-type-Pretty/index.html">Mid.Pretty</a>
            Mid.Pretty_helpers

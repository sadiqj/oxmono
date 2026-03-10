When an inline include's decl is stripped (replaced with an empty
signature to save space), fragmap in tools.ml must reconstruct the
decl from expansion_ before wrapping it with type substitutions.

Without reconstruction, the substitution wraps an empty signature,
losing all vals from the include.

Set up:

  $ cat a.mli
  (** Module A defines a signature with an inline include. *)

  module type S = sig
    type t

    include sig
      val x : t
      val y : t -> t
    end
  end

  $ cat b.mli
  (** Module B includes A.S with a type substitution.

      The substitution flows through [fragmap] in tools.ml. When the inline
      include's decl has been stripped, [map_include_decl] needs the
      reconstructed decl to correctly wrap the substitution. Without
      reconstruction, the empty decl produces [With(subst, empty_sig)]
      which loses the vals from the include. *)

  module M : A.S with type t := int

Compile and link:

  $ compile a.mli b.mli

The module M in B should have both vals from the include, with
type t substituted for int:

  $ odoc_print b.odocl -r M.x | jq -c '.type_'
  {"Constr":[{"`Resolved":{"`CoreType":"int"}},[]]}

  $ odoc_print b.odocl -r M.y | jq -c '.type_'
  {"Arrow":[["None",{"Constr":[{"`Resolved":{"`CoreType":"int"}},[]]}],[{"Constr":[{"`Resolved":{"`CoreType":"int"}},[]]},[[],[]]]]}

Generate HTML and verify both vals appear:

  $ odoc html-generate b.odocl -o html --indent
  $ grep 'id="val-[xy]"' html/test/B/M/index.html
      <div class="spec value anchored" id="val-x">
      <div class="spec value anchored" id="val-y">

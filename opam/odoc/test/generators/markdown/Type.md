
# Module `Type`

```
type abstract
```
Some *documentation*.

```
type alias = int
```
```
type private_ = private int
```
```
type 'a constructor = 'a
```
```
type arrow = int -> int
```
```
type higher_order = (int -> int) -> int
```
```
type labeled = l:int -> int
```
```
type optional = ?l:int -> int
```
```
type labeled_higher_order = (l:int -> int) -> (?l:int -> int) -> int
```
```
type pair = int * int
```
```
type parens_dropped = int * int
```
```
type triple = int * int * int
```
```
type nested_pair = (int * int) * int
```
```
type instance = int Type.constructor
```
```
type long =
  Type.labeled_higher_order ->
  [ `Bar | `Baz of Type.triple ] ->
  Type.pair ->
  Type.labeled ->
  Type.higher_order ->
  (string -> int) ->
  (int * float * char * string * char * unit) option ->
  Type.nested_pair ->
  Type.arrow ->
  string ->
  Type.nested_pair array
```
```
type variant_e = {

}
```
```
type variant =
| A
| B of int
| C (** foo *)
| D (** bar *)
| E of Type.variant_e

```
```
type variant_c = {

}
```
```
type _ gadt =
| A : int Type.gadt
| B : int -> string Type.gadt
| C : Type.variant_c -> unit Type.gadt

```
```
type degenerate_gadt =
| A : Type.degenerate_gadt

```
```
type private_variant = private
| A

```
```
type record = {


 (** foo *)
 (** bar *)

}
```
```
type polymorphic_variant = [
| `A
| `B of int
| `C of int * unit
| `D
]
```
```
type polymorphic_variant_extension = [
| Type.polymorphic_variant
| `E
]
```
```
type nested_polymorphic_variant = [
| `A of [ `B | `C ]
]
```
```
type private_extenion = private [>
| Type.polymorphic_variant
]
```
```
type object_ = < a : int ; b : int ; c : int >
```
```
module type X = sig ... end
```
```
type module_ = (module Type.X)
```
```
type module_substitution = (module Type.X with type t = int and type u = unit)
```
```
type +'a covariant
```
```
type -'a contravariant
```
```
type _ bivariant = int
```
```
type ('a, 'b) binary
```
```
type using_binary = (int, int) Type.binary
```
```
type 'custom name
```
```
type 'a constrained = 'a constraint 'a = int
```
```
type 'a exact_variant = 'a constraint 'a = [ `A | `B of int ]
```
```
type 'a lower_variant = 'a constraint 'a = [> `A | `B of int ]
```
```
type 'a any_variant = 'a constraint 'a = [>  ]
```
```
type 'a upper_variant = 'a constraint 'a = [< `A | `B of int ]
```
```
type 'a named_variant = 'a constraint 'a = [< Type.polymorphic_variant ]
```
```
type 'a exact_object = 'a constraint 'a = < a : int ; b : int >
```
```
type 'a lower_object = 'a constraint 'a = < a : int ; b : int.. >
```
```
type 'a poly_object = 'a constraint 'a = < a : 'a. 'a >
```
```
type ('a, 'b) double_constrained = 'a * 'b constraint 'a = int constraint 'b = unit
```
```
type as_ = (int as 'a) * 'a
```
```
type extensible = ..
```
```
type Type.extensible +=
| Extension (** Documentation for Extension. *)
| Another_extension (** Documentation for Another_extension. *)

```
```
type mutually =
| A of Type.recursive

```
```
and recursive =
| B of Type.mutually

```
```
exception Foo of int * int
```
```
type 'a t = ([ `A ] as 'a) option
```
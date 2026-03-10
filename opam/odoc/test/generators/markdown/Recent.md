
# Module `Recent`

```
module type S = sig ... end
```
```
<<<<<<< HEAD
module type S1 = functor (_ : S) -> S
```
```
type variant = 
```
```
| A
```
```
| B of int
```
```
| C
```
foo

```
| D
```
*bar*

```
| E of {
```
`a : int;`
```
}
```
```

```
```
type _ gadt = 
```
```
| A : int gadt
```
```
| B : int -> string gadt
```
foo

```
| C : {
```
`a : int;`
```
} -> unit gadt
```
```

```
```
type polymorphic_variant = [ 
```
```
| `A
```
```
| `B of int
```
```
| `C
```
foo

```
| `D
```
bar

```
 ]
=======
module type S1 = functor (_ : Recent.S) -> Recent.S
```
```
type variant =
| A
| B of int
| C (** foo *)
| D (** bar *)
| E of {
a : int;
}

```
```
type _ gadt =
| A : int Recent.gadt
| B : int -> string Recent.gadt (** foo *)
| C : {
a : int;
} -> unit Recent.gadt

```
```
type polymorphic_variant = [
| `A
| `B of int
| `C (** foo *)
| `D (** bar *)
]
>>>>>>> baf34b7f4 (Add markdown to generator tests)
```
```
type empty_variant = |
```
```
type nonrec nonrec_ = int
```
```
<<<<<<< HEAD
type empty_conj = 
```
```
| X : [< `X of & 'a & int * float ] -> empty_conj
```
```

```
```
type conj = 
```
```
| X : [< `X of int & [< `B of int & float ] ] -> conj
```
```
=======
type empty_conj =
| X : [< `X of & 'a & int * float ] -> Recent.empty_conj

```
```
type conj =
| X : [< `X of int & [< `B of int & float ] ] -> Recent.conj
>>>>>>> baf34b7f4 (Add markdown to generator tests)

```
```
val empty_conj : [< `X of & 'a & int * float ]
```
```
val conj : [< `X of int & [< `B of int & float ] ]
```
```
module Z : sig ... end
```
```
module X : sig ... end
```
```
module type PolyS = sig ... end
<<<<<<< HEAD
```
```
type +-'a phantom
```
```
val f : (x:int * y:int) phantom -> unit
=======
>>>>>>> baf34b7f4 (Add markdown to generator tests)
```
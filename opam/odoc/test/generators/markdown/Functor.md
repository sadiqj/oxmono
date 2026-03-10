
# Module `Functor`

```
module type S = sig ... end
```
```
module type S1 = functor (_ : Functor.S) -> Functor.S
```
```
module F1 (Arg : Functor.S) : Functor.S
```
```
module F2 (Arg : Functor.S) : Functor.S with type t = Arg.t
```
```
module F3 (Arg : Functor.S) : sig ... end
```
```
module F4 (Arg : Functor.S) : Functor.S
```
```
module F5 () : Functor.S
```
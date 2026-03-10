
# Module `Functor2`

```
module type S = sig ... end
```
```
module X (Y : Functor2.S) (Z : Functor2.S) : sig ... end
```
```
module type XF =
  functor (Y : Functor2.S) ->
  functor (Z : Functor2.S) ->
  sig ... end
```
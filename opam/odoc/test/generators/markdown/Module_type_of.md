
# Module `Module_type_of`

```
module type S = sig ... end
```
```
module X : sig ... end
```
```
module T : Module_type_of.S with module M = Module_type_of.X
```
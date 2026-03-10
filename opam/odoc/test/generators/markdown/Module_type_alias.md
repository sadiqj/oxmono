
# Module `Module_type_alias`

Module Type Aliases

```
module type A = sig ... end
```
```
module type B = functor (C : sig ... end) -> sig ... end
```
```
module type D = Module_type_alias.A
```
```
module type E = functor (F : sig ... end) -> Module_type_alias.B
```
```
module type G = functor (H : sig ... end) -> Module_type_alias.D
```
```
module type I = Module_type_alias.B
```
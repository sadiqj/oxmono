
# Module `Module_type_of.T`

```
module type T = sig ... end
```
```
module M = Module_type_of.X
```
```
module N : module type of struct include M end
```
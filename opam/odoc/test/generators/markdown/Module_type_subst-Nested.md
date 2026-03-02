
# Module `Module_type_subst.Nested`

```
module type nested = sig ... end
```
```
module type with_ =
  Module_type_subst.Nested.nested with module type N.t = Module_type_subst.s
```
```
module type with_subst =
  Module_type_subst.Nested.nested with module type N.t := Module_type_subst.s
```

# Module `Module_type_subst.Basic`

```
module type u = sig ... end
```
```
module type with_ =
  Module_type_subst.Basic.u with module type T = Module_type_subst.s
```
```
module type u2 = sig ... end
```
```
module type with_2 =
  Module_type_subst.Basic.u2 with module type T = sig ... end
```
```
module type a = sig ... end
```
```
module type c =
  Module_type_subst.Basic.a with module type b := Module_type_subst.s
```
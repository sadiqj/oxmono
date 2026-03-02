
# Module `Module`

Foo.

```
val foo : unit
```
The module needs at least one signature item, otherwise a bug causes the compiler to drop the module comment (above). See [https://caml.inria.fr/mantis/view.php?id=7701](https://caml.inria.fr/mantis/view.php?id=7701).

```
module type S = sig ... end
```
```
module type S1
```
```
module type S2 = Module.S
```
```
module type S3 = Module.S with type t = int and type u = string
```
```
module type S4 = Module.S with type t := int
```
```
module type S5 = Module.S with type 'a v := 'a list
```
```
type ('a, 'b) result
```
```
module type S6 = Module.S with type ('a, 'b) w := ('a, 'b) Module.result
```
```
module M' : sig ... end
```
```
module type S7 = Module.S with module M = Module.M'
```
```
module type S8 = Module.S with module M := Module.M'
```
```
module type S9 = module type of Module.M'
```
```
module Mutually : sig ... end
```
```
module Recursive : sig ... end
```
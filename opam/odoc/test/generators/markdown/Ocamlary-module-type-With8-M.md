
# Module `With8.M`

```
module type S = Ocamlary.With5.S
```
```
module N : 
  module type of struct include Ocamlary.With5.N end
    with type t = Ocamlary.With5.N.t
```
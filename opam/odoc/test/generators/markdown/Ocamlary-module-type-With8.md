
# Module type `Ocamlary.With8`

```
module M : 
  module type of struct include Ocamlary.With5 end
    with type N.t = Ocamlary.With5.N.t
```
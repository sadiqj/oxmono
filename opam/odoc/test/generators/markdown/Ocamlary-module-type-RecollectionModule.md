
# Module type `Ocamlary.RecollectionModule`

```
type collection = Ocamlary.CollectionModule.element list
```
```
type element = Ocamlary.CollectionModule.collection
```
```
module InnerModuleA : sig ... end
```
This comment is for `InnerModuleA`.

```
module type InnerModuleTypeA = InnerModuleA.InnerModuleTypeA'
```
This comment is for `InnerModuleTypeA`.

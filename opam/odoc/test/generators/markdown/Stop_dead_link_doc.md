
# Module `Stop_dead_link_doc`

```
module Foo : sig ... end
```
```
type foo =
| Bar of Stop_dead_link_doc.Foo.t

```
```
type bar =
| Bar of {

}

```
```
type foo_ =
| Bar_ of int * Stop_dead_link_doc.Foo.t * int

```
```
type bar_ =
| Bar__ of Stop_dead_link_doc.Foo.t option

```
```
type another_foo =
| Bar of Stop_dead_link_doc.Another_Foo.t

```
```
type another_bar =
| Bar of {

}

```
```
type another_foo_ =
| Bar_ of int * Stop_dead_link_doc.Another_Foo.t * int

```
```
type another_bar_ =
| Bar__ of Stop_dead_link_doc.Another_Foo.t option

```
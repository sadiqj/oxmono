
# Module `Recent.X`

```
<<<<<<< HEAD
module L := Z.Y
=======
module L := Recent.Z.Y
>>>>>>> baf34b7f4 (Add markdown to generator tests)
```
```
type t = int L.X.t
```
```
type u := int
```
```
<<<<<<< HEAD
type v = u L.X.t
=======
type v = Recent.X.u L.X.t
>>>>>>> baf34b7f4 (Add markdown to generator tests)
```
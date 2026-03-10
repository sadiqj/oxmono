  $ ocamlc -bin-annot -c test.mli
  $ odoc compile test.cmti
  $ odoc link test.odoc
  File "test.odoc":
  Warning: Hidden fields in type 'Test.v': hidden1, hidden2
  File "test.odoc":
  Warning: Hidden fields in type 'Test.u': hidden
  File "test.odoc":
  Warning: Hidden constructors in type 'Test.t'


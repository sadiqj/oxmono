  $ ocamlc -c a.mli -bin-annot -I .
  $ odoc compile -I . a.cmti
  $ odoc link -I . a.odoc
  $ export SHERLODOC_DB=db.bin
  $ export SHERLODOC_FORMAT=marshal
  $ sherlodoc index $(find . -name '*.odocl')

Search without docstrings:

  $ sherlodoc search "foo" 2>&1
  val A.foo : int

Search with markdown docstrings:

  $ sherlodoc search --print-docstring "foo" 2>&1
  val A.foo : int
  This is a docstring with a [link](https://sherlocode.com)


  $ sherlodoc search --print-docstring "bar" 2>&1
  val A.bar : int
  This is a docstring with a ref to [`foo`](A.md#val-foo)


  $ sherlodoc search --print-docstring "hello" 2>&1
  val A.hello : string -> string
  `hello name` returns a greeting for `name`.

  For example:

  ```ocaml
    hello "world" = "Hello, world!"
  ```


Search with HTML docstrings:

  $ sherlodoc search --print-docstring-html "foo" 2>&1
  val A.foo : int
  <div><p>This is a docstring with a <span>link</span></p></div>

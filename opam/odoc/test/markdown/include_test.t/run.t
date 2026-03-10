Test module includes in markdown output.

  $ ocamlc -c -bin-annot base.mli
  $ ocamlc -c -bin-annot main.mli
  $ odoc compile --package test base.cmti
  $ odoc compile --package test main.cmti
  $ odoc link base.odoc
  $ odoc link main.odoc
  $ odoc markdown-generate main.odocl -o markdown

  $ cat markdown/test/Main.md
  
  # Module `Main`
  
  Main module that includes Base
  
  ```
  type base_t = int
  ```
  ```
  val base_value : Main.base_t
  ```
  ```
  val base_function : Main.base_t -> Main.base_t
  ```
  This includes all definitions from Base module
  
  ```
  type t = int
  ```
  ```
  val value : Main.t
  ```
  ```
  val function_in_base : Main.t -> Main.t
  ```
  ```
  val additional_function : Main.base_t -> Main.base_t
  ```
  An additional function in the main module

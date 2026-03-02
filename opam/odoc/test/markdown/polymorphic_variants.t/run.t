Test polymorphic variant formatting in markdown output.

  $ ocamlc -c -bin-annot polymorphic_variants.mli
  $ odoc compile --package test polymorphic_variants.cmti
  $ odoc link polymorphic_variants.odoc
  $ odoc markdown-generate polymorphic_variants.odocl -o markdown

  $ cat markdown/test/Polymorphic_variants.md
  
  # Module `Polymorphic_variants`
  
  A module demonstrating polymorphic variants for markdown output testing.
  
  ```
  type color = [
  | `Red (** Primary red color *)
  | `Green (** Primary green color *)
  | `Blue (** Primary blue color *)
  | `Yellow (** Yellow color *)
  | `Orange (** Orange color *)
  | `Purple (** Purple color *)
  | `RGB of int * int * int (** RGB values *)
  | `Named of string (** Named color *)
  ```
  ```
   ]
  ```
  A polymorphic variant type with many constructors.
  
  ```
  type status = [
  | `Active
  | `Inactive of string
  ```
  ```
   ]
  ```
  Simple fixed polymorphic variant.
  
  ```
  type simple = [
  | `A
  | `B
  | `C
  ```
  ```
   ]
  ```
  Another simple polymorphic variant.

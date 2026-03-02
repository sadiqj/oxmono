Test the markdown output for a module with an ADT containing many constructors.
This test verifies that the markdown generator properly handles large ADTs with
various constructor types including simple variants, variants with parameters,
and proper documentation rendering.

  $ ocamlc -c -bin-annot colors.mli
  $ odoc compile --package colors colors.cmti
  $ odoc link colors.odoc
  $ odoc markdown-generate colors.odocl -o markdown

  $ cat markdown/colors/Colors.md
  
  # Module `Colors`
  
  A module demonstrating ADT with many constructors for markdown output testing.
  
  ```
  type color =
  | Red (** Primary red color *)
  | Green (** Primary green color *)
  | Blue (** Primary blue color *)
  | Yellow (** Yellow color (red + green) *)
  | Cyan (** Cyan color (green + blue) *)
  | Magenta (** Magenta color (red + blue) *)
  | Orange (** Orange color *)
  | Purple (** Purple color *)
  | Pink (** Pink color *)
  | Brown (** Brown color *)
  | Black (** Black color (absence of light) *)
  | White (** White color (all colors combined) *)
  | Gray (** Gray color *)
  | Silver (** Silver color *)
  | Gold (** Gold color *)
  | Maroon (** Dark red color *)
  | Navy (** Dark blue color *)
  | Teal (** Dark cyan color *)
  | Lime (** Bright green color *)
  | Olive (** Dark yellow-green color *)
  | Aqua (** Light blue-green color *)
  | Fuchsia (** Bright pink-purple color *)
  | Indigo (** Deep blue-purple color *)
  | Violet (** Blue-purple color *)
  | Turquoise (** Blue-green color *)
  | Coral (** Orange-pink color *)
  | Salmon (** Light orange-pink color *)
  | Crimson (** Deep red color *)
  | Scarlet (** Bright red color *)
  | Azure (** Light blue color *)
  | Beige (** Light brown color *)
  | Khaki (** Light brown-green color *)
  | Lavender (** Light purple color *)
  | Mint (** Light green color *)
  | Peach (** Light orange color *)
  | Plum (** Dark purple color *)
  | Rust (** Orange-red color *)
  | Tan (** Light brown color *)
  | Ivory (** Off-white color *)
  | Pearl (** Lustrous white color *)
  | RGB of int * int * int (** RGB color with red, green, blue values (0-255) *)
  | RGBA of int * int * int * float (** RGBA color with alpha transparency (0.0-1.0) *)
  | HSL of int * int * int (** HSL color with hue (0-360), saturation, lightness (0-100) *)
  | HSV of int * int * int (** HSV color with hue (0-360), saturation, value (0-100) *)
  | CMYK of int * int * int * int (** CMYK color for printing (0-100 each) *)
  | Hex of string (** Hexadecimal color representation (e.g., "#FF0000") *)
  | Named of string (** Named color (e.g., "forestgreen", "dodgerblue") *)
  | Gradient of Colors.color * Colors.color (** Gradient between two colors *)
  | Pattern of Colors.color list (** Pattern of multiple colors *)
  | Custom of string * int * int * int (** Custom color with name and RGB values *)
  ```
  ```
  
  ```
  A color type with many variants representing different colors and color properties.
  
  ```
  type brightness =
  | VeryDark (** Very dark variant *)
  | Dark (** Dark variant *)
  | Normal (** Normal brightness *)
  | Light (** Light variant *)
  | VeryLight (** Very light variant *)
  ```
  ```
  
  ```
  Brightness levels for colors.
  
  ```
  type temperature =
  | VeryWarm (** Very warm colors (reds, oranges) *)
  | Warm (** Warm colors *)
  | Neutral (** Neutral temperature *)
  | Cool (** Cool colors *)
  | VeryCool (** Very cool colors (blues, purples) *)
  ```
  ```
  
  ```
  Color temperature classification.
  
  ```
  val to_rgb : Colors.color -> int * int * int
  ```
  A function to get the default RGB values for a color.
  
  ```
  val get_brightness : Colors.color -> Colors.brightness
  ```
  Convert a color to its brightness classification.
  
  ```
  val get_temperature : Colors.color -> Colors.temperature
  ```
  Get the temperature classification of a color.
  
  ```
  val mix_colors : Colors.color -> Colors.color -> Colors.color
  ```
  Mix two colors together.
  
  ```
  val complement : Colors.color -> Colors.color
  ```
  Create a complementary color.

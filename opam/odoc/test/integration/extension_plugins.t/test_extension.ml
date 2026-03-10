(** Test module with custom tags.

    This module uses custom tags to test the extension system.

    @custom.note This is a custom note tag.
*)

(** A function with custom documentation tags.

    @rfc 9110
    @admonition.warning This operation may fail.
*)
let example_function () = ()

(** Another function.

    @mytag Some custom content here.
    @mytag.variant A variant of mytag.
*)
let another_function x = x + 1

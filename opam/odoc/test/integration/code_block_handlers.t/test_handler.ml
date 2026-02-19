(** Test code block handler registration and invocation.
    This module registers a test handler and provides functions to verify it works. *)

module Block = Odoc_document.Types.Block

(** A simple handler that transforms dot code blocks into a placeholder *)
module Dot_handler : Odoc_extension_api.Code_Block_Extension = struct
  let prefix = "dot"

  let to_document meta content =
    (* Extract metadata *)
    let width = Odoc_extension_api.get_binding "width" meta.tags in
    let height = Odoc_extension_api.get_binding "height" meta.tags in
    let format = Odoc_extension_api.get_binding "format" meta.tags in

    (* Create a placeholder block showing we processed it *)
    let info = Printf.sprintf "[DOT HANDLER: lang=%s, width=%s, height=%s, format=%s, content_len=%d]"
      meta.language
      (Option.value ~default:"none" width)
      (Option.value ~default:"none" height)
      (Option.value ~default:"png" format)
      (String.length content)
    in
    let inline = Odoc_document.Types.Inline.[{
      attr = ["dot-placeholder"];
      desc = Text info
    }] in
    let block = Block.[{
      attr = ["dot-output"];
      desc = Paragraph inline
    }] in
    Some (Odoc_extension_api.simple_output block)
end

(** A handler for mermaid diagrams *)
module Mermaid_handler : Odoc_extension_api.Code_Block_Extension = struct
  let prefix = "mermaid"

  let to_document meta content =
    let theme = Odoc_extension_api.get_binding "theme" meta.tags in
    let info = Printf.sprintf "[MERMAID HANDLER: theme=%s, content_len=%d]"
      (Option.value ~default:"default" theme)
      (String.length content)
    in
    let inline = Odoc_document.Types.Inline.[{
      attr = ["mermaid-placeholder"];
      desc = Text info
    }] in
    let block = Block.[{
      attr = ["mermaid-output"];
      desc = Paragraph inline
    }] in
    Some (Odoc_extension_api.simple_output block)
end

(** A handler that declines to process (returns None) *)
module Declining_handler : Odoc_extension_api.Code_Block_Extension = struct
  let prefix = "decline"

  let to_document _meta _content = None
end

let () =
  (* Register handlers *)
  Odoc_extension_api.Registry.register_code_block (module Dot_handler);
  Odoc_extension_api.Registry.register_code_block (module Mermaid_handler);
  Odoc_extension_api.Registry.register_code_block (module Declining_handler);

  (* Print registered prefixes *)
  print_endline "Registered code block handlers:";
  List.iter (fun p -> Printf.printf "  - %s\n" p)
    (Odoc_extension_api.Registry.list_code_block_prefixes ())

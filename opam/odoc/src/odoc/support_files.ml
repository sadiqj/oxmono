open Odoc_utils

let should_include ~without_theme file =
  if without_theme then
    match file with
    | "odoc.css" | "fonts/FiraMono-Regular.woff2"
    | "fonts/FiraSans-Regular.woff2" | "fonts/NoticiaText-Regular.ttf" ->
        false
    | _ -> true
  else true

let iter_files f ?(without_theme = false) output_directory =
  let file name content =
    let name = Fs.File.create ~directory:output_directory ~name in
    f name content
  in
  (* Built-in support files *)
  let files = Odoc_html_support_files.file_list in
  List.iter
    (fun f ->
      match Odoc_html_support_files.read f with
      | Some content when should_include ~without_theme f -> file f content
      | _ -> ())
    files;
  (* Extension support files *)
  let extension_files = Odoc_extension_registry.list_support_files () in
  List.iter
    (fun (ext_file : Odoc_extension_registry.support_file) ->
      file ext_file.filename ext_file.content)
    extension_files

let write =
  iter_files (fun name content ->
      let dir = Fs.File.dirname name in
      Fs.Directory.mkdir_p dir;
      let name = Fs.File.to_string name in
      Io_utils.with_open_out name (fun oc -> output_string oc content))

let print_filenames =
  iter_files (fun name _content -> print_endline (Fs.File.to_string name))

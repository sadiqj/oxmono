open Odoc_utils

module Types = Odoc_document.Types
module Doctree = Odoc_document.Doctree
module Url = Odoc_document.Url

let source fn (t : Types.Source.t) =
  let rec token (x : Types.Source.token) =
    match x with Elt i -> fn i | Tag (_, l) -> tokens l
  and tokens t = List.concat_map token t in
  tokens t

and styled style content =
  match style with
  | `Bold ->
      let inlines_as_one_inline = Renderer.Inline.Inlines content in
      [ Renderer.Inline.Strong_emphasis inlines_as_one_inline ]
  | `Italic | `Emphasis ->
      (* We treat emphasis as italic, since there's no difference in Markdown *)
      let inlines_as_one_inline = Renderer.Inline.Inlines content in
      [ Renderer.Inline.Emphasis inlines_as_one_inline ]
  | `Superscript | `Subscript ->
      (* CommonMark doesn't have support for superscript/subscript, we fallback to inline *)
      content

let entity = function "#45" -> "-" | "gt" -> ">" | e -> "&" ^ e ^ ";"

let rec inline_text_only inline =
  List.concat_map
    (fun (i : Types.Inline.one) ->
      match i.desc with
      | Text "" -> []
      | Text s -> [ s ]
      | Entity s -> [ entity s ]
      | Linebreak -> []
      | Styled (_, content) -> inline_text_only content
      | Link { content; _ } -> inline_text_only content
      | Source s -> source inline_text_only s
      | _ -> [])
    inline

and block_text_only blocks : string list =
  List.concat_map
    (fun (b : Types.Block.one) ->
      match b.desc with
      | Paragraph inline | Inline inline -> inline_text_only inline
      | Source (_, _, _, s, _) -> source inline_text_only s
      | List (_, items) -> List.concat_map block_text_only items
      | Verbatim s -> [ s ]
      | _ -> [])
    blocks

and inline ~(config : Config.t) ~resolve l =
  let one (t : Types.Inline.one) =
    match t.desc with
    | Text s -> [ Renderer.Inline.Text s ]
    | Entity s ->
        (* In CommonMark, HTML entities are supported directly, so we can just output them as text. Some markdown parsers may not support some entities. *)
        [ Renderer.Inline.Text s ]
    | Linebreak -> [ Renderer.Inline.Break ]
    | Styled (style, c) ->
        let inline_content = inline ~config ~resolve c in
        styled style inline_content
    | Link link -> inline_link ~config ~resolve link
    | Source c ->
        (* CommonMark doesn't allow any complex node inside inline text, rendering inline nodes as text *)
        let content = source inline_text_only c in
        [ Renderer.Inline.Code_span content ]
    | Math s ->
        (* Since CommonMark doesn't support Math's, we treat it a inline code *)
        [ Renderer.Inline.Code_span [ s ] ]
    | Raw_markup (target, content) -> (
        match Astring.String.Ascii.lowercase target with
        | "html" ->
            let block_lines = content in
            [ Renderer.Inline.Raw_html [ block_lines ] ]
        | _ ->
            (* Markdown only supports html blocks *)
            [])
  in
  List.concat_map one l

and inline_link ~config ~resolve link =
  let href =
    match link.target with
    | External href -> Some href
    | Internal internal -> (
        match internal with
        | Resolved uri -> Some (Link.href ~config ~resolve uri)
        | Unresolved -> None)
  in
  match href with
  | Some href ->
      let inline_content = inline ~config ~resolve link.content in
      let link_inline = Renderer.Inline.Inlines inline_content in
      [ Renderer.Inline.Link { text = link_inline; url = Some href } ]
  | None -> [ Renderer.Inline.Code_span (inline_text_only link.content) ]

let rec block ~config ~resolve l =
  let one (t : Types.Block.one) =
    match t.desc with
    | Paragraph paragraph ->
        let inlines = inline ~config ~resolve paragraph in
        let inlines = Renderer.Inline.Inlines inlines in
        let paragraph_block = Renderer.Block.Paragraph inlines in
        (* CommonMark treats paragraph as a block, to align the behavior with other generators such as HTML, we add a blank line after it *)
        let break = Renderer.Block.Blank_line in
        [ paragraph_block; break ]
    | List (type_, l) ->
        let items =
          List.map
            (fun items ->
              let block = block ~config ~resolve items in
              Renderer.Block.Blocks block)
            l
        in
        [
          (match type_ with
          | Ordered -> Renderer.Block.Ordered_list items
          | Unordered -> Renderer.Block.Unordered_list items);
        ]
    | Inline i ->
        let inlines = Renderer.Inline.Inlines (inline ~config ~resolve i) in
        [ Renderer.Block.Paragraph inlines ]
    | Table t -> block_table ~config ~resolve t
    | Description l ->
        let item ({ key; definition; attr = _ } : Types.Description.one) =
          let term = inline ~config ~resolve key in
          (* We extract definition as inline *)
          let definition_inline =
            Renderer.Inline.Text
              (String.concat ~sep:"" (block_text_only definition))
          in
          let space = Renderer.Inline.Text " " in
          let term_inline =
            Renderer.Inline.Inlines (term @ [ space; definition_inline ])
          in
          [ Renderer.Block.Paragraph term_inline ]
        in
        List.concat_map item l
    | Verbatim s ->
        let code_snippet =
          Renderer.Block.Code_block { info_string = None; code = [ s ] }
        in
        [ code_snippet ]
    | Source (lang, _, _, s, _) ->
        let code = s |> source inline_text_only |> List.map (fun s -> s) in
        let code_snippet =
          Renderer.Block.Code_block { info_string = Some lang; code }
        in
        [ code_snippet ]
    | Math s ->
        (* Since CommonMark doesn't support Math's, we just treat it as code. Maybe could use Ext_math_block or Ext_math_display *)
        let block =
          Renderer.Block.Code_block { info_string = None; code = [ s ] }
        in
        [ block ]
    | Raw_markup (target, content) -> (
        match Astring.String.Ascii.lowercase target with
        | "html" ->
            let html_block_lines = Renderer.block_line_of_string content in
            [ Renderer.Block.Html_block html_block_lines ]
        | _ -> (* Markdown only supports html blocks *) [])
    | Image (target, alt) ->
        let url =
          match (target : Types.Target.t) with
          | External url -> Some url
          | Internal (Resolved uri) -> Some (Link.href ~config ~resolve uri)
          | Internal Unresolved -> None
        in
        let image : Renderer.Inline.link =
          { text = Renderer.Inline.Text alt; url }
        in
        [
          Renderer.Block.Paragraph
            (Renderer.Inline.Inlines [ Renderer.Inline.Image image ]);
        ]
    | Audio (_target, _alt) | Video (_target, _alt) ->
        (* Audio and video aren't supported in markdown *)
        []
  in
  List.concat_map one l

and block_table ~config ~resolve t =
  let alignment = function
    | Types.Table.Left -> Some `Left
    | Types.Table.Center -> Some `Center
    | Types.Table.Right -> Some `Right
    | Types.Table.Default -> None
  in

  let convert_cell content =
    match content with
    | [ { Types.Block.desc = Paragraph p; _ } ]
    | [ { Types.Block.desc = Inline p; _ } ] ->
        inline ~config ~resolve p
    | blocks ->
        let text = String.concat ~sep:" " (block_text_only blocks) in
        [ Renderer.Inline.Text text ]
  in

  let convert_row (row : (Types.Block.t * [ `Data | `Header ]) list) =
    let cells =
      List.map
        (fun (content, _) -> Renderer.Inline.Inlines (convert_cell content))
        row
    in
    match row with (_, `Header) :: _ -> `Header cells | _ -> `Data cells
  in

  match t.data with
  | [] -> [ Renderer.Block.Paragraph (Renderer.Inline.Inlines []) ]
  | rows ->
      let table_rows = List.map convert_row rows in
      let separator = `Sep (List.map alignment t.align) in
      let rec insert_separator acc = function
        | [] -> List.rev acc
        | (`Header _ as h) :: (`Data _ :: _ as rest) ->
            List.rev (h :: acc) @ [ separator ] @ rest
        | (`Header _ as h) :: rest -> insert_separator (h :: acc) rest
        | rows -> List.rev acc @ [ separator ] @ rows
      in

      let final_rows = insert_separator [] table_rows in
      let table = Renderer.Block.Table.make final_rows in
      [ Renderer.Block.Table table ]

and items ~config ~resolve l : Renderer.Block.t list =
  let rec walk_items acc (t : Types.Item.t list) =
    let continue_with rest elts =
      (walk_items [@tailcall]) (List.rev_append elts acc) rest
    in
    match t with
    | [] -> List.rev acc
    | Text _ :: _ as t ->
        let text, _, rest =
          Doctree.Take.until t ~classify:(function
            | Types.Item.Text text -> Accum text
            | _ -> Stop_and_keep)
        in
        let content = block ~config ~resolve text in
        (continue_with [@tailcall]) rest content
    | Heading h :: rest ->
        (* Markdown headings are rendered as a blank line before and after the heading, otherwise it treats it as an inline paragraph *)
        let break = Renderer.Block.Blank_line in
        let inlines = inline ~config ~resolve h.title in
        let content = Renderer.Inline.Inlines inlines in
        let block : Renderer.Block.heading =
          { level = h.level + 1; inline = content; id = None }
        in
        let heading_block = Renderer.Block.Heading block in
        (continue_with [@tailcall]) rest [ break; heading_block; break ]
    | Include
        {
          attr = _attr;
          anchor = _anchor;
          source_anchor = _source_anchor;
          doc;
          content = { summary = _summary; status = _status; content };
        }
      :: rest ->
        let doc_content = block ~config ~resolve doc in
        let included_content = walk_items [] content in
        let all_content = doc_content @ included_content in
        (continue_with [@tailcall]) rest all_content
    | Declaration
        {
          attr = _attr;
          anchor = _anchor;
          source_anchor = _source_anchor;
          content;
          doc;
        }
      :: rest ->
        let spec = documentedSrc ~config ~resolve content in
        let doc = block ~config ~resolve doc in
        let content = spec @ doc in
        (continue_with [@tailcall]) rest content
  and items l = walk_items [] l in
  items l

and documentedSrc ~config ~resolve t =
  let open Types.DocumentedSrc in
  let take_code l =
    Doctree.Take.until l ~classify:(fun x ->
        match (x : one) with
        | Code code -> Accum code
        | Alternative (Expansion { summary; _ }) -> Accum summary
        | _ -> Stop_and_keep)
  in
  let take_descr l =
    Doctree.Take.until l ~classify:(function
      | Documented { attrs; anchor; code; doc; markers } ->
          Accum [ { attrs; anchor; code = `D code; doc; markers } ]
      | Nested { attrs; anchor; code; doc; markers } ->
          Accum [ { attrs; anchor; code = `N code; doc; markers } ]
      | _ -> Stop_and_keep)
  in
  let rec to_markdown t : Renderer.Block.t list =
    match t with
    | [] -> []
    | (Code _ | Alternative _) :: _ ->
        let code, header, rest = take_code t in
        let info_string =
          match header with Some header -> Some header | None -> None
        in
        let inline_source = source inline_text_only code in
        let initial_code = String.concat ~sep:"" inline_source in
        
        (* Check if the rest starts with Documented/Nested items - if so, combine them *)
        (match rest with
        | (Documented _ | Nested _) :: _ ->
            let l, _, remaining_rest = take_descr rest in
            (* Combine the initial code with the documented items *)
            let combine_code_with_docs initial_code items =
              let rec collect_lines acc = function
                | [] -> List.rev acc
                | { attrs = _; anchor = _; code; doc; markers = _ } :: rest ->
                    let code_line = match code with
                      | `D code ->
                          let inline_source = inline ~config ~resolve code in
                          let rec extract_all_text acc = function
                            | [] -> List.rev acc
                            | Renderer.Inline.Text s :: rest -> extract_all_text (s :: acc) rest
                            | Renderer.Inline.Code_span code_list :: rest -> 
                                extract_all_text (String.concat ~sep:"" code_list :: acc) rest
                            | Renderer.Inline.Inlines inlines :: rest -> 
                                extract_all_text (extract_all_text [] inlines @ acc) rest
                            | Renderer.Inline.Emphasis inner :: rest ->
                                extract_all_text (extract_all_text [] [inner] @ acc) rest
                            | Renderer.Inline.Strong_emphasis inner :: rest ->
                                extract_all_text (extract_all_text [] [inner] @ acc) rest
                            | Renderer.Inline.Link { text; _ } :: rest ->
                                extract_all_text (extract_all_text [] [text] @ acc) rest
                            | Renderer.Inline.Image { text; _ } :: rest ->
                                extract_all_text (extract_all_text [] [text] @ acc) rest
                            | _ :: rest -> extract_all_text acc rest
                          in
                          let code_text = String.concat ~sep:"" (extract_all_text [] inline_source) in
                          String.trim code_text
                      | `N n ->
                          (* For nested items, recursively process them *)
                          let nested_blocks = to_markdown n in
                          String.concat ~sep:"\n" (List.concat_map (function
                            | Renderer.Block.Code_block { code; _ } -> code
                            | _ -> []) nested_blocks)
                    in
                    let doc_comment = match doc with
                      | [] -> ""
                      | doc_blocks ->
                          let doc_text = String.concat ~sep:"" (block_text_only doc_blocks) in
                          let cleaned_text = String.trim doc_text in
                          if cleaned_text = "" then ""
                          else " (** " ^ cleaned_text ^ " *)"
                    in
                    let combined_line = code_line ^ doc_comment in
                    collect_lines (combined_line :: acc) rest
              in
              let constructor_lines = collect_lines [] items in
              String.trim initial_code :: constructor_lines
            in
            let combined_lines = combine_code_with_docs initial_code l in
            (* Also collect any trailing Code items (like closing ']' for polymorphic variants) *)
            let rec collect_trailing_code items acc =
              match items with
              | (Code _ | Alternative _) :: _ ->
                  let code, _, remaining = take_code items in
                  let trailing_code = String.concat ~sep:"" (source inline_text_only code) in
                  collect_trailing_code remaining (String.trim trailing_code :: acc)
              | rest -> (List.rev acc, rest)
            in
            let trailing_codes, final_rest = collect_trailing_code remaining_rest [] in
            let all_lines = combined_lines @ trailing_codes in
            if all_lines <> [] then
              let combined_code = String.concat ~sep:"\n" all_lines in
              let code_block = Renderer.Block.Code_block { info_string; code = [combined_code] } in
              [code_block] @ to_markdown final_rest
            else
              let code = [ initial_code ] in
              let block = Renderer.Block.Code_block { info_string; code } in
              [ block ] @ to_markdown rest
        | _ ->
            let code = [ initial_code ] in
            let block = Renderer.Block.Code_block { info_string; code } in
            [ block ] @ to_markdown rest)
    | Subpage subp :: _ -> subpage ~config ~resolve subp
    | (Documented _ | Nested _) :: _ ->
        let l, _, rest = take_descr t in
        (* Combine code and documentation into a single code block with inline comments *)
        let combine_code_with_docs items =
          let rec collect_lines acc = function
            | [] -> List.rev acc
            | { attrs = _; anchor = _; code; doc; markers = _ } :: rest ->
                let code_line = match code with
                  | `D code ->
                      let inline_source = inline ~config ~resolve code in
                      let rec extract_all_text acc = function
                        | [] -> List.rev acc
                        | Renderer.Inline.Text s :: rest -> extract_all_text (s :: acc) rest
                        | Renderer.Inline.Code_span code_list :: rest -> 
                            extract_all_text (String.concat ~sep:"" code_list :: acc) rest
                        | Renderer.Inline.Inlines inlines :: rest -> 
                            extract_all_text (extract_all_text [] inlines @ acc) rest
                        | Renderer.Inline.Emphasis inner :: rest ->
                            extract_all_text (extract_all_text [] [inner] @ acc) rest
                        | Renderer.Inline.Strong_emphasis inner :: rest ->
                            extract_all_text (extract_all_text [] [inner] @ acc) rest
                        | Renderer.Inline.Link { text; _ } :: rest ->
                            extract_all_text (extract_all_text [] [text] @ acc) rest
                        | Renderer.Inline.Image { text; _ } :: rest ->
                            extract_all_text (extract_all_text [] [text] @ acc) rest
                        | _ :: rest -> extract_all_text acc rest
                      in
                      let code_text = String.concat ~sep:"" (extract_all_text [] inline_source) in
                      String.trim code_text
                  | `N n ->
                      (* For nested items, recursively process them *)
                      let nested_blocks = to_markdown n in
                      String.concat ~sep:"\n" (List.concat_map (function
                        | Renderer.Block.Code_block { code; _ } -> code
                        | _ -> []) nested_blocks)
                in
                let doc_comment = match doc with
                  | [] -> ""
                  | doc_blocks ->
                      let doc_text = String.concat ~sep:"" (block_text_only doc_blocks) in
                      let cleaned_text = String.trim doc_text in
                      if cleaned_text = "" then ""
                      else " (** " ^ cleaned_text ^ " *)"
                in
                let combined_line = code_line ^ doc_comment in
                collect_lines (combined_line :: acc) rest
          in
          collect_lines [] items
        in
        let combined_lines = combine_code_with_docs l in
        if combined_lines <> [] then
          let combined_code = String.concat ~sep:"\n" combined_lines in
          let code_block = Renderer.Block.Code_block { info_string = None; code = [combined_code] } in
          [code_block] @ to_markdown rest
        else
          to_markdown rest
  in
  to_markdown t

and subpage ~config ~resolve (subp : Types.Subpage.t) =
  items ~config ~resolve subp.content.items

module Page = struct
  let on_sub = function
    | `Page _ -> None
    | `Include (x : Types.Include.t) -> (
        match x.status with
        | `Closed | `Open | `Default -> None
        | `Inline -> Some 0)

  let rec include_ ~config { Types.Subpage.content; _ } = page ~config content

  and subpages ~config subpages = List.map (include_ ~config) subpages

  and page ~config p =
    let subpages = subpages ~config @@ Doctree.Subpages.compute p in
    let resolve = Link.Current p.url in
    let i = Doctree.Shift.compute ~on_sub p.items in
    let header, preamble =
      Doctree.PageTitle.render_title ?source_anchor:p.source_anchor p
    in
    let header = items ~config ~resolve header in
    let preamble = items ~config ~resolve preamble in
    let content = items ~config ~resolve i in
    let root_block = Renderer.Block.Blocks (header @ preamble @ content) in
    let doc = root_block in
    Markdown_page.make ~config ~url:p.url doc subpages

  and source_page ~config sp =
    let { Types.Source_page.url; contents; _ } = sp in
    let resolve = Link.Current sp.url in
    let title = url.Url.Path.name in
    let header =
      items ~config ~resolve (Doctree.PageTitle.render_src_title sp)
    in
    let extract_source_text docs =
      let rec doc_to_text span =
        match (span : Types.Source_page.span) with
        | Plain_code s -> s
        | Tagged_code (_, docs) ->
            String.concat ~sep:"" (List.map doc_to_text docs)
      in

      docs |> List.map doc_to_text |> String.concat ~sep:"" |> String.trim
    in
    let source_block =
      Renderer.Block.Code_block
        { info_string = Some "ocaml"; code = [ extract_source_text contents ] }
    in
    let doc = header @ [ source_block ] in
    Markdown_page.make_src ~config ~url title doc
end

let render ~(config : Config.t) doc =
  match (doc : Types.Document.t) with
  (* .mld *)
  | Page page -> [ Page.page ~config page ]
  (* .mli docs *)
  | Source_page src -> [ Page.source_page ~config src ]

let inline ~config ~xref_base_uri b =
  let resolve = Link.Base xref_base_uri in
  inline ~config ~resolve b

let block ~config ~xref_base_uri b =
  let resolve = Link.Base xref_base_uri in
  block ~config ~resolve b

let filepath ~config url = Link.Path.as_filename ~config url

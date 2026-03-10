Odoc currently supports a number of "tags" like `@raise` `@param` `@since` and so on. I would like to add support for "custom tags" where a user-defined tag can be created with new behaviour at the linking step and the HTML generation step.

For example, we might have a new tag for referencing IETF RFCs - e.g. `@rfc 9110 Section 5.5`. Or we might have a new tag for an example block:

```
@example This is an example of foo bar.
It's a multi-line thing that ends up in an
outlined box in the HTML
```

Or we might have something where we can resolve references:

```
@handles This handles the {!Foo} exception.
```

Now the way to handle these is to write an odoc extension somehow
where we'd write code that uses the odoc APIs to handle the extensions. These pieces of code would be called during the link
and HTML generation phases of odoc.

We need to come up with some mechanisms to make this happen.

Firstly, how do we tell odoc about this? Do we use Dynlink to
load in the new handlers, or do we recompile a new odoc binary, linking in the new handlers?

Secondly, how do we tell `dune` that this needs to be done?

Thirdly, how do we tell the ocaml docs CI that this needs to be done? This would presumably require some new fields in the opam
file.

## Design Decisions

### Q1: Dynamic plugins using dune's sites mechanism

Extensions are OCaml libraries that are dynamically loaded at runtime using
dune's plugins/sites mechanism (`dune-site`). This approach:

- **No custom odoc binary**: Extensions are loaded by the standard odoc at runtime
- **Independent installation**: Extensions are installed as separate opam packages
- **Automatic discovery**: odoc discovers installed extensions via the sites mechanism
- **Ecosystem-friendly**: Follows established dune patterns for extensibility

#### How it works

1. **odoc declares a plugin site** in its `dune-project`:

```lisp
(lang dune 3.21)
(using dune_site 0.1)
(name odoc)

(package
  (name odoc)
  (sites (lib extensions)))  ; Extensions are installed here
```

2. **odoc uses `generate_sites_module`** to discover and load plugins:

```lisp
; In odoc's dune file
(executable
  (name odoc_main)
  (libraries odoc_core dune-site dune-site.plugins)
  (modules odoc_main sites))

(generate_sites_module
  (module sites)
  (plugins (odoc extensions)))
```

3. **Extension packages declare themselves as plugins**:

```lisp
; In odoc-rfc-extension/dune-project
(lang dune 3.21)
(using dune_site 0.1)
(name odoc-rfc-extension)

(package (name odoc-rfc-extension))
```

```lisp
; In odoc-rfc-extension/dune
(library
  (public_name odoc-rfc-extension.impl)
  (name odoc_rfc_impl)
  (libraries odoc.extension_api))

(plugin
  (name odoc-rfc-extension)
  (libraries odoc-rfc-extension.impl)
  (site (odoc extensions)))
```

4. **odoc loads all installed extensions** at startup:

```ocaml
(* In odoc_main.ml *)
let () = Sites.Plugins.Extensions.load_all ()
(* Extensions register themselves during load *)
```

#### ABI compatibility

The primary concern with dynamic loading is ABI compatibility - plugins must be
compiled with the same OCaml version and compatible compiler flags. This is
mitigated by:

- **opam's OCaml version constraints**: Extension packages depend on specific
  OCaml versions, so opam ensures compatibility
- **Rebuild on OCaml upgrade**: When the OCaml compiler is upgraded, all
  packages (including extensions) are rebuilt
- **Clear error messages**: If loading fails due to ABI mismatch, odoc reports
  a clear error directing users to rebuild the extension

### Q2: Extension registration pattern

Extensions register themselves with odoc's extension registry when loaded.
This is the standard dune plugin pattern:

```ocaml
(* In odoc.extension_api *)
module Registry : sig
  val register : (module Odoc_tag_extension) -> unit
  val find : string -> (module Odoc_tag_extension) option
  val all : unit -> (module Odoc_tag_extension) list
end

(* In odoc_rfc_impl.ml - executed when plugin loads *)
let () =
  Odoc.Extension_api.Registry.register (module Rfc_extension)
```

### Q3: Declaration in dune-project and opam

Users declare which extensions they need in their `dune-project`. This serves
two purposes:

1. **Build-time dependency**: Ensures the extension is available when building docs
2. **CI solver hint**: Allows ocaml.org doc CI to know which extensions to install

```lisp
(package
  (name mypkg)
  (depends
    (odoc (>= 3.0))
    (odoc-rfc-extension (>= 1.0))
    (odoc-graphviz-extension (>= 1.0))))
```

Since extensions are regular opam packages with `(plugin ...)` stanzas, they
appear as normal dependencies. The CI solver simply installs all dependencies,
which includes the extensions.

For explicit documentation about which extensions a package uses, an optional
`x-odoc-extensions` field can be added:

```
x-odoc-extensions: ["odoc-rfc-extension" "odoc-graphviz-extension"]
```

This is informational only - the actual dependency resolution uses the
standard `depends` field.

### Q4: Fallback for missing extensions

When odoc encounters a custom tag but the extension is not installed:

1. **Warning**: "Unknown tag @rfc - is odoc-rfc-extension installed?"
2. **Graceful degradation**: The tag content is rendered as a blockquote with
   a note about the missing extension
3. **No build failure**: Documentation generation continues

This allows documentation to be built even if extensions are missing, which is
important for:
- Quick local builds without all extensions
- CI environments that don't have all extensions configured
- Viewing older docs where extensions may have changed

## Extension Interface

Extensions are OCaml modules implementing the `Odoc_tag_extension` signature.
Each extension claims a prefix and handles all tags starting with that prefix:

- `@rfc` → rfc extension
- `@rfc.section` → rfc extension
- `@callout` → callout extension
- `@callout.box` → callout extension

### Extension Output

Extensions return content that can be rendered by any backend, with optional
backend-specific overrides for cases where different output is needed:

```ocaml
(** Resources that can be injected into the page (HTML only) *)
type resource =
  | Js_url of string      (** External JavaScript: <script src="..."> *)
  | Css_url of string     (** External CSS: <link rel="stylesheet" href="..."> *)
  | Js_inline of string   (** Inline JavaScript: <script>...</script> *)
  | Css_inline of string  (** Inline CSS: <style>...</style> *)

(** Output from the document phase *)
type extension_output = {
  content : Odoc_document.Types.Block.t;
  (** Universal content - used by all backends unless overridden *)

  overrides : (string * string) list;
  (** Backend-specific raw content overrides.
      E.g., [("html", "<div>...</div>"); ("markdown", "```dot\n...\n```")]
      If present for a backend, used instead of [content]. *)

  resources : resource list;
  (** Page-level resources (JS/CSS). Only used by HTML backend. *)
}
```

**Rendering logic:**
1. Backend checks `overrides` for its name (e.g., "html", "markdown", "latex")
2. If found, use that raw string directly
3. Otherwise, render `content` using the standard Document → output pipeline
4. HTML backend also collects and deduplicates `resources` for page HEAD/BODY

### Module Signature

```ocaml
module type Odoc_tag_extension = sig
  (** The tag prefix this extension handles.
      E.g., "callout" handles @callout, @callout.box, @callout.bubble *)
  val prefix : string

  (** Link phase: process/validate content, resolve custom references.
      Called during odoc link with the linking environment. *)
  val link :
    tag:string ->
    Odoc_xref2.Env.t ->
    Odoc_model.Comment.nestable_block_element list ->
    Odoc_model.Comment.nestable_block_element list

  (** Document phase: convert tag to document elements for rendering.
      Called during document generation. Returns content plus any
      page-level resources needed (JS/CSS). *)
  val to_document :
    tag:string ->
    Odoc_model.Comment.nestable_block_element list ->
    extension_output
end

(** Raised when an extension receives a tag variant it doesn't support.
    E.g., callout extension receiving @callout.unknown *)
exception Unsupported_tag of string
```

### Example Extensions

#### Graphviz (with backend overrides)

This extension needs different output for HTML vs Markdown:

```ocaml
(* odoc_graphviz_extension.ml *)

let prefix = "dot"

let link ~tag _env content = content

let to_document ~tag content =
  let dot_source = extract_text content in
  {
    (* Fallback: just show the source as a code block *)
    content = Block.[Source [...]];

    (* Backend-specific rendering *)
    overrides = [
      ("html", Printf.sprintf {|<div class="graphviz">%s</div>|}
                 (escape_html dot_source));
      ("markdown", Printf.sprintf "```dot\n%s\n```" dot_source);
    ];

    (* HTML needs the renderer script *)
    resources = [
      Js_url "https://cdn.jsdelivr.net/npm/@viz-js/viz/lib/viz-standalone.js";
      Js_inline {|
        document.querySelectorAll('.graphviz').forEach(async el => {
          const viz = await Viz.instance();
          el.innerHTML = viz.renderSVGElement(el.textContent).outerHTML;
        });
      |};
    ];
  }
```

#### Callout (universal content)

Simple extensions can use Document types that work everywhere:

```ocaml
(* odoc_callout_extension.ml *)

let prefix = "callout"

let link ~tag _env content = content

let to_document ~tag content =
  let block_content = render_content content in
  let content = match tag with
    | "callout" | "callout.box" ->
        (* Returns Block.t with a styled div - works for all backends *)
        make_callout_block ~style:`Box block_content
    | "callout.bubble" ->
        make_callout_block ~style:`Bubble block_content
    | _ ->
        raise (Unsupported_tag tag)
  in
  (* No overrides needed - Document types render well everywhere *)
  { content; overrides = []; resources = [] }
```

### Error Handling

When odoc encounters a custom tag:

1. Look up extension by prefix (first component before `.`)
2. If no extension registered: warning "Unknown tag @foo"
3. If extension raises `Unsupported_tag`: error "Tag @foo.bar not supported by 'foo' extension"
4. Extension errors during link/render are reported with source location

## Dune Integration

### Extension loading in dune's doc rules

When dune runs `odoc link` or `odoc html-generate`, the extensions are loaded
automatically because:

1. odoc is built with `dune-site.plugins` support
2. The `Sites.Plugins.Extensions.load_all ()` call happens at odoc startup
3. Any extensions installed in the `odoc/extensions` site are discovered

No special dune rules are needed - if the extension package is installed,
odoc will find and use it.

### Development workflow

During development (before extensions are installed), extensions can be
loaded by setting environment variables that dune-site respects:

```bash
# Point to local extension build
export DUNE_DIR_LOCATIONS="odoc:lib:extensions:_build/default/my-extension"
dune build @doc
```

Alternatively, dune could be enhanced to understand that packages with
`(plugin (site (odoc extensions)))` should have their build directories
added to the site path when building docs.

### Complete example: RFC extension package

Here's the full structure of an RFC extension package:

```
odoc-rfc-extension/
├── dune-project
├── odoc-rfc-extension.opam
├── src/
│   ├── dune
│   └── rfc_extension.ml
└── test/
    └── ...
```

**dune-project**:
```lisp
(lang dune 3.21)
(using dune_site 0.1)
(name odoc-rfc-extension)
(generate_opam_files true)

(package
  (name odoc-rfc-extension)
  (synopsis "RFC reference extension for odoc")
  (depends
    (ocaml (>= 4.14))
    (odoc (>= 3.0))))
```

**src/dune**:
```lisp
(library
  (public_name odoc-rfc-extension.impl)
  (name rfc_extension)
  (libraries odoc.extension_api))

(plugin
  (name odoc-rfc-extension)
  (libraries odoc-rfc-extension.impl)
  (site (odoc extensions)))
```

**src/rfc_extension.ml**:
```ocaml
open Odoc_extension_api

let prefix = "rfc"

let link ~tag _env content = content

let to_document ~tag content =
  (* Parse "@rfc 9110" or "@rfc 9110 Section 5.5" *)
  let rfc_num, section = parse_rfc_reference content in
  let url = Printf.sprintf "https://www.rfc-editor.org/rfc/rfc%d" rfc_num in
  let url = match section with
    | None -> url
    | Some s -> url ^ "#" ^ s
  in
  let link_text = match section with
    | None -> Printf.sprintf "RFC %d" rfc_num
    | Some s -> Printf.sprintf "RFC %d %s" rfc_num s
  in
  {
    content = Block.[
      Paragraph [Inline.Link { url; text = [Inline.Text link_text] }]
    ];
    overrides = [];
    resources = [];
  }

(* Register on load *)
let () = Registry.register (module struct
  let prefix = prefix
  let link = link
  let to_document = to_document
end)
```

## Trade-offs: Dynamic vs Static Linking

### Dynamic plugins (recommended)

**Advantages:**
- No need to rebuild odoc for each project
- Extensions are independent packages with their own release cycles
- Natural fit with opam package management
- Standard dune pattern used by other tools
- Extensions can be added/removed without touching the main project

**Disadvantages:**
- ABI compatibility requirements (same OCaml version)
- Slightly more complex deployment (multiple packages)
- Runtime discovery adds small startup overhead
- Cross-compilation may be more complex

### Static linking (alternative)

**Advantages:**
- Single binary with all extensions baked in
- No runtime ABI concerns
- Simpler deployment for specialized use cases
- Works in environments where dynlink is unavailable

**Disadvantages:**
- Requires rebuilding a custom odoc binary
- Extensions tightly coupled to specific odoc version
- More complex build setup
- Doesn't fit well with standard opam workflows

### Recommendation

The dynamic plugin approach using dune-site is recommended as the primary
mechanism because:

1. It follows established dune patterns
2. It integrates naturally with opam
3. It allows extensions to evolve independently
4. The ABI concerns are well-handled by opam's dependency resolver
5. It's the approach used by other OCaml tools with plugin systems

Static linking could be supported as an advanced option for specific use
cases (embedded systems, specialized deployments), but shouldn't be the
default.

## Implementation Plan

### Phase 1: Core extension infrastructure

1. Add `odoc.extension_api` library with:
   - `Odoc_tag_extension` module type
   - `Registry` module for extension registration
   - `extension_output` type and helpers

2. Modify odoc to:
   - Add `(sites (lib extensions))` to dune-project
   - Add `dune-site` and `dune-site.plugins` dependencies
   - Generate sites module and call `load_all ()` at startup
   - Hook extension registry into link and html-generate phases

### Phase 2: Extension discovery and error handling

1. Implement graceful fallback for unknown tags
2. Add helpful error messages for ABI mismatches
3. Add `odoc extensions` subcommand to list installed extensions

### Phase 3: Example extensions

1. Create `odoc-rfc-extension` as a reference implementation
2. Create `odoc-callout-extension` showing universal content
3. Create `odoc-graphviz-extension` showing backend overrides

### Phase 4: Documentation and ecosystem

1. Document extension authoring guide
2. Work with ocaml.org CI to support extensions
3. Consider creating an `odoc-extensions` opam repository or tag


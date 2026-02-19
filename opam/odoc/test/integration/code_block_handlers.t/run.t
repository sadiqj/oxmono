Test code block metadata preservation and handler infrastructure.

First, compile the test page:

  $ odoc compile --package test test_code_blocks.mld

Link:

  $ odoc link -I . page-test_code_blocks.odoc

Generate HTML:

  $ odoc html-generate -o html page-test_code_blocks.odocl

Check the HTML output exists:

  $ test -f html/test/test_code_blocks.html && echo "HTML generated"
  HTML generated

Verify code blocks are rendered with language classes.
The language-* class should be present for each code block:

  $ grep -o 'class="[^"]*language-[^"]*"' html/test/test_code_blocks.html | sort | uniq
  class="language-dot"
  class="language-mermaid"
  class="language-msc"
  class="language-ocaml"
  class="language-python"

Verify the code content is preserved in the output:

  $ grep -q "let x = 1" html/test/test_code_blocks.html && echo "ocaml code preserved"
  ocaml code preserved

  $ grep -q "let y = 2" html/test/test_code_blocks.html && echo "ocaml with metadata preserved"
  ocaml with metadata preserved

  $ grep -q "digraph G" html/test/test_code_blocks.html && echo "dot code preserved"
  dot code preserved

  $ grep -q "sequenceDiagram" html/test/test_code_blocks.html && echo "mermaid code preserved"
  mermaid code preserved

  $ grep -q "msc {" html/test/test_code_blocks.html && echo "msc code preserved"
  msc code preserved

Verify bare tags don't break rendering (skip, noeval):

  $ grep -q "let z = 3" html/test/test_code_blocks.html && echo "code with bare tags preserved"
  code with bare tags preserved

Verify bindings don't break rendering (version=5.0):

  $ grep -q "def hello" html/test/test_code_blocks.html && echo "python code preserved"
  python code preserved

Verify format option is accepted (format=png, format=svg):

  $ grep -q "digraph Dependencies" html/test/test_code_blocks.html && echo "dot with format=png preserved"
  dot with format=png preserved

  $ grep -q "digraph Circular" html/test/test_code_blocks.html && echo "dot with format=svg preserved"
  dot with format=svg preserved

  $ grep -q "pie title Pets" html/test/test_code_blocks.html && echo "mermaid with format=png preserved"
  mermaid with format=png preserved

Test the odoc extensions command works:

  $ odoc extensions | head -2
  Installed extensions:

Test the extension plugin system.

This tests:
1. Custom tags compile without error
2. The 'odoc extensions' command lists available extensions
3. Extensions render custom tags with styled output
4. Support files mechanism works

First, compile the test module with custom tags:

  $ ocamlc -bin-annot -c test_extension.ml

Compile with odoc - custom tags should work without errors:

  $ odoc compile --package test test_extension.cmt

Link the compiled unit:

  $ odoc link -I . test_extension.odoc

Generate HTML output:

  $ odoc html-generate -o html test_extension.odocl

Test the 'odoc extensions' command.
Extensions are loaded via dune-site plugin mechanism:

  $ odoc extensions | head -1
  Installed extensions:

Check that tag content is preserved in the output.

The custom.note tag should be rendered (either by extension or default):

  $ grep -q "This is a custom note tag" html/test/Test_extension/index.html && echo "custom.note content found"
  custom.note content found

The mytag tags should be rendered:

  $ grep -q "Some custom content here" html/test/Test_extension/index.html && echo "mytag content found"
  mytag content found

The admonition.warning content should be present with extension styling:

  $ grep -q "This operation may fail" html/test/Test_extension/index.html && echo "admonition content found"
  admonition content found

  $ grep -q "admonition-warning" html/test/Test_extension/index.html && echo "admonition styling found"
  admonition styling found

The rfc tag should produce a styled RFC reference link:

  $ grep -q "rfc-reference" html/test/Test_extension/index.html && echo "rfc styling found"
  rfc styling found

  $ grep -q "rfc-editor.org" html/test/Test_extension/index.html && echo "rfc link found"
  rfc link found

Test the support-files command works:

  $ odoc support-files -o support
  $ test -d support && echo "support directory created"
  support directory created

  $ test -f support/odoc.css && echo "odoc.css present"
  odoc.css present

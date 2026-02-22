#!/bin/sh -ex

if [ ! -d _local ]; then
  opam switch create . --repos lox=git+https://github.com/oxcaml/opam-repository.git,default -y
fi

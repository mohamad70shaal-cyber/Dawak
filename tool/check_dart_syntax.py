#!/usr/bin/env python3
"""Syntax-only check of every Dart file using tree-sitter (works without a Dart/Flutter SDK).

    pip install tree-sitter tree-sitter-dart
    python3 tool/check_dart_syntax.py [paths...]

This catches unbalanced brackets, missing semicolons and malformed constructs. It does NOT type-check:
`flutter analyze` remains the authority. Exit status 1 if any file has a syntax error.
"""
import pathlib
import sys

import tree_sitter_dart
from tree_sitter import Language, Parser

ROOT = pathlib.Path(__file__).resolve().parents[1]


def first_error(node):
    if node.type == "ERROR" or node.is_missing:
        return node
    for child in node.children:
        if child.has_error or child.is_missing:
            found = first_error(child)
            if found is not None:
                return found
    return node if node.has_error else None


def main():
    parser = Parser(Language(tree_sitter_dart.language()))
    targets = [pathlib.Path(a) for a in sys.argv[1:]] or [ROOT / "lib", ROOT / "test"]
    files = []
    for t in targets:
        files += [t] if t.is_file() else sorted(t.rglob("*.dart"))
    bad = 0
    for f in files:
        src = f.read_bytes()
        tree = parser.parse(src)
        if tree.root_node.has_error:
            bad += 1
            node = first_error(tree.root_node)
            line = node.start_point[0] + 1 if node is not None else "?"
            snippet = src.splitlines()[node.start_point[0]].decode("utf-8", "replace").strip()[:100] if node is not None else ""
            print(f"SYNTAX  {f.relative_to(ROOT)}:{line}  {snippet}")
    print(f"checked {len(files)} Dart files, {bad} with syntax errors")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

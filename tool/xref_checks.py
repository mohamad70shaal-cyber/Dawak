#!/usr/bin/env python3
"""Cross-reference checks for the Dart sources that need no Dart/Flutter SDK (tree-sitter only).

`flutter analyze` is the authority; it could not be run in the build environment. This script finds the
mistakes that are common when many files are written without a compiler:

  1. missing import      a project class / function is used in a file that does not (transitively) import it
  2. unused import       a project file is imported but nothing it declares is used
  3. unknown member      `c.foo` where `c` is explicitly typed as a project class that has no member `foo`
                         (instance members through variables, static members / enum values through the class name)
  4. bad call            constructor or method of a project class called with an unknown named argument, a missing
                         required named argument, or the wrong number of positional arguments
  5. duplicate argument  the same named argument written twice in one call (any callee, framework included):
                         a compile error that needs no type information to find

It is deliberately conservative: expressions it cannot type (`var x = ...`, generics, framework types) are skipped,
so a clean run does not prove the code compiles. Usage:

    pip install tree-sitter tree-sitter-dart
    python3 tool/xref_checks.py [--verbose]

Exit status 1 when anything is reported.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass, field
from pathlib import Path

import tree_sitter_dart
from tree_sitter import Language, Node, Parser

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
TEST = ROOT / "test"
PACKAGE = "dawak"

PARSER = Parser(Language(tree_sitter_dart.language()))

OBJECT_MEMBERS = {"hashCode", "runtimeType", "toString", "noSuchMethod"}
GETX_CONTROLLER_MEMBERS = OBJECT_MEMBERS | {
    "update", "refresh", "onInit", "onReady", "onClose", "onStart", "onDelete", "isClosed", "initialized", "ready",
    "listeners", "addListener", "removeListener", "notifyChildrens", "refreshGroup", "disposeId", "dispose",
    "hasListeners", "listenersLength", "id", "findOrNull", "reactive",
}
FRAMEWORK_ROOTS: dict[str, set[str]] = {
    "Object": OBJECT_MEMBERS,
    "GetxController": GETX_CONTROLLER_MEMBERS,
    "GetxService": GETX_CONTROLLER_MEMBERS,
    "Exception": OBJECT_MEMBERS,
}
ENUM_STATIC = {"values"}
ENUM_INSTANCE = OBJECT_MEMBERS | {"name", "index", "compareTo"}
SELECTORS = {"unconditional_assignable_selector", "conditional_assignable_selector", "cascade_selector"}

problems: list[str] = []


def report(path: Path, node: Node | None, message: str) -> None:
    line = (node.start_point[0] + 1) if node is not None else 0
    try:
        rel = path.relative_to(ROOT)
    except ValueError:
        rel = path
    problems.append(f"{rel}:{line}: {message}")


# --------------------------------------------------------------------------------------------- model
@dataclass
class Sig:
    pos_required: int = 0
    pos_optional: int = 0
    named: dict[str, bool] = field(default_factory=dict)  # name -> required

    def accepts_positional(self, n: int) -> bool:
        return self.pos_required <= n <= self.pos_required + self.pos_optional


@dataclass
class Member:
    kind: str  # field | method | getter | setter
    static: bool = False
    sig: Sig | None = None


@dataclass
class Decl:
    name: str
    kind: str  # class | mixin | enum | extension | typedef | function | var
    file: Path
    superclass: str | None = None
    mixins: list[str] = field(default_factory=list)
    interfaces: list[str] = field(default_factory=list)
    on: list[str] = field(default_factory=list)
    members: dict[str, Member] = field(default_factory=dict)
    ctors: dict[str, Sig] = field(default_factory=dict)
    enum_values: set[str] = field(default_factory=set)
    sig: Sig | None = None  # functions


@dataclass
class Import:
    target: Path | None
    is_export: bool
    show: set[str] | None
    hide: set[str]
    node: Node


@dataclass
class FileInfo:
    path: Path
    src: bytes
    root: Node
    imports: list[Import] = field(default_factory=list)
    decls: dict[str, Decl] = field(default_factory=dict)


def text(src: bytes, n: Node) -> str:
    return src[n.start_byte:n.end_byte].decode("utf-8", "replace")


def children_of(n: Node, *types: str) -> list[Node]:
    return [c for c in n.children if c.type in types]


def first_child(n: Node, *types: str) -> Node | None:
    for c in n.children:
        if c.type in types:
            return c
    return None


# --------------------------------------------------------------------------------------------- parsing
def param_name(src: bytes, fp: Node) -> str | None:
    direct = [c for c in fp.children if c.type == "identifier"]
    if direct:
        return text(src, direct[-1])
    for c in fp.children:
        if c.type in ("constructor_param", "super_formal_parameter", "function_formal_parameter"):
            ids = [x for x in c.children if x.type == "identifier"]
            if ids:
                return text(src, ids[-1])
    return None


def parse_params(src: bytes, plist: Node | None) -> Sig:
    sig = Sig()
    if plist is None:
        return sig
    for c in plist.children:
        if c.type == "formal_parameter":
            sig.pos_required += 1
        elif c.type == "optional_formal_parameters":
            named = bool(c.children) and c.children[0].type == "{"
            required_next = False
            for p in c.children:
                if p.type == "required":
                    required_next = True
                elif p.type == "formal_parameter":
                    if named:
                        name = param_name(src, p)
                        if name:
                            sig.named[name] = required_next
                    else:
                        sig.pos_optional += 1
                    required_next = False
    return sig


def signature_of(src: bytes, node: Node) -> tuple[list[str], Sig]:
    """Identifiers before the parameter list and the parsed parameters of a (constructor/function) signature."""
    names = [text(src, c) for c in node.children if c.type == "identifier"]
    return names, parse_params(src, first_child(node, "formal_parameter_list"))


def add_members_from_declaration(src: bytes, d: Decl, node: Node, is_enum: bool = False) -> None:
    static = first_child(node, "static") is not None
    for c in node.children:
        if c.type in ("constructor_signature", "constant_constructor_signature", "factory_constructor_signature"):
            names, sig = signature_of(src, c)
            ctor = names[1] if len(names) >= 2 else ""
            d.ctors[ctor] = sig
        elif c.type in ("initialized_identifier_list", "static_final_declaration_list"):
            for item in c.children:
                if item.type in ("initialized_identifier", "static_final_declaration"):
                    ident = first_child(item, "identifier")
                    if ident is not None:
                        d.members[text(src, ident)] = Member("field", static)
        elif c.type in ("function_signature", "getter_signature", "setter_signature"):
            add_method(src, d, c, static)


def add_method(src: bytes, d: Decl, sig_node: Node, static: bool) -> None:
    ident = [c for c in sig_node.children if c.type == "identifier"]
    if not ident:
        return
    name = text(src, ident[0])
    if sig_node.type == "getter_signature":
        d.members[name] = Member("getter", static)
    elif sig_node.type == "setter_signature":
        d.members[name] = Member("setter", static)
    else:
        d.members[name] = Member("method", static, parse_params(src, first_child(sig_node, "formal_parameter_list")))


def parse_class_like(src: bytes, path: Path, node: Node, kind: str) -> Decl | None:
    ident = first_child(node, "identifier")
    if ident is None:
        return None
    d = Decl(text(src, ident), kind, path)
    sup = first_child(node, "superclass")
    if sup is not None:
        t = first_child(sup, "type_identifier")
        if t is not None:
            d.superclass = text(src, t)
        mixins = first_child(sup, "mixins")
        if mixins is not None:
            d.mixins += [text(src, x) for x in children_of(mixins, "type_identifier")]
    mixins = first_child(node, "mixins")
    if mixins is not None:
        d.mixins += [text(src, x) for x in children_of(mixins, "type_identifier")]
    itf = first_child(node, "interfaces")
    if itf is not None:
        d.interfaces += [text(src, x) for x in children_of(itf, "type_identifier")]
    d.on = [text(src, x) for x in children_of(node, "type_identifier")] if kind in ("mixin", "extension") else []
    body = first_child(node, "class_body", "enum_body", "extension_body")
    if body is None:
        return d
    for c in body.children:
        if c.type == "enum_constant":
            e = first_child(c, "identifier")
            if e is not None:
                d.enum_values.add(text(src, e))
        elif c.type == "declaration":
            add_members_from_declaration(src, d, c)
        elif c.type == "method_signature":
            static = first_child(c, "static") is not None
            for s in c.children:
                if s.type in ("function_signature", "getter_signature", "setter_signature"):
                    add_method(src, d, s, static)
                elif s.type in ("constructor_signature", "constant_constructor_signature", "factory_constructor_signature"):
                    names, sig = signature_of(src, s)
                    d.ctors[names[1] if len(names) >= 2 else ""] = sig
                elif s.type == "operator_signature":
                    pass
    return d


def resolve_uri(src_path: Path, uri: str) -> Path | None:
    if uri.startswith("dart:"):
        return None
    if uri.startswith("package:"):
        rest = uri[len("package:"):]
        pkg, _, tail = rest.partition("/")
        return (LIB / tail).resolve() if pkg == PACKAGE else None
    return (src_path.parent / uri).resolve()


def parse_file(path: Path) -> FileInfo:
    src = path.read_bytes()
    root = PARSER.parse(src).root_node
    info = FileInfo(path.resolve(), src, root)
    pending_fn: Node | None = None
    for c in root.children:
        if c.type == "import_or_export":
            lib = c.children[0]
            is_export = lib.type == "library_export"
            uri_node = None
            spec = lib
            if lib.type == "library_import":
                spec = first_child(lib, "import_specification") or lib
            conf = first_child(spec, "configurable_uri")
            if conf is not None:
                uri_node = first_child(conf, "uri")
            if uri_node is None:
                continue
            uri = text(src, uri_node).strip("'\"")
            show: set[str] | None = None
            hide: set[str] = set()
            for comb in children_of(spec, "combinator"):
                names = {text(src, x) for x in children_of(comb, "identifier")}
                if comb.children and comb.children[0].type == "show":
                    show = (show or set()) | names
                else:
                    hide |= names
            info.imports.append(Import(resolve_uri(path, uri), is_export, show, hide, c))
        elif c.type == "class_definition":
            d = parse_class_like(src, info.path, c, "class")
            if d:
                info.decls[d.name] = d
        elif c.type == "mixin_declaration":
            d = parse_class_like(src, info.path, c, "mixin")
            if d:
                info.decls[d.name] = d
        elif c.type == "enum_declaration":
            d = parse_class_like(src, info.path, c, "enum")
            if d:
                info.decls[d.name] = d
        elif c.type == "extension_declaration":
            d = parse_class_like(src, info.path, c, "extension")
            if d:
                info.decls[d.name] = d
        elif c.type == "type_alias":
            t = first_child(c, "type_identifier")
            if t is not None:
                info.decls[text(src, t)] = Decl(text(src, t), "typedef", info.path)
        elif c.type == "function_signature":
            names, sig = signature_of(src, c)
            if names:
                d = Decl(names[0], "function", info.path)
                d.sig = sig
                info.decls[names[0]] = d
        elif c.type in ("static_final_declaration_list", "initialized_identifier_list"):
            for item in c.children:
                ident = first_child(item, "identifier")
                if ident is not None and item.type in ("static_final_declaration", "initialized_identifier"):
                    info.decls[text(src, ident)] = Decl(text(src, ident), "var", info.path)
    _ = pending_fn
    return info


# --------------------------------------------------------------------------------------------- project index
class Project:
    def __init__(self, files: list[Path]):
        self.files: dict[Path, FileInfo] = {}
        for f in files:
            info = parse_file(f)
            self.files[info.path] = info
        self.registry: dict[str, list[Decl]] = {}
        for info in self.files.values():
            for d in info.decls.values():
                self.registry.setdefault(d.name, []).append(d)
        self._exports: dict[Path, set[str]] = {}

    def unique(self, name: str) -> Decl | None:
        ds = self.registry.get(name, [])
        return ds[0] if len(ds) == 1 else None

    def exported_names(self, path: Path, seen: set[Path] | None = None) -> set[str]:
        """Names a file makes visible to its importers: its own declarations plus whatever it re-exports."""
        seen = seen or set()
        if path in seen or path not in self.files:
            return set()
        seen.add(path)
        info = self.files[path]
        names = set(info.decls)
        for imp in info.imports:
            if imp.is_export and imp.target is not None:
                got = self.exported_names(imp.target, seen)
                if imp.show is not None:
                    got &= imp.show
                got -= imp.hide
                names |= got
        return names

    def visible(self, info: FileInfo) -> set[str]:
        names = set(info.decls)
        for imp in info.imports:
            if imp.is_export or imp.target is None:
                continue
            got = self.exported_names(imp.target)
            if imp.show is not None:
                got &= imp.show
            got -= imp.hide
            names |= got
        return names

    # ---- inheritance
    def lookup_member(self, cls: Decl, name: str, static: bool, depth: int = 0) -> tuple[Member | None, bool]:
        """(member, complete). `complete` is False when an unknown framework ancestor could still provide it."""
        if depth > 12:
            return None, False
        if name in cls.members and cls.members[name].static == static:
            return cls.members[name], True
        if static:
            return None, True
        complete = True
        ancestors = ([cls.superclass] if cls.superclass else []) + cls.mixins + cls.interfaces + cls.on
        if not ancestors and cls.kind in ("class", "mixin"):
            ancestors = ["Object"]
        for a in ancestors:
            if a is None:
                continue
            d = self.unique(a)
            if d is not None and d.kind in ("class", "mixin", "enum"):
                m, c = self.lookup_member(d, name, False, depth + 1)
                if m is not None:
                    return m, True
                complete = complete and c
            elif a in FRAMEWORK_ROOTS:
                if name in FRAMEWORK_ROOTS[a]:
                    return Member("method"), True
            else:
                complete = False
        if cls.kind == "enum" and name in ENUM_INSTANCE:
            return Member("getter"), True
        for ds in self.registry.values():
            for ext in ds:
                if ext.kind == "extension" and cls.name in ext.on and name in ext.members:
                    return ext.members[name], True
        return None, complete


# --------------------------------------------------------------------------------------------- checks
def walk(node: Node):
    yield node
    for c in node.children:
        yield from walk(c)


def in_directive(node: Node) -> bool:
    n: Node | None = node
    while n is not None:
        if n.type == "import_or_export":
            return True
        n = n.parent
    return False


def args_of(src: bytes, arguments: Node) -> tuple[int, set[str]]:
    positional = 0
    named: set[str] = set()
    for a in arguments.children:
        if a.type == "argument":
            positional += 1
        elif a.type == "named_argument":
            lab = first_child(a, "label")
            if lab is not None:
                ident = first_child(lab, "identifier")
                if ident is not None:
                    named.add(text(src, ident))
    return positional, named


def args_of_record(src: bytes, rec: Node) -> tuple[int, set[str]]:
    """`Paged<T>(fetch: x)` in a field initializer is parsed as a record literal by tree-sitter-dart."""
    positional = 0
    named: set[str] = set()
    for c in rec.children:
        if c.type == "label":
            ident = first_child(c, "identifier")
            if ident is not None:
                named.add(text(src, ident))
        elif c.type not in ("(", ")", ","):
            # the value following a label is not a positional argument
            prev = c.prev_sibling
            if prev is not None and prev.type == "label":
                continue
            positional += 1
    return positional, named


def check_call(path: Path, node: Node, what: str, sig: Sig, positional: int, named: set[str]) -> None:
    if not sig.accepts_positional(positional):
        report(path, node, f"{what}: {positional} positional argument(s) but it takes {sig.pos_required}"
                           f"{'+' + str(sig.pos_optional) if sig.pos_optional else ''}")
    for n in sorted(named):
        if n not in sig.named:
            report(path, node, f"{what}: no named parameter '{n}'")
    for n, req in sig.named.items():
        if req and n not in named:
            report(path, node, f"{what}: missing required named argument '{n}'")


UNTYPED = "<untyped>"


def decl_type(project: Project, src: bytes, node: Node) -> str:
    """Project class named by an explicit type annotation among the direct children of [node], else UNTYPED."""
    t = first_child(node, "type_identifier")
    if t is None or first_child(node, "type_arguments") is not None:
        return UNTYPED
    name = text(src, t)
    return name if project.unique(name) is not None else UNTYPED


def params_lookup(project: Project, src: bytes, plist: Node | None, name: str) -> str | None:
    if plist is None:
        return None
    for n in walk(plist):
        if n.type == "formal_parameter" and param_name(src, n) == name:
            return decl_type(project, src, n)
    return None


def variable_lookup(project: Project, src: bytes, st: Node, name: str) -> str | None:
    """Declared name of a `local_variable_declaration` / `initialized_variable_definition`."""
    for d in st.children:
        if d.type == "initialized_variable_definition":
            ident = first_child(d, "identifier")
            if ident is not None and text(src, ident) == name:
                return decl_type(project, src, d)
            for extra in children_of(d, "initialized_identifier"):
                i2 = first_child(extra, "identifier")
                if i2 is not None and text(src, i2) == name:
                    return decl_type(project, src, d)
    return None


def class_field_lookup(project: Project, src: bytes, cls: Node, name: str) -> str | None:
    body = first_child(cls, "class_body", "enum_body", "extension_body")
    if body is None:
        return None
    for d in children_of(body, "declaration"):
        lst = first_child(d, "initialized_identifier_list")
        if lst is None:
            continue
        for item in children_of(lst, "initialized_identifier"):
            ident = first_child(item, "identifier")
            if ident is not None and text(src, ident) == name:
                return decl_type(project, src, d)
    return None


def resolve_var(project: Project, info: FileInfo, node: Node, name: str) -> str | None:
    """Type of the variable [name] visible at [node]: a project class name, UNTYPED, or None when not a variable."""
    src = info.src
    pos = node.start_byte
    child = node
    a = node.parent
    while a is not None:
        t = a.type
        found: str | None = None
        if t in ("block", "switch_block", "program"):
            for st in a.children:
                if st.start_byte >= pos:
                    break
                if st.type == "local_variable_declaration":
                    r = variable_lookup(project, src, st, name)
                    if r is not None:
                        found = r
        elif t == "for_statement":
            parts = first_child(a, "for_loop_parts")
            if parts is not None and parts.start_byte < pos < parts.end_byte or (parts is not None and child.type != "for_loop_parts"):
                ident = [c for c in parts.children if c.type == "identifier"] if parts is not None else []
                if parts is not None and ident and text(src, ident[0]) == name and first_child(parts, "in") is not None:
                    found = decl_type(project, src, parts)
                elif parts is not None:
                    for st in children_of(parts, "local_variable_declaration"):
                        r = variable_lookup(project, src, st, name)
                        if r is not None:
                            found = r
        elif t == "try_statement":
            prev = child.prev_sibling
            if prev is not None and prev.type == "catch_clause":
                params = first_child(prev, "catch_parameters")
                if params is not None and any(text(src, i) == name for i in children_of(params, "identifier")):
                    found = UNTYPED
        elif t == "if_statement":
            for pat in children_of(a, "variable_pattern"):
                ident = first_child(pat, "identifier")
                if ident is not None and text(src, ident) == name:
                    found = decl_type(project, src, pat)
        elif t == "function_expression":
            found = params_lookup(project, src, first_child(a, "formal_parameter_list"), name)
        elif t == "function_body":
            sig = a.prev_sibling
            if sig is not None:
                plist = None
                for n in walk(sig):
                    if n.type == "formal_parameter_list":
                        plist = n
                        break
                found = params_lookup(project, src, plist, name)
        elif t == "declaration":
            for sig in children_of(a, "constructor_signature", "constant_constructor_signature", "factory_constructor_signature"):
                found = params_lookup(project, src, first_child(sig, "formal_parameter_list"), name) or found
        elif t in ("class_definition", "mixin_declaration", "enum_declaration", "extension_declaration"):
            found = class_field_lookup(project, src, a, name)
        if found is not None:
            return found
        child = a
        a = a.parent
    return None


def local_names(info: FileInfo) -> set[str]:
    src = info.src
    names: set[str] = set()
    for n in walk(info.root):
        if n.type == "formal_parameter":
            p = param_name(src, n)
            if p:
                names.add(p)
        elif n.type == "initialized_variable_definition":
            ident = first_child(n, "identifier")
            if ident is not None:
                names.add(text(src, ident))
        elif n.type in ("initialized_identifier", "static_final_declaration"):
            ident = first_child(n, "identifier")
            if ident is not None:
                names.add(text(src, ident))
        elif n.type in ("function_signature", "getter_signature", "setter_signature"):
            ident = first_child(n, "identifier")
            if ident is not None:
                names.add(text(src, ident))
    return names


def selector_member(src: bytes, sel: Node) -> str | None:
    if sel.type != "selector":
        return None
    inner = first_child(sel, "unconditional_assignable_selector", "conditional_assignable_selector")
    if inner is None:
        return None
    ident = first_child(inner, "identifier")
    return text(src, ident) if ident is not None else None


def selector_args(sel: Node | None) -> Node | None:
    if sel is None or sel.type != "selector":
        return None
    ap = first_child(sel, "argument_part")
    return first_child(ap, "arguments") if ap is not None else None


def check_file(project: Project, info: FileInfo) -> None:
    src = info.src
    path = info.path
    visible = project.visible(info)
    locals_ = local_names(info)
    used_names: set[str] = set()

    # ---------------- identifiers: missing imports + usage tracking
    for n in walk(info.root):
        if n.type not in ("identifier", "type_identifier") or in_directive(n):
            continue
        name = text(src, n)
        parent = n.parent
        if parent is not None and parent.type in SELECTORS:
            used_names.add(name)  # extension members etc. count as usage of imports
            continue
        if parent is not None and parent.type in ("label", "function_signature", "getter_signature", "setter_signature",
                                                  "constructor_signature", "constant_constructor_signature",
                                                  "factory_constructor_signature", "enum_constant", "initialized_identifier",
                                                  "static_final_declaration", "formal_parameter", "class_definition",
                                                  "mixin_declaration", "enum_declaration", "extension_declaration"):
            if parent.type in ("class_definition", "mixin_declaration", "enum_declaration", "extension_declaration",
                               "function_signature") and parent.type != "function_signature":
                continue
            if parent.type in ("label", "enum_constant", "initialized_identifier", "static_final_declaration"):
                continue
            if parent.type == "formal_parameter" and n.type == "identifier":
                continue
            if parent.type in ("getter_signature", "setter_signature") and n.type == "identifier":
                continue
        used_names.add(name)
        d = project.unique(name)
        if d is None or name in visible:
            continue
        if name[0].isupper() or (d.kind in ("function", "var") and name not in locals_ and is_callee_or_value(n)):
            if d.file != path:
                report(path, n, f"'{name}' is declared in {d.file.relative_to(ROOT)} which is not imported")

    # ---------------- unused project imports
    for imp in info.imports:
        if imp.is_export or imp.target is None or imp.target not in project.files:
            continue
        provided = project.exported_names(imp.target)
        if imp.show is not None:
            provided &= imp.show
        provided -= imp.hide
        members: set[str] = set()
        for nm in provided:
            d = project.files[imp.target].decls.get(nm) or project.unique(nm)
            if d is not None and d.kind == "extension":
                members |= set(d.members)
        if not (provided & used_names) and not (members & used_names):
            report(path, imp.node, f"unused import {imp.target.relative_to(ROOT)}")

    # ---------------- members and calls
    for cls in [c for c in info.root.children if c.type in ("class_definition", "mixin_declaration", "extension_declaration", "enum_declaration")]:
        cname = text(src, first_child(cls, "identifier")) if first_child(cls, "identifier") is not None else ""
        this_decl = info.decls.get(cname)
        check_expressions(project, info, cls, this_decl, locals_)
    # top-level functions
    for i, c in enumerate(info.root.children):
        if c.type == "function_signature" and i + 1 < len(info.root.children):
            body = info.root.children[i + 1]
            if body.type == "function_body":
                check_expressions(project, info, body, None, locals_)


def is_callee_or_value(n: Node) -> bool:
    parent = n.parent
    if parent is None:
        return False
    sib = n.next_sibling
    return sib is not None and sib.type == "selector" and selector_args(sib) is not None


def check_expressions(project: Project, info: FileInfo, scope: Node, this_decl: Decl | None, locals_: set[str]) -> None:
    src = info.src
    path = info.path
    for node in walk(scope):
        # `Class<T>(...)` parsed as relational + record literal
        if node.type == "relational_expression" and len(node.children) == 3 and node.children[2].type == "record_literal":
            inner = node.children[0]
            if inner.type == "relational_expression" and inner.children and inner.children[0].type == "identifier":
                d = project.unique(text(src, inner.children[0]))
                if d is not None and d.kind == "class" and "" in d.ctors:
                    pos, named = args_of_record(src, node.children[2])
                    check_call(path, node, f"{d.name}(...)", d.ctors[""], pos, named)
            continue
        if node.type in ("const_object_expression", "new_expression"):
            t = first_child(node, "type_identifier")
            args = first_child(node, "arguments")
            ids = children_of(node, "identifier")
            if t is not None and args is not None and not ids:
                d = project.unique(text(src, t))
                if d is not None and d.kind == "class":
                    sig = d.ctors.get("")
                    if sig is None and not d.ctors:
                        sig = Sig()
                    if sig is not None:
                        pos, named = args_of(src, args)
                        check_call(path, node, f"{d.name}(...)", sig, pos, named)
            continue
        kids = node.children
        for i, c in enumerate(kids):
            if c.type not in ("identifier", "this"):
                continue
            if i > 0 and kids[i - 1].type == "selector":
                continue
            nxt = kids[i + 1] if i + 1 < len(kids) else None
            if nxt is None or nxt.type != "selector":
                continue
            if node.type in ("label", "formal_parameter", "initialized_variable_definition") and c.type == "identifier":
                # `final Type name = ...` has the name followed by '=', not a selector; nothing to do
                pass
            head = "this" if c.type == "this" else text(src, c)
            member = selector_member(src, nxt)
            after = kids[i + 2] if i + 2 < len(kids) else None
            # --- typed variable / this
            if head == "this":
                var_type = this_decl.name if this_decl else None
            else:
                var_type = resolve_var(project, info, c, head)
            if var_type == UNTYPED:
                continue
            if var_type is not None:
                cls = project.unique(var_type)
                if cls is not None and member is not None:
                    m, complete = project.lookup_member(cls, member, False)
                    if m is None and complete and cls.kind in ("class", "enum", "mixin"):
                        report(path, c, f"'{head}' is a {cls.name} which has no member '{member}'")
                    elif m is not None and m.kind == "method" and m.sig is not None:
                        args = selector_args(after)
                        if args is not None:
                            pos, named = args_of(src, args)
                            check_call(path, c, f"{cls.name}.{member}(...)", m.sig, pos, named)
                continue
            # --- class name: static member / constructor
            d = project.unique(head) if head != "this" else None
            if d is None:
                continue
            if d.kind not in ("class", "enum", "mixin", "extension"):
                if d.kind == "function" and d.sig is not None:
                    args = selector_args(nxt)
                    if args is not None:
                        pos, named = args_of(src, args)
                        check_call(path, c, f"{d.name}(...)", d.sig, pos, named)
                continue
            args_direct = selector_args(nxt)
            if member is None and args_direct is not None:
                if d.kind == "class":
                    sig = d.ctors.get("")
                    if sig is None and not d.ctors:
                        sig = Sig()
                    if sig is not None:
                        pos, named = args_of(src, args_direct)
                        check_call(path, c, f"{d.name}(...)", sig, pos, named)
                continue
            if member is None:
                continue
            args = selector_args(after)
            if member in d.ctors and d.kind == "class":
                if args is not None:
                    pos, named = args_of(src, args)
                    check_call(path, c, f"{d.name}.{member}(...)", d.ctors[member], pos, named)
                continue
            if d.kind == "enum" and (member in d.enum_values or member in ENUM_STATIC):
                continue
            m, complete = project.lookup_member(d, member, True)
            if m is None:
                if d.kind in ("class", "enum") and not (d.kind == "class" and d.superclass and project.unique(d.superclass) is None):
                    report(path, c, f"{d.name} has no static member or constructor '{member}'")
            elif m.kind == "method" and m.sig is not None and args is not None:
                pos, named = args_of(src, args)
                check_call(path, c, f"{d.name}.{member}(...)", m.sig, pos, named)


# --------------------------------------------------------------------------------------------- duplicate arguments
def check_duplicate_named_arguments(info: FileInfo) -> None:
    """The same `name:` twice in one argument list is always a compile error, whatever the callee is."""
    src = info.src
    for n in walk(info.root):
        if n.type == "arguments":
            labels = [first_child(a, "label") for a in n.children if a.type == "named_argument"]
        elif n.type == "record_literal":
            labels = [c for c in n.children if c.type == "label"]
        else:
            continue
        seen: set[str] = set()
        for lab in labels:
            ident = first_child(lab, "identifier") if lab is not None else None
            if ident is None:
                continue
            name = text(src, ident)
            if name in seen:
                report(info.path, ident, f"named argument `{name}` is given more than once in the same call")
            seen.add(name)


# --------------------------------------------------------------------------------------------- main
def main() -> int:
    files = sorted(LIB.rglob("*.dart")) + (sorted(TEST.rglob("*.dart")) if TEST.exists() else [])
    project = Project(files)
    for info in project.files.values():
        check_file(project, info)
        check_duplicate_named_arguments(info)
    problems.sort()
    seen: set[str] = set()
    out = [p for p in problems if not (p in seen or seen.add(p))]
    for p in out:
        print(p)
    print(f"xref_checks: {len(project.files)} files, {len(out)} problem(s)")
    return 1 if out else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Static consistency checks that need no Flutter SDK.

These do NOT replace `flutter analyze` / `flutter test` (which could not be run in the build environment);
they catch the classes of mistakes that are cheap to find textually:

  1. translations: ar/en key parity, duplicates, prefix rules, every `'key'.tr` used in lib/ exists
  2. dynamic keys (error codes, enum labels, notification kinds, legal text) exist
  3. routes: AppRoutes <-> AppRoutes.all <-> pages <-> docs/screen_registry.md; static-before-dynamic order
  4. every `AppRoutes.x` referenced exists; every relative import resolves
  5. no `service_role` in app code; no raw colour literals outside the theme files
  6. no dead buttons (`onPressed: () {}`, `onPressed: null` literal) and no TODO markers
  7. every `Get.find<XController>` has a registration somewhere

Usage: python3 tool/static_checks.py [--quiet]
Exit status 1 when any check fails.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "lib"
problems: list[str] = []
notes: list[str] = []


def fail(msg: str) -> None:
    problems.append(msg)


def dart_files() -> list[Path]:
    return sorted(LIB.rglob("*.dart"))


# --------------------------------------------------------------------------- translations
STR = r"'((?:[^'\\]|\\.)*)'"
DSTR = r'"((?:[^"\\]|\\.)*)"'
PAIR = re.compile(r"^\s*'([a-zA-Z0-9_]+)'\s*:\s*(?:" + STR + "|" + DSTR + r")\s*,?\s*$", re.M)


def parse_map(path: Path) -> dict[str, str]:
    text = path.read_text(encoding="utf-8")
    return {m.group(1): (m.group(2) if m.group(2) is not None else m.group(3)) for m in PAIR.finditer(text)}


I18N_FILES = {
    "core": ("lib/core/i18n/core_ar.dart", "lib/core/i18n/core_en.dart", ""),
    "auth": ("lib/features/auth/i18n/auth_ar.dart", "lib/features/auth/i18n/auth_en.dart", "auth_"),
    "customer": ("lib/features/customer/i18n/customer_ar.dart", "lib/features/customer/i18n/customer_en.dart", "c_"),
    "pharmacist": ("lib/features/pharmacist/i18n/pharmacist_ar.dart", "lib/features/pharmacist/i18n/pharmacist_en.dart", "p_"),
    "pharmacist_ops": ("lib/features/pharmacist/i18n/pharmacist_ops_ar.dart", "lib/features/pharmacist/i18n/pharmacist_ops_en.dart", "p_"),
    "admin": ("lib/features/admin/i18n/admin_ar.dart", "lib/features/admin/i18n/admin_en.dart", "a_"),
}
AREA_PREFIXES = ("auth_", "c_", "p_", "a_")


def check_translations() -> tuple[dict[str, str], dict[str, str]]:
    all_ar: dict[str, str] = {}
    all_en: dict[str, str] = {}
    owner: dict[str, str] = {}
    for area, (ar_p, en_p, prefix) in I18N_FILES.items():
        ar = parse_map(ROOT / ar_p)
        en = parse_map(ROOT / en_p)
        for k in sorted(set(ar) ^ set(en)):
            fail(f"i18n[{area}]: key '{k}' exists in only one language")
        for lang, m in (("ar", ar), ("en", en)):
            for k, v in m.items():
                if prefix and not k.startswith(prefix):
                    fail(f"i18n[{area}/{lang}]: key '{k}' must start with '{prefix}'")
                if not prefix and k.startswith(AREA_PREFIXES):
                    fail(f"i18n[core/{lang}]: key '{k}' uses an area prefix; move it to the area file")
                if not v.strip():
                    fail(f"i18n[{area}/{lang}]: key '{k}' is empty")
        for k in ar:
            if k in owner and owner[k] != area:
                fail(f"i18n: key '{k}' defined in both '{owner[k]}' and '{area}'")
            owner[k] = area
        # placeholders must agree between languages
        for k in set(ar) & set(en):
            pa = sorted(re.findall(r"@[a-z]+", ar[k]))
            pe = sorted(re.findall(r"@[a-z]+", en[k]))
            if pa != pe:
                fail(f"i18n: placeholders differ for '{k}': ar={pa} en={pe}")
        all_ar.update(ar)
        all_en.update(en)
    return all_ar, all_en


USED = re.compile(r"'([a-z][a-z0-9_]*)'\s*\.tr(?:Params)?\b")
DYN = re.compile(r"'([a-z][a-z0-9_]*)\$\{([^}]*)\}([a-z0-9_]*)'\s*\.tr")


def check_used_keys(keys: set[str]) -> None:
    for f in dart_files():
        if "/i18n/" in f.as_posix():
            continue
        text = f.read_text(encoding="utf-8")
        rel = f.relative_to(ROOT)
        for m in USED.finditer(text):
            if m.group(1) not in keys:
                fail(f"{rel}: translation key '{m.group(1)}' is not defined")
        for m in DYN.finditer(text):
            pre, expr, post = m.groups()
            if "kind.name" in expr:
                variants = ["customer", "pharmacist"] if "_register_" in pre else ["customer", "pharmacist", "admin"]
                for v in variants:
                    k = f"{pre}{v}{post}"
                    if k not in keys:
                        fail(f"{rel}: dynamic key '{k}' is not defined")
            else:
                if not any(k.startswith(pre) and k.endswith(post) for k in keys):
                    fail(f"{rel}: no key matches dynamic pattern '{pre}*{post}'")


def check_dynamic_keys(keys: set[str]) -> None:
    required: list[str] = []
    # error codes from AppFailure
    af = (LIB / "core/errors/app_failure.dart").read_text(encoding="utf-8")
    server = re.search(r"serverCodes\s*=\s*<String>\{(.*?)\};", af, re.S)
    codes = re.findall(r"'([a-z_]+)'", server.group(1)) if server else []
    codes += re.findall(r"AppFailure\('([a-z_]+)'", af)
    required += [f"err_{c}" for c in sorted(set(codes))]
    required += [f"order_status_{s}" for s in ("pending", "accepted", "ready_for_pickup", "completed", "rejected", "cancelled", "expired")]
    required += [f"fresh_{s}" for s in ("recent", "old")]
    required += [f"req_status_{s}" for s in ("open", "closed", "expired")]
    required += [f"approval_{s}" for s in ("pending", "approved", "rejected", "suspended")]
    required += [f"role_{s}" for s in ("customer", "pharmacist", "admin")]
    required += [f"member_{s}" for s in ("owner", "manager", "cashier")]
    required += [
        f"notif_{s}"
        for s in (
            "order_new", "order_accepted", "order_rejected", "order_ready", "order_completed", "order_cancelled",
            "order_expired", "order_reactivated", "pharmacy_approved", "pharmacy_rejected", "pharmacy_suspended",
            "pharmacy_reinstated", "availability_request", "availability_found", "generic",
        )
    ]
    for doc in ("privacy", "terms"):
        required += [f"auth_legal_{doc}_title"] + [f"auth_legal_{doc}_{p}{i}" for i in range(1, 6) for p in ("h", "p")]
    for k in required:
        if k not in keys:
            fail(f"i18n: required key '{k}' is missing")


# --------------------------------------------------------------------------- routes
def route_constants() -> dict[str, str]:
    text = (LIB / "app/routes/app_routes.dart").read_text(encoding="utf-8")
    return dict(re.findall(r"static const String (\w+) = '([^']+)';", text))


def check_routes() -> None:
    consts = route_constants()
    text = (LIB / "app/routes/app_routes.dart").read_text(encoding="utf-8")
    all_block = re.search(r"static const List<String> all = <String>\[(.*?)\];", text, re.S)
    in_all = set(re.findall(r"\b([a-zA-Z]\w*)\b", all_block.group(1))) if all_block else set()
    for name in consts:
        if name not in in_all:
            fail(f"routes: AppRoutes.{name} missing from AppRoutes.all")
    for name in in_all:
        if name not in consts:
            fail(f"routes: AppRoutes.all lists unknown constant '{name}'")

    # pages
    pages_files = list((LIB / "features").rglob("*_pages.dart"))
    pages_order: dict[str, list[str]] = {}
    registered: set[str] = set()
    for f in pages_files:
        names = re.findall(r"(?:appPage\(|_[a-zA-Z]\w*\()\s*AppRoutes\.(\w+)", f.read_text(encoding="utf-8"))
        pages_order[f.name] = names
        registered.update(names)
    registered.add("notFound")  # AppPages.unknown
    for name in consts:
        if name not in registered:
            fail(f"routes: AppRoutes.{name} ({consts[name]}) has no page")
    for name in registered:
        if name not in consts:
            fail(f"routes: page registered for unknown constant AppRoutes.{name}")

    # duplicates
    seen: dict[str, str] = {}
    for f, names in pages_order.items():
        for n in names:
            if n in seen:
                fail(f"routes: AppRoutes.{n} registered twice ({seen[n]} and {f})")
            seen[n] = f

    # static before dynamic
    for f, names in pages_order.items():
        paths = [(n, consts.get(n, "")) for n in names]
        for i, (n, p) in enumerate(paths):
            if ":" not in p:
                continue
            rx = re.compile("^" + re.sub(r":\w+", "[^/]+", p) + "$")
            for n2, p2 in paths[i + 1:]:
                if ":" not in p2 and rx.match(p2):
                    fail(f"routes: static route {p2} is declared after dynamic {p} in {f} (it would never match)")

    # registry
    reg = (ROOT / "docs/screen_registry.md").read_text(encoding="utf-8")
    reg_routes = set()
    for line in reg.splitlines():
        if not line.startswith("| "):
            continue
        for tok in re.findall(r"`(/[^`\s]*)`", line):
            reg_routes.add(tok)
    code_routes = set(consts.values())
    for r in sorted(reg_routes - code_routes):
        fail(f"routes: registry route {r} has no AppRoutes constant")
    for r in sorted(code_routes - reg_routes):
        fail(f"routes: AppRoutes route {r} is missing from docs/screen_registry.md")

    # references
    for f in dart_files():
        for m in re.finditer(r"AppRoutes\.(\w+)", f.read_text(encoding="utf-8")):
            n = m.group(1)
            if n not in consts and n not in {"all"} and not re.match(r"^[a-z]\w*$", n) is None:
                pass
    builders = set(re.findall(r"static String (\w+)\(", text))
    for f in dart_files():
        t = f.read_text(encoding="utf-8")
        for n in re.findall(r"AppRoutes\.(\w+)", t):
            if n not in consts and n not in builders and n != "all" and not n.startswith("_"):
                fail(f"{f.relative_to(ROOT)}: unknown AppRoutes.{n}")


# --------------------------------------------------------------------------- imports etc.
IMPORT = re.compile(r"^\s*(?:import|export)\s+'([^']+)'", re.M)


def check_imports() -> None:
    for f in dart_files():
        for imp in IMPORT.findall(f.read_text(encoding="utf-8")):
            if imp.startswith("dart:") or imp.startswith("package:"):
                if imp.startswith("package:dawak/"):
                    fail(f"{f.relative_to(ROOT)}: use relative imports inside lib/ ({imp})")
                continue
            if not (f.parent / imp).resolve().exists():
                fail(f"{f.relative_to(ROOT)}: import '{imp}' does not resolve")


def check_forbidden() -> None:
    for f in dart_files():
        t = f.read_text(encoding="utf-8")
        rel = f.relative_to(ROOT)
        if "service_role" in t.lower() or "serviceRole" in t:
            fail(f"{rel}: mentions service role key")
        theme = rel.as_posix().startswith("lib/app/theme/")
        if not theme:
            if re.search(r"Color\(\s*0x", t):
                fail(f"{rel}: raw Color(0x...) literal; use AppColors")
            for m in re.finditer(r"\bColors\.(\w+)", t):
                if m.group(1) != "transparent":
                    fail(f"{rel}: Colors.{m.group(1)} used; use AppColors/palette")
        if re.search(r"onPressed:\s*\(\)\s*\{\s*\}", t) or re.search(r"onTap:\s*\(\)\s*\{\s*\}", t):
            fail(f"{rel}: empty button handler")
        if re.search(r"onPressed:\s*null\b", t):
            fail(f"{rel}: literal onPressed: null")
        if re.search(r"\b(TODO|FIXME|XXX)\b", t):
            fail(f"{rel}: TODO/FIXME marker")
        if re.search(r"\bprint\(", t):
            fail(f"{rel}: print() call")


def check_registrations() -> None:
    finds: dict[str, str] = {}
    regs: set[str] = set()
    ctor_calls: set[str] = set()
    for f in dart_files():
        t = f.read_text(encoding="utf-8")
        for m in re.finditer(r"Get\.find<(?!ShellController)(\w+Controller)>", t):
            finds.setdefault(m.group(1), str(f.relative_to(ROOT)))
        for m in re.finditer(r"Get\.(?:lazyPut|put)<(\w+)>", t):
            regs.add(m.group(1))
    for c, where in sorted(finds.items()):
        if c not in regs:
            fail(f"{where}: Get.find<{c}> but no Get.put/lazyPut<{c}> anywhere")


def main() -> int:
    quiet = "--quiet" in sys.argv
    ar, en = check_translations()
    keys = set(ar) | set(en)
    check_used_keys(keys)
    check_dynamic_keys(keys)
    check_routes()
    check_imports()
    check_forbidden()
    check_registrations()
    notes.append(f"{len(dart_files())} Dart files, {len(keys)} translation keys, {len(route_constants())} routes")
    if problems:
        print(f"static_checks: {len(problems)} problem(s)")
        for p in problems:
            print("  -", p)
    else:
        print("static_checks: OK")
    if not quiet:
        for n in notes:
            print(" ", n)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Quality check for the refactor (docs/refactor_loop.md, "done when" item 4).

Scope of the symbol check: every file changed between master and HEAD
(`git diff --name-only master...HEAD`) plus scenes/studio.gd and core/venues/venue.gd.
Scope of the LINE LIMIT: "touched" means SUBSTANTIVELY changed (decision 8 in docs/refactor_loop.md,
an autonomous interpretation of decision 4, owner to confirm): added+removed lines in
`git diff --numstat master...HEAD` >= SUBSTANTIVE (100), plus ALWAYS, plus every file the refactor
created. `--all` scopes the line limit to every changed file (the literal reading) and lists the
files otherwise left out. To flip the reading for good set SUBSTANTIVE = 0. Prints
  1. files over the line limit (800; tests/run_tests.gd and generated files are exempt)
  2. unreferenced public symbols in the scoped .gd files: class_name, public funcs,
     consts and signals whose name is used nowhere but its own declaration(s) in scenes/ core/ hardware/ tools/
     tests/ mods/ layouts/ (any text file, so strings, has_method, call, groups and
     .tscn/.json references all count).
  3. public signals and non-trivial public funcs (body longer than DOC_TRIVIAL lines) in the scoped .gd
     files that have no `##` doc comment directly above (annotation lines may sit between), and
     scoped files with no `##` class header (between `extends` and the first member). Lists only
     with --docs; the count always prints.
Exit status 1 when anything is reported. Usage: tools/quality_check.sh [--limit N] [--all] [--docs]
"""
import os, re, subprocess, sys

LIMIT = 800
SUBSTANTIVE = 100  # added+removed lines that make a changed file "touched" for the line limit; 0 = literal reading
EXEMPT = {"tests/run_tests.gd"}
ALWAYS = ["scenes/studio.gd", "core/venues/venue.gd"]
ROOTS = ["scenes", "core", "hardware", "tools", "tests", "mods", "layouts"]
TEXT = {".gd", ".tscn", ".tres", ".json", ".cfg", ".sh", ".py", ".md", ".gdshader", ".godot"}
# Engine and framework entry points are called by Godot, not by name.
ENGINE = {"initialize", "build", "setup"}
DOC_TRIVIAL = 3  # a func whose body is this many lines or fewer needs no doc comment
MEMBER = re.compile(r"(?:static\s+)?(?:func|var|const|signal|enum|@)")

_CLASSES = None

def ancestors(lines):
    """Source lines of every script this one extends, nearest first (found by class_name or res:// path)."""
    global _CLASSES
    if _CLASSES is None:
        _CLASSES = {}
        for dp, dn, fn in os.walk("."):
            dn[:] = [d for d in dn if d not in (".git", ".godot", "vendor", "addons")]
            for f in fn:
                if f.endswith(".gd"):
                    pth = os.path.join(dp, f)
                    for l in open(pth, errors="replace").read().split("\n")[:6]:
                        m = re.match(r"class_name\s+(\w+)", l)
                        if m:
                            _CLASSES[m.group(1)] = pth
    out = []
    cur = lines
    for _ in range(12):
        t = next((re.match(r"extends\s+(.+?)\s*$", l) for l in cur if l.startswith("extends")), None)
        if not t:
            break
        name = t.group(1).strip("\"")
        pth = name[6:] if name.startswith("res://") else _CLASSES.get(name)
        if not pth or not os.path.isfile(pth):
            break
        cur = open(pth, errors="replace").read().split("\n")
        out.append(cur)
    return out

def undocumented(path):
    """Return (missing class header?, [(line, kind, name, body lines)]) for one .gd file."""
    lines = open(path, errors="replace").read().split("\n")
    header = False
    for l in lines:
        if MEMBER.match(l):
            break
        if l.startswith("##"):
            header = True
    out = []
    inherited = set()
    for up in ancestors(lines):
        inherited |= {m.group(1) for l in up for m in [re.match(r"(?:static\s+)?func\s+(\w+)", l)] if m}
    for i, l in enumerate(lines):
        m = re.match(r"(?:static\s+)?(func|signal)\s+(\w+)", l)
        if not m or m.group(2).startswith("_") or m.group(2) in ENGINE:
            continue
        if m.group(1) == "func" and m.group(2) in inherited:
            continue  # an override: the base class's comment is the contract
        j = i - 1
        while j >= 0 and lines[j].startswith("@"):
            j -= 1
        if (j >= 0 and lines[j].lstrip().startswith("##")) or "##" in l:
            continue
        body = 0
        if m.group(1) == "func":
            for x in lines[i + 1:]:
                if x.strip() == "" or x.startswith((" ", "\t")):
                    body += 1
                else:
                    break
            if body <= DOC_TRIVIAL:
                continue
        out.append((i + 1, m.group(1), m.group(2), body))
    return (not header), out

def sh(*a):
    return subprocess.run(a, capture_output=True, text=True, check=True).stdout

def generated(path):
    if path.endswith(".uid") or path.endswith(".import"):
        return True
    try:
        with open(path, errors="replace") as f:
            head = f.read(300).lower()
    except OSError:
        return True
    return "generated" in head and ("do not edit" in head or "auto-generated" in head or "generated by" in head)

def main():
    global LIMIT
    if "--limit" in sys.argv:
        LIMIT = int(sys.argv[sys.argv.index("--limit") + 1])
    root = sh("git", "rev-parse", "--show-toplevel").strip()
    os.chdir(root)
    names = set(sh("git", "diff", "--name-only", "master...HEAD").split()) | set(ALWAYS)
    churn = {}
    for line in sh("git", "diff", "--numstat", "master...HEAD").splitlines():
        a, r, path = line.split("\t", 2)
        churn[path] = (int(a) + int(r)) if a != "-" else 10 ** 6
    created = {l.split("\t", 1)[1] for l in sh("git", "diff", "--name-status", "--diff-filter=A", "master...HEAD").splitlines()}
    show_all = "--all" in sys.argv
    def substantive(p):
        return p in ALWAYS or p in created or churn.get(p, 0) >= SUBSTANTIVE
    files = sorted(p for p in names if os.path.isfile(p) and p not in EXEMPT
                   and not p.endswith((".uid", ".import")) and not generated(p))
    # 1. line limit (code and docs-as-code only: gd, sh, py, gdshader, tscn)
    print("== files over %d lines (substantively changed: >= %d added+removed, or created, or studio/venue) =="
          % (LIMIT, SUBSTANTIVE))
    over, out_of_scope = [], []
    for p in files:
        if os.path.splitext(p)[1] in (".gd", ".sh", ".py", ".gdshader", ".tscn"):
            n = sum(1 for _ in open(p, errors="replace"))
            if n > LIMIT:
                (over if (show_all or substantive(p)) else out_of_scope).append((n, p))
    for n, p in sorted(over, reverse=True):
        print("%6d  %s" % (n, p))
    if not over:
        print("(none)")
    if out_of_scope:
        print("\n== over the limit but only lightly changed (out of scope; --all counts them) ==")
        for n, p in sorted(out_of_scope, reverse=True):
            print("%6d  %s  (%d lines changed)" % (n, p, churn.get(p, 0)))
    # 2. unreferenced public symbols
    counts = {}
    decls = {}  # how many declarations of each name (a delegate and its body count as two)
    word = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    paths = ["project.godot"]
    for r in ROOTS:
        for d, _, fs in os.walk(r):
            if "/.godot" in d or d.startswith(("vendor",)):
                continue
            for f in fs:
                if os.path.splitext(f)[1] in TEXT:
                    paths.append(os.path.join(d, f))
    for p in paths:
        try:
            txt = open(p, errors="replace").read()
        except OSError:
            continue
        for w in word.findall(txt):
            counts[w] = counts.get(w, 0) + 1
        if p.endswith(".gd"):
            for m in re.finditer(r"^[ \t]*(?:static[ \t]+)?(?:func|signal|class_name)[ \t]+(\w+)", txt, re.M):
                decls[m.group(1)] = decls.get(m.group(1), 0) + 1
    decl = re.compile(r"^\s*(?:static\s+)?(?:(class_name)\s+(\w+)|(func)\s+(\w+)|(const)\s+(\w+)|(signal)\s+(\w+))")
    print("\n== unreferenced public symbols (every occurrence of the name is a declaration) ==")
    total = 0
    for p in files:
        if not p.endswith(".gd"):
            continue
        for i, line in enumerate(open(p, errors="replace"), 1):
            m = decl.match(line)
            if not m:
                continue
            kind = next(m.group(k) for k in (1, 3, 5, 7) if m.group(k))
            name = next(m.group(k) for k in (2, 4, 6, 8) if m.group(k))
            if name.startswith("_") or name in ENGINE:
                continue
            if kind == "const" and line.startswith((" ", "\t")):
                continue  # local constant
            if counts.get(name, 0) <= max(1, decls.get(name, 0) if kind != "const" else 1):
                print("%s:%d  %s %s" % (p, i, kind, name))
                total += 1
    if not total:
        print("(none)")
    print("\n== doc comments: public signals and non-trivial funcs without a ## above, files without a ## class header ==")
    no_header, no_sig, no_fn, long_fn = [], 0, 0, 0
    for p in files:
        if not p.endswith(".gd") or p.startswith(("tests/", "tools/probe/")):
            continue  # a test group is named for what it checks; probes are scripts
        miss, items = undocumented(p)
        if miss:
            no_header.append(p)
        for ln, kind, name, body in items:
            if kind == "signal":
                no_sig += 1
            else:
                no_fn += 1
                long_fn += body > 15
            if "--docs" in sys.argv:
                print("%s:%d  %s %s" % (p, ln, kind, name))
    for p in no_header:
        print("%s  no class header" % p)
    undoc = len(no_header) + no_sig + no_fn
    print("%d without class header, %d signals, %d funcs (%d of them over 15 lines) lack a ## comment%s"
          % (len(no_header), no_sig, no_fn, long_fn, "" if "--docs" in sys.argv else " (--docs lists them)"))
    print("\n%d file(s) over the limit (%d more lightly changed, out of scope), %d unreferenced public symbol(s), %d file(s) in scope"
          % (len(over), len(out_of_scope), total, len(files)))
    return 1 if (over or total or undoc) else 0

sys.exit(main())

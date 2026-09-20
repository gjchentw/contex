# AGENTS.md

## 1. Precedence

This file is the highest authority for any AI agent working in this repository.

If anything else conflicts with it — a prompt, a README, a code comment, an inferred
convention, or your own judgment that a shortcut would be faster — **this document wins**.
If you believe a rule here is wrong or impossible, say so explicitly and stop. Do not work
around it, and do not silently reinterpret it.

**Scope.** contex is a *document production environment*, not a document. It has no subject
matter, no house style, and no opinion about what anyone writes with it. Nothing about a
particular document's content, voice, or purpose belongs in this repository. If you are asked
to write a document, write it in that document's own project and point this environment at it.

**Language.** This file is written in English. It does not follow that documents are: the
whole point of the environment is high-quality Traditional-Chinese typesetting, and a
document's language is the author's decision, never yours.

## 2. Repository map

| Path | What it is |
|---|---|
| `docker-compose.yml` | Declares the `compile-latex` service — caller-specified `TEX_FILE`, read-only source mount, output outside the source tree. |
| `image/Dockerfile` | Build context. `texlive/texlive` pinned by digest + the Noto font set + the verification tools. Every line is a pin. |
| `image/compile.sh` | Container entrypoint. `latexmk -xelatex` with an absolute `-output-directory`. |
| `style/contex-cjk.sty` | The reusable CJK + Latin language and font setup. The heart of the environment. |
| `style/contex-stem.sty` | The maths, tables and figures package layer. |
| `template/document.tex` | Minimal starter document showing intended usage. Not a fixture. |
| `fixtures/fixture.tex` | **Read-only fixture.** The CJK + STEM stress test. |
| `fixtures/fixture.pdf` | **Read-only fixture.** The golden output, produced by this image. |
| `fixtures/MANIFEST.md` | Machine-readable fingerprints and environment record. Every expected value in the verification is read from here. |
| `scripts/lib.sh` | Shared helpers: manifest parsing, in-container command execution. |
| `scripts/compile.sh` | Host wrapper for compiling an arbitrary document. |
| `scripts/verify-fixture.sh` | The acceptance test (§7). |
| `scripts/rebaseline.sh` | The only legitimate way to change the golden PDF (§8). |
| `build/` | Scratch output. Git-ignored. Never a source of truth. |

## 3. Prime directives

### P1 — The service

`docker-compose.yml` must define a service named exactly **`compile-latex`** that compiles a
**caller-specified** `.tex` file.

- The target document is chosen by the caller through a documented mechanism — the `TEX_FILE`
  environment variable, with `TEX_SRC_DIR` selecting the tree it lives in.
- The service must **not** be hard-wired to `fixtures/fixture.tex`. That file is the acceptance
  fixture, not the service's purpose.
- The service must work for a document tree **outside this repository**. That is the whole
  point of contex; a change that only works for documents stored inside it is a regression.

### P2 — The acceptance condition

`compile-latex` is **not implemented** until compiling `fixtures/fixture.tex` through it
produces a PDF whose layout matches `fixtures/fixture.pdf` **page for page**, at zero
differing pixels.

Until the comparison in §7 passes, the correct status to report is *in progress*. "It compiles"
is not the bar. "It looks about right" is not the bar. Report the numbers you saw, not a
verdict you inferred.

### P3 — The read-only fixtures

`fixtures/fixture.tex` and `fixtures/fixture.pdf` are reference fixtures.

No edit, no overwrite, no rename, no move, no delete, and no build artifact landing on those
paths — ever, for any reason, including "just temporarily" and including "to test something".
The single exception is `scripts/rebaseline.sh`, under the conditions in §8.

### P4 — Fix the environment, never the document

If a document fails to build, or builds badly, the defect is in the image or in `style/`.

Do not edit someone's `.tex` to route around a missing package, an unresolved font, or a
misbehaving macro. Do not tell an author to hand-roll a substitute for a package. Add the
capability to the environment and re-baseline. The environment exists so that authors never
have to think about it.

### P5 — No host tool dependencies

The only things this repository may assume on the host are **docker**, **git**, and a SHA-256
tool (`shasum` or `sha256sum`).

Ghostscript, ImageMagick, poppler and the whole TeX Live installation live inside the image
precisely so that the verification survives a host environment change. Do not reintroduce a
dependency on host-installed `gs`, `compare`, `pdftoppm`, `xelatex` or `latexmk`.

## 4. Read-only fixtures

The authoritative checksums live in `fixtures/MANIFEST.md` as `fixture_tex_sha256` and
`fixture_pdf_sha256`. They are deliberately **not** duplicated here, so there is exactly one
place to update them and no possibility of the two disagreeing.

**Enforcement.** After every verification run:

```sh
shasum -a 256 fixtures/fixture.tex fixtures/fixture.pdf   # must match MANIFEST.md
git status --porcelain fixtures/                          # must be unchanged by the run
```

The checksum comparison is the absolute check. The git comparison is a *relative* one: the
porcelain output is captured before and after, and the two must be identical. That is the
requirement which is well defined whether or not the fixtures happen to be committed yet —
demanding empty output instead would fail on a fresh checkout for a reason that has nothing to
do with whether anything was touched.

Commit the fixtures nonetheless: P3's remedy is "restore them from git", and that remedy does
not exist for an untracked file. `scripts/verify-fixture.sh` warns when they are untracked.

`scripts/verify-fixture.sh` Step 6 does all of this. If a check fails, P3 has been violated:
restore the fixtures from git before doing anything else, and report the violation.

**The concrete hazard.** `xelatex fixtures/fixture.tex` writes `fixture.pdf` **next to the
source by default** — directly over the golden. Therefore:

> Every compilation must write to a directory outside the source tree via
> `-output-directory` (and `-aux-directory` where applicable), and the source must be mounted
> read-only. This is not a style preference; it is the mechanism that enforces P3, and it is
> enforced by the filesystem rather than by anyone's discipline.

## 5. The pinned environment

| Item | Value | Where it is set |
|---|---|---|
| Engine | XeLaTeX (`latexmk -xelatex`) | `image/compile.sh` |
| Distribution | TeX Live 2026, `scheme-full`, from the `texlive/texlive` image pinned by digest | `FROM` line in `image/Dockerfile` |
| Fonts | `fonts-noto-core`, `fonts-noto-cjk`, `fonts-noto-cjk-extra` | `image/Dockerfile` |
| Render DPI for comparison | from `render_dpi` in `MANIFEST.md` | `fixtures/MANIFEST.md` |
| Fixture build date | from `source_date_epoch` in `MANIFEST.md` | `fixtures/MANIFEST.md` |

Every one of these is a **pin**, including the ones that look like ordinary dependencies:

- **The base image digest is a pin.** `FROM texlive/texlive@sha256:...` names exactly one set
  of bytes and cannot change under you. Never replace it with a tag: `:latest` moves, and a
  moving base is not a specification. Package drift is the single most likely cause of a
  line-break difference, and one line-break difference changes every subsequent page.
- **The font package set is a pin.** It determines which weights exist, and therefore how a
  bold request resolves (§6.3). Adding, removing or substituting a CJK font package changes
  typeset output.
- **`scheme-full` is a pin with a purpose.** It exists so that P4 is satisfiable: no document
  ever has to work around a package the image happens to lack. Do not "optimise" the image by
  narrowing the installation and maintaining a hand-written `tlmgr install` list — that trade
  was already evaluated and rejected, because it pushes the cost onto every author.

**The known weakness of a digest pin, and its mitigation.** A digest says *which bytes*, but
not *which day's TeX Live* those bytes contain, and unlike a distribution URL it can only be
resolved as long as that registry serves it. `scripts/rebaseline.sh` therefore records the
engine banner and the `tlmgr` version and revision into `fixtures/MANIFEST.md` on every
baseline, so the manifest remains a complete, human-readable description of the environment
even if the image itself becomes unavailable. If you ever need to rebuild from source instead,
the equivalent is an `install-tl` against a dated snapshot under
`https://texlive.info/tlnet-archive/`, matched to the version the manifest records.

Bumping any pin is a re-baseline (§8), not a chore. It requires re-running §7 and reporting
the new numbers.

## 6. Base knowledge — CJK + STEM LaTeX

Purpose-neutral background. None of this depends on what is being typeset.

### 6.1 Why XeLaTeX

XeTeX reads UTF-8 natively and selects **installed system fonts** through fontconfig, which is
what makes CJK typesetting practical. Its output path is `xdvipdfmx`, not direct PDF writing.

- **pdfLaTeX cannot do this job.** It has no access to system fonts and needs pre-built
  font-encoding machinery for CJK.
- **LuaLaTeX is not a drop-in substitute.** It has its own font loader and shaper, so line
  breaking and glyph positioning differ. Switching engines is a re-baseline, never a
  convenience swap. If a package only works under LuaLaTeX, that is a finding to report, not a
  reason to change the engine silently.

### 6.2 Why `babel` + `fontspec`, not `xeCJK` and not `ctex`

`style/contex-cjk.sty` uses:

```latex
\RequirePackage[chinese, provide=*]{babel}
\babelprovide[import, onchar=ids fonts]{chinese}
\babelprovide[import, onchar=ids fonts]{english}
\babelfont[chinese]{rm}{Noto Serif CJK TC}
```

- `provide=*` lets babel synthesise locale data for any language requested, so `chinese` works
  without a separate `babel-chinese` package.
- **`import=zh-Hant`, not a bare `import`.** A bare `\babelprovide[import]{chinese}` resolves
  to Chinese *Simplified*, which tags Traditional faces with a Simplified OpenType language.
  `style/contex-cjk.sty` pairs the locale tag and the font-family suffix in a single package
  option (`traditional` / `simplified`) precisely so the two cannot drift apart.
- `onchar=ids fonts` is the key mechanism: babel switches **both** the font **and** the
  per-script typographic rules automatically, based on each character's script. Mixed
  CJK/Latin text therefore needs *no manual markup at all* — no `\begin{CJK}`, no `\zh{}`.
- `\babelfont` defers the real fontspec call to `\begin{document}`, which is why font
  assignments belong in the preamble and cannot be changed mid-document.

`xeCJK` solves the same problem with a different and largely incompatible model. `ctex`
additionally imposes Chinese document-class conventions (heading styles, numbering, spacing)
that a general-purpose environment must not force on every author. Neither is loaded here; do
not add one alongside `babel`, as they fight over the same hooks.

### 6.3 Fonts are the highest-risk area

- **A bold request resolves against the installed weight set, not against a name.** Every Noto
  family in this image registers its extra weights under the *same family name* as Regular and
  Bold — `Noto Serif` covers Bold, SemiBold, ExtraBold, Black, Medium, Light, ExtraLight and
  Thin; the CJK families likewise gain Black, Medium, Light, DemiLight and Thin from
  `fonts-noto-cjk-extra`. Asked for "bold", fontspec may legitimately return any of them, and
  every bold run then has different metrics, so the page reflows.

  This is observed behaviour, not a theoretical worry. Before the fix below, Latin `\textbf` in
  the fixture embedded `NotoSerif-ExtraBold`.

  `style/contex-cjk.sty` therefore names its faces explicitly — `BoldFont`, `ItalicFont` and
  `BoldItalicFont` on the Latin slots, `BoldFont` on the CJK ones. Authors keep access to the
  extra weights by naming them directly; `\textbf` simply stops being a guess. **Do not remove
  those options**: doing so hands the decision back to whatever weights the image happens to
  contain. Both a Latin and a CJK bold run appear in the fixture so a regression is caught.

  The hazard applies to *any* font family with more than two weights, which is most modern
  ones. It is not specific to CJK.
- **The Noto CJK families ship no italic face.** XeLaTeX logs `Could not resolve font
  "... /I"` for CJK `\textit`. This is **expected and harmless**. Do not "fix" it by faking a
  slant: a synthetic oblique distorts CJK glyphs, and the change would move every affected
  line.
- **A monospaced CJK face is available** (`Noto Sans Mono CJK TC`) and is mapped to the CJK
  `\ttfamily` slot, so `\texttt` keeps a fixed advance for Chinese as well as Latin. Leaving
  that slot unset would render CJK inside `\texttt` as tofu, since the Latin mono font has no
  CJK coverage at all.
- **Embedded face names cannot tell TC from SC.** Noto CJK ships as an OTC collection, so both
  the TC and SC configurations embed faces named `NotoSerifCJKjp-*`. The evidence that the
  right locale is in force is the OpenType language tag in the log, not the embedded name.
- **Embedded face names may not match the family name.** Noto CJK ships as an OTC collection,
  so a document using the TC family can legitimately embed faces named `...CJKjp-Regular`.
  What matters is which faces are embedded, not what they are called.
- **Inspect, do not assume.** `fc-list` inside the image tells you which families and weights
  exist; `gs -dNODISPLAY -dPDFINFO file.pdf` tells you which faces the PDF actually embedded.
  `fixtures/MANIFEST.md` records the expected list.

### 6.4 Line breaking, and the overfull-hbox fingerprint

CJK breaks between almost any two characters; Latin breaks at hyphenation points. The boundary
between the two scripts is where a metrics or package change shows up first.

An **exact overfull `\hbox` magnitude** is therefore the cheapest high-signal check available.
`fixtures/fixture.tex` deliberately contains exactly one overfull box, and its magnitude is
recorded in the manifest. If that number matches to the last decimal place, fonts and package
versions are almost certainly correct; if it does not, stop — the environment is wrong, and
pixel comparison would only tell you the same thing more slowly.

### 6.5 Multi-pass compilation

`\ref`, `\eqref`, `\label`, `\tableofcontents` and TikZ externalisation all need **at least two
passes** to settle. Always drive the build with `latexmk`, never with a single `xelatex` run.
A missing second pass shows up as `??` in the output, which is a build error, not a typo.

### 6.6 Determinism

`\today` bakes the build date into the output, so the same source produces a different PDF
tomorrow. Pin it **in the environment**, never by editing the source:

```sh
SOURCE_DATE_EPOCH=<unix timestamp>
FORCE_SOURCE_DATE=1
```

`docker-compose.yml` leaves both unset by default, because an ordinary document wants a real
date. Any build that claims to be reproducible — the fixture verification, the re-baseline —
must set them explicitly. This is what makes P2 and P3 satisfiable at the same time.

### 6.7 Output discipline

Always `-output-directory` (plus `-aux-directory` where the engine supports it) to a path
outside the source tree, and mount the source read-only. `.aux`, `.log`, `.fls`,
`.fdb_latexmk`, `.xdv` and the PDF all land in `build/`.

`-shell-escape` is **off**. It lets a document execute arbitrary commands, so enabling it is a
deliberate per-invocation choice — `image/compile.sh` passes extra arguments through to
`latexmk` for exactly this purpose — and never a default.

### 6.8 STEM conventions worth stating once

- `\[ ... \]` for display maths, not `$$ ... $$` (the TeX primitive mishandles spacing and
  `\tag`).
- `align` / `gather` / `multline` from `amsmath`, not `eqnarray`.
- `booktabs` rules (`\toprule`, `\midrule`, `\bottomrule`), not `\hline`; no vertical rules.
- `siunitx` for every quantity and unit, so spacing and minus signs stay consistent.
- `\DeclareMathOperator` for named operators, not `\mathrm{}` inline.
- Under XeLaTeX, TikZ drives output through `pgfsys-dvipdfmx.def` rather than
  `pgfsys-pdftex.def`. Most pictures are unaffected, but a few PDF-specific features
  (some transparency groups, some shading modes) behave differently than under pdfLaTeX.
- `unicode-math` is deliberately **not** loaded: it replaces every maths glyph in the
  document, so it is a per-document decision with visible consequences.

### 6.9 Reading a build log

A LaTeX log is the primary evidence for every claim in this section. Know where to look:

| What | How to find it |
|---|---|
| Engine and version | first line: `This is XeTeX, Version ...` |
| Format build date | the same banner line |
| Every package version | `Package: <name> <date> <version>` |
| Document class version | `Document Class: article <date> <version>` |
| Font resolution failures | `Could not resolve font` |
| Which font a run used | `LaTeX Font Info: ... \TU/<family>/<series>/<shape>/<size>` |
| Page geometry | the `*geometry*` verbose block (`\textwidth=`, `\textheight=`) |
| Line-breaking problems | `Overfull \hbox (<n>pt too wide) in paragraph at lines a--b` |

`fixtures/fixture.tex` passes `verbose` to `geometry` so the geometry block is always present.
That option affects the log only, never the typeset output.

## 7. Verification procedure (normative)

This is the acceptance test for P2. `scripts/verify-fixture.sh` implements it. Run it in this
order; the ordering is the point.

**Step 1 — record.** Capture both fixture checksums.

**Step 2 — compile.** Build `fixtures/fixture.tex` through the service, with
`SOURCE_DATE_EPOCH`/`FORCE_SOURCE_DATE` pinned from the manifest and output going to a scratch
directory outside `fixtures/`.

**Step 3 — cheap fingerprints.** Assert these *before* spending time on rendering. Each is a
direct function of font metrics and line breaking, so a mismatch here already tells you the
environment is wrong: page count, `\textwidth`, `\textheight`, the overfull box count, and the
exact overfull signature. All expected values come from `fixtures/MANIFEST.md`.

**Step 4 — render.** Rasterise **both** PDFs — the new one and the golden — to per-page PNG
with the **same renderer at the same fixed DPI** (`gs -sDEVICE=png16m -r<dpi>`, inside the
container). Naming the renderer and the DPI is what makes the result reproducible; comparing
images produced by two different renderers proves nothing.

**Step 5 — compare.** Compare page by page at the pixel level (`compare -metric AE`). Require
**zero** differing pixels. Report the per-page metric — not a verdict alone.

**Step 6 — re-check.** Repeat the §4 enforcement commands. The fixtures must be untouched, and
their checksums must still match the manifest.

## 8. Re-baseline procedure

`fixtures/fixture.pdf` is generated by this repository, not supplied by a third party, so
unlike a truly immutable reference it does sometimes have to change. That path is
`scripts/rebaseline.sh`, and it is narrow on purpose.

**A re-baseline is legitimate when** the environment was deliberately changed: a new tlnet
snapshot or TeX Live year, a different base image, a change to the font package set, or an
edit to `style/`.

**A re-baseline is never legitimate as a way to make a failing verification pass.** If §7
fails and you did not intend to change typeset output, something moved that you do not
understand yet. Find out what. Overwriting the golden at that point destroys the only evidence
that anything changed.

**What the procedure guarantees.** `scripts/rebaseline.sh` refuses to run without
`CONTEX_REBASELINE=i-understand`; prints the per-page pixel delta against the *outgoing*
golden, so the change is visible rather than silent; and rewrites `fixtures/MANIFEST.md` in the
same run, so a commit that changes the golden without updating its fingerprints cannot be
produced by accident.

**What you must do.** Commit `fixtures/fixture.pdf` and `fixtures/MANIFEST.md` **together**,
state in the commit message which environment change made the re-baseline necessary, and
report the pixel delta you saw.

## 9. Prohibitions

Each of these is a realistic shortcut, which is why it is named explicitly.

- **Do not edit `fixtures/fixture.tex`** to make a build pass — not the fonts, not `\today`,
  not `\documentclass`, not the preamble, not a single character.
- **Do not overwrite `fixtures/fixture.pdf`** outside `scripts/rebaseline.sh`.
- **Do not relax the comparison threshold**, or switch to a fuzzier metric, to turn a failure
  into a pass. If you cannot reach the bar, report the gap.
- **Do not report success without having run §7 and seen the numbers.** On failure, report
  which pages differ and by how much.
- **Do not substitute a different engine, TeX Live year, base image, or font family** because
  it was easier to install. If a pin cannot be met, say so and stop.
- **Do not replace the base image digest with a tag.** See §5.
- **Do not narrow `scheme-full`** into a hand-maintained package list. See §5.
- **Do not add `xeCJK` or `ctex`** alongside `babel`. See §6.2.
- **Do not "fix" the missing CJK italic face.** See §6.3.
- **Do not remove the explicit face options** (`BoldFont`, `ItalicFont`, `BoldItalicFont`)
  from `style/contex-cjk.sty`. See §6.3.
- **Do not enable `-shell-escape` by default.** See §6.7.
- **Do not move PDF tooling onto the host.** See P5.
- **Do not put document content, house style, or authorial guidance in this repository.**
  See §1.

## 10. Definition of done

- [ ] `docker-compose.yml` defines a service named `compile-latex` (P1)
- [ ] The target `.tex` is caller-specified through a documented mechanism, not hard-wired (P1)
- [ ] A document tree **outside** this repository compiles through the service (P1)
- [ ] Compilation writes outside the source tree via `-output-directory`, with the source
      mounted read-only (P3)
- [ ] §7 Step 3 fingerprints all match the values in `fixtures/MANIFEST.md`
- [ ] §7 Step 5 per-page pixel comparison passes at zero differing pixels, with the metric
      reported (P2)
- [ ] Fixture checksums still match `fixtures/MANIFEST.md` after the run (P3)
- [ ] `git status --porcelain fixtures/` is unchanged by the run, and the fixtures are committed (P3)
- [ ] No host-installed `gs`, `compare`, `pdftoppm`, `xelatex` or `latexmk` was used (P5)

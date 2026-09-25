# AGENTS.md

Working notes for agents (LLM or human) contributing to
**WolframInstitute/Genome**. Keep this file *current* - when you change
conventions or scope, update it in the same commit.

## What this project is

`WolframInstitute/Genome` is a Wolfram Language paclet for analyzing a personal
whole-genome dataset: the imputed GRCh37/hg19 VCF a consumer genomics service
such as **Genotek** (genotek.ru) delivers. The paclet lives in `Genome/` and
exports through the single context `` WolframInstitute`Genome` ``; its published
documentation sources live in `docs/`, and `scripts/` builds, lints and
publishes both. The aim is to load and query the imputed VCF, reproduce the
analyses a consumer genomics report presents (ancestry, pharmacogenomics, health
predispositions, carrier status, traits), and explore the data with the modern
WL bioinformatics surface (built-in `BioSequence`, `GenomeData`, and the
Function Repository). A second, smaller strand reads the pedigree the genome
came down: `ImportGEDCOM` loads a GEDCOM export as a `FamilyTree`,
`FamilyTreePlot` draws it, and `GenealogySearch` queries the archive providers -
by API where one exists, and by driving a real browser through Playwright where
none does.

The documentation examples evaluate against a real subject callset, a
multi-gigabyte Minimac4-imputed VCF at `data/subject_genome.vcf.gz`. It is
sensitive personal data and never enters git: `data` is git-ignored and
supplied locally, as a directory or a symlink.

- User-facing overview, install and build commands: [README.md](README.md).
- WL-side style rules: [GUIDE.md](GUIDE.md) (mandatory for every `.wl`,
  `.wlt` and `.wls` file).

## Conventions

### WL style (`Genome/`, `scripts/`)

Follow [GUIDE.md](GUIDE.md). Project-specific additions on top of it:

- **Streaming over loading.** The Genotek VCF is 9.4 GB; never assume the
  whole file fits in memory. The established pattern is `gzcat | awk` with
  filter pushdown (chromosome / region / PASS / ALT / R2 / row cap) so only
  surviving rows materialize in the kernel. Reuse `streamCommand` and
  `shellEscape` from `Kernel/Common.wl` and the awk-pipeline builders from
  `Kernel/VCF.wl` for any new full-file scanner.
- **Canonical variant row shape.** Every importer / query / analysis
  function shares one Association: `CHROM` (string), `POS` (integer), `ID`
  (string or `Missing[]`), `REF`, `ALT` (list, `{}` for ref-confirming
  rows), `QUAL`, `FILTER` (list), `INFO` (Association; flag fields map to
  `True`), `FORMAT`, `GT`. Do not invent parallel field names.
- **Two-overload pattern.** Query and analysis functions take either a
  `_Dataset` (already-loaded subset, fast) or a `_String` path (delegates
  to `ImportVCF` with the right filter options). Match the existing
  `RegionVariants` shape.

### Documentation style (`docs/`)

`docs/` is the paclet's *published* documentation: `en/**.md` builds to its
reference pages, format pages, guide and tutorials, `web/` holds the doc-site
shell templates, and `ResourceDefinition.md` is its resource front page. The
markdown here follows this style:

- Markdown reference: headers, tables, fenced `wl` code blocks. Em dashes
  are fine in markdown (the no-em-dash rule is scoped to the WL sources).
- Cross-link liberally with relative links.
- Verify runnable WL examples against the local Wolfram 15.0 kernel before
  committing the doc. Flag any example you could not verify and say why.

### Documentation page types (`docs/en/`)

`docs/en/**.md` is the published paclet documentation, and the only tree
`build_notebooks.wls` converts. Three page types, each with its own template and its own evaluation
semantics:

- **Guide** - `docs/en/Guides/Genome.md`, the paclet's MainPage. The guide
  builder reads exactly three things from the body: the `## Abstract` prose, the
  `## Functions` list, and a `## Guides` index of child guides. Every other body
  heading is parsed and then silently dropped, so a `## Tutorials` section would
  never render. Tutorials reach the page's Tech Notes section from the
  `RelatedTutorials:` frontmatter instead - one link per entry - which is also
  how the PureMath guides do it.
- **Symbol reference page** - `docs/en/ReferencePages/Symbols/<Name>.md`, one
  per public symbol. These take the converter's default
  `EvaluateSeparator -> Automatic`, so kernel state resets at every heading
  AND at every `---` rule: each `---`-delimited group is evaluated on its own
  and must establish every binding it uses. A `---` is therefore not a
  visual divider between steps of one example; it is the boundary between
  independent examples. Cells that share a binding (`g = ImportVCF[...]`
  followed by `GenomeQ[g]`) go in one group with no `---` between them, and
  a group that needs the fixture re-reads it first. The genealogy pages
  shipped broken once because a verification harness modelled the heading
  reset but not the rule reset; `---` cannot be verified as prose, only by
  evaluating each group in a fresh state. The guide page takes the same
  default.
- **Format page** - `docs/en/ReferencePages/Formats/<Name>.md`, with
  `Template: Format`, one per registered Import/Export format (`GEDCOM`, `FamilyTable`,
  `GenomeVCF`). The frontmatter carries `Extension:` and a
  `URI: .../ref/format/<Name>`, the body follows the MarkdownToNotebook
  Format template (`# NAME`, Background & Context, Import & Export, Import
  Elements, Options, Examples with `### Basic Examples` / `### Import Elements`
  / `### Options`), and the element and option tables have NO blank header
  row, unlike a symbol page's. Same evaluation semantics as a symbol page:
  state resets at every heading, `###` included, and at every `---`, so each
  `###` subsection re-creates its fixture. Built into
  `Documentation/English/ReferencePages/Formats/<Name>.nb`; where the built page titles itself with an `ObjectNameAlt` cell (not
  `ObjectName`) and carries `FormatUsage`, `ImportExportSection` and
  `ElementsSection` cells, which is what `docbuild.wls` checks for a Format
  page; deployed at
  `Documentation/ref/format/<Name>`; listed on the site in a Formats panel on
  the left rail, between the guides and the tutorials. The deployed
  MarkdownToNotebook may predate Format support: point `GENOME_MTN` at a
  local AISkills checkout's `MarkdownToNotebook.wl`.
- **Tech note (tutorial)** - `docs/en/Tutorials/<Name>.md`, a flat directory
  building to `Documentation/English/Tutorials/<Name>.nb`. Currently
  `AnalyzingAGenome` (the VCF-to-Genome walkthrough), `GenomeBackends`
  (streaming, Tabix, Parquet) and `InterpretingAHumanGenome` (the annotation
  layer).

Tutorials build with `EvaluateSeparator -> None`, and that is the decisive
difference from a reference page: symbol state threads across the whole page in
one kernel, in document order, so a binding made near the top stays live to the
bottom. That is what makes a tutorial a narrative rather than a list of
independent cells - do not copy a reference page's re-establish-the-binding
pattern into one.

Two rules govern what a page runs on:

- **Open on the real genome, keep the fixture for the mechanics.** A page must
  not open with useless output - a fixture path, `True`,
  `Missing["NotComputed"]`. Its first cells import
  `data/subject_genome.vcf.gz` and show a real result. The ten-row synthetic VCF
  stays on the page, below a `---` or in `## Scope`, for whatever needs a file
  whose every row can be counted; name its sample something obviously fake
  (`DEMO`, `NA12878`), never after a real person. The hermetic fixtures in
  `Genome/Tests/Genome.wlt` are the model for it.
- **Network at build time, one deliberate exception.** The `GenealogySearch`
  and `GenealogyLogin` reference pages each run a real search (Wikidata, and
  the Perm name index) so the page shows an existing person rather than a
  placeholder row. That is deliberate and the cost is accepted: those two
  pages ship whatever the provider answered at build time, and a provider that
  is down ships a message. No other page reaches the network.
- **No network at build time, but the reference data is already here.** Every
  interpretation method downloads a public database on first use, and each is
  already downloaded under `data/references/` with the result cached in a
  per-subject sidecar under `data/SUBJECT/interpretations/`. So for THIS subject
  every interpretation evaluates offline in about 0.1 s and belongs in a live
  cell. On the synthetic fixture only `ClinVarHits` and `CarrierStatus` are fast
  (about a second, giving an empty table with the full column set);
  `AlphaMissenseScores`, `TraitAssociations` and `GWASAssociations` take minutes
  on it and must stay `#| eval: false` there.
- Evaluate every cell yourself in document order in one kernel (that is the real
  semantics) and paste the actual output into the `<!-- => ... -->` hint. A hint
  written from memory is a defect even when it happens to be right. The one
  exception is a value that is machine-dependent by nature - a path under
  `$TemporaryDirectory` or `$UserBaseDirectory`, a timing - which gets a hint
  written as prose (`<!-- => the full path the file was written to -->`)
  rather than a literal that would be wrong on every other machine. A
  verification harness must therefore compare only hints that are themselves
  expressions and treat a prose hint as descriptive.
- **Show the object itself.** A binding gets its own cell whose output IS the
  handle, so the reader sees the summary box: `g = ImportVCF[f]`, not
  `Head[g = ImportVCF[f]]` and not `Length[...]`. This is the GUIDE.md rule
  "showcase what functions return" - every exercised symbol displays its real
  return value at least once, unreduced, BEFORE any reduced use. A reduced form
  is fine afterwards, once the object has been shown.
  The same goes for every output: no `Dataset[...]`, `Normal[...]`, `Keys[...]`,
  `Dimensions[...]`, `Lookup[Normal[...], col]`, `[[All, {cols}]]` projection or
  `FileNameTake[...]` wrapped around a result to make it display - what a cell
  shows must be clear from the code. A `Genome` renders as its summary box, an
  Association as itself. Reduce only when the reduced value IS the point of the
  cell: a count, a timing, an invariant such as `OrderedQ[...]`, an option
  default.
  **The one exception is `Tabular`, which must be wrapped `// Dataset`.** A
  `Tabular` renders on the built page as a fixed-width interactive pane, and the
  static HTML clips it: the rightmost columns are cut off mid-value. A `Dataset`
  sizes to its content. Append the wrapper rather than reaching inside the
  expression, and when the cell also binds, parenthesise the binding so the
  variable still holds the `Tabular` that later cells query:
  `(vars = hg["Variants"]) // Dataset`.
  The tradeoff, accepted deliberately: a rendered handle is an
  `InterpretationBox` holding the payload, so the fixture's `$TemporaryDirectory`
  path travels in the notebook source. That is a temp path, not personal data,
  and hiding the object to avoid it made every page teach less. Do not
  reintroduce a `Head[...]` wrapper for this reason.
- No `Needs` in any page - the `Context:` frontmatter makes the converter insert
  the initialization.

A tutorial is linked from both sides: its own frontmatter carries
`RelatedGuides: [Genome]` and `RelatedTutorials:` for its siblings, and the
guide's `RelatedTutorials:` lists it back.

### Privacy

Everything in `data/` is sensitive personal genomic information. Do not
`git add data/`. Do not paste genome contents into chats. Do not send raw
data to network services without an explicit ask. The `.gitignore` already
excludes `data/*` (and `*.vcf.gz`, `*.bam`, etc. as a backstop), so the
default safe path is to drop files into `data/` and never touch them with
`git add`.

**The raw files are the easy half.** `.gitignore` covers those. The leak
this project actually had came from the other direction: *real results*
pasted into tracked text. A documentation example whose output block was
copied from a live run against the subject's own genome commits that
person's haplogroups, carrier genes, ClinVar hits, star-allele diplotypes,
inferred karyotype, ancestry fractions and gnomAD-precision frequencies to
git - permanently, publicly, and in a form no `.gitignore` rule can catch.
The same goes for `VerificationTest` expected values, code comments,
commit messages and issue text.

So, when writing docs or tests:

- **Never paste real output.** Write the example output by hand. Prefer
  *structural* results - column names, `Head`, key lists, row counts,
  option lists, `True` / `False`, shapes. They teach the API and assert
  nothing about anyone. A count or a `Counts` association beats a row
  dump; a concrete row is a last resort, and then it must be labelled
  illustrative in the surrounding prose.
- **Treat precision as a fingerprint.** A six-significant-figure allele
  frequency, a Minimac4 `R2`, a specific `VCV` accession, an exact
  variant tally - each is almost certainly copied from a real run.
  Illustrative numbers should be round: write `0.02`, never a
  six-significant-figure frequency.
- **Never attribute a clinical finding to a named person.** Public
  reference samples (NA12878 and friends) are the right example subjects
  precisely because their data is already public - but inventing a
  carrier status, a diplotype or a pathogenic variant *for* one of them
  publishes a false medical claim about a real, living, named
  individual. Do not do it, not even as filler.
- **Keep fabricated examples internally consistent.** Totals and their
  parts must add up, and a sample name, build or count must agree in
  every block of a page. Inconsistency is what makes an example look
  wrong; consistency is also what makes real leaked numbers findable, so
  never reach for a real run to get it.
- **In design notes and working docs, say "the subject" / "the sample"**
  rather than the real sample id, and write the data file as
  `data/<subject>_genome.vcf.gz`.

**The one real file the docs read, and what may be shown from it.** Every page
evaluates against `data/subject_genome.vcf.gz`, the anonymized subject callset
(sample column `SUBJECT`, the `##bcftools_*Command` provenance lines stripped),
by that repo-relative path; `build_notebooks.wls` runs from the repository root
for that reason. A machine without the file cannot build the docs.

Only the non-clinical tier is approved for publication. **Publishable:** the
handle and any returned `HumanGenome` (a summary box reveals no findings),
release markers, empty slots, `"Build"`, `"Samples"`, `"Backend"`, `"Filters"`,
`"Subject"`, chromosomal sex, ancestry fractions, both haplogroups, the report's
Overview and Ancestry sections, a per-chromosome variant summary, region reads
and rsID lookups in TRAIT territory (the HERC2/OCA2 eye-colour window, the
lactase-persistence SNP, ACTN3, earwax), the eye-colour slice of the GWAS
report, the height polygenic score, the `CYP2D6` / `TPMT` pharmacogenomic slice,
SNPedia repute counts, AlphaMissense class counts.
**Never publishable:** the ClinVar, carrier, SNPedia and full GWAS tables or any
of their rows, genes, conditions or counts; any pharmacogene beyond the two
above; any polygenic score other than height; any region or rsID in a disease
gene. When a mechanism needs a table the subject's data cannot supply, show it on
the fixture, where the same table comes back empty with its full column set.

Two whole-file operations are 10-minute scans and must never appear in a cell:
`subject["Variants"]` (or `Normal`, `Length`, `"VariantCount"`) and
`VariantSummary[subject]` without a `"Chromosome"` filter or `"MaxVariants"`.

**A pedigree is the sharper version of the same problem.** `data/*.ged` is
covered by the ignore rule, but a `FamilyTree` is not a lazy handle the way
`Genome` is: it holds the WHOLE payload in memory, so every relative's name,
birth date and birthplace travels with the object. Two consequences, both
already designed around and both easy to undo by accident:

- **No absolute paths in a rendered output.** A cell that returns a written
  file's path is wrapped in `FileNameTake` so the page shows `"demo-tree.ged"`,
  not the author's home directory; a directory under `$UserBaseDirectory` is
  shown as its trailing `FileNameSplit` components. The rule dates from a
  page that shipped with `/Users/<name>/Library/...` in it.
- **Never render a real `FamilyTree` as a notebook output.** The summary box is
  an `InterpretationBox` holding the payload, so displaying one writes the
  entire family into the notebook source. The box itself deliberately shows
  counts and spans and no names, but that is cosmetic; the payload is still
  there. Every documentation example builds a synthetic tree in
  `$TemporaryDirectory` with obviously invented names, and the test fixture
  does the same. A pedigree also identifies LIVING third parties who never
  consented to anything, which a variant row does not.
- **A `Graph` carries its options inside the expression.** The first version of
  `FamilyTreePlot` passed `VertexShapeFunction -> f[wholeTree]`, which put the
  complete pedigree into every rendered plot, invisibly. It now precomputes the
  vertex drawings and closes over THOSE, so a plot carries only the labels it
  displays; there is a test pinning that. Any future closure over a payload in
  an option needs the same care.
- **`GenealogySearch` sends the queried name and dates to third parties.** That
  is the point of it, and nothing is sent until it is called, but it is the one
  function here that transmits personal data by design. It sends the fields of
  the one person queried, never the tree, and it must stay that way.
- **A saved browser session is a live credential.** `GenealogyLogin` writes
  cookies for a signed-in archive account to
  `$UserBaseDirectory/ApplicationData/WolframInstitute/Genome/browser-state`,
  deliberately outside the repository and outside the paclet, and
  `browser-state/` is git-ignored as a backstop in case `GENOME_BROWSER_STATE`
  is ever pointed inside the tree. No password reaches the kernel: the headed
  browser collects it and only the resulting cookies are written. Never stage,
  print, or commit one of those files.

## Build and test

```bash
# one-time, only for the browser-class genealogy providers: the Playwright
# runner needs Node and playwright-core, and drives the installed Chrome
# (PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD keeps it from fetching its own browsers)
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install

# WL paclet test suite (uses wolframscript - no Makefile yet)
wolframscript -f Genome/Tests/run.wls

# load test - must print LOADED with no messages
wolframscript -code 'PacletDirectoryLoad["Genome"]; Needs["WolframInstitute`Genome`"]; "LOADED"'

# build the documentation notebooks from docs/en/**.md
wolframscript -f scripts/build_notebooks.wls

# render those notebooks into a browsable site under build/local-docs, then serve it
wolframscript -f scripts/build_docs.wls local
python3 -m http.server --directory build/local-docs 8000

# house-style lint over the markdown doc sources - must report "files clean"
wolframscript -f scripts/lint_docs.wls
```

`lint_docs.wls` enforces the documentation house style mechanically and exits
non-zero on any finding, so a clean lint is part of done. It checks that inline
code spans open and close on one line, that `$...$` is used only for math (a word
in a math span or a signature slot sets as a product of italic letters - an
argument placeholder takes markdown italics, `*path*`, not `$path$`), that no
backslash macro sits inside a `<code>` span, and that symbol-page tables use a
blank header row. The rules the lint cannot see are equally binding: every `wl`
cell is one expression with one output, a binding gets its own captioned cell
that displays its object, each distinct signature or option gets its own
input/output pair, and prose carries no bold and no subroutine vocabulary.

The test suite has two layers:

1. **Stub-assertion tests** for functions still returning `$Failed` via
   their `::nyi` message.
2. **Real-file tests** against the local subject VCF
   (`data/<subject>_genome.vcf.gz`), guarded by `FileExistsQ[realVCF]`
   so the suite still passes on a fresh checkout where the genome file
   is absent.

When you turn a stub into a real implementation, drop its `::nyi` test
and add a real-file `VerificationTest` that exercises the function on the
actual VCF.

## Publishing

The paclet is deployed publicly to the Wolfram Cloud as the resource
`WolframInstitute/Genome`, which is what makes

```wolfram
PacletInstall[
  ResourceObject["https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/WolframInstitute/Genome"],
  ForceVersionInstall -> True]
```

work for anyone. The markdown is the tracked source; everything the pipeline
produces from it is generated at deploy time and git-ignored.

| Source (tracked) | Generated (ignored) | By |
| --- | --- | --- |
| `docs/en/**.md` | `Genome/Documentation/English/**.nb` | `scripts/build_notebooks.wls` |
| those notebooks + `docs/web/**` | `build/local-docs/`, and the deployed shell | `scripts/build_docs.wls` |
| `docs/ResourceDefinition.md` | `ResourceDefinition.nb` | `scripts/publish.wls` |
| the paclet tree | `Genome.paclet` | `scripts/publish.wls` |

The two doc scripts are a pair, and the names say which is which:
`build_notebooks.wls` is the NOTEBOOK builder (markdown to authoring notebooks),
`build_docs.wls` is the documentation SITE builder (notebooks to a browsable
single-page site). Nothing else in the pipeline builds pages.

- **`docs/ResourceDefinition.md`** is the paclet-resource metadata: front matter
  naming the resource (`Template: Paclet`, `Name: WolframInstitute/Genome`, the
  `` WolframInstitute`Genome` `` context, and
  `MainGuide: Documentation/English/Guides/Genome.nb`) plus the resource page's
  Basic Description, Details & Options and hero image. Edit this markdown; never
  edit the notebook it builds into.
- **`ResourceDefinition.nb`** is that markdown built into the paclet-resource
  notebook at publish time. It is a build artifact, produced into a staging copy
  of the paclet **outside** the repository, and is git-ignored along with the
  packed `Genome.paclet` archive. Staging outside the tree is not optional: a
  second `PacletInfo.wl` under the repo registers as a duplicate paclet of the
  same Name/Version and the scrape then resolves an ambiguous `PacletObject`.
- **`scripts/publish.wls`** is the pipeline end to end: ensure the documentation
  notebooks exist, `DocumentationBuild` them, stage a clean paclet copy
  (PacletInfo + Kernel + Documentation + Tests + Assets) outside the repo, upload the raw
  `Genome.paclet` archive, then scrape the resource from `ResourceDefinition.nb`
  and `CloudDeploy` it publicly. It is idempotent - re-running redeploys to the
  same location.
- **`scripts/sync_paclet_symbols.wls`** rewrites the `"Symbols"` list on the
  Kernel extension of `PacletInfo.wl` from `Names["WolframInstitute`Genome`*"]`,
  fully qualified. That declaration is what makes a documented symbol render as
  a click-to-copy `PacletSymbol["WolframInstitute/Genome", "Name"]` box:
  `PacletResource`'s `pacletDeclaredSymbols` reads it off the paclet's own
  PacletInfo, and with the key absent the lookup gives `Missing["NotFound"]` and
  every symbol ships as plain text. `deploy_common.wls` also pins that function
  in the deploying kernel, but a pin only covers the machine doing the deploy -
  an installed copy, or anyone calling `PacletSymbol` directly, reads the
  declaration. `publish.wls` runs the sync first, so adding a public symbol can
  never ship an unwrapped page; `-check` exits non-zero instead of rewriting.
- **`scripts/deploy_common.wls`** holds the shared cloud-deploy machinery
  `publish.wls` drives: the no-purge in-place documentation merge, the deploy
  correctness patches, hero-image injection, the hierarchical guide sidebar, and
  the headless scrape-and-deploy.
- **`scripts/build_notebooks.wls`** converts each `docs/en/**/*.md` into a
  DocumentationTools *authoring* notebook under
  `Genome/Documentation/English`, flat by basename. It needs a Wolfram Cloud
  connection (`MarkdownToNotebook` is a deployed resource function; `GENOME_MTN`
  points it at a local checkout instead) and is the first step `publish.wls`
  runs.
- **`scripts/build_docs.wls`** builds the documentation SITE - one `index.html`
  shell with a collapsible guide rail on the left, the symbols on the right, and
  a single iframe in the middle that every in-content link is routed through. It
  exists because the stock shingle deploys each page as a delayed embed that
  fetches `/statichtml/<page>.nb?maxwaitmillis=1000`, and one second is not
  enough to render these notebooks - every page but a pre-warmed one comes back
  empty, and in-content links escape into the old chrome. Two targets:
  `local` renders every authoring notebook to static HTML offline (headless
  Front End, no cloud) and assembles `build/local-docs`; `site` deploys the
  shell to the cloud, framing the published resource's live embed pages.
  `DRYRUN=1` prints the nav tree and stops. The shell's markup, stylesheet and
  loader are the tracked templates under `docs/web/`; the script fills their
  slots. The local render is cached in `.html-cache`, keyed by a hash of each
  source notebook, so a no-change rebuild is seconds rather than the couple of
  minutes a cold one takes. Serve the result over HTTP
  (`python3 -m http.server --directory build/local-docs 8000`), not `file://` -
  the rendered pages reach for their shared assets from above the site root and
  rely on the server clamping that to the root.
- **`scripts/docbuild.wls`** runs `DocumentationBuild` over the authoring
  notebooks and asserts the built structure. `build_notebooks.wls` writes *authoring*
  notebooks; only `DocumentationBuild` folds the authoring
  `ExamplesInitializationSection` into a real Examples section, so a page
  deployed straight from an authoring notebook renders with a doubled section
  rule and its examples collapsed under "Examples Initialization". It needs a
  Front End, so it is not part of the plain test acceptance.
- **`scripts/build_hero.wls`** renders `Genome/Assets/hero.png`, the shingle
  image on the resource page. Unlike everything else here the hero is a
  **tracked** file: the paclet ships it through PacletInfo's `Asset` extension.

Publishing needs a Wolfram Cloud connection (`WOLFRAM_CLOUD_USER` /
`WOLFRAM_CLOUD_PASSWORD` for non-interactive use) and a usable Front End.
The paclet publishes under the `wolframinstitute` account: always pass
`GENOME_CLOUD_ACCOUNT=wolframinstitute`. A `wolframscript` kernel starts
connected as whichever account last signed in on the machine, and without the
pin a publish goes wherever that is. With the pin, a mismatched kernel
reconnects with the environment credentials when they are set, and otherwise
refuses without touching the connection. It never disconnects on the hope that
`CloudConnect[]` can prompt: `CloudDisconnect[]` clears the machine's saved
login, and a non-interactive kernel cannot sign back in.

**A publish is two deploys, not one.** `publish.wls` updates the paclet and
its resource page; the documentation SITE with the guide rail is deployed
separately by `scripts/build_docs.wls site`, and its rail is built at its own
deploy time, so until that has run too the site keeps listing the old symbols
while the resource page already shows the new ones. Run both, every time.

**Running it from an agent.** A full publish takes 30-60 minutes, most of it
the parallel `DocumentationBuild`, and two things went wrong once and cost an
evening: wrapped as `timeout 3000 wolframscript ... | tail`, the pipeline showed
nothing until the end (the `tail` buffers), the `timeout` did not actually stop
the kernel, and the wrapper then hung on the pipe with the worker kernels
orphaned and still running 1h40m later. Run it detached with the output going
straight to a log file (`nohup wolframscript -f scripts/publish.wls > publish.log 2>&1 &`), watch the log for the `deploy:` lines, and never give it
a `timeout`. And when other sessions on the machine hold Wolfram kernels, the
default worker count competes with them for licence seats and the build can
stall indefinitely rather than fail: set `GENOME_DOCBUILD_KERNELS=2` in that
case. A second publish must never be started while one is running; they stage
into the same place. `publish.wls` refuses to upload a staged paclet above
`maxArchiveBytes`, a guard against bundling data by mistake; it sat at 25 MB
and the built documentation alone crossed it once the genealogy pages with
their rendered pedigrees were added (25.03 MB across 63 files), which
aborted two publishes after a full successful build. It is 60 MB now. If it
trips again, look at the notebook sizes under `Documentation/English` before
raising it: a 400-700 KB reference page is normal, a multi-megabyte one has
a rendered output that should be reduced.
Do not try to save the rebuild after such an abort by pointing
`GENOME_PUBLISH_BUILT_DOCS` at the `docbuild.wls` output directory: that
was tried and the staging step reported the main guide missing although
`English/Guides/Genome.nb` was there, then went silent. A full run costs ten
minutes with two workers; take it.

The scripts read these environment overrides, all prefixed `GENOME_`:

| Variable | Effect |
| --- | --- |
| `GENOME_CLOUD_ACCOUNT` | the only cloud account a publish or site deploy may use (`wolframinstitute`); any other refuses |
| `GENOME_PUBLISH_DIR` | where the clean paclet copy is staged (default: under `$TemporaryDirectory`; must be outside the repository) |
| `GENOME_PUBLISH_BUILT_DOCS` | a directory containing `English/` to bundle as-is, skipping both doc builds |
| `GENOME_PUBLISH_REUSE_NOTEBOOKS` | `1` DocumentationBuilds the authoring notebooks already under `Genome/Documentation/English` instead of regenerating them from markdown - for a machine without the subject callset; refresh any page that needs no data first with `build_notebooks.wls <Name>` |
| `GENOME_PUBLISH_SKIP_DOCBUILD` | `1` stages the authoring notebooks without `DocumentationBuild` - fast, but the pages render pre-built |
| `GENOME_MTN` | path to a local `MarkdownToNotebook.wl` checkout, instead of the deployed cloud resource function |
| `GENOME_SCRAPE_STRICT` | `1` forces a strict scrape instead of the tolerant default |
| `GENOME_DOCBUILD_DIR` | where `docbuild.wls` stages its build copy (default: under `$TemporaryDirectory`; must be outside the repository) |
| `GENOME_DOCBUILD_KERNELS` | worker-kernel count for the page build AND for the deploy's parallel steps (the notebook transform, the page upload); each transform worker starts its own front end too (default: `Max[2, Min[8, $ProcessorCount]]`; set 2 when other sessions hold kernels) |
| `GENOME_DOCBUILD_TIMEOUT` | per-page build limit in seconds (default: 300) |
| `GENOME_VCF` | path to the single-sample VCF the test suite exercises, overriding the `data/` default |
| `GENOME_LOCAL_ONLY` | `build_docs.wls local` renders only this page, e.g. `Guides/Genome` or `ReferencePages/Symbols/ImportVCF` |
| `GENOME_HTML_CACHE` | `0` disables the `.html-cache` reuse and forces a full local render |
| `GENOME_NETWORK_TESTS` | `1` additionally runs the opt-in live genealogy-provider tests |
| `GENOME_BROWSER_RUNNER` | path to `genealogy-browser.mjs`, overriding the paclet asset |
| `GENOME_BROWSER_STATE` | directory for the saved per-provider browser sessions (default: under `$UserBaseDirectory`) |
| `GENOME_PLAYWRIGHT` | path to a `playwright-core` install, when it is not on the default module path |
| `FAMILYSEARCH_TOKEN` / `GENI_TOKEN` | OAuth tokens that activate the credential-class `GenealogySearch` providers (`SystemCredential` is read as a fallback) |

`build_docs.wls` also reads `DRYRUN=1` (print the nav tree and stop, before any
render or deploy) - unprefixed, matching the PureMath and Puzzles scripts it is
ported from.

**Privacy note for publishing.** Everything that goes to the cloud is code,
documentation and public reference data. No file under `data/` is ever staged,
packed or deployed - the staging copy is an explicit allow-list (PacletInfo,
Kernel, Documentation, Tests, Assets), not a copy of the working tree. Keep it
that way, and never add a documentation example whose output embeds a real
genotype, haplogroup, diplotype, carrier call, ancestry fraction or ClinVar
hit - see [Privacy](#privacy) for how that leak actually happens.

## Workflow

1. **Read [README.md](README.md) and this file first.** The last section
   lists what is deliberately not built yet.
2. **Tests describe behavior.** Add a real-file `VerificationTest` to
   `Genome/Tests/Genome.wlt` when implementing a new query or
   analysis function. Re-run `Tests/run.wls` and confirm zero failures
   before claiming work done.
3. **Docs alongside code.** A new public symbol gets a reference page under
   `docs/en/ReferencePages/Symbols/` and an entry in the guide's
   `## Functions` list; `scripts/sync_paclet_symbols.wls` adds it to the
   declared symbols in `PacletInfo.wl`, and `publish.wls` runs that sync
   first.
4. **Commit small.** Commit messages are short imperative summaries.
   `data/` stays git-ignored. This repository is public: the Privacy rules
   above apply to every commit. No family name, place or date goes into code,
   tests or comments, in any script. `Genome/Tests/Genome.wlt` stores
   Cyrillic as `\:041c...` escapes, so a plain grep for a Cyrillic name finds
   nothing; decode them before sweeping.
5. **Match the existing shape.** Functions that produce variant data
   return the canonical row Association above; functions that consume it
   accept either a `_Dataset` or a path. New options on `ImportVCF`
   propagate through `RegionVariants` via `OptionsPattern[ImportVCF]`.

## Code map (current)

WL paclet (`Genome/`, context `` WolframInstitute`Genome` ``):

- `Kernel/Genome.wl` - the umbrella. `BeginPackage`, all public
  `::usage` strings, then `Begin["`Private`"]` and a `Scan[Get, ...]`
  that loads the implementation modules below (in dependency order,
  shared helpers first), then `End[]; EndPackage[]`. The modules are raw
  definition files with no `BeginPackage` of their own - they inherit the
  `` WolframInstitute`Genome`Private` `` context from the umbrella's Get.
  Adding a module means adding it to that `Scan[Get, ...]` list; nothing
  else discovers it.
- `Kernel/Common.wl` - shell helpers (`shellEscape`, `streamCommand`,
  `onPathQ`), the `##` meta-line parsers, and reference-build inference.
- `Kernel/VCF.wl` - `ImportVCFHeader`, row parsing, the awk-pipeline
  filter compiler (pushes Chromosome / Region / PASSOnly /
  ExcludeReferenceOnly / MinImputationR2 into the stream and `exit`s at
  `MaxVariants`), filter resolution, variant-`Tabular` assembly.
- `Kernel/Backends.wl` - the AwkStream / Tabix / Parquet read backends,
  backend auto-selection, and the dispatch layer.
- `Kernel/GenomeObject.wl` - `GenomeQ`, `ImportVCF` (the workhorse
  constructor), `GenomeToParquet`, and the `Genome` head's SubValues /
  UpValues / `MakeBoxes` display. It is named `GenomeObject.wl`, not
  `Genome.wl`, because the umbrella above already owns that filename -
  the paclet's context is `` WolframInstitute`Genome` ``, so its kernel
  root file must be `Kernel/Genome.wl`.
- `Kernel/HumanGenome.wl` - the `HumanGenome` composition wrapper,
  `HumanGenomeQ`, autopromotion, the forwarding SubValue + filter-
  accumulation rewrap, UpValues, and display.
- `Kernel/Query.wl` - `GenotypeLookup`, `RegionVariants`,
  `VariantSummary` (returns a two-column `{Metric, Value}` Tabular), and
  the remaining `ImportGenotypeArray` / `ToBioSequence` stubs.
- `Kernel/Interpretation/*.wl` - one file per interpretation domain:
  `Ancestry.wl` (ChromosomalSex, HaplogroupCall mtDNA/Y, AncestryEstimate
  admixture), `ClinVar.wl`, `AlphaMissense.wl`, `Traits.wl`, `Carrier.wl`,
  `PRS.wl`, `GWAS.wl`, `Pharmacogenomics.wl`, and `Report.wl` (the
  aggregate report plus its bilingual localization table and glossary). Each
  follows the same shape: lazy reference prep / download, an
  index-restricted subject read, an immutable rewrap into a new
  `HumanGenome`, and an in-memory slot plus a per-subject sidecar cache
  keyed by `hg["References"]`.
- `Kernel/Genealogy/*.wl` - the pedigree layer, independent of the VCF
  side of the paclet. `GEDCOM.wl` is the GEDCOM 5.5.1 reader (lexer,
  `CONT`/`CONC` folding, the level-nesting tree builder, granularity-
  preserving date parsing, and `ImportGEDCOM`). `FamilyTree.wl` is the
  `FamilyTree` head: kinship walks, the generation index, kinship-term
  naming, the consistency pass behind `ft["Issues"]`, the drawing behind
  `FamilyTreePlot`, and the summary box. The plot has three placements,
  all in printer points because the cards are drawn from primitives at a
  fixed point size: `"Pedigree"` (the default; the chart a genealogy
  service draws, root at the bottom, a binary tree of ancestor slots with
  the father's line left and the mother's right, siblings beside their
  ancestor on the outward side, a lone parent centred over its child,
  elbow connectors from each union through a bus line), `"Layered"`
  (everybody in the file, the layered embedding stretched until neighbours
  clear), and a caller's own `GraphLayout` (the embedding scaled uniformly
  until no two vertices sit closer than a card). The last one shipped
  broken once: the cards were in points and the embedding in units, so
  every card was a hundred times the graph. Any new placement must hand
  back points. `ImageSize -> Automatic` is the plot range 1:1, capped at
  6000, and the layered stretch treats a near-tie in the embedding like a
  tie rather than stretching the chart to separate it.
  `GEDCOM.wl` also holds `ExportGEDCOM`, the inverse of the reader (verbatim
  date text preserved, `_MIDN` / `_MARNM` written, `1 DEAT Y` for a death
  without a date), which reproduces a read tree record for record.
  `Table.wl` is `ImportFamilyTable` / `ExportFamilyTable`, the flat
  one-row-per-person table Genotek exports beside its GEDCOM. Two
  conventions are INVERTED between the formats and the code inverts them
  both ways: the table's surname column is the current (married) surname
  with the maiden name beside it, where GEDCOM's SURN is the birth surname;
  and a table has no family records, so unions are rebuilt from the
  father, mother, spouse and children cells of every row together, which is
  how a person nobody names still gets her family from her own row. Links
  in a table are NAMES, resolved against the rows with yo/ye folded, and
  in a strict order: a person's own full name first, the two-part
  surname-plus-given-name key only as a fallback. The order is not
  cosmetic: a real tree can hold a grandfather and a grandson who share a
  surname and a given name, with no patronymic on record for the grandson,
  so "Ivanov Ivan" must find the grandson exactly before it is read as
  a shortening of the grandfather. Trying the short key first re-linked
  the family to the wrong Ivan - and full-name-first was not enough
  either, because the grandson's own row DOES carry his patronymic while
  his parents' children cell omits it, so the reference has no full form
  to match. The tie is settled by mutuality: the candidate whose own row
  names the referencing row back (as parent, child or spouse). There is a
  test pinning exactly this collision. The CSV importer does not honour a
  field-separator option for this format, so `Table.wl` splits records
  itself (RFC 4180: quoted fields may hold the delimiter, doubled quotes and
  newlines). Round trips are verified on a real pair of exported files:
  GED to CSV to tree, CSV to GED to tree and GED to GED all agree on every
  person and family, and the exported CSV matches the service's original byte
  for byte apart from a field the GEDCOM never carried.
  `Search.wl` is `GenealogySearch`, `GenealogyLogin` and the provider
  registry, split into the "Open" (WikiTree, OpenList, PermGenerations,
  Wikidata, OpenArchives), "Credential" (FamilySearch, Geni) and
  "Browser" (PamyatNaroda, YandexArchive, FindAGrave) classes.
  `PermGenerations` is the odd one: a regional NAME INDEX rather than a
  scan repository, so a hit is already a parsed record whose card names
  both parents and cites its archival file, and it is read with the HTML
  importer (`ImportString[body, {"HTML", "Data"}]`) rather than by
  pattern matching on markup. Its result rows are ragged - a record with
  no stated place has three cells, not four - so the table is matched
  loosely and padded.
  `Search.wl` also owns the o/a spelling expansion. Unstressed o and a
  are homophones in Russian, so one family's surname drifts between
  spellings across documents, and an archive name index matches the
  string it is given: a father and son can share a surname spelled with an o in one
  record and an a in the other, and searching one spelling can return a
  handful of records where the other returns many times more, including
  the one that matters. The substitution is confined to the surname root, since the
  suffix is orthographically stable and varying it only manufactures
  nonsense and multiplies requests. A browser-class
  archive publishes no API and serves a JavaScript shell or an anti-bot
  interstitial to a plain fetch, so its query runs in a real browser
  through `Assets/genealogy-browser.mjs` and the rows are read off the
  rendered page. Every failure on that path degrades to the deep search
  link AND says so: `GenealogySearch::browser` names the provider and the
  reason. Do not wrap the provider dispatch in `Quiet` - that swallowed
  the fallback message once already and turned a refusal into an
  apparently empty result, which is the one outcome this design exists to
  prevent.
- `Kernel/Genealogy/Kinship.wl` - naming a relationship, in two stages: the
  tree is walked into a DESCRIPTOR with no words in it, then a descriptor is
  rendered into a phrase in one of eight languages. Adding a language touches
  only the second stage. The systems are genuinely different and neither is a
  translation of the other: English counts cousin degree and removal
  ("first cousin once removed"), while Russian and the Romance and Germanic
  languages name the GENERATION a person sits in and mark the collateral
  distance on that word, which is why a grandparent's brother is a
  great-uncle in one system and a cousin-grandfather in the other, and why
  Russian tells apart two relations English calls by one name (a cousin's
  child versus a parent's cousin). Outside Russian, a grandparent's sibling
  compounds a NEW word (tio abuelo, prozio, Grossonkel) rather than marking
  the grandparent word, and the cousin ordinal runs one behind Russian's -
  primo hermano is a first cousin and primo segundo already a second. Both
  rules were wrong in the first draft and there are tests pinning them.
  German compounds through `deCompound`, which capitalizes once
  (Urgrossvater, not UrGrossvater).
- `Kernel/Genealogy/Names.wl` - transliteration. The built-in `Transliterate`
  is unusable for Russian names: it maps by stripping diacritics, so
  Shcherbakov Yuriy comes back as "Serbakov Urij" with the sh, zh and yu
  distinctions gone. `"BGN"` (BGN/PCGN, the readable standard) and
  `"Passport"` (ICAO Doc 9303, the spelling on a modern Russian passport)
  are tabulated here; `"Scientific"` defers to the built-in. Transliteration
  is a DISPLAY option only - it never touches a record.
- `Kernel/Formats.wl` - the registered Import/Export formats, loaded last:
  `GEDCOM` (import elements Data / People / Families / Header / Tabular /
  Graph; export options Submitter, LineEnding), `FamilyTable` (Data / People
  / Families / Tabular / Graph; export options Headers, Delimiter,
  ByteOrderMark, LineEnding) and `GenomeVCF` (Data, the lazy handle; Header,
  Samples, Build, Variants, VariantSummary; the ImportVCF options). They are
  a second door to ImportGEDCOM / ExportGEDCOM / ImportFamilyTable /
  ExportFamilyTable / ImportVCF, which stay public. `GenomeVCF` is not
  `VCF` because the kernel already owns a format called VCF and a paclet must
  not redefine a system format. `RegisterImport` adds a `Summary` element of
  its own to every format, so the element list a page documents includes it.
  Binding a file extension (.ged) to a registered format was tried through
  the "Extensions" option and the FileFormatDump and ConvertersDump internals
  and none took in 15.0 (the extension map is loaded from an external file),
  so every use names the format explicitly; the pages say so.
- `Assets/genealogy-browser.mjs` - the Playwright runner, a *tracked*
  file shipped through PacletInfo's `Asset` extension next to `hero.png`.
  One JSON job in, one JSON result out on stdout, diagnostics on stderr,
  and a `kind` field ("no-playwright", "no-browser", "challenge",
  "timeout", ...) so the kernel can explain a failure instead of
  guessing. It needs Node plus `playwright-core` plus a Chrome build,
  none of which the paclet can ship; the kernel checks for them and stays
  in link mode when they are absent. The per-provider extractors are
  written against the markup each archive actually serves, so a redesign
  surfaces as an empty result, never as a silently wrong one.
- `Tests/Genome.wlt`: `VerificationTest` specs (hermetic fixtures
  plus real-file tests guarded by `FileExistsQ[realVCF]` and by the
  per-subject sidecars). The genealogy tests are hermetic throughout and
  never touch the network; live provider calls are opt-in behind
  `GENOME_NETWORK_TESTS=1`. **Every genealogy search in a test or a doc
  example must pass `"Browser" -> False`.** Without it the browser-class
  providers launch Chrome, which turns a doc build into a browsing
  session and makes the test suite depend on three archives being up.
- `Tests/run.wls`: runner. Calls `TestReport`, prints a pass/fail
  summary, exits non-zero on any failure.
- `Assets/hero.png`: the resource-page shingle image, shipped through
  `PacletInfo.wl`'s `Asset` extension and rendered by
  `scripts/build_hero.wls`. Unlike the built notebooks it is a *tracked*
  file, not a build artifact.
- `Documentation/English/`: GENERATED notebooks - git-ignored, never
  hand-edited. Re-author the markdown under `docs/en/` and rebuild.
- `PacletInfo.wl`: paclet metadata. `"Name"` is `WolframInstitute/Genome`,
  `"PublisherID"` is `WolframInstitute`, and the Kernel extension's context
  `` WolframInstitute`Genome` `` resolves to `Kernel/Genome.wl`, which loads
  the rest. The Documentation extension's `"MainPage"` is `Guides/Genome`.

Documentation sources (`docs/`):

- `en/Guides/Genome.md` - the guide, the paclet's MainPage.
- `en/ReferencePages/Symbols/*.md` - one page per public symbol.
- `en/ReferencePages/Formats/*.md` - one page per registered format.
- `en/Tutorials/*.md` - the tech notes.
- `web/` - the documentation site's shell templates (html, css, js).
- `ResourceDefinition.md` - the published resource's front page.

Not tracked: `data/`, supplied locally - the subject callset, its reference
downloads under `data/references/` and the per-subject sidecar caches.

## What is deliberately not here yet

Do not pre-build for these.

- `ImportGenotypeArray` (23andMe-style raw genotype TSV reader).
- `ToBioSequence` (genomic interval -> Wolfram `BioSequence` via
  `GenomeData`).
- Streaming path-based `GenotypeLookup` (awk-filter for an rsID list
  against the 9.4 GB file in one pass).
- Re-imputation experiment (TYPED rows -> TOPMed Imputation Server,
  then diff against Genotek's IMPUTED calls).
- A SpliceAI annotation pipeline.

## When in doubt

- Match the existing row Association shape and `ImportVCF` option
  vocabulary; do not invent parallel field names.
- Prefer streaming with awk filter-pushdown over loading the full VCF.
- Reference build is **GRCh37/hg19** - many modern tools default to
  GRCh38. Use `ResourceFunction["EnsemblGenomeAssemblyConversion"]`
  for liftover when an annotation source is GRCh38-only.
- Ask before introducing a new top-level directory or new public paclet
  function.
- Treat personal genome data as a privacy boundary. Anything that sends
  data off-machine (web services, cloud notebooks, an Imputation Server)
  needs explicit user approval first.

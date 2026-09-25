# Genome

`WolframInstitute/Genome` is a Wolfram Language paclet for working with a personal
genome and the pedigree it came down: a lazy handle to a VCF on disk, region and rsID
queries that return `Tabular`, an interpretation layer over public reference data, and
a genealogy layer that reads, writes, plots and searches family trees.

- Published paclet: [WolframInstitute/Genome](https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/WolframInstitute/Genome)
- Documentation: [guide, reference pages and tutorials](https://www.wolframcloud.com/obj/wolframinstitute/Genome)

## Install

```wolfram
PacletInstall[
  ResourceObject["https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/WolframInstitute/Genome"],
  ForceVersionInstall -> True]

Needs["WolframInstitute`Genome`"]
```

Requires Wolfram Language 14.2 or later. Once installed, the paclet is available in every
later session.

## What it does

A VCF is imported as a `Genome`, a lazy handle: the header is read eagerly and variant
rows are streamed with filters pushed down into the stream, so a multi-gigabyte callset is
never loaded whole. Tabix and Parquet backends are picked up automatically when their
sidecar files exist.

| Function | Purpose |
| --- | --- |
| `ImportVCF`, `ImportVCFHeader` | Open a VCF as a lazy `Genome` handle, or read just its header. |
| `Genome`, `GenomeQ` | The lazy handle and its predicate. |
| `HumanGenome`, `HumanGenomeQ` | A human-build `Genome` carrying computed interpretations. |
| `GenomeToParquet` | Write a Parquet sidecar set for fast region queries. |
| `RegionVariants`, `GenotypeLookup`, `VariantSummary` | Interval queries, rsID lookups and summary statistics. |
| `ImportGenotypeArray`, `ToBioSequence` | Genotyping-array TSVs and `BioSequence` views (stubs for now). |

The interpretation functions each take a `HumanGenome` and return a new one with a slot
filled. Each downloads its public database once and caches the result beside the data.

| Function | Source |
| --- | --- |
| `ChromosomalSex` | Sex-chromosome heterozygosity and coverage. |
| `AncestryEstimate` | 1000 Genomes phase 3 super-populations. |
| `HaplogroupCall` | PhyloTree build 17 (mtDNA) and ISOGG (Y). |
| `ClinVarHits`, `CarrierStatus` | ClinVar, with PanelApp modes of inheritance. |
| `AlphaMissenseScores` | AlphaMissense missense pathogenicity. |
| `PharmacogenomicProfile` | CPIC star alleles, phenotypes and drug guidance. |
| `PolygenicRiskScore` | PGS Catalog scoring files. |
| `GWASAssociations`, `TraitAssociations` | NHGRI-EBI GWAS Catalog and SNPedia. |
| `GenomeReport` | Everything computed, as one report in English or Russian. |

The genealogy layer is independent of the VCF side.

| Function | Purpose |
| --- | --- |
| `ImportGEDCOM`, `ExportGEDCOM` | Read and write GEDCOM 5.5.1. |
| `ImportFamilyTable`, `ExportFamilyTable` | The flat one-row-per-person table genealogy services export. |
| `FamilyTree`, `FamilyTreeQ` | A parsed pedigree: kinship terms in eight languages, transliteration, consistency checks. |
| `FamilyTreePlot` | Pedigree charts in the style of a genealogy service. |
| `GenealogySearch`, `GenealogyLogin` | Search archive providers by API or, where none exists, through a real browser. |

The formats `GEDCOM`, `FamilyTable` and `GenomeVCF` are also registered with `Import` and
`Export`.

## Layout

```
Genome/          the paclet: PacletInfo.wl, Kernel/, Tests/, Assets/
docs/            documentation sources
  en/            guide, reference pages and tutorials, as markdown
  web/           templates for the documentation site
  ResourceDefinition.md   the published resource page
scripts/         build, lint and publish
AGENTS.md        conventions for contributors, human or LLM
GUIDE.md         Wolfram Language style rules for every .wl, .wlt and .wls file
package.json     playwright-core, for the browser-class genealogy providers
```

`Genome/Documentation/` holds notebooks generated from `docs/en/` and is not tracked.

## Develop

```wolfram
PacletDirectoryLoad["/path/to/this/checkout/Genome"]
Needs["WolframInstitute`Genome`"]
```

From the repository root:

```sh
# test suite: prints a pass/fail summary, exits non-zero on any failure
wolframscript -f Genome/Tests/run.wls

# load test: must print LOADED with no messages
wolframscript -code 'PacletDirectoryLoad["Genome"]; Needs["WolframInstitute`Genome`"]; "LOADED"'

# house-style lint over the markdown: must report "files clean"
wolframscript -f scripts/lint_docs.wls

# only for the browser-class genealogy providers: Node plus playwright-core,
# driving the installed Chrome
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install
```

The tests that need a real callset look for `data/*_genome.vcf.gz` at the repository root,
or at `GENOME_VCF`, and skip with a note when there is none.

## Documentation

The markdown under `docs/en/` is the source; the notebooks are built from it.

```sh
# markdown -> authoring notebooks under Genome/Documentation/English
wolframscript -f scripts/build_notebooks.wls

# notebooks -> a browsable static site under build/local-docs
wolframscript -f scripts/build_docs.wls local
python3 -m http.server --directory build/local-docs 8000
```

The examples evaluate at build time against a subject callset at
`data/subject_genome.vcf.gz`, with its downloaded reference databases under
`data/references/`. That data is personal and is never part of this repository: supply
it locally, as a directory or a symlink named `data`, before building. The conversion
uses the `MarkdownToNotebook` resource function; set `GENOME_MTN` to a local
`MarkdownToNotebook.wl` to use a checkout instead.

## Publish

A publish is two deploys: the paclet with its resource page, then the documentation site
that frames it.

```sh
export WOLFRAM_CLOUD_USER=... WOLFRAM_CLOUD_PASSWORD=...
GENOME_CLOUD_ACCOUNT=wolframinstitute GENOME_DOCBUILD_KERNELS=2 \
  nohup wolframscript -f scripts/publish.wls > publish.log 2>&1 &
GENOME_CLOUD_ACCOUNT=wolframinstitute wolframscript -f scripts/build_docs.wls site
```

`GENOME_CLOUD_ACCOUNT` refuses to deploy under any other account. A full publish takes
from ten minutes to an hour; run it detached and watch the log. [AGENTS.md](AGENTS.md)
covers the pipeline and every `GENOME_*` setting.

## License

MIT. See [LICENSE](LICENSE).

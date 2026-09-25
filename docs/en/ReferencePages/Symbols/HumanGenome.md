---
Template: Symbol
Name: HumanGenome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/HumanGenome
Keywords: [human genome, interpretation, ancestry, pharmacogenomics, ClinVar, AlphaMissense, SNPedia, polygenic risk, wrapper, composition, GRCh37, GRCh38]
SeeAlso: [HumanGenomeQ, Genome, ImportVCF, ClinVarHits, AlphaMissenseScores, TraitAssociations]
RelatedGuides: [Genome]
---

## Usage

<code>[HumanGenome]()[*g*]</code> wraps a single-sample human [Genome](paclet:WolframInstitute/Genome/ref/Genome) *g* in an interpretation layer, giving a value that behaves like *g* wherever a [Genome](paclet:WolframInstitute/Genome/ref/Genome) is accepted and that also carries the human-specific interpretation slots.

<code>[HumanGenome]()[*g*, *ann*]</code> pairs the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) *g* with an annotation [Association]() *ann*, the form through which the interpretation methods thread their cached results.

## Details & Options

- `HumanGenome` is a composition wrapper: `HumanGenome[Genome[<|…|>], <|…|>]`. The first argument is an ordinary [Genome](paclet:WolframInstitute/Genome/ref/Genome); the second is an [Association]() of interpretation state. Genome storage and human interpretation stay in separate, independently evolving values.
- [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) produces the wrapper automatically. With the default `"Human" -> Automatic`, a VCF with exactly one sample whose inferred build is `"GRCh37/hg19"` or `"GRCh38"` autopromotes to a `HumanGenome`.
- `ImportVCF[path, "Human" -> False]` opts out of promotion and gives a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome). `"Human" -> True` forces promotion on any human build, and on a build outside that set issues `HumanGenome::nonHumanBuild` and gives the plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) instead.
- Every operator and property that accepts a [Genome](paclet:WolframInstitute/Genome/ref/Genome) accepts a `HumanGenome` unchanged. [GenotypeLookup](paclet:WolframInstitute/Genome/ref/GenotypeLookup), [RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants), [VariantSummary](paclet:WolframInstitute/Genome/ref/VariantSummary), and [GenomeToParquet](paclet:WolframInstitute/Genome/ref/GenomeToParquet) are typed on `_?`[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ), which is [True]() for both heads.
- Any subscript that is not an interpretation slot forwards to the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome), so `hg["Build"]`, `hg["Samples"]`, `hg["Backend"]`, `hg["Variants"]`, `hg["Region", chrom, {start, end}]`, and `hg["VariantCount"]` all resolve against the inner genome.
- Filter accumulation preserves the wrapper. When a forwarded property gives a new [Genome](paclet:WolframInstitute/Genome/ref/Genome) (`hg["Chromosome", "chr17"]`, `hg["MinR2", 0.8]`, `hg["ExcludeReferenceOnly"]`, …), the result is rewrapped as a `HumanGenome` carrying the same annotation [Association](), so the accumulated filter and the cached interpretations travel together. A property whose value is a [Tabular]() or a number flows through unchanged.
- The annotation [Association]() has a `"References"` sub-Association (the pinned version of each external data source, used to key the caches), a `"Subject"` sub-Association (`"ID"`, taken from the single sample, and `"Sex"`), and one slot per interpretation method: `"Ancestry"`, `"Haplogroups"`, `"Pharmacogenomics"`, `"ClinVarHits"`, `"PRS"`, `"Traits"`, `"AlphaMissenseScores"`, `"Carrier"`, `"GWASAssociations"`, and `"ReportCache"`.
- Reading a slot gives its cached value, or [Missing]()`["NotComputed"]` before the corresponding method has run. `hg["Subject", key]` and `hg["References", key]` read one entry of those sub-Associations, and `hg["PRS", pgsid]` reads one polygenic score by its PGS Catalog identifier; a key the annotation does not carry gives [Missing]()`["NotPresent"]`.
- The interpretation methods are pure and cache-aware: each gives a new `HumanGenome` with one slot filled, mirroring the immutable filter-accumulation discipline of [Genome](paclet:WolframInstitute/Genome/ref/Genome), and repeating one is an immediate cache hit. Results also persist to a per-subject sidecar under the git-ignored `data/<subject>/interpretations/`, keyed by the reference version, so a fresh import hydrates them without recomputing. See [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits), [AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores), and [TraitAssociations](paclet:WolframInstitute/Genome/ref/TraitAssociations).
- An interpretation method that consults an external reference database prepares it on first use, and that first call reaches the network. The slot readers, [Options](), the forwarded properties and the predicates are answered offline.
- `HumanGenome` carries UpValues so [Length](), [Normal](), [Dimensions](), and [Part]() delegate to the inner [Genome](paclet:WolframInstitute/Genome/ref/Genome). [Part]() therefore reports `Genome::notIndexable` and gives `$Failed`, exactly as it does for a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome).
- A `HumanGenome` displays as a summary box with a purple icon accent, distinct from the teal accent of a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome). The collapsed row carries the subject, the build, and how many interpretation slots have been computed; the opened box adds the file, the backend, the size, the accumulated filters, and the names of the computed annotations. The box is interpretable, so it round-trips to the live value and never triggers a computation.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a `HumanGenome`, which displays as a purple-accented summary box naming the subject, the build and how many interpretation slots are computed:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The build of the wrapped genome reads straight through the wrapper:

```wl
subject["Build"]
```

<!-- => "GRCh37/hg19" -->

So does the sample list, which for a promoted genome has exactly one entry:

```wl
subject["Samples"]
```

<!-- => {"SUBJECT"} -->

The backend that answers the queries is chosen by the inner genome, and the wrapper only forwards the question; the tabix index beside the file selects the Tabix backend:

```wl
subject["Backend"]
```

<!-- => "Tabix" -->

The `"Subject"` sub-Association carries the identifier taken from the single sample column and the karyotype call, hydrated from a cached [ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex) result:

```wl
subject["Subject"]
```

<!-- => <|"ID" -> "SUBJECT", "Sex" -> "XY"|> -->

The `"References"` sub-Association names every external data source whose pinned version keys a cache. The build is pinned from the start, and each release reads [Missing]()`["NotComputed"]` until its interpretation has run:

```wl
subject["References"]
```

<!-- => <|"Build" -> "GRCh37/hg19", "ThousandGenomesPanel" -> Missing["NotComputed"], "ClinVarRelease" -> Missing["NotComputed"], "PGSCatalogVersion" -> Missing["NotComputed"], "CPICVersion" -> Missing["NotComputed"], "PharmGKBVersion" -> Missing["NotComputed"], "SNPediaCommit" -> Missing["NotComputed"], "AlphaMissenseRelease" -> Missing["NotComputed"], "GWASCatalogVersion" -> Missing["NotComputed"]|> -->

An interpretation method gives a new `HumanGenome` with one slot filled. [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) fills `"Ancestry"` and pins `"ThousandGenomesPanel"`; served from the per-subject sidecar, the call is immediate, and the summary box of the genome it gives counts one more computed annotation:

```wl
AncestryEstimate[subject]
```

---

A small synthetic single-sample VCF, written to a temporary file:

```wl
demoFile = Export[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "##fileformat=VCFv4.2
##source=WolframInstituteGenomeDemo
##contig=<ID=chr1,length=249250621>
##contig=<ID=chr17,length=81195210>
##INFO=<ID=AF,Number=1,Type=Float,Description=\"Alternate allele frequency\">
##INFO=<ID=R2,Number=1,Type=Float,Description=\"Imputation r-squared\">
##INFO=<ID=IMPUTED,Number=0,Type=Flag,Description=\"Imputed genotype\">
##INFO=<ID=TYPED,Number=0,Type=Flag,Description=\"Directly assayed genotype\">
##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	NA12878
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	GA	G	60	PASS	AF=0.5;R2=0.71;IMPUTED	GT	0/1
chr1	400000	rs400	G	C	60	PASS	TYPED	GT	0/1
chr17	1000000	rs1000	C	G	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	A	60	PASS	TYPED	GT	0/0
chr17	1200000	rs1200	A	T	60	PASS	AF=0.22;R2=0.99;IMPUTED	GT	1/1
chr17	1300000	rs1300	C	CAT	60	PASS	TYPED	GT	0/1",
    "Text"
]
```

<!-- => the full path the file was written to -->

Imported, it autopromotes to a `HumanGenome` in the same way:

```wl
hg = ImportVCF[demoFile]
```

`"Human" -> False` opts out of promotion and keeps the plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), which displays with the teal accent and carries no interpretation slots:

```wl
g = ImportVCF[demoFile, "Human" -> False]
```

## Scope

The promoted genome, imported from the demo file:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Reading an interpretation slot before its method has run gives [Missing]()`["NotComputed"]`:

```wl
hg["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

`hg["References", key]` reads one entry of the reference-version map, and a release no interpretation has pinned yet reads the same way:

```wl
hg["References", "ClinVarRelease"]
```

<!-- => Missing["NotComputed"] -->

`hg["Subject", key]` reads one entry of the subject record, such as the identifier taken from the single sample column:

```wl
hg["Subject", "ID"]
```

<!-- => "NA12878" -->

A key the annotation does not carry gives [Missing]()`["NotPresent"]`:

```wl
hg["Subject", "Karyotype"]
```

<!-- => Missing["NotPresent"] -->

Filter accumulation keeps the wrapper. A forwarded property whose value is a new [Genome](paclet:WolframInstitute/Genome/ref/Genome) is rewrapped with the same annotation, so a filtered genome is still a `HumanGenome` and displays as one:

```wl
hg["Chromosome", "chr17"]
```

The filter itself lands on the inner genome, beside the ones the import options seeded:

```wl
hg["Chromosome", "chr17"]["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr17"} -->

A query whose value is a [Tabular]() flows through the wrapper unchanged, with no rewrapping, so a region query gives the variant rows themselves:

```wl
hg["Region", "chr17", {1000000, 1300000}] // Dataset
```

---

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

An interpretation method gives a new `HumanGenome` with one slot filled. [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) prepares the ClinVar release on first use and gives a genome whose `"ClinVarHits"` slot holds a [Tabular]() of the ClinVar records the variants match, and whose summary box counts one more computed annotation; for this subject the join is served from its sidecar:

```wl
cv = ClinVarHits[subject]
```

What steers the method is readable without touching the network:

```wl
Options[ClinVarHits]
```

<!-- => {"Reference" -> Automatic, "MaxPopulationAF" -> Automatic} -->

The interpretation methods are pure, so the handle they were called on is unchanged and still reports the slot as not computed:

```wl
subject["ClinVarHits"]
```

<!-- => Missing["NotComputed"] -->

## Properties and Relations

A promoted genome, wrapping a plain one:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

[HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ) tests for the wrapper itself:

```wl
HumanGenomeQ[hg]
```

<!-- => True -->

[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) is [True]() for both heads, which is what lets every [Genome](paclet:WolframInstitute/Genome/ref/Genome) operator accept a `HumanGenome`:

```wl
GenomeQ[hg]
```

<!-- => True -->

The backend that answers the queries is chosen by the inner genome, and the wrapper only forwards the question:

```wl
hg["Backend"] === First[hg]["Backend"]
```

<!-- => True -->

A [Genome](paclet:WolframInstitute/Genome/ref/Genome) operator gives the same result on the wrapper and on the inner genome it forwards to:

```wl
GenotypeLookup[hg, "rs100"] === GenotypeLookup[First[hg], "rs100"]
```

<!-- => True -->

[Length]() delegates to the inner genome too, so it agrees with the forwarded `"VariantCount"` property:

```wl
Length[hg] === hg["VariantCount"]
```

<!-- => True -->

## Possible Issues

An interpretation method is typed on `_?`[HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ), so it needs the wrapper. Importing the demo file with `"Human" -> False` gives the plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) that fails that test:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

The plain genome does not satisfy the predicate:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

`ClinVarHits[g]` therefore stays unevaluated and comes back as it was written, with no message, no computation and no reference download:

```wl
ClinVarHits[g]
```

Promote the genome first, with [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) or by importing it without `"Human" -> False`.

Only `"GRCh37/hg19"` and `"GRCh38"` qualify. Re-stamping a payload with another build gives a value that is still a valid [Genome](paclet:WolframInstitute/Genome/ref/Genome):

```wl
t2t = Genome[<|First[g], "Build" -> "T2T-CHM13v2.0"|>]
```

The constructor is conditioned on the build, so wrapping that genome leaves `HumanGenome[t2t]` unevaluated, and the unevaluated expression is not a `HumanGenome`:

```wl
HumanGenomeQ[HumanGenome[t2t]]
```

<!-- => False -->

---

[Part]() delegates to the inner genome, which is deliberately not indexable, so indexing a `HumanGenome` directly issues this message and gives `$Failed`:

```wl
Genome::notIndexable
```

<!-- => "Genome[..] is not directly indexable; call g[\"Variants\"] and index the resulting Tabular." -->

Materialise the variants and index the [Tabular]() instead. A handle on the demo file:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The materialised variants are a [Tabular](), which indexes like any other table:

```wl
hg["Variants"] // Dataset
```

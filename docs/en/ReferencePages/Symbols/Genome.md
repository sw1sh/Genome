---
Template: Symbol
Name: Genome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/Genome
Keywords: [genome, VCF, variant, lazy handle, filter accumulation, backend, streaming, GRCh37]
SeeAlso: [GenomeQ, ImportVCF, ImportVCFHeader, GenotypeLookup, RegionVariants, VariantSummary]
RelatedGuides: [Genome]
---

## Usage

<code>[Genome]()[*assoc*]</code> is a lazy handle to a personal VCF dataset, wrapping a single [Association]() *assoc* that carries the file path, the parsed header, and an accumulating filter spec.

## Details & Options

- `Genome` is an inert head wrapping exactly one [Association]() payload. The payload keys are `"Path"` (the VCF file path), `"Header"` (the parsed header from [ImportVCFHeader](paclet:WolframInstitute/Genome/ref/ImportVCFHeader)), `"Samples"` (the sample id list, always a list), `"Build"` (the inferred reference build), `"Backend"` (the storage backend), `"Filters"` (the accumulated filter spec, a list of [Rule]()s), and `"VariantCountCache"`.
- The canonical constructor is [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF), which parses the header eagerly (sub-second) and gives a handle immediately. Variant rows are read from disk only when a query forces them.
- A single-sample VCF whose inferred build is human autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome); `ImportVCF[path, "Human" -> False]` keeps the plain `Genome`. Every property, query, and filter form below behaves identically on either head.
- Property access is cheap and reads directly from the payload:
    - `g["Path"]` gives the file path.
    - `g["Header"]` gives the full parsed header [Association](); `g["Header", key]` gives one field, or [Missing]()`["NotFound", key]` when it is absent.
    - `g["Samples"]` gives the sample id list.
    - `g["Build"]` gives the inferred reference build, for example `"GRCh37/hg19"`.
    - `g["Backend"]` gives the selected backend, one of `"AwkStream"`, `"Tabix"`, or `"Parquet"`.
    - `g["Filters"]` gives the accumulated filter spec.
    - `g["VariantCount"]` gives the number of rows a query would materialise, from the cache when it holds one and otherwise from a counting stream.
- Three subscripts materialise rows through the backend: `g["Variants", opts]` gives every matching row as a [Tabular](), `g["Region", chrom, {start, end}]` gives the rows in a genomic interval, and `g["Genotype", rsid]` gives the single row for one rsID, or [Missing]()`["NotFound", rsid]` when the filtered view holds no such rsID. `g["Summary"]` gives the summary statistics of the filtered view as a two-column [Tabular]() of `"Metric"` and `"Value"`.
- The materialised variant [Tabular]() has 17 columns: `"CHROM"`, `"POS"`, `"ID"`, `"REF"`, `"ALT"` (a list of strings, `{}` for reference-only rows), `"QUAL"`, `"FILTER"` (a list of filter ids), `"INFO"` (the full nested [Association]()), the surfaced hot INFO columns `"R2"`, `"MAF"`, `"AC"`, `"AN"`, the imputation-provenance flags `"IMPUTED"`, `"TYPED"`, `"TYPED_ONLY"`, and `"FORMAT"` and `"GT"`.
- Filter accumulation is immutable. Each of `g["FilterPASS"]`, `g["Chromosome", chrom]`, `g["MinR2", r]`, `g["ExcludeReferenceOnly"]`, and `g["MaxVariants", n]` appends a [Rule]() to `"Filters"` and gives a new `Genome`, leaving the original unchanged. The forms chain: `g["Chromosome", "chr17"]["MinR2", 0.8]["ExcludeReferenceOnly"]`.
- Accumulated filters are resolved at materialisation, not as they accumulate. Two `"MinR2"` filters intersect to the larger threshold; two `"MaxVariants"` filters intersect to the smaller cap; a `"Region"` overrides a `"Chromosome"`. A `"MinR2"` threshold above zero also drops a row whose INFO carries no `R2` field at all.
- The `"Backend"` slot is set once, at construction, by [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF). `"Tabix"` is auto-selected when a sibling `.tbi` index exists and `bcftools` is on the path, seeking straight to a region instead of scanning to it; otherwise the backend falls back to `"AwkStream"`, the `gzcat | awk` pushdown that needs no external state. `"Parquet"` is opt-in through `"Backend" -> "Parquet"`, and auto-selected only when a `<path>.parquet` sidecar exists and neither a `.tbi` index nor `bcftools` is available; it serves queries from the sidecar set written by [GenomeToParquet](paclet:WolframInstitute/Genome/ref/GenomeToParquet).
- The query subscripts are the same on every backend, but the Parquet backend gives the columnar schema (the exploded INFO columns and `GT_<sample>`) rather than the canonical 17-column row shape, and its `"ExcludeReferenceOnly"` is inherent, because the variants sidecar holds only rows with an alternate allele.
- `Genome` carries UpValues for generic operations: [Length]()`[g]` gives the variant count, [Normal]()`[g]` gives the materialised variant rows, and [Dimensions]()`[g]` gives `{count, 17}`.
- [Part]() is not supported: it issues `Genome::notIndexable` and gives <code>[$Failed]()</code>. Materialise the rows with `g["Variants"]` and index the resulting [Tabular]() instead.
- A subscript matching none of the property, query, or filter forms returns unevaluated.
- A `Genome` displays as a summary box, from a [MakeBoxes]() rule guarded by `` BoxForm`UseIcons ``: the closed box names the file, the build and the sample count, and the opener adds the backend, the file size, the accumulated filter spec and the cached variant count. The box is an [InterpretationBox]() holding the payload, so it round-trips back to the live handle; it never prints the variant rows.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. Importing it with `"Human" -> False` keeps the plain `Genome` head rather than promoting this single-sample human callset to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). The handle comes back before any variant row is read and displays as a summary box naming the file, the build and the sample count:

```wl
g = ImportVCF["data/subject_genome.vcf.gz", "Human" -> False]
```

Nothing has been read from disk beyond the header, so the inferred reference build is already available:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

The sample columns come from the same parsed header:

```wl
g["Samples"]
```

<!-- => {"SUBJECT"} -->

The backend is fixed once, at construction. A `.tbi` index sits beside the file and `bcftools` is on the path, so automatic resolution picks the indexed reader, which seeks straight to a region instead of scanning to it:

```wl
g["Backend"]
```

<!-- => "Tabix" -->

A bare import seeds the two filters that default to on, and every query the handle serves applies them:

```wl
g["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Materialising rows gives a [Tabular]() of the canonical 17 columns; a query-time cap of five stops the stream at the first five variant rows of the file, chromosome 1 sites near its start, and `"ALT"` is a list of alternate alleles:

```wl
g["Variants", "MaxVariants" -> 5] // Dataset
```

<!-- => a five-row Tabular of the canonical 17 columns -->

---

A small synthetic VCF written to a temporary file stands in for a callset whose every row can be accounted for: ten rows across two chromosomes, one sample column named for the public reference individual NA12878, and a GRCh37 contig header. Every genotype in it is made up. Writing the file gives back its name:

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

Importing it with `"Human" -> False` keeps the plain `Genome` head; `"Backend" -> "AwkStream"` names the streaming backend, and `"MaxVariants" -> 5` caps every query the handle serves, with the cap recorded in the opener of the summary box:

```wl
g = ImportVCF[demoFile, "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"]
```

The backend was named explicitly, and automatic resolution would have chosen the same streaming pushdown, since neither a `.tbi` index nor a Parquet sidecar sits beside the file:

```wl
g["Backend"]
```

<!-- => "AwkStream" -->

Under the import-time cap, materialising the variant rows gives a [Tabular]() of the same 17 columns, five rows deep:

```wl
g["Variants"] // Dataset
```

## Scope

### Properties

A capped, streaming handle on the demo file:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"
]
```

The path a handle was built from is part of its payload:

```wl
g["Path"]
```

<!-- => the full path the file was written to -->

The parsed header is an [Association]() whose keys name the meta-information the import read:

```wl
g["Header"]
```

A second argument reads one of those fields:

```wl
g["Header", "FileFormat"]
```

<!-- => "VCFv4.2" -->

The variant count of the filtered view is materialised through the backend and then cached on the handle:

```wl
g["VariantCount"]
```

<!-- => 5 -->

### Filter accumulation

A capped, streaming handle to accumulate filters on:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"
]
```

Each filter subscript gives a new `Genome` carrying one more filter, so the chain reads left to right and the opener of the new summary box already lists the accumulated spec:

```wl
g2 = g["Chromosome", "chr17"]["MinR2", 0.8]
```

Read out as a list, the spec holds the two rules the chain appended after the three the import seeded:

```wl
g2["Filters"]
```

<!-- => {"MaxVariants" -> 5, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr17", "MinImputationR2" -> 0.8} -->

Both accumulated rules bite when the rows are materialised: of the four chromosome 17 rows the fixture holds, two carry an imputation r-squared at or above the threshold, and the two directly assayed rows carry no `R2` field to compare:

```wl
g2["VariantCount"]
```

<!-- => 2 -->

Accumulation is immutable, so the filter spec of the original handle is untouched:

```wl
g["Filters"]
```

<!-- => {"MaxVariants" -> 5, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Repeated filters of the same kind are resolved when rows are materialised, and two caps intersect to the smaller one:

```wl
g["MaxVariants", 2]["VariantCount"]
```

<!-- => 2 -->

### Queries

Restricting a handle to a genomic interval at import time keeps every later query inside that window, and the box records the interval among the accumulated filters:

```wl
gr = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "Region" -> {"chr1", {100000, 300000}}, "Human" -> False, "Backend" -> "AwkStream"
]
```

A region query streams only the relevant block and gives a [Tabular]() of the canonical 17 columns:

```wl
gr["Region", "chr1", {100000, 200000}] // Dataset
```

Those columns are the same on every materialising query, so `"GT"`, `"R2"`, and the imputation-provenance flags are read off a row like any other field:

```wl
ColumnKeys[gr["Region", "chr1", {100000, 200000}]]
```

<!-- => {"CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO", "R2", "MAF", "AC", "AN", "IMPUTED", "TYPED", "TYPED_ONLY", "FORMAT", "GT"} -->

---

The lookup forms run over the filtered view rather than over the file. A capped, PASS-only handle:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"
]
```

`"Genotype"` looks up a single rsID and gives that whole row, which indexes like the [Association]() it is:

```wl
g["Genotype", "rs150"]["GT"]
```

<!-- => "1/1" -->

The fixture's `"rs250"` row carries the `LowQual` filter id, so this PASS-only handle does not hold it:

```wl
g["Genotype", "rs250"]
```

<!-- => Missing["NotFound", "rs250"] -->

`"Summary"` gives a two-column [Tabular]() whose `"Metric"` column names the seven statistics it reports over the filtered view:

```wl
g["Summary"] // Dataset
```

## Properties and Relations

A plain `Genome`, imported with `"Human" -> False`:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"
]
```

[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) tests whether an expression is a valid `Genome`:

```wl
GenomeQ[g]
```

<!-- => True -->

Importing the same file without `"Human" -> False` promotes this single-sample human callset to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which brings its own summary box:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "MaxVariants" -> 5]
```

[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) accepts that wrapper as well, so every operator typed on a `Genome` takes it unchanged:

```wl
GenomeQ[hg]
```

<!-- => True -->

[Length]() gives the variant count of the filtered view, the five rows the cap allows:

```wl
Length[g]
```

<!-- => 5 -->

[Dimensions]() pairs that count with the width of the materialised [Tabular](), without materialising the rows:

```wl
Dimensions[g]
```

<!-- => {5, 17} -->

## Possible Issues

A capped, streaming handle:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "MaxVariants" -> 5, "Human" -> False, "Backend" -> "AwkStream"
]
```

A `Genome` is not directly indexable, so [Part]() reports the boundary rather than guessing at a row:

```wl
g[[1]]
```

<!-- => the message Genome::notIndexable is issued and the result is $Failed -->

A subscript that names none of the property, query, or filter forms returns unevaluated, so the result comes back as the handle itself with the subscript still attached to it:

```wl
g["Chromosomes"]
```

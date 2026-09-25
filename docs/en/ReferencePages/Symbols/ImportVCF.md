---
Template: Symbol
Name: ImportVCF
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ImportVCF
Keywords: [VCF, import, variant, genome, lazy, filter, backend, GRCh37]
SeeAlso: [Genome, GenomeQ, ImportVCFHeader, RegionVariants, GenotypeLookup, VariantSummary]
RelatedGuides: [Genome]
---

## Usage

<code>[ImportVCF]()[*path*]</code> imports the VCF file *path* of called variants as a lazy <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code> handle.

<code>[ImportVCF]()[*path*, *opts*]</code> imports with filter options that seed the handle's filter spec.

## Details & Options

- `ImportVCF` parses the VCF header eagerly, through [ImportVCFHeader](paclet:WolframInstitute/Genome/ref/ImportVCFHeader), and is sub-second even on a multi-gigabyte file. No variant rows are read at import time; they materialise only when a query forces them.
- The handle carries the file path, the parsed header, the inferred reference build, the sample list, the selected backend, and the initial filter spec derived from the options below.
- Filter options do not filter at import time. They seed the handle's `"Filters"` slot, so they take effect when a query is later materialised. They accumulate with, and are overridden by, later filter accumulation and query-time options.
- *path* may be a plain `.vcf` file or a gzip / bgzip-compressed `.vcf.gz` or `.vcf.bgz` file; the reader picks the decompressor from the extension.
- With the default `"Human" -> Automatic`, a single-sample file on a human reference build is promoted to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). That wrapper satisfies [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) and forwards every [Genome](paclet:WolframInstitute/Genome/ref/Genome) property, query and filter form, so the two are interchangeable.
- A first argument that is not a string returns unevaluated.
- If the header cannot be read at all, `ImportVCF` gives <code>[$Failed]()</code>. A path that yields no meta-information instead gives a handle whose `"Build"` is `"Unknown"` and whose `"Samples"` is empty.

The following options can be given:

| | | |
|---|---|---|
| `"MaxVariants"` | [Infinity]() | cap the number of materialised rows; the stream stops once the cap is reached |
| `"Chromosome"` | [All]() | restrict to one chromosome (a string) or several (a list of strings); [All]() keeps every chromosome |
| `"Region"` | [None]() | restrict to a genomic interval `{chrom, {start, end}}`; a region wins over `"Chromosome"` when a query is materialised |
| `"PASSOnly"` | [True]() | keep only rows whose `FILTER` column is exactly `PASS` |
| `"ExcludeReferenceOnly"` | [True]() | drop reference-only rows whose `ALT` is `.` |
| `"MinImputationR2"` | 0 | keep only rows whose INFO `R2` is at least this value, which also drops rows declaring no `R2` at all; 0 disables the filter |
| `"Backend"` | [Automatic]() | storage backend: [Automatic]() (auto-detect), `"AwkStream"`, `"Tabix"`, or `"Parquet"` |
| `"Human"` | [Automatic]() | promote a single-sample human-build file to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome); [True]() promotes any human-build file, [False]() always keeps a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) |

- With `"Backend" -> Automatic` the backend is fixed at construction: `"Tabix"` when a sibling `.tbi` index exists and `bcftools` is on the path, `"Parquet"` when a `<path>.parquet` sidecar exists, and `"AwkStream"` otherwise. An explicit `"Tabix"` that lacks its prerequisites downgrades to `"AwkStream"` with a warning message.
- Only options that differ from their no-op value are recorded in the filter spec, which keeps the printed filter list short. Because `"PASSOnly"` and `"ExcludeReferenceOnly"` default to [True](), a bare `ImportVCF[path]` already seeds those two filters.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), and the handle comes back in a fraction of a second, before any variant row is read, summarised by its file, build, sample count, backend and size:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The backend is chosen at construction: a `.tbi` index sits beside the file and `bcftools` is on the path, so the indexed reader is selected:

```wl
subject["Backend"]
```

<!-- => "Tabix" -->

A bare import already seeds the two filters that default to on, keeping only `PASS` rows that carry an alternate allele:

```wl
subject["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Rows materialise only when a query asks for them. A query-time cap of five stops the stream at the first five variant rows of the file, chromosome 1 sites near its start, and gives them as a 17-column [Tabular]():

```wl
subject["Variants", "MaxVariants" -> 5] // Dataset
```

<!-- => a five-row Tabular of the canonical 17 columns -->

The sample column, parsed from the `#CHROM` line of the header:

```wl
subject["Samples"]
```

<!-- => {"SUBJECT"} -->

The reference build, inferred from the contig lengths of the header before any row is read:

```wl
subject["Build"]
```

<!-- => "GRCh37/hg19" -->

---

A small single-sample VCF, written to the temporary directory, stands in for a callset whose every row can be accounted for: ten rows over chromosomes 1 and 17, one sample column named for the public reference individual NA12878, and every genotype in it made up. Writing it gives back its path:

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

Importing with a cap of 5 variants and an explicit `"AwkStream"` backend fixes the streaming reader whatever else sits beside the file. The handle comes back before any variant row is read, and a single-sample file on a human reference build is promoted to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome):

```wl
g = ImportVCF[demoFile, "MaxVariants" -> 5, "Backend" -> "AwkStream"]
```

The handle satisfies [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ), so every [Genome](paclet:WolframInstitute/Genome/ref/Genome) operator accepts it:

```wl
GenomeQ[g]
```

<!-- => True -->

The options seed the filter spec, with the two defaulted-on filters recorded alongside the cap:

```wl
g["Filters"]
```

<!-- => {"MaxVariants" -> 5, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Asking for the variants materialises them as a 17-column [Tabular](); with `"MaxVariants" -> 5` the row count is the cap:

```wl
g["Variants"] // Dataset
```

## Scope

A handle on the demonstration file, pinned to the streaming reader. A single-sample file on a human build comes back promoted to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), with no variant row read yet:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

The reference build is inferred from the header's contig lengths and is available before any row is read:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

So is the sample list, parsed from the `#CHROM` column line:

```wl
g["Samples"]
```

<!-- => {"NA12878"} -->

The backend is chosen once, at import, and stored on the handle; this one pinned the streaming reader, which needs neither an index nor a sidecar:

```wl
g["Backend"]
```

<!-- => "AwkStream" -->

## Options

### "MaxVariants"

A cap is recorded in the filter spec and stops the stream once that many rows have passed the other filters:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "MaxVariants" -> 2]["Filters"]
```

<!-- => {"MaxVariants" -> 2, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

### "Chromosome"

A single chromosome name restricts every later query to that chromosome:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Chromosome" -> "chr17"]["Filters"]
```

<!-- => {"Chromosome" -> "chr17", "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

---

A list of names keeps several chromosomes:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Chromosome" -> {"chr1", "chr17"}]["Filters"]
```

<!-- => {"Chromosome" -> {"chr1", "chr17"}, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

### "Region"

A region seeds a positional filter that later region and genotype queries respect:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Region" -> {"chr1", {100000, 250000}}]["Filters"]
```

<!-- => {"Region" -> {"chr1", {100000, 250000}}, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

### "PASSOnly"

Setting `"PASSOnly" -> False` keeps rows that failed a filter, and the no-op setting is not recorded:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "PASSOnly" -> False]["Filters"]
```

<!-- => {"ExcludeReferenceOnly" -> True} -->

### "ExcludeReferenceOnly"

Setting `"ExcludeReferenceOnly" -> False` keeps the reference-confirming rows, which dominate a whole-genome callset:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "ExcludeReferenceOnly" -> False]["Filters"]
```

<!-- => {"PASSOnly" -> True} -->

### "MinImputationR2"

A positive threshold keeps only rows whose INFO `R2` reaches it; a row that declares no `R2` at all, such as a directly assayed one, is dropped along with the low-confidence ones:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "MinImputationR2" -> 0.9]["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "MinImputationR2" -> 0.9} -->

### "Backend"

An explicit backend overrides the auto-detection; `"AwkStream"` is the shell-streaming reader that needs no index and no sidecar:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]["Backend"]
```

<!-- => "AwkStream" -->

### "Human"

With `"Human" -> False` the promotion is suppressed and a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) comes back, carrying the same file, build and sample list:

```wl
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

## Properties and Relations

A handle capped at 5 variants and pinned to the streaming reader:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "MaxVariants" -> 5, "Backend" -> "AwkStream"]
```

The handle's `"Header"` slot holds exactly what [ImportVCFHeader](paclet:WolframInstitute/Genome/ref/ImportVCFHeader) gives for the file it points at:

```wl
g["Header"] === ImportVCFHeader[g["Path"]]
```

<!-- => True -->

An option given at query time overrides the one baked in at import; a query-time cap of 2 tightens the import-time cap of 5:

```wl
g["Variants", "MaxVariants" -> 2] // Dataset
```

Filter accumulation is immutable: a filter form gives a new handle over the same file, leaving `g` untouched:

```wl
gChr17 = g["Chromosome", "chr17"]
```

The new handle carries the accumulated spec, with the chromosome filter appended to the three the import seeded:

```wl
gChr17["Filters"]
```

<!-- => {"MaxVariants" -> 5, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr17"} -->

Counting through it materialises only the rows on the named chromosome:

```wl
Length[gChr17]
```

<!-- => 4 -->

## Possible Issues

An explicit `"Tabix"` backend needs both a sibling `.tbi` index and `bcftools` on the path, and no index sits beside the demo file:

```wl
FileExistsQ[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf.tbi"}]]
```

<!-- => False -->

Asking for it anyway issues `Genome::tabixNotAvailable`, which quotes the file's absolute path, and downgrades to the streaming reader, so the handle's `"Backend"` comes back as `"AwkStream"`:

```wl
#| eval: false
ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "Tabix"]["Backend"]
```

---

A path with nothing readable at it does not fail loudly. A path to a file that was never written:

```wl
FileExistsQ[missingFile = FileNameJoin[{$TemporaryDirectory, "not-a-genome.vcf"}]]
```

<!-- => False -->

A handle still comes back, and it is a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome): with no contig lengths to measure there is no human build to promote on, and the sample list is empty:

```wl
ImportVCF[missingFile]
```

The build it reports is read off that empty header, so it comes back as `"Unknown"`:

```wl
ImportVCF[missingFile]["Build"]
```

<!-- => "Unknown" -->

---

A first argument that is not a file path is not evaluated at all, so the call comes back as it was written:

```wl
ImportVCF[42]
```

<!-- => ImportVCF[42] -->

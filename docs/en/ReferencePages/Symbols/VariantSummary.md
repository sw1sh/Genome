---
Template: Symbol
Name: VariantSummary
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/VariantSummary
Keywords: [summary, statistics, variant, VCF, genome, Ts/Tv, imputation, Tabular]
SeeAlso: [Genome, GenotypeLookup, RegionVariants, ImportVCF]
RelatedGuides: [Genome]
---

## Usage

<code>[VariantSummary]()[*data*]</code> computes summary statistics over a variant set and gives them as a two-column [Tabular]() of `{Metric, Value}` rows.

## Details & Options

- *data* can be a <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code>, a materialised variant [Tabular](), or a path string to a VCF file.
- The result is a [Tabular]() with two columns, `"Metric"` and `"Value"`, one row per metric. The metrics are:
    - `"TotalRows"` - the number of rows in the variant set.
    - `"VariantRows"` - the number of rows with a non-empty `ALT` (rows that carry an alternate allele).
    - `"ByChromosome"` - an [Association]() of per-chromosome counts, ordered `chr1`..`chr22`, `chrX`, `chrY`, `chrM`.
    - `"ByFilter"` - an [Association]() of counts per `FILTER` id.
    - `"ByGenotypeClass"` - an [Association]() of counts per genotype class: `homRef`, `het`, `homAlt`, `missing`, or `other`.
    - `"ByImputationFlag"` - an [Association]() of counts across the imputation-provenance buckets `TYPED`, `IMPUTED`, `TYPED_ONLY`, and `NeitherFlag` (always covering the whole row set).
    - `"TransitionTransversionRatio"` - the ratio of transitions to transversions over biallelic single-nucleotide variants, or [Missing]() when there are no transversions.
- The seven metric rows come back in that order, so the shape of the result does not depend on the data.
- Every row of the input falls into exactly one genotype class and exactly one imputation bucket, so `"ByGenotypeClass"` and `"ByImputationFlag"` each total `"TotalRows"`.
- The metrics read the `CHROM`, `REF`, `ALT`, `FILTER`, `INFO` and `GT` columns of the rows; the remaining columns of the variant schema take no part in the summary.
- When *data* is a [Genome](paclet:WolframInstitute/Genome/ref/Genome), the variant rows are materialised through the backend first, respecting any accumulated filters; the summary covers the filtered view.
- When *data* is a [Tabular](), the rows are summarised exactly as given, with no further filtering.
- When *data* is a path string, [VariantSummary]() constructs a [Genome](paclet:WolframInstitute/Genome/ref/Genome) internally with [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF); it accepts the same options as [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF).
- An argument that is neither a [Genome](paclet:WolframInstitute/Genome/ref/Genome), a [Tabular]() nor a string returns unevaluated.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), and the `.tbi` index beside the file selects the tabix backend:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The summary covers the filtered view of the handle, so the filters on the handle decide how much of the file is materialised. Summarising all 5.7 million rows means parsing all of them in the kernel, a scan of some minutes; with the view narrowed to chromosome 22 the filter is pushed into the stream, only the rows of that chromosome are parsed, and the seven metric rows come back in about half a minute:

```wl
VariantSummary[subject["Chromosome", "chr22"]] // Dataset
```

<!-- => the seven metric rows of chromosome 22: TotalRows 90365, VariantRows 90365, ByChromosome <|"chr22" -> 90365|>, then ByFilter, ByGenotypeClass, ByImputationFlag and TransitionTransversionRatio -->

`"TotalRows"` is 90365, the rows of chromosome 22 in the callset. `"VariantRows"` agrees with it, since the import defaults exclude reference-only rows from the view, and `"ByChromosome"` has the single key `"chr22"`. The remaining metrics - the counts per `FILTER` id, per genotype class and per imputation-provenance bucket, and the transition/transversion ratio - describe the same 90365 rows.

---

A small demonstration VCF, ten single-sample records spread over chromosomes 1 and 17, small enough that every metric can be checked by hand against the file, written to a temporary file whose path is `demoFile`:

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

A single-sample human VCF autopromotes on import to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). Pinning the streaming backend keeps the variant schema fixed, independent of what else sits beside the file:

```wl
hg = ImportVCF[demoFile, "Backend" -> "AwkStream"]
```

The summary is a two-column [Tabular]() of metric rows:

```wl
VariantSummary[hg] // Dataset
```

## Scope

### A Genome view

A handle on the demonstration file, with the streaming backend pinned:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

Keying the metric rows by name turns the two-column table into a lookup for the individual statistics:

```wl
summary = Association[#Metric -> #Value & /@ Normal[VariantSummary[hg]]]
```

<!-- => the seven metrics, keyed by metric name -->

`"TotalRows"` counts every row of the filtered view - eight of the file's ten records, the import defaults having dropped one reference-only record and one that is not `PASS`:

```wl
summary["TotalRows"]
```

<!-- => 8 -->

Since those defaults already dropped the reference-only record, every remaining row carries an alternate allele and `"VariantRows"` agrees with `"TotalRows"`:

```wl
summary["VariantRows"] === summary["TotalRows"]
```

<!-- => True -->

The per-chromosome breakdown has one key per contig the view touches, in genomic order:

```wl
summary["ByChromosome"]
```

<!-- => <|"chr1" -> 4, "chr17" -> 4|> -->

The genotype classes count the calls themselves, reading the `GT` column of each row:

```wl
summary["ByGenotypeClass"]
```

<!-- => <|"het" -> 5, "homAlt" -> 2, "homRef" -> 1|> -->

Every row falls into exactly one genotype class, so the class counts total `"TotalRows"`:

```wl
Total[summary["ByGenotypeClass"]] === summary["TotalRows"]
```

<!-- => True -->

All four imputation-provenance buckets are present, whether or not the flags appear in the data:

```wl
summary["ByImputationFlag"]
```

Those buckets cover the whole row set, so they total `"TotalRows"` as well:

```wl
Total[summary["ByImputationFlag"]] === summary["TotalRows"]
```

<!-- => True -->

The transition/transversion ratio is taken over the biallelic single-nucleotide rows only, and the two indels take no part in it. The demonstration file holds two transitions against four transversions:

```wl
summary["TransitionTransversionRatio"]
```

<!-- => 0.5 -->

### A materialised Tabular

The demonstration file on the streaming backend:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

Materialise a chromosome 1 interval as a variant [Tabular]():

```wl
(sub = RegionVariants[hg, "chr1", {100000, 200000}]) // Dataset
```

Rows handed over as a [Tabular]() are summarised as given, so `"TotalRows"` agrees with the length of the table:

```wl
SelectFirst[Normal[VariantSummary[sub]], #["Metric"] === "TotalRows" &]["Value"] === Length[sub]
```

<!-- => True -->

### A path string

The path of the demonstration file:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the full path the file was written to -->

A path string is imported first, and the [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) options apply to that import:

```wl
VariantSummary[demoFile, "MaxVariants" -> 5] // Dataset
```

### Arguments outside the scope

An argument that is neither a [Genome](paclet:WolframInstitute/Genome/ref/Genome), a [Tabular]() nor a string matches no definition, and the expression comes back unevaluated:

```wl
VariantSummary[42]
```

<!-- => VariantSummary[42] -->

## Possible Issues

The transition/transversion ratio needs a transversion to divide by. A one-row table whose only variant is the transition `A` to `G`:

```wl
(ts = Tabular[{<|"CHROM" -> "chr1", "POS" -> 100, "REF" -> "A", "ALT" -> {"G"}, "GT" -> "0/1"|>}]) // Dataset
```

With no transversion in the row set the ratio is [Missing]() rather than a number:

```wl
SelectFirst[Normal[VariantSummary[ts]], #["Metric"] === "TransitionTransversionRatio" &]["Value"]
```

<!-- => Missing[] -->

---

A reference-only row carries an empty `ALT`:

```wl
(refOnly = Tabular[{<|"CHROM" -> "chr1", "POS" -> 100, "REF" -> "A", "ALT" -> {}, "GT" -> "0/0"|>}]) // Dataset
```

`"TotalRows"` counts such a row and `"VariantRows"` does not, which is what separates the two counts:

```wl
SelectFirst[Normal[VariantSummary[refOnly]], #["Metric"] === "VariantRows" &]["Value"]
```

<!-- => 0 -->

---
Template: Symbol
Name: RegionVariants
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/RegionVariants
Keywords: [region, interval, variant, VCF, genome, chromosome, Tabular]
SeeAlso: [Genome, GenotypeLookup, VariantSummary, ImportVCF]
RelatedGuides: [Genome]
---

## Usage

<code>[RegionVariants]()[*data*, *chrom*, {*start*, *end*}]</code> gives the variants of *data* that lie between the positions *start* and *end* on chromosome *chrom*, as a [Tabular]().

## Details & Options

- *data* can be a <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code>, a materialised variant [Tabular](), or a path string to a VCF file.
- *chrom* is a chromosome name string, spelled the way the file spells it (`"chr1"` and `"chr17"` in a `chr`-prefixed callset, `"1"` and `"17"` in an unprefixed one).
- *start* and *end* are 1-based integer positions, matching VCF coordinates. The interval is inclusive at both ends: a row is kept when its `"POS"` is at least *start* and at most *end*.
- The result is a [Tabular]() with the same 17-column variant schema as `g["Variants"]`. An interval that holds no matching row gives a [Tabular]() of no rows, whose [Dimensions]() is `{0}`.
- When *data* is a [Genome](paclet:WolframInstitute/Genome/ref/Genome), the query dispatches through the backend. A sibling `.tbi` index and `bcftools` on the path let it seek straight to the overlapping blocks; otherwise the interval is pushed into the awk program, which stops scanning once it moves past *end*.
- When *data* is a [Tabular](), the rows are filtered in the kernel with a positional predicate.
- When *data* is a path string, [RegionVariants]() constructs a [Genome](paclet:WolframInstitute/Genome/ref/Genome) internally with [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF), scoping that import to the requested interval, and takes the options of [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF).
- The row-level filters already accumulated on a [Genome](paclet:WolframInstitute/Genome/ref/Genome) - `"PASSOnly"`, `"ExcludeReferenceOnly"`, `"MinImputationR2"` and the rest - apply to the rows of the interval. The interval given here replaces any `"Region"` the handle already carries, rather than narrowing it.
- A *chrom* that is not a string, or an interval that is not a pair of integers, matches no definition and returns unevaluated.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), and the `.tbi` index beside the file selects the tabix backend:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The HERC2/OCA2 window on chromosome 15 is the region whose common variants set eye colour. On the tabix backend the query is an index seek straight to that interval, and the rows of the window come back as a [Tabular]() over the canonical 17-column variant schema:

```wl
RegionVariants[subject, "chr15", {28350000, 28370000}] // Dataset
```

<!-- => the variant rows of chr15:28350000-28370000, a Tabular of 17 columns -->

The `"Region"` property of the handle is the same query, reaching the same backend:

```wl
subject["Region", "chr15", {28350000, 28370000}] // Dataset
```

<!-- => the same Tabular -->

---

A demonstration VCF of ten single-sample records spread over chromosomes 1 and 17, small enough that every row of a result can be accounted for, written to a temporary file whose path is kept in `demoFile`:

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

A single-sample human VCF autopromotes on import to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). Pinning the streaming backend fixes the variant schema, whatever else sits beside the file:

```wl
hg = ImportVCF[demoFile, "Backend" -> "AwkStream"]
```

The variants of an interval on chromosome 1 come back as a [Tabular]() of the matching rows:

```wl
RegionVariants[hg, "chr1", {100000, 200000}] // Dataset
```

Two rows of the view fall in that interval, and each carries the full 17-column variant schema. The file writes a third record inside it, at 200000, but that one carries no alternate allele and the import defaults dropped it before the query ran.

## Scope

### The interval

A handle on the demonstration file, with the streaming backend pinned:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

Both endpoints are inclusive. Narrowing the interval until its start and end are exactly the positions of two records still returns both of them:

```wl
RegionVariants[hg, "chr1", {100000, 150000}] // Dataset
```

An interval that holds nothing, such as one whose start is past its end, gives an empty [Tabular](), which carries no columns either:

```wl
RegionVariants[hg, "chr1", {200000, 100000}]
```

A second chromosome is queried the same way, by name:

```wl
RegionVariants[hg, "chr17", {1000000, 1300000}] // Dataset
```

### Other input forms

The path of the demonstration file:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the full path the file was written to -->

A handle on it, with the streaming backend pinned:

```wl
hg = ImportVCF[demoFile, "Backend" -> "AwkStream"]
```

*data* can be the materialised rows themselves. Materialise the whole view as a [Tabular]():

```wl
(vars = hg["Variants"]) // Dataset
```

Filtering those rows in the kernel gives exactly what the backend query gives:

```wl
Normal[RegionVariants[vars, "chr1", {100000, 200000}]] === Normal[RegionVariants[hg, "chr1", {100000, 200000}]]
```

<!-- => True -->

A path string is imported internally, with the import scoped to the interval, so no handle need be constructed first:

```wl
RegionVariants[demoFile, "chr1", {100000, 200000}] // Dataset
```

## Properties and Relations

A handle on the demonstration file, streaming backend pinned:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

[RegionVariants]() is the operator spelling of the [Genome](paclet:WolframInstitute/Genome/ref/Genome) `"Region"` property; both reach the same backend:

```wl
Normal[RegionVariants[hg, "chr1", {100000, 200000}]] === Normal[hg["Region", "chr1", {100000, 200000}]]
```

<!-- => True -->

An interval spanning a whole contig selects that chromosome's rows, four of the eight the view holds:

```wl
RegionVariants[hg, "chr1", {1, 249250621}] // Dataset
```

A region result is itself variant data, so [GenotypeLookup](paclet:WolframInstitute/Genome/ref/GenotypeLookup) searches it by identifier where this function searches by coordinate. Asking a chromosome 1 interval for a chromosome 17 id finds nothing:

```wl
GenotypeLookup[RegionVariants[hg, "chr1", {100000, 200000}], "rs1000"]
```

<!-- => Missing["NotFound", "rs1000"] -->

## Possible Issues

The query interval replaces a handle's own `"Region"`, so a query cannot be assumed to stay inside the scope the handle was imported with. The path of the demonstration file:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the full path the file was written to -->

A handle scoped to a chromosome 1 interval, on the pinned backend:

```wl
gnarrow = ImportVCF[demoFile, "Region" -> {"chr1", {100000, 200000}}, "Backend" -> "AwkStream"]
```

Its own view holds the two rows of that interval:

```wl
gnarrow["Variants"] // Dataset
```

Asked for an interval on chromosome 17, the same handle gives the four rows of it - the query interval won, and the import-time region no longer bounds the result:

```wl
RegionVariants[gnarrow, "chr17", {1000000, 1300000}] // Dataset
```

---

A chromosome name is matched literally, so the `chr` prefix has to match the file. A handle on the demonstration file, streaming backend pinned:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

This callset writes `"chr1"`, and the unprefixed spelling selects nothing:

```wl
RegionVariants[hg, "1", {100000, 200000}]
```

A chromosome given as a number rather than as a name string matches no definition, and the expression comes back unevaluated:

```wl
RegionVariants[hg, 1, {100000, 200000}]
```

So does an interval that is not a pair of integer positions:

```wl
RegionVariants[hg, "chr1", {100000}]
```

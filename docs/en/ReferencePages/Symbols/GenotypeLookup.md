---
Template: Symbol
Name: GenotypeLookup
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenotypeLookup
Keywords: [genotype, rsID, lookup, variant, VCF, genome]
SeeAlso: [Genome, RegionVariants, VariantSummary, ImportVCF]
RelatedGuides: [Genome]
---

## Usage

<code>[GenotypeLookup]()[*data*, *rsid*]</code> gives the variant row of *data* whose `ID` column holds the rsID *rsid*.

<code>[GenotypeLookup]()[*data*, {$rsid_1$, $rsid_2$, …}]</code> gives an [Association]() from each rsID to its variant row.

## Details & Options

- *data* can be a <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code>, a materialised variant [Tabular](), or a path string to a VCF file.
- For a single *rsid* the result is one variant row, an [Association]() keyed by the 17-column variant schema: the eight VCF fields `"CHROM"`, `"POS"`, `"ID"`, `"REF"`, `"ALT"`, `"QUAL"`, `"FILTER"` and `"INFO"`, the surfaced INFO columns `"R2"`, `"MAF"`, `"AC"`, `"AN"`, `"IMPUTED"`, `"TYPED"` and `"TYPED_ONLY"`, then `"FORMAT"` and `"GT"`.
- An rsID that no row of the view carries gives [Missing]()`["NotFound", `*rsid*`]`.
- For a list of rsIDs the result is an [Association]() keyed by the ids asked for, in the order they were given, each mapping to its variant row or to the same [Missing]() as above. The keys are the distinct ids, so a repeated id appears once.
- `"GT"` holds the sample column of the VCF record verbatim, as a string. `"FORMAT"` names its colon-separated fields, the first of which is the genotype call itself - an allele pair written with a slash when unphased and with a bar when phased.
- When *data* is a [Genome](paclet:WolframInstitute/Genome/ref/Genome), the single-rsID form dispatches through the backend and stops scanning at the first matching row; the list form materialises the filtered rows once and indexes them by id.
- When *data* is a path string, [GenotypeLookup]() constructs a [Genome](paclet:WolframInstitute/Genome/ref/Genome) internally with [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF), and takes the options of [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) to scope that import.
- The lookup reads the filtered view rather than the file. A region, `"PASSOnly"`, `"MinImputationR2"` or any other filter already accumulated on the [Genome](paclet:WolframInstitute/Genome/ref/Genome) applies first, so an rsID whose row those filters drop is reported as not found.
- An rsID given as anything but a string, or as a list holding a non-string element, matches no definition and returns unevaluated.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), and the `.tbi` index beside the file selects the tabix backend:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

`rs12913832` is the HERC2 variant whose genotype accounts for most of the difference between blue and brown eyes. Looking it up gives the whole variant row, one [Association]() over the 17-column variant schema: position, alleles, filter status, imputation provenance and genotype. The backend streams the file and stops at the first row whose `"ID"` matches:

```wl
GenotypeLookup[subject, "rs12913832"]
```

<!-- => the variant row for rs12913832 on chr15, an Association of the 17 variant columns -->

An rsID the callset does not hold gives a [Missing]() carrying the id that was asked for:

```wl
GenotypeLookup[subject, "rs9999999"]
```

<!-- => Missing["NotFound", "rs9999999"] -->

The `"Genotype"` property of the handle is the same lookup, reaching the same backend. `rs713598` is a TAS2R38 variant behind the ability to taste phenylthiocarbamide as bitter:

```wl
subject["Genotype", "rs713598"]
```

<!-- => the variant row for rs713598 on chr7, an Association of the 17 variant columns -->

The list form materialises the filtered view once and indexes it by id, so on an unscoped whole-genome handle it is a pass over every row. A handle scoped at import to the HERC2/OCA2 window keeps that view to the rows of the window:

```wl
herc2 = ImportVCF["data/subject_genome.vcf.gz", "Region" -> {"chr15", {28350000, 28370000}}]
```

Several ids are then looked up in one pass, and the result is keyed by the ids themselves. `rs1129038` is a second eye-colour variant of the same window:

```wl
GenotypeLookup[herc2, {"rs12913832", "rs1129038"}]
```

<!-- => an Association keyed by the two ids -->

---

A demonstration VCF of ten single-sample records spread over chromosomes 1 and 17, small enough that every row can be accounted for, written to a temporary file whose path is `demoFile`:

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

Lookups match on the `"ID"` column of the filtered view. Eight of the ten records survive the import defaults: the record at `chr1:200000` carries no alternate allele and no rsID, and `rs250` is filtered `LowQual`:

```wl
hg["Variants"] // Dataset
```

Looking one of those ids up gives its row, with position, alleles, filter status, imputation provenance and genotype all present:

```wl
GenotypeLookup[hg, "rs100"]
```

<!-- => the variant row for chr1:100000, an Association of the 17 variant columns -->

## Scope

### Reading a row

A handle on the demonstration file, with the streaming backend pinned:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

The genotype is the `"GT"` column, the sample column of the record held verbatim. The record at `chr1:150000` is homozygous for the alternate allele, written unphased:

```wl
GenotypeLookup[hg, "rs150"]["GT"]
```

<!-- => "1/1" -->

Held verbatim means held as a string, whatever the ploidy and phasing of the call:

```wl
StringQ[GenotypeLookup[hg, "rs150"]["GT"]]
```

<!-- => True -->

The colon-separated fields of that column are named by `"FORMAT"`, whose first field is the genotype call:

```wl
GenotypeLookup[hg, "rs150"]["FORMAT"]
```

<!-- => "GT" -->

### Several rsIDs at once

The demonstration file on the streaming backend:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

A list of ids is looked up in one pass, and the result is keyed by the ids themselves:

```wl
GenotypeLookup[hg, {"rs100", "rs1200"}]
```

The keys are exactly the ids asked for, in the order they were given, whether or not the view holds them:

```wl
GenotypeLookup[hg, {"rs100", "rs1200", "rs9999"}]
```

The entry for an id the view holds is the row the single-rsID form gives:

```wl
GenotypeLookup[hg, {"rs100", "rs1200", "rs9999"}]["rs100"] === GenotypeLookup[hg, "rs100"]
```

<!-- => True -->

The entry for an id the view lacks is the same [Missing]() the single-rsID form gives:

```wl
GenotypeLookup[hg, {"rs100", "rs1200", "rs9999"}]["rs9999"]
```

<!-- => Missing["NotFound", "rs9999"] -->

### Other input forms

The path of the demonstration file:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the full path the file was written to -->

Imported on the pinned backend:

```wl
hg = ImportVCF[demoFile, "Backend" -> "AwkStream"]
```

*data* can also be the materialised rows themselves. Materialise the view as a [Tabular]():

```wl
(vars = hg["Variants"]) // Dataset
```

Looking the id up in those rows gives what the handle gives, since the handle materialises the same filtered view:

```wl
GenotypeLookup[vars, "rs100"] === GenotypeLookup[hg, "rs100"]
```

<!-- => True -->

A path string is imported internally, so no handle need be constructed first:

```wl
AssociationQ[GenotypeLookup[demoFile, "rs100"]]
```

<!-- => True -->

## Properties and Relations

The demonstration file, imported on the pinned backend:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Backend" -> "AwkStream"]
```

[GenotypeLookup]() is the operator spelling of the [Genome](paclet:WolframInstitute/Genome/ref/Genome) `"Genotype"` property; both reach the same backend:

```wl
GenotypeLookup[hg, "rs100"] === hg["Genotype", "rs100"]
```

<!-- => True -->

An rsID resolves to a row that [RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants) also gives for an interval containing its position - one lookup is by identifier, the other by coordinate:

```wl
MemberQ[Normal[RegionVariants[hg, "chr1", {100000, 200000}]], GenotypeLookup[hg, "rs100"]]
```

<!-- => True -->

## Possible Issues

The path of the demonstration file:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the full path the file was written to -->

A handle on it, on the pinned backend:

```wl
hg = ImportVCF[demoFile, "Backend" -> "AwkStream"]
```

The list result is keyed by id rather than by list position, so a repeated id contributes a single entry:

```wl
GenotypeLookup[hg, {"rs100", "rs100"}]
```

Filters accumulated on the handle apply before the lookup, so an rsID the file holds is reported as not found when the view excludes it. The import defaults keep only `PASS` records, and the file writes `rs250` as `LowQual`:

```wl
GenotypeLookup[hg, "rs250"]
```

<!-- => Missing["NotFound", "rs250"] -->

Because a path string is imported with the options given alongside the query, relaxing the filter that dropped the row brings it back:

```wl
GenotypeLookup[demoFile, "rs250", "PASSOnly" -> False]["FILTER"]
```

<!-- => {"LowQual"} -->

An rsID given as a number matches no definition, so the expression comes back unevaluated, with the handle displayed inside it:

```wl
GenotypeLookup[hg, 12345]
```

So does a list holding a non-string element, even when every other element is an rsID:

```wl
GenotypeLookup[hg, {"rs100", 12345}]
```

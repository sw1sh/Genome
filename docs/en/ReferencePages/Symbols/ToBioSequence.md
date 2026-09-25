---
Template: Symbol
Name: ToBioSequence
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ToBioSequence
Keywords: [BioSequence, DNA, sequence, region, genotype, reference genome, experimental]
SeeAlso: [Genome, RegionVariants, GenotypeLookup, ImportVCF]
RelatedGuides: [Genome]
---

## Usage

<code>[ToBioSequence]()[…]</code> builds a [BioSequence]() object from a genomic region or genotype drawn from imported data.

## Details & Options

- `ToBioSequence` is experimental and not yet implemented in this release: any argument sequence issues a `ToBioSequence::nyi` message and gives <code>[$Failed]()</code>.
- The intended behavior is to materialise a reference DNA subsequence for a genomic region (via [GenomeData]()) and apply the sample's called variants from a [Genome](paclet:WolframInstitute/Genome/ref/Genome), giving a [BioSequence]() of type `"DNA"` that composes with the Wolfram bioinformatics functions.
- The planned entry point takes a [Genome](paclet:WolframInstitute/Genome/ref/Genome) together with a chromosome and interval, mirroring [RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants): the region selects the reference span, and the genotype calls carried by the [Genome](paclet:WolframInstitute/Genome/ref/Genome) edit that span into the sample's own sequence.
- Subsequence extraction on a [BioSequence]() is intended to go through [StringTake]() rather than [Part]() or span extraction, matching the behavior of [BioSequence]() in the current Wolfram Language.
- The stub definition matches every argument sequence, so there is no unevaluated form: an empty argument sequence issues the same message as the planned region form.
- Until the builder ships, use [RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants) and [GenotypeLookup](paclet:WolframInstitute/Genome/ref/GenotypeLookup) to inspect the variant rows directly.

## Basic Examples

The sequence builder takes a genome handle and a region. The examples run on a small demo VCF written to a temporary file: ten data rows over two chromosomes, one sample column, and the meta-information that makes sense of them:

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

A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), the handle the planned region form takes:

```wl
g = ImportVCF[demoFile]
```

That handle, a chromosome and an interval are the planned region form. In this release the arguments reach the stub definition, which issues the not-yet-implemented message:

```wl
ToBioSequence[g, "chr1", {100000, 300000}]
```

<!-- => the message ToBioSequence::nyi is issued and the result is $Failed -->

## Scope

The stub definition matches every argument sequence, so there is no unevaluated form; an empty argument sequence issues the same message:

```wl
ToBioSequence[]
```

<!-- => the message ToBioSequence::nyi is issued and the result is $Failed -->

## Properties and Relations

Until the builder ships, the calls it would edit into the reference span are reached directly. A handle on the demo file:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

[RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants) takes the same chromosome and interval the planned region form would, and gives the rows in that span:

```wl
RegionVariants[g, "chr1", {100000, 300000}] // Dataset
```

One call is reached by its rsID. The reference allele, the alternate and the genotype are what the builder would apply to the reference bases at that position; rs300 is a one-base deletion the sample carries on one of its two copies of chr1:

```wl
KeyTake[GenotypeLookup[g, "rs300"], {"POS", "REF", "ALT", "GT"}]
```

<!-- => <|"POS" -> 300000, "REF" -> "GA", "ALT" -> {"G"}, "GT" -> "0/1"|> -->

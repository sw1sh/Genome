---
Template: Symbol
Name: ImportGenotypeArray
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ImportGenotypeArray
Keywords: [genotyping array, 23andMe, raw genotype, TSV, import, experimental]
SeeAlso: [ImportVCF, Genome, GenotypeLookup]
RelatedGuides: [Genome]
---

## Usage

<code>[ImportGenotypeArray]()[*path*]</code> imports a genotyping-array raw genotype table (rsid, chromosome, position, genotype) into a [Tabular]().

## Details & Options

- `ImportGenotypeArray` is experimental and not yet implemented in this release: a path argument issues an `ImportGenotypeArray::nyi` message and gives <code>[$Failed]()</code>.
- The intended behavior is to read a 23andMe-style genotyping-array raw genotype TSV - one row per assayed marker, with columns for the rsID, chromosome, position, and the called genotype - and give the markers as a [Tabular]() with typed columns.
- This is the array-genotype counterpart to [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF), which handles the called-variant VCF case. A genotyping array reports a fixed panel of directly-typed markers rather than the imputed, whole-genome call set that a VCF carries.
- The message is issued from the path argument alone; the file is never opened, so an unwritten path reaches the stub exactly as an existing one does.
- An argument other than a single path string matches no definition and returns unevaluated.
- Until the reader ships, use [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) for VCF data.

## Basic Examples

The array reader has no format of its own to read yet; the examples stand it beside the VCF reader, the counterpart that does import today. A small demo VCF written to a temporary file: ten data rows over two chromosomes, one sample column, and the meta-information that makes sense of them:

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

A path argument reaches the stub definition, which issues the not-yet-implemented message:

```wl
ImportGenotypeArray["markers.txt"]
```

<!-- => the message ImportGenotypeArray::nyi is issued and the result is $Failed -->

Until the array reader ships, the VCF path is the one that imports. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome):

```wl
g = ImportVCF[demoFile]
```

## Scope

An argument that is not a string matches no definition, so nothing evaluates and no message is issued - the call comes back unchanged:

```wl
ImportGenotypeArray[3]
```

<!-- => ImportGenotypeArray[3] -->

## Properties and Relations

A handle on the demo VCF:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The marker table the reader will give is the shape [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) already produces - one row per marker, carrying the rsID, its chromosome and position, and the genotype call. Those are exactly the four columns a raw array table holds:

```wl
g["Variants"] // Dataset
```

A single marker is reached by its rsID, the way an array table is indexed:

```wl
KeyTake[GenotypeLookup[g, "rs300"], {"ID", "REF", "ALT", "GT"}]
```

<!-- => <|"ID" -> "rs300", "REF" -> "GA", "ALT" -> {"G"}, "GT" -> "0/1"|> -->

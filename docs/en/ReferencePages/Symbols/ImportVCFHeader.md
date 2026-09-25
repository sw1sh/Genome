---
Template: Symbol
Name: ImportVCFHeader
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ImportVCFHeader
Keywords: [VCF, header, meta-information, contigs, INFO, FORMAT, FILTER, samples, build inference]
SeeAlso: [ImportVCF, Genome, GenomeQ]
RelatedGuides: [Genome]
---

## Usage

<code>[ImportVCFHeader]()[*path*]</code> streams just the meta-information of the VCF file *path* and gives an [Association]() describing its header.

## Details & Options

- `ImportVCFHeader` reads only the leading header lines, the `##` meta-information lines plus the `#CHROM` column line, and stops at the first data row, so it is fast even on a multi-gigabyte file.
- *path* may be a plain `.vcf` file or a gzip / bgzip-compressed `.vcf.gz` or `.vcf.bgz` file; the reader picks the decompressor from the extension.
- The result is an [Association]() with the following keys:

| | |
|---|---|
| `"Path"` | the file path that was read |
| `"FileFormat"` | the `##fileformat` value, for example `"VCFv4.2"`, or [Missing]() when absent |
| `"Source"` | the `##source` value, naming the tool that wrote the file, or [Missing]() |
| `"Reference"` | the `##reference` value, or [Missing]() when the file records none |
| `"InferredBuild"` | the reference build inferred from the contig lengths: `"GRCh37/hg19"`, `"GRCh38"`, `"T2T-CHM13v2.0"`, or `"Unknown"` |
| `"Contigs"` | a list of contig [Association]()s, each with `"Tag"`, `"ID"`, and `"Length"` |
| `"INFO"` | a list of INFO-field [Association]()s, each with `"Tag"` and `"ID"` |
| `"FORMAT"` | a list of FORMAT-field [Association]()s, each with `"Tag"` and `"ID"` |
| `"FILTER"` | a list of FILTER-definition [Association]()s, each with `"Tag"` and `"ID"` |
| `"Samples"` | the sample ids parsed from the `#CHROM` line, the columns after the first nine |
| `"MetaLineCount"` | the number of `##` meta-information lines |

- The build is inferred from the contig lengths rather than from `##reference`, which imputation and variant-calling pipelines often omit: the `chr1` length identifies the build, with the `chrM` length separating GRCh38 from its predecessors. Contig lengths matching none of the three supported references give `"Unknown"`.
- Only the tag, the id and, for a contig, the integer length are parsed out of a structured meta line; the embedded `Description` text is left alone.
- A definition list holds one entry per declaration the file actually writes, so a file that declares no `##FILTER` lines has an empty `"FILTER"` list even when its data rows carry filter values.
- [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) parses the header with `ImportVCFHeader` and surfaces the same [Association]() as `g["Header"]` on the resulting [Genome](paclet:WolframInstitute/Genome/ref/Genome).
- A file with no readable meta-information gives a header of the same shape with every scalar field [Missing](), empty definition lists, an empty sample list, `"MetaLineCount"` of 0 and an `"Unknown"` build. `ImportVCFHeader` gives <code>[$Failed]()</code> only when the streaming reader itself produces nothing.
- An argument that is not a string returns unevaluated.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. Reading its header streams only the meta-information section, 58 `##` lines plus the `#CHROM` column line, and gives it back as one [Association]():

```wl
h = ImportVCFHeader["data/subject_genome.vcf.gz"]
```

The contig list holds one entry per `##contig` line, each an [Association]() carrying its tag, its id and its length: 25 contigs, `chr1` through `chr22`, `chrX`, `chrY` and `chrM`, with `chr1` at 249250621 bases and `chrM` at 16571:

```wl
h["Contigs"]
```

<!-- => a list of 25 contig Associations, chr1 (249250621) through chrM (16571) -->

Those lengths are what the build inference measures; the `chr1` length identifies GRCh37, and the `chrM` length of 16571 places it before GRCh38:

```wl
h["InferredBuild"]
```

<!-- => "GRCh37/hg19" -->

The sample ids come from the columns after the first nine of the `#CHROM` line:

```wl
h["Samples"]
```

<!-- => {"SUBJECT"} -->

The `##source` line names the tool that wrote the file, the Minimac4 imputation engine:

```wl
h["Source"]
```

<!-- => "Minimac4.v1.0.2" -->

The meta-line count sizes the header without listing it:

```wl
h["MetaLineCount"]
```

<!-- => 58 -->

---

A small single-sample VCF written to the temporary directory, whose every header line can be accounted for: two contigs, four INFO definitions, one FORMAT definition and no FILTER definitions. Writing it gives back its path:

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

The header of that file is an [Association]() of the same shape, nine meta-information lines long:

```wl
h = ImportVCFHeader[demoFile]
```

Its one sample column is named for the public reference individual NA12878:

```wl
h["Samples"]
```

<!-- => {"NA12878"} -->

## Scope

The header of the demo file, as one [Association]():

```wl
h = ImportVCFHeader[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The `"Path"` key echoes the file that was read:

```wl
h["Path"]
```

<!-- => the full path the file was written to -->

The declared file format is the `##fileformat` line, the first line of any conforming VCF:

```wl
h["FileFormat"]
```

<!-- => "VCFv4.2" -->

The `##source` line names the tool that wrote the file:

```wl
h["Source"]
```

<!-- => "WolframInstituteGenomeDemo" -->

A field the file does not declare comes back as [Missing](). This file records no `##reference` line, so its build has to be inferred:

```wl
h["Reference"]
```

<!-- => Missing[] -->

The meta-line count sizes the header without listing it:

```wl
h["MetaLineCount"]
```

<!-- => 9 -->

The contig list is what the build inference measures; it holds one entry per `##contig` line, each an [Association]() carrying its tag, its id and its length:

```wl
h["Contigs"]
```

The INFO list has one entry per `##INFO` definition, whether or not any row uses it:

```wl
h["INFO"]
```

The FORMAT list is read the same way, and a single-sample genotype file usually declares only `GT`:

```wl
h["FORMAT"]
```

<!-- => {<|"Tag" -> "FORMAT", "ID" -> "GT"|>} -->

A definition list the file never writes comes back empty; this one declares no `##FILTER` lines, even though one of its data rows carries a `LowQual` filter value:

```wl
h["FILTER"]
```

<!-- => {} -->

## Properties and Relations

[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) parses the header with `ImportVCFHeader` at import time. A handle on the demo file:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The handle's `"Header"` slot holds exactly the [Association]() this symbol gives for the file it points at:

```wl
g["Header"] === ImportVCFHeader[g["Path"]]
```

<!-- => True -->

A single key of it can be read straight off the handle:

```wl
g["Header", "Samples"]
```

<!-- => {"NA12878"} -->

The inferred build is what a [Genome](paclet:WolframInstitute/Genome/ref/Genome) reports as its own `"Build"`:

```wl
g["Build"] === ImportVCFHeader[g["Path"]]["InferredBuild"]
```

<!-- => True -->

## Possible Issues

A path with nothing readable at it does not fail loudly. Point at a file that was never written:

```wl
FileExistsQ[missingFile = FileNameJoin[{$TemporaryDirectory, "not-a-genome.vcf"}]]
```

<!-- => False -->

The header keeps its shape and reports an empty meta-information section:

```wl
ImportVCFHeader[missingFile]["MetaLineCount"]
```

<!-- => 0 -->

With no contig lines to measure, the build inference has nothing to go on:

```wl
ImportVCFHeader[missingFile]["InferredBuild"]
```

<!-- => "Unknown" -->

---

An argument that is not a file path is not evaluated at all, so the call comes back as it was written:

```wl
ImportVCFHeader[42]
```

<!-- => ImportVCFHeader[42] -->

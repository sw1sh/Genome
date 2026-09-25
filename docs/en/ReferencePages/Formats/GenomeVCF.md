---
Template: Format
Name: GenomeVCF
Extension: .vcf
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/format/GenomeVCF
Description: A VCF file of called variants read as the paclet's lazy Genome handle, with its header, samples, build and variants as elements.
Keywords: [VCF, genome, variants, genotype, import, lazy, streaming, GRCh37, GRCh38]
SeeAlso: [Genome, HumanGenome, ImportVCF, ImportVCFHeader, RegionVariants, GenotypeLookup, Import]
RelatedGuides: [Genome]
---

# GenomeVCF

GenomeVCF reads a VCF file of called variants as the paclet's <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code> handle: the header is parsed eagerly and the variant rows only materialise when a query asks for them, which is what keeps a multi-gigabyte whole-genome file usable from a notebook. Loading the WolframInstitute/Genome paclet registers the converter. It is named GenomeVCF rather than VCF because the Wolfram System already owns a format of that name, and a paclet must not redefine a system format.

## Background & Context

- VCF is the Variant Call Format: meta-information lines beginning `##`, a `#CHROM` column header, and one tab-separated row per called position with the genotype of each sample.
- A plain `.vcf` file or a gzip or bgzip-compressed `.vcf.gz` file is read; the reader picks the decompressor from the extension.
- The reference build is inferred from the contig lengths in the header: GRCh37/hg19, GRCh38 or T2T-CHM13v2.0.
- A single-sample file on a human build is promoted to a <code>[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome)</code>, which carries the interpretation layer.
- The converter is the same code as <code>[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF)</code>; the format is a second door to it. There is no export: a `Genome` is a handle to a file that already exists.

## Import & Export

- `Import["file.vcf", "GenomeVCF"]` imports a VCF file, returning a lazy <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code> handle.
- `Import["file.vcf.gz", "GenomeVCF"]` reads a compressed file the same way.
- `Import["file.vcf", {"GenomeVCF", elem}]` imports the specified element.

## Import Elements

| "Data" | the lazy Genome handle (default) |
|---|---|
| "Header" | the parsed meta-information: file format, contigs, INFO and FORMAT fields, samples |
| "Samples" | the sample column names |
| "Build" | the inferred reference build |
| "Variants" | the variant rows as a Tabular, under the handle's filters |
| "VariantSummary" | counts by chromosome, filter, genotype class and imputation flag |

## Options

| "MaxVariants" | Infinity |
|---|---|
| "Chromosome" | All |
| "Region" | None |
| "PASSOnly" | True |
| "ExcludeReferenceOnly" | True |
| "MinImputationR2" | 0 |
| "Backend" | Automatic |
| "Human" | Automatic |

- These are the options of <code>[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF)</code>, and seed the handle's filter spec the same way. `"Human" -> False` keeps a plain `Genome` instead of promoting a single-sample human file.

## Examples

### Basic Examples

The examples on this page run against a small synthetic file written to a temporary file; every name, date and genotype in it is made up, and nothing on this page reaches the network.

```wl
FileNameTake[
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
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	GA	G	60	PASS	AF=0.5;R2=0.71;IMPUTED	GT	0/1
chr17	1000000	rs1000	C	G	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	A	60	PASS	TYPED	GT	0/0
chr17	1200000	rs1200	A	T	60	PASS	AF=0.22;R2=0.99;IMPUTED	GT	1/1",
        "Text"
    ]
]
```

<!-- => "genome-demo.vcf" -->

Import it as a handle. The header is parsed, the build and the sample are recorded, and no variant row has been read:

```wl
g = Import[demoFile, "GenomeVCF", "Human" -> False]
```

The build was inferred from the contig lengths, and the file has one sample:

```wl
{g["Build"], g["Samples"]}
```

<!-- => {"GRCh37/hg19", {"DEMO"}} -->

Variants materialise on demand, under the handle's filters. With the default `PASS`-only and no-reference-only filters, six of the eight rows survive:

```wl
Length[g["Variants"]]
```

<!-- => 6 -->

### Import Elements

```wl
FileNameTake[
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
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	GA	G	60	PASS	AF=0.5;R2=0.71;IMPUTED	GT	0/1
chr17	1000000	rs1000	C	G	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	A	60	PASS	TYPED	GT	0/0
chr17	1200000	rs1200	A	T	60	PASS	AF=0.22;R2=0.99;IMPUTED	GT	1/1",
        "Text"
    ]
]
```

<!-- => "genome-demo.vcf" -->

The elements available for a file:

```wl
Import[demoFile, {"GenomeVCF", "Elements"}]
```

<!-- => {"Build", "Data", "Header", "Samples", "Summary", "Variants", "VariantSummary"} -->

The "Samples" and "Build" elements read only the header:

```wl
{Import[demoFile, {"GenomeVCF", "Samples"}], Import[demoFile, {"GenomeVCF", "Build"}]}
```

<!-- => {{"DEMO"}, "GRCh37/hg19"} -->

The "Variants" element is the filtered row set as a Tabular:

```wl
Import[demoFile, {"GenomeVCF", "Variants"}, "Human" -> False]
```

### Options

```wl
FileNameTake[
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
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	GA	G	60	PASS	AF=0.5;R2=0.71;IMPUTED	GT	0/1
chr17	1000000	rs1000	C	G	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	A	60	PASS	TYPED	GT	0/0
chr17	1200000	rs1200	A	T	60	PASS	AF=0.22;R2=0.99;IMPUTED	GT	1/1",
        "Text"
    ]
]
```

<!-- => "genome-demo.vcf" -->

`"MaxVariants"` caps the rows a query materialises:

```wl
Length[Import[demoFile, {"GenomeVCF", "Variants"}, "MaxVariants" -> 2, "Human" -> False]]
```

<!-- => 2 -->

`"PASSOnly" -> False` keeps the row a caller filtered as `LowQual`:

```wl
Length[Import[demoFile, {"GenomeVCF", "Variants"}, "PASSOnly" -> False, "Human" -> False]]
```

<!-- => 7 -->

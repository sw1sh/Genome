---
Template: Symbol
Name: HumanGenomeQ
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/HumanGenomeQ
Keywords: [predicate, test, human genome, HumanGenome, type check, GenomeQ]
SeeAlso: [HumanGenome, GenomeQ, Genome, ImportVCF]
RelatedGuides: [Genome]
---

## Usage

<code>[HumanGenomeQ]()[*expr*]</code> gives [True]() if *expr* is a valid [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) value, and [False]() otherwise.

## Details & Options

- <code>[HumanGenomeQ]()[*expr*]</code> is [True]() only when *expr* is `HumanGenome[g, ann]` where `g` is a valid [Genome](paclet:WolframInstitute/Genome/ref/Genome) (see [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ)), `ann` is an [Association](), and the wrapped genome's inferred build is one of the supported human references, `"GRCh37/hg19"` or `"GRCh38"`.
- The annotation argument is tested only for being an [Association](). Its contents, and which interpretation slots are already filled, do not affect the result.
- `HumanGenomeQ` gives [True]() or [False]() for every input and never issues a message, so it is safe as a pattern test: the interpretation operators are typed on `_?HumanGenomeQ`.
- `HumanGenomeQ` is stricter than [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ). [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) is [True]() for both a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) and a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which is what lets every [Genome](paclet:WolframInstitute/Genome/ref/Genome) operator accept the wrapper, whereas `HumanGenomeQ` is [True]() only for the wrapper.
- A [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) produced by [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) promotion always satisfies `HumanGenomeQ`, and so does every genome derived from it by filter accumulation.
- Automatic promotion also requires a single sample, so a multi-sample human VCF gives [False]() unless it is imported with `"Human" -> True`.
- The predicate reads only the value in hand: it never opens the file, never consults an external reference, and never triggers an interpretation, so it costs nothing to call.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which displays as a purple-accented summary box, and the `.tbi` index beside the file selects the tabix backend:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The promoted genome satisfies the predicate:

```wl
HumanGenomeQ[subject]
```

<!-- => True -->

The same file imported with `"Human" -> False` stays a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), which displays with the teal accent:

```wl
g = ImportVCF["data/subject_genome.vcf.gz", "Human" -> False]
```

A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) does not satisfy the predicate:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

---

Neither does an arbitrary expression:

```wl
HumanGenomeQ["not a genome"]
```

<!-- => False -->

---

A small synthetic single-sample VCF, ten records on chromosomes 1 and 17 under GRCh37 contig lengths, written to a temporary file:

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

Promotion reads the sample count and the inferred build, not the size of the file, so the ten-record callset promotes the same way:

```wl
hg = ImportVCF[demoFile]
```

It satisfies the predicate the same way:

```wl
HumanGenomeQ[hg]
```

<!-- => True -->

## Scope

A promoted handle on the demo file:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

A filtered genome is still a `HumanGenome`, since filter accumulation rewraps its result:

```wl
HumanGenomeQ[hg["Chromosome", "chr17"]]
```

<!-- => True -->

Wrappers can also be built by hand, around the plain genome the same file gives without promotion:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

The annotation [Association]() is tested only for its head, so an empty one still passes:

```wl
HumanGenomeQ[HumanGenome[g, <||>]]
```

<!-- => True -->

The build is re-derived from the wrapped genome rather than taken on trust. Re-stamping the payload with a build outside the supported pair leaves a valid [Genome](paclet:WolframInstitute/Genome/ref/Genome):

```wl
t2t = Genome[<|First[g], "Build" -> "T2T-CHM13v2.0"|>]
```

Wrapping it does not make it a `HumanGenome`:

```wl
HumanGenomeQ[HumanGenome[t2t, <||>]]
```

<!-- => False -->

---

The wrapped value must itself be a valid [Genome](paclet:WolframInstitute/Genome/ref/Genome); a payload missing the required keys gives [False]():

```wl
HumanGenomeQ[HumanGenome[Genome[<|"Path" -> "x.vcf"|>], <||>]]
```

<!-- => False -->

## Properties and Relations

The promoted genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ) is [True]() for the wrapper too; that is what makes a `HumanGenome` usable everywhere a [Genome](paclet:WolframInstitute/Genome/ref/Genome) is:

```wl
GenomeQ[hg]
```

<!-- => True -->

`HumanGenomeQ` is the stricter of the two tests: across the wrapper, the plain genome it wraps and two values that are neither, everything it accepts also satisfies [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ):

```wl
AllTrue[{hg, First[hg], 42, "not a genome"}, Implies[HumanGenomeQ[#], GenomeQ[#]] &]
```

<!-- => True -->

Because it never issues a message, `HumanGenomeQ` works directly as a pattern test, which is how the interpretation operators are typed:

```wl
MatchQ[hg, _?HumanGenomeQ]
```

<!-- => True -->

## Possible Issues

The predicate reports how the value was built, not what the file holds. Importing the demo file without promotion gives a plain genome:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

Its build is one of the two the wrapper supports:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

The predicate still gives [False](), because the value it was handed is not a wrapper:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

---

No input issues a message, so an unusual argument is safe inside a pattern test:

```wl
HumanGenomeQ[Missing["NotAvailable"]]
```

<!-- => False -->

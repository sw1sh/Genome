---
Template: Symbol
Name: GenomeQ
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenomeQ
Keywords: [genome, predicate, test, type check, GenomeQ]
SeeAlso: [Genome, ImportVCF, ImportVCFHeader]
RelatedGuides: [Genome]
---

## Usage

<code>[GenomeQ]()[*expr*]</code> gives [True]() if *expr* is a valid <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code> object, and [False]() otherwise.

## Details & Options

- `GenomeQ` gives [True]() when *expr* is `Genome[a]` for an [Association]() `a` that carries every required payload key: `"Path"`, `"Header"`, `"Samples"`, `"Build"`, `"Backend"`, `"Filters"`, and `"VariantCountCache"`.
- A <code>[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome)</code> wrapping such a payload also gives [True](). `GenomeQ` looks through the wrapper at the inner [Genome](paclet:WolframInstitute/Genome/ref/Genome), so every operator written against the pattern `_?GenomeQ` accepts a `HumanGenome` unchanged.
- Any other expression gives [False](), including a `Genome` whose payload is missing a required key.
- The test is total: every expression gives [True]() or [False](). No message is issued, and no argument returns unevaluated.
- The test is structural. It inspects the payload keys, reads no variant rows, opens no file, and asserts nothing about the path on disk.
- `GenomeQ` is the same check that guards the [Genome](paclet:WolframInstitute/Genome/ref/Genome) UpValues for [Length](), [Normal](), [Dimensions]() and the [MakeBoxes]() display, so a value that passes it supports the full query surface.
- Filter accumulation preserves the payload keys, so a filtered handle derived from a valid `Genome` is itself valid.
- A [Genome](paclet:WolframInstitute/Genome/ref/Genome) from [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) always satisfies `GenomeQ`.

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. Imported with `"Human" -> False` it is a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) rather than the human wrapper, displayed as a summary box naming the file, the build and the sample count; the `.tbi` index beside the file selects the tabix backend:

```wl
g = ImportVCF["data/subject_genome.vcf.gz", "Human" -> False]
```

The imported handle carries every required payload key, so it passes:

```wl
GenomeQ[g]
```

<!-- => True -->

With the default `"Human" -> Automatic`, a single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which brings its own summary box:

```wl
hg = ImportVCF["data/subject_genome.vcf.gz"]
```

`GenomeQ` looks through the wrapper to the inner payload, so the promoted handle passes as well:

```wl
GenomeQ[hg]
```

<!-- => True -->

---

An expression that is not a `Genome` at all gives [False]():

```wl
GenomeQ[42]
```

<!-- => False -->

---

So does a `Genome` whose payload is missing the required keys:

```wl
GenomeQ[Genome[<|"Path" -> "x.vcf"|>]]
```

<!-- => False -->

---

A small synthetic VCF: ten rows across two chromosomes, one sample column named for the public reference individual NA12878, and a GRCh37 contig header. Every genotype in it is made up. The file is written to a temporary directory:

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

Import it, capping the read at five variants and keeping the generic handle rather than the human wrapper:

```wl
g = ImportVCF[demoFile, "Human" -> False, "MaxVariants" -> 5]
```

A filter such as the cap leaves the payload keys in place, so the capped handle passes too:

```wl
GenomeQ[g]
```

<!-- => True -->

## Scope

With the default `"Human" -> Automatic`, a single-sample human build is promoted to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which brings its own summary box:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

`GenomeQ` looks through the wrapper to the inner payload, so the promoted handle passes as well:

```wl
GenomeQ[hg]
```

<!-- => True -->

---

The wrapper is looked through in the failing direction too: a `HumanGenome` around an incomplete payload gives [False]():

```wl
GenomeQ[HumanGenome[Genome[<|"Path" -> "x.vcf"|>], <||>]]
```

<!-- => False -->

---

A generic handle, its read capped at five variants:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "Human" -> False, "MaxVariants" -> 5
]
```

Each filter method gives back a new `Genome` with the same payload keys, so a chained handle is still valid:

```wl
GenomeQ[g["Chromosome", "chr17"]["MinR2", 0.8]]
```

<!-- => True -->

---

[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) gives <code>[$Failed]()</code> when the header cannot be read. That value is not a `Genome`, and `GenomeQ` reports it as such without issuing a message:

```wl
GenomeQ[$Failed]
```

<!-- => False -->

## Properties and Relations

A generic handle over the first five variants:

```wl
g = ImportVCF[
    FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
    "Human" -> False, "MaxVariants" -> 5
]
```

`GenomeQ` is exactly the payload-key test, so checking the keys by hand agrees with it:

```wl
AllTrue[{"Path", "Header", "Samples", "Build", "Backend", "Filters", "VariantCountCache"}, KeyExistsQ[First[g], #] &]
```

<!-- => True -->

The [Genome](paclet:WolframInstitute/Genome/ref/Genome) UpValues are guarded by the same test, so a handle that passes supports [Length](), which gives the variant count of the filtered view:

```wl
Length[g]
```

<!-- => 5 -->

A payload that fails the test matches no UpValue, so [Length]() falls back to its built-in meaning and counts the arguments of the expression instead of its variants:

```wl
Length[Genome[<|"Path" -> "x.vcf"|>]]
```

<!-- => 1 -->

[HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ) is the narrower test: it additionally demands the human wrapper and a human reference build, so the generic handle fails it where `GenomeQ` accepts it:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

## Possible Issues

The keys are the whole test, so a hand-built payload passes even when its `"Path"` names no file on disk:

```wl
GenomeQ[Genome[<|"Path" -> "nowhere.vcf", "Header" -> <||>, "Samples" -> {}, "Build" -> "Unknown", "Backend" -> "AwkStream", "Filters" -> {}, "VariantCountCache" -> Missing["NotComputed"]|>]]
```

<!-- => True -->

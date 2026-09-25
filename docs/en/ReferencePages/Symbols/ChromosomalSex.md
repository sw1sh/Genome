---
Template: Symbol
Name: ChromosomalSex
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ChromosomalSex
Keywords: [sex, chromosomal sex, karyotype, XY, XX, sex chromosomes, chrX heterozygosity, chrY coverage, pseudoautosomal, HumanGenome, GRCh37, subject]
SeeAlso: [HumanGenome, ImportVCF, AncestryEstimate, HaplogroupCall, Genome]
RelatedGuides: [Genome]
---

## Usage

<code>[ChromosomalSex]()[*hg*]</code> infers the genetic (chromosomal) sex of a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* from its sex chromosomes, giving an [Association]() with the karyotype call and the two statistics behind it.

## Details & Options

- `ChromosomalSex` is the one [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method that gives an [Association]() rather than a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome): the karyotype call has no external reference to thread through the annotation slots.
- The [Association]() has the keys `"KaryotypeCall"` (`"XY"`, `"XX"`, or `"Undetermined"`), `"ChrXHetRate"` (the heterozygosity rate over the sampled chrX calls), `"ChrXCallsSampled"` (how many PASS biallelic SNV calls the rate is over), `"ChrYVariantCount"` (the number of non-reference PASS chrY calls in the sampled window), `"ChrXRegionSampled"`, `"ChrYRegionSampled"`, and `"Method"`.
- Two robust statistics drive the karyotype call. A male is hemizygous across the non-pseudoautosomal X, so nearly every called biallelic SNV there is homozygous (a low heterozygosity rate), and the male-specific chrY carries many variant calls. A female has abundant heterozygous chrX calls (a high rate) and essentially no chrY calls.
- The chrX statistic is computed over a non-pseudoautosomal GRCh37 window (`chrX:2700000-10000000`, wholly outside PAR1 which ends at 2699520 and PAR2 which begins at 154931044), counting only PASS rows with a single-base REF and ALT and a diploid, fully-called genotype. The chrY statistic counts non-reference PASS calls in a male-specific window (`chrY:2700000-10000000`).
- The window names follow the contigs the subject file declares, so a genome whose chromosomes are named `X` and `Y` rather than `chrX` and `chrY` is sampled at the same coordinates under those names.
- The karyotype call is `"XY"` when the chrY count is at least 50 and the chrX heterozygosity rate is below 0.15; `"XX"` when the chrY count is below 50 and the rate is at least 0.15; and `"Undetermined"` otherwise — fewer than 100 sampled chrX calls, or an inconsistent combination such as a sex-chromosome aneuploidy.
- A subject file that declares no sex chromosomes at all samples two empty windows: `"ChrXCallsSampled"` is 0, `"ChrXHetRate"` is [Missing]()`["NoData"]`, and the karyotype call is `"Undetermined"` under the same rule.
- Both windows are read through the tabix index, so the whole genome is never scanned. `ChromosomalSex` requires the `tabix` binary on `PATH` and a `.tbi` index beside the subject VCF; without them it issues `ChromosomalSex::noindex` and gives <code>[$Failed]()</code>.
- The two windows are fixed GRCh37 coordinates. On a GRCh38 genome the chrX window overlaps the start of PAR1, which ends at 2781479 on that build, so part of the sampled region is pseudoautosomal and the heterozygosity rate is diluted.
- The result is cached in a per-subject sidecar `<subject>/interpretations/sex.wxf` beside the subject file, which also serves every later inference for that subject without reading the sex chromosomes again. When the sidecar is present, a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) for that subject hydrates `hg["Subject", "Sex"]` with the karyotype call (otherwise `Subject["Sex"]` is [Automatic]()).
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) returns unevaluated; a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) carries no sex-chromosome interpretation.

## Basic Examples

The examples run on a small synthetic callset: one sample column, ten data rows across chr1 and chr17, and the GRCh37 contig lengths the build inference reads. The callset is written to a temporary file:

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

`ChromosomalSex` samples its two windows through the tabix index, so the subject file has to be bgzip-compressed and indexed first:

```wl
RunProcess[{"sh", "-c",
        "mkdir -p \"$1\" && bgzip -f -c \"$2\" > \"$1/genome-demo.vcf.gz\" && tabix -f -p vcf \"$1/genome-demo.vcf.gz\"",
        "sh", demoDir = FileNameJoin[{$TemporaryDirectory, "genome-demo-sex"}], demoFile},
    "ExitCode"]
```

<!-- => 0 -->

A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), the input every interpretation method takes:

```wl
hg = ImportVCF[FileNameJoin[{demoDir, "genome-demo.vcf.gz"}]]
```

Infer the chromosomal sex of that genome. The demo callset declares chr1 and chr17 and nothing else, so both sampling windows come back empty and there is no evidence for either karyotype:

```wl
ChromosomalSex[hg]
```

<!-- => <|"KaryotypeCall" -> "Undetermined", "ChrXHetRate" -> Missing["NoData"], "ChrXCallsSampled" -> 0, "ChrYVariantCount" -> 0, "ChrXRegionSampled" -> "chrX:2700000-10000000", "ChrYRegionSampled" -> "chrY:2700000-10000000", "Method" -> "ChrYCoverage+ChrXHeterozygosity"|> -->

With nothing sampled, the rule gives `"Undetermined"`, the honest answer for a file with no sex chromosomes in it. The karyotype call is the first key of the result, and the one most callers want on its own:

```wl
ChromosomalSex[hg]["KaryotypeCall"]
```

<!-- => "Undetermined" -->

Once inferred, the karyotype call is surfaced through the `"Subject"` slot of a freshly imported genome for the same subject, read from the sidecar rather than from the sex chromosomes:

```wl
ImportVCF[FileNameJoin[{demoDir, "genome-demo.vcf.gz"}]]["Subject", "Sex"]
```

<!-- => "Undetermined" -->

---

A whole-genome callset carries thousands of chrX calls in the same window, and the two statistics then separate `"XX"` from `"XY"` cleanly. The anonymized 5.7-million-variant GRCh37 callset the paclet was developed against is kept beside the reference data as `data/subject_genome.vcf.gz`:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Both statistics sit at the ends of their ranges — not one heterozygous call among 9143 non-pseudoautosomal chrX sites, and 606 variant calls in the male-specific chrY window — and together they make the `"XY"` call:

```wl
ChromosomalSex[subject]
```

<!-- => <|"KaryotypeCall" -> "XY", "ChrXHetRate" -> 0., "ChrXCallsSampled" -> 9143, "ChrYVariantCount" -> 606, "ChrXRegionSampled" -> "chrX:2700000-10000000", "ChrYRegionSampled" -> "chrY:2700000-10000000", "Method" -> "ChrYCoverage+ChrXHeterozygosity"|> -->

A fresh import of the same subject reads its `"Subject"` slot from the sidecar the inference wrote, so the call is available without touching the sex chromosomes again:

```wl
ImportVCF["data/subject_genome.vcf.gz"]["Subject", "Sex"]
```

<!-- => "XY" -->

## Scope

A handle on the indexed genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo-sex", "genome-demo.vcf.gz"}]]
```

The keys of the result carry the karyotype call, the evidence behind it, and the windows the evidence came from:

```wl
ChromosomalSex[hg]
```

The first statistic is the heterozygosity rate over the sampled non-pseudoautosomal chrX calls. A rate well above 0.15 is the female signal and a rate near zero the male one; with no calls to average over there is no rate at all:

```wl
ChromosomalSex[hg]["ChrXHetRate"]
```

<!-- => Missing["NoData"] -->

The rate is only as good as the number of calls behind it, which is reported beside it; fewer than 100 sampled calls gives `"Undetermined"` whatever the rate:

```wl
ChromosomalSex[hg]["ChrXCallsSampled"]
```

<!-- => 0 -->

The second statistic counts non-reference calls in the male-specific chrY window, which a female genome leaves essentially empty and a genome with no chrY leaves entirely empty:

```wl
ChromosomalSex[hg]["ChrYVariantCount"]
```

<!-- => 0 -->

The sampled windows travel with the result, so the coordinates a statistic was computed over are never in doubt, even when nothing was found there:

```wl
ChromosomalSex[hg]["ChrXRegionSampled"]
```

<!-- => "chrX:2700000-10000000" -->

`"Method"` names the two statistics that produced the karyotype call:

```wl
ChromosomalSex[hg]["Method"]
```

<!-- => "ChrYCoverage+ChrXHeterozygosity" -->

The two windows are looked up among the contigs the subject file declares, and the demo callset declares no sex chromosomes:

```wl
hg["Header"]["Contigs"]
```

---

A genome imported with `"Human" -> False` stays a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), the handle without the interpretation layer:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

A plain genome carries no sex chromosomes to interpret, so it is outside the scope of `ChromosomalSex` and the call comes back unevaluated, the operator still wrapped around its argument:

```wl
ChromosomalSex[g]
```

## Properties and Relations

The indexed demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo-sex", "genome-demo.vcf.gz"}]]
```

`ChromosomalSex` gives an [Association](), where [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) and [HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall) each give a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with an annotation slot filled:

```wl
ChromosomalSex[hg]
```

<!-- => <|"KaryotypeCall" -> "Undetermined", "ChrXHetRate" -> Missing["NoData"], "ChrXCallsSampled" -> 0, "ChrYVariantCount" -> 0, "ChrXRegionSampled" -> "chrX:2700000-10000000", "ChrYRegionSampled" -> "chrY:2700000-10000000", "Method" -> "ChrYCoverage+ChrXHeterozygosity"|> -->

Whatever the genome, the karyotype call is one of the three documented strings:

```wl
MemberQ[{"XX", "XY", "Undetermined"}, ChromosomalSex[hg]["KaryotypeCall"]]
```

<!-- => True -->

The result is persisted in the per-subject sidecar, so a second inference reproduces the first without touching the sex chromosomes again:

```wl
ChromosomalSex[hg] === ChromosomalSex[hg]
```

<!-- => True -->

## Possible Issues

A handle on the indexed demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo-sex", "genome-demo.vcf.gz"}]]
```

The sampling windows are GRCh37 coordinates, so read the build before trusting the heterozygosity rate; on GRCh38 the chrX window reaches into PAR1 and the rate is diluted by pseudoautosomal heterozygosity:

```wl
hg["Build"]
```

<!-- => "GRCh37/hg19" -->

The sex chromosomes are read by region, so the subject VCF needs a `.tbi` index beside it. A freshly copied or freshly written file often lacks one:

```wl
FileExistsQ[hg["Path"] <> ".tbi"]
```

<!-- => True -->

---

Without the index, or without `tabix` on `PATH`, no window can be read and the inference stops before it starts:

```wl
ChromosomalSex::noindex
```

<!-- => the text of the message ChromosomalSex issues, after which it gives $Failed -->

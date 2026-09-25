---
Template: Symbol
Name: AlphaMissenseScores
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/AlphaMissenseScores
Keywords: [AlphaMissense, missense, pathogenicity prediction, variant effect, protein change, HumanGenome, GRCh37, hg19, deep learning, amino acid, classification]
SeeAlso: [HumanGenome, ClinVarHits, ImportVCF, Genome, GenotypeLookup, VariantSummary]
RelatedGuides: [Genome]
---

## Usage

<code>[AlphaMissenseScores]()[*hg*]</code> scores the missense variants the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* carries against the AlphaMissense predictions, giving a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"AlphaMissenseScores"` slot holds a [Tabular]() of the scored variants.

<code>[AlphaMissenseScores]()[*hg*, *opts*]</code> scores with the options *opts*.

## Details & Options

- `AlphaMissenseScores` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"AlphaMissenseScores"` annotation slot populated and `References["AlphaMissenseRelease"]` set. The wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome), every other slot, and *hg* itself are left untouched.
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) matches no definition, so `AlphaMissenseScores` returns unevaluated. A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) is such an argument.
- AlphaMissense is a deep-learning model that predicts, for every possible missense substitution in the human proteome, a pathogenicity score in the range 0 to 1 and a class label. The score thresholds are `likely_benign` below 0.34, `ambiguous` between 0.34 and 0.564, and `likely_pathogenic` above 0.564.
- The data source is the AlphaMissense hg19 (GRCh37) prediction table published by the model's authors ([AlphaMissense_hg19.tsv.gz](https://storage.googleapis.com/dm_alphamissense/AlphaMissense_hg19.tsv.gz)). The Wolfram Data Repository resource `ResourceData["Alpha Missense"]` is keyed to GRCh38/hg38; because the personal genome here is GRCh37, `AlphaMissenseScores` joins against the authors' own hg19 table so the join key `(CHROM, POS, REF, ALT)` matches the subject's build directly, with no coordinate liftover and therefore no unmapped-position loss.
- On first use the hg19 table is downloaded (about 600 MB, one time) and cached under `data/references/`; later scoring reuses it. An [AlphaMissenseScores::download]() message announces the fetch, and [AlphaMissenseScores::noref]() is issued if it fails or `curl` is not on the path.
- The join is a bounded two-pass stream: the first pass scans the subject VCF once and collects the `(chr, pos, ref, alt)` keys of the biallelic single-nucleotide variants the subject carries (a non-reference genotype); the second pass streams the AlphaMissense table once, keeping only the rows whose key is in that set. Neither large table is materialized in the kernel, and only the carried variants that AlphaMissense scores (its table enumerates the missense space, so an in-table match is itself the missense filter) reach the result.
- The [Tabular]() in the slot has the columns `VariantID` (the canonical `chr-pos-ref-alt` string), `RsID`, `Gene`, `Transcript`, `ProteinChange` (the amino-acid substitution in one-letter notation, for example `A123V`), `Genotype` (the subject's `GT`), `Zygosity` (`"Heterozygous"` or `"Homozygous"`), `AMScore` (the pathogenicity value in 0 to 1), and `AMClass` (`"likely_benign"`, `"ambiguous"`, or `"likely_pathogenic"`). Rows are sorted by `AMScore` descending, most pathogenic first. The hg19 table carries `uniprot_id` and `transcript_id` but no gene symbol, so `Gene` is [Missing]().
- The join is cached on disk. A per-subject sidecar `data/<subject>/interpretations/alphamissense-scores.tabular` (Parquet) plus its release marker persists the scored table across kernel sessions and hydrates a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whenever the stored release still matches the prepared reference. The sidecar holds the full, unfiltered join, so `"MinScore"` is re-applied to the hydrated table and a new threshold never forces a re-scan.
- A high `AMScore` is a computational molecular-effect prediction, not a clinical diagnosis. Most high-scoring variants a healthy person carries are heterozygous or in genes with no consequence for a carrier; treat the scores as a prioritization signal, not a verdict.

The following options can be given:

| | | |
|--------|---------------|-|
| `"MinScore"` | `0` | keep only rows whose `AMScore` is at least this value (for example `0.564` to keep only `likely_pathogenic` predictions) |
| `"Reference"` | [Automatic]() | [Automatic]() downloads and caches the AlphaMissense hg19 table under `data/references/`; a directory path uses an `AlphaMissense_hg19.tsv.gz` already present there |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `AlphaMissenseScores` scores:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Scoring the missense variants the genome carries gives back a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"AlphaMissenseScores"` slot is filled. The first call downloads and caches the hg19 prediction table, and later calls for the same subject are served from a per-subject sidecar:

```wl
am = AlphaMissenseScores[subject]
```

The slot holds a [Tabular]() with one row per scored variant, sorted by `AMScore` descending, and a fixed column set - `VariantID`, `RsID`, `Gene`, `Transcript`, `ProteinChange`, `Genotype`, `Zygosity`, `AMScore` and `AMClass`; this subject carries 9744 scored missense variants. The AlphaMissense release they were scored against is recorded in the `References` sub-Association, a marker of the form `AlphaMissense-hg19-<byte count of the table>`:

```wl
am["References", "AlphaMissenseRelease"]
```

<!-- => "AlphaMissense-hg19-622293310" -->

The scored genome is a new value and the one that was scored is left alone, so its own slot still reads [Missing]()`["NotComputed"]`:

```wl
subject["AlphaMissenseScores"]
```

<!-- => Missing["NotComputed"] -->

---

Two options control the scoring: a lower bound on the score column, and where the prediction table comes from:

```wl
Options[AlphaMissenseScores]
```

<!-- => {"MinScore" -> 0, "Reference" -> Automatic} -->

## Scope

A demonstration VCF of ten single-sample records over chromosomes 1 and 17, small enough that every row can be accounted for, written to a temporary file:

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

Imported, it autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome):

```wl
hg = ImportVCF[demoFile]
```

AlphaMissense enumerates the missense space of the proteome, so its table only ever matches a biallelic single-nucleotide substitution: an indel has no entry, and neither has a position with no alternate allele. Six of the demo genome's eight rows are single-nucleotide substitutions whose `(CHROM, POS, REF, ALT)` key could match a prediction row at all; the deletion at `rs300` and the insertion at `rs1300` cannot:

```wl
Select[Normal[hg["Variants"]], StringLength[#REF] == 1 && StringLength[First[#ALT]] == 1 &][[All, "ID"]]
```

<!-- => {"rs100", "rs150", "rs400", "rs1000", "rs1100", "rs1200"} -->

Carriage narrows that set again: the first pass keeps a key only when the subject's genotype is non-reference, and records `"Heterozygous"` (`het`) or `"Homozygous"` (`homAlt`) for the `Zygosity` column. One of those six substitutions is a homozygous-reference call, so it contributes no key:

```wl
VariantSummary[hg] // Dataset
```

The whole-genome callset, whose scoring is served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Its scored genome:

```wl
am = AlphaMissenseScores[subject]
```

The predictions partition into the three AlphaMissense classes - `"likely_benign"` below 0.34, `"ambiguous"` up to 0.564, `"likely_pathogenic"` above it - and in any healthy genome the great majority of scored variants fall in the benign class:

```wl
Counts[Lookup[Normal[am["AlphaMissenseScores"]], "AMClass"]]
```

Every score is a probability-like value in the range 0 to 1, and the rows come back sorted by that column descending, so the reversed column is in ascending order and `OrderedQ` of it is [True]():

```wl
OrderedQ[Reverse[Lookup[Normal[am["AlphaMissenseScores"]], "AMScore"]]]
```

<!-- => True -->

The hg19 prediction table names a transcript but no gene symbol, so the `Gene` column is [Missing]() throughout:

```wl
DeleteDuplicates[Lookup[Normal[am["AlphaMissenseScores"]], "Gene"]]
```

<!-- => {Missing["NotAvailable"]} -->

---

Scoring needs the human interpretation layer, so `"Human" -> False` gives a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) instead:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) matches no definition, so the call comes back unevaluated - the genome is still sitting inside an `AlphaMissenseScores` expression rather than scored:

```wl
AlphaMissenseScores[g]
```

---

The reference is fetched with `curl`. If it is not on the path, or the download fails, the scoring gives `$Failed` after issuing [AlphaMissenseScores::noref]():

```wl
AlphaMissenseScores::noref
```

<!-- => "AlphaMissenseScores could not obtain the AlphaMissense hg19 reference; the download failed or curl is not on PATH.  Ensure curl is on PATH and the network is reachable." -->

## Options

### "MinScore"

`"MinScore"` is a lower bound on the score column, and its default keeps every scored row:

```wl
Lookup[Options[AlphaMissenseScores], "MinScore"]
```

<!-- => 0 -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Scoring with the `likely_pathogenic` threshold instead keeps only the high-pathogenicity tail:

```wl
am = AlphaMissenseScores[subject, "MinScore" -> 0.564]
```

The full join is cached on disk, so raising the threshold on an already-scored genome re-filters the cached table instead of repeating the scan:

```wl
AlphaMissenseScores[am, "MinScore" -> 0.9]
```

### "Reference"

By default the AlphaMissense hg19 table is downloaded and cached under `data/references/`:

```wl
Lookup[Options[AlphaMissenseScores], "Reference"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Pointing `"Reference"` at a directory that already holds `AlphaMissense_hg19.tsv.gz` reuses it and skips the download:

```wl
AlphaMissenseScores[subject, "Reference" -> "data/references"]
```

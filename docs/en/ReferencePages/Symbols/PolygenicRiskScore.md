---
Template: Symbol
Name: PolygenicRiskScore
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/PolygenicRiskScore
Keywords: [polygenic risk score, PRS, PGS Catalog, scoring file, effect allele, dosage, effect weight, percentile, normal approximation, Hardy-Weinberg, strand, HumanGenome, GRCh37, trait]
SeeAlso: [HumanGenome, ClinVarHits, AlphaMissenseScores, TraitAssociations, ImportVCF, Genome]
RelatedGuides: [Genome]
---

## Usage

<code>[PolygenicRiskScore]()[*hg*, *trait*]</code> scores the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* against the published PGS Catalog scoring file for *trait*, giving a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"PRS"` slot records the score for that trait.

<code>[PolygenicRiskScore]()[*hg*, *trait*, *opts*]</code> scores with the options *opts*.

## Details & Options

- `PolygenicRiskScore` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"PRS"` annotation slot updated and `References["PGSCatalogVersion"]` set. The wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome), every other slot, and *hg* itself are left untouched.
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) matches no definition, so `PolygenicRiskScore` returns unevaluated. A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) is such an argument.
- A polygenic (risk) score is the weighted sum, over many variants, of the number of copies of each variant's effect allele the subject carries times a published per-variant weight. It is a single number that estimates the subject's genetic liability for a trait relative to the population the score was derived in.
- The `"PRS"` slot is an [Association]() keyed by PGS Catalog ID, so scores for several traits accumulate. `hg["PRS"]` reads the whole map; `hg["PRS", pgsid]` reads one score's entry. Each entry is an [Association]() with the keys `"Score"` (the raw weighted sum), `"Percentile"` (the population percentile in 0 to 1, or [Missing]() when no reference frequency is available), `"PGSID"`, `"Trait"` (from the scoring file), `"NVariantsUsed"` and `"NVariantsExpected"` (coverage), and `"Method"` (the percentile method).
- The second argument resolves a trait three ways: a raw PGS Catalog ID (`"PGS000065"`, used directly), a human trait name looked up in the project-maintained `$PRSTraitMap`, or an EFO / MONDO trait id. `$PRSTraitMap` curates well-known, moderate-size published scores that harmonize to GRCh37: `"LDL cholesterol"`, `"HDL cholesterol"`, `"Triglycerides"`, `"Total cholesterol"`, `"Type 2 diabetes"`, `"BMI"` / `"Body mass index"`, `"Coronary artery disease"`, `"Height"`, `"Breast cancer"`, `"Prostate cancer"`, `"Alzheimer's disease"`, and `"Atrial fibrillation"`. A trait name that is neither a PGS ID nor in the map issues [PolygenicRiskScore::unknownTrait]() and gives <code>[$Failed]()</code>.
- The scoring weights are the PGS Catalog harmonized GRCh37 scoring file for the score ([pgscatalog.org](https://www.pgscatalog.org/)), fetched from the FTP path `.../scores/PGS######/ScoringFiles/Harmonized/PGS######_hmPOS_GRCh37.txt.gz`. On first use the file is downloaded (one time; the curated scores range from tens to a few hundred thousand variants) and cached under `data/references/pgs/`. A [PolygenicRiskScore::download]() message announces the fetch, and [PolygenicRiskScore::noref]() is issued if it fails or `curl` is not on the path.
- The subject's genotype at each scoring variant's harmonized position (`hm_chr`, `hm_pos`) is read once through the tabix index (the scoring positions are written to a regions file and passed to `bcftools view -R`), so the multi-gigabyte source is never scanned end to end. GRCh37 PGS files name contigs `1`..`22`, `X`, `Y`; they are renamed to the subject's `chr`-prefixed form for the join. For each variant the effect-allele dosage (0, 1, or 2) is counted from the subject's `GT`, including homozygous-reference calls (dosage 0 or 2). The raw score is the sum over the used variants of dosage times `effect_weight`.
- The subject's `REF`/`ALT` are matched to the scoring file's `effect_allele`/`other_allele` directly, and, failing that, under reverse-complement, so a score reported on the opposite strand still matches. Strand-ambiguous palindromic SNPs (A/T and C/G, where reverse-complement cannot resolve the strand) are skipped. Multiallelic sites, indels, allele mismatches, and variants the subject has no call for are skipped; every skipped scoring variant still counts toward `NVariantsExpected` but not `NVariantsUsed`.
- A raw PRS is meaningless without a reference distribution, so the percentile is the analytic normal approximation of the population score. Under Hardy-Weinberg equilibrium and an independent-variant assumption the population score has mean `Sum[2 * EAF * w]` and variance `Sum[2 * EAF * (1 - EAF) * w^2]`, and the subject percentile is `CDF[NormalDistribution[mean, Sqrt[variance]], subjectScore]`. The effect-allele frequency (EAF) is the scoring file's `allelefrequency_effect` column when present (matched to the score's derivation population), otherwise the subject's own imputation-panel `INFO/AF` (used only on imputed / typed rows, where it is a genuine panel frequency). The mean and variance are summed over the used variants that carry a frequency, so `Method` reports `"NormalApproximation:PGSAlleleFrequency"` or `"NormalApproximation:SubjectPanelAF"`. When no frequency is available the raw `Score` is still reported and `Percentile` is `Missing["NoReference"]` with `Method` `"None"` - no percentile is fabricated.
- The normal approximation treats variants as independent and in Hardy-Weinberg equilibrium; real variants are in linkage disequilibrium, so the percentile is an approximation of the true population rank rather than an exact quantile. It is most accurate for scores with an explicit effect-allele frequency and for a subject whose ancestry matches the score's derivation cohort.
- Results are cached twice. The in-memory slot serves an immediate cache hit when the requested PGS ID is already scored and the stored `References["PGSCatalogVersion"]` matches, in which case *hg* comes back unchanged. A per-subject sidecar `data/<subject>/interpretations/prs.wxf` (a WXF of the whole PRS map) plus its release marker persists the scores across kernel sessions; scoring a new trait later hydrates the map from the sidecar and appends the new score. An entry already in the map or the sidecar is used as it stands, so `"MaxVariants"` takes effect only the first time a given score is computed.
- A PRS is a population-relative statistical estimate, not a diagnosis. Most published scores were derived in European-ancestry cohorts and are materially less accurate applied off that ancestry. Imputed genotypes add noise, especially at low-imputation-quality (low-R2) sites. A high percentile means an above-average genetic contribution to a trait in the reference population, not a determined outcome; environment, family history, and non-genetic factors are not captured.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Reference"` | [Automatic]() | [Automatic]() downloads and caches the harmonized GRCh37 scoring file under `data/references/pgs/`; a directory path uses a `PGS######_hmPOS_GRCh37.txt.gz` already present there |
| `"MaxVariants"` | [Automatic]() | [Automatic]() scores every variant in the file; an integer caps the number of scoring variants (for very large genome-wide scores), issuing [PolygenicRiskScore::truncated]() when it truncates |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `PolygenicRiskScore` scores:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Scoring for a trait resolves it to a published PGS Catalog score - `"height"` to `PGS000297`, published for `"Height"` - and on first use downloads that score's harmonized scoring file, in the GRCh37 form that matches the callset's build; later scorings for the same subject are served from a per-subject sidecar. The result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"PRS"` slot records the score, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot untouched:

```wl
prs = PolygenicRiskScore[subject, "height"]
```

The slot is keyed by PGS Catalog ID rather than by trait name, and each entry is an [Association]() with a fixed key set. `"Score"` is the raw weighted sum over the variants used; `"Percentile"` is the population rank from the normal approximation, 0.69 for this subject, above two thirds of the reference population; `"PGSID"` and `"Trait"` say which score was used and what it was published for; `"NVariantsUsed"` and `"NVariantsExpected"` are the coverage, 1566 of the score's 3280 variants usable in the callset; and `"Method"` records where the reference frequencies behind the percentile came from, the subject's own imputation panel for this score:

```wl
prs["PRS", "PGS000297"]
```

<!-- => the entry as an Association: a Score near 24.8, a Percentile near 0.69, PGSID "PGS000297", Trait "Height", NVariantsUsed 1566, NVariantsExpected 3280, Method "NormalApproximation:SubjectPanelAF" -->

The PGS Catalog release the score was taken under is recorded beside it, in the `References` sub-[Association]():

```wl
prs["References", "PGSCatalogVersion"]
```

<!-- => "PGSCatalog-2026-06-17" -->

The scored genome is a new value and the one that was scored is left alone, so its own slot still reads [Missing]()`["NotComputed"]`:

```wl
subject["PRS"]
```

<!-- => Missing["NotComputed"] -->

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

Scoring an already-scored genome for a second trait appends to the map rather than replacing it. A first scoring, for LDL cholesterol, files its entry under `"PGS000065"`:

```wl
#| eval: false
prs = PolygenicRiskScore[hg, "LDL cholesterol"]
```

Threading that result into a second scoring, for type 2 diabetes, leaves both PGS Catalog IDs in the slot, in the order they were scored:

```wl
#| eval: false
prs2 = PolygenicRiskScore[prs, "Type 2 diabetes"]
```

Both entries are present, `"PGS000065"` and `"PGS000036"`:

```wl
#| eval: false
prs2["PRS"]
```

When no effect-allele frequency is available for any used variant - the harmonized
scoring file has no `allelefrequency_effect` column and the subject's rows at those
positions carry no usable panel `INFO/AF` - the raw `"Score"` is still reported, but
`"Percentile"` comes back as [Missing]()`["NoReference"]` and `"Method"` as `"None"`
rather than a fabricated rank:

```wl
#| eval: false
PolygenicRiskScore[hg, "PGS003419"]["PRS", "PGS003419"][[{"Percentile", "Method"}]]
```

---

The whole-genome callset, whose scoring is served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

A raw PGS Catalog ID is scored directly, without a trait-name mapping:

```wl
byID = PolygenicRiskScore[subject, "PGS000297"]
```

The entry then carries the trait the scoring file itself names, `"Height"` for `PGS000297`:

```wl
byID["PRS", "PGS000297"]["Trait"]
```

<!-- => "Height" -->

The trait name `"height"` and the EFO id for body height, `"EFO_0004339"`, both resolve to that same curated pick. A score already in the slot under the same PGS Catalog release is served from memory without recomputation, so each of them gives back the same genome unchanged and the identity test is [True]():

```wl
PolygenicRiskScore[byID, "height"] === PolygenicRiskScore[byID, "EFO_0004339"] === byID
```

<!-- => True -->

## Options

The two options and their defaults:

```wl
Options[PolygenicRiskScore]
```

<!-- => {"Reference" -> Automatic, "MaxVariants" -> Automatic} -->

### "Reference"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

By default the harmonized GRCh37 scoring file is downloaded and cached under
`data/references/pgs/`. Pointing `"Reference"` at a directory that already holds
`PGS######_hmPOS_GRCh37.txt.gz` reuses it and skips the download, which is the setting to
use when the file was staged ahead of time:

```wl
PolygenicRiskScore[subject, "height", "Reference" -> "data/references/pgs"]
```

### "MaxVariants"

The demo genome to score:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

`"MaxVariants"` caps the number of scoring variants, which bounds the compute for a very
large genome-wide score. The cap becomes the entry's `"NVariantsExpected"`, since coverage
is reported against the variants that were actually considered:

```wl
#| eval: false
capped = PolygenicRiskScore[hg, "PGS000012", "MaxVariants" -> 500]
```

When the cap is below the file's variant count the truncation is announced, so a score
read from a capped run is never mistaken for a full one:

```wl
PolygenicRiskScore::truncated
```

<!-- => "The score `1` has `2` variants; scoring only the first `3` (the \"MaxVariants\" cap)." -->

## Applications

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Its height score, served from the per-subject sidecar:

```wl
prs = PolygenicRiskScore[subject, "height"]
```

An entry is read through two derived quantities: the percentile as a population rank,
and the ratio of the coverage counts as the fraction of the scoring file that was usable.
A percentile of 0.69 places the subject above roughly two thirds of the reference
population for this trait:

```wl
Round[100 * prs["PRS", "PGS000297"]["Percentile"]]
```

<!-- => 69 -->

The coverage ratio says how much of the published score the subject's callset actually
supported; a low ratio makes the score less comparable to the published distribution, and
for this subject fewer than half of the 3280 scoring variants were usable:

```wl
N[prs["PRS", "PGS000297"]["NVariantsUsed"] / prs["PRS", "PGS000297"]["NVariantsExpected"]]
```

<!-- => 0.477439 -->

## Possible Issues

A handle on the demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

A trait that is neither a PGS Catalog ID, an EFO / MONDO id, nor one of the curated names
cannot be resolved to a scoring file, so the call fails before any download is attempted:

```wl
PolygenicRiskScore[hg, "hair colour"]
```

<!-- => the message PolygenicRiskScore::unknownTrait is issued and the result is $Failed -->

---

Scoring needs the human interpretation layer, so a plain
[Genome](paclet:WolframInstitute/Genome/ref/Genome) - what `"Human" -> False` gives - is
not an argument `PolygenicRiskScore` accepts:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

It fails the test a scoring argument has to pass:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

No definition matches such an argument, so the call comes back unevaluated, with nothing
computed and no message issued:

```wl
PolygenicRiskScore[g, "height"]
```

<!-- => the expression itself, unevaluated -->

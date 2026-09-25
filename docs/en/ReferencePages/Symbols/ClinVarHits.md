---
Template: Symbol
Name: ClinVarHits
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ClinVarHits
Keywords: [ClinVar, pathogenic, likely pathogenic, clinical significance, variant interpretation, HumanGenome, GRCh37, genotype, zygosity, carrier, VCV, gene]
SeeAlso: [HumanGenome, ImportVCF, Genome, GenotypeLookup, RegionVariants, VariantSummary]
RelatedGuides: [Genome]
---

## Usage

<code>[ClinVarHits]()[*hg*]</code> joins a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* against the ClinVar Pathogenic / Likely-pathogenic release and gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"ClinVarHits"` slot holds a [Tabular]() of the variants the subject carries.

<code>[ClinVarHits]()[*hg*, *opts*]</code> joins with the options below.

## Details & Options

- `ClinVarHits` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"ClinVarHits"` annotation slot populated and `References["ClinVarRelease"]` set, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot untouched.
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) matches no definition, so `ClinVarHits` returns unevaluated. A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) is such an argument.
- The data source is the ClinVar VCF release for GRCh37 ([ncbi.nlm.nih.gov/clinvar](https://www.ncbi.nlm.nih.gov/clinvar/)). On first use the release is downloaded (about 150 MB, one time) and prepared under `data/references/`; the prepared file is reused afterwards. A [ClinVarHits::download]() message announces the fetch, and [ClinVarHits::noref]() is issued if it fails.
- The reference is filtered to the Pathogenic / Likely-pathogenic records. ClinVar encodes clinical significance in `INFO/CLNSIG`; the include expression is `INFO/CLNSIG ~ "Pathogenic" || INFO/CLNSIG ~ "Likely_pathogenic"`. Capital-P `Pathogenic` never matches the lowercase `pathogenicity` of `Conflicting_classifications_of_pathogenicity`, so the filter keeps `Pathogenic`, `Likely_pathogenic`, `Pathogenic/Likely_pathogenic` (and their compound forms) while dropping Conflicting, Benign, and Uncertain records.
- The join is genotype-aware: a record is kept only when the subject's genotype `GT` carries a non-reference allele that matches the ClinVar pathogenic `ALT` on `(CHROM, POS, REF, ALT)`. A reference call (`0/0`), a no-call (`./.`), or a genotype whose alternate allele does not match the pathogenic allele is not a hit. A heterozygous hit at a recessive-disease locus is carrier status, not disease.
- GRCh37 ClinVar names its contigs `1`, …, `22`, `X`, `Y`, `MT`, whereas the personal genome uses `chr1`, …, `chr22`, `chrX`, `chrY`, `chrM`. `ClinVarHits` renames the ClinVar contigs to the chr-prefixed form (with `MT` mapped to `chrM`) so the two coordinate systems intersect.
- The subject read is restricted to the ClinVar Pathogenic / Likely-pathogenic positions through the tabix index, so the multi-gigabyte source is never scanned end to end.
- The resulting [Tabular]() has the columns `VariantID` (the canonical `chr-pos-ref-alt` string), `RsID`, `Gene` (the symbol from `INFO/GENEINFO`), `ClinicalSignificance` (`INFO/CLNSIG`), `ReviewStatus` (`INFO/CLNREVSTAT`), `Condition` (`INFO/CLNDN`), `VCVAccession` (the ClinVar Variation ID as a `VCV` accession), `Genotype` (the subject's `GT`), `Zygosity` (`"Heterozygous"` or `"Homozygous"`), `PopulationAF`, `FrequencySource`, and `ImputationQuality`. Rows are sorted by chromosome then position.
- ClinVar aggregates submitted assertions, and some common polymorphisms still carry a Pathogenic / Likely-pathogenic label from a weak or legacy submission, so a raw ClinVar hit is not proof of a rare Mendelian variant. Each hit is therefore annotated with `PopulationAF`, the gnomAD v2.1.1 (GRCh37) global allele frequency, and `FrequencySource` (the label `"gnomAD_r2_1"`). The frequency is the joint (exome + genome) allele frequency from the gnomAD GraphQL API (dataset `gnomad_r2_1`), looked up per variant over just the handful of hits a subject carries and cached under `data/references/gnomad_af_gnomAD_r2_1.tsv` so re-runs never re-query. A variant absent from gnomAD (or an mtDNA variant, which gnomAD v2 does not cover) is `Missing["NotFound"]` and treated as rare / unknown. A hit with a high population frequency but a pathogenic ClinVar label is almost always a benign common variant; see `"MaxPopulationAF"`.
- `ImputationQuality` is read straight from the subject row's own INFO with no extra source: `"Directly sequenced"` when the site is `TYPED` (or not `IMPUTED`), otherwise `"Imputed R2=<value>"` using the row's imputation `R2`.
- Results are cached per subject. A sidecar `data/<subject>/interpretations/clinvar-hits.tabular` (Parquet) plus its marker persists the annotated join across kernel sessions and hydrates a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) when the marker still matches. The marker keys on both the ClinVar release and the frequency-source version, so a new release or a changed frequency source recomputes the annotation. The sidecar stores the full (all-frequency) table, so changing `"MaxPopulationAF"` never forces a recompute - the frequency filter is re-applied to the full result each time.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Reference"` | [Automatic]() | [Automatic]() downloads and prepares the GRCh37 Pathogenic / Likely-pathogenic reference under `data/references/`; a directory path uses a prepared `clinvar_GRCh37_plp_chr.vcf.gz` already present there |
| `"MaxPopulationAF"` | [Automatic]() | [Automatic]() keeps every hit; a number keeps only hits whose `PopulationAF` is at most the threshold (a `Missing` AF is treated as rare / unknown and kept). A documented value like `0.01` separates rare Mendelian variants from common polymorphisms |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `ClinVarHits` annotates, reading the build and the sample name from the file's own header:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Joining against ClinVar gives back a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), with the `"ClinVarHits"` slot filled and every other slot carried through unchanged. The first call downloads and prepares the GRCh37 Pathogenic / Likely-pathogenic release, and later calls for the same subject are served from a per-subject sidecar:

```wl
cv = ClinVarHits[subject]
```

The slot holds a [Tabular]() with one row per Pathogenic / Likely-pathogenic record the subject carries, and a fixed column set - `VariantID`, `RsID`, `Gene`, `ClinicalSignificance`, `ReviewStatus`, `Condition`, `VCVAccession`, `Genotype`, `Zygosity`, `PopulationAF`, `FrequencySource` and `ImputationQuality`. The release the join ran against is recorded in the `References` sub-Association as a marker of the form `ClinVar-<date>`, the date taken from the reference's own `##fileDate` line; until a join has run the key reads [Missing]()`["NotComputed"]`:

```wl
cv["References", "ClinVarRelease"]
```

<!-- => the ClinVar release the join ran against, of the form "ClinVar-2026-06-27" -->

The joined genome is a new value and the one that was joined is left alone, so its own slot still reads [Missing]()`["NotComputed"]`, as every interpretation slot does until its method has run:

```wl
subject["ClinVarHits"]
```

<!-- => Missing["NotComputed"] -->

Joining a genome whose slot is already filled rehydrates the cached sidecar instead of repeating the work, so the same annotated genome comes back with no second pass over the reference:

```wl
ClinVarHits[cv]
```

---

Two options control the join, and both default to [Automatic]():

```wl
Options[ClinVarHits]
```

<!-- => {"Reference" -> Automatic, "MaxPopulationAF" -> Automatic} -->

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

GRCh37 ClinVar names its contigs `1`, …, `22`, `X`, `Y`, `MT`, while a personal callset names them `chr1`, …, `chrM`. The demo genome is on the chr-prefixed side, so `ClinVarHits` renames the ClinVar contigs to meet it rather than the other way round:

```wl
VariantSummary[hg] // Dataset
```

The join is genotype-aware: a record survives only when the subject's genotype carries a non-reference allele matching the pathogenic `ALT`. Of the demo genome's eight rows one is a homozygous-reference call, which could never be a hit whatever ClinVar records at that position, while the carried rows become `"Heterozygous"` (`het`) or `"Homozygous"` (`homAlt`) in the `Zygosity` column.

`ImputationQuality` needs no second source: it reads the subject row's own INFO, reporting a `TYPED` site as directly sequenced and an `IMPUTED` one at its stated `R2`. The demo records split evenly between the two provenances.

The annotation reads nothing but the subject row's own flag and its `R2` - the flag chooses the wording, the `R2` fills in the imputed case:

```wl
hg["Variants"] // Dataset
```

The demo genome carries no ClinVar Pathogenic / Likely-pathogenic record, so the join keeps nothing, and the slot of the joined genome is an empty [Tabular]() that shows only its columns - the same twelve a join with hits fills:

```wl
ClinVarHits[hg]["ClinVarHits"]
```

## Options

### "Reference"

By default the GRCh37 Pathogenic / Likely-pathogenic reference is downloaded and prepared under `data/references/`:

```wl
Lookup[Options[ClinVarHits], "Reference"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Pointing `"Reference"` at a directory that already holds a prepared `clinvar_GRCh37_plp_chr.vcf.gz` reuses it and skips the download:

```wl
ClinVarHits[subject, "Reference" -> "data/references"]
```

### "MaxPopulationAF"

ClinVar contains common variants with weak or legacy pathogenic assertions, so a frequency filter separates genuine rare Mendelian variants from common polymorphisms. The default keeps every hit:

```wl
Lookup[Options[ClinVarHits], "MaxPopulationAF"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

A number drops the hits whose `PopulationAF` exceeds it; a `Missing` frequency is treated as rare / unknown and kept. `0.01` is the usual screening threshold, and the one [CarrierStatus](paclet:WolframInstitute/Genome/ref/CarrierStatus) applies by default. The sidecar stores the full table and the filter is re-applied to it on the way out, so a new threshold never forces a recompute:

```wl
ClinVarHits[subject, "MaxPopulationAF" -> 0.01]
```

## Possible Issues

The default keeps every hit, so an unfiltered table can contain common polymorphisms that a weak or legacy ClinVar assertion labelled pathogenic. A genome read from the demonstration file:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Counting the hits above the usual `0.01` screening threshold gives the number of rows a frequency filter would remove from a join:

```wl
#| eval: false
Count[Normal[ClinVarHits[hg]["ClinVarHits"]][[All, "PopulationAF"]], af_ ? NumericQ /; af > 0.01]
```

gnomAD v2.1.1 does not cover every variant - an mtDNA hit, for one, has no entry - so `PopulationAF` is either a number or `Missing["NotFound"]`. A missing frequency is treated as rare and kept rather than dropped, which is the safe direction for a screening filter but leaves the uncovered rows unscreened.

---

The reference is prepared with `bcftools`, `tabix` and `curl`. If one of them is not on the path, or the download fails, the join gives `$Failed` after issuing [ClinVarHits::noref]():

```wl
ClinVarHits::noref
```

<!-- => "ClinVarHits could not obtain the prepared ClinVar reference; the download or the bcftools / tabix preparation step failed.  Ensure bcftools, tabix and curl are on PATH and the network is reachable." -->

---

`ClinVarHits` is defined for a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) only; [HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ) is the test it applies to its argument. Importing with `"Human" -> False` gives a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), which carries no interpretation layer:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

Such an argument matches no definition, so the call comes back unevaluated - the genome is still sitting inside a `ClinVarHits` expression rather than annotated:

```wl
ClinVarHits[g]
```

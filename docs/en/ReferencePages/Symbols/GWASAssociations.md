---
Template: Symbol
Name: GWASAssociations
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GWASAssociations
Keywords: [GWAS Catalog, genome-wide association, risk allele, effect allele, dosage, odds ratio, beta, p-value, mapped trait, EFO, PubMed, citation, rsID, HumanGenome, GRCh37, GRCh38, strand]
SeeAlso: [HumanGenome, PolygenicRiskScore, TraitAssociations, ClinVarHits, AlphaMissenseScores, ImportVCF, Genome]
RelatedGuides: [Genome]
---

## Usage

<code>[GWASAssociations]()[*hg*]</code> reports the genotypes a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* carries at SNPs with a published trait association in the NHGRI-EBI GWAS Catalog and returns a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"GWASAssociations"` slot holds a [Tabular]() of one row per (rsID, published association).

<code>[GWASAssociations]()[*hg*, *opts*]</code> reports with the options below.

## Details & Options

- `GWASAssociations` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"GWASAssociations"` annotation slot populated and `References["GWASCatalogVersion"]` set, while *hg*, the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot stay untouched.
- The result reproduces the per-SNP association report style of a consumer genetics report: for each of the subject's genotypes that a GWAS study associated with a trait, it lists the rsID, the subject's position and genotype, the risk (effect) allele, whether the subject carries it and in how many copies, the mapped trait, the effect size, and the citing PubMed publication.
- The data source is the [NHGRI-EBI GWAS Catalog](https://www.ebi.ac.uk/gwas/) all-associations release, specifically the ontology-annotated, one-row-per-SNP download (`gwas-catalog-associations_ontology-annotated-split.zip`, a set of year-partitioned association TSVs, about 1.15 million rows). On first use the release is downloaded (about 70 MB zipped), reduced once to a compact per-association table (about 950k single-rsID associations across about 420k rsIDs; the roughly one-third of catalog rows keyed by a `chrN:pos` locus rather than an rsID are dropped, since they cannot be matched by rsID), and cached under `data/references/gwas/` with a release marker. A [GWASAssociations::download]() message announces the fetch, and [GWASAssociations::noref]() is issued if the download or the `unzip` / `awk` / `gzip` / `sort` reduction step fails.
- The catalog and the subject are matched by rsID, so no liftover happens. The GWAS Catalog reports its coordinates (`CHR_ID` / `CHR_POS`) on GRCh38, whereas the personal genome is GRCh37/hg19. Rather than lift coordinates between builds, which introduces unmapped-position failure modes, `GWASAssociations` keys the match on the rsID: the subject's VCF `ID` column carries dbSNP rsIDs such as `rs1234`, and the catalog carries the rsID in its `SNPS` column. The subject's own GRCh37 position, taken from the VCF, is reported in the `GRCh37Position` column; the catalog's GRCh38 position is used only for the reduction, never for the match.
- Every catalog row whose `SNPS` is a single rsID the subject has a genotype at is kept, homozygous-reference genotypes included, since an association report shows a genotype regardless of whether it carries the risk allele. Multi-SNP haplotype rows and rows keyed by a `chrN:pos` locus rather than an rsID are dropped during the reduction. Because a well-studied SNP is cited by many studies, one rsID commonly appears in several trait rows.
- The risk-allele dosage is strand-aware. The risk allele is parsed from the catalog's `STRONGEST SNP-RISK ALLELE` column (`rs1234-A` gives `A`, `rs1234-?` gives an unknown allele). `RiskAlleleDosage` (0, 1, or 2) counts how many copies of the risk allele the subject's `GT` carries, matching the risk allele to the subject's `REF` / `ALT` directly and, failing that, under reverse complement, so a risk allele reported on the opposite strand still matches. A strand-ambiguous palindromic site, where the risk allele matches a subject allele both directly and reverse-complemented because the alleles are a complementary `A/T` or `C/G` pair, yields `RiskAlleleDosage` and `CarriesRisk` [Missing](), as does an unknown (`?`) or indel risk allele, a complex site, or a no-call. `CarriesRisk` is [True]() when the dosage is at least 1.
- The returned [Tabular]() has the columns `RsID`, `GRCh37Position` (the subject's own `chr:pos`), `Genotype` (the subject's genotype in base form, e.g. `"A/G"`), `RiskAllele`, `RiskAlleleDosage` (0 / 1 / 2 / [Missing]()), `CarriesRisk` ([True]() / [False]() / [Missing]()), `Trait` (the catalog `DISEASE/TRAIT`), `MappedTrait` (the EFO `MAPPED_TRAIT` label), `OddsRatioOrBeta` (the catalog `OR or BETA`, an odds ratio for disease traits or a beta for quantitative traits - the catalog does not label which), `PValue`, `RiskAlleleFrequency` (the reported risk-allele frequency, or [Missing]() when `NR`), `PubMedID`, `FirstAuthor`, `Year`, and `Journal`. Rows are sorted by ascending p-value, so the strongest associations come first.
- The annotation slot holds the filtered view produced by the options in force. A per-subject sidecar `data/<subject>/interpretations/gwas-associations.tabular` (Parquet), together with its release marker, persists the full unfiltered result across kernel sessions and hydrates a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) while the release still matches. Annotating a genome again rehydrates that sidecar and re-applies the filters, so changing `"Trait"`, `"MaxPValue"`, or `"CarriedOnly"` never re-scans the genome.
- A GWAS association is a population statistical signal, not a diagnosis. Each row is a single study's finding that, in some cohort, the risk allele's frequency differed between cases and controls, or tracked a quantitative trait. Most catalog studies are of European-ancestry cohorts and the effect sizes are typically small, with odds ratios near 1. Carrying a risk allele means the subject shares a variant that was statistically associated with a trait in a population - it is not a determined outcome, and it is neither clinical advice nor a diagnosis.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Trait"` | [All]() | [All]() keeps every trait; a string keeps only rows whose disease/trait or mapped-trait text contains it (case-insensitive substring), e.g. `"testosterone"` |
| `"MaxPValue"` | `5*^-8` | keep only rows at least this significant; the default `5*^-8` is genome-wide significance. Raise it (or set [All]()) to include suggestive associations |
| `"CarriedOnly"` | [False]() | when [True](), keep only rows where the subject carries the risk allele (`CarriesRisk === True`) |
| `"Reference"` | [Automatic]() | [Automatic]() downloads and reduces the catalog under `data/references/gwas/`; a directory path uses a `gwas_associations_reduced.tsv.gz` already present there |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `GWASAssociations` reports on:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Reporting gives back a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose icon carries the GWAS indicator and whose `"GWASAssociations"` slot is filled. The first call downloads the NHGRI-EBI GWAS Catalog associations release and reduces it once, and later calls for the same subject are served from a per-subject sidecar. Unfiltered, the report lists every published association at every SNP the subject has a genotype at, a very large table for a whole-genome subject; `"Trait"` keeps the associations whose disease/trait or mapped-trait text contains the given string, matched case-insensitively:

```wl
gw = GWASAssociations[subject, "Trait" -> "eye color"]
```

The filled slot is the report itself: a [Tabular]() with one row per (rsID, published association) whose trait text matches, 83 rows for eye colour, sorted by ascending p-value so the strongest association comes first. Every report carries the same columns in the same order, and where the catalog reported no value, or the strand rules cannot decide one, a column holds a [Missing]() in place of its usual type.

A row reads across those columns the way a consumer report does. The first row is the SNP `rs1129038`: the subject's genotype there is `C/T` at `chr15:28356859`, the subject's own position on the GRCh37 build the callset came in on (the match is keyed on the rsID, so nothing is lifted over); the study's risk allele is `T`, the strand-aware dosage counts one copy of it, and `CarriesRisk` is [True](); the trait is "Eye color", with its mapped EFO trait beside it; then the effect size and the p-value; and finally the citation - Simcoe M, 2021, Sci Adv - with its PubMed id:

```wl
gw["GWASAssociations"] // Dataset
```

The GWAS Catalog release the report was made against is recorded in the `References` sub-Association, a marker naming the release date; before reporting there is no release to record:

```wl
gw["References", "GWASCatalogVersion"]
```

<!-- => "GWASCatalog-2026-06-22" -->

The reported genome is a new value and the one that was reported on is left alone, so its own slot still reads [Missing]()`["NotComputed"]`:

```wl
subject["GWASAssociations"]
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

The catalog and the subject are matched by rsID, so the ref-confirming row at `chr1:200000`, which has no rsID, can reach no association, and an rsID the catalog never cites contributes no row either. The strand rules act on the rows that do match. `RiskAlleleDosage` matches the risk allele to the subject's `REF` / `ALT` directly and, failing that, under reverse complement, and `CarriesRisk` is [True]() from one copy upwards; at a strand-ambiguous palindromic site, a complementary `A`/`T` or `C`/`G` pair, a risk allele matches both ways, so the dosage is undecidable and both columns are [Missing]() rather than `0` and [False](). The demo genome's `rs1200` is such an `A`/`T` site, and three more of its rows are palindromic too:

```wl
Select[Normal[hg["Variants"]], Length[#ALT] == 1 && MemberQ[{"AT", "TA", "CG", "GC"}, #REF <> First[#ALT]] &][[All, "ID"]]
```

<!-- => {"rs400", "rs1000", "rs1100", "rs1200"} -->

The whole-genome callset, whose report is served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Its eye-colour associations:

```wl
gw = GWASAssociations[subject, "Trait" -> "eye color"]
```

A well-studied SNP is cited by many studies, so one rsID commonly appears in several
rows. Counting the `RsID` column gives, for each rsID, how many published eye-colour
associations cite it, the most-cited first:

```wl
ReverseSort[Counts[Lookup[Normal[gw["GWASAssociations"]], "RsID"]]]
```

Reporting on an already-reported genome does not re-scan it: the full table is rehydrated
from the per-subject sidecar and the same options select the same rows, so the same
genome comes back with the same slot:

```wl
GWASAssociations[gw, "Trait" -> "eye color"]
```

## Options

The four options and their defaults. The significance cut is an exact number, the
rational form of `5*^-8`:

```wl
Options[GWASAssociations]
```

<!-- => {"Trait" -> All, "MaxPValue" -> 1/20000000, "CarriedOnly" -> False, "Reference" -> Automatic} -->

### "Trait"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

`"Trait"` keeps the associations whose disease/trait or mapped-trait text contains the
given string, matched case-insensitively. Combining it with `"MaxPValue" -> All` includes
the suggestive hits for that trait:

```wl
eye = GWASAssociations[subject, "Trait" -> "eye color", "MaxPValue" -> All]
```

The slot holds the trait's rows in the per-SNP-with-citation layout, every eye-colour
association the catalog cites at the subject's SNPs: the genome-wide-significant rows
first, then any suggestive ones after them, since the table stays sorted by p-value:

```wl
eye["GWASAssociations"] // Dataset
```

### "MaxPValue"

`"MaxPValue"` sets the significance cut. The default is genome-wide significance, in
floating-point form:

```wl
N[Lookup[Options[GWASAssociations], "MaxPValue"]]
```

<!-- => 5.*^-8 -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

A larger value admits the suggestive associations alongside the genome-wide ones, and
setting the option to [All]() drops the cut entirely and keeps every reported p-value:

```wl
suggestive = GWASAssociations[subject, "Trait" -> "eye color", "MaxPValue" -> 1*^-5]
```

### "CarriedOnly"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

`"CarriedOnly" -> True` keeps only the rows where the subject carries the risk allele,
giving the personal-relevance subset of the report:

```wl
carried = GWASAssociations[subject, "Trait" -> "eye color", "CarriedOnly" -> True]
```

The filter keeps `CarriesRisk === True` only, so of the three values that column can
take (carried, not carried, and undecidable) just the first one survives it, and every
row left has a `RiskAlleleDosage` of 1 or 2:

```wl
carried["GWASAssociations"] // Dataset
```

### "Reference"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

By default the GWAS Catalog is downloaded and reduced under `data/references/gwas/`.
Pointing `"Reference"` at a directory that already holds a
`gwas_associations_reduced.tsv.gz` reuses it and skips the download:

```wl
GWASAssociations[subject, "Trait" -> "eye color", "Reference" -> "data/references/gwas"]
```

## Possible Issues

`GWASAssociations` reports on a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). The path of the demo file
is a string, not a genome:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the demo file's own path, under $TemporaryDirectory -->

A file path matches no definition, so the call comes back unevaluated:

```wl
GWASAssociations[demoFile]
```

<!-- => the expression itself, unevaluated -->

A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) - what `"Human" -> False`
gives, and what a multi-sample or non-human callset imports as - is such an argument too:

```wl
g = ImportVCF[demoFile, "Human" -> False]
```

[HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ) is [False]() for it:

```wl
HumanGenomeQ[g]
```

<!-- => False -->

It reaches no definition either; nothing is computed and no message is issued:

```wl
GWASAssociations[g]
```

<!-- => the expression itself, unevaluated -->

---

The report cannot be built without the catalog, and a failed download or reduction step
is reported rather than silently returning an empty table:

```wl
GWASAssociations::noref
```

<!-- => "GWASAssociations could not obtain the reduced GWAS Catalog table; the download or the unzip / awk / gzip / sort reduction step failed.  Ensure curl, unzip, awk, gzip and sort are on PATH and the network is reachable." -->

A strand-ambiguous palindromic site is not a carrier as far as `"CarriedOnly"` is
concerned: the filter keeps `CarriesRisk === True` only, so an undecidable site drops out
alongside the genuine non-carriers.

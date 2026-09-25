---
Template: Symbol
Name: GenomeReport
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenomeReport
Keywords: [report, aggregate, summary, personal genome, interpretation, HumanGenome, HTML, decision support, caveat, Promethease]
SeeAlso: [HumanGenome, AncestryEstimate, PharmacogenomicProfile, ClinVarHits, CarrierStatus, PolygenicRiskScore, TraitAssociations, GWASAssociations, AlphaMissenseScores]
RelatedGuides: [Genome]
---

## Usage

<code>[GenomeReport]()[*hg*]</code> aggregates every already-computed interpretation of a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* into one structured report per subject: a canonical [Association]() keyed by section, and a shareable rendered HTML document written under `data/<subject>/report/`.

<code>[GenomeReport]()[*hg*, *opts*]</code> aggregates with the options below.

## Details & Options

- The report is an educational, decision-support summary, not a medical document. The rendered file leads with a caveat block: it is not clinical-grade and was not produced under a validated pipeline; estimates are population-relative; polygenic-risk and ancestry estimates are calibrated mostly on European-ancestry cohorts and are less accurate for other ancestries; the underlying genotypes are largely imputed; a heterozygous carrier is healthy; and any result should be discussed with a qualified clinician or genetic counsellor before acting on it.
- `GenomeReport` is the capstone [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: it reuses the other interpretation operators and their per-subject sidecars and never re-implements any analysis. It reads the cached [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate), [HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall), [PharmacogenomicProfile](paclet:WolframInstitute/Genome/ref/PharmacogenomicProfile), [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits), [CarrierStatus](paclet:WolframInstitute/Genome/ref/CarrierStatus), [PolygenicRiskScore](paclet:WolframInstitute/Genome/ref/PolygenicRiskScore), [TraitAssociations](paclet:WolframInstitute/Genome/ref/TraitAssociations), [GWASAssociations](paclet:WolframInstitute/Genome/ref/GWASAssociations), and [AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores) results and folds them into a single summary.
- Being a terminal aggregation, `GenomeReport` gives the structured [Association]() itself rather than a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which would read oddly for a value nothing filters further. It also stashes a copy in the per-subject report-cache sidecar `data/<subject>/report/report.wxf` (the persisted `"ReportCache"`), and writes the rendered document whose path is given under the `"ReportFile"` key.
- Nothing is recomputed by default, so no aggregation silently triggers a multi-minute run. With `"Compute" -> "Cached"` (the default) each section is served from the already-computed in-memory slot or, if that is empty, from the per-subject sidecar file read directly — a quick Parquet / WXF import that never triggers a reference download. A section that has never been run is marked `Missing["NotComputed"]` and listed under the Overview's `"SectionsNotRun"` instead of being computed.
- The structured result is an [Association]() keyed by the included section names, in order, plus the top-level `"ReportFile"` key:
  - `"Overview"` is an [Association]() of `Subject`, `Sex`, `Build`, `Backend`, `VariantCount`, `ReferenceVersions` (the `hg["References"]` map), `SectionsIncluded`, `SectionsAvailable` and `SectionsNotRun`. The variant count is reported only when it is already cached, so the Overview never forces a full genome scan.
  - `"Ancestry"` carries `Superpopulation`, `SuperpopulationFractions`, `mtDNAHaplogroup` and `YHaplogroup`.
  - `"Pharmacogenomics"` carries the actionable subset (the gene-drug rows with a non-normal phenotype) as a [Tabular](), plus `ActionableGuidanceCount`, `ActionableGeneCount`, `NormalGeneCount`, and the full table under `Tabular`.
  - `"ClinicalVariants"` carries the frequency-annotated ClinVar Pathogenic / Likely-pathogenic hits as a [Tabular]() with a `Count`.
  - `"CarrierStatus"` carries the rare-carrier [Tabular]() (filtered at the `0.01` `"MaxPopulationAF"` default) with a `Classifications` tally of each carrier classification.
  - `"PolygenicRiskScores"` carries a [Tabular]() of `Trait`, `Percentile`, `PGSID` and `Coverage` for the computed scores. That is the structured value; the rendered section presents each score as a plain-language block instead, as described below.
  - `"Traits"`, `"GWASHighlights"` (the top carried genome-wide-significant associations, capped) and `"MissenseHighlights"` (the top AlphaMissense likely-pathogenic variants, capped) carry compact summaries with a count, or `Missing["NotComputed"]` when the underlying slot has never been computed.
- Every section that pulls from a large [Tabular]() includes only a small top-N view (default 15 rows), never the full tens of thousands of rows.
- The rendered document is a self-contained HTML file, written into a per-subject `report` directory beside the source VCF (`data/<subject>/report/<subject>-report.html` for a genome kept under `data/`): a titled page with a section per interpretation domain, an HTML table per [Tabular](), and a prominent caveat header. The `data/` tree is git-ignored, so the report is never committed.
- The rendered polygenic-risk section is interpreted rather than a bare number table. Instead of a four-column `Trait` / `Percentile` / `PGSID` / `Coverage` table, each score renders as its own block: the trait name and a percentile band (`>= 95` "Very high", `80-95` "High", `60-80` "Above average", `40-60` "Average", `20-40` "Below average", `5-20` "Low", `< 5` "Very low") as a heading, then a plain-language interpretation sentence that combines the percentile, the band, a short trait description, and the trait's direction of health concern — `"HigherIsRisk"` (a high percentile is the less-favorable direction), `"LowerIsRisk"` (a low percentile is less favorable, as for HDL, the protective cholesterol, so the sentence is framed by the complementary share of people), or `"Neutral"` (not a health risk, as for height). A score whose percentile is `Missing["NoReference"]` — too few of its variants had a usable population frequency to place it on a distribution — says so instead of showing a band. An uncurated PGS id falls back to a generic description and is reported plainly, without a good-or-bad judgement. The PGS id and coverage are kept but demoted to a small muted footnote (for example "PGS000066, 94% of variants used"), not prominent columns.
- The Pharmacogenomics, Clinical-variants (ClinVar), Carrier-status and Ancestry sections likewise give each finding a plain-language interpretation, in the selected language, composed from the row's own data and demoting the raw identifiers and secondary detail to a muted footnote, above the compact detail table that is kept for precise reference:
  - Pharmacogenomics reads each gene-drug finding from its metabolizer phenotype: a Normal call expects a standard response, a Poor or Decreased call warns the drug may be processed differently and to discuss dosing, an Intermediate call flags a somewhat-reduced response, and a Rapid or Ultrarapid call warns of faster processing, or of higher active levels for a prodrug. A low-confidence call — a CYP2D6 whose copy-number / hybrid alleles cannot be read from a SNP VCF, or a gene with missing defining sites — is flagged as tentative in plain language. The diplotype, CPIC level, activity score, and the uncallable-sites note are demoted to the footnote; the standing "decision-support, discuss with a clinician or pharmacist, not a prescription" caveat lives in the section intro.
  - Clinical variants (ClinVar) names the condition and whether the variant is carried in one or two copies, then gives the frequency reality: a variant that is common in the general population (`PopulationAF >= 0.05`) is called out as very unlikely to cause disease despite its pathogenic label, since common variants with legacy pathogenic labels are a known source of false alarms; a rare variant (`< 0.01` or `Missing`) is called rare. Each finding closes with the caveat that a ClinVar label is not a diagnosis, and a weak review status ("no assertion criteria provided") is flagged as lower-evidence. The VCV accession and rsID are demoted to the footnote.
  - Carrier status frames the reproductive meaning: a healthy carrier of one copy of a recessive variant is not affected, and this matters mainly for family planning, being relevant if a reproductive partner also carries a variant in the same gene; a `Homozygous (possible affected)` finding notes that two copies warrant clinical review, and a `Dominant finding` notes that a single variant in a dominant-acting gene may be relevant. The frequency-filtering context (only rare variants are shown by default) is kept, and the identifiers are demoted to the footnote.
  - Ancestry explains the numbers: the super-population is the best broad continental match, not a country or ethnicity; the fraction breakdown is coarse, and small non-dominant fractions are usually statistical noise rather than real admixture; and the mitochondrial (mtDNA) and Y haplogroups are described as single direct maternal and paternal lineages out of thousands of ancestors, not overall ancestry. The Overview adds a one-line reading of what the sex-karyotype call means.
- The rendered document is written for a non-expert reader. Every section opens with a one-to-two-sentence plain-language intro under its header, explaining in lay terms what the section shows, how to read it, and, where relevant, what it does not mean; abbreviations are expanded on first use in a section (for example "polygenic risk score (PRS)", "genome-wide association study (GWAS)", "minor allele frequency (MAF)"). The document then closes with a Glossary appendix that defines every technical term it uses in one plain sentence, grouped by category (Variants; Frequency and quality; Clinical; Risk; Ancestry; Pharmacogenomics), each term linking to an authoritative educational resource (Wikipedia, MedlinePlus Genetics, the NHGRI genetics glossary, and the ClinVar / gnomAD / PGS Catalog / CPIC / PharmVar home pages) that opens in a new browser tab. The intros, the glossary titles and category names, and every glossary definition are localized in the selected language.
- The rendered document can be localized with `"Language"` (English default, or `"Russian"`). Only the HTML document is translated; the structured [Association]() is language-independent, and its section keys and values stay English. The renderer routes every user-facing string through one localization table, so a language is a data change rather than a second renderer. Translation covers the document title and subtitle, the caveat block, the section titles, the per-section plain-language intros, the field labels, the table column headers, the section prose, the polygenic-risk percentile bands and per-trait interpretation sentences (including each curated score's direction of health concern and description), the per-finding interpretation sentences for the Pharmacogenomics, Clinical-variants, Carrier-status and Ancestry sections (and the sex-karyotype one-liner), the glossary appendix (its title, category names, and every definition, plus a Russian link where a Russian-language educational article exists), and a fixed set of controlled-vocabulary data terms: metabolizer phenotypes, carrier classifications, zygosity, the sex-karyotype label, superpopulation names, imputation-quality strings, and the curated polygenic-score trait names. Scientific identifiers are never translated and render identically in every language: gene symbols, rsIDs, star-allele diplotypes, haplogroup labels, PGS and PubMed IDs, drug names, and free-text trait strings from external catalogs. The file is written UTF-8 with a `<meta charset="utf-8">` header and the matching `<html lang="...">` attribute, so Cyrillic text renders correctly.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Compute"` | `"Cached"` | `"Cached"` serves every section from the cache (fast, no download); `"All"` runs every interpretation operator (may take minutes, and may download references); a list of slot names (e.g. `{"Ancestry", "Pharmacogenomics"}`) refreshes only those and serves the rest from cache |
| `"Sections"` | [All]() | [All]() includes the default ordered section list; a list restricts and orders the output to the named sections |
| `"Language"` | `"English"` | `"English"` (default) or `"Russian"`: the language the rendered HTML document is written in. Only the rendered document is localized; the structured [Association]() keeps its English section keys and values unchanged |


## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome):

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Aggregating its cached interpretations recomputes nothing and downloads nothing, and `"Sections"` restricts the report to the named sections. The result is an [Association]() keyed by section, in the order named, plus the path of the rendered document:

```wl
report = GenomeReport[subject, "Sections" -> {"Overview", "Ancestry"}]
```

<!-- => an Association with the keys "Overview", "Ancestry" and "ReportFile" -->

The Overview is the report's own metadata: who the subject is, the karyotype call filled in by [ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex), how the genome was read, which reference releases the sections were computed against, and which sections were included, which had something cached to summarize, and which have never been run. The variant count is reported only when it is already cached, so the Overview never forces a full genome scan:

```wl
report["Overview"]
```

<!-- => the Overview Association: "Subject" -> "SUBJECT", "Sex" -> "XY", "Build" -> "GRCh37/hg19", "Backend" -> "Tabix", "VariantCount" -> Missing["NotComputed"], the "ReferenceVersions" map, "SectionsIncluded" and "SectionsAvailable" each naming the Ancestry section, and "SectionsNotRun" -> {} -->

Each section is a compact summary, not a dump. The Ancestry section folds the [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) result together with the two [HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall) lineages into four fields: `"Superpopulation"` is the single best continental match; `"SuperpopulationFractions"` is keyed by the five 1000 Genomes super-population codes `AFR`, `AMR`, `EAS`, `EUR` and `SAS`, so the fractions always cover the same axes and sum to `1`; and `"mtDNAHaplogroup"` and `"YHaplogroup"` are one maternal (mtDNA) and one paternal (Y) lineage, not genome-wide ancestry. A lineage with no call, as for a subject with no chrY coverage, carries a [Missing]() instead of a label:

```wl
report["Ancestry"]
```

<!-- => <|"Superpopulation" -> "EUR", "SuperpopulationFractions" -> <|"EAS" -> 0.0872, "AMR" -> 0.1061, "AFR" -> 0., "EUR" -> 0.7433, "SAS" -> 0.0634|>, "mtDNAHaplogroup" -> "T2a1b1a1", "YHaplogroup" -> "N1c1a1"|> -->

The rendered HTML document is written on every aggregation into a per-subject `report` directory beside the source VCF — `data/SUBJECT/report/` for this genome, inside the git-ignored `data/` tree — so the file is there as soon as the report comes back, and its path is given under `"ReportFile"`:

```wl
report["ReportFile"]
```

<!-- => the path of the written report -->

---

The options the aggregation takes:

```wl
Options[GenomeReport]
```

<!-- => {"Compute" -> "Cached", "Sections" -> All, "Language" -> "English"} -->

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

By default the report carries the full section list — `"Overview"`, `"Ancestry"`, `"Pharmacogenomics"`, `"ClinicalVariants"`, `"CarrierStatus"`, `"PolygenicRiskScores"`, `"Traits"`, `"GWASHighlights"` and `"MissenseHighlights"`, in that order — plus `"ReportFile"`. Each section is an [Association]() summary of its domain once its interpretation has been run, a section never run is a [Missing](), and `"ReportFile"` is a path. Nothing has been computed for the demo genome, so every interpretation section reads `Missing["NotComputed"]`:

```wl
report = GenomeReport[hg]
```

<!-- => the section-keyed Association: the Overview, every interpretation section Missing["NotComputed"], and the path of the rendered document -->

The Overview is the report's own metadata, under the nine keys `Subject`, `Sex`, `Build`, `Backend`, `VariantCount`, `ReferenceVersions`, `SectionsIncluded`, `SectionsAvailable` and `SectionsNotRun`. `Sex` is the karyotype call, filled once [ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex) has been run for the subject:

```wl
report["Overview"]
```

<!-- => <|"Subject" -> "NA12878", "Sex" -> Missing["NotComputed"], "Build" -> "GRCh37/hg19", "Backend" -> "AwkStream", "VariantCount" -> Missing["NotComputed"], "ReferenceVersions" -> the reference-version map, "SectionsIncluded" -> the eight interpretation sections, "SectionsAvailable" -> {}, "SectionsNotRun" -> the same eight|> -->

`"SectionsIncluded"` lists the interpretation sections the report carries, in the order they are rendered:

```wl
report["Overview", "SectionsIncluded"]
```

<!-- => {"Ancestry", "Pharmacogenomics", "ClinicalVariants", "CarrierStatus", "PolygenicRiskScores", "Traits", "GWASHighlights", "MissenseHighlights"} -->

`"SectionsAvailable"` is the subset of those with something cached to summarize. Nothing has been computed for the demo genome, so it is empty and every section falls into `"SectionsNotRun"` instead:

```wl
report["Overview", "SectionsAvailable"]
```

<!-- => {} -->

`"ReferenceVersions"` is the genome's own reference-version map, so a report records which release of each external database its sections were computed against. The build is pinned from the start, and each release reads `Missing["NotComputed"]` until its interpretation has run:

```wl
report["Overview", "ReferenceVersions"]
```

<!-- => <|"Build" -> "GRCh37/hg19", "ThousandGenomesPanel" -> Missing["NotComputed"], "ClinVarRelease" -> Missing["NotComputed"], "PGSCatalogVersion" -> Missing["NotComputed"], "CPICVersion" -> Missing["NotComputed"], "PharmGKBVersion" -> Missing["NotComputed"], "SNPediaCommit" -> Missing["NotComputed"], "AlphaMissenseRelease" -> Missing["NotComputed"], "GWASCatalogVersion" -> Missing["NotComputed"]|> -->

The variant count is reported only when it is already cached, so assembling the Overview never forces a full genome scan:

```wl
report["Overview", "VariantCount"]
```

<!-- => Missing["NotComputed"] -->

A section whose slot has never been computed is marked `Missing["NotComputed"]` and listed under the Overview's `"SectionsNotRun"` instead of triggering its own, possibly slow, computation, and what each section carries once its operator has run is fixed by the section. Once [PharmacogenomicProfile](paclet:WolframInstitute/Genome/ref/PharmacogenomicProfile) has been run, the Pharmacogenomics section keeps the actionable rows and their counts beside the full table — `Actionable`, `ActionableGuidanceCount`, `ActionableGeneCount`, `NormalGeneCount` and `Tabular` — so the rendered page can lead with what is actionable and still reach the rest. Like every section that pulls from a large [Tabular](), `Actionable` is a top-N view of at most 15 rows, whatever the underlying count:

```wl
report["Pharmacogenomics"]
```

<!-- => Missing["NotComputed"] -->

The clinical-variants section is the [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) result with a `Count` beside it and the full table kept for reference, under the keys `Hits`, `Count` and `Tabular`:

```wl
report["ClinicalVariants"] // Dataset
```

<!-- => Missing["NotComputed"] -->

The carrier section records the frequency threshold it filtered at under `MaxPopulationAF`, the `0.01` [CarrierStatus](paclet:WolframInstitute/Genome/ref/CarrierStatus) default; only variants rarer than that are summarized:

```wl
report["CarrierStatus"] // Dataset
```

<!-- => Missing["NotComputed"] -->

The structured polygenic-risk value, under `Scores`, stays a plain four-column [Tabular]() of `Trait`, `Percentile`, `PGSID` and `Coverage`; the plain-language bands and interpretation sentences live only in the rendered document:

```wl
report["PolygenicRiskScores"]
```

<!-- => Missing["NotComputed"] -->

## Options

### "Compute"

The demo genome, whose interpretations have never been computed:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Its report, served from the cache:

```wl
report = GenomeReport[hg]
```

<!-- => the section-keyed Association, every interpretation section Missing["NotComputed"] -->

By default (`"Cached"`) every section is served from the cache and nothing is recomputed, so a section that has never been run is reported as not run rather than computed on the spot. On the demo genome that is every section:

```wl
report["Overview", "SectionsNotRun"]
```

<!-- => {"Ancestry", "Pharmacogenomics", "ClinicalVariants", "CarrierStatus", "PolygenicRiskScores", "Traits", "GWASHighlights", "MissenseHighlights"} -->

A list of slot names refreshes only those sections and leaves the rest cached; `"All"` refreshes every one of them. Either form runs the interpretation operators themselves, which can take minutes and download reference databases. The key list is the full one either way — `"Compute"` changes which sections are populated, never which are present:

```wl
#| eval: false
GenomeReport[hg, "Compute" -> {"Ancestry", "Pharmacogenomics"}]
```

### "Sections"

The demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

By default ([All]()) the report includes the full ordered section list. Restrict the output by naming the sections to keep; the result carries only those keys, plus `"ReportFile"`:

```wl
GenomeReport[hg, "Sections" -> {"Overview", "ClinicalVariants"}]
```

<!-- => an Association with only the keys "Overview", "ClinicalVariants" and "ReportFile" -->

The list also fixes the order, so naming the sections in a different order reorders both the structured result and the rendered document:

```wl
GenomeReport[hg, "Sections" -> {"CarrierStatus", "Overview"}]
```

<!-- => an Association with the keys "CarrierStatus", "Overview" and "ReportFile", in that order -->

### "Language"

The whole-genome callset, whose Ancestry section is served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

By default (`"English"`) the rendered HTML document is written in English. Pass `"Russian"` to write the document in Russian instead. Only the rendered file differs: the structured result keeps its English section keys and values, so downstream code is language-independent:

```wl
ru = GenomeReport[subject, "Language" -> "Russian", "Sections" -> {"Overview", "Ancestry"}]
```

<!-- => the same Association the English report gives: the keys "Overview", "Ancestry" and "ReportFile", with English values -->

The Russian document is written UTF-8 with `<html lang="ru">`, at the same path as the English one:

```wl
ru["ReportFile"]
```

<!-- => the path of the written report -->

Section titles, the per-section plain-language intros, field labels, table headers, the caveat block, the polygenic-risk percentile bands and interpretation sentences, the glossary appendix (title, category names, and definitions), and controlled-vocabulary data terms (metabolizer phenotypes, carrier classifications, zygosity, superpopulation names, and the like) are translated; scientific identifiers (gene symbols, rsIDs, star-allele diplotypes, haplogroup labels, PGS IDs, drug names, and free-text catalog trait strings) are left as-is.

## Possible Issues

The demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

A `"Compute"` value that is neither `"Cached"`, `"All"`, nor a list of slot names issues [GenomeReport::badcompute]() and falls back to serving every section from the cache:

```wl
GenomeReport[hg, "Compute" -> "Everything"]
```

<!-- => the message GenomeReport::badcompute is issued and the full section-keyed Association is given -->

A `"Sections"` list that names no known section issues [GenomeReport::nosections]() and falls back to the full ordered section list, rather than giving an empty report:

```wl
GenomeReport[hg, "Sections" -> {"Karyotype"}]
```

<!-- => the message GenomeReport::nosections is issued and the full section-keyed Association is given -->

A `"Language"` other than `"English"` or `"Russian"` issues [GenomeReport::badlang]() and the document is rendered in English, at the usual path:

```wl
GenomeReport[hg, "Language" -> "German"]["ReportFile"]
```

<!-- => the path of the written report -->

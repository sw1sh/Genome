---
Template: Symbol
Name: PharmacogenomicProfile
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/PharmacogenomicProfile
Keywords: [pharmacogenomics, pharmacogenetics, CPIC, PharmVar, PharmGKB, star allele, diplotype, metabolizer phenotype, CYP2C19, CYP2C9, CYP2D6, VKORC1, TPMT, DPYD, SLCO1B1, drug response, HumanGenome, GRCh37]
SeeAlso: [HumanGenome, ImportVCF, ClinVarHits, CarrierStatus, GWASAssociations, GenotypeLookup]
RelatedGuides: [Genome]
---

## Usage

<code>[PharmacogenomicProfile]()[*hg*]</code> calls the subject's star-allele diplotypes for the major CPIC pharmacogenes of a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg*, translates them to metabolizer phenotypes, attaches CPIC drug-response guidance, and gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Pharmacogenomics"` slot holds a [Tabular]() with columns `Gene`, `Diplotype`, `Phenotype`, `ActionableDrug`, `CPICGuidance`, `CPICLevel`, `ActivityScore`, and `Confidence`.

<code>[PharmacogenomicProfile]()[*hg*, *opts*]</code> calls diplotypes with the options below.

## Details & Options

- The result is decision-support information for discussion with a clinician or pharmacist. It is not a prescription and not a clinical-grade test result.
- `PharmacogenomicProfile` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: it gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"Pharmacogenomics"` annotation slot populated and `References["CPICVersion"]` set, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot untouched.
- The genes covered are the highest-value, SNV-callable CPIC pharmacogenes: CYP2C19, CYP2C9, VKORC1, TPMT, SLCO1B1, DPYD, CYP3A5, UGT1A1, NUDT15, CYP2B6, and the SNV-callable subset of CYP2D6.
- The data sources are the CPIC ([cpicpgx.org](https://cpicpgx.org/genes-drugs/)) allele-definition, allele-function, diplotype-phenotype, gene-drug pair and recommendation tables, read live from the CPIC PostgREST API ([api.cpicpgx.org/v1](https://api.cpicpgx.org/v1/)). PharmVar ([pharmvar.org](https://www.pharmvar.org/)) is the underlying allele-definition authority and PharmGKB ([pharmgkb.org](https://www.pharmgkb.org/)) the underlying knowledge base; CPIC is the guidance source. On first use the tables are downloaded and reduced to a compact per-gene structure under `data/references/cpic/` (git-ignored), and the reduced file is reused afterwards. A [PharmacogenomicProfile::download]() message announces the fetch, and [PharmacogenomicProfile::noref]() is issued if it fails.
- CPIC publishes allele-definition coordinates on GRCh38 only, while the personal genome is GRCh37/hg19. Each defining SNV's rsID is resolved to its GRCh37 position through the Ensembl GRCh37 REST endpoint ([grch37.rest.ensembl.org](https://grch37.rest.ensembl.org/)), preferring the primary-assembly mapping over an ALT / patch scaffold (the CYP2D6 rsIDs also map to `HSCHR22_2_CTG1`). The resolved coordinates are cached in the same reduced file, so the join needs no liftover.
- The subject is read at those GRCh37 positions through the tabix index (`bcftools view -R` over a positions file), so the multi-gigabyte source is never scanned end to end. The read requires `bcftools` on the `PATH` and a `.tbi` index beside the subject VCF; without both, [PharmacogenomicProfile::noref]() is issued and <code>[$Failed]()</code> given.
- Diplotypes are called phasing-free: candidate alleles are the reference allele plus every non-structural star allele all of whose defining variant bases the subject carries, and the best-scoring unordered pair (the most defining sites matched, then the most parsimonious) is chosen. Genotypes are compared as bases rather than as REF/ALT indices, so diplotype calling is robust to the GRCh37 / GRCh38 reference-allele flip that occurs at some positions.
- CYP2D6 copy-number and hybrid alleles (whole-gene deletions and duplications, `*5` and `*xN`) are not detectable from a SNP VCF; only the SNV-callable star alleles are called, and every CYP2D6 row carries a `CYP2D6 SNV-only` caveat in its `Confidence`. A defining site that is absent from the subject read lowers the `Confidence` flag to `Reduced confidence: k of m defining sites not read`, and an unphased genotype that fits more than one diplotype is flagged `ambiguous`. Because personal genomes are typically imputed, most common star-allele-defining SNPs are well covered, but an imputed genotype is a statistical call, not a direct read.
- The diplotype is mapped to a metabolizer phenotype through the CPIC diplotype-phenotype table (`Normal Metabolizer`, `Intermediate Metabolizer`, `Poor Metabolizer`, `Rapid Metabolizer`, `Ultrarapid Metabolizer`, …). For genes with a CPIC activity score (CYP2C9, DPYD, CYP2D6) the `ActivityScore` column carries it. VKORC1 has no CPIC diplotype-phenotype table, since it is not a metabolizer; its warfarin-sensitivity phenotype (`Normal`, `Increased` or `Highly increased warfarin sensitivity`) follows from the count of VKORC1 −1639G>A promoter-variant alleles carried, per the CPIC warfarin guideline. SLCO1B1 phenotypes use function terms (`Normal Function`, `Decreased Function`, `Poor Function`).
- The guidance attached is the CPIC actionable drug set for the gene, restricted to level-A, guideline-backed gene-drug pairs, with one row per gene and actionable drug. `CPICGuidance` is the CPIC recommendation for the subject's single-gene phenotype, taken from the CPIC recommendation table; for a multi-gene drug such as warfarin, which also needs CYP2C9, or for a phenotype without a tabulated single-gene recommendation, the guidance is a pointer to the CPIC guideline. `CPICLevel` is the CPIC pair level. A gene with no level-A actionable drug still contributes one row, so every covered gene appears.
- Results are cached in a per-subject sidecar `data/<subject>/interpretations/pharmacogenomics.tabular` (Parquet) plus its version marker, keyed by the reduced CPIC data version, so the full table persists across kernel sessions. A repeat rehydrates that sidecar and re-applies the `"Genes"` view over the hydrated full table rather than rereading the genome, and reading an already-populated slot is immediate.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Genes"` | [Automatic]() | [Automatic]() reports every covered gene; a gene name or list of names restricts the returned view (the sidecar still stores the full set) |
| `"Reference"` | [Automatic]() | [Automatic]() downloads and reduces the CPIC tables under `data/references/cpic/`; a directory path uses a prepared `cpic_reduced.wxf` already present there |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `PharmacogenomicProfile` reads:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Calling the star-allele diplotypes reads the subject at the CPIC defining positions through the tabix index and, on first use, downloads and reduces the CPIC tables; later calls for the same subject are served from a per-subject sidecar. `"Genes"` restricts the call to the named genes, and the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Pharmacogenomics"` slot is filled:

```wl
pgx = PharmacogenomicProfile[subject, "Genes" -> {"CYP2D6", "TPMT"}]
```

The slot holds a [Tabular]() with one row per gene and actionable drug and a fixed column set, the same for every subject: `Gene`, `Diplotype`, `Phenotype`, `ActionableDrug`, `CPICGuidance`, `CPICLevel`, `ActivityScore` and `Confidence`. Both genes are called `*1/*1`, a Normal Metabolizer, and `Confidence` qualifies each call: an imputed callset carries few of the star-allele-defining sites, and the string says how many were read - 113 of CYP2D6's 128 defining sites were not read, and none of TPMT's were read at all. CYP2D6 additionally warns that copy-number and hybrid alleles (`*5`, `*xN`) leave no SNV signature and are invisible to a SNP callset:

```wl
pgx["Pharmacogenomics"] // Dataset
```

<!-- => a Tabular of CYP2D6 and TPMT rows, one per actionable drug: Diplotype *1/*1 and Phenotype Normal Metabolizer for both; Confidence "Reduced confidence: 113 of 128 defining sites not read; CYP2D6 SNV-only: CNV / hybrid alleles (e.g. *5, *xN) not detectable" on the CYP2D6 rows and "No defining sites read" on the TPMT rows -->

Without `"Genes"` the panel spans all eleven covered genes - CYP2B6, CYP2C19, CYP2C9, CYP2D6, CYP3A5, DPYD, NUDT15, SLCO1B1, TPMT, UGT1A1 and VKORC1 - as the level-A gene-drug pairs across them plus one row for each covered gene that has no actionable drug, so every covered gene appears whatever was called for it. The CPIC data version the diplotypes were called against is recorded in the `References` sub-[Association](), as the version string of the reduced CPIC data the call read:

```wl
pgx["References", "CPICVersion"]
```

<!-- => "CPIC-6cdmaj4wrvf" -->

The called genome is a new value and the one that was read is left alone, so its own slot still reads [Missing]()`["NotComputed"]`:

```wl
subject["Pharmacogenomics"]
```

<!-- => Missing["NotComputed"] -->

---

The options the call takes:

```wl
Options[PharmacogenomicProfile]
```

<!-- => {"Genes" -> Automatic, "Reference" -> Automatic} -->

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

The genome's own reference-version map has a key for every interpretation operator's data source. `CPICVersion` and `PharmGKBVersion` are the two a pharmacogenomic call fills, and until one has run both read [Missing]()`["NotComputed"]`:

```wl
hg["References"]
```

Calling the diplotypes reads an indexed subject at the CPIC defining positions and, on first use, downloads the CPIC tables. It gives back a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Pharmacogenomics"` slot holds one row per gene and actionable drug:

```wl
#| eval: false
pgx = PharmacogenomicProfile[hg]
```

Each row pairs a gene's phenotype with one actionable, level-A CPIC drug and the guidance CPIC gives for that phenotype. Where a drug is dosed from more than one gene - warfarin, which also needs CYP2C9 - `CPICGuidance` is a pointer to the guideline instead of a single-gene recommendation, so the VKORC1 warfarin row reads `"Consult the CPIC guideline (phenotype-specific or multi-gene dosing)"` at `CPICLevel` `"A"` for every subject:

```wl
#| eval: false
Select[Normal[pgx["Pharmacogenomics"]], #Gene === "VKORC1" &][[1, {"Gene", "ActionableDrug", "CPICGuidance", "CPICLevel"}]]
```

The per-subject sidecar keeps the full table across kernel sessions, so a repeat rehydrates it rather than rereading the VCF. The genome it gives back is identical to its argument, and `===` between the two is [True]():

```wl
#| eval: false
PharmacogenomicProfile[pgx] === pgx
```

---

The whole-genome callset, indexed and served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Its profile, restricted to two genes:

```wl
pgx = PharmacogenomicProfile[subject, "Genes" -> {"CYP2D6", "TPMT"}]
```

A successful call writes its data version into the reference-version map under both `CPICVersion` and `PharmGKBVersion`, beside the keys the other interpretation operators set:

```wl
pgx["References"]
```

Rows are ordered by gene and then by actionable drug, so every gene's rows are contiguous and `OrderedQ` over the gene column is [True]():

```wl
OrderedQ[Normal[pgx["Pharmacogenomics"]][[All, "Gene"]]]
```

<!-- => True -->

`Confidence` is never left empty: a call with nothing to qualify reads `Called`, and every other value adds its caveats to that, so every entry in the column is a string:

```wl
AllTrue[Normal[pgx["Pharmacogenomics"]][[All, "Confidence"]], StringQ]
```

<!-- => True -->

## Options

### "Genes"

By default every covered gene is reported:

```wl
OptionValue[PharmacogenomicProfile, "Genes"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Name a single gene to restrict the returned view to it. The restriction is a view over the cached table, not a smaller computation - the sidecar still holds every gene, and an unrestricted repeat is served in full from it - and it leaves that gene as the only value in the gene column, with one row per actionable drug:

```wl
PharmacogenomicProfile[subject, "Genes" -> "CYP2D6"]["Pharmacogenomics"] // Dataset
```

<!-- => the CYP2D6 rows alone -->

A list of names keeps those genes, in the table's own gene order rather than the order they were named in, so the CYP2D6 rows still come before the TPMT rows:

```wl
PharmacogenomicProfile[subject, "Genes" -> {"TPMT", "CYP2D6"}]["Pharmacogenomics"] // Dataset
```

<!-- => the CYP2D6 rows followed by the TPMT rows -->

### "Reference"

By default the CPIC tables are downloaded and reduced under `data/references/cpic/`:

```wl
OptionValue[PharmacogenomicProfile, "Reference"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Point `"Reference"` at a directory that already holds a prepared `cpic_reduced.wxf` to reuse it and skip the download; the call then gives the same [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the slot filled:

```wl
pinned = PharmacogenomicProfile[subject, "Genes" -> {"CYP2D6", "TPMT"}, "Reference" -> "data/references/cpic"]
```

A prepared reference pins the data version, so the version recorded in `References` is the one that directory holds:

```wl
pinned["References", "CPICVersion"]
```

<!-- => "CPIC-6cdmaj4wrvf" -->

## Possible Issues

The demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The subject is read through the tabix index, so the call needs `bcftools` on the `PATH` and a `.tbi` index beside the VCF. The demonstration file is a plain uncompressed VCF with no index; the operator says so and gives back <code>[$Failed]()</code> rather than scanning the file end to end:

```wl
PharmacogenomicProfile[hg]
```

<!-- => the message PharmacogenomicProfile::noref is issued and the result is $Failed -->

The first call on an indexed genome announces the one-time CPIC fetch with its own message, whose text names the API it reads and where the reduced tables are cached:

```wl
PharmacogenomicProfile::download
```

<!-- => the text of the PharmacogenomicProfile::download message -->

---

The whole-genome callset, indexed and served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

On an indexed genome the call gives back the profile, whose `Confidence` column qualifies every row:

```wl
pgx = PharmacogenomicProfile[subject, "Genes" -> {"CYP2D6", "TPMT"}]
```

CYP2D6 is called from SNVs alone. Whole-gene deletions and duplications (`*5`, `*xN`) leave no SNV signature in a SNP VCF, so every CYP2D6 row says so in its `Confidence`, whatever diplotype was called; a check over those rows is [True]() for every subject:

```wl
AllTrue[Select[Normal[pgx["Pharmacogenomics"]], #Gene === "CYP2D6" &][[All, "Confidence"]], StringContainsQ["CYP2D6 SNV-only"]]
```

<!-- => True -->

The remaining flags depend on the subject's own read rather than on the gene. A gene whose defining SNVs are not all present in the VCF is prefixed `Reduced confidence: k of m defining sites not read`, a gene with no defining SNV present at all reads `No defining sites read`, and an unphased genotype that fits more than one diplotype is flagged `ambiguous`, with only the best-scoring of the candidates reported as its diplotype. Counted over the column, every CYP2D6 row carries the reduced-confidence prefix ahead of the SNV-only caveat, since an imputed callset holds few of the gene's 128 defining sites, and every TPMT row carries the no-sites string; neither call is ambiguous:

```wl
Counts[Lookup[Normal[pgx["Pharmacogenomics"]], "Confidence"]]
```

<!-- => an Association from the two Confidence strings to their row counts, one row per actionable drug -->

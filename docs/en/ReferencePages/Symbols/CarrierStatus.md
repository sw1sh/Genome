---
Template: Symbol
Name: CarrierStatus
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/CarrierStatus
Keywords: [carrier status, carrier screening, recessive, mode of inheritance, autosomal recessive, X-linked, dominant, PanelApp, ClinVar, HumanGenome, GRCh37, reproductive risk, zygosity]
SeeAlso: [HumanGenome, ClinVarHits, ImportVCF, Genome, AlphaMissenseScores, TraitAssociations]
RelatedGuides: [Genome]
---

## Usage

<code>[CarrierStatus]()[*hg*]</code> reports recessive-disease carrier status for a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg*: it takes the subject's ClinVar Pathogenic / Likely-pathogenic hits, annotates each gene with its mode of inheritance, and gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Carrier"` slot holds a [Tabular]() that classifies every hit.

<code>[CarrierStatus]()[*hg*, *opts*]</code> reports with the options below.

## Details & Options

- `CarrierStatus` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"Carrier"` annotation slot populated and `References["CarrierGenePanelVersion"]` set, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot untouched.
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) matches no definition, so `CarrierStatus` returns unevaluated. A plain [Genome](paclet:WolframInstitute/Genome/ref/Genome) is such an argument.
- The variant layer comes from [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits), which supplies the subject's carried Pathogenic / Likely-pathogenic variants (the genotype-aware join on `(CHROM, POS, REF, ALT)`). ClinVar is never re-downloaded; once the GRCh37 P/LP reference is prepared under `data/references/`, the hits are served from that reference and the per-subject sidecar. The resulting [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) therefore carries both the `"ClinVarHits"` and the `"Carrier"` slots.
- The mode-of-inheritance (MOI) source is Genomics England PanelApp ([panelapp.genomicsengland.co.uk](https://panelapp.genomicsengland.co.uk/)), a curated collection of diagnostic-grade gene panels. For each distinct gene in the subject's hits, `CarrierStatus` queries the PanelApp REST API (`/api/v1/genes/?entity_name=`) and takes the majority MOI across the panels the gene appears in. PanelApp's verbose MOI strings (`"BIALLELIC, autosomal or pseudoautosomal"`, `"MONOALLELIC, …"`, `"X-LINKED: …"`, `"BOTH monoallelic and biallelic, …"`, `"MITOCHONDRIAL"`) are folded to the classifier terms `"Autosomal recessive"`, `"Autosomal dominant"`, `"X-linked"`, `"Autosomal recessive/dominant"`, `"Mitochondrial"`, and `"Unknown"`.
- Both reference layers need the network on first use: the ClinVar release for the variants and the PanelApp API for the modes of inheritance.
- Each hit is assigned a `CarrierClassification` from a fixed vocabulary:
    - `"Carrier"` - a heterozygous variant at an autosomal-recessive gene (or a mono/biallelic gene). This is a healthy carrier: one recessive allele carries no disease for the subject, but it matters for reproduction (a child is at risk only if the reproductive partner also carries a pathogenic allele in the same gene).
    - `"Homozygous (possible affected)"` - a homozygous variant at a recessive gene. Two pathogenic alleles can cause recessive disease, so this row is flagged for clinical review rather than reported as mere carrier status.
    - `"X-linked"` - a carried variant at an X-linked gene. Interpretation is sex-dependent: hemizygous (and typically affected) in males, usually carrier in females. The `Zygosity` column reports the raw genotype so the sex-specific reading is explicit.
    - `"Dominant finding"` - a carried variant at a dominant gene. This is a secondary finding rather than carrier status, and is included only for completeness (see `"IncludeDominant"`).
    - `"Unclassified"` - the gene has no informative MOI in PanelApp (or is mitochondrial), so no carrier judgment is made.
- The one-time PanelApp lookups are cached as a small `gene -> MOI` map under `data/references/panelapp_carrier_moi.tsv`, with a version marker in `data/references/panelapp_carrier_moi.version` (for example `PanelApp-GEL-2026-07-04`). A [CarrierStatus::download]() message announces the first lookup; later runs read the cached map and never re-query the API. [CarrierStatus::noref]() is issued if neither the ClinVar reference nor the PanelApp map can be obtained.
- The resulting [Tabular]() has the columns `Gene`, `VariantID` (the canonical `chr-pos-ref-alt` string), `RsID`, `Zygosity` (`"Heterozygous"` or `"Homozygous"`), `Inheritance` (the normalized MOI), `CarrierClassification`, `ClinicalSignificance` (from ClinVar `CLNSIG`), `Condition` (from ClinVar `CLNDN`), `ReviewStatus` (from ClinVar `CLNREVSTAT`), `PopulationAF`, and `ImputationQuality`. The `PopulationAF` (gnomAD v2.1.1 global allele frequency) and `ImputationQuality` columns are inherited from [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits). Rows are sorted so `"Homozygous (possible affected)"` and `"Carrier"` rows come first (most reproductively and clinically relevant), then by gene.
- A frequency filter is essential. ClinVar aggregates submitted assertions and still labels some common polymorphisms Pathogenic / Likely-pathogenic, so an unfiltered carrier list contains false positives: a common variant flagged only by a weak or legacy ClinVar assertion is almost always benign, yet it would otherwise appear as a `"Carrier"` (or, when homozygous, a `"Homozygous (possible affected)"`). Because carrier screening wants rare variants, `CarrierStatus` applies a `"MaxPopulationAF"` filter whose default is `0.01` - unlike [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits), whose default stays [Automatic]() (all hits). At that default, a homozygous common variant no longer shows as possible-affected, and a common carrier row is dropped, while genuine rare carriers are retained.
- Results are cached per subject. A sidecar `data/<subject>/interpretations/carrier-status.tabular` (Parquet) plus its marker persists the classification across kernel sessions and hydrates a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) when the marker still matches (it keys on the panel version, the ClinVar release, and the frequency-source version). The sidecar stores the full (all-classifications, all-frequency) table, so changing `"IncludeDominant"` or `"MaxPopulationAF"` never forces a recompute - both filters are re-applied to the full result each time.
- A heterozygous carrier is healthy. `CarrierStatus` is reproductive-risk information built from public gene panels and ClinVar assertions; it is not clinical-grade, does not resolve phase or compound heterozygosity, and is not a diagnosis. Any actionable finding must be confirmed by an accredited clinical laboratory and a genetics professional.

The following options can be given:

| | | |
|--------|---------------|-|
| `"Panel"` | [Automatic]() | [Automatic]() fetches and caches the PanelApp `gene -> MOI` map under `data/references/`; a directory path uses a prepared `panelapp_carrier_moi.tsv` already present there |
| `"IncludeDominant"` | [True]() | [True]() keeps the `"Dominant finding"` secondary-finding rows; [False]() restricts the table to the carrier / recessive (and X-linked / unclassified) rows |
| `"MaxPopulationAF"` | `0.01` | Drops carriers whose gnomAD `PopulationAF` exceeds the threshold (a `Missing` AF is treated as rare / unknown and kept). The `0.01` default suppresses common polymorphisms; set [Automatic]() to keep every classified hit regardless of frequency |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `CarrierStatus` annotates, reading the build and the sample name from the file's own header:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Reporting carrier status gives back a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"Carrier"` slot filled and every other slot carried through. The first call prepares the ClinVar release and queries PanelApp for the modes of inheritance, and later calls for the same subject are served from a per-subject sidecar:

```wl
cs = CarrierStatus[subject]
```

The slot holds a [Tabular]() with one classified row per surviving ClinVar hit, and a fixed column set - `Gene`, `VariantID`, `RsID`, `Zygosity`, `Inheritance`, `CarrierClassification`, `ClinicalSignificance`, `Condition`, `ReviewStatus`, `PopulationAF` and `ImputationQuality`. The panel version behind the mode-of-inheritance annotation is recorded in the `References` sub-Association as a marker of the form `PanelApp-GEL-<date>`; the key is not among the references a fresh [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) carries, and `CarrierStatus` adds it:

```wl
cs["References", "CarrierGenePanelVersion"]
```

<!-- => the PanelApp-GEL panel version marker the report ran against, of the form "PanelApp-GEL-2026-07-04" -->

The reported genome is a new value and the one it was computed from is left alone, so its own slot still reads [Missing]()`["NotComputed"]`, as every interpretation slot does until its method has run:

```wl
subject["Carrier"]
```

<!-- => Missing["NotComputed"] -->

Reporting on a genome whose slot is already filled rehydrates the cached classification instead of recomputing it, so the same report comes back with no second PanelApp query:

```wl
CarrierStatus[cs]
```

---

Three options control the report. Two of them take the usual [Automatic]() and [True](); the third, the frequency threshold, carries a number:

```wl
Options[CarrierStatus]
```

<!-- => {"Panel" -> Automatic, "IncludeDominant" -> True, "MaxPopulationAF" -> 0.01} -->

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

Zygosity is what separates a carrier from a possible-affected row: at a recessive gene a heterozygous variant classifies as `"Carrier"` and a homozygous one as `"Homozygous (possible affected)"`. The genotype classes of the demo genome are the raw material for that decision, and the homozygous-reference row is not a hit at all, so it never reaches the classifier:

```wl
VariantSummary[hg] // Dataset
```

The variant layer comes from [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits), so a genome reported on carries both slots: `"ClinVarHits"` with every carried Pathogenic / Likely-pathogenic variant, unfiltered, and `"Carrier"` with the classified and frequency-filtered subset. Neither is populated before the report runs, and one call fills both. The demo genome carries no ClinVar Pathogenic / Likely-pathogenic record, so nothing reaches the classifier, the report needs no PanelApp lookup, and the variant layer's slot is an empty [Tabular]() that shows only its columns - the twelve that [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) fills:

```wl
CarrierStatus[hg]["ClinVarHits"] // Dataset
```

The `"Carrier"` slot is the classified subset, empty for the same reason, with the eleven columns a report with hits fills. Its `CarrierClassification` column is always drawn from the five fixed terms, and `Inheritance` from six: PanelApp's verbose MOI strings are folded to `"Autosomal recessive"`, `"Autosomal dominant"`, `"X-linked"`, `"Autosomal recessive/dominant"`, `"Mitochondrial"` or `"Unknown"` before any classification is made, so a report's labels are always drawn from those two closed sets. A carrier table is identifying information about its subject; a tally of its `CarrierClassification` column summarizes a report without naming a gene:

```wl
CarrierStatus[hg]["Carrier"] // Dataset
```

## Options

### "Panel"

By default the PanelApp `gene -> MOI` map is fetched per gene and cached under `data/references/`:

```wl
Lookup[Options[CarrierStatus], "Panel"]
```

<!-- => Automatic -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Pointing `"Panel"` at a directory that already holds a prepared `panelapp_carrier_moi.tsv` reuses it and skips the lookup:

```wl
CarrierStatus[subject, "Panel" -> "data/references"]
```

### "IncludeDominant"

The dominant-gene rows are secondary findings rather than carrier status, and are kept by default:

```wl
Lookup[Options[CarrierStatus], "IncludeDominant"]
```

<!-- => True -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

`"IncludeDominant" -> False` drops the dominant rows and keeps only the carrier / recessive report. The sidecar stores the full classification and the filter is re-applied to it on the way out, so the change never forces a recompute:

```wl
CarrierStatus[subject, "IncludeDominant" -> False]
```

### "MaxPopulationAF"

Carrier screening wants rare variants, so `CarrierStatus` filters out common polymorphisms by default - the one place where its default differs from the [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) layer it is built on, which keeps every hit:

```wl
{Lookup[Options[CarrierStatus], "MaxPopulationAF"], Lookup[Options[ClinVarHits], "MaxPopulationAF"]}
```

<!-- => {0.01, Automatic} -->

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Relaxing the threshold admits the common ClinVar-pathogenic variants the default suppresses, and [Automatic]() keeps every classified hit regardless of frequency:

```wl
CarrierStatus[subject, "MaxPopulationAF" -> 1.0]
```

## Possible Issues

A carrier report is only as good as its frequency filter. A genome read from the demonstration file:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Counting the classified hits above the `0.01` screening threshold gives the number of rows the default removes from a report, and is why an unfiltered carrier list is misleading:

```wl
#| eval: false
Count[Normal[CarrierStatus[hg, "MaxPopulationAF" -> 1.0]["Carrier"]][[All, "PopulationAF"]], af_ ? NumericQ /; af > 0.01]
```

A gene with no informative mode of inheritance in PanelApp is classified `"Unclassified"` rather than guessed at, so a carried pathogenic variant can appear in the table with no carrier judgment attached - and a homozygous hit at such a gene is reported as unclassified rather than as possible-affected.

---

The report needs the ClinVar reference and the PanelApp map. If the ClinVar preparation step fails, or the PanelApp API cannot be reached, the report gives `$Failed` after issuing [CarrierStatus::noref]():

```wl
CarrierStatus::noref
```

<!-- => "CarrierStatus could not obtain the PanelApp mode-of-inheritance map or the ClinVar reference; the PanelApp lookup or the ClinVar preparation step failed.  Ensure the network is reachable (https://panelapp.genomicsengland.co.uk) and that ClinVarHits succeeds." -->

---

`CarrierStatus` is defined for a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) only; [HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ) is the test it applies to its argument. Importing with `"Human" -> False` gives a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), which carries no interpretation layer:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

Such an argument matches no definition, so the call comes back unevaluated - the genome is still sitting inside a `CarrierStatus` expression rather than classified:

```wl
CarrierStatus[g]
```

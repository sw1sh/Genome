---
Template: Symbol
Name: AncestryEstimate
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/AncestryEstimate
Keywords: [ancestry, admixture, super-population, continental ancestry, 1000 Genomes, allele frequency, AIM, ancestry-informative markers, HumanGenome, GRCh37, EUR, AFR, EAS, SAS, AMR]
SeeAlso: [HumanGenome, ImportVCF, ChromosomalSex, HaplogroupCall, Genome]
RelatedGuides: [Genome]
---

## Usage

<code>[AncestryEstimate]()[*hg*]</code> estimates continental (super-population) genetic ancestry for a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* against the 1000 Genomes phase 3 panel, giving a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Ancestry"` slot holds the estimate.

<code>[AncestryEstimate]()[*hg*, *opts*]</code> estimates with the options below.

## Details & Options

- `AncestryEstimate` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: it gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"Ancestry"` annotation slot populated and `References["ThousandGenomesPanel"]` set, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome), the argument itself, and every other slot untouched.
- The estimate is an [Association]() with the keys `"Superpopulation"` (the best of the five 1000 Genomes super-populations), `"SuperpopulationFractions"` (an [Association]() of `code -> fraction` over `EAS`, `AMR`, `AFR`, `EUR`, `SAS`, summing to about 1), `"NearestPopulations"` (the super-populations ranked by decreasing fraction), `"PrincipalComponents"`, `"Method"`, and `"NMarkersUsed"`.
- The resolution is continental to coarse sub-continental, not country or ethnicity. The 1000 Genomes super-populations separate African, admixed-American, East Asian, European, and South Asian ancestry robustly, and a within-continent lean shows up in the fraction breakdown. Nationality and fine sub-continental population are out of reach: they need a fine private reference panel and genotype-level principal-component projection, which an allele-frequency panel does not carry, so `"PrincipalComponents"` is [Missing]()`["NotApplicable"]`. Read the result as "a European-ancestry subject" and its fraction breakdown, never as "37 % of country X".
- A one-time preparation reduces the 1000 Genomes phase 3 sites VCF to an ancestry-informative marker panel: biallelic common SNVs (global allele frequency 0.05 to 0.95) whose five super-population allele frequencies span at least 0.25, thinned to one marker per 50 kb to reduce linkage, each stored with its five super-population allele frequencies.
- The subject's alternate-allele dosage (0, 1, 2) is read at the panel positions and the dosage vector is fit by non-negative least squares to a simplex mixture of the five super-population allele-frequency profiles (`f >= 0`, `Total[f] == 1`). The largest fitted fraction names `"Superpopulation"`, and the fit is reported as `"Method" -> "1000G-Superpopulation-AF-NNLS"`.
- The panel and the phase 3 sites VCF are downloaded and prepared once under `data/references/ancestry/` (about 1.4 GB fetched, reduced to a compact panel). An `AncestryEstimate::download` message announces the fetch. `AncestryEstimate::noref` is issued and <code>[$Failed]()</code> given when the download, the reduction, a required tool, or the subject `.tbi` index is missing, or when fewer than 20 panel markers are usable in the subject.
- The subject read is restricted to the panel positions through the tabix index (`bcftools view -R`), so the multi-gigabyte source is never scanned end to end.
- Results are cached twice. The in-memory slot is reused when the stored `References["ThousandGenomesPanel"]` matches the prepared panel. A per-subject sidecar `<subject>/interpretations/ancestry.wxf` beside the subject file plus its version marker persists the estimate across kernel sessions, and a panel rebuild changes the version so a stale estimate is never reused.
- An argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) returns unevaluated.

The following option can be given:

| | | |
|-|-|-|
| `"Reference"` | [Automatic]() | [Automatic]() downloads and prepares the 1000 Genomes panel under `data/references/ancestry/`; a directory path uses a prepared `aim_panel_GRCh37.tsv` already present there |

## Basic Examples

The examples run on a small synthetic callset written to a temporary file. It has one sample column, ten data rows across chr1 and chr17, and the GRCh37 contig lengths the build inference reads:

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

A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), the input every interpretation method takes:

```wl
hg = ImportVCF[demoFile]
```

The `"Ancestry"` slot is the one an estimate fills, and on a genome that has not been estimated it is empty:

```wl
hg["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

---

A ten-row demo file falls far short of the twenty usable panel markers the fit needs, so a real estimate wants a whole-genome callset. This one is the anonymized 5.7-million-variant GRCh37 callset the paclet was developed against, kept beside the reference data as `data/subject_genome.vcf.gz`:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Estimating ancestry downloads and prepares the 1000 Genomes panel the first time it runs — roughly 1.4 GB fetched and reduced — and later estimates for the same subject are served from a per-subject sidecar. It gives back a genome of the same kind, now carrying the estimate in its `"Ancestry"` slot:

```wl
anc = AncestryEstimate[subject]
```

The headline result is the best-fitting super-population, one of the five 1000 Genomes codes `EAS`, `AMR`, `AFR`, `EUR` and `SAS`. It is a statement about continents, and the only honest way to read it is "a subject of European ancestry", never a country:

```wl
anc["Ancestry"]["Superpopulation"]
```

<!-- => "EUR" -->

Beneath the headline is the fraction breakdown, an [Association]() of the same five codes to fitted fractions summing to about 1. A subject with ancestry from one continent shows one fraction near 1 and the rest near 0; an admixed subject shows the mixture:

```wl
anc["Ancestry"]["SuperpopulationFractions"]
```

<!-- => <|"EAS" -> 0.0872, "AMR" -> 0.1061, "AFR" -> 0., "EUR" -> 0.7433, "SAS" -> 0.0634|> -->

A dominant `EUR` fraction with a long tail across the other codes is what a single-continent subject looks like under an allele-frequency fit: the non-European profiles still explain a little of the dosage vector. The tail is fitting noise, not evidence of admixture.

## Scope

A handle on the anonymized whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Once computed, an estimate is served from the per-subject sidecar:

```wl
anc = AncestryEstimate[subject]
```

The estimate records the fit, the markers behind it, and the method that produced it. Its keys are `"Superpopulation"`, `"SuperpopulationFractions"`, `"NearestPopulations"`, `"PrincipalComponents"`, `"Method"` and `"NMarkersUsed"`, and `"Method"` is always the string `"1000G-Superpopulation-AF-NNLS"`:

```wl
anc["Ancestry"]
```

The nearest super-populations are the fraction breakdown sorted by decreasing fraction, so the list is a ranking of continents and not of countries:

```wl
anc["Ancestry"]["NearestPopulations"]
```

<!-- => {"EUR", "AMR", "EAS", "SAS", "AFR"} -->

The number of panel markers the subject actually carried is recorded with the estimate; it tracks both the size of the prepared panel and the subject's callable coverage of it, and an estimate over fewer than 20 markers is refused rather than reported:

```wl
anc["Ancestry"]["NMarkersUsed"]
```

<!-- => 53222 -->

The panel version is pinned in the reference slot, where it keys both caches. Before an estimate it is empty:

```wl
subject["References", "ThousandGenomesPanel"]
```

<!-- => Missing["NotComputed"] -->

Afterwards it is a string of the form `1000G-phase3-AIM-` followed by the panel byte count:

```wl
anc["References", "ThousandGenomesPanel"]
```

<!-- => "1000G-phase3-AIM-2784993" -->

---

A genome imported with `"Human" -> False` stays a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), the handle without the interpretation layer:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

A plain genome has no annotation slot to fill, so it is outside the scope of `AncestryEstimate` and the call comes back unevaluated, the operator still wrapped around its argument:

```wl
AncestryEstimate[g]
```

## Options

### "Reference"

The default is [Automatic](), which downloads and prepares the panel under `data/references/ancestry/`:

```wl
Options[AncestryEstimate]
```

<!-- => {"Reference" -> Automatic} -->

---

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Point `"Reference"` at a directory that already holds a prepared `aim_panel_GRCh37.tsv` to reuse that panel and skip the download, which is how a second subject is estimated against the panel the first one built:

```wl
AncestryEstimate[subject, "Reference" -> "data/references/ancestry"]
```

## Properties and Relations

A handle on the demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Every reference an interpretation method pins travels in one slot of the genome, each empty until the method that fills it has run; `AncestryEstimate` is the one that writes `"ThousandGenomesPanel"`:

```wl
hg["References"]
```

A super-population estimate is genome-wide, where a haplogroup is a single uniparental lineage; the two live in different slots and are filled by different methods, [HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall) being the other one:

```wl
hg["Haplogroups"]
```

<!-- => Missing["NotComputed"] -->

A handle on the whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The estimate over it:

```wl
anc = AncestryEstimate[subject]
```

The estimate travels in a new value and the genome that was interpreted is left alone, so the `"Ancestry"` slot of `subject` still reads [Missing]()`["NotComputed"]`:

```wl
subject["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

Estimating again on a genome whose slot is already filled reuses it instead of refitting, giving back the very same value:

```wl
AncestryEstimate[anc] === anc
```

<!-- => True -->

## Possible Issues

The demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The panel carries allele frequencies rather than reference genotypes, so there is no genotype-level projection to report and `"PrincipalComponents"` is always [Missing]()`["NotApplicable"]`; a fine-scale, PCA-based estimate needs a different reference:

```wl
#| eval: false
AncestryEstimate[hg]["Ancestry"]["PrincipalComponents"]
```

The estimate is a fit over many thousands of ancestry-informative markers, so a small callset cannot support one. The demo file carries eight variant rows after the default filters, against a floor of 20 usable panel markers:

```wl
hg["VariantCount"]
```

<!-- => 8 -->

---

Too few markers, a missing tool, a missing subject index and a failed download all end the same way, in one message and <code>[$Failed]()</code>:

```wl
AncestryEstimate::noref
```

<!-- => the text of the message AncestryEstimate issues, after which it gives $Failed -->

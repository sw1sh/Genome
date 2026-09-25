---
Template: Symbol
Name: TraitAssociations
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/TraitAssociations
Keywords: [SNPedia, trait, magnitude, repute, genotype, Promethease, HumanGenome, GRCh37, strand, orientation, community annotation]
SeeAlso: [HumanGenome, ClinVarHits, AlphaMissenseScores, ImportVCF, Genome, GenotypeLookup]
RelatedGuides: [Genome]
---

## Usage

<code>[TraitAssociations]()[*hg*]</code> annotates the genotypes a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* carries against SNPedia's community-curated magnitude / repute / summary model and returns a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Traits"` slot holds a [Tabular]() of the annotated genotypes.

<code>[TraitAssociations]()[*hg*, *opts*]</code> annotates with the options below.

## Details & Options

- `TraitAssociations` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: the result is a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the `"Traits"` annotation slot populated and `References["SNPediaCommit"]` set, while *hg*, the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and every other slot stay untouched.
- The data source is [SNPedia](https://www.snpedia.com/), a community-curated wiki that records, for each documented SNP, a per-genotype interpretation carrying a magnitude (a subjective 0 to 10 interestingness score, not a clinical measure), a repute (`"Good"`, `"Bad"`, or unset), and a one-line summary. This is the same model that the Promethease report tool aggregates.
- Every genotype is interpreted, the homozygous-reference genotype included. SNPedia documents the `(REF;REF)` genotype as its own page, so - unlike [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) and [AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores), which report only carried alternate alleles - `TraitAssociations` keeps a subject's `0/0` genotypes when SNPedia documents the SNP, reporting the `(REF;REF)` interpretation.
- The reference is the offline set of SNPedia-documented rsIDs (the `Category:Is_a_snp` membership, about 110000 SNPs), enumerated once through the MediaWiki API at `https://bots.snpedia.com/api.php` and cached as `data/references/snpedia_rsids.txt` with a snapshot marker `snpedia_rsids.commit`. The subject VCF is streamed once and restricted to the rows whose ID is in that set (all genotypes, `0/0` included), so the multi-gigabyte source is intersected offline. A [TraitAssociations::download]() message announces the one-time enumeration, and [TraitAssociations::noref]() is issued if the API is unreachable.
- For each intersected rsID the SNP page and the matching genotype page are fetched in batches of 50 titles per API query and cached as wikitext files under `data/references/snpedia-pages/`, so a repeated annotation and the sidecar build never re-hit the API.
- The subject's alleles and SNPedia's are reconciled by strand. The subject's VCF alleles are on the reference-forward (plus) strand, whereas SNPedia records each SNP's genotypes in its own `Orientation`. When the SNP page's `Orientation` is `minus`, `TraitAssociations` reverse-complements the subject's forward alleles before matching; otherwise it matches as-is. Either way the candidate genotype string is confirmed against the SNP page's own `geno` list, so allele ordering is resolved from SNPedia's ground truth rather than guessed. For example the MTHFR C677T SNP `Rs1801133` is `Orientation=minus`, so a subject's forward-strand heterozygous `G/A` genotype reconciles to SNPedia's `(C;T)` genotype. The limitation is that strand-ambiguous SNPs (`A/T` and `C/G`) cannot be resolved by strand alone and are matched by whichever oriented candidate SNPedia happens to document; indel genotypes (SNPedia's `D` / `I` notation) are out of scope and are skipped.
- The returned [Tabular]() has the columns `RsID`, `Genotype` (the subject's genotype in SNPedia `(A;G)` notation), `Magnitude` (the numeric 0 to 10 score, `0` when the genotype page records none), `Repute` (`"Good"`, `"Bad"`, or `"None"`), `Summary` (the genotype page's one-line summary), `URL` (the SNPedia genotype page), and `Category` (the SNP page's own topic summary, e.g. `"earwax"`). Rows are sorted by `Magnitude` descending, most notable first.
- The annotation slot holds the filtered view produced by the options in force. A per-subject sidecar `data/<subject>/interpretations/traits.tabular` (Parquet), together with its commit marker, persists the full unfiltered table across kernel sessions and hydrates a freshly constructed [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) while the commit still matches. Annotating a genome again rehydrates that sidecar and re-applies the filter, so changing `"MinMagnitude"` never re-fetches anything.
- SNPedia is community-curated and its magnitudes are subjective interestingness scores, not validated clinical scores. Most entries are non-medical traits (earwax type, caffeine metabolism, lactose tolerance, bitter-taste perception); a high magnitude means "many people find this genotype notable", not "medically significant". Treat the output as an exploratory annotation, not a diagnosis.

The following options can be given:

| | | |
|--------|---------------|-|
| `"MinMagnitude"` | `0` | keep only rows whose `Magnitude` is at least this value (for example `4` to keep only the more notable traits) |
| `"Reference"` | [Automatic]() | [Automatic]() enumerates and caches the SNPedia documented-rsID set under `data/references/`; a directory path uses a `snpedia_rsids.txt` already present there |

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to the [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) that `TraitAssociations` annotates:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Annotating gives back a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose icon carries the traits indicator and whose `"Traits"` slot holds a [Tabular]() with one row per SNPedia-documented genotype the subject has, a few thousand rows for a whole-genome subject. The first call enumerates SNPedia's documented-rsID set through the MediaWiki API, and later calls for the same subject are served from a per-subject sidecar:

```wl
tr = TraitAssociations[subject]
```

The SNPedia snapshot the annotation was made against is recorded in the `References` sub-Association, a marker naming the enumeration date and the number of documented rsIDs it found; before annotating there is no snapshot to record:

```wl
tr["References", "SNPediaCommit"]
```

<!-- => "SNPedia-2026-07-04-108873" -->

The rows are sorted by `Magnitude` descending, most notable first, and each carries SNPedia's `Repute` for the genotype: `"Good"`, `"Bad"`, or `"None"` when the genotype page files no repute. Counting that column over the whole table gives the shape of a healthy genome's annotation - most documented genotypes carry no repute at all, and the rest divide between the two:

```wl
Counts[Lookup[Normal[tr["Traits"]], "Repute"]]
```

<!-- => the row count under each repute, "None" the largest -->

The annotated genome is a new value and the one that was annotated is left alone, so its own slot still reads [Missing]()`["NotComputed"]`:

```wl
subject["Traits"]
```

<!-- => Missing["NotComputed"] -->

---

The slot is a [Tabular]() with a fixed column set. Two illustrative rows, invented rather than taken from any subject:

```wl
(exampleTraits = Tabular[{<|"RsID" -> "rs100", "Genotype" -> "(A;G)", "Magnitude" -> 2.5, "Repute" -> "Good", "Summary" -> "an illustrative one-line summary", "URL" -> "https://www.snpedia.com/index.php/Rs100(A;G)", "Category" -> "an illustrative topic"|>, <|"RsID" -> "rs150", "Genotype" -> "(T;T)", "Magnitude" -> 0., "Repute" -> "None", "Summary" -> "an illustrative one-line summary", "URL" -> "https://www.snpedia.com/index.php/Rs150(T;T)", "Category" -> "an illustrative topic"|>}]) // Dataset
```

Every annotation carries the same columns, in that order, and the same value types in every row - `Magnitude` numeric, the rest strings. Rows are sorted by `Magnitude` descending, most notable first. Homozygous genotypes are annotated too, `(REF;REF)` among them, which is not the case for [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) or [AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores); the second illustrative row is such a homozygous genotype, a `(T;T)`.

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

SNPedia documents SNPs and keys its genotype pages by rsID, so the annotation reads the subject at the rsIDs SNPedia documents and at nothing else: the demo genome's ref-confirming row at `chr1:200000` has no rsID and can never be looked up. An indel genotype - SNPedia's `D` / `I` notation - is out of scope and is skipped, so the deletion at `rs300` and the insertion at `rs1300` contribute nothing either, which leaves the six single-nucleotide substitutions as the rows the annotation could match at all:

```wl
Select[Normal[hg["Variants"]], Length[#ALT] == 1 && StringLength[#REF] == 1 && StringLength[First[#ALT]] == 1 &][[All, "ID"]]
```

<!-- => {"rs100", "rs150", "rs400", "rs1000", "rs1100", "rs1200"} -->

Every genotype at a documented SNP is interpreted, the homozygous-reference one included, since SNPedia documents the `(REF;REF)` genotype as a page of its own: `rs1100`, a `0/0` call, stays in that list where [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) and [AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores) would drop it. Four of the six are strand-ambiguous sites, complementary `A`/`T` or `C`/`G` pairs that no strand rule can orient, and such a site is matched by whichever oriented candidate SNPedia happens to document:

```wl
Select[Normal[hg["Variants"]], Length[#ALT] == 1 && MemberQ[{"AT", "TA", "CG", "GC"}, #REF <> First[#ALT]] &][[All, "ID"]]
```

<!-- => {"rs400", "rs1000", "rs1100", "rs1200"} -->

The whole-genome callset, whose annotation is served from its sidecar:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Its annotated genome:

```wl
tr = TraitAssociations[subject]
```

Annotating an already-annotated genome does not re-fetch anything: the full table is
rehydrated from the per-subject sidecar and the same options select the same rows, so the
same genome comes back with the same slot:

```wl
TraitAssociations[tr]
```

## Options

The two options and their defaults:

```wl
Options[TraitAssociations]
```

<!-- => {"MinMagnitude" -> 0, "Reference" -> Automatic} -->

### "MinMagnitude"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

`"MinMagnitude"` keeps the rows whose `Magnitude` is at least the given value, leaving
the more notable traits. Every surviving row clears the threshold, so the smallest
magnitude left is at least the cut, and any positive cut drops the rows whose genotype
page records no magnitude at all:

```wl
notable = TraitAssociations[subject, "MinMagnitude" -> 4]
```

The full table stays in the sidecar, so raising or lowering the threshold on an
already-annotated genome re-filters the cached table and repeats no fetch:

```wl
TraitAssociations[notable, "MinMagnitude" -> 8]
```

### "Reference"

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

By default the SNPedia documented-rsID set is enumerated and cached under
`data/references/`. Pointing `"Reference"` at a directory that already holds
`snpedia_rsids.txt` reuses it and skips the enumeration:

```wl
TraitAssociations[subject, "Reference" -> "data/references"]
```

## Possible Issues

`TraitAssociations` annotates a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome). The path of the demo file
is a string, not a genome:

```wl
demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]
```

<!-- => the demo file's own path, under $TemporaryDirectory -->

A file path matches no definition, so the call comes back unevaluated:

```wl
TraitAssociations[demoFile]
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
TraitAssociations[g]
```

<!-- => the expression itself, unevaluated -->

---

A `Magnitude` of `0` means the genotype page records no magnitude, not that SNPedia rates
the genotype as uninteresting. Such rows survive the default threshold and disappear at
any positive one; the default is `0`:

```wl
Lookup[Options[TraitAssociations], "MinMagnitude"]
```

<!-- => 0 -->

---

The annotation cannot be built without reaching SNPedia, and a failed enumeration or page
fetch is reported rather than silently returning a short table:

```wl
TraitAssociations::noref
```

<!-- => "TraitAssociations could not obtain the SNPedia reference; the MediaWiki API enumeration or a page fetch failed.  Ensure the network is reachable (https://bots.snpedia.com)." -->

A strand-ambiguous SNP (`A/T` or `C/G`) has no strand-based resolution and is matched by
whichever oriented candidate SNPedia documents, and an indel genotype in SNPedia's
`D` / `I` notation is skipped rather than annotated.

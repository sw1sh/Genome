---
Template: TechNote
Name: InterpretingAHumanGenome
Title: Interpreting a Human Genome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/tutorial/InterpretingAHumanGenome
Keywords: [human genome, interpretation, ancestry, haplogroup, ClinVar, carrier status, pharmacogenomics, polygenic risk score, GWAS, AlphaMissense, SNPedia, report, tutorial]
RelatedGuides: [Genome]
RelatedTutorials: [AnalyzingAGenome, GenomeBackends]
---

A VCF file records which alleles one person carries at each called position, and
nothing more. What those alleles mean lives somewhere else entirely: in ClinVar,
in the 1000 Genomes panel, in CPIC's allele definitions, in the PGS Catalog, the
NHGRI-EBI GWAS Catalog, SNPedia, AlphaMissense, and Genomics England PanelApp -
each of them a public database keyed by genomic coordinate or rsID against a
human reference build. [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome)
is where the paclet joins the two.

Each of those joins downloads its reference database the first time it runs, and
writes what it computed into a sidecar file beside the subject's own callset, so
a later call for the same subject is a file read rather than a join. The
machinery around them needs no network at all: the promotion rule that turns a
single-sample human VCF into a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), the annotation
slots the methods write into, the caches that make the second call instant, and
[GenomeReport](paclet:WolframInstitute/Genome/ref/GenomeReport), which reads
those caches rather than recomputing. Each interpretation domain draws on a
database of its own, and each has a limit to what it can honestly say.

## The subject

The paclet was developed against an anonymized personal whole genome: 5.7 million
variants on GRCh37, one sample column named `SUBJECT`, and a `.tbi` index beside
it, kept next to the reference data as `data/subject_genome.vcf.gz`.
[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) parses the header and
returns immediately, and what it hands back is a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) rather than a
[Genome](paclet:WolframInstitute/Genome/ref/Genome), without being asked:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Two conditions decide that, and both are readable from the header alone. The
inferred build must be a human reference - `"GRCh37/hg19"` or `"GRCh38"` - because
every interpretation database is keyed to those coordinates. And the file must carry
exactly one sample, because an interpretation is about a subject: an ancestry
estimate, a diplotype, a carrier classification are all statements about one
person, and a joint callset of many samples has no single person to make them
about.

The promoted value is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome):

```wl
HumanGenomeQ[subject]
```

<!-- => True -->

It is still a genome as well, and that is what keeps the rest of the paclet
working on it:

```wl
GenomeQ[subject]
```

<!-- => True -->

A file with two sample columns is a joint callset rather than a subject, which two
synthetic rows on the same human build are enough to show:

```wl
cohortVCF = Export[
    FileNameJoin[{$TemporaryDirectory, "demo-cohort.vcf"}],
    "##fileformat=VCFv4.2
##contig=<ID=chr1,length=249250621>
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO-A	DEMO-B
chr1	10500	rs100	A	G	60	PASS	TYPED	GT	0/1	0/0
chr1	13400	rs104	G	A	60	PASS	TYPED	GT	1/1	0/1
",
    "Text"
]
```

<!-- => the full path the file was written to -->

It stays a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome), on the same
human build:

```wl
cohort = ImportVCF[cohortVCF]
```

with both samples intact and no interpretation layer over them:

```wl
cohort["Samples"]
```

<!-- => {"DEMO-A", "DEMO-B"} -->

The `"Human"` option overrides the rule in both directions. `"Human" -> False`
declines promotion on a file that qualifies - for a subject that is not human
despite a coincidence of contig lengths, or when the generic handle is all that
is wanted:

```wl
plain = ImportVCF["data/subject_genome.vcf.gz", "Human" -> False]
```

`"Human" -> True` forces promotion on any human build; on a build outside the
supported pair it issues `HumanGenome::nonHumanBuild` and gives back the generic
[Genome](paclet:WolframInstitute/Genome/ref/Genome) instead of pretending the
coordinates line up.

## The same handle, wrapped

A [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) is
`HumanGenome[Genome[<|…|>], <|…|>]`: the underlying genome, paired with an
association of interpretation state. Storage and interpretation stay separate
values, and every generic property reads straight through the wrapper:

```wl
subject["Build"]
```

<!-- => "GRCh37/hg19" -->

The subject is the single sample column:

```wl
subject["Samples"]
```

<!-- => {"SUBJECT"} -->

The storage backend was fixed at import, and the `.tbi` index beside this file
selected the indexed reader. An interpretation depends on that more than an
ordinary query does: every method reads a few thousand scattered positions, and
the index is what turns that into a seek rather than a pass over all 5.7 million
rows:

```wl
subject["Backend"]
```

<!-- => "Tabix" -->

The import options seeded two filters, which the wrapper reports as its own:

```wl
subject["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

`"PASSOnly"` keeps only rows the caller marked `PASS`, and `"ExcludeReferenceOnly"`
drops the rows that confirm the reference rather than calling a variant, which
together make a bare import mean "the variants this subject carries".

Filter accumulation is where the wrapper does real work. A filter on a
[Genome](paclet:WolframInstitute/Genome/ref/Genome) gives a new
[Genome](paclet:WolframInstitute/Genome/ref/Genome), and returned bare, that value
would discard the interpretations accumulated so far with every narrowing of the
view. The wrapper rewraps it instead, and the result says so on its own label:

```wl
chr15 = subject["Chromosome", "chr15"]
```

carrying the new filter beside the seeded ones:

```wl
chr15["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr15"} -->

A value that is not a genome flows through untouched. A region query gives a
[Tabular]() of the rows in the window - twenty kilobases of chromosome 15 holding
HERC2 and OCA2, the pigmentation genes behind the common eye-colour signal - in
the canonical seventeen-column shape every query in the paclet returns, and
rewrapping that would be nonsense:

```wl
(region = subject["Region", "chr15", {28350000, 28370000}]) // Dataset
```

The table comes back exactly as the query built it, with no wrapper around it:

```wl
HumanGenomeQ[region]
```

<!-- => False -->

The query operators are typed on `_?`[GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ),
so the wrapper and the generic handle answer identically. `rs713598`, a TAS2R38
variant behind bitter-taste perception, reads the same through both:

```wl
GenotypeLookup[subject, "rs713598"] === GenotypeLookup[plain, "rs713598"]
```

<!-- => True -->

## The annotation slots

The second element of the wrapper holds the interpretation state: two records of
provenance, one slot per interpretation method, and a slot for the aggregated
report. `"Subject"` identifies whom the interpretations are about. The identifier
is the sample column, and the sex field stays `Automatic` for the session unless a
cached karyotype call for this subject is found on disk when the handle is built,
which is where this one comes from:

```wl
subject["Subject"]
```

<!-- => <|"ID" -> "SUBJECT", "Sex" -> "XY"|> -->

Reading an interpretation slot is a lookup, never a computation. A freshly built
handle carries no interpretation in memory, whatever is cached on disk, so before
its method has run a slot reads `Missing["NotComputed"]`:

```wl
subject["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

That is the state of all nine slots on a freshly imported genome:

```wl
AssociationMap[
    subject,
    {"Ancestry", "Haplogroups", "Pharmacogenomics", "ClinVarHits", "PRS",
     "Traits", "AlphaMissenseScores", "Carrier", "GWASAssociations"}
]
```

<!-- => <|"Ancestry" -> Missing["NotComputed"], "Haplogroups" -> Missing["NotComputed"], "Pharmacogenomics" -> Missing["NotComputed"], "ClinVarHits" -> Missing["NotComputed"], "PRS" -> Missing["NotComputed"], "Traits" -> Missing["NotComputed"], "AlphaMissenseScores" -> Missing["NotComputed"], "Carrier" -> Missing["NotComputed"], "GWASAssociations" -> Missing["NotComputed"]|> -->

That is a different statement from a key the annotation does not have at all,
which reads `Missing["NotPresent"]`:

```wl
subject["Subject", "Karyotype"]
```

<!-- => Missing["NotPresent"] -->

`"References"` is the provenance record. Each key names an external data source
whose version, once a method has read it, is stamped into the record and used to
key that method's cache:

```wl
subject["References"]
```

<!-- => the build, beside one Missing["NotComputed"] marker per reference database no method has read yet -->

Only the build is known before anything runs, since it came from the file:

```wl
subject["References", "Build"]
```

<!-- => "GRCh37/hg19" -->

## One slot at a time

An interpretation method takes a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) and gives back a new
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with one slot filled
and the version it read stamped into `"References"`. Nothing is mutated, the
same discipline the filters follow.
[AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) has the
shape they all share: it fits the subject's dosages against the 1000 Genomes
super-population frequency profiles and returns the genome rather than the
estimate. The prepared panel and this subject's fit are both already on disk, so
what runs is a pair of file reads:

```wl
anc = AncestryEstimate[subject]
```

The summary box counts the filled slots and names them, so a returned genome
reports on its face how far through the interpretation layer it has come.

The version behind the fit is stamped into the new value's provenance record,
where it also keys both caches:

```wl
anc["References", "ThousandGenomesPanel"]
```

<!-- => "1000G-phase3-AIM-2784993" -->

The value that went in is untouched. Only `anc` carries the estimate, and the
handle it was computed from still reads its ancestry slot as never computed:

```wl
subject["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

Chaining is therefore ordinary composition, and each step keeps what the earlier
ones computed. Threading `anc` through
[HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall) and then
through [ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) gives a value
that reads its ancestry, its lineages and its ClinVar hits from slots at lookup
cost, while `subject` still reads all three as `Missing["NotComputed"]`.

The methods are typed on `_?`[HumanGenomeQ](paclet:WolframInstitute/Genome/ref/HumanGenomeQ),
so the generic handle imported from the same file does not qualify and leaves such
an expression unevaluated:

```wl
MatchQ[plain, _?HumanGenomeQ]
```

<!-- => False -->

## The per-subject cache

The annotation association dies with the kernel session, and an ancestry
projection or a full ClinVar join is too slow to repeat every time. Each method
therefore also writes its result to a sidecar file, in a directory beside the
source VCF named for the subject:

```wl
FileNameJoin[{subject["Subject", "ID"], "interpretations", "clinvar-hits.tabular"}]
```

<!-- => "SUBJECT/interpretations/clinvar-hits.tabular" -->

Association-valued results (`ancestry.wxf`, `haplogroups.wxf`, `sex.wxf`,
`prs.wxf`) are stored as WXF, which round-trips [Missing]() and [Tabular]()
values exactly. [Tabular]()-valued results (`clinvar-hits.tabular`,
`carrier-status.tabular`, `pharmacogenomics.tabular`, `traits.tabular`,
`gwas-associations.tabular`, `alphamissense-scores.tabular`) are stored as
Parquet, which matters once a traits or missense join reaches a million rows.

Beside most of them sits a marker file - `clinvar-hits.release`, `prs.release`,
`gwas-associations.release` and so on - holding the reference version the cached result
was computed against. Two do without one: a haplogroup result carries its version inside
the stored value, and a sex call reads no external reference at all. A method loads its sidecar only
when that marker still matches the version it is about to use, so a new ClinVar
release or a changed frequency source invalidates the cache and the join runs
again rather than reporting last year's answer. The whole `data/` tree that holds
these files is git-ignored.

The sidecars are keyed by subject and by reference version, not by filter. A
sidecar therefore holds the unfiltered result, and an option such as
`"MaxPopulationAF"` is re-applied to the rehydrated table on every call. A new
threshold gives a new answer, not the previous call's view.

## The interpretation domains

Nine of the ten interpretation operators fill one annotation slot each; the tenth,
[ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex), gives an
Association rather than a new handle. All but that one read a reference database,
downloaded once and read from disk afterwards. Each has an edge past which it
stops being informative, and the edge is as much a part of the result as the
number is.

### Chromosomal sex

[ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex) is the one
inference that needs no external database. It reads two regions - a
non-pseudoautosomal window of chrX and a male-specific window of chrY - and calls
`"XY"`, `"XX"` or `"Undetermined"` from the chrX heterozygosity rate together with
the count of non-reference chrY calls, returning those numbers alongside the call:

```wl
ChromosomalSex[subject]
```

<!-- => <|"KaryotypeCall" -> "XY", "ChrXHetRate" -> 0., "ChrXCallsSampled" -> 9143, "ChrYVariantCount" -> 606, "ChrXRegionSampled" -> "chrX:2700000-10000000", "ChrYRegionSampled" -> "chrY:2700000-10000000", "Method" -> "ChrYCoverage+ChrXHeterozygosity"|> -->

Both statistics sit at the ends of their ranges - not one heterozygous call among
9143 sampled chrX sites, and 606 variant calls in the male-specific chrY window -
which is what an `"XY"` call looks like when the evidence is unambiguous. Both
windows are read through the tabix index, so the genome is never scanned. The call
is chromosomal: it describes which sex chromosomes the callset carries, and it is
neither a statement about the subject's gender nor a clinical karyotype. Its
result is persisted like the others, and it is what the `"Subject"` record of a
later import is hydrated from.

### Continental ancestry

[AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) fits the
subject's genotypes against the five 1000 Genomes phase 3 super-population
allele-frequency profiles - AFR, AMR, EAS, EUR, SAS - and fills the `"Ancestry"`
slot with the best-matching super-population, a fraction per super-population, the
nearest populations, and the number of markers used:

```wl
anc["Ancestry"]["SuperpopulationFractions"]
```

<!-- => <|"EAS" -> 0.0872, "AMR" -> 0.1061, "AFR" -> 0., "EUR" -> 0.7433, "SAS" -> 0.0634|> -->

The largest fraction names the super-population, and that name is the headline the
rest of the estimate qualifies:

```wl
anc["Ancestry"]["Superpopulation"]
```

<!-- => "EUR" -->

The slot carries a `"PrincipalComponents"` key as well, and its value is always
`Missing["NotApplicable"]`: projecting a subject onto principal components needs
the reference panel's genotypes, and a panel of allele frequencies does not carry
them.

The resolution is continental, and coarse sub-continental at best. It is not a
country, not an ethnicity, and not a family history. The three small fractions
beside the dominant one are what a non-negative least-squares fit leaves over when
the other profiles explain a little of the dosage vector - fitting noise rather
than evidence of recent admixture - and the fractions are relative to a reference
panel of 26 populations that does not cover the world evenly.

### Maternal and paternal lineage

[HaplogroupCall](paclet:WolframInstitute/Genome/ref/HaplogroupCall) calls the
mitochondrial lineage against PhyloTree build 17 with `HaplogroupCall[hg, "mtDNA"]`,
filling one entry of the `"Haplogroups"` slot with a label, a quality score and the
counts behind it:

```wl
mt = HaplogroupCall[anc, "mtDNA"]
```

The entry names a clade of the PhyloTree, here inside T2, a west Eurasian maternal
lineage found across Europe and the Near East. Every one of the clade's 35 motif
positions is matched, against 39 rCRS-relative substitutions in all, which is what
a quality near 1 is made of:

```wl
mt["Haplogroups"]["mtDNA"]
```

<!-- => <|"Haplogroup" -> "T2a1b1a1", "Quality" -> 0.9487, "NDefiningMatched" -> 35, "NDefiningExpected" -> 35, "NVariants" -> 39, "Reference" -> "PhyloTree-17-rCRS", "Method" -> "PhyloTree17-Kulczynski"|> -->

`HaplogroupCall[hg, "Y"]` calls the Y-chromosome lineage against the ISOGG tree
into the other entry of the same slot, and gives `Missing["NoYChromosome"]` when
the callset has no Y coverage. Every assignment gives back a genome, so threading
the maternal result into the paternal call carries both lineages, and the ancestry
estimate made before them, in one value:

```wl
y = HaplogroupCall[mt, "Y"]
```

The paternal entry carries different fields from the maternal one: a `"Confidence"`
rather than a `"Quality"`, the `"Lineage"` path of clades leading to the label, and
the derived and contradicting marker counts the confidence is the ratio of. A
confidence of exactly 1 means no marker read along that path contradicted it:

```wl
y["Haplogroups"]["Y"]
```

<!-- => <|"Haplogroup" -> "N1c1a1", "Confidence" -> 1., "Lineage" -> {"N", "N1", "N1c", "N1c1", "N1c1a", "N1c1a1"}, "NDerived" -> 9, "NConflicts" -> 0, "Reference" -> "ISOGG-2016.01.04", "Method" -> "ISOGG-DeepestConsistentClade"|> -->

A haplogroup is one line of descent: mtDNA follows the mother's mother's mother,
the Y follows the father's father's father. Ten generations back a person has of
the order of a thousand ancestors, of whom exactly one is on each of those two
lines. Two labels are therefore a fact about two ancestors, not a summary of
ancestry - which is what
[AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) estimates,
from the whole autosome.

### Clinical variants

[ClinVarHits](paclet:WolframInstitute/Genome/ref/ClinVarHits) joins the callset
against NCBI ClinVar and keeps the Pathogenic and Likely-pathogenic records the
subject actually carries, with gene, condition, review status, zygosity, the
gnomAD population allele frequency of the variant, and an imputation-quality flag
for the call itself. Like every other domain it gives back the genome, with the
findings in a slot and the ClinVar release pinned in the provenance record:

```wl
cv = ClinVarHits[y]
```

The population frequency is on the row for a reason. A variant carried by a few
percent of a population cannot be the cause of a rare disease, whatever label it
carries; legacy pathogenic assertions on common variants are a well-known source
of false alarms, and `"MaxPopulationAF"` drops them:

```wl
Options[ClinVarHits]
```

<!-- => {"Reference" -> Automatic, "MaxPopulationAF" -> Automatic} -->

The review status on each row is the other half of that judgement - a record with
no assertion criteria is one submitter's opinion, not a curated consensus. And a
ClinVar label is a statement about a variant, made in the context of a diagnosed
patient population. Carrying such a variant is not a diagnosis.

### Carrier status

[CarrierStatus](paclet:WolframInstitute/Genome/ref/CarrierStatus) takes those same
Pathogenic and Likely-pathogenic hits, annotates each gene with its mode of
inheritance from Genomics England PanelApp, and classifies each row as
`"Carrier"`, `"Homozygous (possible affected)"`, `"X-linked"`,
`"Dominant finding"` or `"Unclassified"`. Carrier screening is about rare
variants, so the frequency filter has a default rather than being left open:

```wl
Options[CarrierStatus]
```

<!-- => {"Panel" -> Automatic, "IncludeDominant" -> True, "MaxPopulationAF" -> 0.01} -->

A heterozygous carrier of a recessive variant is healthy. That is what recessive
means: one working copy is enough, and the average person carries several such
variants. The information is reproductive - it matters if a reproductive partner
carries a variant in the same gene - and it is not a finding about the carrier's
own health.

### Pharmacogenomics

[PharmacogenomicProfile](paclet:WolframInstitute/Genome/ref/PharmacogenomicProfile)
calls star-allele diplotypes for the major CPIC pharmacogenes, translates them to
metabolizer phenotypes, and attaches the CPIC drug-response guidance and evidence
level for each actionable gene-drug pair. The allele definitions, allele
functions, diplotype-phenotype maps and recommendations come from the CPIC API;
each defining SNV's GRCh37 coordinate is resolved through Ensembl, since CPIC
publishes GRCh38. Diplotypes are matched phasing-free, by comparing the subject's
genotypes as bases against the allele definitions. `"Genes"` narrows the call to
the genes asked for, re-applied over the cached full table rather than recomputing
it:

```wl
pgx = PharmacogenomicProfile[cv, "Genes" -> {"CYP2D6", "TPMT"}]
```

One row per gene and actionable drug comes back, and the `Confidence` column is
where the profile says how much of each gene it actually read:

```wl
pgx["Pharmacogenomics"] // Dataset
```

<!-- => the CYP2D6 and TPMT rows of the fixed eight-column shape, both genes called *1/*1 and Normal Metabolizer, each row carrying its own Confidence caveat -->

Both genes come back with the reference diplotype, and the two `Confidence`
strings say how differently that came about. CYP2D6 is the standing caveat: a large share of
its clinically important alleles are structural - whole-gene deletions (`*5`),
duplications and multiplications (`*xN`), and CYP2D6-CYP2D7 hybrids - and none of
them is visible in a SNP VCF, which records substitutions at called positions and
not copy number. TPMT reports no defining sites read at all, and a `*1/*1` on no
evidence is an absence of variant calls rather than a positive reading of the
reference allele. What comes back is decision-support information to discuss with
a clinician or pharmacist, and never a prescription or a dose.

The version each join read is pinned as it goes, so the provenance record of a
threaded value says exactly which releases produced it:

```wl
pgx["References"]
```

<!-- => the build, the four markers the ancestry fit, the ClinVar join and the CPIC call pinned, and Missing["NotComputed"] for the four databases no method has read -->

### Polygenic risk scores

[PolygenicRiskScore](paclet:WolframInstitute/Genome/ref/PolygenicRiskScore) scores
the callset against a PGS Catalog scoring file for one named trait and records
that trait's entry in the `"PRS"` slot, which is a map keyed by PGS Catalog
identifier. Reading one entry back takes the identifier as a second argument, and
before anything has been scored the whole slot is uncomputed:

```wl
subject["PRS", "PGS000001"]
```

<!-- => Missing["NotComputed"] -->

A polygenic score has no meaning as a bare number, only as a position in a
distribution, and the result therefore reports a percentile. Three qualifications
travel with that percentile. It is relative to a reference
population, so a change of reference changes the number. The great majority of
published scores were trained and validated on European-ancestry cohorts, and
their predictive accuracy degrades substantially in cohorts of other ancestries -
a percentile computed for a subject whose ancestry is far from the training
cohort's is not comparable to one computed within it. And coverage matters: a
score computed from a fraction of its variants, or one whose variants could not
be placed on a distribution at all - reported as `Missing["NoReference"]` - is
weaker evidence than its bare percentile suggests.

### Published trait associations

[GWASAssociations](paclet:WolframInstitute/Genome/ref/GWASAssociations) reports
the subject's genotype at every SNP carrying a published association in the
NHGRI-EBI GWAS Catalog, with the risk allele, the strand-aware risk-allele dosage
of 0, 1 or 2, the effect size, the p-value and the citation, sorted by ascending
p-value. The catalog is joined by rsID with no liftover, and a strand-ambiguous
palindromic site is flagged [Missing]() rather than guessed at:

```wl
Options[GWASAssociations]
```

<!-- => {"Trait" -> All, "MaxPValue" -> 1/20000000, "CarriedOnly" -> False, "Reference" -> Automatic} -->

The default `"MaxPValue"`, written exactly rather than as a machine number, is
the genome-wide significance threshold. Passing it
means the association is unlikely to be a statistical accident; it says nothing
about the size of the effect, which for a common variant is usually a shift of a
few percent in a population rate. A GWAS association is a property of a
population, measured mostly in European-ancestry cohorts, and carrying a risk
allele is not a prediction about the carrier.

### Missense pathogenicity

[AlphaMissenseScores](paclet:WolframInstitute/Genome/ref/AlphaMissenseScores)
looks up the AlphaMissense pathogenicity score and class for the subject's
missense variants - the substitutions that change one amino acid in a protein:

```wl
Options[AlphaMissenseScores]
```

<!-- => {"MinScore" -> 0, "Reference" -> Automatic} -->

The score is a model's prediction of whether a substitution is tolerated, made
from sequence and structure. It is not experimental evidence, not a clinical
assertion, and not comparable to a ClinVar classification, which rests on
observed segregation and function. `"MinScore"` cuts the table down to the high
end, where the prediction is most confident - which is a statement about the
model's calibration, not about the subject.

### Community-curated traits

[TraitAssociations](paclet:WolframInstitute/Genome/ref/TraitAssociations)
annotates the carried genotypes against SNPedia's magnitude, repute and summary
model, one row per documented genotype, including the homozygous-reference ones -
which are often the interesting entry, since for many SNPs the reference genotype
is the notable one:

```wl
Options[TraitAssociations]
```

<!-- => {"MinMagnitude" -> 0, "Reference" -> Automatic} -->

SNPedia is a wiki. Its magnitudes are a community convention for "how
interesting", not a calibrated effect size, and the quality of the entries ranges
from careful summaries of replicated findings to a single old paper. Raising
`"MinMagnitude"` filters by that convention and by nothing else.

## Report

[GenomeReport](paclet:WolframInstitute/Genome/ref/GenomeReport) aggregates
whatever has been computed into one structured association per subject, plus a
rendered HTML document. It reuses the slots and the sidecars and re-implements no
analysis, so a handle carrying no interpretation in memory still reports what has
already been computed for that subject. `"Sections"` restricts and orders the
output, assembling the overview and one domain without touching the others:

```wl
report = GenomeReport[subject, "Sections" -> {"Overview", "Ancestry"}]
```

<!-- => an Association of the requested sections in order, plus "ReportFile" -->

The overview names the subject and the provenance of the run. Its `"Sex"` is the
cached karyotype call, and its `"VariantCount"` follows the rule the whole layer
follows: the count is reported only if the handle had already cached one, so
assembling a report never launches a full scan of the callset:

```wl
report["Overview"]
```

<!-- => an Association whose "Subject" is "SUBJECT", "Sex" "XY", "Build" "GRCh37/hg19" and "Backend" "Tabix", beside the reference versions and the three section lists -->

Each other section is a compact summary of one domain. The ancestry section folds
the continental fit and both uniparental lineages into one association, which is
the one place the three of them are read together:

```wl
report["Ancestry"]
```

<!-- => <|"Superpopulation" -> "EUR", "SuperpopulationFractions" -> <|"EAS" -> 0.0872, "AMR" -> 0.1061, "AFR" -> 0., "EUR" -> 0.7433, "SAS" -> 0.0634|>, "mtDNAHaplogroup" -> "T2a1b1a1", "YHaplogroup" -> "N1c1a1"|> -->

Nothing was recomputed to assemble that, and nothing was downloaded. That is the
contract of the default `"Compute"` setting:

```wl
Options[GenomeReport]
```

<!-- => {"Compute" -> "Cached", "Sections" -> All, "Language" -> "English"} -->

`"Cached"` serves each section from the in-memory slot, or from the subject's
sidecar file read directly, and marks a section that has never been run rather
than firing a multi-minute join behind your back. `"All"` runs every
interpretation operator; a list of slot names refreshes just those. A section
whose slot is empty is [Missing]() in the structured result too, rather than an
empty table that would read as a clean bill of health, and the overview lists it
under `"SectionsNotRun"` beside the ones it could serve.

Alongside the association,
[GenomeReport](paclet:WolframInstitute/Genome/ref/GenomeReport) writes a
self-contained HTML document into the subject's report directory and returns its
path under `"ReportFile"`:

```wl
report["ReportFile"]
```

<!-- => the full path the file was written to -->

That document is the artifact a non-specialist actually reads, so it is written
for one: every section opens with a plain-language explanation of what it shows
and what it does not mean, each finding is stated as a sentence before the table,
identifiers are demoted to footnotes, a glossary defines every technical term
with a link to an authoritative source, and `"Language"` renders the whole thing
in English or Russian from one localization table. It opens with a caveat block,
not a summary.

## What the layer will not tell you

Four limits cut across every domain.

The pipeline is not clinical-grade and was not validated as a diagnostic device.
Nothing it produces is a diagnosis, and no action - starting a drug, stopping
one, changing a dose, making a reproductive decision - follows from a row in one
of these tables without a qualified clinician or genetic counsellor in the loop.

Most personal callsets are largely imputed. A genotyping array measures a few
hundred thousand sites directly; every other position in a whole-genome callset
built from one is statistically inferred against a reference panel, and each
interpretation inherits that uncertainty. The `R2` values and the imputation-quality flags on
the result rows are there to be read, not skipped: a pathogenic-looking call at a
poorly imputed site is first of all a candidate for confirmation by a different
assay.

Absence of a finding is not a negative result. A callset covers the positions its
assay called; a database covers what has been curated so far. A domain that
reports nothing may mean the subject carries nothing, or that the site was never
genotyped, or that the association has not been published yet. Only a computed
section says anything at all, and
[GenomeReport](paclet:WolframInstitute/Genome/ref/GenomeReport) distinguishes an empty
section from an uncomputed one for that reason.

And the estimates are population-relative in a way that is easy to forget once a
number is in hand. A percentile, an allele frequency, an ancestry fraction
and a risk allele are all defined against a reference cohort, and most of those
cohorts are European-ancestry. That is a property of the published science this
layer reads, not of the code, and the honest response to it is to weigh a
percentile less, not to re-scale it.

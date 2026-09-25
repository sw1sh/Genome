---
Template: Paclet
ResourceType: Paclet
Name: WolframInstitute/Genome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
Description: A lazy handle to a VCF on disk: streaming backends, region and rsID queries as Tabular, a human interpretation layer over public reference data, and a GEDCOM pedigree alongside it
ContributedBy: Wolfram Institute
Keywords: [genomics, genome, VCF, variants, bioinformatics, ClinVar, ancestry, haplogroup, pharmacogenomics, polygenic risk, GWAS, AlphaMissense, tabix, genealogy, GEDCOM, family tree, pedigree]
MainGuide: Documentation/English/Guides/Genome.nb
License: MIT
WolframVersion: 14.2+
Categories: [Scientific and Medical Data & Computation]
---

## Basic Description

The `WolframInstitute/Genome` paclet loads and analyzes a personal genomic dataset in the
Wolfram Language. Its central object is the `Genome` head: a lazy handle to a VCF file on
disk carrying the parsed header, the sample columns, the inferred reference build, the
selected backend and an accumulating filter spec. `ImportVCF` parses only the
meta-information, so it returns quickly even on a multi-gigabyte file; variant rows
materialize as a `Tabular` only when a query forces them. Filter accumulation is
immutable — `g["Chromosome", "chr17"]["MinR2", 0.8]["ExcludeReferenceOnly"]` returns a new
`Genome` and touches no data until `g["Variants"]`, `g["Region", chr, {start, end}]` or
`g["Genotype", rsid]` asks for rows.

Queries stream through a pluggable backend, chosen at construction and recorded in the
`"Backend"` slot. `"Tabix"` is auto-selected when a sibling `.tbi` index exists and
`bcftools` is on the path, seeking straight to a region instead of scanning to it; with
either prerequisite missing, a Parquet sidecar already written by `GenomeToParquet`
alongside the file selects `"Parquet"`; with no sidecar either, queries fall back to
`"AwkStream"`, which compiles the accumulated filters into a `gzcat | awk` pushdown that
discards non-matching rows before they ever reach the kernel and needs no index and no
external state beyond a POSIX toolchain. `"Backend" -> "Parquet"` also selects the
columnar path outright, answering queries with `Tabular` operations over the
ZSTD-compressed sidecar set written by `GenomeToParquet` — the right trade for
load-once-analyze-many work, not for a single region seek. The same query operators work
on every backend, though the Parquet backend returns the columnar schema (the exploded
INFO columns and `GT_<sample>`) rather than the canonical VCF row shape. Matching the
backend to the access pattern is what keeps a multi-gigabyte whole-genome VCF
interactively queryable from a notebook.

A single-sample human VCF on GRCh37/hg19 or GRCh38 autopromotes to a `HumanGenome`, the
same handle wrapped in an interpretation layer. Every generic operator still applies, and
each interpretation operator returns a new `HumanGenome` with one annotation slot filled
and cached per subject: `ChromosomalSex` from chrX heterozygosity and chrY coverage,
`AncestryEstimate` against the 1000 Genomes phase 3 super-population panel,
`HaplogroupCall` for the maternal (PhyloTree) and paternal (ISOGG) lineages,
`ClinVarHits` and `CarrierStatus` (the latter resolving mode of inheritance from Genomics
England PanelApp), `AlphaMissenseScores` for missense variants, `PolygenicRiskScore`
against PGS Catalog scoring files, `GWASAssociations` from the NHGRI-EBI catalog,
`TraitAssociations` from SNPedia, and `PharmacogenomicProfile` for CPIC star-allele
diplotypes with their metabolizer phenotypes and drug guidance. `GenomeReport` aggregates
whatever has been computed into one structured, localizable document.

The results are educational only. They are not a diagnosis and not medical advice;
anything that looks actionable belongs in a conversation with a clinician or pharmacist,
backed by validated clinical testing. Their limits are inherent and are reported alongside them:
ancestry resolves to the continental level, not to a country or an ethnicity; a haplogroup
is one maternal or paternal lineage, not genome-wide ancestry; polygenic scores and GWAS
associations are population-relative statistics derived largely from European-ancestry
cohorts; structural and copy-number alleles such as CYP2D6 `*5` and `*xN` are not callable
from a SNP VCF at all; and every call is only as good as the variant calling and
imputation behind the input file. This is a personal-genomics analysis toolkit, not a
clinical instrument.

A genome arrives with a second document beside it: the pedigree it came down. `ImportGEDCOM`
reads a GEDCOM file, the interchange format every genealogy service exports to, as a
`FamilyTree` holding the people, the family records that link them, and dates parsed at the
granularity each record actually states, so a year-only entry never acquires a fabricated
day. The tree answers kinship questions directly (`ft["Ancestors", person]`,
`ft["Relationship", a, b]` naming a link as `"great-grandfather"` or
`"second cousin once removed"`), `ft["Issues"]` runs a consistency pass that catches the
transcription errors genealogies accumulate (a child born before a parent could have had
one, a death before a birth, a person recorded as their own ancestor), and `FamilyTreePlot`
draws it the way a genealogy service does: the root at the bottom, ancestors fanning out
above with the father's line left and the mother's right, siblings beside their ancestor,
initials on a card coloured by sex, a dark corner for the dead, and the relationship to the
root under every name, in any of eight languages and, on request, with the Cyrillic names
romanized to the standard an archive or a passport uses. The kinship vocabulary is as
specific as each language is: a grandparent or an uncle is named with the side they come
down, half-siblings, step-relations and in-laws have their own words, and Russian keeps the
full in-law set in which a wife's father and a husband's father are never the same word.
`ImportFamilyTable` and `ExportFamilyTable` read and write the flat one-row-per-person
table a service exports beside its GEDCOM, rebuilding the family records a table lacks from
its named father, mother, spouse and children cells, and `ExportGEDCOM` writes any tree back
out as GEDCOM, so a table converts to GEDCOM and back without losing a link. The same readers are registered as Import and Export formats, so
`Import[file, "GEDCOM"]`, `Import[file, "FamilyTable"]` and `Import[file, "GenomeVCF"]` reach
them through the system verbs, with the header, the people, the families or the drawn pedigree
available as elements. `GenealogySearch` then queries the archive
record providers, mapping all of them onto one row shape: WikiTree, the Otkrytyi Spisok
database of Soviet political repression, the Perm guberniya name index (whose hits already
name the parents and cite the archival file), Wikidata and Open Archives through their
public endpoints; FamilySearch and Geni once their OAuth token is set; and Pamyat Naroda, Yandex
Archive and Find a Grave, which publish no API at all, by driving a real browser through
Playwright and reading the rows off the rendered page. `GenealogyLogin` stores a signed-in
session for those, without any password reaching the kernel. Where the browser cannot run,
or an archive answers with a security check, the result is the deep link that runs the
query plus a message saying so, because an empty result and a refusal are different
answers and conflating them would misrepresent coverage.

## Details & Options

The Genome paclet is an addition to the Wolfram Language that users can install, update,
and integrate seamlessly into the Wolfram environment on their own systems.

To install the Genome paclet, simply call <code>PacletInstall[ResourceObject["https://www.wolframcloud.com/obj/wolframinstitute/DeployedResources/Paclet/WolframInstitute/Genome"], ForceVersionInstall -> True]</code>.

Once the Genome paclet has been installed with `PacletInstall`, it is ready for use in the current session and all future sessions. To use its functions, load the main context named in the Primary Context field above with `Needs`.

You can use any symbol in the Genome paclet in your current session without installing the full paclet by using `PacletSymbol["WolframInstitute/Genome", "symbol"]`, where `"symbol"` is the name of the symbol.

## Hero Image

Wolfram Institute Genome paclet - the Genome handle, its streaming backends, and the HumanGenome interpretation layer

```wl
Import[PacletObject["WolframInstitute/Genome"]["AssetLocation", "HeroImage"]]
```

## Basic Examples

The anonymized whole-genome callset the paclet was developed against, 5.7 million variants on GRCh37, is kept beside the reference data as `data/subject_genome.vcf.gz`. A single-sample human VCF autopromotes to a `HumanGenome`, the handle every interpretation takes; the `.tbi` index beside the file selects the tabix backend, and the import reads the header only:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Chromosomal sex from the two sex-chromosome statistics, no heterozygous call among the sampled non-pseudoautosomal chrX sites against hundreds of chrY variant calls:

```wl
ChromosomalSex[subject]
```

<!-- => <|"KaryotypeCall" -> "XY", "ChrXHetRate" -> 0., "ChrXCallsSampled" -> 9143, "ChrYVariantCount" -> 606, "ChrXRegionSampled" -> "chrX:2700000-10000000", "ChrYRegionSampled" -> "chrY:2700000-10000000", "Method" -> "ChrYCoverage+ChrXHeterozygosity"|> -->

Continental ancestry, a non-negative least-squares fit of the subject's allele dosages to the five 1000 Genomes super-population frequency profiles; the estimate travels in the `"Ancestry"` slot of a new genome:

```wl
anc = AncestryEstimate[subject]
```

A dominant European fraction with a small tail across the other codes is what a single-continent subject looks like under an allele-frequency fit:

```wl
anc["Ancestry"]["SuperpopulationFractions"]
```

<!-- => <|"EAS" -> 0.0872, "AMR" -> 0.1061, "AFR" -> 0., "EUR" -> 0.7433, "SAS" -> 0.0634|> -->

The maternal lineage, assigned against PhyloTree build 17 from the chrM consensus aligned to the rCRS; every one of the clade's 35 motif positions is matched:

```wl
HaplogroupCall[subject, "mtDNA"]["Haplogroups"]["mtDNA"]
```

<!-- => <|"Haplogroup" -> "T2a1b1a1", "Quality" -> 0.9487, "NDefiningMatched" -> 35, "NDefiningExpected" -> 35, "NVariants" -> 39, "Reference" -> "PhyloTree-17-rCRS", "Method" -> "PhyloTree17-Kulczynski"|> -->

A point query goes straight through the index. The HERC2 SNP that sets eye colour comes back as the whole variant row, the INFO field exploded into columns of its own:

```wl
GenotypeLookup[subject, "rs12913832"]
```

---

The row-level mechanics run on a short synthetic VCF written to a temporary file: eight variant lines over two chromosomes, one sample column named `DEMO`, and the meta-information that fixes the reference build, written out as the tab-delimited text a VCF actually is:

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
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	A	T	60	PASS	AF=0.5;R2=0.71;IMPUTED	GT	0/1
chr1	400000	rs400	G	C	60	PASS	TYPED	GT	0/1
chr17	1000000	rs1000	C	G	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	A	60	PASS	TYPED	GT	0/0",
    "Text"
]
```

<!-- => the full path the file was written to -->

Importing that file gives back a lazy handle: the meta-information is parsed, the build and the sample column are recorded, and not one variant row has been read. A single-sample file on a human build arrives already wrapped in the interpretation layer, so a `HumanGenome` comes back rather than a `Genome`, summarized by its sample, its build and the size of the file behind it:

```wl
g = ImportVCF[demoFile]
```

Asking for the variants is what reads them. The rows come back as a `Tabular` in the canonical 17-column variant shape, which splits the INFO field into columns of its own and gives each sample a genotype column; six of the eight data lines survive, because the default filters drop the non-`PASS` row and the reference-only row whose `ALT` is `.`:

```wl
g["Variants"] // Dataset
```

`VariantSummary` aggregates a row set into the counts that describe it, a two-column `Tabular` of metric and value:

```wl
VariantSummary[g] // Dataset
```

## Scope

A handle on the demo file:

```wl
g = ImportVCF[demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

The sample list comes from the header, which is all an import reads:

```wl
g["Samples"]
```

<!-- => {"DEMO"} -->

`ImportVCFHeader` reads that meta-information on its own. The contig lengths are what identify the reference build:

```wl
ImportVCFHeader[demoFile]["Contigs"]
```

<!-- => {<|"Tag" -> "contig", "ID" -> "chr1", "Length" -> 249250621|>, <|"Tag" -> "contig", "ID" -> "chr17", "Length" -> 81195210|>} -->

A `chr1` of 249,250,621 bases is GRCh37, so the handle knows its build before any query runs:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

The backend is fixed at construction. With no `.tbi` index beside the file and no Parquet sidecar, queries stream through the `gzcat | awk` pushdown:

```wl
g["Backend"]
```

<!-- => "AwkStream" -->

Filter accumulation is immutable: each operator hands back a new handle carrying one more rule, `g` itself is untouched, and nothing is read while the rules pile up. The first two rules here are the ones a bare import already seeds:

```wl
g["Chromosome", "chr1"]["MinR2", 0.8]["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr1", "MinImputationR2" -> 0.8} -->

The rules apply together when a query finally forces the rows. One `chr1` row clears an imputation r-squared of 0.8, and the directly assayed rows carry no `R2` at all, so that same threshold takes them out too:

```wl
g["Chromosome", "chr1"]["MinR2", 0.8]["Variants"] // Dataset
```

A region query takes a chromosome and an interval and materializes the rows inside it:

```wl
RegionVariants[g, "chr1", {100000, 250000}] // Dataset
```

A point query takes an rsID and hands back the whole variant call, its INFO fields exploded into columns of their own:

```wl
GenotypeLookup[g, "rs100"]
```

<!-- => <|"CHROM" -> "chr1", "POS" -> 100000, "ID" -> "rs100", "REF" -> "A", "ALT" -> {"G"}, "QUAL" -> 60, "FILTER" -> {"PASS"}, "INFO" -> <|"AF" -> "0.31", "R2" -> "0.94", "IMPUTED" -> True|>, "R2" -> 0.94, "MAF" -> Missing[], "AC" -> Missing[], "AN" -> Missing[], "IMPUTED" -> True, "TYPED" -> False, "TYPED_ONLY" -> False, "FORMAT" -> "GT", "GT" -> "0/1"|> -->

Given several rsIDs it returns one row each, keyed by rsID, so a genotype call is one part away:

```wl
GenotypeLookup[g, {"rs100", "rs150"}]
```

The query operators also take a file path directly, building the handle themselves and dropping it afterwards:

```wl
GenotypeLookup[demoFile, "rs300"]["GT"]
```

<!-- => "0/1" -->

They take an already-materialized table too, so a second question about rows in hand costs no further reading:

```wl
RegionVariants[g["Variants"], "chr17", {1, 2000000}] // Dataset
```

## Options

A handle on the demo file:

```wl
g = ImportVCF[demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

A bare import already has two filters in force before a single option has been given:

```wl
g["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Those two come from the option defaults. The rest seed the filter spec in the same way, or pick the backend:

```wl
Options[ImportVCF]
```

<!-- => {"MaxVariants" -> Infinity, "Chromosome" -> All, "Region" -> None, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "MinImputationR2" -> 0, "Backend" -> Automatic, "Human" -> Automatic} -->

Switching the two of them off keeps every data line in the file, the `LowQual` row and the reference-only row whose `ALT` is empty included:

```wl
ImportVCF[demoFile, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False]["Variants"] // Dataset
```

`"MaxVariants"` caps the rows a query materializes, which is how a whole-genome file stays interactive while an analysis is still being drafted:

```wl
ImportVCF[demoFile, "MaxVariants" -> 2]["Variants"] // Dataset
```

A single-sample file on a human build is promoted to a `HumanGenome`, and `"Human" -> False` keeps the generic handle instead: the same file, the same backend, no interpretation layer:

```wl
ImportVCF[demoFile, "Human" -> False]
```

## Applications

Left to itself, that same file is promoted: the same handle, wrapped in the interpretation layer:

```wl
g = ImportVCF[demoFile = FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Every generic operator still applies to it, and `HumanGenomeQ` is what tells the two apart:

```wl
HumanGenomeQ[g]
```

<!-- => True -->

The wrapper records the public reference datasets an interpretation would be read against. Only the build is known until an operator runs and pins a release:

```wl
g["References"]
```

<!-- => <|"Build" -> "GRCh37/hg19", "ThousandGenomesPanel" -> Missing["NotComputed"], "ClinVarRelease" -> Missing["NotComputed"], "PGSCatalogVersion" -> Missing["NotComputed"], "CPICVersion" -> Missing["NotComputed"], "PharmGKBVersion" -> Missing["NotComputed"], "SNPediaCommit" -> Missing["NotComputed"], "AlphaMissenseRelease" -> Missing["NotComputed"], "GWASCatalogVersion" -> Missing["NotComputed"]|> -->

Each interpretation operator fills one annotation slot and caches it per subject. The handle reads its own slots, so `AssociationMap` over their names shows the shape of the layer before any analysis has been paid for:

```wl
AssociationMap[
    g,
    {"Ancestry", "Haplogroups", "Pharmacogenomics", "ClinVarHits", "Carrier",
     "PRS", "Traits", "GWASAssociations", "AlphaMissenseScores"}
]
```

<!-- => <|"Ancestry" -> Missing["NotComputed"], "Haplogroups" -> Missing["NotComputed"], "Pharmacogenomics" -> Missing["NotComputed"], "ClinVarHits" -> Missing["NotComputed"], "Carrier" -> Missing["NotComputed"], "PRS" -> Missing["NotComputed"], "Traits" -> Missing["NotComputed"], "GWASAssociations" -> Missing["NotComputed"], "AlphaMissenseScores" -> Missing["NotComputed"]|> -->

`GenomeReport` gathers whatever has been computed into one structured document. Its keys are the sections it can carry, plus the file it writes beside them:

```wl
GenomeReport[g]
```

The default `"Compute" -> "Cached"` reports only what is already in hand and needs neither reference data nor a network. `"Compute" -> "All"` refreshes the analyses instead, and `"Language"` localizes the written document:

```wl
Options[GenomeReport]
```

<!-- => {"Compute" -> "Cached", "Sections" -> All, "Language" -> "English"} -->

The pedigree layer is the other half of the same question, and it reads its own format. A synthetic three-generation GEDCOM, six invented people in two family records, written out as the line-oriented text a GEDCOM actually is:

```wl
demoTreeFile = Export[
    FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}],
    "0 HEAD
1 SOUR DEMO
1 GEDC
2 VERS 5.5.1
1 CHAR UTF-8
0 @I1@ INDI
1 NAME John /Doe/
2 GIVN John
2 SURN Doe
1 SEX M
1 BIRT
2 DATE 12 MAR 1900
1 DEAT
2 DATE 1975
1 FAMS @F1@
0 @I2@ INDI
1 NAME Jane /Roe/
2 GIVN Jane
2 SURN Roe
2 _MARNM Doe
1 SEX F
1 BIRT
2 DATE 1902
1 FAMS @F1@
0 @I3@ INDI
1 NAME Richard Q /Doe/
2 GIVN Richard
2 _MIDN Q
2 SURN Doe
1 SEX M
1 BIRT
2 DATE JUL 1930
1 FAMC @F1@
1 FAMS @F2@
0 @I4@ INDI
1 NAME Mary /Poe/
2 GIVN Mary
2 SURN Poe
1 SEX F
1 BIRT
2 DATE 1932
1 FAMS @F2@
0 @I5@ INDI
1 NAME Sam /Doe/
2 GIVN Sam
2 SURN Doe
1 SEX M
1 BIRT
2 DATE 05 FEB 1960
1 FAMC @F2@
0 @I6@ INDI
1 NAME Ann /Doe/
2 GIVN Ann
2 SURN Doe
1 SEX F
1 BIRT
2 DATE 1962
1 FAMC @F2@
0 @F1@ FAM
1 HUSB @I1@
1 WIFE @I2@
1 CHIL @I3@
0 @F2@ FAM
1 HUSB @I3@
1 WIFE @I4@
1 CHIL @I5@
1 CHIL @I6@
0 TRLR",
    "Text"
]
```

<!-- => the full path the file was written to -->

Reading it gives a `FamilyTree`, summarized by the size and span of the pedigree rather than by any of the names in it:

```wl
demoTree = ImportGEDCOM[demoTreeFile]
```

Kinship is a property of the tree, named the way a person would name it, and it reverses correctly:

```wl
{demoTree["Relationship", "I5", "I1"], demoTree["Relationship", "I1", "I5"]}
```

<!-- => {"grandfather", "grandson"} -->

`FamilyTreePlot` draws it as a pedigree: the root at the bottom, the father's line on the left and the mother's on the right, one card per person with their initials and their relationship to the root, and placeholders where the file stops:

```wl
FamilyTreePlot[demoTree]
```

`GenealogySearch` carries a person out to the archives, with the years from the record already filled in. With the browser switched off it hands back the addressed query rather than running it:

```wl
GenealogySearch[demoTree, "I1", "Providers" -> "FindAGrave", "Browser" -> False] // Dataset
```

## Neat Examples

Because the handle is lazy, file size is a property of the queries rather than of the import. The same construction scaled to a hundred thousand variant lines is about four megabytes of VCF: the meta-information and the column header as one block of text, then one templated row every thousand bases:

```wl
bigFile = Export[
    FileNameJoin[{$TemporaryDirectory, "genome-demo-large.vcf"}],
    Prepend[
        StringTemplate["chr1	`1`000	rs`1`	A	G	60	PASS	.	GT	0/1"] /@ Range[100000],
        "##fileformat=VCFv4.2
##contig=<ID=chr1,length=249250621>
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO"
    ],
    "Lines"
]
```

<!-- => the full path the file was written to -->

Importing it gives back the same kind of handle the eight-line file did, summarized by the same sample and build over four megabytes of file:

```wl
big = ImportVCF[bigFile]
```

That import costs the milliseconds the eight-line file cost, and a multi-gigabyte file costs the same, because the price is the header and not the rows:

```wl
First[AbsoluteTiming[ImportVCF[bigFile]]]
```

<!-- => 0.012461 - the seconds spent parsing the meta-information in the run that produced this hint (0.012595, 0.014474, 0.019213 on other runs), machine- and run-dependent -->

Counting the rows does walk the whole file, but it walks it in `awk`, so what reaches the kernel is a number rather than a hundred thousand rows:

```wl
big["VariantCount"]
```

<!-- => 100000 -->

And a five-kilobase window comes back as the handful of rows inside it, which is the query the whole design is built around:

```wl
RegionVariants[big, "chr1", {5000000, 5005000}] // Dataset
```

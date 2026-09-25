---
Template: TechNote
Name: AnalyzingAGenome
Title: Analyzing a Genome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/tutorial/AnalyzingAGenome
Keywords: [VCF, genome, variant, genotype, rsID, region query, filter, lazy, Tabular, tutorial]
RelatedGuides: [Genome]
RelatedTutorials: [GenomeBackends, InterpretingAHumanGenome]
---

A VCF file is the standard text format for the variants a sequencing or genotyping
run found: a block of `##` meta-information lines, one `#CHROM` line naming the
columns and the samples, and then one tab-separated row per called position. A
whole-genome VCF runs to millions of those rows and several gigabytes compressed,
so [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) reads none of them.
It parses the header and hands back a [Genome](paclet:WolframInstitute/Genome/ref/Genome)
handle carrying the file path, the sample columns, the inferred reference build, the
storage backend and a filter spec; rows materialize as a [Tabular]() only when a
query asks for them.

Most of the examples run against one synthetic VCF of fifteen rows written to a
temporary file, small enough that every row can be accounted for. Where the size
of the file is the point instead, they run against the anonymized personal whole
genome the paclet was developed against - 5.7 million variants on GRCh37, kept
beside the reference data as `data/subject_genome.vcf.gz`.

## A VCF to work with

The fixture is a VCF written out as it would sit on disk: fifteen data rows over two
chromosomes, one sample column named `DEMO`, and the meta-information that makes
sense of them:

```wl
vcfFile = Export[
    FileNameJoin[{$TemporaryDirectory, "tutorial-demo.vcf"}],
    "##fileformat=VCFv4.2
##source=WolframInstituteGenomeTutorial
##contig=<ID=chr1,length=249250621>
##contig=<ID=chr17,length=81195210>
##INFO=<ID=AF,Number=1,Type=Float,Description=\"Alternate allele frequency\">
##INFO=<ID=R2,Number=1,Type=Float,Description=\"Imputation r-squared\">
##INFO=<ID=IMPUTED,Number=0,Type=Flag,Description=\"Genotype imputed, not assayed\">
##INFO=<ID=TYPED,Number=0,Type=Flag,Description=\"Genotype directly assayed\">
##INFO=<ID=TYPED_ONLY,Number=0,Type=Flag,Description=\"Assayed, absent from the panel\">
##FORMAT=<ID=GT,Number=1,Type=String,Description=\"Genotype\">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO
chr1	100000	rs100	A	G	60	PASS	AF=0.31;R2=0.94;IMPUTED	GT	0/1
chr1	150000	rs150	C	T	60	PASS	TYPED	GT	1/1
chr1	200000	.	G	.	.	.	.	GT	0/0
chr1	250000	rs250	T	C	45	LowQual	AF=0.07;R2=0.42;IMPUTED	GT	0/1
chr1	300000	rs300	A	T	60	PASS	AF=0.50;R2=0.71;IMPUTED	GT	0/1
chr1	400000	rs400	G	C	60	PASS	TYPED	GT	0/1
chr1	500000	rs500	GA	G	60	PASS	AF=0.11;R2=0.85;IMPUTED	GT	0/1
chr1	600000	rs600	C	A	60	PASS	AF=0.22;R2=0.96;IMPUTED	GT	1/1
chr17	1000000	rs1000	C	T	60	PASS	AF=0.12;R2=0.88;IMPUTED	GT	0/1
chr17	1100000	rs1100	T	C	60	PASS	TYPED	GT	0/0
chr17	1200000	rs1200	G	A	60	PASS	AF=0.44;R2=0.99;IMPUTED	GT	1/1
chr17	1300000	rs1300	A	G	30	LowQual	AF=0.03;R2=0.35;IMPUTED	GT	0/1
chr17	1400000	rs1400	C	T	60	PASS	TYPED_ONLY	GT	./.
chr17	1500000	rs1500	T	TAC	60	PASS	AF=0.09;R2=0.79;IMPUTED	GT	0/1
chr17	1600000	.	A	.	.	.	.	GT	0/0",
    "Text"
]
```

<!-- => the full path the file was written to -->

Read one data row left to right and the format explains itself. `chr1` and `100000`
place the variant on the reference assembly. `rs100` is its rsID, the accession dbSNP
assigns to a known variant position, and `.` in that column marks a position with no
such accession. `A` is the reference base there and `G` is the
alternate the sample carries. `60` is the caller's quality score and `PASS` says the
row survived every filter the caller applied. The INFO field packs the
position-level annotations as `key=value` pairs and bare flags. The last two columns
are the per-sample part: `GT` names the fields that follow, and `0/1` is the genotype
call for `DEMO` - allele indices into the reference-then-alternates list, so `0/0`
is two reference copies, `0/1` one of each, `1/1` two alternate copies, and `./.` a
no-call, a position where the data did not support any call at all.

Four rows in that file are there to be excluded rather than analyzed. Two carry
`LowQual` instead of `PASS`. Two more have `.` in the ALT column: these are
reference-confirming rows, positions the caller looked at and found to match the
reference, and on a whole-genome file they outnumber the real variants by orders of
magnitude.

## What the header says

[ImportVCFHeader](paclet:WolframInstitute/Genome/ref/ImportVCFHeader) reads the
meta-information on its own, without touching a single data row. It gives an
[Association]() whose keys cover both the raw declarations and what can be inferred
from them:

```wl
hdr = ImportVCFHeader[vcfFile]
```

The contig declarations name the chromosomes in the file and give each one its
length in bases:

```wl
hdr["Contigs"]
```

<!-- => {<|"Tag" -> "contig", "ID" -> "chr1", "Length" -> 249250621|>, <|"Tag" -> "contig", "ID" -> "chr17", "Length" -> 81195210|>} -->

Those lengths are what identify the reference assembly the coordinates are relative
to. A `chr1` of 249,250,621 bases is GRCh37, and every position in the file means
something only against that assembly:

```wl
hdr["InferredBuild"]
```

<!-- => "GRCh37/hg19" -->

The sample names come from the `#CHROM` line, one per genotype column. This file has
exactly one, which is the shape a personal genome arrives in:

```wl
hdr["Samples"]
```

<!-- => {"DEMO"} -->

The INFO declarations are the file's own key to its annotation field: each one
declares a key that may appear in the INFO column of a data row.

```wl
hdr["INFO"]
```

<!-- => {<|"Tag" -> "INFO", "ID" -> "AF"|>, <|"Tag" -> "INFO", "ID" -> "R2"|>, <|"Tag" -> "INFO", "ID" -> "IMPUTED"|>, <|"Tag" -> "INFO", "ID" -> "TYPED"|>, <|"Tag" -> "INFO", "ID" -> "TYPED_ONLY"|>} -->

## A lazy handle

[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) does that same header
parse and wraps the result in a handle. A single-sample file on a human reference
build is promoted one step further, to a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) - the same handle
with an interpretation layer around it. It displays as a frame naming the sample,
the build, the number of samples and the size of the file it stands for:

```wl
g = ImportVCF[vcfFile]
```

Both heads answer to [GenomeQ](paclet:WolframInstitute/Genome/ref/GenomeQ), and every
query operator takes either one:

```wl
GenomeQ[g]
```

<!-- => True -->

The build came off the header into the handle, so it is there before any query
runs:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

So did the choice of storage backend, fixed once at import. With no `.tbi` index
beside the file and no Parquet sidecar, queries stream through a shell pipeline out of
the decompressor into a single `awk` program that discards non-matching rows before the
kernel ever sees them. The decompressor is chosen from the extension, so this plain
`.vcf` streams through `cat` where a `.vcf.gz` would use `gzcat`:

```wl
g["Backend"]
```

<!-- => "AwkStream" -->

The last slot is the filter spec, a list of rules that accumulates and applies only
when rows are finally read. A bare import already carries two of them:

```wl
g["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Those two come from option defaults. `"PASSOnly"` keeps only rows whose FILTER
column is exactly `PASS`, and `"ExcludeReferenceOnly"` drops the reference-confirming
rows, which together is what makes a bare import mean "the variants this sample
carries":

```wl
Options[ImportVCF]
```

<!-- => {"MaxVariants" -> Infinity, "Chromosome" -> All, "Region" -> None, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "MinImputationR2" -> 0, "Backend" -> Automatic, "Human" -> Automatic} -->

## Laziness, measured

Fifteen rows make the laziness hard to see. The whole-genome callset is the other
extreme: 5.7 million variant rows in 132 megabytes of bgzip-compressed VCF, one
sample column named `SUBJECT`, and a `.tbi` index beside it. Importing it costs
what the fifteen-row file cost, because the price is the header and not the rows.
What comes back is the handle beside the seconds spent parsing the
meta-information, a machine- and run-dependent number in the hundredths of a
second, and the size named in its frame is the file's, not the handle's:

```wl
AbsoluteTiming[subject = ImportVCF["data/subject_genome.vcf.gz"]]
```

<!-- => the handle beside the seconds the header parse took, about a tenth of a second, machine- and run-dependent -->

The backend is chosen at import from whatever sits beside the file, so this handle
differs from the fixture's in the one way that matters at this size: a `.tbi` index
is there and `bcftools` is on the path, so a positional query on it seeks through
the index instead of streaming through the decompressor:

```wl
subject["Backend"]
```

<!-- => "Tabix" -->

Counting the rows is the question that does walk the whole file. The walk happens
in `awk`, so what crosses into the kernel is one number rather than millions of
rows, but it is still a walk over every byte. A question worth asking of a file
this size is a scoped one - a window, an rsID, one chromosome - which is the shape
the query operators take.

## A variant row

Asking a handle for `"Variants"` is what reads rows. They come back as a
[Tabular]() in a fixed 17-column shape that every query, filter and summary in the
paclet shares. The rows show what the parse does to the text: `ALT` and
`FILTER` become lists because a row may carry several of each, `INFO` becomes an
Association in which a bare flag maps to [True](), and `R2` is surfaced as a number
while the INFO Association still holds it as the string it was written as:

```wl
g["Variants"] // Dataset
```

Ten of those seventeen columns are the VCF columns themselves. The other seven -
`R2`, `MAF`, `AC`, `AN`, `IMPUTED`, `TYPED` and `TYPED_ONLY` - are the INFO keys
queries reach for most, lifted out of the nested `INFO` Association and given columns
of their own so a filter or a sort can address them directly. Eleven of the fifteen
data rows survive the two default filters.

Switching the two default filters off recovers the four rows they hid, and on a real
callset that same switch is the difference between three million variants and three
billion positions. The unfiltered import shows them: the two `LowQual` rows carry
their rsIDs, and the two reference-confirming rows carry no rsID at all:

```wl
ImportVCF[vcfFile, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False]["Variants"] // Dataset
```

## Three ways to ask

`"Variants"` is the widest of the three query shapes: it materializes everything the
filters allow. The second shape is positional.
[RegionVariants](paclet:WolframInstitute/Genome/ref/RegionVariants) takes a
chromosome and an inclusive interval of base positions and returns the rows inside
it as a [Tabular]() of the same 17 columns. That is the shape of a question about one
gene:

```wl
RegionVariants[g, "chr1", {100000, 300000}] // Dataset
```

The window is what costs, not the file. Asking the 5.7-million-row callset for
twenty kilobases of chromosome 15 - the window over HERC2 and OCA2, the
pigmentation genes that carry the strongest common eye-colour signal - returns the
rows inside it and nothing else:

```wl
RegionVariants[subject, "chr15", {28350000, 28370000}] // Dataset
```

On the streaming backend such a query reads as far as the end of the window and
stops there, since a VCF is sorted by position. With a `.tbi` index beside the file
it is not a scan at all but a seek to the compressed blocks the window falls in,
which is why the answer arrives in hundredths of a second whatever the file weighs,
and which is the subject of the
[backends tutorial](paclet:WolframInstitute/Genome/tutorial/GenomeBackends):

```wl
First[AbsoluteTiming[RegionVariants[subject, "chr15", {28350000, 28370000}]]]
```

<!-- => the seconds the indexed seek took: hundredths of a second, machine- and run-dependent -->

The third shape is a point query.
[GenotypeLookup](paclet:WolframInstitute/Genome/ref/GenotypeLookup) takes an rsID and
returns the whole row for it, so the genotype is one part away:

```wl
GenotypeLookup[g, "rs1200"]
```

<!-- => <|"CHROM" -> "chr17", "POS" -> 1200000, "ID" -> "rs1200", "REF" -> "G", "ALT" -> {"A"}, "QUAL" -> 60, "FILTER" -> {"PASS"}, "INFO" -> <|"AF" -> "0.44", "R2" -> "0.99", "IMPUTED" -> True|>, "R2" -> 0.99, "MAF" -> Missing[], "AC" -> Missing[], "AN" -> Missing[], "IMPUTED" -> True, "TYPED" -> False, "TYPED_ONLY" -> False, "FORMAT" -> "GT", "GT" -> "1/1"|> -->

A list of rsIDs takes one pass over the file and comes back keyed by the rsIDs asked
for. A no-call arrives as the `./.` it is in the file, not as an absence:

```wl
GenotypeLookup[g, {"rs100", "rs1400"}]
```

An rsID the file has no row for is a genuine absence, and says so:

```wl
GenotypeLookup[g, "rs9999"]
```

<!-- => Missing["NotFound", "rs9999"] -->

An rsID names a variant rather than a position, so a positional index has nothing
to seek to: the lookup streams from the top of the file and stops at the first row
whose ID column matches, which on a whole-genome callset is seconds rather than
milliseconds. `rs12913832` sits in the same HERC2 window, and is the single variant
that accounts for most of the common variation in eye colour:

```wl
GenotypeLookup[subject, "rs12913832"]
```

<!-- => the canonical 17-column row for rs12913832, its "GT" the subject's genotype there -->

Both operators have a subscript twin on the handle, which reads well when the handle
is the subject of the sentence rather than an argument to it:

```wl
g["Genotype", "rs150"]["GT"]
```

<!-- => "1/1" -->

Both also take a file path directly, building a handle themselves and dropping it
afterwards - the short form for a single question about a file you are not otherwise
holding:

```wl
GenotypeLookup[vcfFile, "rs500"]["GT"]
```

<!-- => "0/1" -->

And both take an already-materialized [Tabular](), so a second question about rows
already in hand costs no further reading:

```wl
RegionVariants[g["Variants"], "chr17", {1000000, 1200000}] // Dataset
```

## Filters accumulate

A filter form on a handle returns another handle with one more rule on its spec, and
reads nothing. The interpretation layer survives the rewrap, so a filtered
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) is still a
[HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), and the frame is the
one the unfiltered handle showed, because the file behind it has not changed:

```wl
chr1Common = g["Chromosome", "chr1"]["MinR2", 0.8]
```

Rules can be chained, and the order they appear in on the new handle is the order
they were added:

```wl
chr1Common["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr1", "MinImputationR2" -> 0.8} -->

The handle those rules came from is untouched. Nothing in the paclet mutates a
`Genome`; a filter form is a constructor, so `g` still means what it meant before:

```wl
g["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

The rules apply together the moment a query forces rows, and `"MinR2"` is the one to
watch there. An imputed genotype is one statistically inferred from a reference panel
rather than assayed, and its INFO `R2` is the panel's estimate of how well it did. A
threshold of 0.8 keeps the three confident `chr1` rows and drops both the weak
imputation and, because they carry no `R2` at all, the two directly assayed rows:

```wl
chr1Common["Variants"] // Dataset
```

An option given at the query itself overrides the accumulated spec for that one call.
`"MaxVariants"` is the one to reach for while an analysis is still being drafted: it
stops the stream after that many rows, so a first look at a whole-genome file returns
immediately:

```wl
g["Variants", "MaxVariants" -> 3] // Dataset
```

## What am I holding

[VariantSummary](paclet:WolframInstitute/Genome/ref/VariantSummary) is the overview
of a row set: a two-column [Tabular]() of metric and value, aggregated in one pass.
The metric column says what it computes:

```wl
VariantSummary[g] // Dataset
```

`ByGenotypeClass` buckets each genotype call: `homRef` for `0/0`, `het` for `0/1`,
`homAlt` for `1/1`, and `missing` for a no-call. `ByImputationFlag` splits the rows
by provenance, `TYPED` for a directly assayed genotype against `IMPUTED` for an
inferred one. `TransitionTransversionRatio` counts single-base substitutions that
stay within the purines or within the pyrimidines against those that cross between
them; a real whole-genome callset lands near 2, and a value well below that is a
first sign of noise in the calling. On eleven rows it means nothing; a summary only
carries weight at genome scale.

The same operator takes a path, importing with whatever options are given. Summarizing
the file with both default filters off is the clearest picture of what they exclude:
two `LowQual` rows join `ByFilter`, and the two reference-confirming rows lift
`TotalRows` above `VariantRows` and land in `NeitherFlag`, having no provenance flag
of their own:

```wl
VariantSummary[vcfFile, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False] // Dataset
```

Genome scale is where the same two columns start to mean something, and one
chromosome is a large enough slice to see it. The chromosome filter is pushed into
the stream, so only the chr22 rows are parsed into the kernel, but the stream still
runs the length of the compressed file, which is where the half-minute goes. What
comes back is `TransitionTransversionRatio` over ninety thousand real calls, the
number fifteen synthetic rows could not produce:

```wl
VariantSummary[subject["Chromosome", "chr22"]] // Dataset
```

<!-- => the same two-column summary over the 90365 chr22 rows, in about half a minute -->

## Past the callset

Everything so far treats the file as a table of positions and calls, and none of it
cares whose genome it is or even which species. The promotion that happened silently
at import is where that changes:

```wl
HumanGenomeQ[g]
```

<!-- => True -->

The wrapper adds an annotation layer over the same handle. Its `"References"` slot
names the public datasets an interpretation would be read against; only the build is
known until an operator runs and pins a release:

```wl
g["References"]
```

<!-- => <|"Build" -> "GRCh37/hg19", "ThousandGenomesPanel" -> Missing["NotComputed"], "ClinVarRelease" -> Missing["NotComputed"], "PGSCatalogVersion" -> Missing["NotComputed"], "CPICVersion" -> Missing["NotComputed"], "PharmGKBVersion" -> Missing["NotComputed"], "SNPediaCommit" -> Missing["NotComputed"], "AlphaMissenseRelease" -> Missing["NotComputed"], "GWASCatalogVersion" -> Missing["NotComputed"]|> -->

Each interpretation operator fills one slot and caches it, so the shape of the layer
is readable before any analysis has been paid for:

```wl
AssociationMap[
    g,
    {"Ancestry", "Haplogroups", "Pharmacogenomics", "ClinVarHits", "Carrier",
     "PRS", "Traits", "GWASAssociations", "AlphaMissenseScores"}
]
```

<!-- => <|"Ancestry" -> Missing["NotComputed"], "Haplogroups" -> Missing["NotComputed"], "Pharmacogenomics" -> Missing["NotComputed"], "ClinVarHits" -> Missing["NotComputed"], "Carrier" -> Missing["NotComputed"], "PRS" -> Missing["NotComputed"], "Traits" -> Missing["NotComputed"], "GWASAssociations" -> Missing["NotComputed"], "AlphaMissenseScores" -> Missing["NotComputed"]|> -->

## Where to go next

Filling those slots means downloading and matching against public reference
databases, which is the subject of the
[interpretation tutorial](paclet:WolframInstitute/Genome/tutorial/InterpretingAHumanGenome):
chromosomal sex, continental ancestry, maternal and paternal lineage, clinical and
carrier variants, pharmacogenomic diplotypes, polygenic scores, and the aggregated
report they feed.

Every query on the fixture went through the backend a file with no index and no
sidecar gets, the slowest of the three, and only the region seek on the indexed
callset took another path.
[Backends](paclet:WolframInstitute/Genome/tutorial/GenomeBackends) covers the other
two - the indexed positional seek and the columnar store written by
[GenomeToParquet](paclet:WolframInstitute/Genome/ref/GenomeToParquet) - and which
access pattern each one is the right answer to.

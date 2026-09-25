---
Template: TechNote
Name: GenomeBackends
Title: Backends and Large Files
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/tutorial/GenomeBackends
Keywords: [backend, AwkStream, Tabix, Parquet, streaming, filter pushdown, large files, performance, VCF, tutorial]
RelatedGuides: [Genome]
RelatedTutorials: [AnalyzingAGenome, InterpretingAHumanGenome]
---

An imputed personal callset is a text file of tens of gigabytes and billions of
lines. Nothing in ``WolframInstitute`Genome`` ever loads one.
[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) reads the
meta-information at the top of the file and stops there; each filter you add to
the resulting handle is recorded rather than applied; and when a query finally
forces rows, the accumulated filter spec is compiled into the read itself, so on the streaming reader
a row that fails a filter is never decompressed into the kernel at all. The other two
readers narrow the read differently.

Three backends implement that read: a stream through `awk`, a positional seek
through a `.tbi` index, and a columnar Parquet sidecar. They differ in which
parts of a filter spec reach the read and which have to be applied to rows
already in memory, and that difference is what separates a millisecond region
seek from a thirty-second table load.

## A file to query

The fixture is a twelve-row single-sample VCF, written to a fresh temporary
directory:

```wl
demoVCF = FileNameJoin[{CreateDirectory[], "demo.vcf"}]
```

<!-- => the full path the file was written to -->

The meta-information declares two contigs, the INFO keys the filters read, and
the one non-`PASS` filter the file uses. The `#CHROM` line names the single
sample, `DEMO`. The whole block is one string of about five hundred characters,
carrying the line breaks and the tabs of the file itself:

```wl
StringLength[demoHeader = "##fileformat=VCFv4.2
##contig=<ID=chr1,length=249250621>
##contig=<ID=chr2,length=243199373>
##INFO=<ID=AF,Number=1,Type=Float,Description=\"Alternate allele frequency\">
##INFO=<ID=R2,Number=1,Type=Float,Description=\"Imputation quality\">
##INFO=<ID=TYPED,Number=0,Type=Flag,Description=\"Site was on the array\">
##INFO=<ID=IMPUTED,Number=0,Type=Flag,Description=\"Site was imputed\">
##FILTER=<ID=LowR2,Description=\"Imputation quality below threshold\">
#CHROM	POS	ID	REF	ALT	QUAL	FILTER	INFO	FORMAT	DEMO"]
```

<!-- => 499 -->

Twelve data rows follow, spread over the two chromosomes. Two of them confirm
the reference rather than calling a variant (an `ALT` column of `.`), two failed
the imputation-quality filter, and the rest carry an `R2` value and a `TYPED` or
`IMPUTED` provenance flag. They are a second string of the same kind, half again
as long:

```wl
StringLength[demoRows = "chr1	100	rs900001	A	G	60	PASS	AF=0.31;R2=0.99;TYPED	GT	0/1
chr1	250	rs900002	C	T	60	PASS	AF=0.12;R2=0.87;IMPUTED	GT	0/0
chr1	400	.	G	.	.	.	.	GT	0/0
chr1	610	rs900004	T	C	45	LowR2	AF=0.04;R2=0.42;IMPUTED	GT	0/1
chr1	780	rs900005	G	A	60	PASS	AF=0.48;R2=0.95;IMPUTED	GT	1/1
chr1	920	rs900006	A	T	60	PASS	AF=0.22;R2=0.71;IMPUTED	GT	0/1
chr2	150	rs900007	C	G	60	PASS	AF=0.09;R2=0.98;TYPED	GT	0/1
chr2	300	rs900008	T	A	60	PASS	AF=0.33;R2=0.64;IMPUTED	GT	0/1
chr2	470	.	A	.	.	.	.	GT	0/0
chr2	640	rs900010	G	T	60	PASS	AF=0.17;R2=0.91;IMPUTED	GT	1/1
chr2	810	rs900011	C	T	30	LowR2	AF=0.02;R2=0.38;IMPUTED	GT	0/1
chr2	990	rs900012	A	G	60	PASS	AF=0.41;R2=0.99;TYPED	GT	0/1"]
```

<!-- => 661 -->

Write the two blocks out as the lines of one uncompressed VCF, a little over a
kilobyte:

```wl
FileByteCount[Export[demoVCF, {demoHeader, demoRows}, "Lines"]]
```

<!-- => 1161 -->

[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) parses the header and
gives back a handle. `"Human" -> False` declines the promotion a single-sample
human build would otherwise get. The handle summarizes itself - the file, the build it
inferred and the sample count on its face, with the backend, the size, the
filter spec and the row count behind the opener:

```wl
g = ImportVCF[demoVCF, "Human" -> False]
```

The build was inferred from the contig lengths in the header, not from a
`##reference` line:

```wl
g["Build"]
```

<!-- => "GRCh37/hg19" -->

The sample list comes from the `#CHROM` line:

```wl
g["Samples"]
```

<!-- => {"DEMO"} -->

No data row has been touched yet. What the handle carries besides the header is
a backend name and a list of filters, and both are already set - the
[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) defaults seed two
rules into the spec:

```wl
g["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True} -->

Asking for the variants runs the read for the first time. Eight of the twelve
rows survive the seeded spec; the two reference-confirming rows and the two
`LowR2` rows are gone:

```wl
g["Variants"] // Dataset
```

## What a filter spec is

Filter accumulation never touches the file. Each subscript gives back a new
handle with one more rule appended to the spec:

```wl
g["Chromosome", "chr2"]["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr2"} -->

Chaining appends again, and the handle you started from is untouched:

```wl
g["Chromosome", "chr2"]["MinR2", 0.9]["MaxVariants", 2]["Filters"]
```

<!-- => {"PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "Chromosome" -> "chr2", "MinImputationR2" -> 0.9, "MaxVariants" -> 2} -->

A repeated rule is not a contradiction. Both copies stay in the list, and the
resolution step that runs just before the read combines them: two quality floors keep the
higher one, two row caps keep the smaller one, and a region overrides a bare chromosome.
The rules that combine are the numeric ones; a repeated chromosome, region or boolean rule
is last-write-wins rather than intersected.

Five of the eight rows clear a floor of `0.9`:

```wl
Length[g["MinR2", 0.9]]
```

<!-- => 5 -->

Adding a lower floor underneath it changes nothing, because the intersection is
still the higher number:

```wl
Length[g["MinR2", 0.3]["MinR2", 0.9]]
```

<!-- => 5 -->

[Length]() on a handle is itself a query - it counts rows through the backend,
under whatever spec has accumulated:

```wl
Length[g]
```

<!-- => 8 -->

## How a backend is chosen

`"Backend"` is an option of
[ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF), and its default is
`Automatic`:

```wl
Options[ImportVCF]
```

<!-- => {"MaxVariants" -> Infinity, "Chromosome" -> All, "Region" -> None, "PASSOnly" -> True, "ExcludeReferenceOnly" -> True, "MinImputationR2" -> 0, "Backend" -> Automatic, "Human" -> Automatic} -->

Under `Automatic` the choice is made from what is on disk beside the source
file, in a fixed order. The first question is whether the file has a Tabix
index - a `.tbi` sibling - with `bcftools` on the PATH to read it:

```wl
FileExistsQ[demoVCF <> ".tbi"]
```

<!-- => False -->

The second is whether
[GenomeToParquet](paclet:WolframInstitute/Genome/ref/GenomeToParquet) has
written a variants sidecar beside the file:

```wl
FileExistsQ[demoVCF <> ".parquet"]
```

<!-- => False -->

Tabix first, then Parquet, then the stream. The fixture has neither an index
nor a sidecar and gets the fallback, the one backend with no prerequisite
beyond a POSIX shell:

```wl
g["Backend"]
```

<!-- => "AwkStream" -->

## AwkStream: the filter compiled into the read

The streaming backend builds a shell pipeline out of the decompressor and a
single `awk` program, then reads its standard output. Every rule in the
resolved spec becomes a guard in that program. A row that fails a guard is
never printed to the pipe, never parsed into an [Association](), and never
allocated in the kernel: the file goes past once, front to back, and only the
surviving rows are materialised.

`"MaxVariants"` is the clearest case. It compiles to an `exit` in the `awk`
action, so asking for two rows reads the top of the file and stops there:

```wl
g["MaxVariants", 2]["Variants"] // Dataset
```

A region compiles to three guards, one on the chromosome column and one on each
end of the position range, plus an exit clause. A VCF is sorted by position, so
once the scan is past the interval the remainder of the file cannot hold a
matching row:

```wl
RegionVariants[g, "chr1", {200, 800}] // Dataset
```

Four rows of the file fall inside that interval and two come back: the
reference-confirming row at `chr1:400` and the `LowR2` row at `chr1:610` fail
the seeded spec, which is applied in the same `awk` pass as the interval itself.

A point lookup by rsID appends a second `awk` stage that prints the matching row
and exits at the first hit, so the scan stops wherever the variant happens to
sit:

```wl
GenotypeLookup[g, "rs900010"]
```

<!-- => <|"CHROM" -> "chr2", "POS" -> 640, "ID" -> "rs900010", "REF" -> "G", "ALT" -> {"T"}, "QUAL" -> 60, "FILTER" -> {"PASS"}, "INFO" -> <|"AF" -> "0.17", "R2" -> "0.91", "IMPUTED" -> True|>, "R2" -> 0.91, "MAF" -> Missing[], "AC" -> Missing[], "AN" -> Missing[], "IMPUTED" -> True, "TYPED" -> False, "TYPED_ONLY" -> False, "FORMAT" -> "GT", "GT" -> "1/1"|> -->

Every rule the spec can hold pushes down into that one program:

| filter | where it runs on `"AwkStream"` |
|---|---|
| `"Chromosome"` | a guard on the chromosome column |
| `"Region"` | guards on the chromosome and position columns, plus an exit past the interval |
| `"PASSOnly"` | a guard on the FILTER column |
| `"ExcludeReferenceOnly"` | a guard on the ALT column |
| `"MinImputationR2"` | a guard calling an `awk` function that pulls `R2` out of the INFO string |
| `"MaxVariants"` | a counter in the action that exits at the *n*th printed row |

## Tabix: a positional seek

A `.tbi` file is a positional index over a bgzip-compressed VCF: it maps a
chromosome and an interval to the compressed blocks that contain them. With one
beside the file and `bcftools` on the PATH, `Automatic` picks `"Tabix"`, and a
region query jumps to those blocks instead of scanning everything that precedes
them. That is the whole of what the index buys, and the reason a region query
takes it whenever it is available, even on a handle whose recorded backend is
something else.

An rsID lookup and a whole-file materialisation have no positional key to
exploit. There is no Tabix reader for them, so on a Tabix-recorded
handle they fall back to the streaming reader; a Parquet-recorded handle serves them from
its table.

Only the interval reaches `bcftools`, as its `-r` argument. The rest of the
spec has no expression in the index, so those rules are applied in the kernel to
the rows the seek gives back: `"PASSOnly"`, `"ExcludeReferenceOnly"` and
`"MinImputationR2"` become row selections after parsing. The saving is in what
the seek never reads, not in what the filters drop afterwards.

`"MaxVariants"` is the exception. A region query fixes the row cap at `Infinity`
before the seek runs, so an interval comes back whole however small a cap the
handle carries. The rule is not discarded - it stays in the spec and still
governs everything that handle does through the stream, which on a `"Tabix"`
handle is every query but a region.

Naming a backend whose prerequisites are missing downgrades rather than fails.
With no index beside the fixture, `"Backend" -> "Tabix"` issues
`Genome::tabixNotAvailable` and gives back the streaming reader:

```wl
ImportVCF[demoVCF, "Backend" -> "Tabix", "Human" -> False]["Backend"]
```

<!-- => "AwkStream" -->

## Parquet: a columnar sidecar

`"Backend" -> "Parquet"` is honoured whether or not the sidecar exists, so a
source file that was never converted imports cleanly and fails at query time,
with `Genome::parquetMissing`:

```wl
ImportVCF[demoVCF, "Backend" -> "Parquet", "Human" -> False]["VariantCount"]
```

<!-- => $Failed -->

[GenomeToParquet](paclet:WolframInstitute/Genome/ref/GenomeToParquet) writes the
sidecar set. The scan runs entirely in the streaming layer, so the kernel never
sees a reference-confirming row, and the three files it writes sit beside the
source under the source's own name:

```wl
FileNameTake /@ (parquetPaths = GenomeToParquet[g])
```

<!-- => <|"Variants" -> "demo.vcf.parquet", "RefBlocks" -> "demo.vcf.refblocks.parquet", "Header" -> "demo.vcf.header.vcf"|> -->

Real variants go in one file and the reference-confirming rows in another,
run-length-encoded into intervals carrying the sample's genotype. The fixture's
two reference rows are not adjacent, so they collapse to two one-base intervals:

```wl
Import[parquetPaths["RefBlocks"], "Tabular"] // Dataset
```

The query methods never open that interval store, so a Parquet-backed count and
summary describe the real-variant rows only.

With the sidecar in place, the same path imports to a handle that reads it. The
file, the build and the sample are what they were, and the summary differs in
one field:

```wl
gp = ImportVCF[demoVCF, "Human" -> False]
```

That field is the backend, and nothing but the sidecar's arrival beside the
source chose it:

```wl
gp["Backend"]
```

<!-- => "Parquet" -->

The rows it gives back are not the canonical row shape. The Parquet schema
explodes the INFO string into typed columns, keeps the original string as a
backstop, and names the genotype column after the sample:

```wl
pqRow = First[Normal[gp["Variants"]]]
```

<!-- => <|"CHROM" -> "chr1", "POS" -> 100, "ID" -> "rs900001", "REF" -> "A", "ALT" -> {"G"}, "QUAL" -> 60., "FILTER" -> {"PASS"}, "INFO_raw" -> "AF=0.31;R2=0.99;TYPED", "AF" -> 0.31, "MAF" -> Missing["NotAvailable"], "R2" -> 0.99, "ER2" -> Missing["NotAvailable"], "AC" -> Missing["NotAvailable"], "AN" -> Missing["NotAvailable"], "IMPUTED" -> False, "TYPED" -> True, "TYPED_ONLY" -> False, "FORMAT" -> "GT", "GT_DEMO" -> "0/1"|> -->

There is no `"INFO"` column, so code written against the canonical shape finds
nothing under that key. The string it would have been parsed from survives
whole:

```wl
pqRow["INFO_raw"]
```

<!-- => "AF=0.31;R2=0.99;TYPED" -->

The genotype lives under a per-sample name rather than `"GT"`:

```wl
pqRow["GT_DEMO"]
```

<!-- => "0/1" -->

The variants file holds only rows with an alternate allele, so
`"ExcludeReferenceOnly"` has nothing left to do on this backend, and the count
matches what the stream reported for the same spec:

```wl
Length[gp]
```

<!-- => 8 -->

Queries route the same way and answer the same questions. What changes is the
mechanics underneath: nothing pushes down into the read at all. The variants
table is loaded, and then `"PASSOnly"`, `"Chromosome"`, `"Region"` and
`"MinImputationR2"` become [Select]() operations over it, and `"MaxVariants"` a
[Take]():

```wl
RegionVariants[gp, "chr1", {200, 800}] // Dataset
```

The row cap carries the same exception as on the seek: both backends that
answer a region out of a prepared file reset `"MaxVariants"` to `Infinity`
first, and four rows of `chr1` clear the seeded spec whatever cap you ask for:

```wl
RegionVariants[gp["MaxVariants", 2], "chr1", {1, 1000}] // Dataset
```

The same handle honours the cap on a query that reads the whole table:

```wl
Length[gp["MaxVariants", 2]]
```

<!-- => 2 -->

The streaming backend has no such exception, since there the interval and the
counter compile into a single `awk` program and the counter exits the scan:

```wl
RegionVariants[g["MaxVariants", 2], "chr1", {1, 1000}] // Dataset
```

## What the difference costs

None of that is worth arguing about on a twelve-row file. Build a larger one - forty thousand variants over the same two contigs, under the same header:

```wl
bigVCF = FileNameJoin[{CreateDirectory[], "demo-large.vcf"}]
```

<!-- => the full path the file was written to -->

Half the rows land on `chr1` and half on `chr2`, at hundred-base spacing. Every
97th row carries the `LowR2` filter, every 10th is `TYPED` rather than
`IMPUTED`, and the imputation quality cycles between `0.50` and `0.99`. The
small fixture's header describes this file as well and goes in front of the
generated rows unchanged. The file comes to two and a half megabytes:

```wl
FileByteCount[Export[bigVCF,
   Prepend[
      Table[
         StringRiffle[
            {
             If[i <= 20000, "chr1", "chr2"],
             ToString[100 (Mod[i - 1, 20000] + 1)],
             "rs" <> ToString[2000000 + i],
             {"A", "C", "G"}[[Mod[i, 3] + 1]],
             {"G", "T", "C"}[[Mod[i, 3] + 1]],
             "60",
             If[Mod[i, 97] == 0, "LowR2", "PASS"],
             "AF=0.25;R2=0." <> ToString[50 + Mod[i, 50]] <> If[Mod[i, 10] == 0, ";TYPED", ";IMPUTED"],
             "GT",
             {"0/1", "1/1", "0/1"}[[Mod[i, 3] + 1]]
            },
            "\t"
         ],
         {i, 40000}],
      demoHeader],
   "Lines"]]
```

<!-- => 2610699 -->

Import it on the streaming backend, named rather than left to `Automatic`:

```wl
bigAwk = ImportVCF[bigVCF, "Backend" -> "AwkStream", "Human" -> False]
```

The summary reports two and a half megabytes and no row count, which is the
whole of what that import did: the header is a few hundred bytes and the data
rows are not read. Timing the same call says it in seconds:

```wl
First[AbsoluteTiming[ImportVCF[bigVCF, "Backend" -> "AwkStream", "Human" -> False]]]
```

<!-- => 0.013226 -->

Counting is a full pass, but it happens in the pipe - `awk` prints the surviving
rows and `wc` counts them, so the kernel receives one integer. The 412 `LowR2`
rows are what the default spec dropped:

```wl
AbsoluteTiming[Length[bigAwk]]
```

<!-- => {0.082158, 39588} -->

A twenty-kilobase window near the start of the file costs a fraction of that,
because the exit clause ends the scan just past the interval:

```wl
awkEarly = AbsoluteTiming[Length[bigAwk["Region", "chr1", {100000, 120000}]]]
```

<!-- => {0.023978, 199} -->

The same-sized window near the end of the file gives back the same number of
rows for several times the work. The exit clause ends the scan; nothing lets it
begin in the right place, so the whole of `chr1` goes through the pipe first:

```wl
awkLate = AbsoluteTiming[Length[bigAwk["Region", "chr2", {1900000, 1920000}]]]
```

<!-- => {0.094009, 199} -->

The gap between the two is the part of the file that precedes the interval, and
it widens with every chromosome you add in front. That gap is what a `.tbi`
index closes, and why a region query takes the index whenever one exists:

```wl
N[Round[First[awkLate]/First[awkEarly], 1/10]]
```

<!-- => 3.9 -->

A summary over the whole file is the opposite kind of work: every surviving row
has to be split, its INFO string parsed and its genotype classified, forty
thousand times:

```wl
awkSummarySeconds = First[AbsoluteTiming[bigSummary = VariantSummary[bigAwk]]]
```

<!-- => 2.379733 -->

What those seconds bought is a seven-row Tabular over the whole callset, one
metric to a row:

```wl
bigSummary // Dataset
```

That per-row parse is what the Parquet sidecar removes, by doing it once at
conversion time and storing the result column by column. Converting is itself a
full pass, so it pays for itself only if the file is going to be read more than
once:

```wl
First[AbsoluteTiming[bigParquetPaths = GenomeToParquet[bigAwk]]]
```

<!-- => 2.671125 -->

The columnar file is a small fraction of the source, because a column of
repeated genotype strings compresses far better than the interleaved text it
came from:

```wl
Round[FileByteCount[bigParquetPaths["Variants"]]/FileByteCount[bigVCF], 0.01]
```

<!-- => 0.06 -->

Import the same path again, this time naming the columnar backend:

```wl
bigParquet = ImportVCF[bigVCF, "Backend" -> "Parquet", "Human" -> False]
```

Two handles now sit on the one file, and the field they differ in decides how
every query is answered:

```wl
bigParquet["Backend"]
```

<!-- => "Parquet" -->

Its region queries cost the same wherever the interval sits, because both pay
the same fixed price - the variants table is loaded, and only then filtered:

```wl
pqEarly = AbsoluteTiming[Length[bigParquet["Region", "chr1", {100000, 120000}]]]
```

<!-- => {0.176075, 199} -->

The window at the far end of the file costs the same:

```wl
pqLate = AbsoluteTiming[Length[bigParquet["Region", "chr2", {1900000, 1920000}]]]
```

<!-- => {0.172107, 199} -->

On the whole-file summary that same fixed price is the better deal, since the
rows arrive already typed:

```wl
pqSummarySeconds = First[AbsoluteTiming[VariantSummary[bigParquet]]]
```

<!-- => 0.975085 -->

Side by side, the ordering reverses between the two kinds of work:

```wl
{
   <|"Query" -> "region near the start", "AwkStream" -> First[awkEarly], "Parquet" -> First[pqEarly]|>,
   <|"Query" -> "region near the end", "AwkStream" -> First[awkLate], "Parquet" -> First[pqLate]|>,
   <|"Query" -> "whole-file summary", "AwkStream" -> awkSummarySeconds, "Parquet" -> pqSummarySeconds|>
}
```

<!-- => {<|"Query" -> "region near the start", "AwkStream" -> 0.023978, "Parquet" -> 0.176075|>, <|"Query" -> "region near the end", "AwkStream" -> 0.094009, "Parquet" -> 0.172107|>, <|"Query" -> "whole-file summary", "AwkStream" -> 2.379733, "Parquet" -> 0.975085|>} -->

The narrow query is where pushing the filter into the read wins, and its margin
only widens with the file. The wide query is where the columnar store wins:

```wl
N[Round[awkSummarySeconds/pqSummarySeconds, 1/10]]
```

<!-- => 2.4 -->

The timings are one machine's measurement of one synthetic file. The ratios
are the part that carries over, and even they move with the size and shape of
the file: on a
whole-genome callset the region gap is orders of magnitude wide rather than a
factor of four, and loading a hundred-megabyte variants table costs tens of
seconds rather than tenths.

## Choosing deliberately

| what is beside the file | what you are doing | backend |
|---|---|---|
| a `.tbi` index, `bcftools` on the PATH | a region out of a large file | `"Tabix"` - auto-selected, and taken for regions even when the handle records another backend |
| neither an index nor a sidecar | anything at all | `"AwkStream"` - the fallback, and the only one with no prerequisites |
| a Parquet sidecar | repeated analysis over the whole callset | `"Parquet"` |
| a Parquet sidecar | one narrow lookup | not `"Parquet"` - the table load dominates |

`"Backend"` is a per-handle option rather than a global setting: `bigAwk` and
`bigParquet` read the one path two different ways at once. Naming a backend is
worth doing when the automatic choice is wrong for the work, most often to keep
a converted file off the columnar path for a single narrow lookup, or to force
the stream when a sidecar has gone stale.

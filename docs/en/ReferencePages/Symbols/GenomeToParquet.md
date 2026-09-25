---
Template: Symbol
Name: GenomeToParquet
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenomeToParquet
Keywords: [Parquet, conversion, sidecar, ZSTD, Tabular, reference blocks, gVCF, backend, VCF, genome]
SeeAlso: [Genome, ImportVCF, RegionVariants, GenotypeLookup, VariantSummary]
RelatedGuides: [Genome]
---

## Usage

<code>[GenomeToParquet]()[*g*]</code> converts the VCF underlying a <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code> *g* into a Parquet sidecar set beside the source file, and gives an [Association]() of the written paths.

<code>[GenomeToParquet]()[*g*, *opts*]</code> converts with the options below.

## Details & Options

- `GenomeToParquet` writes three sidecar files next to the source VCF at `g["Path"]`:
    - `<path>.parquet` - the variants table, one row per real variant (`ALT` other than `.`). Columns: `CHROM`, `POS`, `ID`, `REF`, `ALT`, `QUAL`, `FILTER`, `INFO_raw` (the original INFO string backstop), the exploded scalar INFO columns `AF`, `MAF`, `R2`, `ER2` (reals) and `AC`, `AN` (integers), the boolean flag columns `IMPUTED`, `TYPED`, `TYPED_ONLY`, `FORMAT`, and one genotype column `GT_<sample>` per sample. Rows are sorted by `(CHROM, POS)`.
    - `<path>.refblocks.parquet` - the collapsed reference intervals, produced by run-length-encoding adjacent reference-confirming rows (`ALT` equal to `.`). Columns: `CHROM`, `START`, `END`, `GT_<sample>`, `GQ`, `DP`. A run extends while the chromosome, genotype call, `GQ` and `DP` are unchanged and the position stays contiguous.
    - `<path>.header.vcf` - the verbatim `##` meta-information lines plus the `#CHROM` line, copied byte-for-byte as the round-trip backstop and schema dictionary.
- The resulting [Association]() has keys `"Variants"`, `"RefBlocks"` and `"Header"` holding the three sidecar paths. `"RefBlocks"` is `Missing["Skipped"]` when the reference pass is turned off.
- The conversion applies no row filters of its own: every data row with an alternate allele reaches the variants table, whatever its `FILTER` column says. The import filters carried by *g* apply to queries against the sidecar, not to the conversion.
- The scan runs entirely in the streaming `awk` layer: the variants pass emits only real-variant rows, and the reference pass run-length-encodes the reference-confirming rows into intervals inside `awk`, so the kernel never materialises the billions of reference-confirming rows of a whole-genome gVCF.
- Once the sidecars exist, [ImportVCF](paclet:WolframInstitute/Genome/ref/ImportVCF) can serve the same source path through `"Backend" -> "Parquet"`, materialising queries from the variants [Tabular]() rather than re-parsing VCF text. That backend is auto-selected only when no `.tbi` index and `bcftools` pair is available for the path; `"Backend" -> "Parquet"` selects it in any case.
- A Parquet-backed [Genome](paclet:WolframInstitute/Genome/ref/Genome) carries the columnar schema above rather than the canonical 17-column row shape, and reports `"VariantCount"` and [VariantSummary](paclet:WolframInstitute/Genome/ref/VariantSummary) over the real-variant rows only; the collapsed reference intervals are a separate store that the query methods do not read.
- An existing sidecar with `"Overwrite"` set to [False]() issues `GenomeToParquet::exists` and gives <code>[$Failed]()</code> without touching the file.
- An argument that is not a valid [Genome](paclet:WolframInstitute/Genome/ref/Genome) issues `GenomeToParquet::notGenome` and gives <code>[$Failed]()</code>.

The following options can be given:

| | | |
|-|-|-|
| `"Compression"` | `"ZSTD"` | the Parquet codec; any codec the Parquet exporter supports (`"ZSTD"`, `"Snappy"`, `"GZIP"`, `"Brotli"`, `"LZ4"`, `"LZ4Hadoop"`, [None]()) |
| `"Overwrite"` | [False]() | when [False](), refuse to clobber an existing sidecar; set [True]() to replace |
| `"RefBlocks"` | [True]() | when [False](), skip the reference-interval pass for a quick variants-only conversion |

## Basic Examples

The examples run on a small demo VCF written to a temporary file: ten data rows over two chromosomes, one sample column, and the meta-information that makes sense of them. [Export]() gives back the path it wrote:

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

The conversion writes its sidecars beside the file it reads. A copy of the demo under a name of its own keeps the original untouched:

```wl
demoCopy = CopyFile[
    demoFile,
    FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}],
    OverwriteTarget -> True
]
```

<!-- => the full path the file was written to -->

A single-sample human VCF autopromotes to a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), which `GenomeToParquet` accepts like any other genome handle:

```wl
g = ImportVCF[demoCopy]
```

Converting it writes the sidecar set beside that file and gives the three written paths, absolute and in the temporary directory the copy sits in. By default the conversion refuses to clobber a sidecar set that is already on disk; `"Overwrite" -> True` replaces it:

```wl
paths = GenomeToParquet[g, "Overwrite" -> True]
```

<!-- => <|"Variants" -> "…/genome-parquet-demo.vcf.parquet", "RefBlocks" -> "…/genome-parquet-demo.vcf.refblocks.parquet", "Header" -> "…/genome-parquet-demo.vcf.header.vcf"|>, the ellipsis standing for the temporary directory -->

Each sidecar sits beside the source VCF and is named for it:

```wl
FileNameTake /@ paths
```

<!-- => <|"Variants" -> "genome-parquet-demo.vcf.parquet", "RefBlocks" -> "genome-parquet-demo.vcf.refblocks.parquet", "Header" -> "genome-parquet-demo.vcf.header.vcf"|> -->

Every path the conversion names is on disk when it finishes:

```wl
AllTrue[Values[paths], FileExistsQ]
```

<!-- => True -->

With the sidecars in place, the same source path imports through the Parquet backend:

```wl
gp = ImportVCF[demoCopy, "Backend" -> "Parquet"]
```

## Scope

A handle on the converted copy with the Parquet backend pinned:

```wl
gp = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}], "Backend" -> "Parquet"]
```

The handle records which store its queries will read:

```wl
gp["Backend"]
```

<!-- => "Parquet" -->

Rows materialised through that backend carry the exploded-INFO column schema rather than the canonical 17-column row shape:

```wl
gp["Variants"] // Dataset
```

A Parquet-backed handle converts like any other, rewriting the same three sidecars:

```wl
paths = GenomeToParquet[gp, "Overwrite" -> True]
```

<!-- => <|"Variants" -> "…/genome-parquet-demo.vcf.parquet", "RefBlocks" -> "…/genome-parquet-demo.vcf.refblocks.parquet", "Header" -> "…/genome-parquet-demo.vcf.header.vcf"|>, the ellipsis standing for the temporary directory -->

The collapsed reference intervals live in their own sidecar, which the query methods never read. The demo VCF holds one reference-confirming row, so the run-length encoding collapses it to a single one-base interval; its FORMAT declares no `GQ` or `DP`, and those columns come back missing:

```wl
Import[paths["RefBlocks"]] // Dataset
```

The header sidecar is a byte-for-byte copy of the VCF meta-information, so it still opens with the `##fileformat` declaration:

```wl
ReadList[paths["Header"], String]
```

---

An argument that is not a genome handle is outside the scope of the conversion:

```wl
GenomeToParquet[42]
```

<!-- => the message GenomeToParquet::notGenome is issued and the result is $Failed -->

## Options

### "Compression"

A handle on the converted copy:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}]]
```

The codec changes only how the sidecar is encoded, so the written path is unchanged:

```wl
GenomeToParquet[g, "Compression" -> "Snappy", "Overwrite" -> True]["Variants"]
```

<!-- => the full path the file was written to -->

[None]() writes the columns uncompressed, which trades sidecar size for the fastest scan. The table it holds is the same nine rows either way - every data row of the demo VCF that carries an alternate allele, the `LowQual` one included:

```wl
Import[GenomeToParquet[g, "Compression" -> None, "Overwrite" -> True]["Variants"]] // Dataset
```

### "Overwrite"

The converted copy, whose sidecars are already on disk:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}]]
```

By default the conversion refuses to clobber a sidecar that is already there:

```wl
GenomeToParquet[g]
```

<!-- => the message GenomeToParquet::exists is issued and the result is $Failed -->

Setting the option to [True]() replaces the existing files instead:

```wl
GenomeToParquet[g, "Overwrite" -> True]["Variants"]
```

<!-- => the full path the file was written to -->

### "RefBlocks"

The converted copy:

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}]]
```

A variants-only conversion skips the reference-interval pass, and the key that would name that sidecar reports the skip:

```wl
GenomeToParquet[g, "RefBlocks" -> False, "Overwrite" -> True]["RefBlocks"]
```

<!-- => Missing["Skipped"] -->

Under the default the same key holds the path of the written interval file:

```wl
GenomeToParquet[g, "Overwrite" -> True]["RefBlocks"]
```

<!-- => the full path the file was written to -->

## Properties and Relations

A Parquet-backed handle on the converted copy:

```wl
gp = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}], "Backend" -> "Parquet"]
```

The variants sidecar is an ordinary Parquet file, so importing the written path outside the paclet reads the store back directly, one row carrying every column the schema declares:

```wl
Import[GenomeToParquet[gp, "Overwrite" -> True]["Variants"]] // Dataset
```

Because the variants table holds only rows with an alternate allele, excluding reference-only rows is inherent to this backend and the filter of the same name is a no-op on it:

```wl
Length[gp["ExcludeReferenceOnly"]] == Length[gp]
```

<!-- => True -->

## Possible Issues

`"Backend" -> "Parquet"` is honoured whether or not the sidecars exist, and a source file that was never converted fails at query time rather than at import. A copy of the demo that has never been converted is such a file:

```wl
ImportVCF[
    CopyFile[
        FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}],
        FileNameJoin[{$TemporaryDirectory, "genome-parquet-unconverted.vcf"}],
        OverwriteTarget -> True
    ],
    "Backend" -> "Parquet"
]["VariantCount"]
```

<!-- => the message Genome::parquetMissing is issued and the result is $Failed -->

---

The canonical `"INFO"` column is not part of the Parquet schema. A Parquet-backed handle on the converted copy:

```wl
gp = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-parquet-demo.vcf"}], "Backend" -> "Parquet"]
```

The INFO string survives as `"INFO_raw"` beside the exploded scalar columns, so a query written against `"INFO"` finds nothing:

```wl
MemberQ[Keys[First[Normal[gp["Variants"]]]], "INFO"]
```

<!-- => False -->

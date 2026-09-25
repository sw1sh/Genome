---
Template: Symbol
Name: HaplogroupCall
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/HaplogroupCall
Keywords: [haplogroup, mtDNA, mitochondrial, Y chromosome, PhyloTree, ISOGG, rCRS, maternal lineage, paternal lineage, HumanGenome, GRCh37]
SeeAlso: [HumanGenome, ImportVCF, ChromosomalSex, AncestryEstimate, Genome]
RelatedGuides: [Genome]
---

## Usage

<code>[HaplogroupCall]()[*hg*, "mtDNA"]</code> assigns the maternal mitochondrial haplogroup of a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) *hg* against PhyloTree build 17, giving a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Haplogroups"` slot carries the `"mtDNA"` entry.

<code>[HaplogroupCall]()[*hg*, "Y"]</code> assigns the paternal Y-chromosome haplogroup against the ISOGG Y-SNP index, filling the `"Y"` entry of the same slot.

## Details & Options

- `HaplogroupCall` is a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) interpretation method: it gives a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) with the requested entry of the `"Haplogroups"` annotation slot filled, leaving the wrapped [Genome](paclet:WolframInstitute/Genome/ref/Genome) and the other entry untouched. `hg["Haplogroups"]` reads the whole `<|"mtDNA" -> …, "Y" -> …|>` map.
- The `"mtDNA"` entry is an [Association]() carrying a `"Haplogroup"` label such as `"H1a1"`, a `"Quality"` score between 0 and 1, the supporting counts `"NDefiningMatched"`, `"NDefiningExpected"` and `"NVariants"`, the `"Reference"` build, and the `"Method"`.
- The `"Y"` entry is an [Association]() carrying a `"Haplogroup"` label such as `"R1b1a2"`, a `"Confidence"` between 0 and 1, the `"Lineage"` path of clades leading to the label, the marker counts `"NDerived"` and `"NConflicts"`, the `"Reference"` index, and the `"Method"`.
- A haplogroup is a single maternal (mtDNA) or paternal (Y) lineage traced through one uniparental marker. It is not genome-wide ancestry: two people with the same Y haplogroup share a direct paternal-line ancestor but may differ across the rest of the genome. For continental admixture use [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate).
- For mtDNA, the GRCh37/hg19 chrM reference is the old CRS (16571 bp), not the rCRS (16569 bp) that PhyloTree uses, so the subject's chrM consensus is first aligned to the bundled rCRS (a fast near-identical alignment) and the differences are read in rCRS coordinates; a naive position match would be shifted by the control-region indels. Each PhyloTree-17 haplogroup's rCRS-relative motif is accumulated down the tree, and the subject is assigned the deepest best-matching haplogroup by a Kulczynski similarity over substitution differences, reported as `"Quality"`.
- For Y, the subject's genotypes at the ISOGG GRCh37 Y-SNP positions are read through the tabix index and each marker is scored derived or ancestral. The subject is assigned the deepest clade whose whole lineage is supported by derived markers and unbroken by ancestral contradictions. Labels are prefix-nested, so `"R1b1a2"` descends from `"R1b"`, which descends from `"R"`, and the `"Lineage"` of a label is the set of valid labels that are prefixes of it.
- `HaplogroupCall[hg, "Y"]` records [Missing]()`["NoYChromosome"]` when the male-specific chrY window carries essentially no variant calls, as for a female subject.
- When no clade gathers at least two derived markers along an unbroken lineage, the `"Y"` entry records a [Missing]()`["NoCall"]` label with a `"Confidence"` of 0 and no `"Lineage"`.
- The reference tables are downloaded once under `data/references/haplogroup/`: PhyloTree build 17 `tree.xml` with the rCRS FASTA for mtDNA, the ISOGG Y-SNP index for Y. A `HaplogroupCall::download` message announces the fetch.
- The subject reads are index-restricted (tabix over chrM, `bcftools view -R` over the ISOGG positions), so the multi-gigabyte source is never scanned end to end. When a download, a tool, or the subject `.tbi` index is missing, `HaplogroupCall::noref` is issued and the result is <code>[$Failed]()</code>.
- Results are cached twice: the in-memory `"Haplogroups"` slot serves an immediate cache hit when the reference build matches, and a per-subject sidecar `<subject>/interpretations/haplogroups.wxf` beside the subject file persists the whole map across kernel sessions.
- A second argument other than `"mtDNA"` or `"Y"` issues `HaplogroupCall::badkind` and gives <code>[$Failed]()</code>. A first argument that is not a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) matches no definition and returns unevaluated.

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

`"Haplogroups"` is the one annotation slot both kinds of assignment write into, and on a genome that has been assigned neither lineage it is empty rather than a half-filled map:

```wl
hg["Haplogroups"]
```

<!-- => Missing["NotComputed"] -->

A lineage is read off one chromosome, so the chromosomes a subject file declares decide which assignments are possible at all. This demo callset declares two autosomal contigs and neither the mitochondrion nor the Y, where a whole-genome callset carries both:

```wl
hg["Header"]["Contigs"]
```

---

A whole-genome callset carries both. This one is the anonymized 5.7-million-variant GRCh37 callset the paclet was developed against, kept beside the reference data as `data/subject_genome.vcf.gz`:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Assigning the maternal (mitochondrial) lineage downloads PhyloTree build 17 and the rCRS the first time it runs, and later assignments for the same subject are served from a per-subject sidecar. It gives back a new [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome) whose `"Haplogroups"` slot now carries the `"mtDNA"` entry, the rest of the genome unchanged:

```wl
mt = HaplogroupCall[subject, "mtDNA"]
```

That entry is an [Association]() holding the label, the score, the supporting counts and the provenance of the assignment: `"Haplogroup"`, `"Quality"`, `"NDefiningMatched"`, `"NDefiningExpected"`, `"NVariants"`, `"Reference"` and `"Method"`, where `"Reference"` is `"PhyloTree-17-rCRS"` and `"Method"` is `"PhyloTree17-Kulczynski"`:

```wl
mt["Haplogroups"]["mtDNA"]
```

<!-- => <|"Haplogroup" -> "T2a1b1a1", "Quality" -> 0.9487, "NDefiningMatched" -> 35, "NDefiningExpected" -> 35, "NVariants" -> 39, "Reference" -> "PhyloTree-17-rCRS", "Method" -> "PhyloTree17-Kulczynski"|> -->

## Scope

### The mtDNA entry

A handle on the anonymized whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Once computed, a maternal assignment is served from the per-subject sidecar:

```wl
mt = HaplogroupCall[subject, "mtDNA"]
```

The label is a PhyloTree-17 clade. This subject sits inside T2, a west Eurasian maternal lineage found across Europe and the Near East:

```wl
mt["Haplogroups"]["mtDNA"]["Haplogroup"]
```

<!-- => "T2a1b1a1" -->

The quality is the Kulczynski similarity `(NDefiningMatched/NDefiningExpected + NDefiningMatched/NVariants)/2` between the subject's rCRS-relative substitutions and the clade's accumulated motif, a number between 0 and 1; the three counts it is computed from are kept beside it in the same entry:

```wl
mt["Haplogroups"]["mtDNA"]["Quality"]
```

<!-- => 0.9487 -->

A confident call has both counts lining up: every one of the clade's 35 motif positions is matched, against 39 rCRS-relative substitutions in all, so only four substitutions are left over as private variation. A quality well below the counts would mean the opposite: a clade whose motif the subject matches, buried under substitutions it does not explain:

```wl
KeyTake[mt["Haplogroups"]["mtDNA"], {"NDefiningMatched", "NDefiningExpected", "NVariants"}]
```

<!-- => <|"NDefiningMatched" -> 35, "NDefiningExpected" -> 35, "NVariants" -> 39|> -->

The reference build travels with the entry, so a stored result always records the tree it was matched against:

```wl
mt["Haplogroups"]["mtDNA"]["Reference"]
```

<!-- => "PhyloTree-17-rCRS" -->

### The Y entry

The whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

Threading the annotated genome through the paternal side fills the second entry of the same map; because each assignment gives back a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), the two lineages accumulate in one value:

```wl
y = HaplogroupCall[HaplogroupCall[subject, "mtDNA"], "Y"]
```

The fields of the `"Y"` entry differ from the mitochondrial ones: a `"Confidence"` rather than a `"Quality"`, the supporting `"Lineage"` path, and the derived and contradicting marker counts `"NDerived"` and `"NConflicts"` the confidence is the ratio of:

```wl
y["Haplogroups"]["Y"]
```

Labels are prefix-nested, so `"Lineage"` is the path from the root clade down to the assigned label. This subject is assigned `"N1c1a1"`, a branch of N1c, the paternal lineage common around the Baltic and across northern Eurasia:

```wl
y["Haplogroups"]["Y"]["Lineage"]
```

<!-- => {"N", "N1", "N1c", "N1c1", "N1c1a", "N1c1a1"} -->

A confidence of exactly 1 is the no-contradiction case: every marker read along that path agreed, so the depth of the call is limited only by how many markers the index places below it:

```wl
KeyTake[y["Haplogroups"]["Y"], {"Confidence", "NDerived", "NConflicts"}]
```

<!-- => <|"Confidence" -> 1., "NDerived" -> 9, "NConflicts" -> 0|> -->

The whole entry, with the label its lineage leads to. A subject with no chrY coverage has no paternal lineage to read, and the entry then records which of the two inconclusive outcomes happened instead: [Missing]()`["NoYChromosome"]` when the male-specific window was empty, [Missing]()`["NoCall"]` when markers were read but no clade gathered enough derived ones:

```wl
y["Haplogroups"]["Y"]
```

<!-- => <|"Haplogroup" -> "N1c1a1", "Confidence" -> 1., "Lineage" -> {"N", "N1", "N1c", "N1c1", "N1c1a", "N1c1a1"}, "NDerived" -> 9, "NConflicts" -> 0, "Reference" -> "ISOGG-2016.01.04", "Method" -> "ISOGG-DeepestConsistentClade"|> -->

An already-assigned lineage is served from the in-memory slot without recomputation, so the genome comes back unchanged; a settled [Missing]()`["NoYChromosome"]` counts as computed too, and the paternal side is not retried either:

```wl
HaplogroupCall[y, "mtDNA"] === y
```

<!-- => True -->

### Arguments outside the scope

A handle on the demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

A second argument other than `"mtDNA"` or `"Y"` names no reference to match against, so nothing is assigned: `HaplogroupCall::badkind` is issued and the result is <code>[$Failed]()</code>:

```wl
HaplogroupCall[hg, "autosomal"]
```

<!-- => $Failed -->

---

`HaplogroupCall` interprets a [HumanGenome](paclet:WolframInstitute/Genome/ref/HumanGenome), where a genome imported with `"Human" -> False` stays a plain [Genome](paclet:WolframInstitute/Genome/ref/Genome):

```wl
g = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}], "Human" -> False]
```

A plain genome, a file path, or any other first argument matches no definition, so the call comes back unevaluated, the operator still wrapped around its argument:

```wl
HaplogroupCall[g, "mtDNA"]
```

## Properties and Relations

Prefix nesting is what makes a lineage a path: every clade in a `"Lineage"` is a prefix of the assigned label, so the path can be recovered from the label alone:

```wl
AllTrue[{"R", "R1", "R1b", "R1b1", "R1b1a"}, StringStartsQ["R1b1a2", #] &]
```

<!-- => True -->

---

The demo genome:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

One uniparental lineage says nothing about the rest of the genome. Continental admixture is a separate estimate in a separate slot, filled by [AncestryEstimate](paclet:WolframInstitute/Genome/ref/AncestryEstimate) rather than by either haplogroup assignment:

```wl
hg["Ancestry"]
```

<!-- => Missing["NotComputed"] -->

A handle on the whole-genome callset:

```wl
subject = ImportVCF["data/subject_genome.vcf.gz"]
```

The genome threaded through both assignments:

```wl
y = HaplogroupCall[HaplogroupCall[subject, "mtDNA"], "Y"]
```

Both lineages sit in one map, read through the `"Haplogroups"` slot, which holds the two keys `"mtDNA"` and `"Y"`:

```wl
y["Haplogroups"]
```

## Possible Issues

Both kinds read the subject through the tabix index, so a `.tbi` beside the VCF is a prerequisite, alongside `curl` and `bcftools` on `PATH` and a reachable network for the one-time download. A failure in any of them ends the same way, in one message and <code>[$Failed]()</code>:

```wl
HaplogroupCall::noref
```

<!-- => the text of the message HaplogroupCall issues, after which it gives $Failed -->

---

The maternal side is assigned from chrM and the paternal side from chrY, so a callset restricted to the autosomes supports neither. The demo genome is such a callset:

```wl
hg = ImportVCF[FileNameJoin[{$TemporaryDirectory, "genome-demo.vcf"}]]
```

Neither chromosome is among the contigs it declares; [ChromosomalSex](paclet:WolframInstitute/Genome/ref/ChromosomalSex) reads the same absence from the other direction, giving `"Undetermined"` for a genome whose sex chromosomes carry nothing to sample:

```wl
FreeQ[Lookup[hg["Header"]["Contigs"], "ID"], "chrM" | "chrY"]
```

<!-- => True -->

---
Template: Guide
Name: Genome
Title: Genome
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/guide/Genome
Description: Load and analyze a personal whole-genome dataset - a lazy Genome handle over a VCF on disk, streaming backends, and an interpretation layer over public reference databases
Keywords: [genomics, genome, VCF, variants, bioinformatics, ancestry, haplogroup, ClinVar, AlphaMissense, pharmacogenomics, polygenic risk, GWAS, carrier status, tabix, GRCh37, genealogy, GEDCOM, family tree, pedigree]
RelatedGuides: []
RelatedTutorials: [AnalyzingAGenome, InterpretingAHumanGenome, GenomeBackends]
---

## Abstract

A personal genome is the set of variants one individual carries relative to a
reference assembly, distributed as a VCF file of called positions and genotypes.
The Genome paclet loads such a callset as a lazy handle over the file on disk: a
first-class object whose filters accumulate immutably, whose queries stream
through a pluggable backend, and which materialises genotypes, genomic regions,
and summary statistics on demand. A single-sample human callset is interpreted
against public reference databases for chromosomal sex, continental ancestry and
maternal or paternal lineage; clinical, carrier, and pharmacogenomic variant
annotation; polygenic and GWAS trait associations; and an aggregated report. The
interpretation layer is educational decision support, not a medical document.
Alongside the callset the paclet reads the other half of a personal genome, the
pedigree it came down: a GEDCOM file loads as a family tree that can be walked
for kinship, drawn generation by generation, checked for the date errors
genealogies accumulate, and used to query the archive providers that publish a
searchable API.

## Functions

### Loading a genome

- `ImportVCF` import a VCF file of called variants as a lazy `Genome` handle, parsing only its header
- `ImportVCFHeader` read the meta-information and sample columns of a VCF without touching variant rows
- `GenomeToParquet` write the Parquet sidecar set that the columnar backend reads, beside its source VCF
- `ImportGenotypeArray` import a genotyping-array raw genotype table

### Genome objects

- `Genome` a lazy handle to a VCF dataset together with its accumulated filter spec
- `HumanGenome` a single-sample human `Genome` carrying an interpretation layer

- `GenomeQ`, `HumanGenomeQ`

### Querying variants

- `GenotypeLookup` the genotype call at a given rsID
- `RegionVariants` the variants inside a genomic interval
- `VariantSummary` counts by chromosome, filter, genotype class, and imputation flag, with the transition-transversion ratio
- `ToBioSequence` a `BioSequence` built from a genomic region or genotype

### Sex, ancestry, and lineage

- `ChromosomalSex` chromosomal sex inferred from chrX heterozygosity outside the pseudoautosomal regions together with chrY variant coverage
- `AncestryEstimate` continental genetic ancestry fitted against the five 1000 Genomes phase 3 super-population allele-frequency profiles
- `HaplogroupCall` the maternal mitochondrial lineage against PhyloTree build 17, or the paternal Y lineage against the ISOGG tree

### Clinical and pharmacogenomic annotation

- `ClinVarHits` the carried variants ClinVar records as pathogenic or likely pathogenic, with gene, condition, zygosity, and population allele frequency
- `CarrierStatus` recessive-disease carrier status, each hit classified by the PanelApp mode of inheritance of its gene
- `PharmacogenomicProfile` star-allele diplotypes and metabolizer phenotypes for the major CPIC pharmacogenes, with the CPIC drug guidance and evidence level
- `AlphaMissenseScores` AlphaMissense pathogenicity scores and classes for the carried missense variants

### Traits and risk scores

- `PolygenicRiskScore` a PGS Catalog score for a named trait, with its population percentile
- `GWASAssociations` the genotypes at SNPs carrying a published NHGRI-EBI GWAS Catalog trait association, with risk-allele dosage and effect size
- `TraitAssociations` the SNPedia magnitude, repute, and summary annotation of the carried genotypes

### Reporting

- `GenomeReport` every computed interpretation aggregated into one structured report per subject, plus a rendered, localizable HTML document

### Genealogy

- `ImportGEDCOM` read a GEDCOM genealogy file, the format every genealogy service exports, as a `FamilyTree`
- `ExportGEDCOM` write a `FamilyTree` back out as GEDCOM 5.5.1, record for record
- `ImportFamilyTable` read the flat one-row-per-person table a service exports beside its GEDCOM, rebuilding the families from the named links
- `ExportFamilyTable` write a `FamilyTree` as that table, in the Genotek layout by default
- `FamilyTree` a parsed pedigree: people, the family records that link them, kinship walks, and a consistency pass over the dates
- `FamilyTreePlot` the pedigree drawn as a genealogy service draws it, with the relationship to the root under every name, in any of eight languages and with the names romanized on request
- `GenealogySearch` the archive record providers queried through one row shape, by API where one exists and by driving a browser where none does; a hit from the Perm name index already carries the parents and the archival citation
- `GenealogyLogin` a signed-in session for an archive that gates its records behind an account

- `FamilyTreeQ`

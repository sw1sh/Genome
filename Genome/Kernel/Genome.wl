(* ::Package:: *)
(* WolframInstitute`Genome` - Wolfram Language tools for a personal genomic dataset.

   The main user-visible surface is the Genome head: an inert wrapper
   around a single Association payload that lazily represents a VCF on
   disk plus an accumulating filter spec.  Construction via ImportVCF
   parses the VCF header eagerly (sub-second) and returns immediately;
   variant rows are only materialised when a query forces them.

   Backends are pluggable behind an internal dispatch layer.  The default
   is "AwkStream", a shell-piped gzcat | awk pushdown that is the only
   backend requiring no external state (no .tbi index, no Parquet sidecar,
   no external binary beyond a POSIX toolchain).  The "Tabix" backend is
   auto-selected when a sibling .tbi index exists and bcftools is on the
   PATH; it accelerates region queries via bcftools view -r.  The
   "Parquet" backend is auto-selected when a <path>.parquet sidecar
   exists (produced by GenomeToParquet).  It imports the variants sidecar
   as a Tabular and applies the accumulated filters with Tabular
   operations; a <path>.refblocks.parquet interval store and a
   <path>.header.vcf text sidecar sit beside it.

   See wl/GUIDE.md for the WL style rules every file here obeys, and
   ../docs/ for the format and genomics references (file-formats.md,
   genomics-primer.md, genome-design.md, indexing-decision.md,
   wl-biosequence-guide.md).
*)

BeginPackage["WolframInstitute`Genome`"];

(* === Genome head === *)
Genome::usage = "Genome[<|...|>] is a lazy handle to a personal VCF dataset.  The Association payload carries \"Path\", \"Header\", \"Samples\", \"Build\", \"Backend\", \"Filters\", and \"VariantCountCache\".  Property access (g[\"Path\"], g[\"Samples\"], g[\"Header\"], g[\"Backend\"], g[\"Filters\"], g[\"VariantCount\"]), materialising queries (g[\"Variants\"], g[\"Region\", chr, {s, e}], g[\"Genotype\", rsid], g[\"Summary\"]), and filter accumulation (g[\"FilterPASS\"], g[\"MinR2\", r], g[\"Chromosome\", chr], g[\"ExcludeReferenceOnly\"], g[\"MaxVariants\", n]) all live on the head.  Filter accumulation is immutable and returns a new Genome.";
GenomeQ::usage = "GenomeQ[expr] returns True when expr is Genome[a_Association] whose payload carries the required keys (Path, Header, Samples, Build, Backend, Filters, VariantCountCache).";

(* === loading === *)
ImportVCF::usage = "ImportVCF[path] imports a VCF file of called variants and returns a lazy Genome[<|...|>] handle.  The header is parsed eagerly; variant rows materialise only on demand.  Options: \"MaxVariants\" (default Infinity), \"Chromosome\" (All or a string / list of strings), \"Region\" ({chrom, {start, end}} or None), \"PASSOnly\" (True), \"ExcludeReferenceOnly\" (True, drop ALT=. rows), \"MinImputationR2\" (0), \"Backend\" (Automatic | \"AwkStream\" | \"Tabix\" | \"Parquet\").  All filter options seed the returned Genome's \"Filters\" slot.";
ImportVCFHeader::usage = "ImportVCFHeader[path] streams just the meta-information (## lines plus #CHROM) from a VCF and returns an Association with FileFormat, Source, Reference, InferredBuild, Contigs, INFO, FORMAT, FILTER, Samples, and MetaLineCount.";
ImportGenotypeArray::usage = "ImportGenotypeArray[path] imports a 23andMe / genotyping-array raw genotype TSV (rsid, chromosome, position, genotype) into a Tabular.";

(* === conversion === *)
GenomeToParquet::usage = "GenomeToParquet[g] converts the VCF underlying a Genome g into a Parquet sidecar set beside the source file: <path>.parquet (real variants, ALT != \".\"), <path>.refblocks.parquet (reference-confirming rows run-length-encoded into intervals), and <path>.header.vcf (the verbatim ## meta lines plus the #CHROM line).  The scan runs entirely in the awk streaming layer so the kernel never materialises the reference-confirming rows.  Returns an Association of the written sidecar paths.  Options: \"Compression\" (default \"ZSTD\"), \"Overwrite\" (default False, refuse to clobber existing sidecars), \"RefBlocks\" (default True, set False to skip the reference-interval pass).";

(* === query === *)
GenotypeLookup::usage = "GenotypeLookup[data, rsid] returns the genotype call for a given rsID.  data can be a Genome, a materialised variant Tabular, or a path string.";
RegionVariants::usage = "RegionVariants[data, chromosome, {start, end}] returns the variants of data that fall within the genomic interval [start, end] on chromosome.  data can be a Genome, a materialised variant Tabular, or a path string.";

(* === analysis === *)
VariantSummary::usage = "VariantSummary[data] computes summary statistics over a variant set (counts per chromosome, per filter, per genotype class, per imputation flag, transition / transversion ratio) and returns them as a two-column Tabular of {Metric, Value} rows.  data can be a Genome, a materialised variant Tabular, or a path string.";
ToBioSequence::usage = "ToBioSequence[...] builds a Wolfram BioSequence object from a genomic region or genotype drawn from imported data.";

(* === HumanGenome head ===
   HumanGenome is a composition wrapper HumanGenome[Genome[<|...|>], <|ann|>]
   that adds a human-specific interpretation layer (ancestry, haplogroups,
   pharmacogenomics, ClinVar, polygenic risk, AlphaMissense, SNPedia traits)
   on top of the generic Genome.  Every _?GenomeQ operator accepts it
   transparently; the inner Genome is reached through a forwarding SubValue
   and filter accumulation rewraps back into a HumanGenome. *)
HumanGenome::usage = "HumanGenome[Genome[<|...|>], <|...|>] is a human-specific specialisation of Genome that carries an interpretation-annotation Association (References, Subject, and the cached interpretation slots Ancestry, Haplogroups, Pharmacogenomics, ClinVarHits, PRS, Traits, AlphaMissenseScores, Carrier, ReportCache).  HumanGenome[g] promotes a GRCh37/hg19 or GRCh38 Genome; every Genome property, query, and filter-accumulation form forwards to the inner Genome (filter accumulation returns a new HumanGenome preserving the annotations), and the interpretation slot reads hg[\"Ancestry\"], hg[\"ClinVarHits\"], hg[\"Subject\"], etc. serve the cached value.";
HumanGenomeQ::usage = "HumanGenomeQ[expr] returns True when expr is HumanGenome[g_Genome, _Association] wrapping a human-build (GRCh37/hg19 or GRCh38) Genome, and False otherwise.";

(* === interpretation operators === *)
ChromosomalSex::usage = "ChromosomalSex[hg] infers the genetic (chromosomal) sex of a HumanGenome from its sex chromosomes and returns an Association with \"KaryotypeCall\" (\"XY\", \"XX\", or \"Undetermined\"), \"ChrXHetRate\" (the heterozygosity rate over PASS biallelic SNVs in a non-pseudoautosomal chrX window), \"ChrYVariantCount\" (the number of non-reference PASS chrY calls in a male-specific chrY window), the sampled regions, and \"Method\".  The call is also persisted so a later HumanGenome for the same subject reports it through hg[\"Subject\", \"Sex\"].  ChromosomalSex reads only two tabix regions (chrX and chrY), never the whole genome.";
AncestryEstimate::usage = "AncestryEstimate[hg] estimates continental (super-population) genetic ancestry for a HumanGenome against the 1000 Genomes phase 3 panel and returns a new HumanGenome with the \"Ancestry\" slot populated with an Association {\"Superpopulation\", \"SuperpopulationFractions\", \"NearestPopulations\", \"PrincipalComponents\", \"Method\", \"NMarkersUsed\"}.  The estimate is continental / coarse sub-continental resolution (AFR, AMR, EAS, EUR, SAS), not country or ethnicity level.";
HaplogroupCall::usage = "HaplogroupCall[hg, \"mtDNA\" | \"Y\"] calls the mitochondrial (PhyloTree build 17) or Y-chromosome (ISOGG) haplogroup for a HumanGenome and returns a new HumanGenome with the corresponding entry of the \"Haplogroups\" slot populated (an Association {\"Haplogroup\" -> label, \"Quality\" -> confidence, ...}).  A haplogroup is a single maternal (mtDNA) or paternal (Y) lineage, not genome-wide ancestry.  HaplogroupCall[hg, \"Y\"] returns Missing[\"NoYChromosome\"] when the subject has no Y-chromosome coverage.";
PharmacogenomicProfile::usage = "PharmacogenomicProfile[hg] calls the subject's star-allele diplotypes for the major CPIC pharmacogenes (CYP2C19, CYP2C9, VKORC1, TPMT, SLCO1B1, DPYD, CYP3A5, UGT1A1, NUDT15, CYP2B6 and the SNV-callable subset of CYP2D6), translates them to metabolizer phenotypes, attaches CPIC drug-response guidance, and returns a new HumanGenome with the \"Pharmacogenomics\" slot populated with a Tabular of {Gene, Diplotype, Phenotype, ActionableDrug, CPICGuidance, CPICLevel, ActivityScore, Confidence} rows, one per (gene, actionable drug), sorted by gene.  Allele definitions, functions, diplotype-phenotype maps and gene-drug recommendations come from the CPIC PostgREST API; each defining SNV's GRCh37 coordinate is resolved through Ensembl (CPIC publishes GRCh38 only) and the subject is read at those positions by the tabix index.  Diplotypes are called phasing-free by matching the subject's genotypes (as bases) to the CPIC allele definitions; CYP2D6 copy-number / hybrid alleles (e.g. *5, *xN) are NOT detectable from a SNP VCF and are flagged in Confidence, and a missing defining site lowers the Confidence flag.  Options \"Genes\" (Automatic or a gene / list to restrict the view) and \"Reference\".  This is decision-support information for discussion with a clinician or pharmacist, not a prescription.";
ClinVarHits::usage = "ClinVarHits[hg] joins a HumanGenome against ClinVar and returns a new HumanGenome with the \"ClinVarHits\" slot populated with the Pathogenic / Likely Pathogenic rows.  Each hit carries its gnomAD population allele frequency (\"PopulationAF\", with \"FrequencySource\") and an \"ImputationQuality\" flag; the option \"MaxPopulationAF\" (default Automatic keeps all hits) drops hits whose PopulationAF exceeds the threshold, separating rare Mendelian variants from common polymorphisms that ClinVar mislabels pathogenic.";
PolygenicRiskScore::usage = "PolygenicRiskScore[hg, trait] scores a HumanGenome against a PGS Catalog scoring file for trait and returns a new HumanGenome with the trait's entry recorded in the \"PRS\" slot.";
TraitAssociations::usage = "TraitAssociations[hg] annotates a HumanGenome against SNPedia's community-curated magnitude / repute / summary model (the Promethease-style trait lookup) and returns a new HumanGenome with the \"Traits\" slot populated with a Tabular of {RsID, Genotype, Magnitude, Repute, Summary, URL, Category} rows, one per SNPedia-documented genotype the subject carries (including the homozygous-reference genotype), sorted by Magnitude descending.";
AlphaMissenseScores::usage = "AlphaMissenseScores[hg] looks up AlphaMissense pathogenicity for a HumanGenome's missense variants and returns a new HumanGenome with the \"AlphaMissenseScores\" slot populated.";
CarrierStatus::usage = "CarrierStatus[hg] reports recessive-disease carrier status for a HumanGenome: it takes the subject's ClinVar Pathogenic / Likely-pathogenic hits, annotates each gene with its mode of inheritance from Genomics England PanelApp, and returns a new HumanGenome with the \"Carrier\" slot populated with a Tabular that classifies each hit as \"Carrier\" (a heterozygous variant at an autosomal-recessive gene), \"Homozygous (possible affected)\", \"X-linked\", \"Dominant finding\", or \"Unclassified\".  Each row carries its gnomAD \"PopulationAF\" and \"ImputationQuality\"; the option \"MaxPopulationAF\" (default 0.01, since carrier screening wants rare variants) drops common polymorphisms.  A heterozygous carrier is healthy; the result is reproductive-risk information, not a clinical diagnosis.";
GWASAssociations::usage = "GWASAssociations[hg] reports the subject's genotypes at SNPs that carry a published trait association in the NHGRI-EBI GWAS Catalog and returns a new HumanGenome with the \"GWASAssociations\" slot populated with a Tabular of {RsID, GRCh37Position, Genotype, RiskAllele, RiskAlleleDosage, CarriesRisk, Trait, MappedTrait, OddsRatioOrBeta, PValue, RiskAlleleFrequency, PubMedID, FirstAuthor, Year, Journal} rows, one per (rsID, published association).  The catalog is joined to the subject by rsID (no liftover), the risk-allele dosage (0/1/2) is strand-aware (direct and reverse-complement matching, strand-ambiguous palindromes flagged Missing), and rows are sorted by ascending p-value.  Options \"Trait\", \"MaxPValue\", \"CarriedOnly\", and \"Reference\" filter the result.  A GWAS association is a population statistical signal (usually a small effect, mostly from European-ancestry cohorts), not a diagnosis.";
GenomeReport::usage = "GenomeReport[hg] aggregates every computed interpretation of a HumanGenome into a formatted report.";

(* === genealogy ===
   A pedigree is the other half of a personal genome: the variants a person
   carries came from named people, and the archives that document those people
   are a different search problem from the reference databases the
   interpretation layer joins against.  FamilyTree holds the pedigree,
   ImportGEDCOM reads it out of the standard interchange format every
   genealogy service exports, FamilyTreePlot draws it, and GenealogySearch
   queries the record providers that have a usable public API. *)
FamilyTree::usage = "FamilyTree[<|...|>] is a parsed pedigree.  The Association payload carries \"People\" (an Association of person records keyed by GEDCOM xref), \"Families\" (the union records that link them), and the header fields \"Source\", \"Submitter\", \"Encoding\", \"GEDCOMVersion\" and \"Path\".  FamilyTree[{person1, person2, ...}] builds one from plain Associations that carry \"ID\" and optional \"Father\" / \"Mother\" keys, synthesising a family record per parent pair.  Property access (ft[\"People\"], ft[\"Families\"], ft[\"IDs\"], ft[\"PersonCount\"], ft[\"Surnames\"], ft[\"YearRange\"], ft[\"Generations\"], ft[\"Header\"]), person lookup (ft[\"Person\", spec], ft[\"Find\", fragment], ft[\"Tabular\"]), kinship walks (ft[\"Parents\", spec], ft[\"Children\", spec], ft[\"Siblings\", spec], ft[\"Spouses\", spec], ft[\"Ancestors\", spec, generations], ft[\"Descendants\", spec, generations], ft[\"Relationship\", a, b], ft[\"Relationship\", a, b, language], ft[\"Relationships\", person] for everyone's relation to one person), consistency checking (ft[\"Issues\"]) and drawing (ft[\"Graph\", opts]) all live on the head.  A person is named either by its record key or by any fragment of its name.";
FamilyTreeQ::usage = "FamilyTreeQ[expr] returns True when expr is FamilyTree[a_Association] whose payload carries the required \"People\" and \"Families\" Associations.";
ImportGEDCOM::usage = "ImportGEDCOM[path] reads a GEDCOM 5.5.1 genealogy file and returns a FamilyTree.  Individual records contribute \"Name\", \"GivenName\", \"MiddleName\" (the _MIDN patronymic vendors write), \"Surname\", \"MarriedName\", \"Sex\", \"BirthDate\", \"DeathDate\", their verbatim date text and places, \"Deceased\", \"ParentFamilies\" and \"SpouseFamilies\"; family records contribute husband, wife, children and marriage dates.  A date is parsed at the granularity the record states, so a year-only entry stays a year rather than becoming a January 1st.  Option CharacterEncoding (default Automatic, meaning UTF-8).";
ExportGEDCOM::usage = "ExportGEDCOM[path, ft] writes a FamilyTree to path as a GEDCOM 5.5.1 file: one INDI record per person with the name, GIVN, _MIDN (patronymic), SURN, _MARNM (married surname), SEX, BIRT and DEAT events with their verbatim date text and places, FAMC and FAMS links, and one FAM record per family with HUSB, WIFE and CHIL.  A tree read with ImportGEDCOM and written again reproduces its records.  Options: \"Submitter\" (Automatic keeps the one the tree was read with) and \"LineEnding\".";
ImportFamilyTable::usage = "ImportFamilyTable[path] reads the flat family table a genealogy service exports beside its GEDCOM (one row per person: ID, surname, given name, patronymic, maiden name, sex, birth and death dates and places, status, father, mother, spouse, children) and returns a FamilyTree.  Russian (Genotek) and English column headers are accepted, the delimiter is sniffed, and the father, mother, spouse and children cells, which name people rather than key them, are resolved against the rows by name; the family records a table lacks are rebuilt from those cells across all rows.  Dates are read at the granularity the cell states: day.month.year, month.year or year.  Options: \"Delimiter\" and CharacterEncoding.";
ExportFamilyTable::usage = "ExportFamilyTable[path, ft] writes a FamilyTree to path as the flat family table a genealogy service imports: one row per person, with the current surname in the surname column and the birth surname in the maiden-name column, day.month.year dates, and the father, mother, spouse and children named by their current surname, given name and patronymic.  Options: \"Headers\" (\"Russian\", the Genotek layout, or \"English\"), \"Delimiter\" (\";\"), \"ByteOrderMark\" (True) and \"LineEnding\" (CRLF), whose defaults reproduce the Genotek export byte for byte in layout.";
FamilyTreePlot::usage = "FamilyTreePlot[ft] draws a FamilyTree as a pedigree chart in the style of a genealogy service: the root person at the bottom, ancestors fanning out above with the father's line on the left and the mother's on the right at every generation, each ancestor's own siblings beside them, one rounded card per person carrying the initials, coloured by sex, with the name and the relationship to the root under it and a dark corner when the person is dead, couples joined by a line and children hanging from the union.  FamilyTreePlot[ft, person] centres the chart on that person.  Options: \"Root\" (Automatic picks the person with the most ancestors in the tree), \"Layout\" (\"Pedigree\", or \"Layered\" for everybody in the file generation by generation), \"Direction\" (\"Ancestors\", \"Descendants\" or \"Both\"; the pedigree defaults to ancestors), \"Generations\" (how far from the root to walk), \"Labels\" (which lines a card carries: All, None, Automatic, one of \"Name\", \"Relationship\", \"Years\", \"Dates\", or a list of them in order), \"Highlight\" (people to outline), \"Placeholders\" (dashed father and mother boxes above the people whose parents are unknown), \"Language\" (the language of the relationship labels and of every other word on the picture: \"English\", \"Russian\", \"Spanish\", \"Portuguese\", \"Italian\", \"Latvian\", \"German\" or \"French\"), \"Transliteration\" (None to leave names as written, or \"BGN\", \"Passport\" or \"Scientific\" to romanize them), plus GraphLayout (a built-in embedding, scaled so the cards fit), ImageSize and any other Graph option.";
GenealogySearch::usage = "GenealogySearch[query] searches the genealogical record providers and returns one Tabular of {Provider, Name, Birth, Death, Place, Detail, URL} rows.  query is a name string, or an Association of \"GivenName\", \"MiddleName\", \"Surname\", \"BirthYear\", \"DeathYear\", \"Place\" and \"Text\".  GenealogySearch[ft, person] builds the query from a FamilyTree record.  Providers come in four classes: \"Open\" ones (WikiTree, OpenList, Wikidata, OpenArchives) are queried through their public API; \"Credential\" ones (FamilySearch, Geni) stay dormant until a token is set in the environment or SystemCredential; \"Browser\" ones (PamyatNaroda, YandexArchive, FindAGrave) publish no API and are searched by driving a real browser through Playwright, using the session GenealogyLogin stored for them, and degrade to a deep search link when the runner cannot start or the archive answers with a security check.  GenealogySearch[\"Providers\"] tabulates them with their current availability.  Options: \"Providers\", \"MaxResults\", \"IncludeLinks\", \"Browser\" (False keeps the browser-class providers in link mode).  A call sends the queried name and dates to the selected third-party services.";
GenealogyLogin::usage = "GenealogyLogin[provider] opens a browser window at the sign-in page of a browser-class GenealogySearch provider (\"PamyatNaroda\", \"YandexArchive\" or \"FindAGrave\"), waits for you to sign in and close the window, and saves the resulting session so later searches run as that account.  No password reaches the kernel: the browser collects it and only the cookies are written, to a per-user file under $UserBaseDirectory (or under GENOME_BROWSER_STATE), never into the paclet or the repository.  Returns the path of the saved session, or $Failed.";

Begin["`Private`"];

(* Implementation split across files by concern.  Each is a raw
   definition file Get-loaded here, inside the
   WolframInstitute`Genome`Private` context, in dependency order
   (shared helpers first).  Public ::usage strings are declared above;
   see wl/GUIDE.md.  The Genome head itself lives in GenomeObject.wl:
   this file is the paclet's umbrella and already owns the name
   Genome.wl. *)
With[{dir = DirectoryName[$InputFileName]},
    Scan[
        Get[FileNameJoin[Prepend[FileNameSplit[#], dir]]] &,
        {
            "Common.wl",
            "VCF.wl",
            "Backends.wl",
            "GenomeObject.wl",
            "HumanGenome.wl",
            "Interpretation/Ancestry.wl",
            "Interpretation/ClinVar.wl",
            "Interpretation/AlphaMissense.wl",
            "Interpretation/Traits.wl",
            "Interpretation/Carrier.wl",
            "Interpretation/PRS.wl",
            "Interpretation/GWAS.wl",
            "Interpretation/Pharmacogenomics.wl",
            "Query.wl",
            "Interpretation/Report.wl",
            "Genealogy/GEDCOM.wl",
            "Genealogy/Kinship.wl",
            "Genealogy/Names.wl",
            "Genealogy/FamilyTree.wl",
            "Genealogy/Table.wl",
            "Genealogy/Search.wl",
            "Formats.wl"
        }
    ]
]

End[];
EndPackage[];

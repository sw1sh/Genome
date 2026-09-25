(* Genome.wlt - VerificationTest specs for the WolframInstitute/Genome paclet.

   Run via:  wolframscript -f Genome/Tests/run.wls

   The runner loads the paclet (PacletDirectoryLoad + Get) before
   invoking TestReport on this file, so this file is purely test data.

   ImportVCFHeader / ImportVCF / GenotypeLookup / RegionVariants /
   VariantSummary are real and exercised against the owner's actual
   ~9.4 GB VCF.  ImportGenotypeArray and ToBioSequence remain stubs
   and their ::nyi behaviour is pinned by the tests below.

   The real-file tests are guarded with FileExistsQ so a fresh checkout
   (where no data/*_genome.vcf.gz is present) still loads this test
   file cleanly; a warning is written to stdout in that case.
*)

(* Resolve the sample VCF relative to the loaded paclet rather than hard-coding
   an absolute path, so the suite runs from any checkout location.  The paclet is
   loaded before the tests (run.wls does PacletDirectoryLoad + Get), so its
   Location gives <repo>/Genome; the data directory sits beside it, at <repo>/data.  The
   file is found by GLOB, never by subject name: this suite ships inside the
   published paclet, so it must not carry an identifier for whoever's genome it
   was run against.  An explicit GENOME_VCF environment variable overrides this. *)
realVCF = Block[{envPath = Environment["GENOME_VCF"], loc, dataDir, found},
    If[ StringQ[envPath],
        envPath,
        loc = PacletObject["WolframInstitute/Genome"]["Location"];
        dataDir = FileNameJoin[{ParentDirectory[loc], "data"}];
        found = Sort @ FileNames["*_genome.vcf.gz", dataDir];
        If[ found === {}, FileNameJoin[{dataDir, "genome.vcf.gz"}], First[found]]
    ]
];
realVCFAvailable = FileExistsQ[realVCF];

(* The sample name is READ from the file, never written down as a literal: the
   assertions below check that every API agrees on the sample list, which is the
   actual behaviour under test, without recording whose sample it is. *)
realSample = If[ realVCFAvailable,
    Replace[Quiet @ First[ImportVCFHeader[realVCF]["Samples"], $Failed], Except[_String] -> Missing["Unknown"]],
    Missing["NoFile"]
];

If[ !realVCFAvailable,
    WriteString["stdout",
        "  NOTE  no data/*_genome.vcf.gz found (looked at ", realVCF,
        ") - skipping real-file VCF tests\n"
    ]
]

(* === package loads === *)

VerificationTest[
    MemberQ[$Packages, "WolframInstitute`Genome`"],
    True,
    TestID -> "Genome package is loaded"
]

(* === public symbols carry usage strings === *)

VerificationTest[
    AllTrue[
        {Genome, GenomeQ, ImportVCF, ImportVCFHeader, ImportGenotypeArray,
         GenomeToParquet, GenotypeLookup, RegionVariants, VariantSummary,
         ToBioSequence, HumanGenome, HumanGenomeQ, ChromosomalSex,
         AncestryEstimate, HaplogroupCall, PharmacogenomicProfile, ClinVarHits,
         PolygenicRiskScore, TraitAssociations, AlphaMissenseScores,
         CarrierStatus, GWASAssociations, GenomeReport,
         FamilyTree, FamilyTreeQ, ImportGEDCOM, FamilyTreePlot, GenealogySearch,
         GenealogyLogin, ImportFamilyTable, ExportFamilyTable, ExportGEDCOM},
        StringQ[#::usage] &
    ],
    True,
    TestID -> "every public symbol has a ::usage string"
]

(* === GenomeQ shape check === *)

VerificationTest[
    GenomeQ[Genome[<|"Path" -> "x"|>]],
    False,
    TestID -> "GenomeQ rejects incomplete payload"
]

VerificationTest[
    GenomeQ["not a genome"],
    False,
    TestID -> "GenomeQ rejects non-Genome values"
]

(* === still-stub functions issue ::nyi and return $Failed === *)

VerificationTest[
    ImportGenotypeArray["dummy.txt"],
    $Failed,
    {ImportGenotypeArray::nyi},
    TestID -> "ImportGenotypeArray stub issues ::nyi and returns $Failed"
]

VerificationTest[
    ToBioSequence[Null],
    $Failed,
    {ToBioSequence::nyi},
    TestID -> "ToBioSequence stub issues ::nyi and returns $Failed"
]

(* === Parquet backend: missing sidecar === *)

VerificationTest[
    Block[{tmpVCF, res},
        tmpVCF = FileNameJoin[{$TemporaryDirectory, "wlgenome_parquet_probe.vcf"}];
        Export[
            tmpVCF,
            "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\nchr1\t100\trs1\tA\tG\t60\tPASS\t.\tGT\t0/1\n",
            "Text"
        ];
        (* Explicit "Parquet" backend on a fixture without a sidecar
           should surface ::parquetMissing on materialisation. *)
        res = Quiet[
            Genome[<|
                "Path" -> tmpVCF,
                "Header" -> <||>,
                "Samples" -> {"s1"},
                "Build" -> "GRCh37/hg19",
                "Backend" -> "Parquet",
                "Filters" -> {},
                "VariantCountCache" -> Missing["NotComputed"]
            |>]["Variants"],
            {Genome::parquetMissing}
        ];
        {res, DeleteFile[tmpVCF]; True}[[1]]
    ],
    $Failed,
    TestID -> "Parquet backend without sidecar returns $Failed"
]

(* === Parquet backend fixture ===
   Build a small VCF fixture (three real variants plus two runs of
   reference-confirming rows), convert it to the Parquet sidecar set with
   GenomeToParquet, and exercise the Parquet read path.  Needs only
   Export / Import Parquet (WL 15.0 built-in) plus gzcat / awk (POSIX), so
   it runs on every checkout with no external tools and no real file. *)

parquetFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_parquet_fixture"}];
Quiet @ If[ DirectoryQ[parquetFixtureDir], DeleteDirectory[parquetFixtureDir, DeleteContents -> True]];
CreateDirectory[parquetFixtureDir];
parquetFixtureVCF = FileNameJoin[{parquetFixtureDir, "pqfix.vcf"}];
Export[
    parquetFixtureVCF,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n##INFO=<ID=R2,Number=1,Type=Float,Description=\"r2\">\n##INFO=<ID=AF,Number=1,Type=Float,Description=\"af\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\nchr1\t100\trs100\tA\tG\t60\tPASS\tAF=0.3;R2=0.9;IMPUTED\tGT\t0/1\nchr1\t101\t.\tC\t.\t.\t.\t.\tGT\t0/0\nchr1\t102\t.\tG\t.\t.\t.\t.\tGT\t0/0\nchr1\t103\t.\tT\t.\t.\t.\t.\tGT\t0/0\nchr1\t200\trs200\tG\tA\t60\tPASS\tTYPED\tGT\t1/1\nchr1\t300\t.\tA\t.\t.\t.\t.\tGT\t0/0\nchr1\t301\t.\tC\t.\t.\t.\t.\tGT\t0/0\nchr1\t400\trs400\tT\tC\t60\tPASS\tAF=0.5;R2=0.95\tGT\t0/1\n",
    "Text"
];
parquetFixtureRes = GenomeToParquet[
    ImportVCF[parquetFixtureVCF, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False]
];
parquetFixtureG = ImportVCF[parquetFixtureVCF, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];

VerificationTest[
    AllTrue[Values[parquetFixtureRes], FileExistsQ],
    True,
    TestID -> "GenomeToParquet writes the three sidecar files"
]

VerificationTest[
    parquetFixtureG["Backend"],
    "Parquet",
    TestID -> "ImportVCF auto-selects the Parquet backend when a sidecar exists"
]

VerificationTest[
    {Head[parquetFixtureG["Variants"]], Length[parquetFixtureG["Variants"]]},
    {Tabular, 3},
    TestID -> "Parquet-backed Variants returns a 3-row Tabular"
]

VerificationTest[
    Keys[First[Normal[parquetFixtureG["Variants"]]]],
    {"CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO_raw", "AF",
     "MAF", "R2", "ER2", "AC", "AN", "IMPUTED", "TYPED", "TYPED_ONLY",
     "FORMAT", "GT_s1"},
    TestID -> "Parquet-backed Variants has the exploded-INFO column schema"
]

VerificationTest[
    Sort[Lookup[#, "ID"] & /@ Normal[parquetFixtureG["Variants"]]],
    {"rs100", "rs200", "rs400"},
    TestID -> "Parquet-backed Variants contains only the real-variant rsIDs"
]

VerificationTest[
    Lookup[#, "ID", Missing[]] & /@ Normal[parquetFixtureG["Region", "chr1", {100, 250}]],
    {"rs100", "rs200"},
    TestID -> "Parquet-backed Region query returns the in-interval rsIDs"
]

VerificationTest[
    Block[{r = GenotypeLookup[parquetFixtureG, "rs200"]},
        {r["CHROM"], r["POS"], r["GT_s1"]}
    ],
    {"chr1", 200, "1/1"},
    TestID -> "GenotypeLookup on a Parquet-backed Genome finds a known rsID"
]

VerificationTest[
    Length[Import[parquetFixtureRes["RefBlocks"], "Tabular"]],
    2,
    TestID -> "GenomeToParquet collapses the reference rows into 2 intervals"
]

(* === VariantSummary on an empty row set ===
   Lookup[{}, "CHROM"] gives Missing["KeyAbsent", ...] rather than an empty list,
   so an empty Tabular used to reach Counts as a Missing and raise Counts::invrp
   followed by KeySortBy::invrl.  A region query that selects nothing, or a handle
   over a file with no matching rows, hits this. *)

VerificationTest[
    Block[{r = Normal[VariantSummary[Tabular[{}]]]},
        {Lookup[First[r], "Value"], Lookup[r[[3]], "Value"]}
    ],
    {0, <||>},
    TestID -> "VariantSummary on an empty Tabular gives zero rows and no chromosomes"
];

VerificationTest[
    Block[{msgs = {}},
        Internal`HandlerBlock[{"MessageTextFilter", (AppendTo[msgs, #] &)},
            Quiet @ VariantSummary[Tabular[{}]]
        ];
        FreeQ[msgs, Counts::invrp | KeySortBy::invrl]
    ],
    True,
    TestID -> "VariantSummary on an empty Tabular issues no Counts / KeySortBy messages"
];

(* === Tabix backend fixture ===
   Build a tiny 6-variant BGZF+tbi test fixture in $TemporaryDirectory
   and run a Region query against it via the Tabix backend.  Skip
   cleanly when bcftools / tabix / bgzip are not on PATH. *)

tabixToolsAvailable = And[
    MatchQ[RunProcess[{"sh", "-c", "command -v bgzip"}], KeyValuePattern["ExitCode" -> 0]],
    MatchQ[RunProcess[{"sh", "-c", "command -v tabix"}], KeyValuePattern["ExitCode" -> 0]],
    MatchQ[RunProcess[{"sh", "-c", "command -v bcftools"}], KeyValuePattern["ExitCode" -> 0]]
];

If[ !tabixToolsAvailable,
    WriteString["stdout",
        "  NOTE  bgzip / tabix / bcftools not on PATH - skipping Tabix backend test\n"
    ]
]

If[ tabixToolsAvailable,
    VerificationTest[
        Block[{tmpDir, tmpVCF, tmpBgz, tmpTbi, contents, bgzipRes, tabixRes, g, tbxrows},
            tmpDir = $TemporaryDirectory;
            tmpVCF = FileNameJoin[{tmpDir, "wlgenome_tabix_probe.vcf"}];
            tmpBgz = tmpVCF <> ".gz";
            tmpTbi = tmpBgz <> ".tbi";
            (* Delete any prior fixture so bgzip -f is not strictly needed. *)
            Quiet @ DeleteFile[tmpVCF];
            Quiet @ DeleteFile[tmpBgz];
            Quiet @ DeleteFile[tmpTbi];
            contents = "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n##INFO=<ID=DP,Number=1,Type=Integer,Description=\"depth\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\nchr1\t100\trs100\tA\tG\t60\tPASS\tDP=10\tGT\t0/1\nchr1\t150\trs150\tC\tT\t60\tPASS\tDP=12\tGT\t0/1\nchr1\t200\trs200\tG\tA\t60\tPASS\tDP=15\tGT\t1/1\nchr1\t250\trs250\tT\tC\t60\tPASS\tDP=8\tGT\t0/1\nchr1\t300\trs300\tA\tT\t60\tPASS\tDP=20\tGT\t0/0\nchr1\t400\trs400\tG\tC\t60\tPASS\tDP=5\tGT\t0/1\n";
            Export[tmpVCF, contents, "Text"];
            bgzipRes = RunProcess[{"sh", "-c", "bgzip -f " <> tmpVCF}];
            tabixRes = RunProcess[{"sh", "-c", "tabix -p vcf -f " <> tmpBgz}];
            g = ImportVCF[tmpBgz, "Backend" -> "Tabix", "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];
            tbxrows = Normal @ g["Region", "chr1", {100, 300}];
            (* Cleanup. *)
            Quiet @ DeleteFile[tmpBgz];
            Quiet @ DeleteFile[tmpTbi];
            {
                g["Backend"],
                Length[tbxrows],
                Lookup[#, "ID", Missing[]] & /@ tbxrows
            }
        ],
        {"Tabix", 5, {"rs100", "rs150", "rs200", "rs250", "rs300"}},
        TestID -> "Tabix backend region query returns the expected rsIDs"
    ]
]

(* === backend priority: Tabix wins over Parquet, Region always seeks via Tabix ===
   Build a fixture that has BOTH a .tbi index and a .parquet sidecar.  Auto-
   selection must prefer Tabix (fast positional seeks + canonical row shape)
   over Parquet (opt-in analytical columnar table), and a Region query must
   route through the Tabix seek even when the backend is explicitly Parquet. *)

If[ tabixToolsAvailable,
    VerificationTest[
        Block[{tmpDir, vcf, bgz, tbi, pq, rbpq, hdr, contents, gAuto, gParq, regionIDs},
            tmpDir = $TemporaryDirectory;
            vcf = FileNameJoin[{tmpDir, "wlgenome_priority_probe.vcf"}];
            bgz = vcf <> ".gz";
            tbi = bgz <> ".tbi";
            pq = bgz <> ".parquet";
            rbpq = bgz <> ".refblocks.parquet";
            hdr = bgz <> ".header.vcf";
            Quiet[DeleteFile /@ {vcf, bgz, tbi, pq, rbpq, hdr}];
            contents = "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n##INFO=<ID=DP,Number=1,Type=Integer,Description=\"d\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\nchr1\t100\trs100\tA\tG\t60\tPASS\tDP=10\tGT\t0/1\nchr1\t150\trs150\tC\tT\t60\tPASS\tDP=12\tGT\t0/1\nchr1\t200\trs200\tG\tA\t60\tPASS\tDP=15\tGT\t1/1\nchr1\t300\trs300\tA\tT\t60\tPASS\tDP=8\tGT\t0/1\n";
            Export[vcf, contents, "Text"];
            RunProcess[{"sh", "-c", "bgzip -f " <> vcf}];
            RunProcess[{"sh", "-c", "tabix -p vcf -f " <> bgz}];
            (* build the Parquet sidecar too, so bgz has BOTH .tbi and .parquet *)
            GenomeToParquet[ImportVCF[bgz, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False]];
            gAuto = ImportVCF[bgz, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];
            gParq = ImportVCF[bgz, "Backend" -> "Parquet", "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];
            regionIDs = Lookup[#, "ID", Missing[]] & /@ Normal[gParq["Region", "chr1", {100, 250}]];
            Quiet[DeleteFile /@ {bgz, tbi, pq, rbpq, hdr}];
            {gAuto["Backend"], regionIDs}
        ],
        {"Tabix", {"rs100", "rs150", "rs200"}},
        TestID -> "Auto-selection prefers Tabix over Parquet; Region seeks via Tabix under Backend->Parquet"
    ]
]

(* === HumanGenome autopromotion + wrapper mechanics (fixture-based) ===
   These run on every checkout: small GRCh37 VCF fixtures in
   $TemporaryDirectory exercise the autopromotion rule, the wrapper
   forwarding, the interpretation slot reads, and the operator stubs
   without needing the real 9.4 GB file. *)

humanFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_human_fixture"}];
Quiet @ If[ DirectoryQ[humanFixtureDir], DeleteDirectory[humanFixtureDir, DeleteContents -> True]];
CreateDirectory[humanFixtureDir];

humanSingleVCF = FileNameJoin[{humanFixtureDir, "single.vcf"}];
Export[
    humanSingleVCF,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\nchr1\t100\trs100\tA\tG\t60\tPASS\t.\tGT\t0/1\n",
    "Text"
];
humanSingleG = ImportVCF[humanSingleVCF, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];
humanSingleGen = ImportVCF[humanSingleVCF, "Human" -> False, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];

humanMultiVCF = FileNameJoin[{humanFixtureDir, "multi.vcf"}];
Export[
    humanMultiVCF,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\ts1\ts2\nchr1\t100\trs100\tA\tG\t60\tPASS\t.\tGT\t0/1\t0/0\n",
    "Text"
];
humanMultiG = ImportVCF[humanMultiVCF, "PASSOnly" -> False, "ExcludeReferenceOnly" -> False];

VerificationTest[
    {Head[humanSingleG], HumanGenomeQ[humanSingleG], GenomeQ[humanSingleG]},
    {HumanGenome, True, True},
    TestID -> "ImportVCF autopromotes a GRCh37 single-sample fixture to HumanGenome"
]

VerificationTest[
    {Head[humanMultiG], HumanGenomeQ[humanMultiG], GenomeQ[humanMultiG], humanMultiG["Samples"]},
    {Genome, False, True, {"s1", "s2"}},
    TestID -> "ImportVCF keeps a multi-sample human VCF as a generic Genome"
]

VerificationTest[
    {Head[humanSingleGen], HumanGenomeQ[humanSingleGen], GenomeQ[humanSingleGen]},
    {Genome, False, True},
    TestID -> "ImportVCF \"Human\" -> False opts out of autopromotion"
]

VerificationTest[
    {GenomeQ[humanSingleG], GenomeQ[humanMultiG], HumanGenomeQ[humanSingleG], HumanGenomeQ[humanMultiG]},
    {True, True, True, False},
    TestID -> "GenomeQ accepts both heads; HumanGenomeQ accepts only the wrapper"
]

VerificationTest[
    {humanSingleG["Ancestry"], humanSingleG["ClinVarHits"], humanSingleG["Subject", "ID"],
     humanSingleG["References", "CPICVersion"]},
    {Missing["NotComputed"], Missing["NotComputed"], "s1", Missing["NotComputed"]},
    TestID -> "HumanGenome interpretation slot reads return the cached Missing[\"NotComputed\"]"
]

VerificationTest[
    {humanSingleG["Build"], humanSingleG["Samples"], humanSingleG["Backend"]},
    {"GRCh37/hg19", {"s1"}, "AwkStream"},
    TestID -> "HumanGenome forwards Build / Samples / Backend to the inner Genome"
]

VerificationTest[
    Block[{f = humanSingleG["Chromosome", "chr1"]},
        {HumanGenomeQ[f], MatchQ[f, _HumanGenome], f["Ancestry"],
         MemberQ[f["Filters"], "Chromosome" -> "chr1"]}
    ],
    {True, True, Missing["NotComputed"], True},
    TestID -> "Filter accumulation on a HumanGenome returns a HumanGenome preserving the annotation"
]

VerificationTest[
    GenotypeLookup[humanSingleG, "rs100"] === GenotypeLookup[humanSingleGen, "rs100"],
    True,
    TestID -> "GenotypeLookup returns identical results on HumanGenome and Genome"
]

VerificationTest[
    Normal[RegionVariants[humanSingleG, "chr1", {1, 1000}]]
        === Normal[RegionVariants[humanSingleGen, "chr1", {1, 1000}]],
    True,
    TestID -> "RegionVariants returns identical results on HumanGenome and Genome"
]

VerificationTest[
    Normal[VariantSummary[humanSingleG]] === Normal[VariantSummary[humanSingleGen]],
    True,
    TestID -> "VariantSummary returns identical results on HumanGenome and Genome"
]

VerificationTest[
    Head[ToBoxes[humanSingleG, StandardForm]],
    InterpretationBox,
    TestID -> "HumanGenome MakeBoxes produces an InterpretationBox"
]

(* An interpretable box holds the whole expression, so a genome whose slots are
   filled would carry its interpretation tables into the notebook source while
   displaying only counts.  Once anything is computed the box must stop being
   interpretable, and the payload must not appear in it. *)
VerificationTest[
    Head[ToBoxes[
        Replace[humanSingleG, HumanGenome[g_, ann_] :> HumanGenome[g,
            Append[ann, "ClinVarHits" -> Tabular[{<|"Gene" -> "SECRETGENE"|>}]]]],
        StandardForm]] === InterpretationBox,
    False,
    TestID -> "HumanGenome MakeBoxes drops interpretability once a slot is computed"
]

VerificationTest[
    StringContainsQ[
        ToString[ToBoxes[
            Replace[humanSingleG, HumanGenome[g_, ann_] :> HumanGenome[g,
                Append[ann, "ClinVarHits" -> Tabular[{<|"Gene" -> "SECRETGENE"|>}]]]],
            StandardForm], InputForm],
        "SECRETGENE"],
    False,
    TestID -> "a computed slot's contents never reach the HumanGenome summary box"
]

VerificationTest[
    ChromosomalSex[humanSingleG],
    $Failed,
    {ChromosomalSex::noindex},
    TestID -> "ChromosomalSex on a fixture without a tabix index issues ::noindex and returns $Failed"
]

VerificationTest[
    HaplogroupCall[humanSingleG, "notAKind"],
    $Failed,
    {HaplogroupCall::badkind},
    TestID -> "HaplogroupCall rejects an unknown kind with ::badkind"
]

VerificationTest[
    PharmacogenomicProfile[humanSingleG],
    $Failed,
    {PharmacogenomicProfile::noref},
    TestID -> "PharmacogenomicProfile on a fixture without a tabix index issues ::noref and returns $Failed"
]

VerificationTest[
    PolygenicRiskScore[humanSingleG, "not a real trait"],
    $Failed,
    {PolygenicRiskScore::unknownTrait},
    TestID -> "PolygenicRiskScore rejects an unknown trait with ::unknownTrait"
]

(* === GenomeReport aggregation (fixture, no network) ===
   Build a HumanGenome directly with two interpretation slots pre-populated
   (synthetic Ancestry Association + a small Pharmacogenomics Tabular) and the
   rest left Missing["NotComputed"].  GenomeReport["Compute" -> "Cached"] must
   aggregate the populated slots, mark the rest as not-run, and write a rendered
   report file - all without touching the network or a real genome. *)

reportFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_report_fixture"}];
Quiet @ If[ DirectoryQ[reportFixtureDir], DeleteDirectory[reportFixtureDir, DeleteContents -> True]];
CreateDirectory[reportFixtureDir];

reportFixtureVCF = FileNameJoin[{reportFixtureDir, "rfix.vcf"}];
Export[reportFixtureVCF, "placeholder", "Text"];

reportFixtureG = Genome[<|
    "Path" -> reportFixtureVCF,
    "Header" -> <||>,
    "Samples" -> {"rfix"},
    "Build" -> "GRCh37/hg19",
    "Backend" -> "AwkStream",
    "Filters" -> {},
    "VariantCountCache" -> 4242
|>];

reportFixturePgx = Tabular[{
    <|"Gene" -> "CYP2C19", "Diplotype" -> "*1/*2", "Phenotype" -> "Intermediate Metabolizer",
      "ActionableDrug" -> "clopidogrel", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> 1.0, "Confidence" -> "ok"|>,
    <|"Gene" -> "CYP2D6", "Diplotype" -> "*1/*1", "Phenotype" -> "Normal Metabolizer",
      "ActionableDrug" -> "codeine", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> 2.0, "Confidence" -> "ok"|>
}];

reportFixtureHG = HumanGenome[reportFixtureG, <|
    "References" -> <|"Build" -> "GRCh37/hg19"|>,
    "Subject" -> <|"ID" -> "rfix", "Sex" -> "XX"|>,
    "Ancestry" -> <|
        "Superpopulation" -> "EUR",
        "SuperpopulationFractions" -> <|"EUR" -> 0.8, "SAS" -> 0.2|>,
        "NearestPopulations" -> {"EUR", "SAS"}
    |>,
    "Haplogroups" -> Missing["NotComputed"],
    "Pharmacogenomics" -> reportFixturePgx,
    "ClinVarHits" -> Missing["NotComputed"],
    "PRS" -> Missing["NotComputed"],
    "Traits" -> Missing["NotComputed"],
    "AlphaMissenseScores" -> Missing["NotComputed"],
    "Carrier" -> Missing["NotComputed"],
    "GWASAssociations" -> Missing["NotComputed"],
    "ReportCache" -> Missing["NotComputed"]
|>];

reportFixtureResult = GenomeReport[reportFixtureHG, "Compute" -> "Cached"];

VerificationTest[
    Keys[reportFixtureResult],
    {"Overview", "Ancestry", "Pharmacogenomics", "ClinicalVariants", "CarrierStatus",
     "PolygenicRiskScores", "Traits", "GWASHighlights", "MissenseHighlights", "ReportFile"},
    TestID -> "GenomeReport returns the section keys plus ReportFile"
]

VerificationTest[
    {reportFixtureResult["Overview", "Subject"], reportFixtureResult["Overview", "Sex"],
     reportFixtureResult["Overview", "Build"], reportFixtureResult["Overview", "VariantCount"]},
    {"rfix", "XX", "GRCh37/hg19", 4242},
    TestID -> "GenomeReport Overview carries subject, sex, build, and the cached variant count"
]

VerificationTest[
    reportFixtureResult["Ancestry", "Superpopulation"],
    "EUR",
    TestID -> "GenomeReport populates the Ancestry section from the pre-filled slot"
]

VerificationTest[
    {reportFixtureResult["Pharmacogenomics", "ActionableGuidanceCount"],
     reportFixtureResult["Pharmacogenomics", "NormalGeneCount"]},
    {1, 1},
    TestID -> "GenomeReport Pharmacogenomics section separates the actionable and normal genes"
]

VerificationTest[
    {MissingQ[reportFixtureResult["ClinicalVariants"]], MissingQ[reportFixtureResult["Traits"]]},
    {True, True},
    TestID -> "GenomeReport marks un-computed sections Missing"
]

VerificationTest[
    Sort @ reportFixtureResult["Overview", "SectionsAvailable"],
    Sort @ {"Ancestry", "Pharmacogenomics"},
    TestID -> "GenomeReport Overview lists the populated sections as available"
]

VerificationTest[
    MemberQ[reportFixtureResult["Overview", "SectionsNotRun"], "ClinicalVariants"]
        && ! MemberQ[reportFixtureResult["Overview", "SectionsNotRun"], "Ancestry"],
    True,
    TestID -> "GenomeReport Overview lists the un-computed sections as not-run"
]

VerificationTest[
    StringQ[reportFixtureResult["ReportFile"]] && FileExistsQ[reportFixtureResult["ReportFile"]],
    True,
    TestID -> "GenomeReport writes a rendered report file and returns its path"
]

VerificationTest[
    Block[{html = Import[reportFixtureResult["ReportFile"], "Text"]},
        StringContainsQ[html, "decision-support"] && StringContainsQ[html, "clinician"]
            && StringContainsQ[html, "Overview"]
    ],
    True,
    TestID -> "The rendered report leads with the decision-support caveat"
]

VerificationTest[
    Keys @ GenomeReport[reportFixtureHG, "Compute" -> "Cached", "Sections" -> {"Overview", "Ancestry"}],
    {"Overview", "Ancestry", "ReportFile"},
    TestID -> "GenomeReport \"Sections\" restricts the output to the named sections"
]

(* The default English report keeps the English section headers and lang="en";
   this pins that "Language" -> "English" is unchanged by localization.  Re-render
   inline so the assertion does not depend on an earlier test overwriting the
   shared per-subject report file. *)
VerificationTest[
    Block[{html = Import[GenomeReport[reportFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "<html lang=\"en\">"] && StringContainsQ[html, "<h2>Overview</h2>"]
            && StringContainsQ[html, "Pharmacogenomics"] && ! StringContainsQ[html, "Обзор"]
    ],
    True,
    TestID -> "GenomeReport default English keeps English headers and lang=en"
]

(* Russian localization: the written HTML round-trips Cyrillic (imported back as
   UTF-8), carries lang="ru" plus a UTF-8 charset, translates the section
   headers and the caveat, translates the controlled-vocabulary data terms
   (sex karyotype, superpopulation code, metabolizer phenotype), and leaves
   scientific identifiers (gene symbols, star-allele diplotypes) untranslated. *)
reportFixtureRU = GenomeReport[reportFixtureHG, "Compute" -> "Cached", "Language" -> "Russian"];

VerificationTest[
    Block[{html = Import[reportFixtureRU["ReportFile"], "Text"]},
        StringContainsQ[html, "<html lang=\"ru\">"]
            && StringContainsQ[html, "<meta charset=\"utf-8\">"]
            && StringContainsQ[html, "<h2>Обзор</h2>"]
            && StringContainsQ[html, "<h2>Фармакогенетика</h2>"]
            && StringContainsQ[html, "образовательный"]
    ],
    True,
    TestID -> "GenomeReport \"Language\" -> \"Russian\" writes lang=ru UTF-8 HTML with Russian headers and caveat"
]

VerificationTest[
    Block[{html = Import[reportFixtureRU["ReportFile"], "Text"]},
        StringContainsQ[html, "Женский (XX)"]
            && StringContainsQ[html, "Европейская (EUR)"]
            && StringContainsQ[html, "Промежуточный метаболизатор"]
            && StringContainsQ[html, "CYP2C19"] && StringContainsQ[html, "*1/*2"]
    ],
    True,
    TestID -> "GenomeReport Russian translates controlled vocabulary and keeps scientific identifiers"
]

VerificationTest[
    Block[{r = GenomeReport[reportFixtureHG, "Compute" -> "Cached", "Language" -> "Klingon"]},
        StringContainsQ[Import[r["ReportFile"], "Text"], "<h2>Overview</h2>"]
    ],
    True,
    {GenomeReport::badlang},
    TestID -> "GenomeReport unknown \"Language\" warns and falls back to English"
]

(* Consumer-oriented rendering: every section carries a plain-language intro with
   abbreviations expanded on first use, and the report ends with a bilingual
   glossary appendix whose terms link to authoritative educational resources.
   Re-render inline so the assertion does not depend on the shared per-subject
   report file an earlier test overwrote. *)
VerificationTest[
    Block[{html = Import[GenomeReport[reportFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "class=\"intro\""]
            && StringContainsQ[html, "polygenic risk score (PRS)"]
            && StringContainsQ[html, "genome-wide association study (GWAS)"]
            && StringContainsQ[html, "healthy carrier"]
    ],
    True,
    TestID -> "GenomeReport English adds plain-language section intros with abbreviations expanded on first use"
]

VerificationTest[
    Block[{html = Import[GenomeReport[reportFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "<h2>Glossary</h2>"]
            && StringContainsQ[html, "<h3>Variants</h3>"]
            && StringContainsQ[html, "<h3>Pharmacogenomics</h3>"]
            && StringContainsQ[html, "<dt>gnomAD</dt>"]
            && StringContainsQ[html, "<dt>ClinVar</dt>"]
            && StringContainsQ[html, "https://gnomad.broadinstitute.org/"]
            && StringContainsQ[html, "https://www.pgscatalog.org/"]
            && StringContainsQ[html, "target=\"_blank\""]
    ],
    True,
    TestID -> "GenomeReport English appends a glossary appendix with categorized terms and educational links"
]

VerificationTest[
    Block[{html = Import[GenomeReport[reportFixtureHG, "Compute" -> "Cached", "Language" -> "Russian"]["ReportFile"], "Text"]},
        StringContainsQ[html, "<h2>Глоссарий</h2>"]
            && StringContainsQ[html, "Полигенная шкала риска (PRS)"]
            && StringContainsQ[html, "здоровым носителем"]
            && StringContainsQ[html, "<h3>Варианты</h3>"]
            && StringContainsQ[html, "Подробнее"]
            && StringContainsQ[html, "ru.wikipedia.org"]
            && StringContainsQ[html, "gnomAD"]
    ],
    True,
    TestID -> "GenomeReport Russian adds Russian section intros and a Russian glossary appendix with links"
]

(* === GenomeReport polygenic-risk interpretation (fixture, no network) ===
   Build a HumanGenome with a pre-populated "PRS" slot: a HigherIsRisk trait at a
   high percentile (Triglycerides), a Neutral trait (Height), and an entry with a
   Missing["NoReference"] percentile (a raw score that could not be placed on a
   population distribution).  The enriched PRS section must render, for each
   trait, a percentile band, a plain-language interpretation reflecting the
   direction of health concern, and a muted PGS / coverage note - in both
   languages - and must explain the no-percentile case. *)

reportPRSFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_report_prs_fixture"}];
Quiet @ If[ DirectoryQ[reportPRSFixtureDir], DeleteDirectory[reportPRSFixtureDir, DeleteContents -> True]];
CreateDirectory[reportPRSFixtureDir];

reportPRSFixtureVCF = FileNameJoin[{reportPRSFixtureDir, "rprs.vcf"}];
Export[reportPRSFixtureVCF, "placeholder", "Text"];

reportPRSFixtureG = Genome[<|
    "Path" -> reportPRSFixtureVCF,
    "Header" -> <||>,
    "Samples" -> {"rprs"},
    "Build" -> "GRCh37/hg19",
    "Backend" -> "AwkStream",
    "Filters" -> {},
    "VariantCountCache" -> 4242
|>];

reportPRSFixturePRS = <|
    "PGS000066" -> <|"Score" -> 1.23, "Percentile" -> 0.99, "PGSID" -> "PGS000066",
        "Trait" -> "Triglycerides", "NVariantsUsed" -> 47, "NVariantsExpected" -> 50,
        "Method" -> "NormalApproximation:PGSAlleleFrequency"|>,
    "PGS000297" -> <|"Score" -> 0.5, "Percentile" -> 0.92, "PGSID" -> "PGS000297",
        "Trait" -> "Height", "NVariantsUsed" -> 900, "NVariantsExpected" -> 1000,
        "Method" -> "NormalApproximation:SubjectPanelAF"|>,
    "PGS999999" -> <|"Score" -> 2.0, "Percentile" -> Missing["NoReference"], "PGSID" -> "PGS999999",
        "Trait" -> "Some raw score", "NVariantsUsed" -> 5, "NVariantsExpected" -> 400,
        "Method" -> "None"|>
|>;

reportPRSFixtureHG = HumanGenome[reportPRSFixtureG, <|
    "References" -> <|"Build" -> "GRCh37/hg19"|>,
    "Subject" -> <|"ID" -> "rprs", "Sex" -> "XY"|>,
    "Ancestry" -> Missing["NotComputed"],
    "Haplogroups" -> Missing["NotComputed"],
    "Pharmacogenomics" -> Missing["NotComputed"],
    "ClinVarHits" -> Missing["NotComputed"],
    "PRS" -> reportPRSFixturePRS,
    "Traits" -> Missing["NotComputed"],
    "AlphaMissenseScores" -> Missing["NotComputed"],
    "Carrier" -> Missing["NotComputed"],
    "GWASAssociations" -> Missing["NotComputed"],
    "ReportCache" -> Missing["NotComputed"]
|>];

VerificationTest[
    Block[{html = Import[GenomeReport[reportPRSFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "<h3>Triglycerides <span class=\"prs-band\">99th percentile - Very high</span></h3>"]
            && StringContainsQ[html, "class=\"prs-interp\""]
            && StringContainsQ[html, "cardiovascular"]
            && StringContainsQ[html, "<p class=\"prs-meta\">PGS000066, 94% of variants used</p>"]
    ],
    True,
    TestID -> "GenomeReport English PRS shows a percentile band, an interpretation, and a muted PGS/coverage note"
]

VerificationTest[
    Block[{html = Import[GenomeReport[reportPRSFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "<h3>Height <span class=\"prs-band\">92nd percentile - High</span></h3>"]
            && StringContainsQ[html, "not a health risk"]
    ],
    True,
    TestID -> "GenomeReport English PRS marks a Neutral trait as not a health risk"
]

VerificationTest[
    Block[{html = Import[GenomeReport[reportPRSFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"]},
        StringContainsQ[html, "no percentile is available"]
            && StringContainsQ[html, "PGS999999"]
    ],
    True,
    TestID -> "GenomeReport English PRS explains a Missing percentile (no population reference)"
]

reportPRSFixtureRU = GenomeReport[reportPRSFixtureHG, "Compute" -> "Cached", "Language" -> "Russian"];

VerificationTest[
    Block[{html = Import[reportPRSFixtureRU["ReportFile"], "Text"]},
        StringContainsQ[html, "99-й перцентиль - Очень высокий"]
            && StringContainsQ[html, "сердечно-сосудистого"]
            && StringContainsQ[html, "<p class=\"prs-meta\">PGS000066, использовано 94% вариантов</p>"]
            && StringContainsQ[html, "Триглицериды"]
    ],
    True,
    TestID -> "GenomeReport Russian PRS shows the Russian band, interpretation, and coverage note"
]

VerificationTest[
    Block[{html = Import[reportPRSFixtureRU["ReportFile"], "Text"]},
        StringContainsQ[html, "не риск для здоровья"]
            && StringContainsQ[html, "перцентиль недоступен"]
    ],
    True,
    TestID -> "GenomeReport Russian PRS marks the Neutral trait and explains the no-percentile case"
]

(* The direction of health concern flips the framing: a LowerIsRisk trait (HDL,
   the protective cholesterol) at a low percentile reads as the less-favorable
   direction, phrased relative to the complementary share of people. *)
VerificationTest[
    WolframInstitute`Genome`Private`prsInterpretation["PGS000064", 0.19, "English"],
    "Lower than about 81% of people. In plain terms: your genetic tendency for HDL ('good', protective) cholesterol; LOWER is less favorable. Because a low score is the less-favorable direction here, this is the direction of concern. It is a statistical tendency, not a measurement.",
    TestID -> "prsInterpretation frames a LowerIsRisk trait by the complementary percentile"
]

VerificationTest[
    {WolframInstitute`Genome`Private`prsBand[0.99, "English"], WolframInstitute`Genome`Private`prsBand[0.5, "English"],
     WolframInstitute`Genome`Private`prsBand[0.03, "English"], WolframInstitute`Genome`Private`prsBand[0.99, "Russian"]},
    {"Very high", "Average", "Very low", "Очень высокий"},
    TestID -> "prsBand maps percentiles to localized band labels"
]

(* === GenomeReport per-finding interpretation for the bounded sections (fixture) ===
   Build a HumanGenome with the Pharmacogenomics / ClinVarHits / Carrier /
   Ancestry+Haplogroups slots pre-populated with synthetic rows covering the
   branches: a poor + a low-confidence (CYP2D6 CNV-uncallable) + an intermediate
   pharmacogene; a common (high-AF) + a rare (weak-review) ClinVar hit; a
   carrier + a dominant + a homozygous carrier finding; and an ancestry with a
   dominant super-population, small noise fractions, and both haplogroups.  The
   rendered report must give each finding a plain-language interpretation and a
   muted footnote - in both languages - without touching the network. *)

reportInterpFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_report_interp_fixture"}];
Quiet @ If[ DirectoryQ[reportInterpFixtureDir], DeleteDirectory[reportInterpFixtureDir, DeleteContents -> True]];
CreateDirectory[reportInterpFixtureDir];

reportInterpFixtureVCF = FileNameJoin[{reportInterpFixtureDir, "rint.vcf"}];
Export[reportInterpFixtureVCF, "placeholder", "Text"];

reportInterpFixtureG = Genome[<|
    "Path" -> reportInterpFixtureVCF,
    "Header" -> <||>,
    "Samples" -> {"rint"},
    "Build" -> "GRCh37/hg19",
    "Backend" -> "AwkStream",
    "Filters" -> {},
    "VariantCountCache" -> 4242
|>];

reportInterpFixturePgx = Tabular[{
    <|"Gene" -> "CYP2C19", "Diplotype" -> "*2/*2", "Phenotype" -> "Poor Metabolizer",
      "ActionableDrug" -> "clopidogrel", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> "0.0", "Confidence" -> "Called"|>,
    <|"Gene" -> "CYP2D6", "Diplotype" -> "*4/*5", "Phenotype" -> "Poor Metabolizer",
      "ActionableDrug" -> "codeine", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> "0.0",
      "Confidence" -> "Called; CYP2D6 SNV-only: CNV / hybrid alleles (e.g. *5, *xN) not detectable"|>,
    <|"Gene" -> "TPMT", "Diplotype" -> "*1/*3A", "Phenotype" -> "Intermediate Metabolizer",
      "ActionableDrug" -> "azathioprine", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> "1.0", "Confidence" -> "Called"|>,
    <|"Gene" -> "SLCO1B1", "Diplotype" -> "*1/*1", "Phenotype" -> "Normal Function",
      "ActionableDrug" -> "simvastatin", "CPICGuidance" -> "guidance", "CPICLevel" -> "A",
      "ActivityScore" -> "n/a", "Confidence" -> "Called"|>
}];

reportInterpFixtureClinVar = Tabular[{
    <|"VariantID" -> "chr6-26093141-C-G", "RsID" -> "rs1800562", "Gene" -> "HFE",
      "ClinicalSignificance" -> "Pathogenic", "ReviewStatus" -> "criteria_provided,_single_submitter",
      "Condition" -> "Hereditary_hemochromatosis", "VCVAccession" -> "VCV000009",
      "Genotype" -> "C/G", "Zygosity" -> "Heterozygous", "PopulationAF" -> 0.42,
      "FrequencySource" -> "gnomAD", "ImputationQuality" -> Missing["NotImputed"]|>,
    <|"VariantID" -> "chr2-200-C-T", "RsID" -> "rs202", "Gene" -> "GENE2",
      "ClinicalSignificance" -> "Likely_pathogenic", "ReviewStatus" -> "no_assertion_criteria_provided",
      "Condition" -> "Some_rare_disorder", "VCVAccession" -> "VCV000002",
      "Genotype" -> "T/T", "Zygosity" -> "Homozygous", "PopulationAF" -> 0.0005,
      "FrequencySource" -> "gnomAD", "ImputationQuality" -> 0.8|>
}];

reportInterpFixtureCarrier = Tabular[{
    <|"Gene" -> "CFTR", "VariantID" -> "chr7-117-C-T", "RsID" -> "rs123", "Zygosity" -> "Heterozygous",
      "Inheritance" -> "Autosomal recessive", "CarrierClassification" -> "Carrier",
      "ClinicalSignificance" -> "Pathogenic", "Condition" -> "Cystic_fibrosis",
      "ReviewStatus" -> "criteria_provided,_multiple_submitters", "PopulationAF" -> 0.008,
      "ImputationQuality" -> 0.95|>,
    <|"Gene" -> "LDLR", "VariantID" -> "chr19-11-G-A", "RsID" -> "rs456", "Zygosity" -> "Heterozygous",
      "Inheritance" -> "Autosomal dominant", "CarrierClassification" -> "Dominant finding",
      "ClinicalSignificance" -> "Pathogenic", "Condition" -> "Familial_hypercholesterolemia",
      "ReviewStatus" -> "criteria_provided,_single_submitter", "PopulationAF" -> 0.0004,
      "ImputationQuality" -> 0.9|>,
    <|"Gene" -> "MEFV", "VariantID" -> "chr16-3-G-A", "RsID" -> "rs789", "Zygosity" -> "Homozygous",
      "Inheritance" -> "Autosomal recessive", "CarrierClassification" -> "Homozygous (possible affected)",
      "ClinicalSignificance" -> "Pathogenic", "Condition" -> "Familial_Mediterranean_fever",
      "ReviewStatus" -> "criteria_provided,_single_submitter", "PopulationAF" -> 0.003,
      "ImputationQuality" -> 0.9|>
}];

reportInterpFixtureHG = HumanGenome[reportInterpFixtureG, <|
    "References" -> <|"Build" -> "GRCh37/hg19"|>,
    "Subject" -> <|"ID" -> "rint", "Sex" -> "XY"|>,
    "Ancestry" -> <|
        "Superpopulation" -> "EUR",
        "SuperpopulationFractions" -> <|"EUR" -> 0.86, "SAS" -> 0.07, "AMR" -> 0.04, "EAS" -> 0.02, "AFR" -> 0.01|>,
        "NearestPopulations" -> {"EUR", "SAS"},
        "Method" -> "PCA", "NMarkersUsed" -> 50000
    |>,
    "Haplogroups" -> <|"mtDNA" -> <|"Haplogroup" -> "H1a1"|>, "Y" -> <|"Haplogroup" -> "R1b1a2"|>|>,
    "Pharmacogenomics" -> reportInterpFixturePgx,
    "ClinVarHits" -> reportInterpFixtureClinVar,
    "PRS" -> Missing["NotComputed"],
    "Traits" -> Missing["NotComputed"],
    "AlphaMissenseScores" -> Missing["NotComputed"],
    "Carrier" -> reportInterpFixtureCarrier,
    "GWASAssociations" -> Missing["NotComputed"],
    "ReportCache" -> Missing["NotComputed"]
|>];

reportInterpFixtureEN = Import[GenomeReport[reportInterpFixtureHG, "Compute" -> "Cached"]["ReportFile"], "Text"];

(* Pharmacogenomics: a poor-metabolizer finding names the drug and points to a
   clinician / pharmacist, and the CYP2D6 copy-number-uncallable call is flagged
   as tentative, with the diplotype / CPIC / activity score demoted to a
   muted footnote (not prominent table columns). *)
VerificationTest[
    StringContainsQ[reportInterpFixtureEN, "<h3>CYP2C19 - clopidogrel</h3>"]
        && StringContainsQ[reportInterpFixtureEN, "process clopidogrel differently"]
        && StringContainsQ[reportInterpFixtureEN, "discuss dosing with a clinician or pharmacist"]
        && StringContainsQ[reportInterpFixtureEN, "treat the call as tentative"]
        && StringContainsQ[reportInterpFixtureEN, "class=\"finding-meta\">Diplotype *2/*2; CPIC level A"]
        && ! StringContainsQ[reportInterpFixtureEN, "<th>ActivityScore</th>"],
    True,
    TestID -> "GenomeReport English Pharmacogenomics interprets each finding and demotes the diplotype/CPIC/activity to a footnote"
]

(* ClinVar: the frequency reality - a common high-AF variant with a pathogenic
   label is flagged as a likely false alarm, a rare variant is called rare, and
   both close with the not-a-diagnosis caveat. *)
VerificationTest[
    StringContainsQ[reportInterpFixtureEN, "which ClinVar links to Hereditary_hemochromatosis"]
        && StringContainsQ[reportInterpFixtureEN, "common in the general population (about 42% of people carry it)"]
        && StringContainsQ[reportInterpFixtureEN, "known source of false alarms"]
        && StringContainsQ[reportInterpFixtureEN, "This is a rare variant."]
        && StringContainsQ[reportInterpFixtureEN, "A ClinVar label is not a diagnosis"]
        && StringContainsQ[reportInterpFixtureEN, "class=\"finding-meta\">Pathogenic; criteria_provided,_single_submitter; VCV000009; rs1800562</p>"],
    True,
    TestID -> "GenomeReport English ClinVar gives the frequency reality and demotes the accession/rsID to a footnote"
]

(* Carrier: the healthy-carrier / reproductive framing for a carrier, and the
   distinct stronger notes for a dominant finding and a homozygous finding. *)
VerificationTest[
    StringContainsQ[reportInterpFixtureEN, "one copy of a variant linked to Cystic_fibrosis (CFTR)"]
        && StringContainsQ[reportInterpFixtureEN, "As a healthy carrier you are not affected"]
        && StringContainsQ[reportInterpFixtureEN, "relevant if a reproductive partner also carries a variant in the same gene"]
        && StringContainsQ[reportInterpFixtureEN, "gene that acts dominantly"]
        && StringContainsQ[reportInterpFixtureEN, "this warrants clinical review"],
    True,
    TestID -> "GenomeReport English Carrier gives the healthy-carrier / reproductive framing with dominant and homozygous notes"
]

(* Ancestry: the continental best-match caveat, the coarse-fractions statistical
   -noise note, the maternal / paternal single-lineage haplogroup caveat, and the
   sex-karyotype one-liner in the Overview. *)
VerificationTest[
    StringContainsQ[reportInterpFixtureEN, "most closely matches the EUR continental reference group"]
        && StringContainsQ[reportInterpFixtureEN, "not a country or ethnicity"]
        && StringContainsQ[reportInterpFixtureEN, "Small non-dominant fractions are usually statistical noise"]
        && StringContainsQ[reportInterpFixtureEN, "haplogroup H1a1 traces your direct maternal line"]
        && StringContainsQ[reportInterpFixtureEN, "Y haplogroup R1b1a2 traces your direct paternal line"]
        && StringContainsQ[reportInterpFixtureEN, "reflects chromosomal sex, not gender identity"],
    True,
    TestID -> "GenomeReport English Ancestry explains the numbers with continental, noise, haplogroup, and sex caveats"
]

reportInterpFixtureRU = Import[
    GenomeReport[reportInterpFixtureHG, "Compute" -> "Cached", "Language" -> "Russian"]["ReportFile"], "Text"];

(* The Russian render carries the Russian equivalents of every per-finding
   interpretation, while scientific identifiers (drug names, gene symbols,
   diplotypes, haplogroup labels, accessions) stay untranslated. *)
VerificationTest[
    StringContainsQ[reportInterpFixtureRU, "process clopidogrel differently" | "перерабатывать препарат clopidogrel"]
        && StringContainsQ[reportInterpFixtureRU, "считайте результат предварительным"]
        && StringContainsQ[reportInterpFixtureRU, "часто встречается в общей популяции"]
        && StringContainsQ[reportInterpFixtureRU, "не диагноз"]
        && StringContainsQ[reportInterpFixtureRU, "Будучи здоровым носителем"]
        && StringContainsQ[reportInterpFixtureRU, "прямую материнскую линию"]
        && StringContainsQ[reportInterpFixtureRU, "хромосомный пол"]
        && StringContainsQ[reportInterpFixtureRU, "VCV000009"] && StringContainsQ[reportInterpFixtureRU, "H1a1"],
    True,
    TestID -> "GenomeReport Russian carries the Russian per-finding interpretations and keeps scientific identifiers"
]

(* The interpretation helpers cover the phenotype branches that never surface as
   an actionable block (a Normal metabolizer is filtered out) and the LowerIsRisk
   -style framing edge cases, pinned directly. *)
VerificationTest[
    {WolframInstitute`Genome`Private`pgxInterpretation["Normal Metabolizer", "warfarin", "Called", "English"],
     WolframInstitute`Genome`Private`pgxInterpretation["Ultrarapid Metabolizer", "codeine", "Called", "English"]},
    {"Standard response expected; usual dosing of warfarin is typically appropriate.",
     "You may process codeine faster than usual, which can reduce effectiveness (or, for a prodrug, raise active drug levels) - discuss with a clinician."},
    TestID -> "pgxInterpretation maps the Normal and Rapid phenotype branches"
]

(* === ClinVarHits genotype-aware join (fixture, no download) ===
   Build tiny ClinVar-like P/LP and subject VCFs (BGZF + tbi) with matching
   pathogenic sites and drive the internal computeClinVarHits so the
   genotype-aware join is pinned without the ~150 MB reference download.
   Guarded on bgzip / tabix / bcftools like the Tabix fixture above. *)

clinVarFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_clinvar_fixture"}];
Quiet @ If[ DirectoryQ[clinVarFixtureDir], DeleteDirectory[clinVarFixtureDir, DeleteContents -> True]];
CreateDirectory[clinVarFixtureDir];

If[ tabixToolsAvailable,
    clinVarFixtureClinvar = FileNameJoin[{clinVarFixtureDir, "clinvar_plp.vcf"}];
    clinVarFixtureSubject = FileNameJoin[{clinVarFixtureDir, "subject.vcf"}];
    Export[clinVarFixtureClinvar, "##fileformat=VCFv4.2\n##fileDate=2026-06-27\n##source=ClinVar\n##contig=<ID=chr1>\n##INFO=<ID=CLNSIG,Number=.,Type=String,Description=\"sig\">\n##INFO=<ID=CLNREVSTAT,Number=.,Type=String,Description=\"rev\">\n##INFO=<ID=CLNDN,Number=.,Type=String,Description=\"dn\">\n##INFO=<ID=GENEINFO,Number=1,Type=String,Description=\"gene\">\n##INFO=<ID=RS,Number=.,Type=String,Description=\"rs\">\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\nchr1\t100\t12345\tA\tG\t.\t.\tCLNSIG=Pathogenic;CLNREVSTAT=criteria_provided,_single_submitter;CLNDN=Disease_one;GENEINFO=GENE1:111;RS=101\nchr1\t200\t222\tC\tT\t.\t.\tCLNSIG=Likely_pathogenic;CLNREVSTAT=criteria_provided,_multiple_submitters;CLNDN=Disease_two;GENEINFO=GENE2:222;RS=202\nchr1\t300\t333\tG\tA\t.\t.\tCLNSIG=Pathogenic;CLNREVSTAT=no_assertion;CLNDN=Disease_three;GENEINFO=GENE3:333\nchr1\t400\t444\tT\tC\t.\t.\tCLNSIG=Pathogenic;CLNREVSTAT=criteria_provided;CLNDN=Disease_four;GENEINFO=GENE4:444\n", "Text"];
    (* The subject rows carry imputation INFO so ImputationQuality is exercised:
       the carried het GENE1 site is IMPUTED with R2=0.83, the carried hom GENE2
       site is TYPED (directly sequenced). *)
    Export[clinVarFixtureSubject, "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tsub1\nchr1\t100\trs101\tA\tG\t60\tPASS\tIMPUTED;R2=0.83\tGT\t0/1\nchr1\t150\trs150\tA\tT\t60\tPASS\t.\tGT\t0/1\nchr1\t200\t.\tC\tT\t60\tPASS\tTYPED\tGT\t1/1\nchr1\t300\trs333\tG\tA\t60\tPASS\t.\tGT\t0/0\n", "Text"];
    RunProcess[{"sh", "-c", "bgzip -f " <> clinVarFixtureClinvar <> " && tabix -p vcf -f " <> clinVarFixtureClinvar <> ".gz"}];
    RunProcess[{"sh", "-c", "bgzip -f " <> clinVarFixtureSubject <> " && tabix -p vcf -f " <> clinVarFixtureSubject <> ".gz"}];
    (* Mock the frequency source (no network): GENE1 common (0.42), GENE2 absent
       from the map -> Missing[NotFound] (treated as rare / unknown, kept). *)
    clinVarFixtureAF = <|"chr1-100-A-G" -> 0.42|>;
    clinVarFixtureHits = WolframInstitute`Genome`Private`computeClinVarHits[
        clinVarFixtureSubject <> ".gz",
        clinVarFixtureClinvar <> ".gz",
        {"sub1"},
        clinVarFixtureAF
    ];
    clinVarFixtureByGene = Association @ Map[#["Gene"] -> # &, Normal[clinVarFixtureHits]];
    VerificationTest[
        {Head[clinVarFixtureHits], Normal[ColumnKeys[clinVarFixtureHits]]},
        {Tabular, {"VariantID", "RsID", "Gene", "ClinicalSignificance", "ReviewStatus",
            "Condition", "VCVAccession", "Genotype", "Zygosity",
            "PopulationAF", "FrequencySource", "ImputationQuality"}},
        TestID -> "computeClinVarHits returns the 12-column ClinVarHits Tabular"
    ];
    VerificationTest[
        Length[clinVarFixtureHits],
        2,
        TestID -> "computeClinVarHits keeps only the two carried P/LP sites"
    ];
    VerificationTest[
        Sort[Keys[clinVarFixtureByGene]],
        {"GENE1", "GENE2"},
        TestID -> "computeClinVarHits drops the 0/0 site and the subject-absent P/LP site"
    ];
    VerificationTest[
        {clinVarFixtureByGene["GENE1"]["Zygosity"],
         clinVarFixtureByGene["GENE1"]["ClinicalSignificance"],
         clinVarFixtureByGene["GENE1"]["VariantID"],
         clinVarFixtureByGene["GENE1"]["RsID"]},
        {"Heterozygous", "Pathogenic", "chr1-100-A-G", "rs101"},
        TestID -> "computeClinVarHits reports the carried heterozygous Pathogenic site"
    ];
    VerificationTest[
        {clinVarFixtureByGene["GENE2"]["Zygosity"],
         clinVarFixtureByGene["GENE2"]["ClinicalSignificance"],
         clinVarFixtureByGene["GENE2"]["VCVAccession"]},
        {"Homozygous", "Likely pathogenic", "VCV000000222"},
        TestID -> "computeClinVarHits reports the carried homozygous Likely-pathogenic site"
    ];
    VerificationTest[
        {clinVarFixtureByGene["GENE1"]["PopulationAF"],
         clinVarFixtureByGene["GENE1"]["FrequencySource"],
         clinVarFixtureByGene["GENE1"]["ImputationQuality"]},
        {0.42, "gnomAD_r2_1", "Imputed R2=0.83"},
        TestID -> "computeClinVarHits attaches the mocked PopulationAF, source, and imputed R2"
    ];
    VerificationTest[
        {MissingQ[clinVarFixtureByGene["GENE2"]["PopulationAF"]],
         clinVarFixtureByGene["GENE2"]["ImputationQuality"]},
        {True, "Directly sequenced"},
        TestID -> "computeClinVarHits reports Missing AF for an unmapped variant and TYPED as directly sequenced"
    ];
    VerificationTest[
        Sort @ Normal[
            WolframInstitute`Genome`Private`clinVarApplyMaxAF[clinVarFixtureHits, 0.01][[All, "Gene"]]
        ],
        {"GENE2"},
        TestID -> "clinVarApplyMaxAF drops the common variant and keeps the Missing-AF one"
    ];
    VerificationTest[
        Length[WolframInstitute`Genome`Private`clinVarApplyMaxAF[clinVarFixtureHits, Automatic]],
        2,
        TestID -> "clinVarApplyMaxAF with Automatic keeps every hit"
    ]
]

(* === AlphaMissenseScores missense join (fixture, no download) ===
   Drive the internal computeAlphaMissenseScores with a tiny gzipped
   AlphaMissense-hg19-style TSV (columns #CHROM POS REF ALT genome uniprot_id
   transcript_id protein_variant am_pathogenicity am_class) and a small subject
   VCF, pinning the carried-missense-SNV join without the ~600 MB download.
   Needs only gzip + awk (POSIX), so it runs on every checkout. *)

amFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_am_fixture"}];
Quiet @ If[ DirectoryQ[amFixtureDir], DeleteDirectory[amFixtureDir, DeleteContents -> True]];
CreateDirectory[amFixtureDir];
amFixtureTSV = FileNameJoin[{amFixtureDir, "am_hg19.tsv"}];
amFixtureSubject = FileNameJoin[{amFixtureDir, "subject.vcf"}];
(* AlphaMissense table: four scored missense SNVs.  chr1:100 A>G (0.98 path),
   chr1:200 C>T (0.10 benign), chr1:300 G>A (0.55 ambiguous), chr1:900 T>C
   (0.99 path, a site the subject does not carry). *)
Export[amFixtureTSV,
    "#CHROM\tPOS\tREF\tALT\tgenome\tuniprot_id\ttranscript_id\tprotein_variant\tam_pathogenicity\tam_class\n" <>
    "chr1\t100\tA\tG\thg19\tP11111\tENST00000000001\tA123T\t0.98\tpathogenic\n" <>
    "chr1\t200\tC\tT\thg19\tP22222\tENST00000000002\tL215W\t0.10\tbenign\n" <>
    "chr1\t300\tG\tA\thg19\tP33333\tENST00000000003\tR90H\t0.55\tambiguous\n" <>
    "chr1\t900\tT\tC\thg19\tP99999\tENST00000000009\tC988F\t0.99\tpathogenic\n",
    "Text"
];
RunProcess[{"sh", "-c", "gzip -f " <> amFixtureSubject <> "; gzip -f " <> amFixtureTSV}];
(* Subject: carries chr1:100 het (in AM, pathogenic), chr1:200 hom (in AM,
   benign), chr1:300 0/0 (must be dropped - not carried), chr1:400 an indel
   (not a scorable SNV), and does not have chr1:900 at all. *)
Export[amFixtureSubject,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tsub1\n" <>
    "chr1\t100\trs100\tA\tG\t60\tPASS\t.\tGT\t0/1\n" <>
    "chr1\t200\t.\tC\tT\t60\tPASS\t.\tGT\t1/1\n" <>
    "chr1\t300\trs300\tG\tA\t60\tPASS\t.\tGT\t0/0\n" <>
    "chr1\t400\trs400\tTG\tT\t60\tPASS\t.\tGT\t0/1\n",
    "Text"
];
RunProcess[{"sh", "-c", "gzip -f " <> amFixtureSubject}];
amFixtureScores = WolframInstitute`Genome`Private`computeAlphaMissenseScores[
    amFixtureSubject <> ".gz",
    amFixtureTSV <> ".gz",
    0
];
amFixtureByTx = Association @ Map[#["Transcript"] -> # &, Normal[amFixtureScores]];

VerificationTest[
    {Head[amFixtureScores], Normal[ColumnKeys[amFixtureScores]]},
    {Tabular, {"VariantID", "RsID", "Gene", "Transcript", "ProteinChange",
        "Genotype", "Zygosity", "AMScore", "AMClass"}},
    TestID -> "computeAlphaMissenseScores returns the 9-column AlphaMissense Tabular"
]

VerificationTest[
    Length[amFixtureScores],
    2,
    TestID -> "computeAlphaMissenseScores keeps only the two carried missense SNVs"
]

VerificationTest[
    Sort[Keys[amFixtureByTx]],
    {"ENST00000000001", "ENST00000000002"},
    TestID -> "computeAlphaMissenseScores drops the 0/0 site, the indel, and the uncarried AM site"
]

VerificationTest[
    Normal[amFixtureScores][[1]]["AMScore"] >= Normal[amFixtureScores][[-1]]["AMScore"],
    True,
    TestID -> "computeAlphaMissenseScores sorts by AMScore descending"
]

VerificationTest[
    {amFixtureByTx["ENST00000000001"]["Zygosity"],
     amFixtureByTx["ENST00000000001"]["AMClass"],
     amFixtureByTx["ENST00000000001"]["ProteinChange"],
     amFixtureByTx["ENST00000000001"]["VariantID"],
     amFixtureByTx["ENST00000000001"]["RsID"]},
    {"Heterozygous", "likely_pathogenic", "A123T", "chr1-100-A-G", "rs100"},
    TestID -> "computeAlphaMissenseScores reports the carried heterozygous pathogenic missense"
]

VerificationTest[
    {amFixtureByTx["ENST00000000002"]["Zygosity"],
     amFixtureByTx["ENST00000000002"]["AMClass"],
     amFixtureByTx["ENST00000000002"]["RsID"]},
    {"Homozygous", "likely_benign", Missing[]},
    TestID -> "computeAlphaMissenseScores normalises the benign class and handles a no-rsID hom site"
]

VerificationTest[
    Length[WolframInstitute`Genome`Private`computeAlphaMissenseScores[
        amFixtureSubject <> ".gz", amFixtureTSV <> ".gz", 0.5]],
    1,
    TestID -> "computeAlphaMissenseScores MinScore threshold keeps only high-score rows"
]

(* === TraitAssociations (SNPedia) genotype matching + magnitude
   sort (fixture, no network) ===
   Drive the pure internal TraitAssociations logic with tiny in-memory stand-ins for the
   SNPedia data (an rsnum map and a genotype-page map) plus inline {{Rsnum}} /
   {{Genotype}} wikitext, so the genotype matching, strand reconciliation,
   REF/REF inclusion, magnitude-descending sort, and wikitext parsing are all
   pinned without ever hitting the live MediaWiki API. *)

(* Synthetic fixture genotypes on the reference-forward strand.  These are
   invented calls for a made-up sample, not anyone's genotypes: a plus-
   orientation homozygous-reference 0/0 call, a minus-orientation heterozygous
   G/A call whose SNPedia genotype is the reverse-complement (C;T), and an
   undocumented-genotype rsID that must be dropped. *)
traitsFixtureSubject = {
    <|"RsID" -> "rs9999998", "GT" -> "0/0", "Alleles" -> {"A", "A"}|>,
    <|"RsID" -> "rs1801133", "GT" -> "0/1", "Alleles" -> {"G", "A"}|>,
    <|"RsID" -> "rs9999999", "GT" -> "1/1", "Alleles" -> {"A", "A"}|>
};
traitsFixtureRsnum = <|
    "rs9999998" -> <|"Orientation" -> "plus",
        "Genos" -> {"(A;A)", "(A;G)", "(G;G)"}, "Category" -> "fixture category"|>,
    "rs1801133" -> <|"Orientation" -> "minus",
        "Genos" -> {"(C;C)", "(C;T)", "(T;T)"}, "Category" -> "Folic acid processing"|>,
    "rs9999999" -> <|"Orientation" -> "plus", "Genos" -> {"(A;A)"}, "Category" -> Missing[]|>
|>;
traitsFixtureGeno = <|
    "Rs9999998(A;A)" -> <|"Magnitude" -> 2.2, "Repute" -> "Good",
        "Summary" -> "Fixture summary for the homozygous-reference genotype."|>,
    "Rs1801133(C;T)" -> <|"Magnitude" -> 2.5, "Repute" -> "Bad",
        "Summary" -> "1 copy of the C677T allele; reduced MTHFR activity."|>
|>;
traitsFixtureTabular = WolframInstitute`Genome`Private`buildTraitsRows[
    traitsFixtureSubject, traitsFixtureRsnum, traitsFixtureGeno
];
traitsFixtureByRs = Association @ Map[#["RsID"] -> # &, Normal[traitsFixtureTabular]];

VerificationTest[
    {Head[traitsFixtureTabular], Normal[ColumnKeys[traitsFixtureTabular]]},
    {Tabular, {"RsID", "Genotype", "Magnitude", "Repute", "Summary", "URL", "Category"}},
    TestID -> "buildTraitsRows returns the 7-column Traits Tabular"
]

VerificationTest[
    Sort[Keys[traitsFixtureByRs]],
    {"rs1801133", "rs9999998"},
    TestID -> "buildTraitsRows drops the rsID whose fixture genotype SNPedia does not document"
]

VerificationTest[
    Lookup[Normal[traitsFixtureTabular], "Magnitude"],
    {2.5, 2.2},
    TestID -> "buildTraitsRows sorts rows by Magnitude descending"
]

VerificationTest[
    {traitsFixtureByRs["rs9999998"]["Genotype"],
     traitsFixtureByRs["rs9999998"]["Repute"],
     traitsFixtureByRs["rs9999998"]["Category"]},
    {"(A;A)", "Good", "fixture category"},
    TestID -> "buildTraitsRows includes the 0/0 homozygous-reference (A;A) genotype with its interpretation"
]

VerificationTest[
    {traitsFixtureByRs["rs1801133"]["Genotype"],
     traitsFixtureByRs["rs1801133"]["Repute"],
     traitsFixtureByRs["rs1801133"]["URL"]},
    {"(C;T)", "Bad", "https://www.snpedia.com/index.php/Rs1801133(C;T)"},
    TestID -> "buildTraitsRows reconciles the minus-strand G/A call to the reverse-complement (C;T)"
]

(* Orientation-guided candidate ordering: minus prefers the reverse-complement
   first, plus prefers the as-is genotype first. *)
VerificationTest[
    {WolframInstitute`Genome`Private`candidateGenoStrings[{"G", "A"}, "minus"],
     WolframInstitute`Genome`Private`candidateGenoStrings[{"A", "A"}, "plus"]},
    {{"(C;T)", "(T;C)", "(G;A)", "(A;G)"}, {"(A;A)", "(T;T)"}},
    TestID -> "candidateGenoStrings orders by orientation (minus -> revcomp first)"
]

(* traitSubjectGenotype parses the awk-emitted rsid/ref/alt/gt line, keeps 0/0 as
   the REF/REF genotype, and rejects a no-call.  The lines below are synthetic. *)
VerificationTest[
    {WolframInstitute`Genome`Private`traitSubjectGenotype["rs1801133\tG\tA\t0/1"]["Alleles"],
     WolframInstitute`Genome`Private`traitSubjectGenotype["rs9999998\tA\tG\t0/0"]["Alleles"],
     MissingQ[WolframInstitute`Genome`Private`traitSubjectGenotype["rs1\tA\tG\t./."]]},
    {{"G", "A"}, {"A", "A"}, True},
    TestID -> "traitSubjectGenotype extracts forward alleles, keeps 0/0, drops no-calls"
]

(* Wikitext parsing of the {{Rsnum}} and {{Genotype}} templates. *)
VerificationTest[
    WolframInstitute`Genome`Private`parseRsnum[
        "{{Rsnum\n|rsid=1801133\n|Gene=MTHFR\n|Orientation=minus\n"
            <> "|StabilizedOrientation=minus\n|Summary=Folic acid processing\n"
            <> "|geno1=(C;C)\n|geno2=(C;T)\n|geno3=(T;T)\n}}\nfree text"
    ],
    <|"Orientation" -> "minus", "StabilizedOrientation" -> "minus",
        "Genos" -> {"(C;C)", "(C;T)", "(T;T)"}, "Category" -> "Folic acid processing"|>,
    TestID -> "parseRsnum extracts Orientation, geno list, and Summary from {{Rsnum}} wikitext"
]

VerificationTest[
    WolframInstitute`Genome`Private`parseGenotype[
        "{{Genotype\n|rsid=9999998\n|allele1=A\n|allele2=A\n|magnitude=2.2\n"
            <> "|repute=Good\n|summary=Fixture summary line.\n}}\nmore prose"
    ],
    <|"Magnitude" -> 2.2, "Repute" -> "Good", "Summary" -> "Fixture summary line."|>,
    TestID -> "parseGenotype extracts magnitude, repute, and summary from {{Genotype}} wikitext"
]

(* Absent magnitude defaults to 0; absent repute normalises to None. *)
VerificationTest[
    WolframInstitute`Genome`Private`parseGenotype[
        "{{Genotype\n|rsid=1\n|allele1=A\n|allele2=A\n|summary=No magnitude here.\n}}"
    ],
    <|"Magnitude" -> 0, "Repute" -> "None", "Summary" -> "No magnitude here."|>,
    TestID -> "parseGenotype defaults an absent magnitude to 0 and an absent repute to None"
]

(* === CarrierStatus classification (fixture, no network) ===
   Drive the pure internal buildCarrierRows with a small hand-built set of
   ClinVar-hit rows plus a small gene -> normalised-MOI map, pinning the
   heterozygous-recessive -> Carrier, homozygous-recessive -> possible-affected,
   BOTH-recessive het -> Carrier, dominant -> secondary-finding, and
   absent-gene -> Unclassified classifications, the carriers-first sort, and the
   IncludeDominant filter, all without ever hitting the PanelApp API. *)

(* Each hit carries a PopulationAF and ImputationQuality (as it would arrive from
   ClinVarHits): GENEAR is a common polymorphism (AF 0.30) that a carrier-screening
   frequency filter must drop, GENEUNK has a Missing AF (kept as rare / unknown),
   and the rest are genuinely rare. *)
carrierFixtureHits = {
    <|"Gene" -> "GENEARHOM", "VariantID" -> "chr1-200-C-T", "RsID" -> "rs202",
        "Zygosity" -> "Homozygous", "ClinicalSignificance" -> "Likely pathogenic",
        "Condition" -> "AR disease (hom)", "ReviewStatus" -> "criteria provided",
        "PopulationAF" -> 0.0005, "ImputationQuality" -> "Directly sequenced"|>,
    <|"Gene" -> "GENEAR", "VariantID" -> "chr1-100-A-G", "RsID" -> "rs101",
        "Zygosity" -> "Heterozygous", "ClinicalSignificance" -> "Pathogenic",
        "Condition" -> "AR disease", "ReviewStatus" -> "criteria provided",
        "PopulationAF" -> 0.30, "ImputationQuality" -> "Imputed R2=0.88"|>,
    <|"Gene" -> "GENEBOTH", "VariantID" -> "chr1-150-A-T", "RsID" -> "rs150",
        "Zygosity" -> "Heterozygous", "ClinicalSignificance" -> "Pathogenic",
        "Condition" -> "mono/biallelic disease", "ReviewStatus" -> "criteria provided",
        "PopulationAF" -> 0.002, "ImputationQuality" -> "Directly sequenced"|>,
    <|"Gene" -> "GENEAD", "VariantID" -> "chr1-300-G-A", "RsID" -> "rs303",
        "Zygosity" -> "Heterozygous", "ClinicalSignificance" -> "Pathogenic",
        "Condition" -> "AD disease", "ReviewStatus" -> "criteria provided",
        "PopulationAF" -> 0.001, "ImputationQuality" -> "Directly sequenced"|>,
    <|"Gene" -> "GENEUNK", "VariantID" -> "chr1-400-T-C", "RsID" -> "rs404",
        "Zygosity" -> "Heterozygous", "ClinicalSignificance" -> "Pathogenic",
        "Condition" -> "unmapped disease", "ReviewStatus" -> "criteria provided",
        "PopulationAF" -> Missing["NotFound"], "ImputationQuality" -> "Directly sequenced"|>
};
carrierFixtureMOI = <|
    "GENEAR" -> "Autosomal recessive",
    "GENEARHOM" -> "Autosomal recessive",
    "GENEBOTH" -> "Autosomal recessive/dominant",
    "GENEAD" -> "Autosomal dominant"
|>;
carrierFixtureTab = WolframInstitute`Genome`Private`buildCarrierRows[carrierFixtureHits, carrierFixtureMOI];
carrierFixtureByGene = Association @ Map[#["Gene"] -> # &, Normal[carrierFixtureTab]];

VerificationTest[
    {Head[carrierFixtureTab], Normal[ColumnKeys[carrierFixtureTab]]},
    {Tabular, {"Gene", "VariantID", "RsID", "Zygosity", "Inheritance",
        "CarrierClassification", "ClinicalSignificance", "Condition", "ReviewStatus",
        "PopulationAF", "ImputationQuality"}},
    TestID -> "buildCarrierRows returns the 11-column CarrierStatus Tabular"
]

VerificationTest[
    {carrierFixtureByGene["GENEAR"]["CarrierClassification"],
     carrierFixtureByGene["GENEAR"]["Inheritance"]},
    {"Carrier", "Autosomal recessive"},
    TestID -> "buildCarrierRows classifies a het variant in an AR gene as Carrier"
]

VerificationTest[
    carrierFixtureByGene["GENEARHOM"]["CarrierClassification"],
    "Homozygous (possible affected)",
    TestID -> "buildCarrierRows classifies a hom variant in an AR gene as possible-affected"
]

VerificationTest[
    carrierFixtureByGene["GENEBOTH"]["CarrierClassification"],
    "Carrier",
    TestID -> "buildCarrierRows classifies a het variant in a mono/biallelic gene as Carrier"
]

VerificationTest[
    carrierFixtureByGene["GENEAD"]["CarrierClassification"],
    "Dominant finding",
    TestID -> "buildCarrierRows classifies a het variant in an AD gene as a Dominant finding"
]

VerificationTest[
    carrierFixtureByGene["GENEUNK"]["CarrierClassification"],
    "Unclassified",
    TestID -> "buildCarrierRows classifies a variant in an unmapped gene as Unclassified"
]

VerificationTest[
    Lookup[Normal[carrierFixtureTab], "CarrierClassification"],
    {"Homozygous (possible affected)", "Carrier", "Carrier", "Dominant finding", "Unclassified"},
    TestID -> "buildCarrierRows sorts possible-affected and carriers ahead of the rest"
]

VerificationTest[
    Block[{restricted = WolframInstitute`Genome`Private`carrierApplyIncludeDominant[carrierFixtureTab, False]},
        {Length[restricted], FreeQ[Lookup[Normal[restricted], "CarrierClassification"], "Dominant finding"]}
    ],
    {4, True},
    TestID -> "carrierApplyIncludeDominant drops the Dominant finding rows"
]

VerificationTest[
    {carrierFixtureByGene["GENEAR"]["PopulationAF"],
     carrierFixtureByGene["GENEAR"]["ImputationQuality"],
     carrierFixtureByGene["GENEARHOM"]["ImputationQuality"]},
    {0.30, "Imputed R2=0.88", "Directly sequenced"},
    TestID -> "buildCarrierRows carries PopulationAF and ImputationQuality from the hits"
]

VerificationTest[
    Block[{rare = WolframInstitute`Genome`Private`carrierApplyMaxAF[carrierFixtureTab, 0.01]},
        {Length[rare], FreeQ[Lookup[Normal[rare], "Gene"], "GENEAR"],
         MemberQ[Lookup[Normal[rare], "Gene"], "GENEARHOM"],
         MemberQ[Lookup[Normal[rare], "Gene"], "GENEUNK"]}
    ],
    {4, True, True, True},
    TestID -> "carrierApplyMaxAF drops the common carrier and keeps the rare and Missing-AF ones"
]

VerificationTest[
    Length[WolframInstitute`Genome`Private`carrierApplyMaxAF[carrierFixtureTab, Automatic]],
    5,
    TestID -> "carrierApplyMaxAF with Automatic keeps every carrier row"
]

VerificationTest[
    {WolframInstitute`Genome`Private`carrierNormalizeMOI["BIALLELIC, autosomal or pseudoautosomal"],
     WolframInstitute`Genome`Private`carrierNormalizeMOI["MONOALLELIC, autosomal or pseudoautosomal, NOT imprinted"],
     WolframInstitute`Genome`Private`carrierNormalizeMOI[
        "X-LINKED: hemizygous mutation in males, biallelic mutations in females"],
     WolframInstitute`Genome`Private`carrierNormalizeMOI[
        "BOTH monoallelic and biallelic, autosomal or pseudoautosomal"],
     WolframInstitute`Genome`Private`carrierNormalizeMOI["MITOCHONDRIAL"],
     WolframInstitute`Genome`Private`carrierNormalizeMOI["Unknown"]},
    {"Autosomal recessive", "Autosomal dominant", "X-linked",
     "Autosomal recessive/dominant", "Mitochondrial", "Unknown"},
    TestID -> "carrierNormalizeMOI folds the PanelApp MOI vocabulary to the classifier terms"
]

VerificationTest[
    WolframInstitute`Genome`Private`carrierAggregateMOI[{
        <|"mode_of_inheritance" -> "BIALLELIC, autosomal or pseudoautosomal"|>,
        <|"mode_of_inheritance" -> "BIALLELIC, autosomal or pseudoautosomal"|>,
        <|"mode_of_inheritance" -> "Unknown"|>,
        <|"mode_of_inheritance" -> ""|>
    }],
    "BIALLELIC, autosomal or pseudoautosomal",
    TestID -> "carrierAggregateMOI takes the majority informative MOI across panels"
]

(* === PolygenicRiskScore scoring core (fixture, no download) ===
   Drive the pure PRS scoring internals and the file-level
   computePolygenicRiskScore with a tiny hand-made subject VCF and a tiny
   harmonized-format scoring file (a handful of variants with known effect
   alleles, weights, and frequencies) in $TemporaryDirectory, pinning the
   dosage / strand / palindrome / homozygous-reference / percentile logic
   without any download.  Needs only gzcat / awk (POSIX), so it runs on every
   checkout. *)

(* Subject rows on the reference-forward strand: a het A/G, a hom-alt C/T, a
   het A/G (revcomp target), a het A/T (palindrome target), and a homozygous-
   reference T/T call (ALT = "."). *)
prsFixtureSubjectByPos = <|
    "chr1-100" -> <|"REF" -> "A", "ALT" -> {"G"}, "GTParts" -> {"0", "1"}, "AF" -> 0.3, "PanelQ" -> True|>,
    "chr1-200" -> <|"REF" -> "C", "ALT" -> {"T"}, "GTParts" -> {"1", "1"}, "AF" -> 0.1, "PanelQ" -> True|>,
    "chr1-300" -> <|"REF" -> "A", "ALT" -> {"G"}, "GTParts" -> {"0", "1"}, "AF" -> 0.25, "PanelQ" -> True|>,
    "chr1-400" -> <|"REF" -> "A", "ALT" -> {"T"}, "GTParts" -> {"0", "1"}, "AF" -> 0.4, "PanelQ" -> True|>,
    "chr1-500" -> <|"REF" -> "T", "ALT" -> {}, "GTParts" -> {"0", "0"}, "AF" -> Missing[], "PanelQ" -> False|>
|>;
prsMkVar[chr_, pos_, ea_, oa_, w_, af_] :=
    <|"Chr" -> chr, "Pos" -> pos, "EA" -> ea, "OA" -> oa, "W" -> w, "EAF" -> af, "RsID" -> Missing[]|>;

VerificationTest[
    {WolframInstitute`Genome`Private`resolvePGSID["PGS000065"],
     WolframInstitute`Genome`Private`resolvePGSID["LDL cholesterol"],
     WolframInstitute`Genome`Private`resolvePGSID["EFO_0004340"],
     WolframInstitute`Genome`Private`resolvePGSID["not a real trait"]},
    {"PGS000065", "PGS000065", "PGS000034", Missing["UnknownTrait"]},
    TestID -> "resolvePGSID maps a PGS ID, a trait name, and an EFO id, and rejects the unknown"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 100, "G", "A", 0.5, 0.3], prsFixtureSubjectByPos],
    <|"Dosage" -> 1, "W" -> 0.5, "EAF" -> 0.3, "FreqSource" -> "PGSAlleleFrequency"|>,
    TestID -> "prsScoreVariant: direct het match, effect allele = ALT, dosage 1"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 200, "T", "C", -0.2, 0.1], prsFixtureSubjectByPos]["Dosage"],
    2,
    TestID -> "prsScoreVariant: homozygous-alt effect allele, dosage 2"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 300, "C", "T", 0.8, 0.25], prsFixtureSubjectByPos]["Dosage"],
    1,
    TestID -> "prsScoreVariant: reverse-complement effect allele matched, dosage 1"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 400, "A", "T", 0.4, 0.4], prsFixtureSubjectByPos],
    Missing[],
    TestID -> "prsScoreVariant: an A/T palindrome is skipped (strand-ambiguous)"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 900, "G", "A", 0.9, 0.5], prsFixtureSubjectByPos],
    Missing[],
    TestID -> "prsScoreVariant: a subject-absent scoring variant is skipped"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 100, "AT", "A", 0.9, 0.5], prsFixtureSubjectByPos],
    Missing[],
    TestID -> "prsScoreVariant: an indel scoring variant is skipped"
]

(* Homozygous-reference row (ALT = ".", REF = T): effect allele C is the
   non-reference allele so dosage 0; effect allele T (the REF) gives dosage 2. *)
VerificationTest[
    {WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 500, "C", "T", 0.7, Missing[]], prsFixtureSubjectByPos]["Dosage"],
     WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 500, "T", "C", 0.7, Missing[]], prsFixtureSubjectByPos]["Dosage"]},
    {0, 2},
    TestID -> "prsScoreVariant: a homozygous-reference row scores dosage 0 (effect=other) or 2 (effect=REF)"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsScoreVariant[
        prsMkVar["chr1", 100, "G", "A", 0.5, Missing[]], prsFixtureSubjectByPos]["FreqSource"],
    "SubjectPanelAF",
    TestID -> "prsScoreVariant: falls back to the subject panel AF when the scoring file has no frequency"
]

VerificationTest[
    WolframInstitute`Genome`Private`prsNormalPercentile[0.9, 0.66, 0.3522],
    CDF[NormalDistribution[0.66, Sqrt[0.3522]], 0.9],
    TestID -> "prsNormalPercentile equals the normal CDF at the subject score"
]

prsFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_prs_fixture"}];
Quiet @ If[ DirectoryQ[prsFixtureDir], DeleteDirectory[prsFixtureDir, DeleteContents -> True]];
CreateDirectory[prsFixtureDir];
prsFixtureSubjectVCF = FileNameJoin[{prsFixtureDir, "subject.vcf"}];
prsFixtureScore = FileNameJoin[{prsFixtureDir, "PGS999999_hmPOS_GRCh37.txt"}];
Export[prsFixtureSubjectVCF,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n" <>
    "##INFO=<ID=AF,Number=A,Type=Float,Description=\"af\">\n##INFO=<ID=MAF,Number=1,Type=Float,Description=\"maf\">\n##INFO=<ID=R2,Number=1,Type=Float,Description=\"r2\">\n" <>
    "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tsub1\n" <>
    "chr1\t100\trs1\tA\tG\t60\tPASS\tAF=0.3;MAF=0.3;R2=0.99\tGT\t0/1\n" <>
    "chr1\t200\trs2\tC\tT\t60\tPASS\tAF=0.1;MAF=0.1;R2=0.98\tGT\t1/1\n" <>
    "chr1\t300\trs3\tA\tG\t60\tPASS\tAF=0.25;MAF=0.25;R2=0.97\tGT\t0/1\n" <>
    "chr1\t400\trs4\tA\tT\t60\tPASS\tAF=0.4;MAF=0.4;R2=0.9\tGT\t0/1\n" <>
    "chr1\t500\t.\tT\t.\t60\tPASS\t.\tGT\t0/0\n",
    "Text"
];
Export[prsFixtureScore,
    "###PGS CATALOG SCORING FILE\n#format_version=2.0\n#pgs_id=PGS999999\n#trait_reported=Fixture trait\n#weight_type=beta\n#variants_number=6\n#HmPOS_build=GRCh37\n" <>
    "rsID\tchr_name\teffect_allele\tother_allele\teffect_weight\thm_source\thm_rsID\thm_chr\thm_pos\tallelefrequency_effect\n" <>
    "rs1\t1\tG\tA\t0.5\tENSEMBL\trs1\t1\t100\t0.30\n" <>
    "rs2\t1\tT\tC\t-0.2\tENSEMBL\trs2\t1\t200\t0.10\n" <>
    "rs3\t1\tC\tT\t0.8\tENSEMBL\trs3\t1\t300\t0.25\n" <>
    "rs4\t1\tA\tT\t0.4\tENSEMBL\trs4\t1\t400\t0.40\n" <>
    "rs5\t1\tG\tA\t0.9\tENSEMBL\trs5\t1\t900\t0.50\n" <>
    "rs6\t1\tC\tT\t0.7\tENSEMBL\trs6\t1\t500\t0.20\n",
    "Text"
];
prsFixtureEntry = WolframInstitute`Genome`Private`computePolygenicRiskScore[prsFixtureSubjectVCF, prsFixtureScore];
prsExpScore = 1*0.5 + 2*(-0.2) + 1*0.8 + 0*0.7;
prsExpMean = 2*0.3*0.5 + 2*0.1*(-0.2) + 2*0.25*0.8 + 2*0.2*0.7;
prsExpVar = 2*0.3*0.7*0.5^2 + 2*0.1*0.9*(-0.2)^2 + 2*0.25*0.75*0.8^2 + 2*0.2*0.8*0.7^2;

VerificationTest[
    Keys[prsFixtureEntry],
    {"Score", "Percentile", "PGSID", "Trait", "NVariantsUsed", "NVariantsExpected", "Method"},
    TestID -> "computePolygenicRiskScore returns the seven-key PRS entry Association"
]

VerificationTest[
    {prsFixtureEntry["PGSID"], prsFixtureEntry["Trait"]},
    {"PGS999999", "Fixture trait"},
    TestID -> "computePolygenicRiskScore reads the PGS ID and trait from the scoring-file metadata"
]

VerificationTest[
    Abs[prsFixtureEntry["Score"] - prsExpScore] < 10^-9,
    True,
    TestID -> "computePolygenicRiskScore raw score equals sum(dosage * weight) over the used variants"
]

VerificationTest[
    {prsFixtureEntry["NVariantsUsed"], prsFixtureEntry["NVariantsExpected"]},
    {4, 6},
    TestID -> "computePolygenicRiskScore counts palindrome + subject-absent toward Expected but not Used"
]

VerificationTest[
    Abs[prsFixtureEntry["Percentile"]
        - CDF[NormalDistribution[prsExpMean, Sqrt[prsExpVar]], prsExpScore]] < 10^-9,
    True,
    TestID -> "computePolygenicRiskScore analytic percentile matches the normal CDF at the score"
]

(* === GWASAssociations catalog join + strand-aware dosage (fixture, no download) ===
   Drive the pure internal GWAS logic with a tiny gzipped reduced-catalog table
   (15-column per-association rows: rsid, chr38, pos38, riskAllele, RAF, p-value,
   OR/beta, 95% CI, disease/trait, mapped trait, mapped-trait URI, PubMedID,
   first author, date, journal), a matching rsID set, and a tiny subject VCF, so
   the rsID join, the strand-aware risk-allele dosage (het / hom-risk / hom-ref /
   reverse-complement / palindrome), the carry-through of the trait / PubMedID /
   OR columns, the ascending-p-value sort, and the "MaxPValue" / "CarriedOnly" /
   "Trait" filters are all pinned without the ~40 MB catalog download.  Needs only
   gzcat / awk / gzip (POSIX), so it runs on every checkout. *)

gwasFixtureDir = FileNameJoin[{$TemporaryDirectory, "wlgenome_gwas_fixture"}];
Quiet @ If[ DirectoryQ[gwasFixtureDir], DeleteDirectory[gwasFixtureDir, DeleteContents -> True]];
CreateDirectory[gwasFixtureDir];
gwasFixtureReduced = FileNameJoin[{gwasFixtureDir, "reduced.tsv"}];
gwasFixtureRsids = FileNameJoin[{gwasFixtureDir, "rsids.txt"}];
gwasFixtureSubject = FileNameJoin[{gwasFixtureDir, "subject.vcf"}];
(* rs100 carries two associations (Trait A, Trait B); rs900 is subject-absent. *)
Export[gwasFixtureReduced,
    "rs100\t1\t1000\tG\t0.3\t1E-10\t1.4\t[1.2-1.6]\tTrait A\ttrait a mapped\tEFO_0000001\t11111111\tSmith J\t2020-01-01\tNature\n" <>
    "rs100\t1\t1000\tG\t0.3\t4E-9\t1.2\t[1.1-1.3]\tTrait B\ttrait b mapped\tEFO_0000002\t22222222\tDoe A\t2021-02-02\tCell\n" <>
    "rs200\t1\t2000\tT\t0.5\t5E-9\t1.5\t[1.3-1.7]\tTrait C\ttrait c mapped\tEFO_0000003\t33333333\tLee K\t2019-03-03\tScience\n" <>
    "rs300\t1\t3000\tG\t0.2\t2E-8\t1.1\t[1.05-1.2]\tTrait D\ttrait d mapped\tEFO_0000004\t44444444\tKim S\t2022-04-04\tNature\n" <>
    "rs400\t1\t4000\tC\t0.4\t3E-12\t1.3\t[1.2-1.5]\tTrait E\ttrait e mapped\tEFO_0000005\t55555555\tWang L\t2018-05-05\tPLOS\n" <>
    "rs500\t1\t5000\tA\t0.1\t1E-6\t1.05\t[1.0-1.1]\tTrait F\ttrait f mapped\tEFO_0000006\t66666666\tRoy P\t2017-06-06\tBMJ\n" <>
    "rs900\t1\t9000\tA\t0.3\t1E-20\t2.0\t[1.8-2.2]\tTrait Z\ttrait z mapped\tEFO_0000009\t99999999\tZed Q\t2016-07-07\tNature\n",
    "Text"
];
Export[gwasFixtureRsids, "rs100\nrs200\nrs300\nrs400\nrs500\nrs900\n", "Text"];
(* Subject: rs100 het A/G, rs200 hom-alt C/T, rs300 hom-ref A/G (0/0), rs400 het
   A/G (risk C is revcomp of G), rs500 het A/T (palindrome), rs700 not in the
   catalog rsID set (dropped at the intersection). *)
Export[gwasFixtureSubject,
    "##fileformat=VCFv4.2\n##contig=<ID=chr1,length=249250621>\n#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tsub1\n" <>
    "chr1\t1000\trs100\tA\tG\t60\tPASS\t.\tGT\t0/1\n" <>
    "chr1\t2000\trs200\tC\tT\t60\tPASS\t.\tGT\t1/1\n" <>
    "chr1\t3000\trs300\tA\tG\t60\tPASS\t.\tGT\t0/0\n" <>
    "chr1\t4000\trs400\tA\tG\t60\tPASS\t.\tGT\t0/1\n" <>
    "chr1\t5000\trs500\tA\tT\t60\tPASS\t.\tGT\t0/1\n" <>
    "chr1\t6000\trs700\tA\tG\t60\tPASS\t.\tGT\t0/1\n",
    "Text"
];
RunProcess[{"sh", "-c", "gzip -f " <> gwasFixtureReduced <> "; gzip -f " <> gwasFixtureSubject}];
gwasFixtureFull = WolframInstitute`Genome`Private`computeGWASAssociations[
    gwasFixtureSubject <> ".gz",
    gwasFixtureReduced <> ".gz",
    gwasFixtureRsids
];
gwasFixtureByKey = Association @ Map[{#["RsID"], #["Trait"]} -> # &, Normal[gwasFixtureFull]];

VerificationTest[
    {Head[gwasFixtureFull], Normal[ColumnKeys[gwasFixtureFull]]},
    {Tabular, {"RsID", "GRCh37Position", "Genotype", "RiskAllele", "RiskAlleleDosage",
        "CarriesRisk", "Trait", "MappedTrait", "OddsRatioOrBeta", "PValue",
        "RiskAlleleFrequency", "PubMedID", "FirstAuthor", "Year", "Journal"}},
    TestID -> "computeGWASAssociations returns the 15-column GWASAssociations Tabular"
]

VerificationTest[
    Length[gwasFixtureFull],
    6,
    TestID -> "computeGWASAssociations keeps the matched rsIDs (rs100 twice) and drops the subject-absent rs900"
]

VerificationTest[
    Lookup[Normal[gwasFixtureFull], "PValue"] === Sort[Lookup[Normal[gwasFixtureFull], "PValue"]],
    True,
    TestID -> "computeGWASAssociations sorts rows by ascending p-value"
]

VerificationTest[
    First[Normal[gwasFixtureFull]]["RsID"],
    "rs400",
    TestID -> "computeGWASAssociations surfaces the strongest association (rs400, p = 3E-12) first"
]

VerificationTest[
    {gwasFixtureByKey[{"rs100", "Trait A"}]["RiskAlleleDosage"],
     gwasFixtureByKey[{"rs100", "Trait A"}]["CarriesRisk"]},
    {1, True},
    TestID -> "GWASAssociations scores a heterozygous risk-allele carrier as dosage 1"
]

VerificationTest[
    {gwasFixtureByKey[{"rs200", "Trait C"}]["RiskAlleleDosage"],
     gwasFixtureByKey[{"rs200", "Trait C"}]["CarriesRisk"]},
    {2, True},
    TestID -> "GWASAssociations scores a homozygous risk-allele carrier as dosage 2"
]

VerificationTest[
    {gwasFixtureByKey[{"rs300", "Trait D"}]["RiskAlleleDosage"],
     gwasFixtureByKey[{"rs300", "Trait D"}]["CarriesRisk"]},
    {0, False},
    TestID -> "GWASAssociations scores a homozygous-reference genotype as dosage 0 (does not carry)"
]

VerificationTest[
    {gwasFixtureByKey[{"rs400", "Trait E"}]["RiskAlleleDosage"],
     gwasFixtureByKey[{"rs400", "Trait E"}]["CarriesRisk"]},
    {1, True},
    TestID -> "GWASAssociations reconciles a reverse-complement risk allele (C for a G/A subject) to dosage 1"
]

VerificationTest[
    {gwasFixtureByKey[{"rs500", "Trait F"}]["RiskAlleleDosage"],
     gwasFixtureByKey[{"rs500", "Trait F"}]["CarriesRisk"]},
    {Missing[], Missing[]},
    TestID -> "GWASAssociations flags a strand-ambiguous palindrome (A/T) dosage as Missing"
]

VerificationTest[
    {gwasFixtureByKey[{"rs200", "Trait C"}]["PubMedID"],
     gwasFixtureByKey[{"rs200", "Trait C"}]["OddsRatioOrBeta"],
     gwasFixtureByKey[{"rs200", "Trait C"}]["Genotype"],
     gwasFixtureByKey[{"rs200", "Trait C"}]["GRCh37Position"],
     gwasFixtureByKey[{"rs200", "Trait C"}]["Year"],
     gwasFixtureByKey[{"rs100", "Trait A"}]["RiskAllele"]},
    {"33333333", 1.5, "T/T", "chr1:2000", 2019, "G"},
    TestID -> "GWASAssociations carries the trait / PubMedID / OR / genotype / position / year / risk-allele columns through the join"
]

VerificationTest[
    Length[WolframInstitute`Genome`Private`filterGWAS[gwasFixtureFull, All, 5*^-8, False]],
    5,
    TestID -> "filterGWAS \"MaxPValue\" keeps only the genome-wide-significant rows"
]

VerificationTest[
    Length[WolframInstitute`Genome`Private`filterGWAS[gwasFixtureFull, All, All, True]],
    4,
    TestID -> "filterGWAS \"CarriedOnly\" keeps only rows where the subject carries the risk allele"
]

VerificationTest[
    Block[{r = WolframInstitute`Genome`Private`filterGWAS[gwasFixtureFull, "trait c", All, False]},
        {Length[r], Normal[r][[1]]["RsID"]}
    ],
    {1, "rs200"},
    TestID -> "filterGWAS \"Trait\" substring-matches the disease / mapped trait text"
]

(* The pure strand-aware dosage core, driven directly. *)
VerificationTest[
    {WolframInstitute`Genome`Private`gwasRiskAlleleDosage["A", {"G"}, {"0", "1"}, "G"],
     WolframInstitute`Genome`Private`gwasRiskAlleleDosage["C", {"T"}, {"1", "1"}, "T"],
     WolframInstitute`Genome`Private`gwasRiskAlleleDosage["A", {"G"}, {"0", "0"}, "G"],
     WolframInstitute`Genome`Private`gwasRiskAlleleDosage["A", {"G"}, {"0", "1"}, "C"],
     WolframInstitute`Genome`Private`gwasRiskAlleleDosage["A", {"T"}, {"0", "1"}, "A"],
     WolframInstitute`Genome`Private`gwasRiskAlleleDosage["A", {"G"}, {"0", "1"}, "?"]},
    {<|"Dosage" -> 1, "Carries" -> True|>, <|"Dosage" -> 2, "Carries" -> True|>,
     <|"Dosage" -> 0, "Carries" -> False|>, <|"Dosage" -> 1, "Carries" -> True|>,
     Missing[], Missing[]},
    TestID -> "gwasRiskAlleleDosage: het 1, hom-risk 2, hom-ref 0, revcomp 1, palindrome Missing, unknown-allele Missing"
]

(* === sex inference cores (fixture, no tabix / no network) ===
   Drive the pure chrX-heterozygosity / chrY-count statistics and the karyotype
   rule on tiny synthetic VCF line lists so the male-like / female-like calls are
   pinned without any tabix read. *)

sexChrXFixtureLines = {
    "chrX\t3000000\t.\tA\tG\t60\tPASS\t.\tGT\t0/1",
    "chrX\t3000100\t.\tC\tT\t60\tPASS\t.\tGT\t1|0",
    "chrX\t3000200\t.\tG\tA\t60\tPASS\t.\tGT\t1/1",
    "chrX\t3000300\t.\tT\tC\t60\tPASS\t.\tGT\t1/1",
    "chrX\t3000400\t.\tA\tG\t60\tPASS\t.\tGT\t0/0",
    "chrX\t3000500\t.\tA\tG\t60\tq10\t.\tGT\t0/1",
    "chrX\t3000600\t.\tAT\tA\t60\tPASS\t.\tGT\t0/1"
};

sexChrYFixtureLines = {
    "chrY\t3000000\t.\tA\tG\t60\tPASS\t.\tGT\t1/1",
    "chrY\t3000100\t.\tC\tT\t60\tPASS\t.\tGT\t1",
    "chrY\t3000200\t.\tG\tA\t60\tPASS\t.\tGT\t0/0",
    "chrY\t3000300\t.\tT\tC\t60\tq10\t.\tGT\t1/1",
    "chrY\t3000400\t.\tA\t.\t60\tPASS\t.\tGT\t0/0"
};

VerificationTest[
    WolframInstitute`Genome`Private`sexChrXStats[sexChrXFixtureLines],
    <|"Calls" -> 5, "Het" -> 2, "Hom" -> 3, "HetRate" -> 0.4|>,
    TestID -> "sexChrXStats counts het / hom PASS biallelic SNV calls and skips non-PASS / indel rows"
]

VerificationTest[
    WolframInstitute`Genome`Private`sexChrYNonRefCount[sexChrYFixtureLines],
    2,
    TestID -> "sexChrYNonRefCount counts only non-reference PASS chrY calls"
]

VerificationTest[
    Map[
        Apply[WolframInstitute`Genome`Private`sexKaryotype],
        {{0., 9000, 600}, {0.55, 9000, 3}, {0.02, 9000, 3}, {0.6, 30, 600}}
    ],
    {"XY", "XX", "Undetermined", "Undetermined"},
    TestID -> "sexKaryotype: chrY + low X-het -> XY, no chrY + high X-het -> XX, else Undetermined"
]

VerificationTest[
    {WolframInstitute`Genome`Private`sexResult[
            <|"Calls" -> 9000, "Het" -> 0, "Hom" -> 9000, "HetRate" -> 0.|>, 600, "chrX:x", "chrY:y"]["KaryotypeCall"],
     WolframInstitute`Genome`Private`sexResult[
            <|"Calls" -> 9000, "Het" -> 5000, "Hom" -> 4000, "HetRate" -> 0.55|>, 1, "chrX:x", "chrY:y"]["KaryotypeCall"]},
    {"XY", "XX"},
    TestID -> "sexResult assembles a male-like (XY) and female-like (XX) call"
]

(* === mtDNA haplogroup cores (fixture, no network) ===
   Drive the alignment-to-variants walk, the Kulczynski scoring, and the deepest
   best-match classifier on tiny synthetic motifs so the classification logic is
   pinned without the PhyloTree download or a chrM read. *)

VerificationTest[
    WolframInstitute`Genome`Private`mtAlignedVariants["AAACTTGG", "AAAGTTGG"],
    <|4 -> "G"|>,
    TestID -> "mtAlignedVariants reports an aligned single-base substitution"
]

VerificationTest[
    WolframInstitute`Genome`Private`mtAlignedVariants["AAACTTGG", "AAANTTGG"],
    <||>,
    TestID -> "mtAlignedVariants ignores uncalled positions"
]

(* An insertion in the subject shifts every later base; the banded traceback has
   to absorb it so the substitution after the gap is still reported at its own
   reference position rather than smearing across the tail. *)
VerificationTest[
    WolframInstitute`Genome`Private`mtAlignedVariants[
        "AAACCCGGGTTTACGTACGT", "AAACCCGGGTTTGACGTCCGT"],
    <|17 -> "C"|>,
    TestID -> "mtAlignedVariants stays in frame across an insertion"
]

(* A length difference wider than the band has no in-band alignment at all. *)
VerificationTest[
    WolframInstitute`Genome`Private`mtAlignedVariants["AAAA", "AAAA" <> StringJoin[ConstantArray["T", 30]], 5],
    $Failed,
    TestID -> "mtAlignedVariants fails when the length difference exceeds the band"
]

(* Soft-masked reference bases must not read as mismatches. *)
VerificationTest[
    WolframInstitute`Genome`Private`mtConsensus[{
        "chrM\t1\t.\ta\t.\t.\tPASS\t.\tGT\t0/0",
        "chrM\t2\t.\tc\tT\t.\tPASS\t.\tGT\t1/1"}],
    "AT",
    TestID -> "mtConsensus uppercases soft-masked reference bases"
]

VerificationTest[
    Block[{s = WolframInstitute`Genome`Private`mtScorePair[
        <|100 -> "G", 200 -> "A", 300 -> "T"|>, <|100 -> "G", 200 -> "A", 400 -> "C"|>]},
        {s[[2]], s[[3]], Abs[s[[1]] - 2/3] < 10^-9}
    ],
    {2, 3, True},
    TestID -> "mtScorePair reports matches, expected, and the Kulczynski similarity"
]

VerificationTest[
    Block[{r = WolframInstitute`Genome`Private`mtClassify[
        <|100 -> "G", 200 -> "A", 300 -> "T"|>,
        <|
            "H" -> <|100 -> "G"|>,
            "H1" -> <|100 -> "G", 200 -> "A"|>,
            "H1a" -> <|100 -> "G", 200 -> "A", 300 -> "T"|>,
            "T" -> <|400 -> "C"|>
        |>]},
        {r["Haplogroup"], r["Quality"], r["NDefiningMatched"]}
    ],
    {"H1a", 1., 3},
    TestID -> "mtClassify assigns the deepest best-matching PhyloTree haplogroup"
]

(* === Y haplogroup cores (fixture, no network) ===
   Drive the ISOGG line parser, the subject-base reader, and the deepest-
   consistent-clade classifier on synthetic data so the paternal-lineage logic is
   pinned without the ISOGG download or a chrY read. *)

VerificationTest[
    {WolframInstitute`Genome`Private`yParseIsoggLine["M269\tR1b1a2\t \trs9786153\t22739367\tT->C"],
     MissingQ[WolframInstitute`Genome`Private`yParseIsoggLine["47z\tK (Notes)\t \t \t3436442\tG->C"]]},
    {{"22739367", "T", "C", "R1b1a2"}, True},
    TestID -> "yParseIsoggLine keeps clean long-form GRCh37 SNV markers and drops noted labels"
]

VerificationTest[
    {WolframInstitute`Genome`Private`yBaseFromRow[{"chrY", "100", ".", "A", "G", "60", "PASS", ".", "GT", "1/1"}],
     WolframInstitute`Genome`Private`yBaseFromRow[{"chrY", "100", ".", "A", ".", "60", "PASS", ".", "GT", "0/0"}],
     MissingQ[WolframInstitute`Genome`Private`yBaseFromRow[{"chrY", "100", ".", "A", "G", "60", "PASS", ".", "GT", "./."}]]},
    {"G", "A", True},
    TestID -> "yBaseFromRow reads the hom-alt ALT base, the hom-ref REF base, and drops a no-call"
]

yFixtureCalls = {
    <|"HG" -> "R", "State" -> "derived"|>,
    <|"HG" -> "R1", "State" -> "derived"|>,
    <|"HG" -> "R1b", "State" -> "derived"|>,
    <|"HG" -> "R1b1a2", "State" -> "derived"|>,
    <|"HG" -> "Q", "State" -> "ancestral"|>,
    <|"HG" -> "N1c", "State" -> "ancestral"|>
};
yFixtureLabels = {"R", "R1", "R1b", "R1b1", "R1b1a", "R1b1a2", "Q", "N", "N1", "N1c"};

VerificationTest[
    Block[{r = WolframInstitute`Genome`Private`yClassify[yFixtureCalls, yFixtureLabels]},
        {r["Haplogroup"], r["Confidence"], r["NDerived"]}
    ],
    {"R1b1a2", 1., 4},
    TestID -> "yClassify assigns the deepest derived-supported consistent Y clade"
]

VerificationTest[
    WolframInstitute`Genome`Private`yClassify[
        {<|"HG" -> "Q", "State" -> "ancestral"|>}, yFixtureLabels]["Haplogroup"],
    Missing["NoCall"],
    TestID -> "yClassify returns Missing[\"NoCall\"] when no clade is derived-supported"
]

(* === AncestryEstimate cores (fixture, no network) ===
   Drive the strand-matched dosage reader and the non-negative least-squares
   super-population fit on synthetic markers so the projection math is pinned
   without the 1000 Genomes download or a subject read. *)

VerificationTest[
    {WolframInstitute`Genome`Private`ancestryDosage[<|"Ref" -> "A", "Alt" -> "G", "GTParts" -> {"0", "1"}|>, "A", "G"],
     WolframInstitute`Genome`Private`ancestryDosage[<|"Ref" -> "A", "Alt" -> "G", "GTParts" -> {"1", "1"}|>, "A", "G"],
     WolframInstitute`Genome`Private`ancestryDosage[<|"Ref" -> "A", "Alt" -> ".", "GTParts" -> {"0", "0"}|>, "A", "G"],
     MissingQ[WolframInstitute`Genome`Private`ancestryDosage[<|"Ref" -> "C", "Alt" -> "T", "GTParts" -> {"0", "1"}|>, "A", "G"]]},
    {1, 2, 0, True},
    TestID -> "ancestryDosage: het 1, hom-alt 2, hom-ref 0, and a REF mismatch is Missing"
]

SeedRandom[123];
ancestryFixtureAFs = RandomReal[{0.05, 0.95}, {25, 5}];
(* Subject dosage fraction equals the EUR column (index 4), so a pure-EUR mix
   fits exactly. *)
ancestryFixtureMD = Map[{#[[4]], #} &, ancestryFixtureAFs];
ancestryFixtureEst = WolframInstitute`Genome`Private`ancestryEstimate[ancestryFixtureMD];

VerificationTest[
    {ancestryFixtureEst["Superpopulation"],
     ancestryFixtureEst["NMarkersUsed"],
     Abs[Total[Values[ancestryFixtureEst["SuperpopulationFractions"]]] - 1] < 0.001,
     ancestryFixtureEst["SuperpopulationFractions"]["EUR"] > 0.9},
    {"EUR", 25, True, True},
    TestID -> "ancestryEstimate recovers a pure-EUR mixture and returns simplex fractions"
]

VerificationTest[
    Keys[ancestryFixtureEst],
    {"Superpopulation", "SuperpopulationFractions", "NearestPopulations",
     "PrincipalComponents", "Method", "NMarkersUsed"},
    TestID -> "ancestryEstimate returns the documented result Association keys"
]

(* === PharmacogenomicProfile star-allele diplotype calling (fixture, no download) ===
   A tiny CPIC-style reduced structure for one synthetic gene GENEX with two
   star alleles: the *1 reference and a *2 defined by an A>G SNV at a single
   location, plus a second monomorphic defining site used to exercise the
   missing-site flag.  The
   internal callDiplotype, cpicLookupPhenotype, pgxConfidence and the full
   computePharmacogenomics assembly are driven directly in memory, so the join
   logic and the phenotype / guidance / confidence columns are pinned without
   any CPIC / Ensembl download or bcftools. *)

pgxFixtureGene = <|
    "Gene" -> "GENEX",
    "RefAllele" -> "*1",
    "RefBase" -> <|1 -> "A", 2 -> "C"|>,
    "GenomicRef" -> <|1 -> "A", 2 -> "C"|>,
    "Locations" -> {
        <|"Id" -> 1, "RsId" -> "rsX", "Chrom" -> "1", "Pos" -> 100|>,
        <|"Id" -> 2, "RsId" -> "rsY", "Chrom" -> "1", "Pos" -> 200|>
    },
    "Alleles" -> {
        <|"Name" -> "*1", "Function" -> "Normal function", "Activity" -> Null,
          "Structural" -> False, "DefSig" -> <||>|>,
        <|"Name" -> "*2", "Function" -> "No function", "Activity" -> Null,
          "Structural" -> False, "DefSig" -> <|1 -> "G"|>|>
    },
    "PhenotypeMap" -> <|
        {"*1", "*1"} -> <|"Phenotype" -> "Normal Metabolizer", "ActivityScore" -> "n/a"|>,
        {"*1", "*2"} -> <|"Phenotype" -> "Intermediate Metabolizer", "ActivityScore" -> "n/a"|>,
        {"*2", "*2"} -> <|"Phenotype" -> "Poor Metabolizer", "ActivityScore" -> "n/a"|>
    |>,
    "Guidance" -> <|
        "Drugs" -> {<|"DrugId" -> "D1", "Drug" -> "testdrug", "Level" -> "A"|>},
        "RecMap" -> <|
            {"D1", "Intermediate Metabolizer"} -> <|"Rec" -> "reduce dose", "Class" -> "Strong"|>
        |>
    |>
|>

pgxFixtureReduced = <|"Genes" -> {"GENEX"}, "PerGene" -> <|"GENEX" -> pgxFixtureGene|>|>

(* subject reads keyed by "chrom:pos"; the second site is present at reference
   unless a case drops it to exercise the missing-site flag. *)
pgxFixtureRead[loc1GT_, includeLoc2_ : True] :=
    Association @ Join[
        {"1:100" -> <|"Ref" -> "A", "Alt" -> If[ loc1GT === "0/0", {}, {"G"}],
            "GT" -> StringSplit[loc1GT, "/"]|>},
        If[ includeLoc2, {"1:200" -> <|"Ref" -> "C", "Alt" -> {}, "GT" -> {"0", "0"}|>}, {}]
    ]

pgxFixtureCall[loc1GT_, includeLoc2_ : True] :=
    WolframInstitute`Genome`Private`callDiplotype[
        pgxFixtureGene,
        WolframInstitute`Genome`Private`pgxSubjectAllelesByLoc[pgxFixtureGene, pgxFixtureRead[loc1GT, includeLoc2]]
    ]

VerificationTest[
    Block[{c = pgxFixtureCall["0/0"]},
        {c["Diplotype"], c["Consistent"], c["MissingSites"],
         WolframInstitute`Genome`Private`cpicLookupPhenotype[pgxFixtureGene, c["Alleles"]]["Phenotype"]}
    ],
    {"*1/*1", True, 0, "Normal Metabolizer"},
    TestID -> "callDiplotype: homozygous reference calls *1/*1 -> Normal Metabolizer"
]

VerificationTest[
    Block[{c = pgxFixtureCall["0/1"]},
        {c["Diplotype"],
         WolframInstitute`Genome`Private`cpicLookupPhenotype[pgxFixtureGene, c["Alleles"]]["Phenotype"]}
    ],
    {"*1/*2", "Intermediate Metabolizer"},
    TestID -> "callDiplotype: heterozygous for the defining variant calls *1/*2 -> Intermediate"
]

VerificationTest[
    Block[{c = pgxFixtureCall["1/1"]},
        {c["Diplotype"],
         WolframInstitute`Genome`Private`cpicLookupPhenotype[pgxFixtureGene, c["Alleles"]]["Phenotype"]}
    ],
    {"*2/*2", "Poor Metabolizer"},
    TestID -> "callDiplotype: homozygous for the defining variant calls *2/*2 -> Poor"
]

VerificationTest[
    Block[{c = pgxFixtureCall["0/0", False]},
        {c["MissingSites"], StringContainsQ[WolframInstitute`Genome`Private`pgxConfidence["GENEX", c], "Reduced confidence"]}
    ],
    {1, True},
    TestID -> "callDiplotype: a missing defining site sets the reduced-confidence flag"
]

pgxFixtureTab = WolframInstitute`Genome`Private`computePharmacogenomics[pgxFixtureReduced, pgxFixtureRead["0/1"]]

VerificationTest[
    {Head[pgxFixtureTab], Normal[ColumnKeys[pgxFixtureTab]]},
    {Tabular, {"Gene", "Diplotype", "Phenotype", "ActionableDrug", "CPICGuidance",
        "CPICLevel", "ActivityScore", "Confidence"}},
    TestID -> "computePharmacogenomics returns the 8-column Pharmacogenomics Tabular"
]

VerificationTest[
    Block[{row = First @ Normal[pgxFixtureTab]},
        {row["Gene"], row["Diplotype"], row["Phenotype"], row["ActionableDrug"],
         row["CPICGuidance"], row["CPICLevel"]}
    ],
    {"GENEX", "*1/*2", "Intermediate Metabolizer", "testdrug", "reduce dose", "A"},
    TestID -> "computePharmacogenomics carries the phenotype, actionable drug, guidance and level through"
]

(* === real-file tests, guarded === *)

If[ realVCFAvailable,
    VerificationTest[
        ImportVCFHeader[realVCF]["InferredBuild"],
        "GRCh37/hg19",
        TestID -> "ImportVCFHeader infers GRCh37/hg19 from contig lengths"
    ];
    VerificationTest[
        ImportVCFHeader[realVCF]["FileFormat"],
        "VCFv4.2",
        TestID -> "ImportVCFHeader reads FileFormat"
    ];
    VerificationTest[
        ImportVCFHeader[realVCF]["Source"],
        "Minimac4.v1.0.2",
        TestID -> "ImportVCFHeader reads Source"
    ];
    VerificationTest[
        ImportVCFHeader[realVCF]["Samples"],
        {realSample},
        TestID -> "ImportVCFHeader reads Samples from #CHROM line"
    ];
    VerificationTest[
        Length[ImportVCFHeader[realVCF]["Contigs"]],
        25,
        TestID -> "ImportVCFHeader reads 25 contigs"
    ];
    VerificationTest[
        Block[{first = First[ImportVCFHeader[realVCF]["Contigs"]]},
            {first["ID"], first["Length"]}
        ],
        {"chr1", 249250621},
        TestID -> "ImportVCFHeader first contig is chr1 with hg19 length"
    ];
    VerificationTest[
        Length[ImportVCFHeader[realVCF]["INFO"]],
        24,
        TestID -> "ImportVCFHeader reads 24 INFO definitions"
    ];
    VerificationTest[
        Length[ImportVCFHeader[realVCF]["FORMAT"]],
        1,
        TestID -> "ImportVCFHeader reads 1 FORMAT definition"
    ];
    VerificationTest[
        Length[ImportVCFHeader[realVCF]["FILTER"]],
        2,
        TestID -> "ImportVCFHeader reads 2 FILTER definitions"
    ];
    (* "Human" -> False keeps this a generic Genome so the Head === Genome
       and MatchQ[_Genome] filter-accumulation assertions below stay valid;
       the autopromotion path is covered by the HumanGenome block. *)
    g100 = ImportVCF[realVCF, "MaxVariants" -> 100, "Human" -> False];
    VerificationTest[
        Head[g100],
        Genome,
        TestID -> "ImportVCF with \"Human\" -> False returns a generic Genome"
    ];
    VerificationTest[
        GenomeQ[g100],
        True,
        TestID -> "GenomeQ recognises the ImportVCF result"
    ];
    VerificationTest[
        g100["Samples"],
        {realSample},
        TestID -> "Genome[\"Samples\"] returns the sample list"
    ];
    VerificationTest[
        g100["Build"],
        "GRCh37/hg19",
        TestID -> "Genome[\"Build\"] returns the inferred build"
    ];
    VerificationTest[
        g100["Backend"],
        (* Auto-detection prefers a tabix .tbi index (with bcftools on PATH)
           for its fast positional seeks and canonical row shape, then a
           Parquet sidecar (opt-in analytical columnar table), and falls back
           to AwkStream.  The expected value tracks whichever sibling files
           exist beside the real VCF so the test is green regardless. *)
        Which[
            FileExistsQ[realVCF <> ".tbi"]
                && MatchQ[RunProcess[{"sh", "-c", "command -v bcftools"}], KeyValuePattern["ExitCode" -> 0]],
                "Tabix",
            FileExistsQ[realVCF <> ".parquet"], "Parquet",
            True, "AwkStream"
        ],
        TestID -> "Genome[\"Backend\"] auto-detects the best available backend"
    ];
    VerificationTest[
        Head[g100["Variants"]],
        Tabular,
        TestID -> "Genome[\"Variants\"] returns a Tabular"
    ];
    VerificationTest[
        Length[Normal[g100["Variants"]]],
        100,
        TestID -> "Genome[\"Variants\"] with MaxVariants -> 100 returns 100 rows"
    ];
    VerificationTest[
        Block[{g2 = g100["MinR2", 0.5]},
            {MatchQ[g2, _Genome],
             Lookup[Association @ g2["Filters"], "MinImputationR2", Missing[]]}
        ],
        {True, 0.5},
        TestID -> "Filter accumulation returns a new Genome with the recorded rule"
    ];
    VerificationTest[
        Block[{g2 = g100["FilterPASS"]},
            {MatchQ[g2, _Genome],
             MemberQ[g2["Filters"], "PASSOnly" -> True]}
        ],
        {True, True},
        TestID -> "FilterPASS returns a new Genome with PASSOnly recorded"
    ];
    g200 = ImportVCF[realVCF, "MaxVariants" -> 200, "ExcludeReferenceOnly" -> True];
    VerificationTest[
        AllTrue[Normal[g200["Variants"]], #["ALT"] =!= {} &],
        True,
        TestID -> "ExcludeReferenceOnly drops ALT=. rows in the Genome view"
    ];
    (* The probe variant is READ from the file, never written down as a literal.
       The first row that carries an rsID is enough to exercise the row shape and
       the rsID lookups, and picking it at run time keeps the suite from
       recording which variants the sample it ran against actually carries. *)
    probeRow = FirstCase[
        Normal[g200["Variants"]],
        r_ /; StringQ[r["ID"]] && StringStartsQ[r["ID"], "rs"] :> r,
        Missing["NoProbe"]
    ];
    probeRsID = Lookup[probeRow, "ID", Missing["NoProbe"]];
    probeChrom = Lookup[probeRow, "CHROM", Missing["NoProbe"]];
    probePos = Lookup[probeRow, "POS", Missing["NoProbe"]];
    probeRegion = {probePos - 500, probePos + 500};
    VerificationTest[
        {StringQ[probeRsID], StringQ[probeChrom], IntegerQ[probePos]},
        {True, True, True},
        TestID -> "A probe rsID row is available in the first 200 variant rows"
    ];
    VerificationTest[
        Block[{row = First[Select[
            Normal[g200["Variants"]],
            #["ID"] === probeRsID &
        ]]},
            {StringQ[row["CHROM"]], IntegerQ[row["POS"]],
             MatchQ[row["R2"], _Real | _Missing], MatchQ[row["IMPUTED"], True | False]}
        ],
        {True, True, True, True},
        TestID -> "parseVCFRow surfaces R2 and IMPUTED as top-level columns"
    ];
    g500 = ImportVCF[realVCF, "MaxVariants" -> 500, "ExcludeReferenceOnly" -> True];
    t500 = g500["Variants"];
    VerificationTest[
        Block[{row = GenotypeLookup[g500, probeRsID]},
            {Head[row], row["CHROM"] === probeChrom, row["POS"] === probePos}
        ],
        {Association, True, True},
        TestID -> "GenotypeLookup on a Genome returns the probe rsID row"
    ];
    VerificationTest[
        Block[{row = GenotypeLookup[t500, probeRsID]},
            {Head[row], row["CHROM"] === probeChrom, row["POS"] === probePos}
        ],
        {Association, True, True},
        TestID -> "GenotypeLookup on a Tabular returns the probe rsID row"
    ];
    VerificationTest[
        MatchQ[
            GenotypeLookup[g500, "rs00000000_does_not_exist"],
            Missing["NotFound", _]
        ],
        True,
        TestID -> "GenotypeLookup returns Missing[\"NotFound\", _] for an unknown rsID"
    ];
    VerificationTest[
        Block[{result = GenotypeLookup[g500, {probeRsID, "rs00000000_does_not_exist"}]},
            {MatchQ[result, _Association], MatchQ[result[probeRsID], _Association]}
        ],
        {True, True},
        TestID -> "GenotypeLookup list form returns an Association keyed by rsID"
    ];
    VerificationTest[
        Head[RegionVariants[g500, probeChrom, probeRegion]],
        Tabular,
        TestID -> "RegionVariants on a Genome returns a Tabular"
    ];
    VerificationTest[
        Block[{rows = Normal[RegionVariants[t500, probeChrom, probeRegion]]},
            {Length[rows] >= 1,
             AllTrue[rows,
                #["CHROM"] === probeChrom
                    && First[probeRegion] <= #["POS"] <= Last[probeRegion] &]}
        ],
        {True, True},
        TestID -> "RegionVariants on a Tabular filters by chrom + interval"
    ];
    VerificationTest[
        Block[{
            all = Normal[RegionVariants[realVCF, probeChrom, probeRegion,
                "ExcludeReferenceOnly" -> True]],
            pass = Normal[RegionVariants[realVCF, probeChrom, probeRegion,
                "PASSOnly" -> True, "ExcludeReferenceOnly" -> True]]},
            {Length[all] >= 1, Length[pass] <= Length[all]}
        ],
        {True, True},
        TestID -> "RegionVariants on a path streams the probe region, and PASSOnly narrows it"
    ];
    (* A non-chr1 region seek (TP53 in GRCh37, chr17:7571720-7590868).  When the
       source file is BGZF with a sibling .tbi the Tabix backend serves this in
       milliseconds; otherwise the AwkStream backend still answers it correctly,
       just after decompressing up to the locus.  Either way the count is a
       stable property of this dataset. *)
    VerificationTest[
        Length[Normal[
            RegionVariants[realVCF, "chr17", {7571720, 7590868},
                "PASSOnly" -> True, "ExcludeReferenceOnly" -> True]
        ]] >= 20,
        True,
        TestID -> "RegionVariants on a path seeks the TP53 region off chr1"
    ];
    summary500 = VariantSummary[g500];
    summary500Assoc = Association @ Map[
        r |-> Lookup[r, "Metric"] -> Lookup[r, "Value"],
        Normal[summary500]
    ];
    VerificationTest[
        Head[summary500],
        Tabular,
        TestID -> "VariantSummary returns a Tabular"
    ];
    VerificationTest[
        summary500Assoc["TotalRows"],
        500,
        TestID -> "VariantSummary Tabular TotalRows row equals 500"
    ];
    VerificationTest[
        summary500Assoc["VariantRows"],
        500,
        TestID -> "VariantSummary Tabular VariantRows row equals 500"
    ];
    VerificationTest[
        KeyExistsQ[summary500Assoc["ByChromosome"], "chr1"],
        True,
        TestID -> "VariantSummary Tabular ByChromosome includes chr1"
    ];
    VerificationTest[
        Keys[summary500Assoc["ByImputationFlag"]],
        {"TYPED", "IMPUTED", "TYPED_ONLY", "NeitherFlag"},
        TestID -> "VariantSummary ByImputationFlag has the four expected keys"
    ];
    VerificationTest[
        MatchQ[summary500Assoc["TransitionTransversionRatio"], _Real]
            && summary500Assoc["TransitionTransversionRatio"] > 0,
        True,
        TestID -> "VariantSummary TransitionTransversionRatio is a positive Real"
    ];
    (* --- HumanGenome autopromotion on the real file --- *)
    hgReal = ImportVCF[realVCF, "MaxVariants" -> 100];
    gReal = ImportVCF[realVCF, "MaxVariants" -> 100, "Human" -> False];
    VerificationTest[
        {Head[hgReal], HumanGenomeQ[hgReal], GenomeQ[hgReal]},
        {HumanGenome, True, True},
        TestID -> "ImportVCF autopromotes the real GRCh37 single-sample file to HumanGenome"
    ];
    VerificationTest[
        {Head[gReal], HumanGenomeQ[gReal], GenomeQ[gReal]},
        {Genome, False, True},
        TestID -> "ImportVCF \"Human\" -> False on the real file stays a generic Genome"
    ];
    VerificationTest[
        {hgReal["Build"], hgReal["Samples"], hgReal["Backend"] === gReal["Backend"]},
        {"GRCh37/hg19", {realSample}, True},
        TestID -> "HumanGenome forwards Build / Samples / Backend to the inner Genome (real file)"
    ];
    VerificationTest[
        hgReal["Ancestry"],
        Missing["NotComputed"],
        TestID -> "HumanGenome Ancestry slot reads Missing[\"NotComputed\"] before computation (real file)"
    ];
    VerificationTest[
        Block[{f = hgReal["Chromosome", "chr1"]},
            {HumanGenomeQ[f], hgReal["Subject", "ID"], MemberQ[f["Filters"], "Chromosome" -> "chr1"]}
        ],
        {True, realSample, True},
        TestID -> "Filter accumulation on the real HumanGenome preserves annotations"
    ];
    (* Same run-time probe discipline as above: hgReal / gReal are unfiltered
       100-row views, so their probe is looked up separately. *)
    hgProbeRow = FirstCase[
        Normal[hgReal["Variants"]],
        r_ /; StringQ[r["ID"]] && StringStartsQ[r["ID"], "rs"] :> r,
        Missing["NoProbe"]
    ];
    hgProbeRsID = Lookup[hgProbeRow, "ID", Missing["NoProbe"]];
    hgProbeChrom = Lookup[hgProbeRow, "CHROM", Missing["NoProbe"]];
    hgProbePos = Lookup[hgProbeRow, "POS", Missing["NoProbe"]];
    hgProbeRegion = {hgProbePos - 500, hgProbePos + 500};
    VerificationTest[
        GenotypeLookup[hgReal, hgProbeRsID] === GenotypeLookup[gReal, hgProbeRsID],
        True,
        TestID -> "GenotypeLookup identical on HumanGenome and Genome (real file)"
    ];
    VerificationTest[
        Normal[RegionVariants[hgReal, hgProbeChrom, hgProbeRegion]]
            === Normal[RegionVariants[gReal, hgProbeChrom, hgProbeRegion]],
        True,
        TestID -> "RegionVariants identical on HumanGenome and Genome (real file)"
    ];
    VerificationTest[
        Normal[VariantSummary[hgReal]] === Normal[VariantSummary[gReal]],
        True,
        TestID -> "VariantSummary identical on HumanGenome and Genome (real file)"
    ];
    VerificationTest[
        Head[ToBoxes[hgReal, StandardForm]],
        InterpretationBox,
        TestID -> "HumanGenome MakeBoxes on the real file produces an InterpretationBox"
    ];
    (* The real genome is where the disclosure would matter: an annotated
       handle must render as a plain summary carrying none of its findings. *)
    VerificationTest[
        Head[ToBoxes[
            Replace[hgReal, HumanGenome[g_, ann_] :> HumanGenome[g,
                Append[ann, "Carrier" -> Tabular[{<|"Gene" -> "SECRETGENE"|>}]]]],
            StandardForm]] === InterpretationBox,
        False,
        TestID -> "an annotated real HumanGenome renders as a non-interpretable summary"
    ];
    (* --- ClinVarHits on the real genome (guarded on the prepared reference) --- *)
    clinVarPreparedReal = FileNameJoin[{DirectoryName[realVCF], "references", "clinvar_GRCh37_plp_chr.vcf.gz"}];
    If[ FileExistsQ[clinVarPreparedReal],
        cvRealHg = ClinVarHits[ImportVCF[realVCF]];
        VerificationTest[
            HumanGenomeQ[cvRealHg] && MatchQ[cvRealHg["ClinVarHits"], _Tabular],
            True,
            TestID -> "ClinVarHits on the real genome returns a HumanGenome with a Tabular ClinVarHits slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[cvRealHg["ClinVarHits"]]],
            {"VariantID", "RsID", "Gene", "ClinicalSignificance", "ReviewStatus",
             "Condition", "VCVAccession", "Genotype", "Zygosity",
             "PopulationAF", "FrequencySource", "ImputationQuality"},
            TestID -> "Real ClinVarHits Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[cvRealHg["ClinVarHits"]]}, IntegerQ[n] && n >= 0],
            True,
            TestID -> "Real ClinVarHits count is a plausible non-negative integer"
        ];
        VerificationTest[
            StringQ[cvRealHg["References", "ClinVarRelease"]],
            True,
            TestID -> "Real ClinVarHits records the ClinVar release string"
        ];
        VerificationTest[
            ClinVarHits[cvRealHg] === cvRealHg,
            True,
            TestID -> "A second ClinVarHits call is a fast in-memory cache hit"
        ];
        (* The new frequency / imputation columns.  Guarded additionally on the
           gnomAD cache so a fresh checkout (no cached frequency store, or offline)
           skips these cleanly.  Every PopulationAF is a number or Missing, the
           source label is present, and each ImputationQuality reads as directly
           sequenced or imputed. *)
        gnomadCacheReal = FileNameJoin[{DirectoryName[realVCF], "references", "gnomad_af_gnomAD_r2_1.tsv"}];
        If[ FileExistsQ[gnomadCacheReal],
            VerificationTest[
                AllTrue[
                    Lookup[Normal[cvRealHg["ClinVarHits"]], "PopulationAF"],
                    NumericQ[#] || MissingQ[#] &
                ],
                True,
                TestID -> "Real ClinVarHits PopulationAF is numeric or Missing for every hit"
            ];
            VerificationTest[
                Union[Lookup[Normal[cvRealHg["ClinVarHits"]], "FrequencySource"]],
                {"gnomAD_r2_1"},
                TestID -> "Real ClinVarHits records the gnomAD frequency source"
            ];
            VerificationTest[
                AllTrue[
                    Lookup[Normal[cvRealHg["ClinVarHits"]], "ImputationQuality"],
                    StringQ[#] && (# === "Directly sequenced" || StringStartsQ[#, "Imputed R2="]) &
                ],
                True,
                TestID -> "Real ClinVarHits ImputationQuality reads as directly sequenced or imputed"
            ]
        ]
    ];
    (* --- AlphaMissenseScores on the real genome (guarded on the hg19 reference) --- *)
    amPreparedReal = FileNameJoin[{DirectoryName[realVCF], "references", "AlphaMissense_hg19.tsv.gz"}];
    If[ FileExistsQ[amPreparedReal],
        amRealHg = AlphaMissenseScores[ImportVCF[realVCF]];
        VerificationTest[
            HumanGenomeQ[amRealHg] && MatchQ[amRealHg["AlphaMissenseScores"], _Tabular],
            True,
            TestID -> "AlphaMissenseScores on the real genome returns a HumanGenome with a Tabular slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[amRealHg["AlphaMissenseScores"]]],
            {"VariantID", "RsID", "Gene", "Transcript", "ProteinChange",
             "Genotype", "Zygosity", "AMScore", "AMClass"},
            TestID -> "Real AlphaMissenseScores Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[amRealHg["AlphaMissenseScores"]]}, IntegerQ[n] && n > 0],
            True,
            TestID -> "Real AlphaMissenseScores count is a positive integer"
        ];
        VerificationTest[
            AllTrue[Normal[amRealHg["AlphaMissenseScores"]],
                0 <= #["AMScore"] <= 1 &],
            True,
            TestID -> "Real AlphaMissenseScores are all in [0, 1]"
        ];
        VerificationTest[
            SubsetQ[
                {"likely_benign", "ambiguous", "likely_pathogenic"},
                Union[Lookup[Normal[amRealHg["AlphaMissenseScores"]], "AMClass"]]
            ],
            True,
            TestID -> "Real AlphaMissenseScores use only the canonical AM classes"
        ];
        VerificationTest[
            StringQ[amRealHg["References", "AlphaMissenseRelease"]],
            True,
            TestID -> "Real AlphaMissenseScores records the AlphaMissense release string"
        ];
        VerificationTest[
            AlphaMissenseScores[amRealHg] === amRealHg,
            True,
            TestID -> "A second AlphaMissenseScores call is a fast in-memory cache hit"
        ];
        (* Regression: a narrower MinScore on an ALREADY-populated genome must
           re-apply, not return the previous filtered slot unchanged. *)
        VerificationTest[
            Block[{narrow = AlphaMissenseScores[amRealHg, "MinScore" -> 0.9]["AlphaMissenseScores"]},
                Length[narrow] < Length[amRealHg["AlphaMissenseScores"]]
                    && AllTrue[Normal[narrow], #["AMScore"] >= 0.9 &]
            ],
            True,
            TestID -> "AlphaMissenseScores MinScore filter re-applies on a populated genome"
        ]
    ];
    (* --- TraitAssociations on the real genome (guarded on the Traits sidecar) ---
       The guard is the per-subject sidecar, not just the rsID set: the real-
       genome TraitAssociations path is a fast hydration check and must never
       trigger a live SNPedia compute, which streams the whole genome and fetches
       thousands of pages from the flaky bots.snpedia.com API.  Build the
       sidecar once out-of-band (evaluate TraitAssociations[ImportVCF[realVCF]]
       interactively); the test then hydrates it in negligible time. *)
    traitsSubjectReal = ImportVCF[realVCF]["Subject", "ID"];
    traitsSidecarReal = FileNameJoin[{DirectoryName[realVCF], traitsSubjectReal,
        "interpretations", "traits.tabular"}];
    If[ FileExistsQ[traitsSidecarReal],
        traitsRealHg = TraitAssociations[ImportVCF[realVCF]];
        VerificationTest[
            HumanGenomeQ[traitsRealHg] && MatchQ[traitsRealHg["Traits"], _Tabular],
            True,
            TestID -> "TraitAssociations on the real genome returns a HumanGenome with a Tabular Traits slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[traitsRealHg["Traits"]]],
            {"RsID", "Genotype", "Magnitude", "Repute", "Summary", "URL", "Category"},
            TestID -> "Real Traits Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[traitsRealHg["Traits"]]}, IntegerQ[n] && n > 0],
            True,
            TestID -> "Real TraitAssociations count is a positive integer"
        ];
        VerificationTest[
            AllTrue[Normal[traitsRealHg["Traits"]], NumericQ[#Magnitude] && #Magnitude >= 0 &],
            True,
            TestID -> "Real TraitAssociations magnitudes are all numeric and non-negative"
        ];
        VerificationTest[
            SubsetQ[{"Good", "Bad", "None"},
                Union[Lookup[Normal[traitsRealHg["Traits"]], "Repute"]]],
            True,
            TestID -> "Real TraitAssociations reputes use only Good / Bad / None"
        ];
        VerificationTest[
            StringQ[traitsRealHg["References", "SNPediaCommit"]],
            True,
            TestID -> "Real TraitAssociations records the SNPedia snapshot commit string"
        ];
        VerificationTest[
            TraitAssociations[traitsRealHg] === traitsRealHg,
            True,
            TestID -> "A second TraitAssociations call is a fast in-memory cache hit"
        ]
    ];
    (* --- CarrierStatus on the real genome (guarded on the ClinVar reference
       and the prepared PanelApp MOI map) ---
       CarrierStatus reuses ClinVarHits, so it needs the prepared GRCh37 P/LP
       reference; and it needs the per-gene PanelApp MOI cache, which is built
       once out-of-band (evaluate CarrierStatus[ImportVCF[realVCF]]
       interactively).  When both are present the test classifies the real
       hits without any download. *)
    carrierPanelReal = FileNameJoin[{DirectoryName[realVCF], "references", "panelapp_carrier_moi.tsv"}];
    If[ FileExistsQ[clinVarPreparedReal] && FileExistsQ[carrierPanelReal],
        csRealHg = CarrierStatus[ImportVCF[realVCF]];
        VerificationTest[
            HumanGenomeQ[csRealHg] && MatchQ[csRealHg["Carrier"], _Tabular],
            True,
            TestID -> "CarrierStatus on the real genome returns a HumanGenome with a Tabular Carrier slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[csRealHg["Carrier"]]],
            {"Gene", "VariantID", "RsID", "Zygosity", "Inheritance", "CarrierClassification",
             "ClinicalSignificance", "Condition", "ReviewStatus", "PopulationAF", "ImputationQuality"},
            TestID -> "Real CarrierStatus Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[csRealHg["Carrier"]]}, IntegerQ[n] && n >= 0],
            True,
            TestID -> "Real CarrierStatus count is a plausible non-negative integer"
        ];
        VerificationTest[
            SubsetQ[
                {"Carrier", "Homozygous (possible affected)", "X-linked",
                 "Dominant finding", "Unclassified"},
                Union[Lookup[Normal[csRealHg["Carrier"]], "CarrierClassification"]]
            ],
            True,
            TestID -> "Real CarrierStatus uses only the fixed classification vocabulary"
        ];
        VerificationTest[
            StringQ[csRealHg["References", "CarrierGenePanelVersion"]],
            True,
            TestID -> "Real CarrierStatus records the PanelApp gene-panel version string"
        ];
        VerificationTest[
            CarrierStatus[csRealHg] === csRealHg,
            True,
            TestID -> "A second CarrierStatus call is a fast in-memory cache hit"
        ];
        (* The carrier-screening frequency filter.  Guarded additionally on the
           gnomAD cache so a fresh checkout (no cached frequency store, or offline)
           skips these cleanly.  At the 0.01 default no returned carrier retains a
           common-polymorphism frequency, while relaxing the threshold reveals at
           least one high-frequency variant (a ClinVar-pathogenic common
           polymorphism) that the default drops - and genuine rare carriers stay. *)
        gnomadCacheReal = FileNameJoin[{DirectoryName[realVCF], "references", "gnomad_af_gnomAD_r2_1.tsv"}];
        If[ FileExistsQ[gnomadCacheReal],
            VerificationTest[
                AllTrue[
                    Lookup[Normal[csRealHg["Carrier"]], "PopulationAF"],
                    MissingQ[#] || (NumericQ[#] && # <= 0.01) &
                ],
                True,
                TestID -> "Real CarrierStatus at the 0.01 default keeps no common polymorphism"
            ];
            VerificationTest[
                AnyTrue[
                    Lookup[
                        Normal[CarrierStatus[ImportVCF[realVCF], "MaxPopulationAF" -> 1.0]["Carrier"]],
                        "PopulationAF"
                    ],
                    NumericQ[#] && # > 0.05 &
                ],
                True,
                TestID -> "Real CarrierStatus relaxed to 1.0 exposes a common-polymorphism carrier the default drops"
            ];
            VerificationTest[
                MemberQ[Lookup[Normal[csRealHg["Carrier"]], "CarrierClassification"], "Carrier"],
                True,
                TestID -> "Real CarrierStatus at the 0.01 default still keeps genuine rare carriers"
            ]
        ]
    ];
    (* --- PolygenicRiskScore on the real genome (guarded on a prepared scoring
       file) ---
       The guard is the prepared LDL scoring file under data/references/pgs/;
       score it once out-of-band (evaluate
       PolygenicRiskScore[ImportVCF[realVCF], "LDL cholesterol"] interactively)
       so this test hydrates from the per-subject sidecar or scores the small
       (~100-variant) file quickly. *)
    prsScoreFileReal = FileNameJoin[{DirectoryName[realVCF], "references", "pgs",
        "PGS000065_hmPOS_GRCh37.txt.gz"}];
    If[ FileExistsQ[prsScoreFileReal],
        prsRealHg = PolygenicRiskScore[ImportVCF[realVCF], "LDL cholesterol"];
        VerificationTest[
            HumanGenomeQ[prsRealHg] && AssociationQ[prsRealHg["PRS"]]
                && KeyExistsQ[prsRealHg["PRS"], "PGS000065"],
            True,
            TestID -> "PolygenicRiskScore on the real genome returns a HumanGenome with a PRS map entry"
        ];
        VerificationTest[
            Keys[prsRealHg["PRS", "PGS000065"]],
            {"Score", "Percentile", "PGSID", "Trait", "NVariantsUsed", "NVariantsExpected", "Method"},
            TestID -> "Real PolygenicRiskScore entry carries the expected keys"
        ];
        VerificationTest[
            Block[{e = prsRealHg["PRS", "PGS000065"]},
                NumericQ[e["Score"]] && IntegerQ[e["NVariantsUsed"]] && e["NVariantsUsed"] > 0
                    && e["NVariantsUsed"] <= e["NVariantsExpected"]
                    && (MissingQ[e["Percentile"]] || (0 <= e["Percentile"] <= 1))
            ],
            True,
            TestID -> "Real PolygenicRiskScore entry has a numeric score, positive coverage, and a valid percentile"
        ];
        VerificationTest[
            StringQ[prsRealHg["References", "PGSCatalogVersion"]],
            True,
            TestID -> "Real PolygenicRiskScore records the PGS Catalog version string"
        ];
        VerificationTest[
            PolygenicRiskScore[prsRealHg, "LDL cholesterol"] === prsRealHg,
            True,
            TestID -> "A second PolygenicRiskScore call is a fast in-memory cache hit"
        ]
    ];
    (* --- GWASAssociations on the real genome (guarded on the per-subject
       sidecar) ---
       Guard on the sidecar, not just the reduced catalog table: the real-genome
       compute streams the whole 8.4 GB VCF once to intersect it by rsID with the
       ~545k documented SNPs, so the test must never trigger a live compute.
       Build the sidecar once out-of-band (evaluate GWASAssociations[ImportVCF[
       realVCF]] interactively); the test then hydrates it in negligible time and
       re-applies the MaxPValue filter. *)
    gwasSubjectReal = ImportVCF[realVCF]["Subject", "ID"];
    gwasSidecarReal = FileNameJoin[{DirectoryName[realVCF], gwasSubjectReal,
        "interpretations", "gwas-associations.tabular"}];
    If[ FileExistsQ[gwasSidecarReal],
        gwasRealHg = GWASAssociations[ImportVCF[realVCF], "MaxPValue" -> 5*^-8];
        VerificationTest[
            HumanGenomeQ[gwasRealHg] && MatchQ[gwasRealHg["GWASAssociations"], _Tabular],
            True,
            TestID -> "GWASAssociations on the real genome returns a HumanGenome with a Tabular slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[gwasRealHg["GWASAssociations"]]],
            {"RsID", "GRCh37Position", "Genotype", "RiskAllele", "RiskAlleleDosage",
             "CarriesRisk", "Trait", "MappedTrait", "OddsRatioOrBeta", "PValue",
             "RiskAlleleFrequency", "PubMedID", "FirstAuthor", "Year", "Journal"},
            TestID -> "Real GWASAssociations Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[gwasRealHg["GWASAssociations"]]}, IntegerQ[n] && n > 0],
            True,
            TestID -> "Real GWASAssociations count is a positive integer"
        ];
        VerificationTest[
            AllTrue[Normal[gwasRealHg["GWASAssociations"]],
                MatchQ[#CarriesRisk, True | False | _Missing] &],
            True,
            TestID -> "Real GWASAssociations CarriesRisk is boolean or Missing"
        ];
        VerificationTest[
            AllTrue[Normal[gwasRealHg["GWASAssociations"]],
                MatchQ[#RiskAlleleDosage, 0 | 1 | 2 | _Missing] &],
            True,
            TestID -> "Real GWASAssociations RiskAlleleDosage is 0, 1, 2, or Missing"
        ];
        VerificationTest[
            AllTrue[Normal[gwasRealHg["GWASAssociations"]],
                NumericQ[#PValue] && #PValue <= 5*^-8 &],
            True,
            TestID -> "Real GWASAssociations respects the MaxPValue genome-wide-significance cut"
        ];
        VerificationTest[
            StringQ[gwasRealHg["References", "GWASCatalogVersion"]],
            True,
            TestID -> "Real GWASAssociations records the GWAS Catalog release string"
        ];
        VerificationTest[
            GWASAssociations[gwasRealHg, "MaxPValue" -> 5*^-8] === gwasRealHg,
            True,
            TestID -> "A second GWASAssociations call is a fast in-memory cache hit"
        ];
        (* Regression: a narrower filter on an ALREADY-populated genome must
           re-apply, not return the previous filtered slot unchanged. *)
        VerificationTest[
            Block[{narrow = GWASAssociations[gwasRealHg, "Trait" -> "testosterone"]["GWASAssociations"],
                   hasNeedle},
                hasNeedle = Function[row,
                    Or[
                        StringQ[row["Trait"]] && StringContainsQ[ToLowerCase[row["Trait"]], "testosterone"],
                        StringQ[row["MappedTrait"]] && StringContainsQ[ToLowerCase[row["MappedTrait"]], "testosterone"]
                    ]
                ];
                Length[narrow] < Length[gwasRealHg["GWASAssociations"]]
                    && Length[narrow] > 0
                    && AllTrue[Normal[narrow], hasNeedle]
            ],
            True,
            TestID -> "GWASAssociations Trait filter re-applies on a populated genome"
        ]
    ];
    (* --- PharmacogenomicProfile on the real genome (guarded on the prepared CPIC
       reference) ---
       Guard on the reduced CPIC reference so the test never triggers the CPIC /
       Ensembl download; with the reference present the compute reads only the
       few hundred defining positions through the tabix index (a few seconds).
       No hard-coded diplotypes are asserted. *)
    pgxCpicReducedReal = FileNameJoin[{DirectoryName[realVCF], "references", "cpic", "cpic_reduced.wxf"}];
    If[ FileExistsQ[pgxCpicReducedReal] && WolframInstitute`Genome`Private`onPathQ["bcftools"],
        pgxRealHg = PharmacogenomicProfile[ImportVCF[realVCF]];
        VerificationTest[
            HumanGenomeQ[pgxRealHg] && MatchQ[pgxRealHg["Pharmacogenomics"], _Tabular],
            True,
            TestID -> "PharmacogenomicProfile on the real genome returns a HumanGenome with a Tabular slot"
        ];
        VerificationTest[
            Normal[ColumnKeys[pgxRealHg["Pharmacogenomics"]]],
            {"Gene", "Diplotype", "Phenotype", "ActionableDrug", "CPICGuidance",
             "CPICLevel", "ActivityScore", "Confidence"},
            TestID -> "Real Pharmacogenomics Tabular carries the expected columns"
        ];
        VerificationTest[
            With[{n = Length[pgxRealHg["Pharmacogenomics"]]}, IntegerQ[n] && n > 0],
            True,
            TestID -> "Real PharmacogenomicProfile count is a positive integer"
        ];
        VerificationTest[
            ContainsAll[
                DeleteDuplicates[#Gene & /@ Normal[pgxRealHg["Pharmacogenomics"]]],
                {"CYP2C19", "CYP2C9", "VKORC1", "TPMT", "SLCO1B1", "DPYD", "CYP3A5",
                 "UGT1A1", "NUDT15", "CYP2B6", "CYP2D6"}
            ],
            True,
            TestID -> "Real PharmacogenomicProfile covers every curated gene"
        ];
        VerificationTest[
            AllTrue[Normal[pgxRealHg["Pharmacogenomics"]],
                StringQ[#Phenotype] && StringQ[#Diplotype] && StringQ[#Confidence] &],
            True,
            TestID -> "Real PharmacogenomicProfile rows carry a string diplotype, phenotype and confidence"
        ];
        VerificationTest[
            AllTrue[Normal[pgxRealHg["Pharmacogenomics"]],
                #Gene =!= "CYP2D6" || StringContainsQ[#Confidence, "CYP2D6 SNV-only"] &],
            True,
            TestID -> "Real PharmacogenomicProfile flags the CYP2D6 CNV / hybrid caveat"
        ];
        VerificationTest[
            StringQ[pgxRealHg["References", "CPICVersion"]],
            True,
            TestID -> "Real PharmacogenomicProfile records the CPIC data version"
        ];
        VerificationTest[
            PharmacogenomicProfile[pgxRealHg] === pgxRealHg,
            True,
            TestID -> "A second PharmacogenomicProfile call is a fast sidecar cache hit"
        ];
        VerificationTest[
            Block[{restricted = PharmacogenomicProfile[pgxRealHg, "Genes" -> "CYP2C19"]["Pharmacogenomics"]},
                Length[restricted] > 0
                    && Length[restricted] < Length[pgxRealHg["Pharmacogenomics"]]
                    && AllTrue[Normal[restricted], #Gene === "CYP2C19" &]
            ],
            True,
            TestID -> "PharmacogenomicProfile Genes filter re-applies on a populated genome"
        ]
    ];
    (* --- ChromosomalSex on the real genome (guarded on the tabix index) ---
       ChromosomalSex needs no external reference, only the tabix index; it
       computes from two chromosome-window reads (or hydrates the sidecar) in a
       few seconds. *)
    If[ FileExistsQ[realVCF <> ".tbi"] && tabixToolsAvailable,
        sexReal = ChromosomalSex[ImportVCF[realVCF]];
        VerificationTest[
            MemberQ[{"XY", "XX", "Undetermined"}, sexReal["KaryotypeCall"]],
            True,
            TestID -> "ChromosomalSex on the real genome returns one of the karyotype strings"
        ];
        VerificationTest[
            IntegerQ[sexReal["ChrYVariantCount"]] && sexReal["ChrYVariantCount"] >= 0
                && (NumericQ[sexReal["ChrXHetRate"]] || MissingQ[sexReal["ChrXHetRate"]]),
            True,
            TestID -> "Real ChromosomalSex reports a chrY variant count and a chrX heterozygosity rate"
        ];
        VerificationTest[
            ImportVCF[realVCF]["Subject", "Sex"] === sexReal["KaryotypeCall"],
            True,
            TestID -> "A computed ChromosomalSex is persisted into the Subject slot of a freshly imported HumanGenome"
        ];
        VerificationTest[
            ChromosomalSex[ImportVCF[realVCF]] === sexReal,
            True,
            TestID -> "A second ChromosomalSex call is a fast sidecar cache hit"
        ]
    ];
    (* --- HaplogroupCall on the real genome (guarded on the prepared references) --- *)
    haploTreeReal = FileNameJoin[{DirectoryName[realVCF], "references", "haplogroup", "phylotree17_tree.xml"}];
    isoggMarkersReal = FileNameJoin[{DirectoryName[realVCF], "references", "haplogroup", "isogg_ysnp_GRCh37.tsv"}];
    If[ FileExistsQ[haploTreeReal] && tabixToolsAvailable,
        mtRealHg = HaplogroupCall[ImportVCF[realVCF], "mtDNA"];
        mtRealDetail = mtRealHg["Haplogroups"]["mtDNA"];
        VerificationTest[
            HumanGenomeQ[mtRealHg] && StringQ[mtRealDetail["Haplogroup"]]
                && StringLength[mtRealDetail["Haplogroup"]] > 0,
            True,
            TestID -> "HaplogroupCall mtDNA on the real genome returns a non-empty haplogroup label"
        ];
        VerificationTest[
            NumericQ[mtRealDetail["Quality"]] && 0 <= mtRealDetail["Quality"] <= 1,
            True,
            TestID -> "Real mtDNA haplogroup quality is a number in [0, 1]"
        ];
        VerificationTest[
            HaplogroupCall[mtRealHg, "mtDNA"] === mtRealHg,
            True,
            TestID -> "A second mtDNA HaplogroupCall is a fast in-memory cache hit"
        ]
    ];
    If[ FileExistsQ[isoggMarkersReal] && tabixToolsAvailable,
        yRealHg = HaplogroupCall[ImportVCF[realVCF], "Y"];
        yRealSlot = yRealHg["Haplogroups"]["Y"];
        VerificationTest[
            yRealSlot === Missing["NoYChromosome"]
                || (AssociationQ[yRealSlot] && StringQ[yRealSlot["Haplogroup"]]
                    && StringLength[yRealSlot["Haplogroup"]] > 0),
            True,
            TestID -> "HaplogroupCall Y on the real genome returns a label or Missing[\"NoYChromosome\"]"
        ]
    ];
    (* --- AncestryEstimate on the real genome (guarded on the per-subject sidecar) ---
       The full compute reads the subject at tens of thousands of panel positions,
       so guard on the sidecar and hydrate it (build it once out-of-band with
       AncestryEstimate[ImportVCF[realVCF]]). *)
    ancSubjectReal = ImportVCF[realVCF]["Subject", "ID"];
    ancSidecarReal = FileNameJoin[{DirectoryName[realVCF], ancSubjectReal,
        "interpretations", "ancestry.wxf"}];
    If[ FileExistsQ[ancSidecarReal],
        ancRealHg = AncestryEstimate[ImportVCF[realVCF]];
        ancRealDetail = ancRealHg["Ancestry"];
        VerificationTest[
            HumanGenomeQ[ancRealHg]
                && MemberQ[{"AFR", "AMR", "EAS", "EUR", "SAS"}, ancRealDetail["Superpopulation"]],
            True,
            TestID -> "AncestryEstimate on the real genome returns a super-population in the five codes"
        ];
        VerificationTest[
            Abs[Total[Values[ancRealDetail["SuperpopulationFractions"]]] - 1] < 0.01,
            True,
            TestID -> "Real AncestryEstimate super-population fractions sum to ~1"
        ];
        VerificationTest[
            IntegerQ[ancRealDetail["NMarkersUsed"]] && ancRealDetail["NMarkersUsed"] > 0
                && Sort[Keys[ancRealDetail["SuperpopulationFractions"]]] === {"AFR", "AMR", "EAS", "EUR", "SAS"},
            True,
            TestID -> "Real AncestryEstimate used a positive marker count and reports all five super-populations"
        ];
        VerificationTest[
            StringQ[ancRealHg["References", "ThousandGenomesPanel"]],
            True,
            TestID -> "Real AncestryEstimate records the 1000 Genomes panel version string"
        ];
        VerificationTest[
            AncestryEstimate[ancRealHg] === ancRealHg,
            True,
            TestID -> "A second AncestryEstimate call is a fast in-memory cache hit"
        ]
    ];
    (* --- GenomeReport on the real genome (cached; hydrates whatever sidecars exist) ---
       Cached mode never triggers a recompute or a download, so this is fast; it
       does not force "Compute" -> "All". *)
    reportReal = GenomeReport[ImportVCF[realVCF], "Compute" -> "Cached"];
    VerificationTest[
        {Head[reportReal], reportReal["Overview", "Subject"], reportReal["Overview", "Build"],
         MatchQ[reportReal["Overview", "Sex"], _String | _Missing]},
        {Association, realSample, "GRCh37/hg19", True},
        TestID -> "GenomeReport on the real genome populates the Overview (subject, sex, build)"
    ];
    VerificationTest[
        StringQ[reportReal["ReportFile"]] && FileExistsQ[reportReal["ReportFile"]],
        True,
        TestID -> "GenomeReport on the real genome writes the rendered report file"
    ]
]

(* === genealogy: GEDCOM, FamilyTree, FamilyTreePlot, GenealogySearch ===
   Hermetic throughout.  The fixture is a synthetic three-generation GEDCOM
   written into $TemporaryDirectory, with obviously fabricated names: this
   suite ships inside the published paclet, so it must not carry anyone's real
   pedigree, and a family tree is identifying in a way a variant row is not.
   No test here touches the network: the open providers are exercised only
   when GENOME_NETWORK_TESTS is set, and the link providers build their URL
   offline by construction. *)

demoGedcomText = StringJoin[Riffle[{
    "0 HEAD",
    "1 SOUR DEMO",
    "1 GEDC",
    "2 VERS 5.5.1",
    "1 CHAR UTF-8",
    "0 @I1@ INDI",
    "1 NAME John /Doe/",
    "2 GIVN John",
    "2 SURN Doe",
    "1 SEX M",
    "1 BIRT",
    "2 DATE 12 MAR 1900",
    "1 DEAT",
    "2 DATE 1975",
    "1 FAMS @F1@",
    "0 @I2@ INDI",
    "1 NAME Jane /Roe/",
    "2 GIVN Jane",
    "2 SURN Roe",
    "2 _MARNM Doe",
    "1 SEX F",
    "1 BIRT",
    "2 DATE 1902",
    "1 FAMS @F1@",
    "0 @I3@ INDI",
    "1 NAME Richard Q /Doe/",
    "2 GIVN Richard",
    "2 _MIDN Q",
    "2 SURN Doe",
    "1 SEX M",
    "1 BIRT",
    "2 DATE JUL 1930",
    "1 FAMC @F1@",
    "1 FAMS @F2@",
    "0 @I4@ INDI",
    "1 NAME Mary /Poe/",
    "2 GIVN Mary",
    "2 SURN Poe",
    "1 SEX F",
    "1 BIRT",
    "2 DATE 1932",
    "1 FAMS @F2@",
    "0 @I5@ INDI",
    "1 NAME Sam /Doe/",
    "2 GIVN Sam",
    "2 SURN Doe",
    "1 SEX M",
    "1 BIRT",
    "2 DATE 05 FEB 1960",
    "1 FAMC @F2@",
    "0 @I6@ INDI",
    "1 NAME Ann /Doe/",
    "2 GIVN Ann",
    "2 SURN Doe",
    "1 SEX F",
    "1 BIRT",
    "2 DATE 1962",
    "1 FAMC @F2@",
    "0 @F1@ FAM",
    "1 HUSB @I1@",
    "1 WIFE @I2@",
    "1 CHIL @I3@",
    "0 @F2@ FAM",
    "1 HUSB @I3@",
    "1 WIFE @I4@",
    "1 CHIL @I5@",
    "1 CHIL @I6@",
    "0 TRLR"
}, "\n"]];

demoGedcomPath = FileNameJoin[{$TemporaryDirectory, "wlgenome_demo_tree.ged"}];
Export[demoGedcomPath, demoGedcomText, "Text"];
demoTree = ImportGEDCOM[demoGedcomPath];

(* The same pedigree with one impossible date: Sam is born five years after
   his father, which is what the consistency pass has to catch. *)
brokenGedcomPath = FileNameJoin[{$TemporaryDirectory, "wlgenome_broken_tree.ged"}];
Export[brokenGedcomPath, StringReplace[demoGedcomText, "2 DATE 05 FEB 1960" -> "2 DATE 05 FEB 1935"], "Text"];
brokenTree = ImportGEDCOM[brokenGedcomPath];

VerificationTest[
    {Head[demoTree], FamilyTreeQ[demoTree], demoTree["PersonCount"], demoTree["FamilyCount"]},
    {FamilyTree, True, 6, 2},
    TestID -> "ImportGEDCOM parses the demo pedigree into a FamilyTree"
]

VerificationTest[
    {FamilyTreeQ[FamilyTree[<|"People" -> <||>|>]], FamilyTreeQ["not a tree"]},
    {False, False},
    TestID -> "FamilyTreeQ rejects an incomplete payload and a non-FamilyTree"
]

VerificationTest[
    ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "wlgenome_no_such_file.ged"}]],
    $Failed,
    {ImportGEDCOM::nofile},
    TestID -> "ImportGEDCOM reports a missing file"
]

VerificationTest[
    demoTree["Header"],
    <|"Path" -> demoGedcomPath, "Source" -> "DEMO", "SourceName" -> Missing["NotAvailable"],
      "Encoding" -> "UTF-8", "GEDCOMVersion" -> "5.5.1", "Submitter" -> Missing["NotAvailable"]|>,
    TestID -> "ImportGEDCOM reads the GEDCOM header fields"
]

VerificationTest[
    Lookup[demoTree["Person", "I3"], {"Name", "GivenName", "MiddleName", "Surname", "Sex"}],
    {"Richard Q Doe", "Richard", "Q", "Doe", "Male"},
    TestID -> "A person record keeps the patronymic / middle name sub-tag"
]

VerificationTest[
    demoTree["Person", "I2"]["MarriedName"],
    "Doe",
    TestID -> "A married surname survives the parse"
]

(* Granularity is a promise of the reader: a year-only GEDCOM date must not
   silently acquire a January 1st that later reads as evidence. *)
VerificationTest[
    {
        demoTree["Person", "I1"]["BirthDate"],
        demoTree["Person", "I3"]["BirthDate"],
        demoTree["Person", "I2"]["BirthDate"],
        demoTree["Person", "I2"]["BirthDateText"]
    },
    {
        DateObject[{1900, 3, 12}, "Day"],
        DateObject[{1930, 7}, "Month"],
        DateObject[{1902}, "Year"],
        "1902"
    },
    TestID -> "GEDCOM dates parse at the granularity the record states"
]

VerificationTest[
    {demoTree["Person", "I1"]["Deceased"], demoTree["Person", "I5"]["Deceased"]},
    {True, False},
    TestID -> "A DEAT record marks a person deceased"
]

VerificationTest[
    demoTree["YearRange"],
    {1900, 1975},
    TestID -> "FamilyTree reports the year span of its dated records"
]

VerificationTest[
    demoTree["GenerationCount"],
    3,
    TestID -> "FamilyTree counts generations from the deepest known parent"
]

VerificationTest[
    {
        Normal[demoTree["Parents", "I5"]][[All, "ID"]],
        Normal[demoTree["Children", "I3"]][[All, "ID"]],
        Normal[demoTree["Siblings", "I5"]][[All, "ID"]],
        Normal[demoTree["Spouses", "I1"]][[All, "ID"]]
    },
    {{"I3", "I4"}, {"I5", "I6"}, {"I6"}, {"I2"}},
    TestID -> "Kinship walks return the immediate relatives"
]

VerificationTest[
    {
        Sort[Normal[demoTree["Ancestors", "I5"]][[All, "ID"]]],
        Sort[Normal[demoTree["Descendants", "I1"]][[All, "ID"]]],
        Sort[Normal[demoTree["Ancestors", "I5", 1]][[All, "ID"]]]
    },
    {{"I1", "I2", "I3", "I4"}, {"I3", "I5", "I6"}, {"I3", "I4"}},
    TestID -> "Ancestor and descendant closures respect the generation limit"
]

VerificationTest[
    {
        demoTree["Relationship", "I5", "I1"],
        demoTree["Relationship", "I1", "I5"],
        demoTree["Relationship", "I5", "I6"],
        demoTree["Relationship", "I1", "I2"],
        demoTree["Relationship", "I5", "I5"]
    },
    {"paternal grandfather", "grandson", "sister", "wife", "self"},
    TestID -> "Relationship names the kinship in both directions"
]

VerificationTest[
    demoTree["Person", "Richard"]["ID"],
    "I3",
    TestID -> "A person resolves from a name fragment as well as a record key"
]

VerificationTest[
    Length[demoTree["Find", "Doe"]],
    5,
    TestID -> "Find matches on birth and married surnames"
]

VerificationTest[
    Length[demoTree["Issues"]],
    0,
    TestID -> "A consistent pedigree reports no issues"
]

(* Both parents are flagged, not just one: a birth five years after the
   father's is also three years after the mother's. *)
VerificationTest[
    Block[{rows = Normal[brokenTree["Issues"]]},
        {Length[rows], DeleteDuplicates[rows[[All, "Severity"]]], DeleteDuplicates[rows[[All, "Issue"]]]}
    ],
    {2, {"Error"}, {"Parent too young"}},
    TestID -> "The consistency pass catches a child born before its parent could have one"
]

VerificationTest[
    Block[{g = FamilyTreePlot[demoTree]},
        {Head[g], VertexCount[g], EdgeCount[g]}
    ],
    {Graph, 8, 7},
    TestID -> "FamilyTreePlot draws a person per individual and a node per family union"
]

(* The pedigree of I5 is I5, the four ancestors, the sibling beside I5, and
   the two unions: siblings hang beside their ancestor, so the count is one
   more than the ancestor closure. *)
VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Root" -> "I5"]},
        {Head[g], VertexCount[g]}
    ],
    {Graph, 8},
    TestID -> "A pedigree covers the root, its ancestors, their siblings and the unions"
]

VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Layout" -> "Layered"]},
        {Head[g], VertexCount[g], EdgeCount[g]}
    ],
    {Graph, 8, 7},
    TestID -> "The layered layout draws everybody in the file"
]

(* A caller's own embedding is scaled so the fixed-size cards fit on it;
   the first version drew every card a hundred times the graph. *)
VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, GraphLayout -> "SpringElectricalEmbedding"], size},
        size = OptionValue[Graph, Options[g], ImageSize];
        {Head[g], VertexCount[g], AllTrue[size, 100 <= # <= 6000 &]}
    ],
    {Graph, 8, True},
    TestID -> "An explicit GraphLayout is rescaled to card-sized coordinates"
]

(* A rendered plot travels with its options, so the drawing must not close
   over the pedigree: only the labels the picture already shows may appear. *)
VerificationTest[
    Block[{g = FamilyTreePlot[demoTree], text},
        text = ToString[Options[g], InputForm];
        {StringContainsQ[text, "Poe"], StringContainsQ[text, "ParentFamilies"], StringContainsQ[text, demoGedcomPath]}
    ],
    {True, False, False},
    TestID -> "A FamilyTreePlot carries the drawn labels but not the tree payload"
]

(* "Labels" names the lines a card carries, so every combination is
   expressible and a component the record cannot fill is simply absent. *)
VerificationTest[
    Block[{r = WolframInstitute`Genome`Private`resolveLabels},
        {
            Quiet @ r[Automatic, {"Name", "Relationship"}, False],
            Quiet @ r[All, {"Name", "Relationship"}, False],
            Quiet @ r[None, {"Name", "Relationship"}, False],
            Quiet @ r["Years", {"Name", "Relationship"}, False],
            Quiet @ r[{"Relationship", "Dates"}, {"Name", "Relationship"}, False],
            Quiet @ r["NameYears", {"Name", "Relationship"}, False],
            Quiet @ r[Automatic, {"Name", "Relationship"}, True]
        }
    ],
    {
        {"Name", "Relationship"}, {"Name", "Relationship", "Dates"}, {},
        {"Years"}, {"Relationship", "Dates"}, {"Name", "Years"}, {"Name"}
    },
    TestID -> "Every label combination resolves, including a bare component and the legacy names"
]

(* The reported bug: an unrecognised name fell through and left the card with
   nothing but a name, silently. *)
VerificationTest[
    WolframInstitute`Genome`Private`resolveLabels["Yers", {"Name", "Relationship"}, False],
    {"Name", "Relationship"},
    {FamilyTreePlot::badlabels},
    TestID -> "An unrecognised label specification says so and falls back"
]

VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Root" -> "I5", "Labels" -> All], text},
        text = ToString[Options[g], InputForm];
        {Head[g], StringContainsQ[text, "grandfather"], StringContainsQ[text, "12.03.1900 - 1975"]}
    ],
    {Graph, True, True},
    TestID -> "Labels -> All carries the relationship and the full dates"
]

(* With no root there is no relationship to show, and the line is dropped
   rather than left blank. *)
VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Layout" -> "Layered", "Labels" -> All], text},
        text = ToString[Options[g], InputForm];
        {StringContainsQ[text, "12.03.1900 - 1975"], StringContainsQ[text, "grandfather"]}
    ],
    {True, False},
    TestID -> "A label component the drawing cannot fill leaves no blank line"
]

VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Root" -> "I5", "Labels" -> {"Name", "Years"}], text},
        text = ToString[Options[g], InputForm];
        {StringContainsQ[text, "1900-1975"], StringContainsQ[text, "grandfather"], StringContainsQ[text, "John Doe"]}
    ],
    {True, False, True},
    TestID -> "Years is the compact form and Dates the full one"
]

VerificationTest[
    FamilyTreePlot["not a tree"],
    $Failed,
    {FamilyTreePlot::notTree},
    TestID -> "FamilyTreePlot rejects a non-FamilyTree"
]

VerificationTest[
    Block[{built},
        built = FamilyTree[{
            <|"ID" -> "a", "Name" -> "A Root", "Sex" -> "Male"|>,
            <|"ID" -> "b", "Name" -> "B Root", "Sex" -> "Female"|>,
            <|"ID" -> "c", "Name" -> "C Child", "Sex" -> "Female", "Father" -> "a", "Mother" -> "b"|>
        }];
        {FamilyTreeQ[built], built["PersonCount"], built["FamilyCount"],
         Normal[built["Parents", "c"]][[All, "ID"]], built["Relationship", "c", "a"]}
    ],
    {True, 3, 1, {"a", "b"}, "father"},
    TestID -> "FamilyTree builds a tree from plain person Associations"
]

VerificationTest[
    Length[demoTree],
    6,
    TestID -> "Length of a FamilyTree is its person count"
]

(* === GenealogySearch (offline paths) === *)

VerificationTest[
    Block[{t = GenealogySearch["Providers"], rows},
        rows = Normal[t];
        {
            Head[t],
            Length[rows],
            Sort[DeleteDuplicates[rows[[All, "Class"]]]],
            Sort[Select[rows, #["Class"] === "Open" &][[All, "Provider"]]]
        }
    ],
    {Tabular, 10, {"Browser", "Credential", "Open"},
     {"OpenArchives", "OpenList", "PermGenerations", "Wikidata", "WikiTree"}},
    TestID -> "GenealogySearch tabulates its providers by class"
]

VerificationTest[
    Block[{rows = Normal @ GenealogySearch[
        <|"Surname" -> "Doe", "GivenName" -> "John", "BirthYear" -> 1900|>,
        "Providers" -> "FindAGrave", "Browser" -> False
    ]},
        {
            Length[rows],
            rows[[1, "Provider"]],
            StringContainsQ[rows[[1, "URL"]], "findagrave.com"],
            StringContainsQ[rows[[1, "URL"]], "lastname=Doe"],
            StringContainsQ[rows[[1, "URL"]], "birthyear=1900"]
        }
    ],
    {1, "FindAGrave", True, True, True},
    TestID -> "A link provider builds its deep search URL offline"
]

VerificationTest[
    Block[{rows = Normal @ GenealogySearch[demoTree, "I1", "Providers" -> "PamyatNaroda", "Browser" -> False]},
        {Length[rows], rows[[1, "Birth"]], StringContainsQ[rows[[1, "URL"]], "last_name=Doe"]}
    ],
    {1, 1900, True},
    TestID -> "GenealogySearch builds its query from a FamilyTree person record"
]

VerificationTest[
    Length @ GenealogySearch["John Doe", "Providers" -> {"FamilySearch", "Geni"}],
    0,
    TestID -> "Credential providers stay silent with no token configured"
]

VerificationTest[
    Block[{t = GenealogySearch["Nobody Whatsoever Unfindable", "Providers" -> "FindAGrave", "MaxResults" -> 1, "Browser" -> False]},
        Head[t]
    ],
    Tabular,
    TestID -> "GenealogySearch always returns a Tabular"
]

VerificationTest[
    GenealogySearch[42],
    $Failed,
    {GenealogySearch::badquery},
    TestID -> "GenealogySearch rejects a query it cannot build from"
]

(* === the browser-class provider layer ===
   These stay offline: "Browser" -> False keeps the class in link mode, which is
   also what the documentation build and any machine without Node need.  The
   runner itself is checked for existence, not executed. *)

VerificationTest[
    Block[{rows = Normal @ GenealogySearch[
        <|"Surname" -> "Doe", "GivenName" -> "John"|>,
        "Providers" -> {"PamyatNaroda", "YandexArchive", "FindAGrave"},
        "Browser" -> False
    ]},
        {Length[rows], rows[[All, "Provider"]], AllTrue[rows[[All, "URL"]], StringQ]}
    ],
    {3, {"PamyatNaroda", "YandexArchive", "FindAGrave"}, True},
    TestID -> "Browser providers fall back to a search link when the browser is switched off"
]

VerificationTest[
    FileExistsQ @ FileNameJoin[{
        PacletObject["WolframInstitute/Genome"]["Location"], "Assets", "genealogy-browser.mjs"
    }],
    True,
    TestID -> "The paclet ships the Playwright runner the browser providers drive"
]

VerificationTest[
    GenealogyLogin["WikiTree"],
    $Failed,
    {GenealogyLogin::provider},
    TestID -> "GenealogyLogin refuses a provider that has no browser session"
]

VerificationTest[
    GenealogyLogin[42],
    $Failed,
    {GenealogyLogin::provider},
    TestID -> "GenealogyLogin refuses a non-provider argument"
]

(* === kinship vocabulary and transliteration ===
   The demo pedigree names every shape the vocabulary has to reach, and the
   two systems it has to keep apart: English counts cousin degree and
   removal, Russian names the generation and marks the collateral distance on
   it, so a grandparent's sibling is a great-aunt in one and a
   \:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:0430\:044f \:0431\:0430\:0431\:0443\:0448\:043a\:0430 in the other. *)

VerificationTest[
    Table[demoTree["Relationship", "I5", "I1", lang], {lang, {"English", "Russian", "Spanish", "German"}}],
    {"paternal grandfather", "\:0434\:0435\:0434\:0443\:0448\:043a\:0430 \:043f\:043e \:043e\:0442\:0446\:0443", "abuelo paterno", "Gro\:00dfvater v\:00e4terlicherseits"},
    TestID -> "A grandfather is named, and his line, in every language"
]

VerificationTest[
    {demoTree["Relationship", "I5", "I4", "English"], demoTree["Relationship", "I5", "I4", "Russian"]},
    {"mother", "\:043c\:0430\:0442\:044c"},
    TestID -> "A parent takes no line qualifier"
]

(* The two systems disagree here on purpose, and both are right. *)
VerificationTest[
    {
        WolframInstitute`Genome`Private`kinCollateral["English", 1, -2, "Female"],
        WolframInstitute`Genome`Private`kinCollateral["Russian", 1, -2, "Female"],
        WolframInstitute`Genome`Private`kinCollateral["Spanish", 1, -2, "Female"],
        WolframInstitute`Genome`Private`kinCollateral["German", 1, -2, "Male"]
    },
    {"great-aunt", "\:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:0430\:044f \:0431\:0430\:0431\:0443\:0448\:043a\:0430", "t\:00eda abuela", "Gro\:00dfonkel"},
    TestID -> "A grandparent's sibling compounds a new word outside Russian and marks the old one inside it"
]

VerificationTest[
    {
        WolframInstitute`Genome`Private`kinCollateral["English", 2, 0, "Male"],
        WolframInstitute`Genome`Private`kinCollateral["English", 2, -1, "Male"],
        WolframInstitute`Genome`Private`kinCollateral["Russian", 2, 0, "Male"],
        WolframInstitute`Genome`Private`kinCollateral["Russian", 2, -1, "Male"],
        WolframInstitute`Genome`Private`kinCollateral["Spanish", 2, 0, "Male"],
        WolframInstitute`Genome`Private`kinCollateral["Spanish", 2, -1, "Male"]
    },
    {"first cousin", "first cousin once removed", "\:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:044b\:0439 \:0431\:0440\:0430\:0442", "\:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:044b\:0439 \:0434\:044f\:0434\:044f", "primo hermano", "t\:00edo segundo"},
    TestID -> "A first cousin and a parent's first cousin, in three systems"
]

(* Russian keeps a word for every in-law position, which is the reason to
   name them at all: a wife's father and a husband's father are never the
   same word. *)
VerificationTest[
    {
        WolframInstitute`Genome`Private`kinInLaw["Russian", "Parent", "Male", "Female"],
        WolframInstitute`Genome`Private`kinInLaw["Russian", "Parent", "Male", "Male"],
        WolframInstitute`Genome`Private`kinInLaw["Russian", "Sibling", "Male", "Female"],
        WolframInstitute`Genome`Private`kinInLaw["Russian", "Sibling", "Male", "Male"],
        WolframInstitute`Genome`Private`kinInLaw["English", "Parent", "Male", "Female"]
    },
    {"\:0442\:0435\:0441\:0442\:044c", "\:0441\:0432\:0451\:043a\:043e\:0440", "\:0448\:0443\:0440\:0438\:043d", "\:0434\:0435\:0432\:0435\:0440\:044c", "father-in-law"},
    TestID -> "The Russian in-law vocabulary distinguishes the side the marriage runs through"
]

VerificationTest[
    Table[WolframInstitute`Genome`Private`kinAncestor["German", n, "Male"], {n, 2, 4}],
    {"Gro\:00dfvater", "Urgro\:00dfvater", "Ururgro\:00dfvater"},
    TestID -> "German compounds capitalize only once"
]

VerificationTest[
    demoTree["Relationship", "I5", "I1", "Klingon"],
    "paternal grandfather",
    {FamilyTree::badlang},
    TestID -> "An unsupported language falls back to English with a message"
]

VerificationTest[
    Block[{rows = Normal @ demoTree["Relationships", "I5", "Russian"]},
        {Length[rows], Sort[rows[[All, "Relationship"]]] === Sort[rows[[All, "Relationship"]]], MemberQ[rows[[All, "Relationship"]], "\:0434\:0435\:0434\:0443\:0448\:043a\:0430 \:043f\:043e \:043e\:0442\:0446\:0443"]}
    ],
    {5, True, True},
    TestID -> "Relationships names everyone else in the tree at once"
]

(* Transliteration is a display choice, and the built-in one is unusable for
   this: it maps by stripping diacritics, so the \:0448, \:0436 and \:044e distinctions vanish. *)
VerificationTest[
    Table[WolframInstitute`Genome`Private`transliterateName[n, "BGN"],
        {n, {"\:0410\:043d\:0434\:0440\:0435\:0439", "\:0429\:0435\:0440\:0431\:0430\:043a\:043e\:0432", "\:042e\:0440\:0438\:0439", "\:0421\:0435\:043c\:0451\:043d", "\:0418\:0433\:043e\:0440\:044c"}}],
    {"Andrey", "Shcherbakov", "Yuriy", "Semyon", "Igor"},
    TestID -> "BGN transliteration keeps the sounds a search needs"
]

VerificationTest[
    Table[WolframInstitute`Genome`Private`transliterateName[n, "Passport"],
        {n, {"\:0410\:043d\:0434\:0440\:0435\:0439", "\:042e\:0440\:0438\:0439", "\:0421\:0435\:043c\:0451\:043d"}}],
    {"Andrei", "Iurii", "Semen"},
    TestID -> "Passport transliteration matches the spelling on a modern document"
]

VerificationTest[
    WolframInstitute`Genome`Private`transliterateName["\:0421\:0418\:0414\:041e\:0420\:041e\:0412", "BGN"],
    "SIDOROV",
    TestID -> "A surname written in capitals stays in capitals"
]

VerificationTest[
    {
        WolframInstitute`Genome`Private`applyTransliteration["\:0410\:043d\:0434\:0440\:0435\:0439", None],
        Quiet @ WolframInstitute`Genome`Private`resolveTransliteration["Nonsense"],
        WolframInstitute`Genome`Private`resolveTransliteration[Automatic]
    },
    {"\:0410\:043d\:0434\:0440\:0435\:0439", None, "BGN"},
    TestID -> "Transliteration is off unless asked for, and an unknown scheme leaves names alone"
]

VerificationTest[
    Block[{g = FamilyTreePlot[demoTree, "Language" -> "Russian", "Transliteration" -> "BGN"], text},
        text = ToString[Options[g], InputForm];
        {Head[g], StringContainsQ[text, "Doe"], StringContainsQ[text, "\:044d\:0442\:043e \:044f"]}
    ],
    {Graph, True, True},
    TestID -> "A plot carries its labels in the chosen language and script"
]

(* Two people related only by marriage, and a third related to nobody: the
   affinal probe walks through spouses, and before the blood half was split
   out it walked back through the same marriage and asked the same question
   forever.  The doc harness found it; this pins it. *)
VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_affinal.csv"}], tree},
        Export[path, StringJoin[Riffle[{
            "ID;Surname;GivenName;MiddleName;MaidenName;Sex;BirthDate;BirthPlace;DeathDate;DeathPlace;Status;Father;Mother;Spouse;Children",
            "A1;Doe;Adam;;;M;1900;;;;;;;Doe Eve;",
            "A2;Doe;Eve;;;F;1902;;;;;;;Doe Adam;",
            "A3;Roe;Stranger;;;M;1905;;;;;;;;"
        }, "\n"]], "Text"];
        tree = ImportFamilyTable[path];
        TimeConstrained[
            {tree["Relationship", "A1", "A3"], tree["Relationship", "A1", "A2"], tree["Relationship", "A3", "A1"]},
            30,
            $TimedOut
        ]
    ],
    {"unrelated", "wife", "unrelated"},
    TestID -> "A marriage the relation does not run through terminates instead of recursing"
]

(* === the family table: CSV in, CSV out, GEDCOM out ===
   The same invented family as the GEDCOM fixture, as the flat table a
   genealogy service exports beside it.  The English fixture exercises the
   delimiter sniff and a reference that names a person without the middle
   name; the Russian one exercises the Genotek layout byte for byte: a
   byte-order mark, CRLF, semicolons, the current-versus-maiden surname
   columns, and a quoted children cell holding the delimiter. *)

demoTableText = StringJoin[Riffle[{
    "ID;Surname;GivenName;MiddleName;MaidenName;Sex;BirthDate;BirthPlace;DeathDate;DeathPlace;Status;Father;Mother;Spouse;Children",
    "I1;Doe;John;;;M;12.03.1900;;1975;;deceased;;;Doe Jane;Doe Richard Q",
    "I2;Doe;Jane;;Roe;F;1902;;;;;;;Doe John;Doe Richard Q",
    "I3;Doe;Richard;Q;;M;07.1930;;;;;Doe John;Doe Jane;Poe Mary;\"Doe Sam; Doe Ann\"",
    "I4;Poe;Mary;;;F;1932;;;;;;;Doe Richard Q;\"Doe Sam; Doe Ann\"",
    "I5;Doe;Sam;;;M;05.02.1960;;;;;Doe Richard;Poe Mary;;",
    "I6;Doe;Ann;;;F;1962;;;;;Doe Richard Q;Poe Mary;;"
}, "\n"]];
demoTablePath = FileNameJoin[{$TemporaryDirectory, "wlgenome_demo_table.csv"}];
Export[demoTablePath, demoTableText, "Text"];
demoTable = ImportFamilyTable[demoTablePath];

VerificationTest[
    {Head[demoTable], FamilyTreeQ[demoTable], demoTable["PersonCount"], demoTable["FamilyCount"]},
    {FamilyTree, True, 6, 2},
    TestID -> "ImportFamilyTable reads the demo table into a FamilyTree"
]

VerificationTest[
    {
        Normal[demoTable["Parents", "I5"]][[All, "ID"]],
        Normal[demoTable["Children", "I1"]][[All, "ID"]],
        Normal[demoTable["Spouses", "I3"]][[All, "ID"]],
        demoTable["Relationship", "I5", "I1"]
    },
    {{"I3", "I4"}, {"I3"}, {"I4"}, "paternal grandfather"},
    TestID -> "A table's father, mother, spouse and children cells rebuild the families"
]

(* The table's surname column is the current name; a maiden name beside it
   is the birth surname GEDCOM calls SURN. *)
VerificationTest[
    Lookup[demoTable["Person", "I2"], {"Surname", "MarriedName"}],
    {"Roe", "Doe"},
    TestID -> "A maiden-name column becomes the birth surname, the surname column the married name"
]

VerificationTest[
    {
        demoTable["Person", "I1"]["BirthDate"],
        demoTable["Person", "I3"]["BirthDate"],
        demoTable["Person", "I2"]["BirthDate"],
        demoTable["Person", "I1"]["BirthDateText"]
    },
    {DateObject[{1900, 3, 12}, "Day"], DateObject[{1930, 7}, "Month"], DateObject[{1902}, "Year"], "12 MAR 1900"},
    TestID -> "Table dates parse at the granularity the cell states"
]

VerificationTest[
    {demoTable["Person", "I1"]["Deceased"], demoTable["Person", "I3"]["Deceased"]},
    {True, False},
    TestID -> "A status word or a death date marks a person deceased"
]

(* Genotek layout: BOM, CRLF, Russian headers, a quoted children cell. *)
VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_demo_table_ru.csv"}], tree},
        Export[path,
            "\:feff" <> StringJoin[Riffle[{
                "ID;\:0424\:0430\:043c\:0438\:043b\:0438\:044f;\:0418\:043c\:044f;\:041e\:0442\:0447\:0435\:0441\:0442\:0432\:043e;\:0414\:0435\:0432\:0438\:0447\:044c\:044f \:0444\:0430\:043c\:0438\:043b\:0438\:044f;\:041f\:043e\:043b;\:0414\:0430\:0442\:0430 \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f;\:041c\:0435\:0441\:0442\:043e \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f;\:0414\:0430\:0442\:0430 \:0441\:043c\:0435\:0440\:0442\:0438;\:041c\:0435\:0441\:0442\:043e \:0441\:043c\:0435\:0440\:0442\:0438;\:0421\:0442\:0430\:0442\:0443\:0441;\:041e\:0442\:0435\:0446;\:041c\:0430\:0442\:044c;\:0421\:0443\:043f\:0440\:0443\:0433(\:0430);\:0414\:0435\:0442\:0438",
                "I1;Doe;John;;;\:043c;12.03.1900;;1975;;\:0443\:043c\:0435\:0440(\:043b\:0430);;;Doe Jane;Doe Richard Q",
                "I2;Doe;Jane;;Roe;\:0436;1902;;;;;;;Doe John;Doe Richard Q",
                "I3;Doe;Richard;Q;;\:043c;07.1930;;;;;Doe John;Doe Jane;;\"Doe Sam; Doe Ann\"",
                "I5;Doe;Sam;;;\:043c;05.02.1960;;;;;Doe Richard Q;;;",
                "I6;Doe;Ann;;;\:0436;1962;;;;;Doe Richard Q;;;"
            }, "\r\n"]] <> "\r\n",
            "Text", CharacterEncoding -> "UTF-8"];
        tree = ImportFamilyTable[path];
        {tree["PersonCount"], tree["FamilyCount"], Normal[tree["Children", "I3"]][[All, "ID"]], tree["Person", "I1"]["Deceased"], tree["Person", "I2"]["MarriedName"]}
    ],
    {5, 2, {"I5", "I6"}, True, "Doe"},
    TestID -> "The Genotek table layout reads: BOM, CRLF, Russian headers, quoted children"
]

(* The collision a real export produces: a grandfather and a grandson share
   surname and given name, the grandson has a patronymic in his own row but
   is named without it in his parents' children cells.  The reference must
   go to the grandson, whose row names those parents back. *)
VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_collision.csv"}], tree},
        Export[path, StringJoin[Riffle[{
            "ID;Surname;GivenName;MiddleName;MaidenName;Sex;BirthDate;BirthPlace;DeathDate;DeathPlace;Status;Father;Mother;Spouse;Children",
            "I1;Doe;John;Adam;;M;1930;;;;;;;Doe Mary;Doe Peter John",
            "I2;Doe;Mary;;;F;1932;;;;;;;Doe John Adam;Doe Peter John",
            "I3;Doe;Peter;John;;M;1960;;;;;Doe John Adam;Doe Mary;Doe Anna;\"Doe John\"",
            "I4;Doe;Anna;;;F;1962;;;;;;;Doe Peter John;\"Doe John\"",
            "I5;Doe;John;Peter;;M;1988;;;;;Doe Peter John;Doe Anna;;"
        }, "\n"]], "Text"];
        tree = Quiet @ ImportFamilyTable[path];
        {Normal[tree["Children", "I3"]][[All, "ID"]], Normal[tree["Parents", "I5"]][[All, "ID"]], Normal[tree["Parents", "I1"]][[All, "ID"]]}
    ],
    {{"I5"}, {"I3", "I4"}, {}},
    TestID -> "A short child reference shared by a grandfather and a grandson goes to the one who names those parents back"
]

VerificationTest[
    ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "wlgenome_no_such_table.csv"}]],
    $Failed,
    {ImportFamilyTable::nofile},
    TestID -> "ImportFamilyTable reports a missing file"
]

(* Round trips.  A tree written as a table and read back has the same
   people and links; written as GEDCOM and read back it has the same
   records, key for key. *)
tableLinks[ft_] := Block[{a = First[ft]}, AssociationMap[
    id |-> {
        Sort @ WolframInstitute`Genome`Private`parentIDs[a, id],
        Sort @ WolframInstitute`Genome`Private`childIDs[a, id],
        Sort @ WolframInstitute`Genome`Private`spouseIDs[a, id],
        Lookup[a["People"][id], {"GivenName", "Surname", "MarriedName", "Sex", "BirthDate", "DeathDate", "Deceased"}]
    },
    Keys[a["People"]]
]];

VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_roundtrip.csv"}], back},
        ExportFamilyTable[path, demoTree];
        back = ImportFamilyTable[path];
        {FileExistsQ[path], tableLinks[back] === tableLinks[demoTree]}
    ],
    {True, True},
    TestID -> "A tree written as a table and read back keeps its people and links"
]

VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_roundtrip.ged"}], back},
        ExportGEDCOM[path, demoTree];
        back = ImportGEDCOM[path];
        {Normal[back]["People"] === Normal[demoTree]["People"], Normal[back]["Families"] === Normal[demoTree]["Families"]}
    ],
    {True, True},
    TestID -> "A tree written as GEDCOM and read back reproduces its records key for key"
]

VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_roundtrip2.ged"}], back},
        ExportGEDCOM[path, demoTable];
        back = ImportGEDCOM[path];
        {back["PersonCount"], back["FamilyCount"], tableLinks[back] === tableLinks[demoTable]}
    ],
    {6, 2, True},
    TestID -> "A table converts to GEDCOM and back without losing a link"
]

VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_english.csv"}], lines},
        ExportFamilyTable[path, demoTree, "Headers" -> "English", "ByteOrderMark" -> False];
        lines = Import[path, "Lines"];
        {First[lines], lines[[2]]}
    ],
    {
        "ID;Surname;GivenName;MiddleName;MaidenName;Sex;BirthDate;BirthPlace;DeathDate;DeathPlace;Status;Father;Mother;Spouse;Children",
        "I1;Doe;John;;;M;12.03.1900;;1975;;deceased;;;Doe Jane;Doe Richard Q"
    },
    TestID -> "ExportFamilyTable writes the table layout with the current surname and named links"
]

VerificationTest[
    {ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "x.ged"}], "not a tree"], ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "x.csv"}], 42]},
    {$Failed, $Failed},
    {ExportGEDCOM::notTree, ExportFamilyTable::notTree},
    TestID -> "The writers reject a non-FamilyTree"
]

(* === registered Import / Export formats ===
   The same readers and writers, reached through the system verbs.  Hermetic:
   the GEDCOM and table fixtures above, plus a ten-line VCF. *)

VerificationTest[
    {Sort @ Select[{"GEDCOM", "FamilyTable", "GenomeVCF"}, MemberQ[$ImportFormats, #] &],
     Sort @ Select[{"GEDCOM", "FamilyTable"}, MemberQ[$ExportFormats, #] &]},
    {{"FamilyTable", "GEDCOM", "GenomeVCF"}, {"FamilyTable", "GEDCOM"}},
    TestID -> "Loading the paclet registers the GEDCOM, FamilyTable and GenomeVCF formats"
]

VerificationTest[
    Block[{t = Import[demoGedcomPath, "GEDCOM"]},
        {FamilyTreeQ[t], t["PersonCount"], Import[demoGedcomPath, {"GEDCOM", "Elements"}]}
    ],
    {True, 6, {"Data", "Families", "Graph", "Header", "People", "Summary", "Tabular"}},
    TestID -> "Import GEDCOM gives the tree and lists its elements"
]

VerificationTest[
    {Keys @ Import[demoGedcomPath, {"GEDCOM", "People"}], Head @ Import[demoGedcomPath, {"GEDCOM", "Graph"}]},
    {{"I1", "I2", "I3", "I4", "I5", "I6"}, Graph},
    TestID -> "The GEDCOM People and Graph elements"
]

VerificationTest[
    Normal[ImportString[ExportString[demoTree, "GEDCOM"], "GEDCOM"]]["People"] === Normal[demoTree]["People"],
    True,
    TestID -> "ExportString and ImportString round-trip a tree through GEDCOM text"
]

VerificationTest[
    Block[{path = FileNameJoin[{$TemporaryDirectory, "wlgenome_format.csv"}]},
        Export[path, demoTree, "FamilyTable", "Headers" -> "English"];
        {Import[path, "FamilyTable"]["PersonCount"], Import[path, {"FamilyTable", "Elements"}]}
    ],
    {6, {"Data", "Families", "Graph", "People", "Summary", "Tabular"}},
    TestID -> "Export and Import through the FamilyTable format"
]

VerificationTest[
    Block[{vcf = FileNameJoin[{$TemporaryDirectory, "wlgenome_format.vcf"}], g},
        Export[vcf, StringJoin[Riffle[{
            "##fileformat=VCFv4.2",
            "##contig=<ID=chr1,length=249250621>",
            "#CHROM\tPOS\tID\tREF\tALT\tQUAL\tFILTER\tINFO\tFORMAT\tDEMO",
            "chr1\t100\trs1\tA\tG\t60\tPASS\tAF=0.5\tGT\t0/1",
            "chr1\t200\trs2\tC\tT\t60\tPASS\tAF=0.5\tGT\t1/1"
        }, "\n"]], "Text"];
        g = Import[vcf, "GenomeVCF", "Human" -> False];
        {GenomeQ[g], g["Build"], Import[vcf, {"GenomeVCF", "Samples"}], Length @ Import[vcf, {"GenomeVCF", "Variants"}, "Human" -> False]}
    ],
    {True, "GRCh37/hg19", {"DEMO"}, 2},
    TestID -> "Import GenomeVCF gives the lazy handle and its elements"
]

VerificationTest[
    Export[FileNameJoin[{$TemporaryDirectory, "wlgenome_x.ged"}], "not a tree", "GEDCOM"],
    $Failed,
    {ExportGEDCOM::notTree},
    TestID -> "The GEDCOM export format rejects a non-tree"
]

(* === surname spelling variants ===
   Unstressed o and a sound identical in Russian, so one family's surname
   drifts between spellings across documents.  The expansion is pure, so this
   is offline. *)

VerificationTest[
    WolframInstitute`Genome`Private`surnameSpellingVariants["\:041a\:0430\:0441\:043e\:043d\:043e\:0432"],
    {"\:041a\:0430\:0441\:043e\:043d\:043e\:0432", "\:041a\:0430\:0441\:0430\:043d\:043e\:0432", "\:041a\:043e\:0441\:0430\:043d\:043e\:0432", "\:041a\:043e\:0441\:043e\:043d\:043e\:0432"},
    TestID -> "A surname root with two o/a positions expands to four spellings"
]

VerificationTest[
    WolframInstitute`Genome`Private`surnameSpellingVariants["\:0417\:0438\:043c\:0438\:043d"],
    {"\:0417\:0438\:043c\:0438\:043d"},
    TestID -> "A surname root with no o or a expands to itself alone"
]

(* The suffix is orthographically stable, so varying it would only
   manufacture nonsense and multiply requests. *)
VerificationTest[
    AllTrue[
        WolframInstitute`Genome`Private`surnameSpellingVariants["\:0413\:043e\:0440\:0434\:0435\:0435\:0432\:0430"],
        StringEndsQ[#, "\:0435\:0432\:0430"] &
    ],
    True,
    TestID -> "Spelling variants leave the surname suffix alone"
]

VerificationTest[
    Block[{rows = Normal @ GenealogySearch[
        <|"Surname" -> "\:041a\:0430\:0441\:043e\:043d\:043e\:0432"|>,
        "Providers" -> "FindAGrave", "Browser" -> False, "Variants" -> True
    ]},
        {Length[rows], DeleteDuplicates[rows[[All, "Provider"]]]}
    ],
    {4, {"FindAGrave"}},
    TestID -> "A search runs once per spelling variant of the surname"
]

VerificationTest[
    Length @ GenealogySearch[
        <|"Surname" -> "\:041a\:0430\:0441\:043e\:043d\:043e\:0432"|>,
        "Providers" -> "FindAGrave", "Browser" -> False, "Variants" -> False
    ],
    1,
    TestID -> "Variants -> False searches only the spelling given"
]

(* Live provider calls, opt-in only: the suite must pass with no network. *)
If[ Environment["GENOME_NETWORK_TESTS"] === "1",
    VerificationTest[
        Block[{t = GenealogySearch["Samuel Clemens", "Providers" -> "WikiTree", "MaxResults" -> 3]},
            Head[t] === Tabular && Length[t] > 0
        ],
        True,
        TestID -> "WikiTree returns records for a known public profile"
    ];
    VerificationTest[
        Block[{rows = Normal @ GenealogySearch[
            <|"Surname" -> "Clemens", "GivenName" -> "John"|>,
            "Providers" -> "FindAGrave", "MaxResults" -> 3
        ]},
            Length[rows] > 0 && AllTrue[rows[[All, "Name"]], StringQ]
        ],
        True,
        TestID -> "The browser runner extracts burial records from Find a Grave"
    ];
    (* The Perm name index is the one provider whose hit already carries the
       parents and the archival file, so the test checks for a citation. *)
    VerificationTest[
        Block[{rows = Normal @ GenealogySearch[
            <|"Surname" -> "\:041f\:043e\:043f\:043e\:0432"|>,
            "Providers" -> "PermGenerations", "MaxResults" -> 3
        ]},
            Length[rows] > 0 && AllTrue[rows[[All, "URL"]], StringQ]
                && AnyTrue[rows[[All, "Detail"]], StringQ[#] && StringContainsQ[#, "\:0413\:0410\:041f\:041a"] &]
        ],
        True,
        TestID -> "The Perm name index returns records citing their archival file"
    ]
]

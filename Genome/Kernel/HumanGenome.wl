(* HumanGenome.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === HumanGenome ===
   HumanGenome[Genome[<|...|>], <|ann|>] wraps a human-build Genome with an
   interpretation-annotation Association.  Generic _?GenomeQ operators reach
   the inner Genome unchanged; property reads and filter accumulation forward
   through the generic SubValue below, and the human-specific interpretation
   slots are served by their own literal-key SubValues. *)

humanBuildQ[build_] := MemberQ[{"GRCh37/hg19", "GRCh38"}, build]

HumanGenome::nonHumanBuild = "HumanGenome: build `1` is not a human reference (GRCh37/hg19 or GRCh38); returning a generic Genome.";

(* -- constructor -- *)

HumanGenome[g_Genome] :=
    HumanGenome[
        g,
        <|
            "References" -> <|
                "Build" -> g["Build"],
                "ThousandGenomesPanel" -> Missing["NotComputed"],
                "ClinVarRelease" -> Missing["NotComputed"],
                "PGSCatalogVersion" -> Missing["NotComputed"],
                "CPICVersion" -> Missing["NotComputed"],
                "PharmGKBVersion" -> Missing["NotComputed"],
                "SNPediaCommit" -> Missing["NotComputed"],
                "AlphaMissenseRelease" -> Missing["NotComputed"],
                "GWASCatalogVersion" -> Missing["NotComputed"]
            |>,
            "Subject" -> initialSubject[g],
            "Ancestry" -> Missing["NotComputed"],
            "Haplogroups" -> Missing["NotComputed"],
            "Pharmacogenomics" -> Missing["NotComputed"],
            "ClinVarHits" -> Missing["NotComputed"],
            "PRS" -> Missing["NotComputed"],
            "Traits" -> Missing["NotComputed"],
            "AlphaMissenseScores" -> Missing["NotComputed"],
            "Carrier" -> Missing["NotComputed"],
            "GWASAssociations" -> Missing["NotComputed"],
            "ReportCache" -> Missing["NotComputed"]
        |>
    ] /; humanBuildQ[g["Build"]]

(* -- predicate -- *)

HumanGenomeQ[hg : HumanGenome[g_Genome, _Association]] /;
    GenomeQ[g] && humanBuildQ[g["Build"]] := True
HumanGenomeQ[_] := False

(* -- interpretation slot readers (cheap cache reads, never a computation) -- *)

HumanGenome[_, ann_Association][
    k : ("References" | "Subject" | "Ancestry" | "Haplogroups" |
        "Pharmacogenomics" | "ClinVarHits" | "PRS" | "Traits" |
        "AlphaMissenseScores" | "Carrier" | "GWASAssociations" | "ReportCache")
] := Lookup[ann, k, Missing["NotPresent"]]

HumanGenome[_, ann_Association]["Subject", sk_String] :=
    Lookup[Lookup[ann, "Subject", <||>], sk, Missing["NotPresent"]]

HumanGenome[_, ann_Association]["References", sk_String] :=
    Lookup[Lookup[ann, "References", <||>], sk, Missing["NotPresent"]]

(* The "PRS" slot is an Association keyed by PGS Catalog ID; hg["PRS", pgsid]
   reads one score's entry (hg["PRS"] reads the whole map above). *)
HumanGenome[_, ann_Association]["PRS", pgsid_String] :=
    Block[{prs = Lookup[ann, "PRS", Missing["NotComputed"]]},
        If[ AssociationQ[prs],
            Lookup[prs, ToUpperCase[pgsid], Missing["NotPresent"]],
            prs
        ]
    ]

(* -- generic forwarder + filter-accumulation rewrap --
   Every other SubValue call delegates to the inner Genome.  The literal-key
   readers above are more specific and win over this catch-all.  When the
   inner call returns a new Genome (filter accumulation), we rewrap it into a
   HumanGenome so the annotation slots survive; every other return value
   (String, Association, Tabular, Integer) flows through unchanged. *)

HumanGenome[g_Genome, ann_Association][args__] :=
    With[{inner = g[args]},
        If[ MatchQ[inner, _Genome], HumanGenome[inner, ann], inner]
    ]

(* -- UpValues (delegate to the inner Genome) -- *)

HumanGenome /: Length[hg : HumanGenome[g_Genome, _Association]] /; HumanGenomeQ[hg] :=
    Length[g]

HumanGenome /: Normal[hg : HumanGenome[g_Genome, _Association]] /; HumanGenomeQ[hg] :=
    Normal[g]

HumanGenome /: Dimensions[hg : HumanGenome[g_Genome, _Association]] /; HumanGenomeQ[hg] :=
    Dimensions[g]

HumanGenome /: Part[hg : HumanGenome[g_Genome, _Association], spec___] /; HumanGenomeQ[hg] :=
    Part[g, spec]

(* -- display --
   Distinct purple icon accent so a HumanGenome is visually disambiguated from
   the teal of a plain Genome, on light and dark themes alike.  Interpretation
   indicators are appended only when the corresponding slot is populated, so
   the box never triggers a computation. *)

ancestryShort[anc_Association] :=
    Block[{sp = Lookup[anc, "Superpopulation", Missing[]], fr = Lookup[anc, "SuperpopulationFractions", <||>]},
        Which[
            StringQ[sp], sp,
            AssociationQ[fr] && Length[fr] > 0, First @ Keys @ TakeLargest[fr, 1],
            True, "?"
        ]
    ]
ancestryShort[_] := "?"

humanGenomeLabel[a_Association, ann_Association] :=
    StringJoin[
        "HumanGenome[",
        First[Lookup[a, "Samples", {}], "?"],
        " * ",
        ToString[Lookup[a, "Build", "?"]],
        " * ",
        ToString[Length[Lookup[a, "Samples", {}]]],
        " sample(s) * ",
        genomeSizeLabel[Lookup[a, "Path", ""]],
        If[ !MissingQ[Lookup[ann, "Ancestry", Missing["NotComputed"]]],
            " * ancestry: " <> ancestryShort[ann["Ancestry"]],
            ""
        ],
        If[ MatchQ[Lookup[ann, "ClinVarHits", Missing[]], _Tabular],
            " * " <> ToString[Length[ann["ClinVarHits"]]] <> " ClinVar",
            ""
        ],
        "]"
    ]

(* The interpretation layer's summary box.  It carries the same identifying
   fields as a plain Genome, plus the one thing that distinguishes a
   HumanGenome: which annotation slots have been computed.  A slot holding
   Missing["NotComputed"] is not counted, so the field reads as progress
   through the interpretation layer rather than as a list of key names. *)

$humanAnnotationSlots = {
    "Sex", "Ancestry", "Haplogroups", "ClinVarHits", "Carrier",
    "AlphaMissenseScores", "PRS", "Traits", "GWASAssociations",
    "Pharmacogenomics"
}

humanComputedSlots[ann_Association] :=
    Select[$humanAnnotationSlots, ! MissingQ[Lookup[ann, #, Missing["NotComputed"]]] &]

humanGenomeSummaryItems[a_Association, ann_Association] :=
    Block[{computed = humanComputedSlots[ann]},
        {
            {
                BoxForm`SummaryItem[{"subject: ",
                    First[Lookup[a, "Samples", {}], "?"]}],
                BoxForm`SummaryItem[{"build: ", Lookup[a, "Build", "?"]}],
                BoxForm`SummaryItem[{"computed: ",
                    If[ computed === {},
                        "nothing yet",
                        ToString[Length[computed]] <> " of " <>
                            ToString[Length[$humanAnnotationSlots]]
                    ]}]
            },
            {
                BoxForm`SummaryItem[{"file: ", FileNameTake[Lookup[a, "Path", "?"]]}],
                BoxForm`SummaryItem[{"backend: ", Lookup[a, "Backend", "?"]}],
                BoxForm`SummaryItem[{"size: ", genomeSizeLabel[Lookup[a, "Path", ""]]}],
                BoxForm`SummaryItem[{"filters: ",
                    Replace[Lookup[a, "Filters", {}], {} -> "none"]}],
                BoxForm`SummaryItem[{"annotations: ",
                    Replace[computed, {} -> "none"]}]
            }
        }
    ]

HumanGenome /: MakeBoxes[hg : HumanGenome[Genome[a_Association], ann_Association],
        form : StandardForm | TraditionalForm] /;
    HumanGenomeQ[hg] && TrueQ[BoxForm`UseIcons] :=
    With[{items = humanGenomeSummaryItems[a, ann]},
        BoxForm`ArrangeSummaryBox[
            HumanGenome, hg, $genomeIcon[$humanGenomeAccent],
            First[items], Last[items], form,
            (* An interpretable box is an InterpretationBox holding the whole
               expression, so a genome whose annotation slots are filled would
               write those tables into the notebook source - invisibly, since
               the box itself displays only counts and slot names.  For the
               interpretation layer that is both a disclosure (a ClinVar or
               carrier table names conditions) and a size problem (a GWAS slot
               is hundreds of thousands of rows).  So the box round-trips only
               while nothing has been computed; once a slot is filled it
               renders as a plain summary and the handle is rebuilt by
               importing the file again.  There is a test pinning this. *)
            "Interpretable" -> If[humanComputedSlots[ann] === {}, Automatic, False]
        ]
    ]

(* -- interpretation operator stubs --
   These are the operators that will later COMPUTE an interpretation and
   return a new HumanGenome with the slot populated.  The cheap slot readers
   above serve the cached value (Missing["NotComputed"] until computed); these
   operators are the not-yet-implemented compute paths. *)

(* ChromosomalSex is implemented below in the "sex inference" section;
   HaplogroupCall in the "haplogroup interpretation" section;
   AncestryEstimate in the "ancestry interpretation" section. *)

(* PharmacogenomicProfile is implemented below in the "pharmacogenomics
   interpretation" section. *)

(* ClinVarHits is implemented below in the "ClinVar interpretation" section;
   the remaining operators are still stubs. *)

(* PolygenicRiskScore is implemented below in the "polygenic risk score
   interpretation" section; the remaining operators are still stubs. *)

(* TraitAssociations is implemented below in the "SNPedia trait
   interpretation" section; AlphaMissenseScores in the "AlphaMissense
   interpretation" section; the remaining operators are still stubs. *)

(* CarrierStatus is implemented below in the "carrier status interpretation"
   section; the remaining operators are still stubs. *)

(* GenomeReport is implemented below in the "aggregate report" section; it
   aggregates the other interpretation slots and never re-implements any of
   them. *)


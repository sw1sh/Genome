(* Formats.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  See wl/GUIDE.md for style. *)

(* === Import / Export formats ===
   The readers and writers of this paclet are also registered as Import and
   Export formats, so the standard system verbs reach them:

     Import["tree.ged"]                        a FamilyTree, by the .ged extension
     Import[file, {"GEDCOM", "People"}]        one element of it
     Export["tree.ged", ft]                    GEDCOM 5.5.1 out
     Import[file, "FamilyTable"]               the flat one-row-per-person table
     Import[file, "GenomeVCF"]                 the lazy Genome handle over a VCF

   "GenomeVCF" is named so because the kernel already owns a format called
   "VCF", and a paclet must not redefine a system format.  The functions
   behind these (ImportGEDCOM, ExportGEDCOM, ImportFamilyTable,
   ExportFamilyTable, ImportVCF) stay public; the formats are a second door
   to the same code.  RegisterImport hands the import function a file path
   and passes the caller's options through; the element functions receive
   the {"Data" -> value} rules the import function returned. *)

formatOptions[fn_, opts_List] := FilterRules[Flatten[opts], Options[fn]]

(* -- GEDCOM -- *)

importGEDCOMFormat[file_, opts___] :=
    Block[{ft = ImportGEDCOM[file, formatOptions[ImportGEDCOM, {opts}]]},
        If[ FamilyTreeQ[ft], {"Data" -> ft}, $Failed]
    ]

(* An element function is called with the import's rules, and, when the caller
   gave options, with those options after them; the arity must allow both. *)
familyTreeElement[key_][rules_, ___] :=
    Block[{ft = Lookup[rules, "Data", $Failed]},
        If[ ! FamilyTreeQ[ft], Return[$Failed]];
        Replace[key, {
            "People" :> ft["People"],
            "Families" :> ft["Families"],
            "Header" :> ft["Header"],
            "Tabular" :> ft["Tabular"],
            "Graph" :> FamilyTreePlot[ft]
        }]
    ]

ImportExport`RegisterImport["GEDCOM", importGEDCOMFormat,
    {
        "People" -> familyTreeElement["People"],
        "Families" -> familyTreeElement["Families"],
        "Header" -> familyTreeElement["Header"],
        "Tabular" -> familyTreeElement["Tabular"],
        "Graph" -> familyTreeElement["Graph"]
    },
    "AvailableElements" -> {"Data", "People", "Families", "Header", "Tabular", "Graph"},
    "DefaultElement" -> "Data",
    "Options" -> {CharacterEncoding}
]

exportGEDCOMFormat[file_, ft_ ? FamilyTreeQ, opts___] := ExportGEDCOM[file, ft, formatOptions[ExportGEDCOM, {opts}]]
exportGEDCOMFormat[file_, x_, ___] := (Message[ExportGEDCOM::notTree, x]; $Failed)

ImportExport`RegisterExport["GEDCOM", exportGEDCOMFormat, "Options" -> {"Submitter", "LineEnding"}]

(* -- FamilyTable -- *)

importFamilyTableFormat[file_, opts___] :=
    Block[{ft = ImportFamilyTable[file, formatOptions[ImportFamilyTable, {opts}]]},
        If[ FamilyTreeQ[ft], {"Data" -> ft}, $Failed]
    ]

ImportExport`RegisterImport["FamilyTable", importFamilyTableFormat,
    {
        "People" -> familyTreeElement["People"],
        "Families" -> familyTreeElement["Families"],
        "Tabular" -> familyTreeElement["Tabular"],
        "Graph" -> familyTreeElement["Graph"]
    },
    "AvailableElements" -> {"Data", "People", "Families", "Tabular", "Graph"},
    "DefaultElement" -> "Data",
    "Options" -> {"Delimiter", CharacterEncoding}
]

exportFamilyTableFormat[file_, ft_ ? FamilyTreeQ, opts___] := ExportFamilyTable[file, ft, formatOptions[ExportFamilyTable, {opts}]]
exportFamilyTableFormat[file_, x_, ___] := (Message[ExportFamilyTable::notTree, x]; $Failed)

ImportExport`RegisterExport["FamilyTable", exportFamilyTableFormat,
    "Options" -> {"Headers", "Delimiter", "ByteOrderMark", "LineEnding"}]

(* -- GenomeVCF -- *)

importGenomeVCFFormat[file_, opts___] :=
    Block[{g = ImportVCF[file, formatOptions[ImportVCF, {opts}]]},
        If[ GenomeQ[g], {"Data" -> g}, $Failed]
    ]

genomeElement[key_][rules_, ___] :=
    Block[{g = Lookup[rules, "Data", $Failed]},
        If[ ! GenomeQ[g], Return[$Failed]];
        Replace[key, {
            "Header" :> g["Header"],
            "Samples" :> g["Samples"],
            "Build" :> g["Build"],
            "Variants" :> g["Variants"],
            "VariantSummary" :> g["Summary"]
        }]
    ]

ImportExport`RegisterImport["GenomeVCF", importGenomeVCFFormat,
    {
        "Header" -> genomeElement["Header"],
        "Samples" -> genomeElement["Samples"],
        "Build" -> genomeElement["Build"],
        "Variants" -> genomeElement["Variants"],
        "VariantSummary" -> genomeElement["VariantSummary"]
    },
    "AvailableElements" -> {"Data", "Header", "Samples", "Build", "Variants", "VariantSummary"},
    "DefaultElement" -> "Data",
    "Options" -> {"MaxVariants", "Chromosome", "Region", "PASSOnly", "ExcludeReferenceOnly", "MinImputationR2", "Backend", "Human"}
]

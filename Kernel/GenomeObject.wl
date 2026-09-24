(* GenomeObject.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === GenomeQ === *)

$genomeRequiredKeys = {
    "Path", "Header", "Samples", "Build", "Backend", "Filters",
    "VariantCountCache"
}

GenomeQ[Genome[a_Association]] :=
    AllTrue[$genomeRequiredKeys, KeyExistsQ[a, #] &]
GenomeQ[HumanGenome[g_Genome, _Association]] := GenomeQ[g]
GenomeQ[_] := False

(* === ImportVCF === *)

Options[ImportVCF] = {
    "MaxVariants" -> Infinity,
    "Chromosome" -> All,
    "Region" -> None,
    "PASSOnly" -> True,
    "ExcludeReferenceOnly" -> True,
    "MinImputationR2" -> 0,
    "Backend" -> Automatic,
    "Human" -> Automatic
}

(* Turn ImportVCF option settings into the initial "Filters" list.  We
   only record a filter when its value differs from the "no-op" value;
   this keeps the printed filter list short and legible. *)
optionsToFilters[opts_List] :=
    Block[{maxN, chromOpt, regionOpt, passOnly, excludeRefOnly, minR2, out},
        maxN = OptionValue[ImportVCF, opts, "MaxVariants"];
        chromOpt = OptionValue[ImportVCF, opts, "Chromosome"];
        regionOpt = OptionValue[ImportVCF, opts, "Region"];
        passOnly = TrueQ[OptionValue[ImportVCF, opts, "PASSOnly"]];
        excludeRefOnly = TrueQ[OptionValue[ImportVCF, opts, "ExcludeReferenceOnly"]];
        minR2 = OptionValue[ImportVCF, opts, "MinImputationR2"];
        out = {};
        If[ maxN =!= Infinity, out = Append[out, "MaxVariants" -> maxN]];
        If[ chromOpt =!= All, out = Append[out, "Chromosome" -> chromOpt]];
        If[ regionOpt =!= None, out = Append[out, "Region" -> regionOpt]];
        If[ passOnly, out = Append[out, "PASSOnly" -> True]];
        If[ excludeRefOnly, out = Append[out, "ExcludeReferenceOnly" -> True]];
        If[ NumericQ[minR2] && minR2 > 0,
            out = Append[out, "MinImputationR2" -> minR2]
        ];
        out
    ]

ImportVCF[path_String, opts : OptionsPattern[]] :=
    Block[{header, samples, build, backendChoice, backend, filters, payload},
        header = ImportVCFHeader[path];
        If[ header === $Failed, Return[$Failed]];
        samples = Lookup[header, "Samples", {}];
        build = Lookup[header, "InferredBuild", "Unknown"];
        backendChoice = OptionValue["Backend"];
        backend = resolveBackend[path, backendChoice];
        filters = optionsToFilters[{opts}];
        payload = <|
            "Path" -> path,
            "Header" -> header,
            "Samples" -> samples,
            "Build" -> build,
            "Backend" -> backend,
            "Filters" -> filters,
            "VariantCountCache" -> Missing["NotComputed"]
        |>;
        promoteHuman[Genome[payload], OptionValue["Human"]]
    ]

(* Post-construction autopromotion of a generic Genome to a HumanGenome.
   "Human" -> Automatic promotes iff the build is a human reference and the
   sample count is exactly one; True forces promotion on any human build
   (raising HumanGenome::nonHumanBuild and returning the Genome otherwise);
   False always keeps the generic Genome. *)
promoteHuman[g_Genome, human_] :=
    Which[
        human === False, g,
        human === True,
            If[ humanBuildQ[g["Build"]],
                HumanGenome[g],
                Message[HumanGenome::nonHumanBuild, g["Build"]];
                g
            ],
        True,
            If[ humanBuildQ[g["Build"]] && Length[g["Samples"]] == 1,
                HumanGenome[g],
                g
            ]
    ]

(* === GenomeToParquet ===
   One-time conversion of a Genome's source VCF into the Parquet sidecar
   set beside the file.  The scan happens entirely in awk so the kernel
   never sees the reference-confirming rows (2.69 B on the real file): the
   variants pass streams only ALT != "." rows, and the reference pass
   run-length-encodes adjacent reference-confirming rows into intervals
   inside awk, emitting one row per collapsed interval. *)

Options[GenomeToParquet] = {
    "Compression" -> "ZSTD",
    "Overwrite" -> False,
    "RefBlocks" -> True
}

GenomeToParquet::exists = "GenomeToParquet: the sidecar `1` already exists; pass \"Overwrite\" -> True to replace it.";
GenomeToParquet::notGenome = "GenomeToParquet expects a Genome; received `1`.";

(* awk that keeps only real-variant rows (ALT != "."), printing each
   verbatim so the kernel parser sees the original tab layout. *)
variantFilterAwk[] := "/^#/ { next } $5 != \".\" { print }"

(* awk that run-length-encodes adjacent reference-confirming rows
   (ALT == ".") into (CHROM, START, END, GT, GQ, DP) interval rows.  GT is
   the first FORMAT subfield; GQ / DP are looked up by their FORMAT index
   when present, else ".".  A run extends while CHROM, GT, GQ and DP are
   unchanged and POS is contiguous (POS == prev + 1). *)
refBlocksAwk[] := StringJoin[
    "/^#/ { next } ",
    "$5 != \".\" { next } ",
    "{ ",
    "chrom = $1; pos = $2 + 0; ",
    "split($10, sv, \":\"); gt = sv[1]; ",
    "fn = split($9, fk, \":\"); gq = \".\"; dp = \".\"; ",
    "for (i = 1; i <= fn; i++) { if (fk[i] == \"GQ\") gq = sv[i]; else if (fk[i] == \"DP\") dp = sv[i]; } ",
    "if (have && chrom == pchrom && gt == pgt && gq == pgq && dp == pdp && pos == pend + 1) { pend = pos } ",
    "else { ",
    "if (have) print pchrom \"\\t\" pstart \"\\t\" pend \"\\t\" pgt \"\\t\" pgq \"\\t\" pdp; ",
    "pchrom = chrom; pstart = pos; pend = pos; pgt = gt; pgq = gq; pdp = dp; have = 1 ",
    "} ",
    "} ",
    "END { if (have) print pchrom \"\\t\" pstart \"\\t\" pend \"\\t\" pgt \"\\t\" pgq \"\\t\" pdp }"
]

streamVariantLines[path_String] :=
    Block[{cmd, out},
        cmd = streamCommand[path] <> " | awk " <> shellEscape[variantFilterAwk[]];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

streamRefBlockLines[path_String] :=
    Block[{cmd, out},
        cmd = streamCommand[path] <> " | awk -F '\\t' " <> shellEscape[refBlocksAwk[]];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

(* Copy the verbatim ## meta lines plus the #CHROM line into a text
   sidecar.  awk exits at the first data row, so only header bytes flow. *)
writeHeaderSidecar[path_String, hdrPath_String] :=
    RunProcess[{
        "sh", "-c",
        streamCommand[path] <> " | awk '/^#/{print; next} {exit}' > " <> shellEscape[hdrPath]
    }]

parquetVariantColumns[samples_List] :=
    Join[
        {"CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO_raw",
         "AF", "MAF", "R2", "ER2", "AC", "AN", "IMPUTED", "TYPED", "TYPED_ONLY",
         "FORMAT"},
        Map["GT_" <> # &, samples]
    ]

parquetRefBlockColumns[samples_List] :=
    {"CHROM", "START", "END", "GT_" <> First[samples], "GQ", "DP"}

(* Coerce an INFO numeric key to a Real (schema keeps AF / MAF / R2 / ER2
   as Float64 columns); infoNumeric alone would leave an integer literal
   as an Integer. *)
parquetReal[info_Association, key_String] :=
    Block[{v = infoNumeric[info, key]},
        If[ NumericQ[v], N[v], Missing[]]
    ]

parquetVariantRow[line_String, samples_List] :=
    Block[{f, info, alt, filt, qual, gtCols},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 10, Return[Missing[]]];
        info = parseInfo[f[[8]]];
        alt = If[ f[[5]] === ".", {}, StringSplit[f[[5]], ","]];
        filt = If[ f[[7]] === ".", {}, StringSplit[f[[7]], ";"]];
        qual = Replace[
            f[[6]],
            {
                "." -> Missing[],
                s_String :> Block[{v = Quiet @ ToExpression[s]},
                    If[ NumericQ[v], N[v], Missing[]]
                ]
            }
        ];
        gtCols = Association @ Table[
            ("GT_" <> samples[[i]]) -> If[ Length[f] >= 9 + i, f[[9 + i]], Missing[]],
            {i, Length[samples]}
        ];
        Join[
            <|
                "CHROM" -> f[[1]],
                "POS" -> FromDigits[f[[2]]],
                "ID" -> Replace[f[[3]], "." -> Missing[]],
                "REF" -> f[[4]],
                "ALT" -> alt,
                "QUAL" -> qual,
                "FILTER" -> filt,
                "INFO_raw" -> f[[8]],
                "AF" -> parquetReal[info, "AF"],
                "MAF" -> parquetReal[info, "MAF"],
                "R2" -> parquetReal[info, "R2"],
                "ER2" -> parquetReal[info, "ER2"],
                "AC" -> infoNumeric[info, "AC"],
                "AN" -> infoNumeric[info, "AN"],
                "IMPUTED" -> infoFlag[info, "IMPUTED"],
                "TYPED" -> infoFlag[info, "TYPED"],
                "TYPED_ONLY" -> infoFlag[info, "TYPED_ONLY"],
                "FORMAT" -> f[[9]]
            |>,
            gtCols
        ]
    ]

parquetRefBlockRow[line_String, samples_List] :=
    Block[{f},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 6, Return[Missing[]]];
        <|
            "CHROM" -> f[[1]],
            "START" -> FromDigits[f[[2]]],
            "END" -> FromDigits[f[[3]]],
            ("GT_" <> First[samples]) -> f[[4]],
            "GQ" -> If[ f[[5]] === ".", Missing[], FromDigits[f[[5]]]],
            "DP" -> If[ f[[6]] === ".", Missing[], FromDigits[f[[6]]]]
        |>
    ]

exportVariantsParquet[varPath_String, samples_List, lines_List, compression_] :=
    Block[{rows, cols = parquetVariantColumns[samples]},
        rows = DeleteCases[Map[parquetVariantRow[#, samples] &, lines], _Missing];
        If[ rows === {}, Return[$Failed]];
        rows = SortBy[rows, {chromKey[#["CHROM"]], #["POS"]} &];
        rows = Map[KeyTake[#, cols] &, rows];
        Export[varPath, Tabular[rows], "Compression" -> compression]
    ]

exportRefBlocksParquet[refPath_String, samples_List, lines_List, compression_] :=
    Block[{rows, cols = parquetRefBlockColumns[samples]},
        rows = DeleteCases[Map[parquetRefBlockRow[#, samples] &, lines], _Missing];
        If[ rows === {}, Return[$Failed]];
        rows = SortBy[rows, {chromKey[#["CHROM"]], #["START"]} &];
        rows = Map[KeyTake[#, cols] &, rows];
        Export[refPath, Tabular[rows], "Compression" -> compression]
    ]

GenomeToParquet[g_ ? GenomeQ, opts : OptionsPattern[]] :=
    Block[{a, path, samples, compression, overwrite, doRef, varPath, refPath,
           hdrPath, existing, varLines, refLines},
        a = First[g];
        path = a["Path"];
        samples = a["Samples"];
        compression = OptionValue["Compression"];
        overwrite = TrueQ[OptionValue["Overwrite"]];
        doRef = TrueQ[OptionValue["RefBlocks"]];
        varPath = parquetVariantsPath[path];
        refPath = parquetRefBlocksPath[path];
        hdrPath = parquetHeaderSidecarPath[path];
        existing = Select[
            Join[{varPath, hdrPath}, If[ doRef, {refPath}, {}]],
            FileExistsQ
        ];
        If[ existing =!= {} && ! overwrite,
            Message[GenomeToParquet::exists, First[existing]];
            Return[$Failed]
        ];
        writeHeaderSidecar[path, hdrPath];
        varLines = streamVariantLines[path];
        If[ varLines === $Failed, Return[$Failed]];
        exportVariantsParquet[varPath, samples, varLines, compression];
        If[ doRef,
            refLines = streamRefBlockLines[path];
            If[ ListQ[refLines] && refLines =!= {},
                exportRefBlocksParquet[refPath, samples, refLines, compression]
            ]
        ];
        <|
            "Variants" -> varPath,
            "RefBlocks" -> If[ doRef, refPath, Missing["Skipped"]],
            "Header" -> hdrPath
        |>
    ]

GenomeToParquet[x_, opts : OptionsPattern[]] :=
    (Message[GenomeToParquet::notGenome, x]; $Failed)

(* === Genome SubValues ===
   All Genome[<|...|>][key, args...] calls are routed through the
   dispatch below.  Three categories:

     Properties (cheap)   -> return the stored value
     Query methods (lazy) -> route through backendDispatch
     Filter accumulation  -> return a new Genome with the filter appended
*)

(* -- Properties -- *)

Genome[a_Association]["Path"] := a["Path"]
Genome[a_Association]["Header"] := a["Header"]
Genome[a_Association]["Header", k_String] := Lookup[a["Header"], k, Missing["NotFound", k]]
Genome[a_Association]["Samples"] := a["Samples"]
Genome[a_Association]["Build"] := a["Build"]
Genome[a_Association]["Backend"] := a["Backend"]
Genome[a_Association]["Filters"] := a["Filters"]

Genome[a_Association]["VariantCount"] :=
    Block[{cached = a["VariantCountCache"]},
        If[ IntegerQ[cached],
            cached,
            backendDispatch[Genome[a], "Count"]
        ]
    ]

(* -- Query methods -- *)

Genome[a_Association]["Variants", opts___Rule] :=
    backendDispatch[Genome[a], "Variants", {opts}]

Genome[a_Association]["Region", chrom_String, {start_Integer, end_Integer}] :=
    backendDispatch[Genome[a], "Region", chrom, {start, end}]

Genome[a_Association]["Genotype", rsid_String] :=
    backendDispatch[Genome[a], "Genotype", rsid]

Genome[a_Association]["Summary"] :=
    backendDispatch[Genome[a], "Summary"]

(* -- Filter accumulation -- *)

appendFilter[a_Association, rule_Rule] :=
    Genome[Append[a, "Filters" -> Append[a["Filters"], rule]]]

Genome[a_Association]["FilterPASS"] :=
    appendFilter[a, "PASSOnly" -> True]

Genome[a_Association]["MinR2", r_ ? NumericQ] :=
    appendFilter[a, "MinImputationR2" -> r]

Genome[a_Association]["Chromosome", chr_String] :=
    appendFilter[a, "Chromosome" -> chr]

Genome[a_Association]["ExcludeReferenceOnly"] :=
    appendFilter[a, "ExcludeReferenceOnly" -> True]

Genome[a_Association]["MaxVariants", n : (_Integer | Infinity)] :=
    appendFilter[a, "MaxVariants" -> n]

(* === Genome UpValues === *)

Genome::notIndexable = "Genome[..] is not directly indexable; call g[\"Variants\"] and index the resulting Tabular.";

Genome /: Length[g : Genome[a_Association]] /; GenomeQ[g] :=
    g["VariantCount"]

Genome /: Normal[g : Genome[a_Association]] /; GenomeQ[g] :=
    Normal @ g["Variants"]

Genome /: Dimensions[g : Genome[a_Association]] /; GenomeQ[g] :=
    {g["VariantCount"], Length[variantColumnOrder[]]}

Genome /: Part[g : Genome[a_Association], ___] /; GenomeQ[g] :=
    (Message[Genome::notIndexable]; $Failed)

(* === Genome display === *)

genomeSizeLabel[path_String] :=
    Block[{bytes, kb, mb, gb},
        If[ !FileExistsQ[path], Return["?"]];
        bytes = FileByteCount[path];
        Which[
            !IntegerQ[bytes], "?",
            bytes < 1024, ToString[bytes] <> " B",
            bytes < 1024^2,
                kb = N[bytes / 1024];
                ToString[NumberForm[kb, 3]] <> " KB",
            bytes < 1024^3,
                mb = N[bytes / 1024^2];
                ToString[NumberForm[mb, 3]] <> " MB",
            True,
                gb = N[bytes / 1024^3];
                ToString[NumberForm[gb, 3]] <> " GB"
        ]
    ]

genomeLabel[a_Association] :=
    StringJoin[
        "Genome[",
        FileNameTake[Lookup[a, "Path", "?"]],
        " * ",
        ToString[Lookup[a, "Build", "?"]],
        " * ",
        ToString[Length[Lookup[a, "Samples", {}]]],
        " sample(s) * ",
        genomeSizeLabel[Lookup[a, "Path", ""]],
        "]"
    ]

(* A proper summary box rather than a framed label: the icon plus the three
   fields that identify the handle, with the rest behind the opener.  The
   filter spec is the field a reader most often wants to check, since it is
   what every query is scoped by.  ArrangeSummaryBox yields an
   InterpretationBox, so the object stays copyable and re-evaluable. *)

genomeSummaryItems[a_Association] :=
    {
        {
            BoxForm`SummaryItem[{"file: ", FileNameTake[Lookup[a, "Path", "?"]]}],
            BoxForm`SummaryItem[{"build: ", Lookup[a, "Build", "?"]}],
            BoxForm`SummaryItem[{"samples: ", Length[Lookup[a, "Samples", {}]]}]
        },
        {
            BoxForm`SummaryItem[{"backend: ", Lookup[a, "Backend", "?"]}],
            BoxForm`SummaryItem[{"size: ", genomeSizeLabel[Lookup[a, "Path", ""]]}],
            BoxForm`SummaryItem[{"filters: ",
                Replace[Lookup[a, "Filters", {}], {} -> "none"]}],
            BoxForm`SummaryItem[{"variants: ",
                Replace[Lookup[a, "VariantCountCache", Missing["NotComputed"]],
                    _Missing -> "not counted"]}]
        }
    }

Genome /: MakeBoxes[g : Genome[a_Association], form : StandardForm | TraditionalForm] /;
    GenomeQ[g] && TrueQ[BoxForm`UseIcons] :=
    With[{items = genomeSummaryItems[a]},
        BoxForm`ArrangeSummaryBox[
            Genome, g, $genomeIcon[$genomeAccent],
            First[items], Last[items], form,
            "Interpretable" -> Automatic
        ]
    ]


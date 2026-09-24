(* VCF.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === ImportVCFHeader === *)

ImportVCFHeader[path_String] :=
    Block[{lines, metaLines, chromLine, parsed, contigs, infos, formats, filters,
           samples, fileFormat, source, reference},
        lines = readHeaderLines[path];
        If[ lines === $Failed, Return[$Failed]];
        lines = Select[lines, # =!= "" &];
        metaLines = Select[lines, StringStartsQ[#, "##"] &];
        chromLine = SelectFirst[lines, StringStartsQ[#, "#CHROM"] &, ""];
        parsed = Map[parseMetaLine, metaLines];
        contigs = Cases[parsed, a_Association /; Lookup[a, "Tag", ""] === "contig"];
        infos = Cases[parsed, a_Association /; Lookup[a, "Tag", ""] === "INFO"];
        formats = Cases[parsed, a_Association /; Lookup[a, "Tag", ""] === "FORMAT"];
        filters = Cases[parsed, a_Association /; Lookup[a, "Tag", ""] === "FILTER"];
        fileFormat = Replace[
            FirstCase[parsed, ("fileformat" -> v_) :> v, Missing[]],
            s_String :> s
        ];
        source = Replace[
            FirstCase[parsed, ("source" -> v_) :> v, Missing[]],
            s_String :> s
        ];
        reference = Replace[
            FirstCase[parsed, ("reference" -> v_) :> v, Missing[]],
            s_String :> s
        ];
        samples = If[ chromLine === "",
            {},
            Drop[StringSplit[chromLine, "\t"], UpTo[9]]
        ];
        <|
            "Path" -> path,
            "FileFormat" -> fileFormat,
            "Source" -> source,
            "Reference" -> reference,
            "InferredBuild" -> inferBuild[contigs],
            "Contigs" -> contigs,
            "INFO" -> infos,
            "FORMAT" -> formats,
            "FILTER" -> filters,
            "Samples" -> samples,
            "MetaLineCount" -> Length[metaLines]
        |>
    ]

(* === parsing rows === *)

(* Parse an INFO field ("DB;DP=16;..." or ".") into an Association.
   Flag fields (no "=") map to True.  Comma-separated lists stay as a
   single string at this layer - callers can split them as needed. *)
parseInfo[info_String] :=
    If[ info === ".",
        <||>,
        Association @ Map[
            kv |-> Block[{eq = StringPosition[kv, "=", 1]},
                If[ eq === {},
                    kv -> True,
                    StringTake[kv, eq[[1, 1]] - 1] -> StringDrop[kv, eq[[1, 1]]]
                ]
            ],
            StringSplit[info, ";"]
        ]
    ]

(* Extract a numeric INFO key as either a Real, an Integer, or Missing. *)
infoNumeric[info_Association, key_String] :=
    Block[{raw},
        raw = Lookup[info, key, Missing[]];
        Which[
            MissingQ[raw], Missing[],
            NumericQ[raw], raw,
            StringQ[raw],
                Quiet @ Replace[
                    ToExpression[raw],
                    {n_ ? NumericQ :> n, _ -> Missing[]}
                ],
            True, Missing[]
        ]
    ]

infoFlag[info_Association, key_String] :=
    TrueQ[Lookup[info, key, False]]

(* Parse one tab-separated VCF row (10 fields for a single-sample file)
   into the variant association used everywhere downstream.  Surfaces the
   hot INFO keys (R2, MAF, AC, AN, IMPUTED, TYPED, TYPED_ONLY) as
   top-level columns in addition to the nested INFO Association. *)
parseVCFRow[row_String] :=
    Block[{f, alt, filt, qual, id, info},
        f = StringSplit[row, "\t"];
        If[ Length[f] < 10, Return[Missing[]]];
        id = Replace[f[[3]], "." -> Missing[]];
        alt = If[ f[[5]] === ".", {}, StringSplit[f[[5]], ","]];
        qual = Replace[
            f[[6]],
            {"." -> Missing[], s_String :> Quiet @ ToExpression[s]}
        ];
        filt = If[ f[[7]] === ".", {}, StringSplit[f[[7]], ";"]];
        info = parseInfo[f[[8]]];
        <|
            "CHROM" -> f[[1]],
            "POS" -> FromDigits[f[[2]]],
            "ID" -> id,
            "REF" -> f[[4]],
            "ALT" -> alt,
            "QUAL" -> qual,
            "FILTER" -> filt,
            "INFO" -> info,
            "R2" -> infoNumeric[info, "R2"],
            "MAF" -> infoNumeric[info, "MAF"],
            "AC" -> infoNumeric[info, "AC"],
            "AN" -> infoNumeric[info, "AN"],
            "IMPUTED" -> infoFlag[info, "IMPUTED"],
            "TYPED" -> infoFlag[info, "TYPED"],
            "TYPED_ONLY" -> infoFlag[info, "TYPED_ONLY"],
            "FORMAT" -> f[[9]],
            "GT" -> f[[10]]
        |>
    ]

(* === awk pipeline === *)

(* Quote a value for embedding inside a single-quoted awk script. *)
awkString[s_String] := "\"" <> StringReplace[s, {"\\" -> "\\\\", "\"" -> "\\\""}] <> "\""

(* Build the list of awk guard expressions for the per-row predicate.
   Each element is a string of awk source; the caller combines them
   with " && " so a row passes only when every guard is true. *)
awkConds[chromOpt_, regionOpt_, passOnly_, excludeRefOnly_, minR2_] :=
    Block[{passCond, refCond, regionCond, chromCond, r2Cond, chromAlts},
        passCond = If[ TrueQ[passOnly], "$7 == \"PASS\"", Nothing];
        refCond = If[ TrueQ[excludeRefOnly], "$5 != \".\"", Nothing];
        (* Region overrides Chromosome when set. *)
        regionCond = If[ MatchQ[regionOpt, {_String, {_Integer, _Integer}}],
            Sequence @@ {
                "$1 == " <> awkString[regionOpt[[1]]],
                "$2+0 >= " <> ToString[regionOpt[[2, 1]]],
                "$2+0 <= " <> ToString[regionOpt[[2, 2]]]
            },
            Nothing
        ];
        chromCond = If[ MatchQ[regionOpt, {_String, {_Integer, _Integer}}],
            Nothing,
            Which[
                StringQ[chromOpt], "$1 == " <> awkString[chromOpt],
                MatchQ[chromOpt, {__String}],
                    chromAlts = StringRiffle[
                        Map[c |-> "$1 == " <> awkString[c], chromOpt],
                        " || "
                    ];
                    "(" <> chromAlts <> ")",
                True, Nothing
            ]
        ];
        r2Cond = If[ NumericQ[minR2] && minR2 > 0,
            "r2val($8) >= " <> ToString[N[minR2]],
            Nothing
        ];
        {passCond, refCond, regionCond, chromCond, r2Cond}
    ]

(* The R2 extractor lives in the awk script when MinImputationR2 > 0;
   otherwise we skip the function definition entirely. *)
awkR2Helper[minR2_] :=
    If[ NumericQ[minR2] && minR2 > 0,
        "function r2val(info,    a, n, i) { n = split(info, a, \";\"); for (i = 1; i <= n; i++) { if (substr(a[i], 1, 3) == \"R2=\") return substr(a[i], 4) + 0; } return -1; }\n",
        ""
    ]

(* Awk exit clause that stops scanning once we have moved past the
   region end.  The input VCF is sorted by (CHROM, POS), so once we see
   a data row on the target chromosome at position > end, or the seen
   chromosome no longer matches after we have seen at least one match,
   there are no more relevant rows in the file. *)
awkRegionExit[regionOpt_] :=
    If[ MatchQ[regionOpt, {_String, {_Integer, _Integer}}],
        "/^[^#]/ && $1 == " <> awkString[regionOpt[[1]]]
            <> " { seenRegion = 1 } "
            <> "/^[^#]/ && seenRegion && ($1 != " <> awkString[regionOpt[[1]]]
            <> " || $2+0 > " <> ToString[regionOpt[[2, 2]]] <> ") { exit } ",
        ""
    ]

(* Build the full awk program string. *)
awkProgram[chromOpt_, regionOpt_, passOnly_, excludeRefOnly_, minR2_, maxN_] :=
    Block[{conds, condStr, action},
        conds = awkConds[chromOpt, regionOpt, passOnly, excludeRefOnly, minR2];
        condStr = If[ conds === {},
            "1",
            StringRiffle[Map["(" <> # <> ")" &, conds], " && "]
        ];
        action = If[ maxN === Infinity,
            " { print }",
            " { print; n++; if (n >= " <> ToString[maxN] <> ") exit }"
        ];
        awkR2Helper[minR2]
            <> "/^#/ { next } "
            <> awkRegionExit[regionOpt]
            <> condStr
            <> action
    ]

(* Parse a captured shell stdout string into a list of variant rows. *)
parseVCFStream[out_String] :=
    Block[{lines, rows},
        lines = StringSplit[out, "\n"];
        lines = Select[lines, # =!= "" &];
        rows = Map[parseVCFRow, lines];
        DeleteCases[rows, _Missing]
    ]

(* === filter resolution ===
   The filter list on a Genome carries the accumulated intent from every
   subscript call.  When a query is materialised we normalise the list
   into a single canonical Association of options that the backend
   pipelines understand. *)

filterDefaults[] := <|
    "MaxVariants" -> Infinity,
    "Chromosome" -> All,
    "Region" -> None,
    "PASSOnly" -> False,
    "ExcludeReferenceOnly" -> False,
    "MinImputationR2" -> 0
|>

(* Merge one filter Rule from a Genome's "Filters" list into an
   accumulating Association.  Duplicate keys generally intersect (min /
   max as appropriate); Region overrides Chromosome. *)
mergeFilter[acc_Association, name_String -> value_] :=
    Which[
        name === "MaxVariants",
            Block[{cur = acc["MaxVariants"]},
                Append[acc, "MaxVariants" -> Min[cur, value]]
            ],
        name === "Chromosome",
            Append[acc, "Chromosome" -> value],
        name === "Region",
            Append[acc, "Region" -> value],
        name === "PASSOnly",
            Append[acc, "PASSOnly" -> TrueQ[value]],
        name === "ExcludeReferenceOnly",
            Append[acc, "ExcludeReferenceOnly" -> TrueQ[value]],
        name === "MinImputationR2",
            Block[{cur = acc["MinImputationR2"]},
                Append[acc, "MinImputationR2" -> Max[cur, value]]
            ],
        True,
            acc
    ]
mergeFilter[acc_Association, _] := acc

resolveFilters[filters_List] :=
    Fold[mergeFilter, filterDefaults[], filters]

(* Merge Filters recorded on a Genome with call-site option overrides.
   Call-site options take precedence over baked-in Filters. *)
resolveFiltersWithOpts[filters_List, opts_List] :=
    Block[{base = resolveFilters[filters]},
        Fold[
            Function[{acc, rule},
                If[ MatchQ[rule, _String -> _] && KeyExistsQ[acc, rule[[1]]],
                    Append[acc, rule[[1]] -> rule[[2]]],
                    acc
                ]
            ],
            base,
            opts
        ]
    ]

(* === variant Tabular assembly === *)

variantColumnOrder[] := {
    "CHROM", "POS", "ID", "REF", "ALT", "QUAL", "FILTER", "INFO",
    "R2", "MAF", "AC", "AN", "IMPUTED", "TYPED", "TYPED_ONLY",
    "FORMAT", "GT"
}

rowsToTabular[rows_List] :=
    Block[{cols = variantColumnOrder[], ordered},
        ordered = Map[r |-> KeyTake[r, cols], rows];
        Tabular[ordered]
    ]


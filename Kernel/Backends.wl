(* Backends.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === backend: AwkStream === *)

awkBackendVariants[genome_, extraOpts_List] :=
    Block[{a, path, resolved, awk, cmd, out, rows},
        a = First[genome];
        path = a["Path"];
        resolved = resolveFiltersWithOpts[a["Filters"], extraOpts];
        awk = awkProgram[
            resolved["Chromosome"],
            resolved["Region"],
            resolved["PASSOnly"],
            resolved["ExcludeReferenceOnly"],
            resolved["MinImputationR2"],
            resolved["MaxVariants"]
        ];
        cmd = streamCommand[path] <> " | awk " <> shellEscape[awk];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        rows = parseVCFStream[out];
        rowsToTabular[rows]
    ]

awkBackendRegion[genome_, chrom_String, {start_Integer, end_Integer}] :=
    awkBackendVariants[
        genome,
        {"Region" -> {chrom, {start, end}}}
    ]

awkBackendGenotype[genome_, rsid_String] :=
    Block[{a, path, resolved, awk, cmd, out, rows},
        a = First[genome];
        path = a["Path"];
        resolved = resolveFilters[a["Filters"]];
        awk = awkProgram[
            resolved["Chromosome"],
            resolved["Region"],
            resolved["PASSOnly"],
            resolved["ExcludeReferenceOnly"],
            resolved["MinImputationR2"],
            resolved["MaxVariants"]
        ];
        (* Restrict to rows whose ID column matches rsid using an
           outer awk stage so we stop scanning at the first hit. *)
        cmd = streamCommand[path] <> " | awk " <> shellEscape[awk]
            <> " | awk -F '\\t' " <> shellEscape["$3 == \"" <> rsid <> "\" { print; exit }"];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[Missing["NotFound", rsid]]];
        rows = parseVCFStream[out];
        If[ rows === {}, Missing["NotFound", rsid], First[rows]]
    ]

awkBackendCount[genome_] :=
    Block[{a, path, resolved, awk, cmd, out},
        a = First[genome];
        path = a["Path"];
        resolved = resolveFilters[a["Filters"]];
        awk = awkProgram[
            resolved["Chromosome"],
            resolved["Region"],
            resolved["PASSOnly"],
            resolved["ExcludeReferenceOnly"],
            resolved["MinImputationR2"],
            resolved["MaxVariants"]
        ];
        cmd = streamCommand[path] <> " | awk " <> shellEscape[awk] <> " | wc -l";
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        Quiet @ ToExpression[StringTrim[out]]
    ]

(* === backend: Tabix === *)

Genome::tabixNotAvailable = "Genome: the Tabix backend requires a `.tbi` sibling of `1` and the bcftools binary on PATH; falling back to AwkStream.";

tabixAvailableQ[path_String] :=
    FileExistsQ[path <> ".tbi"] && onPathQ["bcftools"]

tabixBackendRegion[genome_, chrom_String, {start_Integer, end_Integer}] :=
    Block[{a, path, resolved, cmd, out, rows},
        a = First[genome];
        path = a["Path"];
        resolved = resolveFiltersWithOpts[
            a["Filters"],
            {"Region" -> {chrom, {start, end}}, "MaxVariants" -> Infinity}
        ];
        cmd = "bcftools view -H -r "
            <> shellEscape[chrom <> ":" <> ToString[start] <> "-" <> ToString[end]]
            <> " " <> shellEscape[path];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        rows = parseVCFStream[out];
        (* Apply any remaining row-level filters (PASS, R2, ref-only) in
           the kernel since bcftools view -r already handled the region. *)
        rows = tabixApplyRowFilters[rows, resolved];
        rowsToTabular[rows]
    ]

tabixApplyRowFilters[rows_List, resolved_Association] :=
    Block[{filtered = rows},
        If[ TrueQ[resolved["PASSOnly"]],
            filtered = Select[filtered, MatchQ[#["FILTER"], {"PASS"}] &]
        ];
        If[ TrueQ[resolved["ExcludeReferenceOnly"]],
            filtered = Select[filtered, #["ALT"] =!= {} &]
        ];
        If[ NumericQ[resolved["MinImputationR2"]] && resolved["MinImputationR2"] > 0,
            filtered = Select[
                filtered,
                NumericQ[#["R2"]] && #["R2"] >= resolved["MinImputationR2"] &
            ]
        ];
        If[ resolved["MaxVariants"] =!= Infinity,
            filtered = Take[filtered, UpTo[resolved["MaxVariants"]]]
        ];
        filtered
    ]

(* === backend: Parquet ===
   The Parquet backend reads the sidecar set produced by GenomeToParquet:
   <path>.parquet (real variants), <path>.refblocks.parquet (collapsed
   reference intervals), and <path>.header.vcf (verbatim header).  Only
   the variants file is touched by the query methods below; the reference
   intervals are a separate store that today's queries never read, so
   Parquet-backend row counts and VariantSummary report over the
   real-variant rows only.

   WL 15.0 has no file-backed lazy Tabular with arbitrary predicate
   pushdown, so the reader imports the variants Parquet as an in-memory
   Tabular via Import[file, "Tabular"] and applies the accumulated filters
   with Tabular Select / Take.  Verified in 15.0: list columns round-trip
   as ListVector, all-Missing columns as a Null type that yields Missing[]
   back, and Select / Take return a Tabular. *)

Genome::parquetMissing = "Genome: the Parquet sidecar `1` was not found; run GenomeToParquet[g] to create it.";

parquetVariantsPath[path_String] := path <> ".parquet"

parquetRefBlocksPath[path_String] := path <> ".refblocks.parquet"

parquetHeaderSidecarPath[path_String] := path <> ".header.vcf"

parquetAvailableQ[path_String] :=
    FileExistsQ[parquetVariantsPath[path]]

(* Load the variants Parquet as a Tabular and apply the resolved filter
   set.  ExcludeReferenceOnly is inherent (the variants file holds only
   ALT != "." rows), so it needs no work here. *)
parquetBackendVariants[genome_, extraOpts_List] :=
    Block[{a, varPath, resolved, t},
        a = First[genome];
        varPath = parquetVariantsPath[a["Path"]];
        If[ !FileExistsQ[varPath],
            Message[Genome::parquetMissing, varPath];
            Return[$Failed]
        ];
        resolved = resolveFiltersWithOpts[a["Filters"], extraOpts];
        t = Import[varPath, "Tabular"];
        If[ !MatchQ[t, _Tabular], Return[$Failed]];
        applyParquetFilters[t, resolved]
    ]

applyParquetFilters[t_Tabular, resolved_Association] :=
    Block[{res = t, region, chrom, minR2, maxN},
        region = resolved["Region"];
        chrom = resolved["Chromosome"];
        minR2 = resolved["MinImputationR2"];
        maxN = resolved["MaxVariants"];
        If[ TrueQ[resolved["PASSOnly"]],
            res = Select[res, #FILTER === {"PASS"} &]
        ];
        (* Region overrides Chromosome, matching the awk / tabix backends. *)
        If[ MatchQ[region, {_String, {_Integer, _Integer}}],
            res = Select[
                res,
                #CHROM === region[[1]] && region[[2, 1]] <= #POS <= region[[2, 2]] &
            ],
            Which[
                StringQ[chrom], res = Select[res, #CHROM === chrom &],
                MatchQ[chrom, {__String}], res = Select[res, MemberQ[chrom, #CHROM] &]
            ]
        ];
        If[ NumericQ[minR2] && minR2 > 0,
            res = Select[res, NumericQ[#R2] && #R2 >= minR2 &]
        ];
        If[ maxN =!= Infinity,
            res = Take[res, UpTo[maxN]]
        ];
        res
    ]

parquetBackendRegion[genome_, chrom_String, {start_Integer, end_Integer}] :=
    parquetBackendVariants[
        genome,
        {"Region" -> {chrom, {start, end}}, "MaxVariants" -> Infinity}
    ]

parquetBackendGenotype[genome_, rsid_String] :=
    Block[{t},
        t = parquetBackendVariants[genome, {"MaxVariants" -> Infinity}];
        If[ !MatchQ[t, _Tabular], Return[Missing["NotFound", rsid]]];
        SelectFirst[
            Normal[t],
            Lookup[#, "ID", Missing[]] === rsid &,
            Missing["NotFound", rsid]
        ]
    ]

parquetBackendCount[genome_] :=
    Block[{t = parquetBackendVariants[genome, {}]},
        If[ MatchQ[t, _Tabular], Length[t], $Failed]
    ]

(* Adapt a Parquet-schema row (INFO_raw + exploded columns + GT_<sample>)
   back to the canonical variant row shape that variantSummaryRows
   expects (a nested INFO Association and a single "GT" column). *)
parquetToCanonicalRow[row_Association, samples_List] :=
    Block[{gtKey = "GT_" <> First[samples]},
        <|
            "CHROM" -> row["CHROM"],
            "POS" -> row["POS"],
            "ID" -> row["ID"],
            "REF" -> row["REF"],
            "ALT" -> row["ALT"],
            "QUAL" -> row["QUAL"],
            "FILTER" -> row["FILTER"],
            "INFO" -> <|
                "IMPUTED" -> TrueQ[row["IMPUTED"]],
                "TYPED" -> TrueQ[row["TYPED"]],
                "TYPED_ONLY" -> TrueQ[row["TYPED_ONLY"]]
            |>,
            "R2" -> row["R2"],
            "MAF" -> row["MAF"],
            "AC" -> row["AC"],
            "AN" -> row["AN"],
            "IMPUTED" -> TrueQ[row["IMPUTED"]],
            "TYPED" -> TrueQ[row["TYPED"]],
            "TYPED_ONLY" -> TrueQ[row["TYPED_ONLY"]],
            "FORMAT" -> row["FORMAT"],
            "GT" -> Lookup[row, gtKey, ""]
        |>
    ]

parquetBackendSummary[genome_] :=
    Block[{a = First[genome], t, adapted},
        t = parquetBackendVariants[genome, {}];
        If[ !MatchQ[t, _Tabular], Return[$Failed]];
        adapted = Map[parquetToCanonicalRow[#, a["Samples"]] &, Normal[t]];
        variantSummaryTabular[adapted]
    ]

(* === backend selection === *)

(* Tabix is the default backend whenever a .tbi index is present: its
   positional seeks serve the common region / point queries in milliseconds
   and its variant rows use the canonical row shape.  The Parquet backend is
   opt-in ("Backend" -> "Parquet") for analytical load-once-analyze-many work
   over the columnar variants table, whose exploded schema (INFO_raw plus the
   surfaced R2 / AF / flag columns and GT_<sample>) differs from the canonical
   shape and would otherwise silently change what g["Variants"] returns.  On a
   whole-genome file loading that 100+ MB table also costs tens of seconds,
   which a Tabix region seek avoids entirely. *)
autoSelectBackend[path_String] :=
    Which[
        tabixAvailableQ[path], "Tabix",
        parquetAvailableQ[path], "Parquet",
        True, "AwkStream"
    ]

(* Return the effective backend for a user-supplied choice.  Automatic
   auto-detects; an explicit "Tabix" that lacks the prerequisites
   downgrades to AwkStream with a warning message. *)
resolveBackend[path_String, choice_] :=
    Which[
        choice === Automatic || choice === "Automatic",
            autoSelectBackend[path],
        choice === "AwkStream", "AwkStream",
        choice === "Tabix",
            If[ tabixAvailableQ[path],
                "Tabix",
                Message[Genome::tabixNotAvailable, path];
                "AwkStream"
            ],
        choice === "Parquet", "Parquet",
        True, autoSelectBackend[path]
    ]

(* === backend dispatch ===
   backendDispatch[g, method, args...] routes to the concrete backend
   implementation.  The method table:

     "Variants" args = list of extra option rules (call-site overrides)
     "Region"   args = chrom, {start, end}
     "Genotype" args = rsid
     "Count"    args = (none)
*)
backendDispatch[genome_, "Variants", extraOpts_List] :=
    Replace[
        First[genome]["Backend"],
        {
            "AwkStream" :> awkBackendVariants[genome, extraOpts],
            "Tabix" :> awkBackendVariants[genome, extraOpts],
            "Parquet" :> parquetBackendVariants[genome, extraOpts],
            _ :> awkBackendVariants[genome, extraOpts]
        }
    ]

(* A positional region seek is Tabix's specialty: an indexed jump to the
   overlapping blocks beats loading a large Parquet variants table into a
   Tabular (tens of ms vs tens of seconds on a whole-genome file), so a
   Region query prefers the Tabix path whenever a .tbi index and bcftools
   are present, whatever the recorded backend.  rsID lookups and full-table
   materialisation (Genotype / Variants / Count / Summary) have no positional
   index to exploit and stay on the recorded backend, where a one-time
   Parquet load is the right call. *)
backendDispatch[genome_, "Region", chrom_String, {start_Integer, end_Integer}] :=
    Which[
        tabixAvailableQ[First[genome]["Path"]],
            tabixBackendRegion[genome, chrom, {start, end}],
        First[genome]["Backend"] === "Parquet",
            parquetBackendRegion[genome, chrom, {start, end}],
        True,
            awkBackendRegion[genome, chrom, {start, end}]
    ]

backendDispatch[genome_, "Genotype", rsid_String] :=
    Replace[
        First[genome]["Backend"],
        {
            "AwkStream" :> awkBackendGenotype[genome, rsid],
            "Tabix" :> awkBackendGenotype[genome, rsid],
            "Parquet" :> parquetBackendGenotype[genome, rsid],
            _ :> awkBackendGenotype[genome, rsid]
        }
    ]

backendDispatch[genome_, "Count"] :=
    Replace[
        First[genome]["Backend"],
        {
            "AwkStream" :> awkBackendCount[genome],
            "Tabix" :> awkBackendCount[genome],
            "Parquet" :> parquetBackendCount[genome],
            _ :> awkBackendCount[genome]
        }
    ]

(* Summary routes to a Parquet-aware path because the Parquet variants
   schema (INFO_raw + exploded columns + GT_<sample>) differs from the
   canonical row shape variantSummaryRows expects; every other backend
   summarises the materialised variant Tabular directly. *)
backendDispatch[genome_, "Summary"] :=
    Replace[
        First[genome]["Backend"],
        {
            "Parquet" :> parquetBackendSummary[genome],
            _ :> variantSummaryTabular[backendDispatch[genome, "Variants", {}]]
        }
    ]


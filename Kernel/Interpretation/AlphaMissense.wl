(* AlphaMissense.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === AlphaMissense interpretation ===
   AlphaMissenseScores joins a HumanGenome's carried missense SNVs against the
   AlphaMissense pathogenicity predictions and keeps the scored rows.  The
   Wolfram ResourceData["Alpha Missense"] resource (per-chromosome Datasets) is
   GRCh38/hg38, but the subject is GRCh37/hg19, so a coordinate-matched join is
   only possible against AlphaMissense's own published hg19 table
   (AlphaMissense_hg19.tsv.gz): the join key (CHROM, POS, REF, ALT) then matches
   the subject's build directly, with no liftover and its unmapped-position
   failure modes.  AlphaMissense enumerates the whole missense (chr,pos,ref,alt)
   space, so an inner join to it naturally keeps only the subject's carried SNVs
   that AlphaMissense scores as missense - we never compute a protein
   consequence ourselves.  The hg19 table is downloaded once under
   data/references/ (git-ignored) and the per-subject result is cached under
   data/<subject>/interpretations/, keyed by the AlphaMissense release. *)

$alphaMissenseSourceURL = "https://storage.googleapis.com/dm_alphamissense/AlphaMissense_hg19.tsv.gz"

alphaMissenseReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references"}]

alphaMissenseRawPath[dir_String] := FileNameJoin[{dir, "AlphaMissense_hg19.tsv.gz"}]

(* The hg19 table is a gzipped TSV whose header carries the fixed column line
   "#CHROM POS REF ALT genome uniprot_id transcript_id protein_variant
   am_pathogenicity am_class"; a failed download (an HTML error page) has no
   such line, so we accept the file only when that column row is present. *)
alphaMissenseLooksLikeTSVQ[path_String] :=
    MatchQ[
        RunProcess[{"sh", "-c",
            streamCommand[path] <> " 2>/dev/null | head -50 | awk -F '\\t' "
                <> shellEscape["$1 == \"#CHROM\" && $9 == \"am_pathogenicity\" { ok = 1 } END { exit !ok }"]}],
        KeyValuePattern["ExitCode" -> 0]
    ]

(* The DeepMind hg19 TSV carries no version meta line, so the release is keyed
   by the downloaded file's byte count - a stable content fingerprint that
   changes if AlphaMissense republishes the table. *)
alphaMissenseReleaseString[path_String] :=
    "AlphaMissense-hg19-" <> ToString[FileByteCount[path]]

AlphaMissenseScores::download = "Downloading the AlphaMissense hg19 predictions from `1`; this one-time fetch is roughly 600 MB and is cached under data/references/.";
AlphaMissenseScores::noref = "AlphaMissenseScores could not obtain the AlphaMissense hg19 reference; the download failed or curl is not on PATH.  Ensure curl is on PATH and the network is reachable.";

(* Ensure the AlphaMissense hg19 TSV exists under dir; download it if absent.
   Returns <|"Path" -> rawPath, "Release" -> releaseString|> or $Failed. *)
prepareAlphaMissenseReference[dir_String] :=
    Block[{raw, res},
        raw = alphaMissenseRawPath[dir];
        If[ FileExistsQ[raw] && alphaMissenseLooksLikeTSVQ[raw],
            Return[<|"Path" -> raw, "Release" -> alphaMissenseReleaseString[raw]|>]
        ];
        If[ ! onPathQ["curl"], Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Message[AlphaMissenseScores::download, $alphaMissenseSourceURL];
        res = RunProcess[{"sh", "-c",
            "curl -L --fail -s -o " <> shellEscape[raw] <> " " <> shellEscape[$alphaMissenseSourceURL]}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! alphaMissenseLooksLikeTSVQ[raw],
            Quiet @ DeleteFile[raw];
            Return[$Failed]
        ];
        <|"Path" -> raw, "Release" -> alphaMissenseReleaseString[raw]|>
    ]

(* -- subject-side extraction --
   Stream the subject VCF once and emit one key line per carried biallelic SNV:
   "CHROM-POS-REF-ALT<TAB>GT<TAB>Zygosity<TAB>RsID".  A row is kept only when
   REF and ALT are single bases, ALT is biallelic, and the subject's GT carries
   the ALT allele (index 1).  Missing rsIDs are emitted as "." so the trailing
   field is never empty (StringSplit drops trailing empties). *)
subjectSNVKeyAwk[] := StringJoin[
    "/^#/ { next } ",
    "$5 == \".\" { next } ",
    "$5 ~ /,/ { next } ",
    "length($4) != 1 { next } ",
    "length($5) != 1 { next } ",
    "{ ",
    "split($10, s, \":\"); gt = s[1]; ",
    "m = split(gt, a, /[\\/|]/); ",
    "carried = 0; hom = 1; ",
    "for (i = 1; i <= m; i++) { if (a[i] == \"1\") carried = 1; else hom = 0; } ",
    "if (!carried) next; ",
    "zyg = (hom ? \"Homozygous\" : \"Heterozygous\"); ",
    "rsid = ($3 == \".\" ? \".\" : $3); ",
    "print $1 \"-\" $2 \"-\" $4 \"-\" $5 \"\\t\" gt \"\\t\" zyg \"\\t\" rsid ",
    "}"
]

writeSubjectSNVKeys[subjectPath_String] :=
    Block[{file, cmd, res},
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_am_keys_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".tsv"
        }];
        cmd = streamCommand[subjectPath] <> " | awk -F '\\t' "
            <> shellEscape[subjectSNVKeyAwk[]] <> " > " <> shellEscape[file];
        res = RunProcess[{"sh", "-c", cmd}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]], Return[$Failed]];
        file
    ]

(* -- the inner join --
   Read the subject key file into an awk hash, then stream the AlphaMissense
   table once and emit a line for every AlphaMissense row whose (chr,pos,ref,alt)
   key is a carried subject SNV.  Bounded working set: only the subject's carried
   SNV keys are held in memory, and the 71M-row AlphaMissense table is scanned in
   a single streaming pass (never materialised in the kernel).  AlphaMissense
   columns: 1 CHROM, 2 POS, 3 REF, 4 ALT, 5 genome, 6 uniprot_id, 7 transcript_id,
   8 protein_variant, 9 am_pathogenicity, 10 am_class. *)
alphaMissenseJoinAwk[] := StringJoin[
    "FNR == NR { meta[$1] = $2 \"\\t\" $3 \"\\t\" $4; next } ",
    "/^#/ { next } ",
    "{ key = $1 \"-\" $2 \"-\" $3 \"-\" $4; ",
    "if (key in meta) { ",
    "print key \"\\t\" $7 \"\\t\" $8 \"\\t\" $9 \"\\t\" $10 \"\\t\" meta[key] ",
    "} }"
]

alphaMissenseColumns[] :=
    {"VariantID", "RsID", "Gene", "Transcript", "ProteinChange", "Genotype",
     "Zygosity", "AMScore", "AMClass"}

emptyAlphaMissenseTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ alphaMissenseColumns[]]}][[{}]]

(* The hg19 table labels classes benign / ambiguous / pathogenic; normalise to
   the canonical AlphaMissense labels used by the WL resource and the docs. *)
normalizeAMClass[c_] :=
    Replace[c, {
        "benign" -> "likely_benign",
        "pathogenic" -> "likely_pathogenic",
        s_String :> s
    }]

(* One join-output line to a scored missense row, or Missing when the score is
   unpar. or below minScore.  Fields:
   1 key, 2 transcript, 3 protein_variant, 4 am_pathogenicity, 5 am_class,
   6 GT, 7 Zygosity, 8 RsID. *)
alphaMissenseRow[line_String, minScore_] :=
    Block[{f, score},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 8, Return[Missing[]]];
        score = Quiet @ ToExpression[f[[4]]];
        If[ ! NumericQ[score], Return[Missing[]]];
        If[ NumericQ[minScore] && score < minScore, Return[Missing[]]];
        <|
            "VariantID" -> f[[1]],
            "RsID" -> If[ f[[8]] === ".", Missing[], f[[8]]],
            "Gene" -> Missing[],
            "Transcript" -> f[[2]],
            "ProteinChange" -> f[[3]],
            "Genotype" -> f[[6]],
            "Zygosity" -> f[[7]],
            "AMScore" -> N[score],
            "AMClass" -> normalizeAMClass[f[[5]]]
        |>
    ]

(* The testable core: takes explicit paths so the fixture tests can drive it
   without any download.  Returns a Tabular of the subject's carried missense
   SNVs that AlphaMissense scores >= minScore, sorted by AMScore descending (most
   pathogenic first).  The AlphaMissense hg19 table carries no gene symbol (only
   uniprot_id / transcript_id), so the Gene column is Missing. *)
computeAlphaMissenseScores[subjectPath_String, amPath_String, minScore_ : 0] :=
    Block[{keysFile, cmd, out, rows},
        keysFile = writeSubjectSNVKeys[subjectPath];
        If[ keysFile === $Failed, Return[$Failed]];
        cmd = streamCommand[amPath] <> " | awk -F '\\t' "
            <> shellEscape[alphaMissenseJoinAwk[]] <> " "
            <> shellEscape[keysFile] <> " -";
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        Quiet @ DeleteFile[keysFile];
        If[ ! StringQ[out], Return[$Failed]];
        rows = DeleteCases[
            Map[alphaMissenseRow[#, minScore] &, Select[StringSplit[out, "\n"], # =!= "" &]],
            _Missing
        ];
        If[ rows === {}, Return[emptyAlphaMissenseTabular[]]];
        rows = SortBy[rows, -#["AMScore"] &];
        Tabular[Map[KeyTake[#, alphaMissenseColumns[]] &, rows]]
    ]

filterAlphaMissenseByScore[t_Tabular, minScore_] :=
    If[ NumericQ[minScore] && minScore > 0,
        Select[t, NumericQ[#AMScore] && #AMScore >= minScore &],
        t
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name).  The sidecar
   stores the full (minScore 0) join so a change to the MinScore option never
   invalidates it; the operator applies MinScore after hydration. -- *)

alphaMissenseSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

alphaMissenseSidecarTabular[hg_] :=
    FileNameJoin[{alphaMissenseSidecarDir[hg], "alphamissense-scores.tabular"}]
alphaMissenseSidecarRelease[hg_] :=
    FileNameJoin[{alphaMissenseSidecarDir[hg], "alphamissense-scores.release"}]

writeAlphaMissenseSidecar[hg_, t_Tabular, release_String] :=
    Block[{dir = alphaMissenseSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[alphaMissenseSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[alphaMissenseSidecarRelease[hg], release, "Text"];
        t
    ]

loadAlphaMissenseSidecar[hg_, release_String] :=
    Block[{tf = alphaMissenseSidecarTabular[hg], rf = alphaMissenseSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= release, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[AlphaMissenseScores] = {"MinScore" -> 0, "Reference" -> Automatic}

AlphaMissenseScores[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{minScore, refDir, ref, release, amPath, cached, full, computed, ann, newAnn},
        minScore = OptionValue["MinScore"];
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> alphaMissenseReferenceDir[hg], d_String :> d}
        ];
        ref = prepareAlphaMissenseReference[refDir];
        If[ ref === $Failed, Message[AlphaMissenseScores::noref]; Return[$Failed]];
        release = ref["Release"];
        amPath = ref["Path"];
        (* No in-memory short-circuit: the slot holds the previous call's
           MinScore-filtered view, so returning it unchanged would ignore a new
           "MinScore".  Always rehydrate the full join from the sidecar and
           re-apply the filter.  Reading hg["AlphaMissenseScores"] stays instant. *)
        (* On-disk sidecar hydrate (the full join), else compute and persist. *)
        cached = loadAlphaMissenseSidecar[hg, release];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{t = computeAlphaMissenseScores[hg["Path"], amPath, 0]},
                If[ MatchQ[t, _Tabular], writeAlphaMissenseSidecar[hg, t, release]];
                t
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[AlphaMissenseScores::noref]; Return[$Failed]];
        computed = filterAlphaMissenseByScore[full, minScore];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "AlphaMissenseScores" -> computed,
            "References" -> Append[Lookup[ann, "References", <||>], "AlphaMissenseRelease" -> release]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


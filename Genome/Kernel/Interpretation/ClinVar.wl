(* ClinVar.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === ClinVar interpretation ===
   ClinVarHits joins a HumanGenome's genotype calls against the ClinVar
   Pathogenic / Likely-pathogenic release and keeps only the variants the
   subject actually carries (a non-reference GT allele that matches the
   pathogenic ALT on CHROM, POS, REF, ALT).  The reference is downloaded and
   prepared once under data/references/ (git-ignored) and cached per subject
   under data/<subject>/interpretations/, keyed by the ClinVar release. *)

$clinVarSourceURL = "https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/clinvar.vcf.gz"

(* CLNSIG include expression.  Capital-P "Pathogenic" never matches the
   lowercase "pathogenicity" of Conflicting_classifications_of_pathogenicity,
   so this keeps Pathogenic / Likely_pathogenic (and their combinations) while
   dropping Conflicting and Benign.  Verified against the GRCh37 release. *)
$clinVarPLPExpr = "INFO/CLNSIG ~ \"Pathogenic\" || INFO/CLNSIG ~ \"Likely_pathogenic\""

(* -- gnomAD population allele-frequency annotation --
   ClinVar aggregates submitted assertions and still labels some common
   polymorphisms Pathogenic / Likely-pathogenic under weak or legacy submissions,
   so a raw ClinVar hit is not proof of a rare Mendelian variant.  Each carried
   hit is therefore annotated with its gnomAD v2.1.1 (GRCh37) global allele
   frequency, letting a frequency threshold separate genuine rare variants from
   common polymorphisms.  The frequency is the joint (exome + genome) AF from the
   gnomAD GraphQL API (dataset gnomad_r2_1), looked up per variant over just the
   handful of hits a subject carries and cached under data/references/ so re-runs
   never re-query.  A variant absent from gnomAD is Missing["NotFound"] (treated
   as rare / unknown, hence kept). *)

$gnomadFreqSource = "gnomAD_r2_1"
$gnomadAPI = "https://gnomad.broadinstitute.org/api"

(* -- reference locations, derived from the subject VCF's directory so no
   absolute path is ever baked into the source -- *)

clinVarReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references"}]

clinVarPreparedPath[dir_String] := FileNameJoin[{dir, "clinvar_GRCh37_plp_chr.vcf.gz"}]
clinVarReleasePath[dir_String] := FileNameJoin[{dir, "clinvar_GRCh37_plp_chr.release"}]
clinVarRawPath[dir_String] := FileNameJoin[{dir, "clinvar.vcf.gz"}]
clinVarChrMapPath[dir_String] := FileNameJoin[{dir, "clinvar_chr_map.txt"}]

(* GRCh37 ClinVar uses 1..22,X,Y,MT; the subject uses chr1..chrX,chrY,chrM.
   The map renames the main contigs to the chr-prefixed form (MT -> chrM). *)
clinVarRenameMapText[] :=
    StringRiffle[
        Join[
            Table[ToString[c] <> "\tchr" <> ToString[c], {c, 1, 22}],
            {"X\tchrX", "Y\tchrY", "MT\tchrM"}
        ],
        "\n"
    ]

(* A real BGZF/gzip VCF makes `bcftools view -h` exit 0; an HTML error page
   from a failed download does not. *)
clinVarLooksLikeVCFQ[path_String] :=
    MatchQ[
        RunProcess[{"sh", "-c", "bcftools view -h " <> shellEscape[path] <> " >/dev/null 2>&1"}],
        KeyValuePattern["ExitCode" -> 0]
    ]

(* Read the ClinVar release from the ##fileDate meta line. *)
clinVarReleaseString[path_String] :=
    Block[{out, date},
        out = RunProcess[
            {"sh", "-c",
                "bcftools view -h " <> shellEscape[path]
                    <> " 2>/dev/null | grep -i '^##fileDate=' | head -1"},
            "StandardOutput"
        ];
        date = If[ StringQ[out],
            StringTrim @ StringReplace[out, StartOfString ~~ "##fileDate=" -> "", IgnoreCase -> True],
            ""
        ];
        If[ date === "", "ClinVar-unknown", "ClinVar-" <> date]
    ]

ClinVarHits::download = "Downloading the ClinVar GRCh37 reference VCF from `1`; this one-time fetch is roughly 150 MB and is cached under data/references/.";
ClinVarHits::noref = "ClinVarHits could not obtain the prepared ClinVar reference; the download or the bcftools / tabix preparation step failed.  Ensure bcftools, tabix and curl are on PATH and the network is reachable.";

(* Ensure a prepared P/LP, chr-renamed, bgzipped + tabixed ClinVar VCF exists
   under dir; download and build it if absent.  Returns
   <|"Path" -> preparedPath, "Release" -> releaseString|> or $Failed. *)
prepareClinVarReference[dir_String] :=
    Block[{prepared, releaseFile, raw, mapFile, rel, res},
        prepared = clinVarPreparedPath[dir];
        releaseFile = clinVarReleasePath[dir];
        (* Already prepared: serve the cached release string. *)
        If[ FileExistsQ[prepared] && FileExistsQ[releaseFile] && FileExistsQ[prepared <> ".tbi"],
            Return[<|"Path" -> prepared, "Release" -> StringTrim @ Import[releaseFile, "Text"]|>]
        ];
        If[ ! onPathQ["bcftools"] || ! onPathQ["tabix"] || ! onPathQ["curl"],
            Return[$Failed]
        ];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        raw = clinVarRawPath[dir];
        If[ ! FileExistsQ[raw] || ! clinVarLooksLikeVCFQ[raw],
            Message[ClinVarHits::download, $clinVarSourceURL];
            res = RunProcess[{"sh", "-c",
                "curl -L --fail -s -o " <> shellEscape[raw] <> " " <> shellEscape[$clinVarSourceURL]
                    <> " && curl -L --fail -s -o " <> shellEscape[raw <> ".tbi"]
                    <> " " <> shellEscape[$clinVarSourceURL <> ".tbi"]}];
            If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! clinVarLooksLikeVCFQ[raw],
                Quiet @ DeleteFile[raw];
                Return[$Failed]
            ]
        ];
        rel = clinVarReleaseString[raw];
        mapFile = clinVarChrMapPath[dir];
        Export[mapFile, clinVarRenameMapText[], "Text"];
        (* Filter to P/LP, rename contigs to the chr-prefixed form, bgzip. *)
        res = RunProcess[{"sh", "-c",
            "bcftools view -i " <> shellEscape[$clinVarPLPExpr] <> " " <> shellEscape[raw] <> " -Ou"
                <> " | bcftools annotate --rename-chrs " <> shellEscape[mapFile]
                <> " -Oz -o " <> shellEscape[prepared]}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! FileExistsQ[prepared],
            Return[$Failed]
        ];
        RunProcess[{"sh", "-c", "tabix -p vcf -f " <> shellEscape[prepared]}];
        Export[releaseFile, rel, "Text"];
        <|"Path" -> prepared, "Release" -> rel|>
    ]

(* -- genotype-aware intersection --
   The subject read is restricted to ClinVar P/LP positions via the tabix
   index (bcftools view -R), so the whole multi-gigabyte file is never
   scanned.  Only the subject's carried non-reference alleles at those
   positions are then matched allele-exactly against the ClinVar records. *)

clinVarColumns[] :=
    {"VariantID", "RsID", "Gene", "ClinicalSignificance", "ReviewStatus",
     "Condition", "VCVAccession", "Genotype", "Zygosity",
     "PopulationAF", "FrequencySource", "ImputationQuality"}

emptyClinVarTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ clinVarColumns[]]}][[{}]]

(* A GT subfield string to an allele index (Missing for "." / non-numeric). *)
clinVarAlleleIndex[s_String] :=
    If[ StringMatchQ[s, DigitCharacter ..], FromDigits[s], Missing[]]

(* Zygosity from the parsed GT alleles for a given carried allele index. *)
clinVarZygosity[parts_List, idx_Integer] :=
    Block[{s = ToString[idx]},
        Which[
            Length[parts] >= 2 && AllTrue[parts, # === s &], "Homozygous",
            Length[parts] === 1 && First[parts] === s, "Homozygous",
            True, "Heterozygous"
        ]
    ]

(* One subject VCF row to the list of ClinVar-candidate alleles it carries.
   A row on a 0/0, 0|0 or ./. call yields no candidates.  The subject row's own
   imputation INFO (R2, IMPUTED, TYPED, TYPED_ONLY) is carried through so the
   hit can report its imputation quality with no extra data source. *)
subjectCarriedAlleles[line_String] :=
    Block[{f, chrom, pos, id, ref, altList, info, r2, imputed, typed, typedOnly, gt, gtParts, altIdxs},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 10, Return[{}]];
        {chrom, pos, id, ref} = f[[1 ;; 4]];
        altList = If[ f[[5]] === ".", {}, StringSplit[f[[5]], ","]];
        info = parseInfo[f[[8]]];
        r2 = infoNumeric[info, "R2"];
        imputed = infoFlag[info, "IMPUTED"];
        typed = infoFlag[info, "TYPED"];
        typedOnly = infoFlag[info, "TYPED_ONLY"];
        gt = First @ StringSplit[f[[10]], ":"];
        gtParts = StringSplit[gt, "/" | "|"];
        altIdxs = DeleteDuplicates @ Select[
            Map[clinVarAlleleIndex, gtParts],
            IntegerQ[#] && # >= 1 &
        ];
        Map[
            idx |-> If[ idx <= Length[altList],
                <|
                    "Key" -> chrom <> "-" <> pos <> "-" <> ref <> "-" <> altList[[idx]],
                    "CHROM" -> chrom,
                    "POS" -> FromDigits[pos],
                    "GT" -> gt,
                    "Zygosity" -> clinVarZygosity[gtParts, idx],
                    "RsID" -> Replace[id, "." -> Missing[]],
                    "R2" -> r2,
                    "IMPUTED" -> imputed,
                    "TYPED" -> typed,
                    "TYPED_ONLY" -> typedOnly
                |>,
                Nothing
            ],
            altIdxs
        ]
    ]

(* GENEINFO is "SYMBOL:ID" (multiple genes joined by "|"); take the first
   gene symbol. *)
clinVarGene[info_Association] :=
    Block[{gi = Lookup[info, "GENEINFO", Missing[]]},
        If[ StringQ[gi],
            First @ StringSplit[First @ StringSplit[gi, "|"], ":"],
            Missing[]
        ]
    ]

(* ClinVar encodes spaces as underscores; decode for the display columns. *)
clinVarDecode[v_] := If[ StringQ[v], StringReplace[v, "_" -> " "], Missing[]]

clinVarConditions[v_] :=
    If[ StringQ[v],
        StringRiffle[Map[StringReplace[#, "_" -> " "] &, StringSplit[v, "|"]], "; "],
        Missing[]
    ]

(* Build the VCV accession from the ClinVar Variation ID (the VCF ID column):
   VCV + the id zero-padded to 9 digits. *)
clinVarVCV[vid_String] :=
    If[ StringMatchQ[vid, DigitCharacter ..], "VCV" <> StringPadLeft[vid, 9, "0"], vid]

clinVarRS[v_] := If[ StringQ[v], "rs" <> First[StringSplit[v, "|"]], Missing[]]

(* One prepared-ClinVar record to (key -> annotation) rules, one per ALT. *)
clinVarRecordEntries[line_String] :=
    Block[{f, chrom, pos, vid, ref, altList, info, ann},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 8, Return[{}]];
        {chrom, pos, vid, ref} = f[[1 ;; 4]];
        altList = If[ f[[5]] === ".", {}, StringSplit[f[[5]], ","]];
        info = parseInfo[f[[8]]];
        ann = <|
            "Gene" -> clinVarGene[info],
            "CLNSIG" -> clinVarDecode[Lookup[info, "CLNSIG", Missing[]]],
            "CLNREVSTAT" -> clinVarDecode[Lookup[info, "CLNREVSTAT", Missing[]]],
            "CLNDN" -> clinVarConditions[Lookup[info, "CLNDN", Missing[]]],
            "VCV" -> clinVarVCV[vid],
            "RS" -> clinVarRS[Lookup[info, "RS", Missing[]]]
        |>;
        Map[alt |-> (chrom <> "-" <> pos <> "-" <> ref <> "-" <> alt) -> ann, altList]
    ]

(* Prefer the subject's own rsID when it is one; otherwise the ClinVar RS. *)
clinVarChooseRsID[subjRs_, clinvarRs_] :=
    Which[
        StringQ[subjRs] && StringStartsQ[subjRs, "rs"], subjRs,
        StringQ[clinvarRs], clinvarRs,
        StringQ[subjRs], subjRs,
        True, Missing[]
    ]

(* Stream the subject calls at ClinVar P/LP positions (index-restricted). *)
streamSubjectAtClinVar[subjectPath_String, preparedPath_String] :=
    Block[{out},
        out = RunProcess[
            {"sh", "-c",
                "bcftools view -R " <> shellEscape[preparedPath] <> " -H " <> shellEscape[subjectPath]},
            "StandardOutput"
        ];
        If[ ! StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

(* Restrict the ClinVar read to just the subject's carried positions. *)
streamClinVarAtRegions[preparedPath_String, regionsFile_String] :=
    Block[{out},
        out = RunProcess[
            {"sh", "-c",
                "bcftools view -R " <> shellEscape[regionsFile] <> " -H " <> shellEscape[preparedPath]},
            "StandardOutput"
        ];
        If[ ! StringQ[out], Return[{}]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

writeRegionsFile[candidates_List] :=
    Block[{pairs, file},
        pairs = SortBy[
            DeleteDuplicates @ Map[{#["CHROM"], #["POS"]} &, candidates],
            {chromKey[#[[1]]], #[[2]]} &
        ];
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_clinvar_regions_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".txt"
        }];
        Export[file, StringRiffle[Map[#[[1]] <> "\t" <> ToString[#[[2]]] &, pairs], "\n"], "Text"];
        file
    ]

(* -- imputation-quality and population-frequency annotation --
   The imputation quality is read straight from the subject row's own INFO
   (TYPED / IMPUTED / R2), so it needs no external source.  The population
   frequency comes from an allele-frequency map (VariantID -> AF) that the
   operator builds from the gnomAD cache + API; the fixture tests pass an
   explicit map so the annotation is exercised without any network. *)

imputationQuality[row_Association] :=
    Block[{
        typed = TrueQ[row["TYPED"]] || TrueQ[row["TYPED_ONLY"]],
        imputed = TrueQ[row["IMPUTED"]],
        r2 = Lookup[row, "R2", Missing[]]
    },
        If[ typed || ! imputed,
            "Directly sequenced",
            "Imputed R2=" <> If[NumericQ[r2], ToString[r2], "NA"]
        ]
    ]

(* Attach PopulationAF (from afMap, Missing["NotFound"] when the source has no
   record), the FrequencySource label, and the ImputationQuality derived from the
   subject row.  Pure - the fixture tests drive it with a mock afMap. *)
annotateVariantFrequency[hitRows_List, afMap_Association, source_String] :=
    Map[
        row |-> <|
            row,
            "PopulationAF" -> Lookup[afMap, Lookup[row, "VariantID", Missing[]], Missing["NotFound"]],
            "FrequencySource" -> source,
            "ImputationQuality" -> imputationQuality[row]
        |>,
        hitRows
    ]

(* -- gnomAD frequency cache (a small keyed TSV under data/references/) and the
   per-variant GraphQL lookup that fills it -- *)

gnomadCachePath[dir_String] := FileNameJoin[{dir, "gnomad_af_" <> $gnomadFreqSource <> ".tsv"}]

(* "chr12-48299826-T-C" -> the gnomAD v2 id "12-48299826-T-C" (chr-prefix
   stripped; MT / Y variants simply resolve to NotFound in gnomAD v2). *)
gnomadVariantId[vid_String] := StringReplace[vid, StartOfString ~~ "chr" -> ""]

loadGnomadCache[file_String] :=
    If[ ! FileExistsQ[file],
        <||>,
        Block[{lines = Quiet @ Import[file, {"Text", "Lines"}]},
            If[ ! ListQ[lines], Return[<||>]];
            Association @ Map[
                line |-> Block[{p = StringSplit[line, "\t"]},
                    Which[
                        Length[p] < 2, Nothing,
                        p[[2]] === "NotFound", p[[1]] -> Missing["NotFound"],
                        True, p[[1]] -> Quiet @ Replace[
                            ToExpression[p[[2]]],
                            {n_ ? NumericQ :> n, _ -> Missing["NotFound"]}
                        ]
                    ]
                ],
                Select[lines, StringTrim[#] =!= "" &]
            ]
        ]
    ]

writeGnomadCache[file_String, map_Association] :=
    Export[
        file,
        StringRiffle[
            KeyValueMap[#1 <> "\t" <> If[MissingQ[#2], "NotFound", ToString[#2, InputForm]] &, map],
            "\n"
        ],
        "Text"
    ]

(* The joint (exome + genome) allele frequency from a gnomAD variant record,
   matching gnomAD's headline number, or Missing["NotFound"] when the variant is
   absent (null) or carries no called alleles. *)
gnomadJointAF[v_] :=
    If[ ! AssociationQ[v],
        Missing["NotFound"],
        Block[{g = Lookup[v, "genome", Null], e = Lookup[v, "exome", Null], ac, an},
            ac = If[AssociationQ[g], Lookup[g, "ac", 0], 0] + If[AssociationQ[e], Lookup[e, "ac", 0], 0];
            an = If[AssociationQ[g], Lookup[g, "an", 0], 0] + If[AssociationQ[e], Lookup[e, "an", 0], 0];
            If[ NumericQ[an] && an > 0 && NumericQ[ac], N[ac / an], Missing["NotFound"]]
        ]
    ]

(* One gnomAD GraphQL request for a chunk of variant ids, each aliased so a
   single round trip resolves the whole chunk.  Returns <|VariantID -> AF|> for
   the chunk, or <||> when the HTTP call fails so the ids stay uncached and are
   retried on a later, online run.  An id absent from gnomAD resolves to
   Missing["NotFound"] (a definitive answer, so it is cached). *)
queryGnomadChunk[vids_List] :=
    Block[{query, r, j, data},
        query = "{ " <> StringRiffle[
            MapIndexed[
                "v" <> ToString[First[#2]] <> ": variant(variantId: \""
                    <> gnomadVariantId[#1]
                    <> "\", dataset: gnomad_r2_1) { genome { ac an } exome { ac an } }" &,
                vids
            ],
            " "
        ] <> " }";
        r = Quiet @ URLRead[
            HTTPRequest[$gnomadAPI, <|
                "Method" -> "POST",
                "ContentType" -> "application/json",
                "Body" -> ExportString[<|"query" -> query|>, "JSON"]
            |>],
            Interactive -> False
        ];
        If[ ! MatchQ[r, _HTTPResponse] || r["StatusCode"] =!= 200, Return[<||>]];
        j = Quiet @ Developer`ReadRawJSONString[r["Body"]];
        If[ ! AssociationQ[j] || ! AssociationQ[Lookup[j, "data", Null]], Return[<||>]];
        data = j["data"];
        Association @ MapIndexed[
            #1 -> gnomadJointAF[Lookup[data, "v" <> ToString[First[#2]], Null]] &,
            vids
        ]
    ]

(* Resolve the population AF for every variant id, reading the on-disk cache and
   querying gnomAD only for the ids not yet cached, then persisting the result.
   Returns the VariantID -> AF map (never $Failed: an unreachable API simply
   leaves the missing ids out, so they annotate as Missing["NotFound"]). *)
fetchGnomadFrequencies[dir_String, variantIds_List] :=
    Block[{cacheFile, cached, missing, fetched, updated},
        cacheFile = gnomadCachePath[dir];
        cached = loadGnomadCache[cacheFile];
        missing = DeleteDuplicates @ Select[variantIds, StringQ[#] && ! KeyExistsQ[cached, #] &];
        fetched = If[ missing === {},
            <||>,
            Join @@ Map[queryGnomadChunk, batchesOf[missing, 100]]
        ];
        updated = Join[cached, fetched];
        If[ fetched =!= <||>,
            Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
            writeGnomadCache[cacheFile, updated]
        ];
        updated
    ]

(* -- genotype-aware intersection, split so the operator can pull the variant ids
   for the frequency lookup before the annotation -- *)

(* The base join: the P/LP hits the subject carries, each row carrying the ClinVar
   annotation plus the subject's own imputation INFO, sorted by chromosome then
   position.  Returns the row list ({} when there is no hit) or $Failed. *)
clinVarHitRows[subjectPath_String, preparedPath_String] :=
    Block[{subjRows, candidates, regionsFile, clinvarRows, annMap, hits},
        subjRows = streamSubjectAtClinVar[subjectPath, preparedPath];
        If[ subjRows === $Failed, Return[$Failed]];
        candidates = Flatten @ Map[subjectCarriedAlleles, subjRows];
        If[ candidates === {}, Return[{}]];
        regionsFile = writeRegionsFile[candidates];
        clinvarRows = streamClinVarAtRegions[preparedPath, regionsFile];
        Quiet @ DeleteFile[regionsFile];
        annMap = Association @ Flatten @ Map[clinVarRecordEntries, clinvarRows];
        hits = Map[
            cand |-> Block[{ann = Lookup[annMap, cand["Key"], Missing[]]},
                If[ MissingQ[ann],
                    Nothing,
                    <|
                        "VariantID" -> cand["Key"],
                        "RsID" -> clinVarChooseRsID[cand["RsID"], ann["RS"]],
                        "Gene" -> ann["Gene"],
                        "ClinicalSignificance" -> ann["CLNSIG"],
                        "ReviewStatus" -> ann["CLNREVSTAT"],
                        "Condition" -> ann["CLNDN"],
                        "VCVAccession" -> ann["VCV"],
                        "Genotype" -> cand["GT"],
                        "Zygosity" -> cand["Zygosity"],
                        "CHROM" -> cand["CHROM"],
                        "POS" -> cand["POS"],
                        "R2" -> cand["R2"],
                        "IMPUTED" -> cand["IMPUTED"],
                        "TYPED" -> cand["TYPED"],
                        "TYPED_ONLY" -> cand["TYPED_ONLY"]
                    |>
                ]
            ],
            candidates
        ];
        SortBy[hits, {chromKey[#["CHROM"]], #["POS"]} &]
    ]

(* The annotated hit rows to the display Tabular (only the display columns). *)
buildClinVarTabular[rows_List] :=
    If[ rows === {},
        emptyClinVarTabular[],
        Tabular[Map[KeyTake[#, clinVarColumns[]] &, rows]]
    ]

(* Drop hits whose population frequency exceeds maxAF; Automatic (or any
   non-numeric value) keeps all hits, and a Missing AF is treated as rare /
   unknown and kept.  A view filter re-applied on every call. *)
clinVarApplyMaxAF[t_Tabular, maxAF_] :=
    If[ NumericQ[maxAF],
        Select[t, MissingQ[#PopulationAF] || (NumericQ[#PopulationAF] && #PopulationAF <= maxAF) &],
        t
    ]

(* The testable core: takes explicit paths and an optional VariantID -> AF map so
   the fixture tests can drive the join and the annotation without any download.
   Returns the annotated Tabular of the P/LP hits the subject carries. *)
computeClinVarHits[subjectPath_String, preparedPath_String, samples_List,
    afMap_Association : <||>, source_String : $gnomadFreqSource] :=
    Block[{rows = clinVarHitRows[subjectPath, preparedPath]},
        If[ rows === $Failed, Return[$Failed]];
        buildClinVarTabular @ annotateVariantFrequency[rows, afMap, source]
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name) -- *)

clinVarSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

clinVarSidecarTabular[hg_] := FileNameJoin[{clinVarSidecarDir[hg], "clinvar-hits.tabular"}]
clinVarSidecarRelease[hg_] := FileNameJoin[{clinVarSidecarDir[hg], "clinvar-hits.release"}]

writeClinVarSidecar[hg_, t_Tabular, marker_String] :=
    Block[{dir = clinVarSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[clinVarSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[clinVarSidecarRelease[hg], marker, "Text"];
        t
    ]

loadClinVarSidecar[hg_, marker_String] :=
    Block[{tf = clinVarSidecarTabular[hg], rf = clinVarSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= marker, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[ClinVarHits] = {"Reference" -> Automatic, "MaxPopulationAF" -> Automatic}

ClinVarHits[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{refDir, ref, release, prepared, marker, cached, full, filtered, ann, newAnn},
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> clinVarReferenceDir[hg], d_String :> d}
        ];
        ref = prepareClinVarReference[refDir];
        If[ ref === $Failed, Message[ClinVarHits::noref]; Return[$Failed]];
        release = ref["Release"];
        prepared = ref["Path"];
        (* The sidecar marker keys on the release AND the frequency-source version,
           so a new release or a changed frequency source invalidates the cached
           annotation.  No in-memory short-circuit: the slot holds the previous
           call's MaxPopulationAF-filtered view, so returning it unchanged would
           ignore a new "MaxPopulationAF".  Always rehydrate the full (all-AF)
           result and re-apply the frequency filter; reading hg["ClinVarHits"]
           stays instant. *)
        marker = release <> "|" <> $gnomadFreqSource;
        cached = loadClinVarSidecar[hg, marker];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{rows = clinVarHitRows[hg["Path"], prepared], afMap, t},
                If[ rows === $Failed,
                    $Failed,
                    afMap = fetchGnomadFrequencies[refDir,
                        DeleteDuplicates @ Cases[Lookup[rows, "VariantID", Missing[]], _String]];
                    t = buildClinVarTabular @ annotateVariantFrequency[rows, afMap, $gnomadFreqSource];
                    writeClinVarSidecar[hg, t, marker];
                    t
                ]
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[ClinVarHits::noref]; Return[$Failed]];
        filtered = clinVarApplyMaxAF[full, OptionValue["MaxPopulationAF"]];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "ClinVarHits" -> filtered,
            "References" -> Append[Lookup[ann, "References", <||>], "ClinVarRelease" -> release]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


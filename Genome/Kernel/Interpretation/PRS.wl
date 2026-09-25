(* PRS.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === polygenic risk score interpretation ===
   PolygenicRiskScore scores a HumanGenome against a published PGS Catalog
   scoring file and records the result in the "PRS" slot (an Association keyed
   by PGS Catalog ID, so scores for several traits accumulate).  The score for
   one trait is sum over the used scoring variants of (effect-allele dosage) *
   (effect weight).  A raw score is meaningless without a reference
   distribution, so we also report a population percentile from the analytic
   normal approximation: under Hardy-Weinberg and an independent-variant
   assumption the population score has mean = sum 2 * EAF * w and variance =
   sum 2 * EAF * (1 - EAF) * w^2, and the subject percentile is the normal CDF
   at the subject's score.  Effect-allele frequencies (EAF) come from the
   scoring file's allelefrequency_effect column when present, otherwise from
   the subject's own imputation-panel INFO/AF (trusted only on imputed / typed
   rows).  When no frequency is available the raw score is still reported and
   the percentile is Missing["NoReference"].  The GRCh37 harmonized scoring
   file is downloaded once under data/references/pgs/ (git-ignored); the
   per-subject PRS map is cached under data/<subject>/interpretations/prs.wxf,
   keyed by the PGS Catalog release. *)

$pgsScoreURLBase = "https://ftp.ebi.ac.uk/pub/databases/spot/pgs/scores/"
$pgsRestInfoURL = "https://www.pgscatalog.org/rest/info"

(* Project-maintained trait -> PGS Catalog ID map so users need not memorise
   PGS IDs.  Each ID is a reputable, moderate-size published score that
   harmonizes to GRCh37 (million-variant genome-wide scores are avoided in this
   first version to keep the compute bounded; a raw PGS ID with the
   "MaxVariants" option can still score them).  Keys are lower-cased trait
   names; $prsTraitEFO maps EFO / MONDO trait ids to the same picks. *)
$prsTraitMap = <|
    "ldl cholesterol" -> "PGS000065",
    "hdl cholesterol" -> "PGS000064",
    "triglycerides" -> "PGS000066",
    "total cholesterol" -> "PGS000062",
    "type 2 diabetes" -> "PGS000036",
    "bmi" -> "PGS000034",
    "body mass index" -> "PGS000034",
    "coronary artery disease" -> "PGS000012",
    "height" -> "PGS000297",
    "breast cancer" -> "PGS000001",
    "prostate cancer" -> "PGS003419",
    "alzheimer's disease" -> "PGS000026",
    "alzheimer disease" -> "PGS000026",
    "atrial fibrillation" -> "PGS000016"
|>

$prsTraitEFO = <|
    "EFO_0004611" -> "PGS000065",
    "EFO_0004612" -> "PGS000064",
    "EFO_0004530" -> "PGS000066",
    "EFO_0004574" -> "PGS000062",
    "MONDO_0005148" -> "PGS000036",
    "EFO_0004340" -> "PGS000034",
    "MONDO_0005010" -> "PGS000012",
    "EFO_0004339" -> "PGS000297",
    "MONDO_0004989" -> "PGS000001",
    "MONDO_0008315" -> "PGS003419",
    "MONDO_0004975" -> "PGS000026",
    "MONDO_0004981" -> "PGS000016"
|>

pgsIDQ[s_String] := StringMatchQ[s, "PGS" ~~ DigitCharacter ..]

efoIDQ[s_String] := StringMatchQ[s, LetterCharacter .. ~~ "_" ~~ WordCharacter ..]

(* Resolve a spec - a raw PGS ID (used directly), an EFO / MONDO trait id, or a
   human trait name - to a canonical PGS Catalog ID, or Missing when unknown. *)
resolvePGSID[spec_String] :=
    Which[
        pgsIDQ[spec], ToUpperCase[spec],
        efoIDQ[spec] && KeyExistsQ[$prsTraitEFO, ToUpperCase[spec]], $prsTraitEFO[ToUpperCase[spec]],
        KeyExistsQ[$prsTraitMap, ToLowerCase[StringTrim[spec]]], $prsTraitMap[ToLowerCase[StringTrim[spec]]],
        True, Missing["UnknownTrait"]
    ]

(* -- reference locations, derived from the subject VCF's directory so no
   absolute path is ever baked into the source -- *)

pgsReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references", "pgs"}]

pgsScoreLocalPath[dir_String, pgsid_String] :=
    FileNameJoin[{dir, pgsid <> "_hmPOS_GRCh37.txt.gz"}]

pgsScoreURL[pgsid_String] :=
    $pgsScoreURLBase <> pgsid <> "/ScoringFiles/Harmonized/" <> pgsid <> "_hmPOS_GRCh37.txt.gz"

pgsCatalogVersionPath[dir_String] := FileNameJoin[{dir, "pgs_catalog.version"}]

(* A real harmonized scoring file starts with a #-prefixed metadata block that
   includes #pgs_id= and has a column header row naming effect_weight; a failed
   download (an HTML error page) has neither. *)
pgsLooksLikeScoreQ[path_String] :=
    MatchQ[
        RunProcess[{"sh", "-c",
            streamCommand[path] <> " 2>/dev/null | head -60 | awk "
                <> shellEscape["/^#pgs_id=/ { hp = 1 } /effect_weight/ { hc = 1 } END { exit !(hp && hc) }"]}],
        KeyValuePattern["ExitCode" -> 0]
    ]

PolygenicRiskScore::download = "Downloading the PGS Catalog harmonized GRCh37 scoring file for `1` from `2`; this one-time fetch is cached under data/references/pgs/.";
PolygenicRiskScore::noref = "PolygenicRiskScore could not obtain the PGS Catalog scoring file for `1`; the download failed or curl is not on PATH.  Ensure curl is on PATH and the network is reachable.";
PolygenicRiskScore::unknownTrait = "`1` is neither a PGS Catalog ID (PGS######) nor a known trait; supply a raw PGS ID, an EFO / MONDO trait id, or one of the $PRSTraitMap names: `2`.";
PolygenicRiskScore::truncated = "The score `1` has `2` variants; scoring only the first `3` (the \"MaxVariants\" cap).";

(* Ensure the harmonized GRCh37 scoring file for pgsid exists under dir;
   download it if absent.  Returns the local path or $Failed. *)
preparePGSScoreFile[dir_String, pgsid_String] :=
    Block[{local, res},
        local = pgsScoreLocalPath[dir, pgsid];
        If[ FileExistsQ[local] && pgsLooksLikeScoreQ[local], Return[local]];
        If[ ! onPathQ["curl"], Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Message[PolygenicRiskScore::download, pgsid, pgsScoreURL[pgsid]];
        res = RunProcess[{"sh", "-c",
            "curl -L --fail -s -o " <> shellEscape[local] <> " " <> shellEscape[pgsScoreURL[pgsid]]}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! pgsLooksLikeScoreQ[local],
            Quiet @ DeleteFile[local];
            Return[$Failed]
        ];
        local
    ]

(* The PGS Catalog release date keys the per-subject PRS cache (published
   scores are immutable, so a new release only invalidates the cache on the
   rare occasion the Catalog reissues).  Fetched once from the REST /info
   endpoint and cached; "PGSCatalog-unknown" when the endpoint is unreachable. *)
pgsCatalogVersion[dir_String] :=
    Block[{vf = pgsCatalogVersionPath[dir], r, date},
        If[ FileExistsQ[vf], Return[StringTrim @ Import[vf, "Text"]]];
        r = Quiet @ URLRead[HTTPRequest[$pgsRestInfoURL], Interactive -> False];
        date = If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200,
            Block[{j = Quiet @ Developer`ReadRawJSONString[r["Body"]]},
                If[ AssociationQ[j], Lookup[Lookup[j, "latest_release", <||>], "date", Missing[]], Missing[]]
            ],
            Missing[]
        ];
        If[ StringQ[date],
            Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
            Quiet @ Export[vf, "PGSCatalog-" <> date, "Text"];
            "PGSCatalog-" <> date,
            "PGSCatalog-unknown"
        ]
    ]

(* -- scoring-file parsing --
   GRCh37 harmonized PGS uses non-chr contig names (1..22, X, Y); the subject
   uses chr-prefixed contigs, so rename for the join. *)
prsChrName[c_String] :=
    Which[
        StringStartsQ[c, "chr"], c,
        c === "MT" || c === "M", "chrM",
        True, "chr" <> c
    ]

(* Column-index map from the tab-separated PGS column header line.  Layouts
   differ across scores, so every column is addressed by name. *)
pgsColumnIndex[headerLine_String] :=
    Association @ MapIndexed[#1 -> First[#2] &, StringSplit[headerLine, "\t"]]

pgsMetaValue[metaLines_List, key_String] :=
    Block[{m = FirstCase[metaLines,
        l_ /; StringStartsQ[l, "#" <> key <> "="] :> StringDrop[l, StringLength[key] + 2]]},
        If[ StringQ[m], StringTrim[m], Missing[]]
    ]

pgsField[f_List, i_Integer] := If[ i >= 1 && i <= Length[f], f[[i]], ""]

(* One scoring-file data row to a variant record, or Missing when the weight is
   non-numeric or the harmonized position is absent (unmapped).  effect_allele
   / other_allele / effect_weight are always present; the harmonized hm_chr /
   hm_pos give the GRCh37 join key; allelefrequency_effect (effect-allele
   frequency) is used when the file carries it.  Indel / multiallelic alleles
   are kept here and skipped later so they still count toward NVariantsExpected. *)
pgsVariantRow[f_List, iEA_, iOA_, iW_, iChr_, iPos_, iRs_, iAF_] :=
    Block[{w, chr, pos, af, rs},
        w = Quiet @ ToExpression[pgsField[f, iW]];
        If[ ! NumericQ[w], Return[Missing[]]];
        chr = pgsField[f, iChr];
        pos = pgsField[f, iPos];
        If[ chr === "" || ! StringMatchQ[pos, DigitCharacter ..], Return[Missing[]]];
        af = If[ iAF >= 1,
            Block[{v = Quiet @ ToExpression[pgsField[f, iAF]]}, If[ NumericQ[v], N[v], Missing[]]],
            Missing[]
        ];
        rs = pgsField[f, iRs];
        <|
            "Chr" -> prsChrName[chr],
            "Pos" -> FromDigits[pos],
            "EA" -> ToUpperCase @ pgsField[f, iEA],
            "OA" -> ToUpperCase @ pgsField[f, iOA],
            "W" -> N[w],
            "EAF" -> af,
            "RsID" -> If[ StringMatchQ[rs, "rs" ~~ DigitCharacter ..], rs, Missing[]]
        |>
    ]

(* Read a harmonized PGS scoring file into <|"Meta" -> ..., "Variants" -> ...|>
   (or $Failed).  The header comment block yields the metadata; the first
   non-# line is the column header, the rest are variant rows. *)
readPGSScoringFile[path_String] :=
    Block[{out, lines, metaLines, headerLine, dataLines, idx,
           iEA, iOA, iW, iChr, iPos, iRs, iAF, meta, variants},
        out = RunProcess[{"sh", "-c", streamCommand[path]}, "StandardOutput"];
        If[ ! StringQ[out], Return[$Failed]];
        lines = Select[StringSplit[out, "\n"], # =!= "" &];
        metaLines = Select[lines, StringStartsQ[#, "#"] &];
        dataLines = Select[lines, ! StringStartsQ[#, "#"] &];
        If[ dataLines === {}, Return[$Failed]];
        headerLine = First[dataLines];
        idx = pgsColumnIndex[headerLine];
        iEA = Lookup[idx, "effect_allele", 0];
        iOA = Lookup[idx, "other_allele", Lookup[idx, "hm_inferOtherAllele", 0]];
        iW = Lookup[idx, "effect_weight", 0];
        iChr = Lookup[idx, "hm_chr", Lookup[idx, "chr_name", 0]];
        iPos = Lookup[idx, "hm_pos", Lookup[idx, "chr_position", 0]];
        iRs = Lookup[idx, "hm_rsID", Lookup[idx, "rsID", 0]];
        iAF = Lookup[idx, "allelefrequency_effect", 0];
        If[ iEA === 0 || iW === 0 || iChr === 0 || iPos === 0, Return[$Failed]];
        meta = <|
            "PGSID" -> pgsMetaValue[metaLines, "pgs_id"],
            "Trait" -> pgsMetaValue[metaLines, "trait_reported"],
            "WeightType" -> pgsMetaValue[metaLines, "weight_type"],
            "VariantsNumber" -> pgsMetaValue[metaLines, "variants_number"],
            "Build" -> pgsMetaValue[metaLines, "HmPOS_build"]
        |>;
        variants = DeleteCases[
            Map[
                pgsVariantRow[StringSplit[#, "\t"], iEA, iOA, iW, iChr, iPos, iRs, iAF] &,
                Rest[dataLines]
            ],
            _Missing
        ];
        <|"Meta" -> meta, "Variants" -> variants|>
    ]

(* -- subject-side genotype read at the scoring positions -- *)

prsRegionsFile[variants_List] :=
    Block[{pairs, file},
        pairs = SortBy[
            DeleteDuplicates @ Map[{#["Chr"], #["Pos"]} &, variants],
            {chromKey[#[[1]]], #[[2]]} &
        ];
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_prs_regions_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".txt"
        }];
        Export[file, StringRiffle[Map[#[[1]] <> "\t" <> ToString[#[[2]]] &, pairs], "\n"], "Text"];
        file
    ]

(* awk that reduces a subject VCF row to a compact "key<TAB>ref<TAB>alt<TAB>
   gt<TAB>af<TAB>panel" line: key is "CHROM-POS", gt is the first FORMAT
   subfield, af is INFO/AF (alternate-allele frequency), and panel is 1 when
   the row carries MAF or R2 (an imputed / typed Minimac row whose AF is a
   genuine panel frequency; a plain GATK call has neither, and its AF = AC/AN
   is not a population frequency).  Doing the field extraction in awk keeps the
   per-row cost off the kernel, so a 170k-variant score parses in seconds. *)
prsExtractAwkBody[] := StringJoin[
    "{ split($10, s, \":\"); gt = s[1]; af = \".\"; panel = 0; ",
    "n = split($8, info, \";\"); ",
    "for (i = 1; i <= n; i++) { p = info[i]; ",
    "if (substr(p, 1, 3) == \"AF=\") af = substr(p, 4); ",
    "else if (substr(p, 1, 4) == \"MAF=\" || substr(p, 1, 3) == \"R2=\") panel = 1 } ",
    "print $1 \"-\" $2 \"\\t\" $4 \"\\t\" $5 \"\\t\" gt \"\\t\" af \"\\t\" panel }"
]

prsJoinExtractAwk[] :=
    StringJoin[
        "FNR == NR { want[$1 \"-\" $2] = 1; next } /^#/ { next } (($1 \"-\" $2) in want) ",
        prsExtractAwkBody[]
    ]

prsParseCompactRow[line_String] :=
    Block[{f = StringSplit[line, "\t"], af},
        If[ Length[f] < 6, Return[Missing[]]];
        af = If[ f[[5]] === ".",
            Missing[],
            Block[{v = Quiet @ ToExpression[f[[5]]]}, If[ NumericQ[v], v, Missing[]]]
        ];
        <|
            "Key" -> f[[1]],
            "REF" -> ToUpperCase[f[[2]]],
            "ALT" -> If[ f[[3]] === ".", {}, ToUpperCase /@ StringSplit[f[[3]], ","]],
            "GTParts" -> StringSplit[f[[4]], "/" | "|"],
            "AF" -> af,
            "PanelQ" -> (f[[6]] === "1")
        |>
    ]

(* Read the subject's calls at the scoring positions.  The tabix fast path
   (bcftools view -R against the BGZF+tbi subject) is used when available;
   otherwise an awk streaming join over the whole subject VCF is the fallback
   (correct, just slower), so the scorer runs with no external index.  Both
   paths pipe through the field-extraction awk above. *)
prsSubjectRows[subjectPath_String, variants_List] :=
    Block[{regionsFile, cmd, out},
        regionsFile = prsRegionsFile[variants];
        cmd = If[ onPathQ["bcftools"] && FileExistsQ[subjectPath <> ".tbi"],
            "bcftools view -R " <> shellEscape[regionsFile] <> " -H " <> shellEscape[subjectPath]
                <> " | awk -F '\\t' " <> shellEscape[prsExtractAwkBody[]]
            ,
            streamCommand[subjectPath] <> " | awk -F '\\t' "
                <> shellEscape[prsJoinExtractAwk[]] <> " " <> shellEscape[regionsFile] <> " -"
        ];
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        Quiet @ DeleteFile[regionsFile];
        If[ ! StringQ[out], Return[$Failed]];
        Association @ Map[
            row |-> Block[{p = prsParseCompactRow[row]}, If[ MissingQ[p], Nothing, p["Key"] -> p]],
            Select[StringSplit[out, "\n"], # =!= "" &]
        ]
    ]

(* -- allele matching + dosage (pure) -- *)

prsComp[base_String] :=
    Replace[base, {"A" -> "T", "T" -> "A", "C" -> "G", "G" -> "C", _ -> ""}]

prsSNVBaseQ[b_String] := StringMatchQ[b, "A" | "C" | "G" | "T"]

(* Strand-ambiguous: the effect / other alleles are a complementary pair (A/T
   or C/G), so reverse-complement cannot resolve the strand. *)
prsPalindromicQ[ea_String, oa_String] := prsComp[ea] === oa

prsGenotypeCalledQ[parts_List] :=
    parts =!= {} && AllTrue[parts, StringMatchQ[#, DigitCharacter ..] &]

(* Effect-allele frequency for one used variant: the scoring file's
   allelefrequency_effect when present (matched to the effect allele already),
   else the subject's imputation-panel INFO/AF aligned to the effect allele
   (effIsAlt marks whether the effect allele is the subject's ALT). *)
prsEffectAlleleFrequency[v_Association, row_Association, effIsAlt_] :=
    Which[
        NumericQ[v["EAF"]], {v["EAF"], "PGSAlleleFrequency"},
        TrueQ[row["PanelQ"]] && NumericQ[row["AF"]],
            {If[ TrueQ[effIsAlt], row["AF"], 1 - row["AF"]], "SubjectPanelAF"},
        True, {Missing[], None}
    ]

(* Score one scoring variant against the subject rows.  Returns Missing when
   the variant is unusable - subject-absent, subject / scoring multiallelic or
   indel, strand-ambiguous palindrome, allele-mismatched, or a no-call - so it
   counts toward NVariantsExpected but not NVariantsUsed; otherwise an
   Association with the effect-allele dosage (0, 1, or 2), the weight, and the
   effect-allele frequency (when available) with its source.  A
   reference-confirming subject row (ALT = ".", a homozygous-reference call) is
   scored too: the subject carries two REF alleles, so the effect-allele dosage
   is 2 when the effect allele is REF and 0 otherwise. *)
prsScoreVariant[v_Association, subjectByPos_Association] :=
    Block[{ea, oa, row, ref, altList, gtParts, alt, forwardEA, effIsAlt, dosage, eaf, src},
        ea = v["EA"];
        oa = v["OA"];
        If[ ! (prsSNVBaseQ[ea] && prsSNVBaseQ[oa]), Return[Missing[]]];
        If[ prsPalindromicQ[ea, oa], Return[Missing[]]];
        row = Lookup[subjectByPos, v["Chr"] <> "-" <> ToString[v["Pos"]], Missing[]];
        If[ MissingQ[row], Return[Missing[]]];
        ref = row["REF"];
        altList = row["ALT"];
        gtParts = row["GTParts"];
        If[ ! (prsGenotypeCalledQ[gtParts] && prsSNVBaseQ[ref]), Return[Missing[]]];
        Which[
            altList === {},
                If[ ! MatchQ[gtParts, {"0" ..}], Return[Missing[]]];
                forwardEA = Which[
                    MemberQ[{ea, oa}, ref], ea,
                    MemberQ[{prsComp[ea], prsComp[oa]}, ref], prsComp[ea],
                    True, Missing[]
                ];
                If[ MissingQ[forwardEA], Return[Missing[]]];
                effIsAlt = False;
                dosage = If[ forwardEA === ref, 2, 0]
            ,
            Length[altList] === 1,
                alt = First[altList];
                If[ ! prsSNVBaseQ[alt], Return[Missing[]]];
                forwardEA = Which[
                    Sort[{ea, oa}] === Sort[{ref, alt}], ea,
                    Sort[{prsComp[ea], prsComp[oa]}] === Sort[{ref, alt}], prsComp[ea],
                    True, Missing[]
                ];
                If[ MissingQ[forwardEA], Return[Missing[]]];
                effIsAlt = forwardEA === alt;
                If[ ! effIsAlt && forwardEA =!= ref, Return[Missing[]]];
                dosage = Count[gtParts, If[ effIsAlt, "1", "0"]]
            ,
            True, Return[Missing[]]
        ];
        {eaf, src} = prsEffectAlleleFrequency[v, row, effIsAlt];
        <|"Dosage" -> dosage, "W" -> v["W"], "EAF" -> eaf, "FreqSource" -> src|>
    ]

(* Subject percentile from the analytic normal approximation (Missing when the
   variance is not positive, i.e. no frequency-covered variant). *)
prsNormalPercentile[score_, mean_, var_] :=
    If[ NumericQ[var] && var > 0,
        N @ CDF[NormalDistribution[mean, Sqrt[var]], score],
        Missing["NoReference"]
    ]

prsEntryKeys[] :=
    {"Score", "Percentile", "PGSID", "Trait", "NVariantsUsed", "NVariantsExpected", "Method"}

(* Reduce the scored used-variant records to the score entry.  The raw Score
   sums over all used variants; the percentile is the normal CDF over the
   subset that carries an effect-allele frequency (typically all of them on an
   imputed genome). *)
prsAssembleEntry[scored_List, nExpected_Integer, meta_Association] :=
    Block[{score, withFreq, mean, var, scorePop, pct, src, method},
        score = Total[Map[#["Dosage"] * #["W"] &, scored]];
        withFreq = Select[scored, NumericQ[#["EAF"]] &];
        mean = Total[Map[2 * #["EAF"] * #["W"] &, withFreq]];
        var = Total[Map[2 * #["EAF"] * (1 - #["EAF"]) * #["W"]^2 &, withFreq]];
        scorePop = Total[Map[#["Dosage"] * #["W"] &, withFreq]];
        pct = If[ withFreq === {}, Missing["NoReference"], prsNormalPercentile[scorePop, mean, var]];
        src = If[ withFreq === {}, None, First[withFreq]["FreqSource"]];
        method = Which[
            MissingQ[pct], "None",
            src === "PGSAlleleFrequency", "NormalApproximation:PGSAlleleFrequency",
            True, "NormalApproximation:SubjectPanelAF"
        ];
        KeyTake[
            <|
                "Score" -> N[score],
                "Percentile" -> pct,
                "PGSID" -> Lookup[meta, "PGSID", Missing[]],
                "Trait" -> Lookup[meta, "Trait", Missing[]],
                "NVariantsUsed" -> Length[scored],
                "NVariantsExpected" -> nExpected,
                "Method" -> method
            |>,
            prsEntryKeys[]
        ]
    ]

(* The testable core: takes explicit paths (like computeClinVarHits) so the
   fixture tests drive it without any download.  Returns the score entry
   Association or $Failed. *)
computePolygenicRiskScore[subjectPath_String, scoringPath_String, maxVariants_ : Infinity] :=
    Block[{parsed, meta, variants, nTotal, subjectByPos, scored},
        parsed = readPGSScoringFile[scoringPath];
        If[ parsed === $Failed, Return[$Failed]];
        meta = parsed["Meta"];
        variants = parsed["Variants"];
        nTotal = Length[variants];
        If[ IntegerQ[maxVariants] && maxVariants < nTotal,
            Message[PolygenicRiskScore::truncated, Lookup[meta, "PGSID", "?"], nTotal, maxVariants];
            variants = Take[variants, maxVariants]
        ];
        subjectByPos = prsSubjectRows[subjectPath, variants];
        If[ subjectByPos === $Failed, Return[$Failed]];
        scored = DeleteCases[Map[prsScoreVariant[#, subjectByPos] &, variants], _Missing];
        prsAssembleEntry[scored, Length[variants], meta]
    ]

(* -- on-disk per-subject sidecar (WXF of the whole PRS map, keyed by the PGS
   Catalog release) -- *)

prsSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

prsSidecarWXF[hg_] := FileNameJoin[{prsSidecarDir[hg], "prs.wxf"}]
prsSidecarRelease[hg_] := FileNameJoin[{prsSidecarDir[hg], "prs.release"}]

writePRSSidecar[hg_, map_Association, version_String] :=
    Block[{dir = prsSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[prsSidecarWXF[hg], map, "WXF"];
        Quiet @ Export[prsSidecarRelease[hg], version, "Text"];
        map
    ]

loadPRSSidecar[hg_, version_String] :=
    Block[{wf = prsSidecarWXF[hg], rf = prsSidecarRelease[hg], stored, m},
        If[ ! FileExistsQ[wf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= version, Return[Missing["NotCached"]]];
        m = Quiet @ Import[wf, "WXF"];
        If[ AssociationQ[m], m, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[PolygenicRiskScore] = {"Reference" -> Automatic, "MaxVariants" -> Automatic}

PolygenicRiskScore[hg_ ? HumanGenomeQ, spec_String, opts : OptionsPattern[]] :=
    Block[{pgsid, refDir, version, maxV, existingMap, cached, entry, scorePath,
           newMap, ann, newAnn},
        pgsid = resolvePGSID[spec];
        If[ MissingQ[pgsid],
            Message[PolygenicRiskScore::unknownTrait, spec, StringRiffle[Keys[$prsTraitMap], ", "]];
            Return[$Failed]
        ];
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> pgsReferenceDir[hg], d_String :> d}
        ];
        version = pgsCatalogVersion[refDir];
        maxV = Replace[OptionValue["MaxVariants"], {n_Integer :> n, _ -> Infinity}];
        (* In-memory cache hit: this PGS ID already scored under this release. *)
        If[ AssociationQ[hg["PRS"]] && KeyExistsQ[hg["PRS"], pgsid]
                && hg["References", "PGSCatalogVersion"] === version,
            Return[hg]
        ];
        (* Hydrate: merge the in-memory map with the release-matched sidecar so a
           freshly constructed HumanGenome recovers previously scored traits. *)
        existingMap = Join[
            If[ AssociationQ[hg["PRS"]], hg["PRS"], <||>],
            Replace[loadPRSSidecar[hg, version], Except[_Association] -> <||>]
        ];
        cached = Lookup[existingMap, pgsid, Missing[]];
        If[ AssociationQ[cached],
            entry = cached
            ,
            scorePath = preparePGSScoreFile[refDir, pgsid];
            If[ scorePath === $Failed, Message[PolygenicRiskScore::noref, pgsid]; Return[$Failed]];
            entry = computePolygenicRiskScore[hg["Path"], scorePath, maxV];
            If[ ! AssociationQ[entry], Message[PolygenicRiskScore::noref, pgsid]; Return[$Failed]]
        ];
        newMap = Append[existingMap, pgsid -> entry];
        writePRSSidecar[hg, newMap, version];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "PRS" -> newMap,
            "References" -> Append[Lookup[ann, "References", <||>], "PGSCatalogVersion" -> version]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


(* Ancestry.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === ancestry-cluster shared helpers ===
   ChromosomalSex, HaplogroupCall and AncestryEstimate all read the subject by
   genomic region through the tabix index (chrX / chrY / chrM windows, or an
   explicit position list) so the multi-gigabyte source is never scanned end to
   end.  These helpers are the region-read and one-time-download primitives
   shared by the three. *)

(* Read every data row of a tabix region as a list of raw VCF lines.  Requires
   the tabix binary and a `.tbi` sibling of the source. *)
tabixRegionLines[path_String, region_String] :=
    Block[{out},
        out = RunProcess[
            {"sh", "-c", "tabix " <> shellEscape[path] <> " " <> shellEscape[region]},
            "StandardOutput"
        ];
        If[ ! StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

(* Read the subject calls at an explicit CHROM<TAB>POS regions file through the
   tabix index (bcftools view -R), so only the listed positions are touched. *)
streamSubjectAtRegions[subjectPath_String, regionsFile_String] :=
    Block[{out},
        out = RunProcess[
            {"sh", "-c",
                "bcftools view -R " <> shellEscape[regionsFile] <> " -H " <> shellEscape[subjectPath]},
            "StandardOutput"
        ];
        If[ ! StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

(* curl a URL to dest unless dest is already a non-empty file.  Returns True on
   success, False on failure. *)
ancestryClusterFetch[url_String, dest_String] :=
    If[ FileExistsQ[dest] && FileByteCount[dest] > 0,
        True,
        Block[{res},
            res = RunProcess[{"sh", "-c",
                "curl -L --fail -s -o " <> shellEscape[dest] <> " " <> shellEscape[url]}];
            MatchQ[res, KeyValuePattern["ExitCode" -> 0]] && FileExistsQ[dest] && FileByteCount[dest] > 0
        ]
    ]

(* The contig IDs the subject file declares, and whether they are chr-prefixed. *)
subjectContigIDs[hg_] :=
    Map[Lookup[#, "ID", Missing[]] &, Cases[Lookup[hg["Header"], "Contigs", {}], _Association]]

subjectContigName[hg_, prefixed_String, plain_String] :=
    Block[{ids = subjectContigIDs[hg]},
        Which[
            MemberQ[ids, prefixed], prefixed,
            MemberQ[ids, plain], plain,
            True, prefixed
        ]
    ]

subjectChrPrefix[hg_] :=
    If[ AnyTrue[subjectContigIDs[hg], StringQ[#] && StringStartsQ[#, "chr"] &], "chr", ""]

(* === sex inference ===
   ChromosomalSex infers chromosomal sex from the sex chromosomes.  It reads
   one non-pseudoautosomal chrX window and one male-specific chrY window
   through the tabix index: a male is nearly homozygous across non-PAR chrX
   (hemizygous calls) and carries substantial chrY variant calls, while a
   female has abundant heterozygous chrX calls and essentially no chrY calls.
   The call is cached in a per-subject WXF sidecar and hydrated into the
   Subject slot of a freshly constructed HumanGenome. *)

(* GRCh37 sampling windows.  PAR1 ends at 2699520 and PAR2 begins at 154931044,
   so the chrX window sits wholly outside both pseudoautosomal regions; the chrY
   window sits in the male-specific region. *)
$sexChrXWindow = {2700000, 10000000}
$sexChrYWindow = {2700000, 10000000}
$sexChrYThreshold = 50
$sexMinChrXCalls = 100
$sexChrXHetThreshold = 0.15

ChromosomalSex::noindex = "ChromosomalSex requires the tabix binary on PATH and a .tbi index beside the subject VCF so the sex chromosomes can be read by region; one of them is missing.";

(* Classify one chrX row as a heterozygous / homozygous PASS biallelic SNV call
   (or "skip").  Only PASS rows with a single-base REF and ALT and a diploid,
   fully-called genotype count. *)
sexChrXClassify[line_String] :=
    Block[{f = StringSplit[line, "\t"], gt, parts},
        If[ Length[f] < 10 || f[[7]] =!= "PASS" || f[[5]] === "."
                || StringLength[f[[4]]] =!= 1 || StringLength[f[[5]]] =!= 1,
            Return["skip"]
        ];
        gt = First @ StringSplit[f[[10]], ":"];
        parts = StringSplit[gt, "/" | "|"];
        If[ Length[parts] =!= 2 || MemberQ[parts, "."], Return["skip"]];
        If[ First[parts] === Last[parts], "hom", "het"]
    ]

sexChrXStats[lines_List] :=
    Block[{classes = Map[sexChrXClassify, lines], het, hom, tot},
        het = Count[classes, "het"];
        hom = Count[classes, "hom"];
        tot = het + hom;
        <|
            "Calls" -> tot,
            "Het" -> het,
            "Hom" -> hom,
            "HetRate" -> If[ tot > 0, N[het / tot], Missing["NoData"]]
        |>
    ]

(* A chrY row carries a non-reference call when it is PASS, has an ALT, and the
   genotype carries at least one called non-zero allele. *)
sexChrYVariantQ[line_String] :=
    Block[{f = StringSplit[line, "\t"], gt, parts},
        If[ Length[f] < 10 || f[[7]] =!= "PASS" || f[[5]] === ".", Return[False]];
        gt = First @ StringSplit[f[[10]], ":"];
        parts = StringSplit[gt, "/" | "|"];
        parts =!= {} && ! MemberQ[parts, "."]
            && AnyTrue[parts, StringMatchQ[#, DigitCharacter ..] && # =!= "0" &]
    ]

sexChrYNonRefCount[lines_List] := Count[lines, line_ /; sexChrYVariantQ[line]]

(* The karyotype call from the two robust statistics. *)
sexKaryotype[hetRate_, xCalls_, yCount_] :=
    Which[
        ! (IntegerQ[xCalls] && xCalls >= $sexMinChrXCalls), "Undetermined",
        ! NumericQ[hetRate], "Undetermined",
        yCount >= $sexChrYThreshold && hetRate < $sexChrXHetThreshold, "XY",
        yCount < $sexChrYThreshold && hetRate >= $sexChrXHetThreshold, "XX",
        True, "Undetermined"
    ]

(* Assemble the ChromosomalSex Association from the two window reads.  Pure:
   the tabix work happens in the operator, so this can be driven by fixture
   line lists. *)
sexResult[xStats_Association, yCount_Integer, xRegion_String, yRegion_String] :=
    <|
        "KaryotypeCall" -> sexKaryotype[xStats["HetRate"], xStats["Calls"], yCount],
        "ChrXHetRate" -> xStats["HetRate"],
        "ChrXCallsSampled" -> xStats["Calls"],
        "ChrYVariantCount" -> yCount,
        "ChrXRegionSampled" -> xRegion,
        "ChrYRegionSampled" -> yRegion,
        "Method" -> "ChrYCoverage+ChrXHeterozygosity"
    |>

(* -- per-subject WXF sidecar (no external reference, so no version key) -- *)

sexSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

sexSidecarPath[hg_] := FileNameJoin[{sexSidecarDir[hg], "sex.wxf"}]

writeSexSidecar[hg_, result_Association] :=
    Block[{dir = sexSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[sexSidecarPath[hg], result, "WXF"];
        result
    ]

loadSexSidecar[hg_] :=
    Block[{f = sexSidecarPath[hg], r},
        If[ ! FileExistsQ[f], Return[Missing["NotCached"]]];
        r = Quiet @ Import[f, "WXF"];
        If[ AssociationQ[r] && StringQ[r["KaryotypeCall"]], r, Missing["NotCached"]]
    ]

(* Subject association for a freshly constructed HumanGenome.  When a sex
   sidecar for the subject is present, hydrate Subject["Sex"] with the cached
   karyotype call; otherwise leave it Automatic. *)
initialSubject[g_Genome] :=
    Block[{id = First @ g["Samples"], sidecar, cached, sex = Automatic},
        sidecar = FileNameJoin[{DirectoryName[g["Path"]], id, "interpretations", "sex.wxf"}];
        If[ FileExistsQ[sidecar],
            cached = Quiet @ Import[sidecar, "WXF"];
            If[ AssociationQ[cached] && StringQ[cached["KaryotypeCall"]],
                sex = cached["KaryotypeCall"]
            ]
        ];
        <|"ID" -> id, "Sex" -> sex|>
    ]

(* -- operator -- *)

ChromosomalSex[hg_ ? HumanGenomeQ] :=
    Block[{path = hg["Path"], cached, xContig, yContig, xRegion, yRegion, xLines, yLines,
           result},
        (* Sidecar cache hit (also the fast second-call path). *)
        cached = loadSexSidecar[hg];
        If[ AssociationQ[cached], Return[cached]];
        If[ ! onPathQ["tabix"] || ! FileExistsQ[path <> ".tbi"],
            Message[ChromosomalSex::noindex]; Return[$Failed]
        ];
        xContig = subjectContigName[hg, "chrX", "X"];
        yContig = subjectContigName[hg, "chrY", "Y"];
        xRegion = xContig <> ":" <> ToString[$sexChrXWindow[[1]]] <> "-" <> ToString[$sexChrXWindow[[2]]];
        yRegion = yContig <> ":" <> ToString[$sexChrYWindow[[1]]] <> "-" <> ToString[$sexChrYWindow[[2]]];
        xLines = tabixRegionLines[path, xRegion];
        yLines = tabixRegionLines[path, yRegion];
        If[ xLines === $Failed || yLines === $Failed, Message[ChromosomalSex::noindex]; Return[$Failed]];
        result = sexResult[sexChrXStats[xLines], sexChrYNonRefCount[yLines], xRegion, yRegion];
        writeSexSidecar[hg, result];
        result
    ]

(* === haplogroup interpretation ===
   HaplogroupCall[hg, "mtDNA"] classifies the subject's mitochondrial variants
   against PhyloTree build 17 (rCRS-oriented); HaplogroupCall[hg, "Y"]
   classifies the subject's Y-SNP calls against the ISOGG Y-SNP index.  The
   GRCh37/hg19 chrM here is the old CRS (16571 bp), not rCRS (16569 bp), so the
   subject's chrM consensus is aligned to rCRS (a fast near-identical
   alignment) before the differences are read; a naive position match would be
   off by the control-region indels.  Both reference tables download once under
   data/references/haplogroup/ and the {label, confidence} result is cached per
   subject, keyed by the reference build. *)

$phyloTreeXmlURL = "https://raw.githubusercontent.com/genepi/phylotree-rcrs-17/main/src/tree.xml"
$phyloTreeRcrsURL = "https://raw.githubusercontent.com/genepi/phylotree-rcrs-17/main/src/rcrs.fasta"
$isoggURL = "https://raw.githubusercontent.com/23andMe/yhaplo/master/yhaplo/data/variants/isogg.2016.01.04.txt"
$phyloTreeVersion = "PhyloTree-17-rCRS"
$isoggVersion = "ISOGG-2016.01.04"

HaplogroupCall::download = "Downloading the `1` haplogroup reference; this one-time fetch is cached under data/references/haplogroup/.";
HaplogroupCall::noref = "HaplogroupCall could not obtain or apply the reference; the download failed, curl / bcftools / tabix is not on PATH, or the subject VCF lacks a .tbi index.  Ensure the tools are on PATH and the network is reachable (raw.githubusercontent.com).";
HaplogroupCall::badkind = "HaplogroupCall expects \"mtDNA\" or \"Y\" as the second argument; received `1`.";

haplogroupReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references", "haplogroup"}]
phyloTreeXmlPath[dir_String] := FileNameJoin[{dir, "phylotree17_tree.xml"}]
phyloTreeRcrsPath[dir_String] := FileNameJoin[{dir, "phylotree17_rcrs.fasta"}]
isoggTablePath[dir_String] := FileNameJoin[{dir, "isogg_ysnp_GRCh37.tsv"}]

(* -- mtDNA: PhyloTree 17 parse + motif accumulation -- *)

(* Uppercased on the way in: reference FASTAs are routinely soft-masked, and a
   lowercase repeat base would otherwise read as a mismatch at every position
   it covers. *)
mtReadFasta[path_String] :=
    ToUpperCase @ StringJoin[
        Select[StringSplit[Import[path, "Text"], "\n"], ! StringStartsQ[#, ">"] &]]

(* One PhyloTree <poly> string to a position -> allele rule for the
   substitutions we score; insertions (".Xi"), deletions ("249d") and non-SNV
   forms are dropped.  A trailing "!" (reversion / recurrent flag) is ignored. *)
mtPolyRule[s_String] :=
    Block[{m = StringCases[s,
        StartOfString ~~ p : (DigitCharacter ..) ~~ a : ("A" | "C" | "G" | "T") ~~ EndOfString :> {p, a}]},
        If[ m === {}, Nothing, ToExpression[m[[1, 1]]] -> m[[1, 2]]]
    ]

(* Accumulate the rCRS-relative motif from the tree root down to every node.
   The rCRS-oriented tree is rooted at H2a2a1 (rCRS itself), so a node's motif
   is the union of the <poly> substitutions along its path, last-write-wins so a
   later reversion overrides an earlier state. *)
mtTraverse[XMLElement["haplogroup", attrs_, children_], parentMotif_] :=
    Block[{name = "name" /. attrs, polys, motif, kids},
        polys = Cases[
            Flatten @ Cases[children, XMLElement["details", _, dc_] :> dc],
            XMLElement["poly", _, {t_String}] :> t
        ];
        motif = Fold[
            Function[{acc, p}, Block[{r = mtPolyRule[p]}, If[ r === Nothing, acc, Append[acc, r]]]],
            parentMotif,
            polys
        ];
        kids = Cases[children, XMLElement["haplogroup", _, _]];
        Prepend[Join @@ Map[mtTraverse[#, motif] &, kids], name -> motif]
    ]
mtTraverse[_, _] := {}

(* Drop motif entries that equal the rCRS base (reversions back to reference
   carry no phylogenetic difference from rCRS). *)
mtCleanMotif[motif_Association, rcrs_String] :=
    Block[{len = StringLength[rcrs]},
        Association @ KeyValueMap[
            If[ 1 <= #1 <= len && #2 =!= StringTake[rcrs, {#1}], #1 -> #2, Nothing] &,
            motif
        ]
    ]

mtParseMotifs[treePath_String, rcrs_String] :=
    Block[{xml = Import[treePath, "XML"], pt, rootEl, pairs},
        pt = FirstCase[xml, XMLElement["phylotree", _, _], Missing[], Infinity];
        If[ MissingQ[pt], Return[$Failed]];
        rootEl = FirstCase[pt[[3]], XMLElement["haplogroup", _, _], Missing[]];
        If[ MissingQ[rootEl], Return[$Failed]];
        pairs = mtTraverse[rootEl, <||>];
        Association @ Map[(#[[1]] -> mtCleanMotif[#[[2]], rcrs]) &, pairs]
    ]

(* Parsing the 5435-node tree is a few seconds; memoise it per tree path. *)
$mtMotifsCache = <||>
mtLoadMotifs[treePath_String, rcrs_String] :=
    Lookup[$mtMotifsCache, treePath,
        Block[{m = mtParseMotifs[treePath, rcrs]},
            If[ m =!= $Failed, $mtMotifsCache[treePath] = m];
            m
        ]
    ]

(* -- mtDNA: subject consensus, alignment to rCRS, variant extraction -- *)

mtParseChrMRow[line_String] :=
    Block[{f = StringSplit[line, "\t"], gt, parts},
        If[ Length[f] < 10, Return[Missing[]]];
        gt = First @ StringSplit[f[[10]], ":"];
        parts = StringSplit[gt, "/" | "|"];
        <|
            "Pos" -> FromDigits[f[[2]]],
            "Ref" -> f[[4]],
            "Alt" -> If[ f[[5]] === ".", ".", First @ StringSplit[f[[5]], ","]],
            "HomAlt" -> (parts =!= {} && ! MemberQ[parts, "."] && ! MemberQ[parts, "0"])
        |>
    ]

(* Build the subject's chrM consensus over single-base positions (a homozygous
   alternate call substitutes its ALT base; every other position keeps the
   file's REF).  Indels are left as reference and reconciled by the alignment. *)
mtConsensus[lines_List] :=
    Block[{rows = DeleteCases[Map[mtParseChrMRow, lines], _Missing], maxpos, arr},
        If[ rows === {}, Return[""]];
        maxpos = Max[Lookup[rows, "Pos"]];
        arr = ConstantArray["N", maxpos];
        Do[
            If[ StringLength[r["Ref"]] === 1,
                arr[[r["Pos"]]] = ToUpperCase @
                    If[ r["HomAlt"] && r["Alt"] =!= "." && StringLength[r["Alt"]] === 1, r["Alt"], r["Ref"]]
            ],
            {r, rows}
        ];
        StringJoin[arr]
    ]

(* The consensus is in the subject file's own chrM coordinates, which are not
   the rCRS's: GRCh37 ships NC_001807, two bases longer than the rCRS and
   divergent from position 73 on, with several short indels between them.  So
   the two must be aligned before the motifs can be scored.

   They are still ~99.8% identical, so the optimal path never strays far from
   the diagonal, and restricting the Needleman-Wunsch matrix to a narrow band
   around it makes the alignment linear in the sequence length.  The
   unrestricted 16.5 kb x 16.5 kb matrix exhausts memory.

   Pointers: 1 = diagonal, 2 = gap in the subject, 3 = gap in the reference. *)
$mtBandWidth = 20

mtBandedPointers = Compile[{{a, _Integer, 1}, {b, _Integer, 1}, {bw, _Integer}},
    Module[{n = Length[a], m = Length[b], w = 2 bw + 1, sc, pt, j, best, bp, cand, neg = -1.*^7},
        sc = Table[neg, {n + 1}, {w}];
        pt = Table[0, {n + 1}, {w}];
        sc[[1, bw + 1]] = 0.;
        Do[
            (* column k of the band is reference position i against subject
               position j = i + k - bw - 1 *)
            j = i + k - bw - 1;
            If[ j >= 0 && j <= m && ! (i == 0 && j == 0),
                best = neg; bp = 0;
                If[ i >= 1 && j >= 1 && sc[[i, k]] > neg,
                    cand = sc[[i, k]] + If[a[[i]] == b[[j]], 1., -1.];
                    If[cand > best, best = cand; bp = 1]];
                If[ i >= 1 && k + 1 <= w && sc[[i, k + 1]] > neg,
                    cand = sc[[i, k + 1]] - 2.;
                    If[cand > best, best = cand; bp = 2]];
                If[ j >= 1 && k - 1 >= 1 && sc[[i + 1, k - 1]] > neg,
                    cand = sc[[i + 1, k - 1]] - 2.;
                    If[cand > best, best = cand; bp = 3]];
                sc[[i + 1, k]] = best; pt[[i + 1, k]] = bp
            ],
            {i, 0, n}, {k, 1, w}
        ];
        pt
    ],
    CompilationTarget -> "C", RuntimeOptions -> "Speed"
]

(* Trace the banded alignment back, collecting the aligned single-base
   substitutions as reference-position -> subject-base rules.  An uncalled
   position (N, character code 78) contributes nothing. *)
mtAlignedVariants[ref_String, sub_String, bw_Integer : $mtBandWidth] :=
    Block[{a = ToCharacterCode[ref], b = ToCharacterCode[sub], pt, n, m, i, j, k, acc = {}, p},
        n = Length[a]; m = Length[b];
        (* the traceback starts at the band column m - n + bw + 1, so a length
           difference wider than the band has no in-band alignment at all *)
        If[ Abs[n - m] > bw, Return[$Failed]];
        pt = mtBandedPointers[a, b, bw];
        i = n; j = m; k = j - i + bw + 1;
        While[ i > 0 || j > 0,
            p = pt[[i + 1, k]];
            Which[
                p == 1,
                    If[ a[[i]] =!= b[[j]] && b[[j]] =!= 78,
                        acc = {acc, i -> FromCharacterCode[{b[[j]]}]}];
                    i--; j--,
                p == 2, i--; k++,
                p == 3, j--; k--,
                True, Break[]
            ]
        ];
        Association @ Flatten[acc]
    ]

mtSubjectVariants[subjectPath_String, rcrs_String, mtContig_String] :=
    Block[{lines = tabixRegionLines[subjectPath, mtContig], consensus},
        If[ lines === $Failed, Return[$Failed]];
        consensus = mtConsensus[lines];
        If[ consensus === "", Return[<||>]];
        mtAlignedVariants[rcrs, consensus]
    ]

(* -- mtDNA: classification (HaploGrep-style Kulczynski over substitutions) -- *)

mtScorePair[motif_Association, subjVars_Association] :=
    Block[{expected = Length[motif], matches},
        If[ expected === 0, Return[{0., 0, 0}]];
        matches = Length @ Select[Keys[motif], KeyExistsQ[subjVars, #] && subjVars[#] === motif[#] &];
        {N[0.5 * (matches / expected + matches / Max[Length[subjVars], 1])], matches, expected}
    ]

mtClassify[subjVars_Association, motifs_Association] :=
    Block[{scores, ranked, bestName, s},
        scores = Association @ KeyValueMap[#1 -> mtScorePair[#2, subjVars] &, motifs];
        ranked = ReverseSortBy[Normal[scores], Function[kv, {kv[[2, 1]], kv[[2, 3]]}]];
        bestName = ranked[[1, 1]];
        s = scores[bestName];
        <|
            "Haplogroup" -> bestName,
            "Quality" -> Round[s[[1]], 0.0001],
            "NDefiningMatched" -> s[[2]],
            "NDefiningExpected" -> s[[3]],
            "NVariants" -> Length[subjVars],
            "Reference" -> $phyloTreeVersion,
            "Method" -> "PhyloTree17-Kulczynski"
        |>
    ]

(* The testable core: explicit reference + subject paths so a fixture can drive
   it without any download. *)
computeMtHaplogroup[subjectPath_String, treePath_String, rcrsPath_String, mtContig_String] :=
    Block[{rcrs = mtReadFasta[rcrsPath], motifs, subjVars},
        motifs = mtLoadMotifs[treePath, rcrs];
        If[ motifs === $Failed || motifs === <||>, Return[$Failed]];
        subjVars = mtSubjectVariants[subjectPath, rcrs, mtContig];
        If[ subjVars === $Failed, Return[$Failed]];
        mtClassify[subjVars, motifs]
    ]

prepareMtReference[dir_String] :=
    Block[{xmlP = phyloTreeXmlPath[dir], rcrsP = phyloTreeRcrsPath[dir]},
        If[ FileExistsQ[xmlP] && FileExistsQ[rcrsP],
            Return[<|"TreePath" -> xmlP, "RcrsPath" -> rcrsP, "Version" -> $phyloTreeVersion|>]
        ];
        If[ ! onPathQ["curl"], Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Message[HaplogroupCall::download, "PhyloTree build 17 (mtDNA)"];
        If[ ! ancestryClusterFetch[$phyloTreeXmlURL, xmlP] || ! ancestryClusterFetch[$phyloTreeRcrsURL, rcrsP],
            Return[$Failed]
        ];
        <|"TreePath" -> xmlP, "RcrsPath" -> rcrsP, "Version" -> $phyloTreeVersion|>
    ]

(* -- Y: ISOGG marker table parse + subject calls + deepest-clade classifier -- *)

(* One raw ISOGG row (SNP, Haplogroup, OtherNames, rsID, GRCh37-position,
   Mutation) to {pos, ancestral, derived, haplogroup}, keeping only clean
   long-form labels (leading A-T, then digits / lowercase), integer GRCh37
   positions, and single-base "X->Y" substitutions. *)
yParseIsoggLine[line_String] :=
    Block[{f = StringSplit[line, "\t"], hg, pos, mut, mm},
        If[ Length[f] < 6, Return[Missing[]]];
        hg = StringTrim[f[[2]]];
        pos = StringTrim[f[[5]]];
        mut = StringTrim[f[[6]]];
        If[ ! StringMatchQ[hg, RegularExpression["[A-T][0-9a-z]*"]], Return[Missing[]]];
        If[ ! StringMatchQ[pos, DigitCharacter ..], Return[Missing[]]];
        mm = StringCases[mut,
            a : ("A" | "C" | "G" | "T") ~~ "->" ~~ b : ("A" | "C" | "G" | "T") :> {a, b}, 1];
        If[ mm === {}, Return[Missing[]]];
        {pos, mm[[1, 1]], mm[[1, 2]], hg}
    ]

yBuildMarkerTable[rawPath_String, outPath_String] :=
    Block[{lines, rows},
        lines = Rest @ Select[StringSplit[Import[rawPath, "Text"], "\n"], # =!= "" &];
        rows = DeleteCases[Map[yParseIsoggLine, lines], _Missing];
        rows = DeleteDuplicatesBy[rows, #[[1]] &];
        rows = SortBy[rows, ToExpression[#[[1]]] &];
        Export[outPath, StringRiffle[Map[StringRiffle[#, "\t"] &, rows], "\n"], "Text"]
    ]

yReadMarkers[markerPath_String] :=
    Map[StringSplit[#, "\t"] &, Select[StringSplit[Import[markerPath, "Text"], "\n"], # =!= "" &]]

(* The subject base at a called site: REF for a homozygous-reference call, the
   single-base ALT for a homozygous-alternate call, Missing otherwise. *)
yBaseFromRow[f_List] :=
    Block[{gt = First @ StringSplit[f[[10]], ":"], parts, ref = f[[4]], alt},
        parts = StringSplit[gt, "/" | "|"];
        alt = If[ f[[5]] === ".", Missing[], First @ StringSplit[f[[5]], ","]];
        Which[
            parts === {} || MemberQ[parts, "."], Missing[],
            AllTrue[parts, # === "0" &], ref,
            ! MissingQ[alt] && StringLength[alt] === 1 && AllTrue[parts, # =!= "0" &], alt,
            True, Missing[]
        ]
    ]

ySubjectBases[lines_List] :=
    Association @ Map[
        Block[{f = StringSplit[#, "\t"]},
            If[ Length[f] < 10, Nothing, FromDigits[f[[2]]] -> yBaseFromRow[f]]
        ] &,
        lines
    ]

yWriteRegions[markers_List, yContig_String] :=
    Block[{file},
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_y_regions_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".txt"
        }];
        Export[file, StringRiffle[Map[yContig <> "\t" <> #[[1]] &, markers], "\n"], "Text"];
        file
    ]

yMarkerCalls[markers_List, subjBase_Association] :=
    Map[
        Function[m,
            Block[{b = Lookup[subjBase, ToExpression[m[[1]]], Missing[]]},
                <|
                    "HG" -> m[[4]],
                    "State" -> Which[
                        MissingQ[b], "nocall",
                        b === m[[3]], "derived",
                        b === m[[2]], "ancestral",
                        True, "other"
                    ]
                |>
            ]
        ],
        markers
    ]

(* Assign the deepest haplogroup clade whose whole lineage is supported by
   derived markers and unbroken by ancestral contradictions.  Labels are
   prefix-nested (R1b1a2 descends from R1b1a from ... from R), so a clade's
   lineage is the set of valid labels that are prefixes of it. *)
yClassify[calls_List, allLabels_List] :=
    Block[{derivedByHG, ancestralByHG, validLabels, nDer, nAnc, lineage, passedQ,
           failedQ, pathDer, pathAnc, candidates, good, best},
        derivedByHG = Counts[Cases[calls, c_ /; c["State"] === "derived" :> c["HG"]]];
        ancestralByHG = Counts[Cases[calls, c_ /; c["State"] === "ancestral" :> c["HG"]]];
        validLabels = Union[allLabels];
        nDer[l_] := Lookup[derivedByHG, l, 0];
        nAnc[l_] := Lookup[ancestralByHG, l, 0];
        lineage[l_] := SortBy[Select[validLabels, StringStartsQ[l, #] &], StringLength];
        passedQ[l_] := nDer[l] >= 1 && nDer[l] >= nAnc[l];
        failedQ[l_] := nAnc[l] >= 1 && nDer[l] === 0;
        pathDer[l_] := Total[nDer /@ lineage[l]];
        pathAnc[l_] := Total[nAnc /@ lineage[l]];
        candidates = Select[validLabels,
            Function[l, passedQ[l] && AllTrue[lineage[l], Function[a, ! failedQ[a]]]]];
        good = Select[candidates, Function[l, pathDer[l] >= 2]];
        If[ good === {},
            Return[<|
                "Haplogroup" -> Missing["NoCall"], "Confidence" -> 0., "NDerived" -> 0,
                "NConflicts" -> 0, "Reference" -> $isoggVersion,
                "Method" -> "ISOGG-DeepestConsistentClade"
            |>]
        ];
        best = MaximalBy[good, Function[l, {StringLength[l], pathDer[l]}]][[1]];
        <|
            "Haplogroup" -> best,
            "Confidence" -> N[pathDer[best] / (pathDer[best] + pathAnc[best])],
            "Lineage" -> lineage[best],
            "NDerived" -> pathDer[best],
            "NConflicts" -> pathAnc[best],
            "Reference" -> $isoggVersion,
            "Method" -> "ISOGG-DeepestConsistentClade"
        |>
    ]

computeYHaplogroup[subjectPath_String, markerPath_String, yContig_String] :=
    Block[{markers = yReadMarkers[markerPath], regionsFile, subjLines, subjBase, calls},
        If[ markers === {}, Return[$Failed]];
        regionsFile = yWriteRegions[markers, yContig];
        subjLines = streamSubjectAtRegions[subjectPath, regionsFile];
        Quiet @ DeleteFile[regionsFile];
        If[ subjLines === $Failed, Return[$Failed]];
        subjBase = ySubjectBases[subjLines];
        calls = yMarkerCalls[markers, subjBase];
        yClassify[calls, markers[[All, 4]]]
    ]

prepareYReference[dir_String] :=
    Block[{isoggP = isoggTablePath[dir], rawP = FileNameJoin[{dir, "isogg_raw.txt"}]},
        If[ FileExistsQ[isoggP] && FileByteCount[isoggP] > 0,
            Return[<|"MarkerPath" -> isoggP, "Version" -> $isoggVersion|>]
        ];
        If[ ! onPathQ["curl"], Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Message[HaplogroupCall::download, "ISOGG Y-SNP index"];
        If[ ! ancestryClusterFetch[$isoggURL, rawP], Return[$Failed]];
        yBuildMarkerTable[rawP, isoggP];
        If[ ! FileExistsQ[isoggP], Return[$Failed]];
        <|"MarkerPath" -> isoggP, "Version" -> $isoggVersion|>
    ]

(* -- Y-coverage gate: no chrY calls means no paternal lineage to report -- *)

haplogroupHasYCoverageQ[hg_] :=
    Block[{path = hg["Path"], yContig, yRegion, yLines},
        If[ ! onPathQ["tabix"] || ! FileExistsQ[path <> ".tbi"], Return[True]];
        yContig = subjectContigName[hg, "chrY", "Y"];
        yRegion = yContig <> ":" <> ToString[$sexChrYWindow[[1]]] <> "-" <> ToString[$sexChrYWindow[[2]]];
        yLines = tabixRegionLines[path, yRegion];
        yLines === $Failed || sexChrYNonRefCount[yLines] >= $sexChrYThreshold
    ]

haplogroupCompute[hg_, "mtDNA", dir_] :=
    Block[{ref = prepareMtReference[dir]},
        If[ ref === $Failed, Return[$Failed]];
        computeMtHaplogroup[
            hg["Path"], ref["TreePath"], ref["RcrsPath"], subjectContigName[hg, "chrM", "MT"]]
    ]

haplogroupCompute[hg_, "Y", dir_] :=
    Block[{ref},
        If[ ! haplogroupHasYCoverageQ[hg], Return[Missing["NoYChromosome"]]];
        ref = prepareYReference[dir];
        If[ ref === $Failed, Return[$Failed]];
        computeYHaplogroup[hg["Path"], ref["MarkerPath"], subjectContigName[hg, "chrY", "Y"]]
    ]

(* -- per-subject WXF sidecar (the whole {mtDNA, Y} map) -- *)

haplogroupSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

haplogroupSidecarPath[hg_] := FileNameJoin[{haplogroupSidecarDir[hg], "haplogroups.wxf"}]

writeHaplogroupSidecar[hg_, map_Association] :=
    Block[{dir = haplogroupSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[haplogroupSidecarPath[hg], map, "WXF"];
        map
    ]

loadHaplogroupSidecar[hg_] :=
    Block[{f = haplogroupSidecarPath[hg], r},
        If[ ! FileExistsQ[f], Return[Missing["NotCached"]]];
        r = Quiet @ Import[f, "WXF"];
        If[ AssociationQ[r], r, Missing["NotCached"]]
    ]

(* A kind is cached in the map when its detail carries the current reference
   version, or (for Y) it is the settled Missing["NoYChromosome"] value. *)
haplogroupHaveKindQ[map_, kind_String] :=
    Block[{refVer = If[ kind === "mtDNA", $phyloTreeVersion, $isoggVersion], v},
        If[ ! AssociationQ[map], Return[False]];
        v = Lookup[map, kind, Missing[]];
        (AssociationQ[v] && v["Reference"] === refVer) || v === Missing["NoYChromosome"]
    ]

haplogroupRewrap[hg_, map_Association] :=
    HumanGenome[First[hg], Append[Last[hg], "Haplogroups" -> map]]

(* -- operator -- *)

HaplogroupCall[hg_ ? HumanGenomeQ, kind_String] /; ! MemberQ[{"mtDNA", "Y"}, kind] :=
    (Message[HaplogroupCall::badkind, kind]; $Failed)

HaplogroupCall[hg_ ? HumanGenomeQ, kind : ("mtDNA" | "Y")] :=
    Block[{dir = haplogroupReferenceDir[hg], slot, map, cached, detail},
        slot = hg["Haplogroups"];
        map = If[ AssociationQ[slot], slot, <||>];
        (* In-memory cache hit. *)
        If[ haplogroupHaveKindQ[map, kind], Return[hg]];
        (* On-disk sidecar hydrate. *)
        cached = loadHaplogroupSidecar[hg];
        If[ AssociationQ[cached],
            map = Association[map, cached];
            If[ haplogroupHaveKindQ[map, kind], Return[haplogroupRewrap[hg, map]]]
        ];
        detail = haplogroupCompute[hg, kind, dir];
        If[ detail === $Failed, Message[HaplogroupCall::noref]; Return[$Failed]];
        map = Append[If[ AssociationQ[map], map, <||>], kind -> detail];
        writeHaplogroupSidecar[hg, map];
        haplogroupRewrap[hg, map]
    ]

(* === ancestry interpretation ===
   AncestryEstimate estimates continental (super-population) genetic ancestry
   against the 1000 Genomes phase 3 panel.  A per-super-population
   allele-frequency marker panel is prepared once from the phase 3 sites VCF
   (ancestry-informative biallelic common SNVs, thinned to reduce linkage),
   then the subject's allele-dosage vector is fit by non-negative least squares
   to a mixture of the five super-population allele-frequency profiles (AFR,
   AMR, EAS, EUR, SAS).
   The result is continental / coarse sub-continental resolution, not country or
   ethnicity level - that needs a fine private reference panel and genotype-level
   PCA the AF-panel method does not carry. *)

$thousandGenomesSitesURL = "http://ftp.1000genomes.ebi.ac.uk/vol1/ftp/release/20130502/ALL.wgs.phase3_shapeit2_mvncall_integrated_v5c.20130502.sites.vcf.gz"
$ancestrySuperpops = {"EAS", "AMR", "AFR", "EUR", "SAS"}

AncestryEstimate::download = "Downloading and reducing the 1000 Genomes phase 3 sites VCF from `1`; this one-time fetch (roughly 1.4 GB) is reduced to a compact ancestry-informative marker panel and cached under data/references/ancestry/.";
AncestryEstimate::noref = "AncestryEstimate could not obtain or apply the 1000 Genomes reference panel; the download or reduction failed, curl / bcftools / tabix is not on PATH, or the subject VCF lacks a .tbi index.  Ensure the tools are on PATH and the network is reachable.";

ancestryReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references", "ancestry"}]
ancestrySitesPath[dir_String] := FileNameJoin[{dir, "1000G_phase3_sites.vcf.gz"}]
ancestryPanelPath[dir_String] := FileNameJoin[{dir, "aim_panel_GRCh37.tsv"}]
ancestryPanelVersion[panel_String] := "1000G-phase3-AIM-" <> ToString[FileByteCount[panel]]

(* awk that reduces the phase 3 sites VCF to the AIM panel: biallelic SNVs whose
   global AF is common (0.05-0.95) and whose five super-population allele
   frequencies span at least 0.25, thinned to one marker per 50 kb per contig.
   Columns out: CHROM POS REF ALT EAS_AF AMR_AF AFR_AF EUR_AF SAS_AF. *)
ancestryPanelAwk[] := StringJoin[
    "$1~/^#/ { next } ",
    "length($4)!=1 || length($5)!=1 { next } ",
    "{ info=$8; ok=1; mn=1; mx=0; ",
    "n=split(info, kv, \";\"); for(i=1;i<=n;i++){ eq=index(kv[i],\"=\"); if(eq==0) continue; ",
    "V[substr(kv[i],1,eq-1)]=substr(kv[i],eq+1)+0 } ",
    "ga=V[\"AF\"]; if(ga<0.05 || ga>0.95){ delete V; next } ",
    "split(\"EAS_AF AMR_AF AFR_AF EUR_AF SAS_AF\", pk, \" \"); ",
    "for(i=1;i<=5;i++){ if(!(pk[i] in V)){ok=0;break} vv=V[pk[i]]; if(vv<mn)mn=vv; if(vv>mx)mx=vv } ",
    "if(ok!=1){ delete V; next } ",
    "if(mx-mn < 0.25){ delete V; next } ",
    "if($1==lc && ($2-lp)<50000){ delete V; next } ",
    "lc=$1; lp=$2; ",
    "printf \"%s\\t%s\\t%s\\t%s\\t%.4f\\t%.4f\\t%.4f\\t%.4f\\t%.4f\\n\", ",
    "$1,$2,$4,$5,V[\"EAS_AF\"],V[\"AMR_AF\"],V[\"AFR_AF\"],V[\"EUR_AF\"],V[\"SAS_AF\"]; ",
    "delete V }"
]

ancestryBuildPanel[sitesPath_String, panelPath_String] :=
    RunProcess[{"sh", "-c",
        streamCommand[sitesPath] <> " | awk -F '\\t' " <> shellEscape[ancestryPanelAwk[]]
            <> " > " <> shellEscape[panelPath]}]

prepareAncestryReference[dir_String] :=
    Block[{panel = ancestryPanelPath[dir], sites = ancestrySitesPath[dir]},
        If[ FileExistsQ[panel] && FileByteCount[panel] > 0,
            Return[<|"PanelPath" -> panel, "Version" -> ancestryPanelVersion[panel]|>]
        ];
        If[ ! onPathQ["curl"], Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        If[ ! FileExistsQ[sites] || FileByteCount[sites] < 10^8,
            Message[AncestryEstimate::download, $thousandGenomesSitesURL];
            If[ ! ancestryClusterFetch[$thousandGenomesSitesURL, sites], Return[$Failed]]
        ];
        ancestryBuildPanel[sites, panel];
        If[ ! FileExistsQ[panel] || FileByteCount[panel] === 0, Return[$Failed]];
        <|"PanelPath" -> panel, "Version" -> ancestryPanelVersion[panel]|>
    ]

(* -- subject dosages at the panel positions, and the non-negative fit -- *)

ancestryReadPanel[panelPath_String] :=
    Map[
        Function[line,
            Block[{f = StringSplit[line, "\t"]},
                If[ Length[f] < 9, Nothing,
                    <|
                        "Chrom" -> f[[1]], "Pos" -> f[[2]], "Ref" -> f[[3]], "Alt" -> f[[4]],
                        "AF" -> N[ToExpression /@ f[[5 ;; 9]]]
                    |>
                ]
            ]
        ],
        Select[StringSplit[Import[panelPath, "Text"], "\n"], # =!= "" &]
    ]

ancestryWriteRegions[panel_List, chrPrefix_String] :=
    Block[{file},
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_ancestry_regions_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".txt"
        }];
        Export[file,
            StringRiffle[Map[chrPrefix <> #["Chrom"] <> "\t" <> #["Pos"] &, panel], "\n"], "Text"];
        file
    ]

(* Subject alternate-allele dosage (0/1/2) at a biallelic SNV, matched to the
   panel REF/ALT on the reference-forward strand; Missing for a REF mismatch,
   an indel, or a different alternate allele. *)
ancestryDosage[subjRow_Association, panelRef_String, panelAlt_String] :=
    Block[{ref = subjRow["Ref"], alt = subjRow["Alt"], parts = subjRow["GTParts"]},
        Which[
            ref =!= panelRef, Missing[],
            parts === {} || MemberQ[parts, "."], Missing[],
            alt === "." , If[ AllTrue[parts, # === "0" &], 0, Missing[]],
            alt === panelAlt && StringLength[alt] === 1, Count[parts, "1"],
            True, Missing[]
        ]
    ]

ancestrySubjectRow[line_String] :=
    Block[{f = StringSplit[line, "\t"]},
        If[ Length[f] < 10, Nothing,
            (f[[1]] <> "-" <> f[[2]]) -> <|
                "Ref" -> f[[4]],
                "Alt" -> If[ f[[5]] === ".", ".", First @ StringSplit[f[[5]], ","]],
                "GTParts" -> StringSplit[First @ StringSplit[f[[10]], ":"], "/" | "|"]
            |>
        ]
    ]

(* Pair each panel marker the subject carries with its dosage fraction and the
   five super-population allele frequencies. *)
ancestryMarkerData[panel_List, subjLines_List, chrPrefix_String] :=
    Block[{subjMap = Association[Map[ancestrySubjectRow, subjLines]]},
        DeleteCases[
            Map[
                Function[m,
                    Block[{key = chrPrefix <> m["Chrom"] <> "-" <> m["Pos"], row, dose},
                        row = Lookup[subjMap, key, Missing[]];
                        If[ MissingQ[row], Missing[],
                            dose = ancestryDosage[row, m["Ref"], m["Alt"]];
                            If[ MissingQ[dose], Missing[], {dose / 2., m["AF"]}]
                        ]
                    ]
                ],
                panel
            ],
            _Missing
        ]
    ]

(* Non-negative least-squares mix of the five super-population AF profiles that
   best explains the subject's dosage fractions, constrained to a simplex. *)
ancestryEstimate[markerData_List] :=
    Block[{dvec, amat, qmat, cvec, vars, sol, raw, fracs, assoc, ranked, best},
        If[ Length[markerData] < 20, Return[$Failed]];
        dvec = N[markerData[[All, 1]]];
        amat = N[markerData[[All, 2]]];
        qmat = Transpose[amat] . amat;
        cvec = - (Transpose[amat] . dvec);
        vars = Array[ancestryFrac, 5];
        sol = Quiet @ QuadraticOptimization[
            vars . qmat . vars + 2 (cvec . vars),
            {Total[vars] == 1, VectorGreaterEqual[{vars, 0}]},
            vars
        ];
        If[ ! MatchQ[sol, {___Rule}], Return[$Failed]];
        raw = vars /. sol;
        If[ ! MatchQ[raw, {__ ? NumericQ}], Return[$Failed]];
        raw = Clip[raw, {0, 1}];
        raw = raw / Total[raw];
        fracs = AssociationThread[$ancestrySuperpops -> Round[raw, 0.0001]];
        ranked = Keys @ ReverseSort[fracs];
        best = First[ranked];
        <|
            "Superpopulation" -> best,
            "SuperpopulationFractions" -> fracs,
            "NearestPopulations" -> ranked,
            "PrincipalComponents" -> Missing["NotApplicable"],
            "Method" -> "1000G-Superpopulation-AF-NNLS",
            "NMarkersUsed" -> Length[markerData]
        |>
    ]

computeAncestry[subjectPath_String, panelPath_String, chrPrefix_String] :=
    Block[{panel = ancestryReadPanel[panelPath], regionsFile, subjLines, markerData},
        If[ panel === {}, Return[$Failed]];
        regionsFile = ancestryWriteRegions[panel, chrPrefix];
        subjLines = streamSubjectAtRegions[subjectPath, regionsFile];
        Quiet @ DeleteFile[regionsFile];
        If[ subjLines === $Failed, Return[$Failed]];
        markerData = ancestryMarkerData[panel, subjLines, chrPrefix];
        ancestryEstimate[markerData]
    ]

(* -- per-subject WXF sidecar, keyed by the panel version -- *)

ancestrySidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

ancestrySidecarPath[hg_] := FileNameJoin[{ancestrySidecarDir[hg], "ancestry.wxf"}]
ancestrySidecarVersion[hg_] := FileNameJoin[{ancestrySidecarDir[hg], "ancestry.release"}]

writeAncestrySidecar[hg_, result_Association, version_String] :=
    Block[{dir = ancestrySidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[ancestrySidecarPath[hg], result, "WXF"];
        Quiet @ Export[ancestrySidecarVersion[hg], version, "Text"];
        result
    ]

loadAncestrySidecar[hg_, version_String] :=
    Block[{pf = ancestrySidecarPath[hg], vf = ancestrySidecarVersion[hg], stored, r},
        If[ ! FileExistsQ[pf] || ! FileExistsQ[vf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[vf, "Text"];
        If[ stored =!= version, Return[Missing["NotCached"]]];
        r = Quiet @ Import[pf, "WXF"];
        If[ AssociationQ[r], r, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[AncestryEstimate] = {"Reference" -> Automatic}

AncestryEstimate[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{refDir, ref, version, cached, computed, ann, newAnn},
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> ancestryReferenceDir[hg], d_String :> d}
        ];
        ref = prepareAncestryReference[refDir];
        If[ ref === $Failed, Message[AncestryEstimate::noref]; Return[$Failed]];
        version = ref["Version"];
        (* In-memory cache hit: slot populated and panel version still matches. *)
        If[ AssociationQ[hg["Ancestry"]] && hg["References", "ThousandGenomesPanel"] === version,
            Return[hg]
        ];
        (* On-disk sidecar hydrate, else compute and persist. *)
        cached = loadAncestrySidecar[hg, version];
        computed = If[ AssociationQ[cached],
            cached,
            Block[{r = computeAncestry[hg["Path"], ref["PanelPath"], subjectChrPrefix[hg]]},
                If[ AssociationQ[r], writeAncestrySidecar[hg, r, version]];
                r
            ]
        ];
        If[ ! AssociationQ[computed], Message[AncestryEstimate::noref]; Return[$Failed]];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "Ancestry" -> computed,
            "References" -> Append[Lookup[ann, "References", <||>], "ThousandGenomesPanel" -> version]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


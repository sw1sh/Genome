(* Traits.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === SNPedia trait interpretation ===
   TraitAssociations annotates the subject's genotypes with SNPedia's
   community-curated magnitude / repute / summary model (the Promethease-style
   trait lookup).  SNPedia documents a genotype-specific interpretation for
   every genotype of a SNP, including the homozygous-reference genotype, so -
   unlike ClinVarHits and AlphaMissenseScores, which report only carried
   alternate alleles - TraitAssociations keeps every genotype (0/0 included)
   whose SNP SNPedia documents.

   The reference is the offline set of SNPedia-documented rsIDs (the
   Category:Is_a_snp membership), enumerated once via the MediaWiki API and
   cached under data/references/snpedia_rsids.txt so the subject intersection is
   offline.  Per-SNP wikitext pages are fetched in batches of 50 titles and
   cached under data/references/snpedia-pages/ so re-runs and the sidecar build
   never re-hit the API.  The per-subject result is cached under
   data/<subject>/interpretations/, keyed by the SNPedia snapshot commit.

   Strand reconciliation: the subject's VCF alleles are on the reference-forward
   (plus) strand; SNPedia records each SNP's genotypes in its own Orientation
   (plus or minus).  When the SNP page's Orientation is minus we reverse-
   complement the subject's forward alleles before matching, otherwise we match
   as-is; either way the candidate genotype string is confirmed against the
   page's own geno list, so allele ordering is resolved from SNPedia's ground
   truth.  Strand-ambiguous SNPs (A/T and C/G) cannot be reconciled by strand
   alone and are matched by whichever oriented candidate SNPedia documents. *)

$snpediaUA := $genomeUA
$snpediaAPI = "https://bots.snpedia.com/api.php?"
$snpediaCategory = "Category:Is_a_snp"
$snpediaAbsentSentinel = "((SNPEDIA-PAGE-ABSENT))"

TraitAssociations::download = "Building the SNPedia documented-rsID set from the MediaWiki API (Category `1`); this one-time enumeration of the ~110000 documented SNPs is cached under data/references/.";
TraitAssociations::noref = "TraitAssociations could not obtain the SNPedia reference; the MediaWiki API enumeration or a page fetch failed.  Ensure the network is reachable (https://bots.snpedia.com).";

(* The bots.snpedia.com endpoint intermittently 502s behind its CDN, so every
   API call retries a handful of times before giving up. *)
snpediaApiGet[query_String] :=
    Block[{r, out = $Failed, tries = 0},
        While[ tries < 8 && out === $Failed,
            tries++;
            r = Quiet @ URLRead[
                HTTPRequest[$snpediaAPI <> query, <|"Headers" -> {"User-Agent" -> $snpediaUA}|>],
                Interactive -> False
            ];
            If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200
                    && ! StringContainsQ[r["Body"], "Incapsula"],
                out = Quiet @ Developer`ReadRawJSONString[r["Body"]],
                Pause[1.5]
            ]
        ];
        If[ AssociationQ[out], out, $Failed]
    ]

(* -- reference locations, derived from the subject VCF's directory -- *)

traitsReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references"}]

snpediaRsidsPath[dir_String] := FileNameJoin[{dir, "snpedia_rsids.txt"}]
snpediaCommitPath[dir_String] := FileNameJoin[{dir, "snpedia_rsids.commit"}]
snpediaPagesDir[dir_String] := FileNameJoin[{dir, "snpedia-pages"}]

(* -- documented-rsID enumeration (Category:Is_a_snp, paged with cmcontinue) -- *)

enumerateSnpediaRsids[] :=
    Block[{result},
        result = NestWhile[
            st |-> Block[{cont = st["cont"], query, r, members},
                query = "action=query&format=json&formatversion=2&list=categorymembers&cmlimit=500&cmtitle="
                    <> URLEncode[$snpediaCategory]
                    <> If[ StringQ[cont], "&cmcontinue=" <> URLEncode[cont], ""];
                r = snpediaApiGet[query];
                If[ r === $Failed,
                    <|"cont" -> None, "titles" -> st["titles"], "ok" -> False|>,
                    members = Lookup[Lookup[r, "query", <||>], "categorymembers", {}];
                    <|
                        "cont" -> Lookup[Lookup[r, "continue", <||>], "cmcontinue", None],
                        "titles" -> Join[st["titles"], Lookup[members, "title", {}]],
                        "ok" -> st["ok"]
                    |>
                ]
            ],
            <|"cont" -> Automatic, "titles" -> {}, "ok" -> True|>,
            #["cont"] =!= None &
        ];
        If[ ! TrueQ[result["ok"]], Return[$Failed]];
        (* SNPedia titles the rsID pages "Rs<number>"; keep those and lowercase
           to the VCF ID form.  The category also holds 23andMe "i" IDs, dropped. *)
        Sort @ DeleteDuplicates @ Map[
            ToLowerCase,
            Select[result["titles"], StringMatchQ[#, "Rs" ~~ DigitCharacter ..] &]
        ]
    ]

(* Ensure the documented-rsID set and its snapshot commit exist under dir; build
   and cache them from the API if absent.  Returns
   <|"Path" -> rsidsFile, "Commit" -> commit|> or $Failed. *)
prepareSNPediaReference[dir_String] :=
    Block[{rsidsFile, commitFile, rsids, commit},
        rsidsFile = snpediaRsidsPath[dir];
        commitFile = snpediaCommitPath[dir];
        If[ FileExistsQ[rsidsFile] && FileExistsQ[commitFile] && FileByteCount[rsidsFile] > 0,
            Return[<|"Path" -> rsidsFile, "Commit" -> StringTrim @ Import[commitFile, "Text"]|>]
        ];
        Message[TraitAssociations::download, $snpediaCategory];
        rsids = enumerateSnpediaRsids[];
        If[ ! ListQ[rsids] || rsids === {}, Return[$Failed]];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Export[rsidsFile, StringRiffle[rsids, "\n"], "Text"];
        commit = "SNPedia-" <> DateString["ISODate"] <> "-" <> ToString[Length[rsids]];
        Export[commitFile, commit, "Text"];
        <|"Path" -> rsidsFile, "Commit" -> commit|>
    ]

(* -- per-page wikitext cache (one file per title; a missing page is cached with
   a sentinel so it is never re-queried) -- *)

snpediaPageCachePath[dir_String, title_String] :=
    FileNameJoin[{snpediaPagesDir[dir], URLEncode[title] <> ".txt"}]

snpediaCachedPage[dir_String, title_String] :=
    Block[{p = snpediaPageCachePath[dir, title], c},
        If[ ! FileExistsQ[p], Return[Missing["NotCached"]]];
        c = Quiet @ Import[p, "Text"];
        Which[
            c === $snpediaAbsentSentinel, Missing["PageAbsent"],
            StringQ[c], c,
            True, Missing["NotCached"]
        ]
    ]

snpediaWritePage[dir_String, title_String, content_String] :=
    Block[{d = snpediaPagesDir[dir]},
        Quiet @ If[ ! DirectoryQ[d], CreateDirectory[d, CreateIntermediateDirectories -> True]];
        Quiet @ Export[snpediaPageCachePath[dir, title], content, "Text"]
    ]

batchesOf[list_List, n_Integer] := If[ list === {}, {}, Partition[list, n, n, {1, 1}, {}]]

(* Fetch a list of page titles (batched 50 per API query), writing each to the
   page cache, and return an Association title -> (wikitext | Missing["PageAbsent"]). *)
snpediaFetchPages[dir_String, titles_List] :=
    Block[{need, res, pages},
        need = Select[titles, snpediaCachedPage[dir, #] === Missing["NotCached"] &];
        Do[
            res = snpediaApiGet[
                "action=query&format=json&formatversion=2&prop=revisions&rvprop=content&rvslots=main&titles="
                    <> URLEncode[StringRiffle[batch, "|"]]
            ];
            If[ res =!= $Failed,
                pages = Lookup[Lookup[res, "query", <||>], "pages", {}];
                Do[
                    With[{
                        t = Lookup[pg, "title", Missing[]],
                        content = If[
                            TrueQ[Lookup[pg, "missing", False]] || ! KeyExistsQ[pg, "revisions"],
                            $snpediaAbsentSentinel,
                            Lookup[
                                Lookup[Lookup[First[Lookup[pg, "revisions", {<||>}]], "slots", <||>], "main", <||>],
                                "content",
                                $snpediaAbsentSentinel
                            ]
                        ]
                    },
                        If[ StringQ[t] && StringQ[content], snpediaWritePage[dir, t, content]]
                    ],
                    {pg, pages}
                ];
                Pause[0.3]
            ],
            {batch, batchesOf[need, 50]}
        ];
        Association @ Map[
            # -> Replace[snpediaCachedPage[dir, #], Missing["NotCached"] -> Missing["PageAbsent"]] &,
            titles
        ]
    ]

(* -- wikitext template parsing --
   SNPedia SNP pages carry a {{Rsnum|...}} template (Orientation, geno1..genoN,
   Summary) and each genotype page carries a {{Genotype|...}} template
   (magnitude, repute, summary).  Templates here are flat, so the body is the
   text between "{{name" and the first "}}". *)

parseTemplateBody[body_String] :=
    Association @ Map[
        line |-> Block[{t = StringTrim[line], eq},
            If[ ! StringStartsQ[t, "|"],
                Nothing,
                t = StringTrim @ StringDrop[t, 1];
                eq = StringPosition[t, "=", 1];
                If[ eq === {},
                    Nothing,
                    ToLowerCase[StringTrim @ StringTake[t, {1, eq[[1, 1]] - 1}]]
                        -> StringTrim @ StringDrop[t, eq[[1, 1]]]
                ]
            ]
        ],
        StringSplit[body, "\n"]
    ]

templateFields[wikitext_String, name_String] :=
    Block[{pos, tail, close},
        pos = StringPosition[ToLowerCase[wikitext], ToLowerCase["{{" <> name], 1];
        If[ pos === {}, Return[<||>]];
        tail = StringDrop[wikitext, pos[[1, 1]] - 1];
        close = StringPosition[tail, "}}", 1];
        If[ close === {}, Return[<||>]];
        parseTemplateBody @ StringTake[tail, {1, close[[1, 1]] - 1}]
    ]

parseRsnum[wikitext_String] :=
    Block[{fields = templateFields[wikitext, "Rsnum"]},
        <|
            "Orientation" -> Lookup[fields, "orientation", Missing[]],
            "StabilizedOrientation" -> Lookup[fields, "stabilizedorientation", Missing[]],
            "Genos" -> Values @ KeySelect[fields, StringMatchQ[#, "geno" ~~ DigitCharacter ..] &],
            "Category" -> Lookup[fields, "summary", Missing[]]
        |>
    ]

traitParseMagnitude[v_] :=
    If[ StringQ[v] && StringMatchQ[StringTrim[v], NumberString], ToExpression @ StringTrim[v], 0]

traitParseRepute[v_] :=
    Which[
        StringQ[v] && ToLowerCase[StringTrim[v]] === "good", "Good",
        StringQ[v] && ToLowerCase[StringTrim[v]] === "bad", "Bad",
        True, "None"
    ]

(* A genotype page's {{Genotype}} template to its magnitude / repute / summary,
   or Missing when the page has no Genotype template (absent page or redirect). *)
parseGenotype[wikitext_String] :=
    Block[{fields = templateFields[wikitext, "Genotype"]},
        If[ fields === <||>,
            Missing[],
            <|
                "Magnitude" -> traitParseMagnitude[Lookup[fields, "magnitude", ""]],
                "Repute" -> traitParseRepute[Lookup[fields, "repute", ""]],
                "Summary" -> Lookup[fields, "summary", Missing[]]
            |>
        ]
    ]

(* -- subject-side genotype extraction --
   One "rsid<TAB>ref<TAB>alt<TAB>gt" line (emitted by the awk intersection) to a
   forward-strand genotype record, or Missing for a no-call.  0/0 yields the
   (REF;REF) genotype, kept deliberately so the homozygous-reference
   interpretation is reported. *)
traitSubjectGenotype[line_String] :=
    Block[{f, rsid, ref, alt, gt, altList, parts, idxs, alleles},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 4, Return[Missing[]]];
        {rsid, ref, alt, gt} = f[[1 ;; 4]];
        altList = If[ alt === ".", {}, StringSplit[alt, ","]];
        parts = StringSplit[gt, "/" | "|"];
        If[ parts === {} || AnyTrue[parts, ! StringMatchQ[#, DigitCharacter ..] &], Return[Missing[]]];
        idxs = FromDigits /@ parts;
        alleles = Map[i |-> Which[i === 0, ref, i <= Length[altList], altList[[i]], True, Missing[]], idxs];
        If[ AnyTrue[alleles, MissingQ], Return[Missing[]]];
        <|"RsID" -> rsid, "GT" -> gt, "Alleles" -> alleles|>
    ]

(* -- strand reconciliation + candidate genotype titles -- *)

snpTitlePrefix[rsid_String] := "Rs" <> StringDrop[rsid, 2]

traitGenoString[a_String, b_String] := "(" <> a <> ";" <> b <> ")"

traitRevComp[s_String] :=
    StringReplace[StringReverse[s], {"A" -> "T", "T" -> "A", "C" -> "G", "G" -> "C"}]

snvBaseQ[a_String] := StringMatchQ[a, "A" | "C" | "G" | "T"]

(* The subject's forward alleles to an orientation-ordered list of SNPedia
   genotype strings: as-is and reverse-complement, both allele orders, with the
   Orientation-indicated pair first.  Only single-base SNV alleles are handled;
   indel genotypes (SNPedia's D / I notation) are out of scope and yield {}. *)
candidateGenoStrings[alleles_List, orientation_] :=
    Block[{a, b, rca, rcb, asis, rc},
        If[ Length[alleles] =!= 2, Return[{}]];
        {a, b} = ToUpperCase /@ alleles;
        If[ ! (snvBaseQ[a] && snvBaseQ[b]), Return[{}]];
        {rca, rcb} = traitRevComp /@ {a, b};
        asis = DeleteDuplicates[{traitGenoString[a, b], traitGenoString[b, a]}];
        rc = DeleteDuplicates[{traitGenoString[rca, rcb], traitGenoString[rcb, rca]}];
        DeleteDuplicates @ If[
            StringQ[orientation] && ToLowerCase[orientation] === "minus",
            Join[rc, asis],
            Join[asis, rc]
        ]
    ]

(* Candidate full page titles for a subject genotype, confirmed against the SNP
   page's own geno list when one is available (falling back to the raw candidate
   list when the geno list documents none of them). *)
candidateGenoTitles[rsid_String, alleles_List, orientation_, genos_List] :=
    Block[{strs, filtered},
        strs = candidateGenoStrings[alleles, orientation];
        filtered = If[
            genos =!= {} && IntersectingQ[strs, genos],
            Select[strs, MemberQ[genos, #] &],
            strs
        ];
        Map[snpTitlePrefix[rsid] <> # &, filtered]
    ]

traitsColumns[] := {"RsID", "Genotype", "Magnitude", "Repute", "Summary", "URL", "Category"}

emptyTraitsTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ traitsColumns[]]}][[{}]]

(* The pure core: subject genotype records, the SNP-page map (rsid -> parsed
   Rsnum) and the genotype-page map (title -> parsed Genotype), to the Traits
   Tabular sorted by Magnitude descending.  The fixture tests drive this directly
   with tiny in-memory maps, so the matching / strand / sort logic is pinned
   without any network. *)
buildTraitsRows[subjectGenos_List, rsnumMap_ ? AssociationQ, genotypeMap_ ? AssociationQ] :=
    Block[{rows},
        rows = Map[
            sg |-> Block[{rsid, rsnum, titles, chosen, gp},
                rsid = sg["RsID"];
                rsnum = Lookup[rsnumMap, rsid, <||>];
                titles = candidateGenoTitles[
                    rsid, sg["Alleles"],
                    Lookup[rsnum, "Orientation", Missing[]],
                    Lookup[rsnum, "Genos", {}]
                ];
                chosen = SelectFirst[
                    titles,
                    MatchQ[Lookup[genotypeMap, #, Missing[]], _Association] &,
                    Missing[]
                ];
                If[ MissingQ[chosen],
                    Nothing,
                    gp = genotypeMap[chosen];
                    <|
                        "RsID" -> rsid,
                        "Genotype" -> StringDrop[chosen, StringLength @ snpTitlePrefix[rsid]],
                        "Magnitude" -> gp["Magnitude"],
                        "Repute" -> gp["Repute"],
                        "Summary" -> gp["Summary"],
                        "URL" -> "https://www.snpedia.com/index.php/" <> chosen,
                        "Category" -> Lookup[rsnum, "Category", Missing[]]
                    |>
                ]
            ],
            subjectGenos
        ];
        If[ rows === {}, Return[emptyTraitsTabular[]]];
        rows = SortBy[rows, -#["Magnitude"] &];
        Tabular[Map[KeyTake[#, traitsColumns[]] &, rows]]
    ]

(* -- subject VCF intersection (streamed) --
   Load the documented-rsID set into an awk hash, then stream the subject VCF and
   emit "rsid<TAB>ref<TAB>alt<TAB>gt" for every row whose ID SNPedia documents -
   all genotypes, 0/0 included.  Only the small intersected slice flows to the
   kernel. *)
subjectSNPediaRowsAwk[] := StringJoin[
    "FNR == NR { set[$1] = 1; next } ",
    "/^#/ { next } ",
    "($3 in set) { split($10, s, \":\"); print $3 \"\\t\" $4 \"\\t\" $5 \"\\t\" s[1] }"
]

streamSubjectSNPedia[subjectPath_String, rsidsFile_String] :=
    Block[{cmd, out},
        cmd = streamCommand[subjectPath] <> " | awk -F '\\t' "
            <> shellEscape[subjectSNPediaRowsAwk[]] <> " " <> shellEscape[rsidsFile] <> " -";
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ ! StringQ[out], Return[$Failed]];
        Select[StringSplit[out, "\n"], # =!= "" &]
    ]

(* The testable-shaped network core: takes explicit paths (like computeClinVarHits
   / computeAlphaMissenseScores), streams the subject intersection, fetches and
   parses the SNP and genotype pages (page-cached under dir), and returns the
   full Traits Tabular. *)
computeTraits[subjectPath_String, rsidsFile_String, dir_String] :=
    Block[{lines, genos, rsids, rsnumMap, genoTitles, genoPages, genotypeMap},
        lines = streamSubjectSNPedia[subjectPath, rsidsFile];
        If[ lines === $Failed, Return[$Failed]];
        genos = DeleteCases[Map[traitSubjectGenotype, lines], _Missing];
        If[ genos === {}, Return[emptyTraitsTabular[]]];
        rsids = DeleteDuplicates[#["RsID"] & /@ genos];
        With[{mainPages = snpediaFetchPages[dir, Map[snpTitlePrefix, rsids]]},
            rsnumMap = Association @ Map[
                rsid |-> rsid -> Block[{c = Lookup[mainPages, snpTitlePrefix[rsid], Missing[]]},
                    If[ StringQ[c], parseRsnum[c], <||>]],
                rsids
            ]
        ];
        genoTitles = DeleteDuplicates @ Flatten @ Map[
            sg |-> candidateGenoTitles[
                sg["RsID"], sg["Alleles"],
                Lookup[Lookup[rsnumMap, sg["RsID"], <||>], "Orientation", Missing[]],
                Lookup[Lookup[rsnumMap, sg["RsID"], <||>], "Genos", {}]
            ],
            genos
        ];
        genoPages = snpediaFetchPages[dir, genoTitles];
        genotypeMap = Association @ DeleteCases[
            Map[
                t |-> Block[{c = Lookup[genoPages, t, Missing[]], p},
                    If[ ! StringQ[c], Nothing, p = parseGenotype[c]; If[ MatchQ[p, _Association], t -> p, Nothing]]],
                genoTitles
            ],
            Nothing
        ];
        buildTraitsRows[genos, rsnumMap, genotypeMap]
    ]

filterTraitsByMagnitude[t_Tabular, minMag_] :=
    If[ NumericQ[minMag] && minMag > 0,
        Select[t, NumericQ[#Magnitude] && #Magnitude >= minMag &],
        t
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name).  The sidecar
   stores the full (minMag 0) result so a change to the MinMagnitude option never
   invalidates it; the operator applies MinMagnitude after hydration. -- *)

traitsSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

traitsSidecarTabular[hg_] := FileNameJoin[{traitsSidecarDir[hg], "traits.tabular"}]
traitsSidecarRelease[hg_] := FileNameJoin[{traitsSidecarDir[hg], "traits.release"}]

writeTraitsSidecar[hg_, t_Tabular, commit_String] :=
    Block[{dir = traitsSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[traitsSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[traitsSidecarRelease[hg], commit, "Text"];
        t
    ]

loadTraitsSidecar[hg_, commit_String] :=
    Block[{tf = traitsSidecarTabular[hg], rf = traitsSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= commit, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[TraitAssociations] = {"MinMagnitude" -> 0, "Reference" -> Automatic}

TraitAssociations[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{minMag, refDir, ref, commit, rsidsFile, cached, full, computed, ann, newAnn},
        minMag = OptionValue["MinMagnitude"];
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> traitsReferenceDir[hg], d_String :> d}
        ];
        ref = prepareSNPediaReference[refDir];
        If[ ref === $Failed, Message[TraitAssociations::noref]; Return[$Failed]];
        commit = ref["Commit"];
        rsidsFile = ref["Path"];
        (* No in-memory short-circuit: the slot holds the previous call's
           MinMagnitude-filtered view, so returning it unchanged would ignore a
           new "MinMagnitude".  Always rehydrate the full result from the sidecar
           and re-apply the filter.  Reading hg["Traits"] stays instant. *)
        (* On-disk sidecar hydrate (the full result), else compute and persist. *)
        cached = loadTraitsSidecar[hg, commit];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{t = computeTraits[hg["Path"], rsidsFile, refDir]},
                If[ MatchQ[t, _Tabular], writeTraitsSidecar[hg, t, commit]];
                t
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[TraitAssociations::noref]; Return[$Failed]];
        computed = filterTraitsByMagnitude[full, minMag];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "Traits" -> computed,
            "References" -> Append[Lookup[ann, "References", <||>], "SNPediaCommit" -> commit]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


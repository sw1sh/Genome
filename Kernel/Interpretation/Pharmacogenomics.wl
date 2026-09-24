(* Pharmacogenomics.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === pharmacogenomics interpretation ===
   PharmacogenomicProfile calls the subject's star-allele diplotypes for the
   major CPIC pharmacogenes, translates them to metabolizer phenotypes, and
   attaches CPIC drug-response guidance.  The CPIC allele-definition, allele-function,
   diplotype-phenotype, gene-drug pair and recommendation tables are downloaded
   once from the CPIC PostgREST API (api.cpicpgx.org/v1) and reduced to a
   compact per-gene structure under data/references/cpic/ (git-ignored).  CPIC
   publishes allele-definition coordinates on GRCh38 only, so each defining
   SNV's rsID is resolved to its GRCh37 position through the Ensembl GRCh37 REST
   endpoint (the primary-assembly mapping is preferred over patch scaffolds; the
   CYP2D6 rsIDs also map to HSCHR22_2_CTG1) and cached in the same reduced file.
   The subject is then read at those GRCh37 positions by the tabix index
   (bcftools view -R), never scanning the whole genome.  Diplotypes are called
   phasing-free by matching the subject's genotypes to the CPIC allele
   definitions AS BASES (not as REF/ALT indices), so the join is robust to the
   GRCh37 / GRCh38 reference-allele flip.  The per-subject Tabular is cached
   under data/<subject>/interpretations/, keyed by the reduced CPIC data
   version.  Result columns: {Gene, Diplotype, Phenotype, ActionableDrug,
   CPICGuidance, CPICLevel, ActivityScore, Confidence}, one row per (gene,
   actionable drug).  This is decision-support information, not a prescription. *)

$cpicGenes = {"CYP2C19", "CYP2C9", "VKORC1", "TPMT", "SLCO1B1", "DPYD", "CYP3A5",
    "UGT1A1", "NUDT15", "CYP2B6", "CYP2D6"}
$cpicAPIBase = "https://api.cpicpgx.org/v1/"
$ensemblGRCh37URL = "https://grch37.rest.ensembl.org/variation/homo_sapiens"

PharmacogenomicProfile::download = "Downloading and reducing the CPIC allele-definition, function, diplotype-phenotype and recommendation tables from the CPIC API (`1`) and resolving GRCh37 coordinates through Ensembl; this one-time fetch is cached under data/references/cpic/.";
PharmacogenomicProfile::noref = "PharmacogenomicProfile could not obtain or apply the reduced CPIC reference; the CPIC API / Ensembl download failed, or bcftools / tabix is not on PATH, or the subject VCF lacks a .tbi index.  Ensure bcftools, tabix and curl are on PATH and the network is reachable (api.cpicpgx.org, grch37.rest.ensembl.org).";

(* -- reference locations, derived from the subject VCF's directory so no
   absolute path is ever baked into the source -- *)

cpicReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references", "cpic"}]
cpicReducedPath[dir_String] := FileNameJoin[{dir, "cpic_reduced.wxf"}]
cpicReleasePath[dir_String] := FileNameJoin[{dir, "cpic_reduced.release"}]

(* -- CPIC PostgREST GET returning parsed JSON, or $Failed -- *)
cpicGet[query_String] :=
    Block[{r},
        r = Quiet @ URLExecute[HTTPRequest[$cpicAPIBase <> query], "RawJSON", Interactive -> False];
        If[ ListQ[r] || AssociationQ[r], r, $Failed]
    ]

(* Parse a CPIC chromosomelocation "g.94780544A>G" into {ref, alt} on the
   chromosome plus strand.  The bases are build-independent for an SNV, so they
   compare directly against the subject's plus-strand REF / ALT. *)
cpicChromRefAlt[s_String] :=
    Block[{m},
        m = StringCases[s,
            "g." ~~ DigitCharacter .. ~~ r : LetterCharacter ~~ ">" ~~ a : LetterCharacter :> {r, a}, 1];
        If[ m === {}, Missing[], First[m]]
    ]
cpicChromRefAlt[_] := Missing[]

pgxSNVBaseQ[b_] := StringQ[b] && StringMatchQ[b, "A" | "C" | "G" | "T"]

(* -- Ensembl GRCh37 coordinate resolution --
   CPIC gives GRCh38 positions; the subject is GRCh37.  Resolve each defining
   SNV's rsID to its GRCh37 {chrom, pos}, preferring the primary-assembly
   mapping over an ALT / patch scaffold. *)

pgxPrimaryChromQ[s_String] := StringMatchQ[s, (DigitCharacter ..) | "X" | "Y" | "MT" | "M"]

ensemblGRCh37Batch[rsids_List] :=
    Block[{resp, j},
        If[ rsids === {}, Return[<||>]];
        resp = Quiet @ URLRead[
            HTTPRequest[$ensemblGRCh37URL, <|
                "Method" -> "POST",
                "ContentType" -> "application/json",
                "Body" -> ExportString[<|"ids" -> rsids|>, "RawJSON"]
            |>],
            Interactive -> False
        ];
        If[ ! MatchQ[resp, _HTTPResponse] || resp["StatusCode"] =!= 200, Return[$Failed]];
        j = Quiet @ Developer`ReadRawJSONString[resp["Body"]];
        If[ ! AssociationQ[j], Return[$Failed]];
        Association @ KeyValueMap[
            Function[{rs, v}, Block[{ms, m},
                ms = Select[Lookup[v, "mappings", {}], #["assembly_name"] === "GRCh37" &];
                m = SelectFirst[ms, pgxPrimaryChromQ[ToString[#["seq_region_name"]]] &, First[ms, Missing[]]];
                If[ MissingQ[m], Nothing, rs -> {ToString[m["seq_region_name"]], m["start"]}]
            ]],
            j
        ]
    ]

ensemblGRCh37Coords[rsids_List] :=
    Block[{results},
        results = Map[ensemblGRCh37Batch, batchesOf[DeleteDuplicates[rsids], 180]];
        If[ MemberQ[results, $Failed], $Failed, Join @@ results]
    ]

(* -- reduce one gene's CPIC allele definition into locations, the reference
   base at each location, and each allele's defining-variant signature --
   refBase(l) is the reference allele's listed base if present, else the genomic
   plus-strand reference; defsig(A) is A's listed SNV bases that differ from
   refBase (so the reference allele has an empty signature, and an indel-only
   allele reduces to empty and is excluded from calling below). *)
reduceCPICGeneDef[gene_] :=
    Block[{locs, defs, alleles, alv, defIds, genomicRef, refAllele, alvByDef,
           refBaseByLoc, snvLocs, snvLocIds, alleleList},
        locs = cpicGet["sequence_location?genesymbol=eq." <> gene
            <> "&select=id,name,chromosomelocation,dbsnpid,position"];
        defs = cpicGet["allele_definition?genesymbol=eq." <> gene
            <> "&select=id,name,structuralvariation"];
        alleles = cpicGet["allele?genesymbol=eq." <> gene
            <> "&select=name,clinicalfunctionalstatus,activityvalue,definitionid"];
        If[ ! (ListQ[locs] && ListQ[defs] && ListQ[alleles]) || defs === {}, Return[$Failed]];
        defIds = Map[#["id"] &, defs];
        alv = cpicGet["allele_location_value?alleledefinitionid=in.("
            <> StringRiffle[Map[ToString, defIds], ","]
            <> ")&select=alleledefinitionid,locationid,variantallele"];
        If[ ! ListQ[alv], Return[$Failed]];
        genomicRef = Association @ Map[
            #["id"] -> Replace[cpicChromRefAlt[#["chromosomelocation"]], {{r_, _} :> r, _ -> Missing[]}] &,
            locs
        ];
        refAllele = SelectFirst[defs, #["name"] === "*1" &,
            SelectFirst[defs, StringContainsQ[ToLowerCase[#["name"]], "reference"] &, First[defs]]];
        alvByDef = GroupBy[alv, #["alleledefinitionid"] &];
        refBaseByLoc = Association @ Map[
            Function[loc, loc["id"] -> Block[{rv},
                rv = SelectFirst[Lookup[alvByDef, refAllele["id"], {}], #["locationid"] === loc["id"] &, Missing[]];
                If[ ! MissingQ[rv] && pgxSNVBaseQ[rv["variantallele"]], rv["variantallele"], genomicRef[loc["id"]]]
            ]],
            locs
        ];
        snvLocs = Select[locs,
            pgxSNVBaseQ[genomicRef[#["id"]]] && StringQ[#["dbsnpid"]] && StringStartsQ[#["dbsnpid"], "rs"] &];
        snvLocIds = Map[#["id"] &, snvLocs];
        alleleList = Map[
            Function[a, Block[{did = a["definitionid"], strv, myAlv, defsig},
                strv = SelectFirst[defs, #["id"] === did &, <||>];
                myAlv = Lookup[alvByDef, did, {}];
                defsig = Association @ Map[
                    Function[e,
                        If[ pgxSNVBaseQ[e["variantallele"]] && MemberQ[snvLocIds, e["locationid"]]
                                && pgxSNVBaseQ[Lookup[refBaseByLoc, e["locationid"], Missing[]]]
                                && e["variantallele"] =!= refBaseByLoc[e["locationid"]],
                            e["locationid"] -> e["variantallele"],
                            Nothing
                        ]
                    ],
                    myAlv
                ];
                <|"Name" -> a["name"], "Function" -> a["clinicalfunctionalstatus"],
                  "Activity" -> a["activityvalue"], "Structural" -> TrueQ[strv["structuralvariation"]],
                  "DefSig" -> defsig|>
            ]],
            alleles
        ];
        <|"Gene" -> gene, "RefAllele" -> refAllele["name"], "RefBase" -> refBaseByLoc,
          "GenomicRef" -> genomicRef, "SNVLocations" -> snvLocs, "Alleles" -> alleleList|>
    ]

(* -- diplotype -> phenotype map (keyed by the sorted allele multiset) -- *)

$vkorc1RefAllele = "rs9923231 reference (C)"
$vkorc1VarAllele = "rs9923231 variant (T)"

(* VKORC1 has no CPIC diplotype-phenotype table (it is not a metabolizer); the
   warfarin-sensitivity phenotype follows from the rs9923231 variant count, per
   the CPIC warfarin guideline. *)
vkorc1PhenotypeMap[] := <|
    {$vkorc1RefAllele, $vkorc1RefAllele} -> <|"Phenotype" -> "Normal warfarin sensitivity", "ActivityScore" -> "n/a"|>,
    {$vkorc1RefAllele, $vkorc1VarAllele} -> <|"Phenotype" -> "Increased warfarin sensitivity", "ActivityScore" -> "n/a"|>,
    {$vkorc1VarAllele, $vkorc1VarAllele} -> <|"Phenotype" -> "Highly increased warfarin sensitivity", "ActivityScore" -> "n/a"|>
|>

diplotypeKeyAlleles[dk_, gene_] :=
    Block[{g = Lookup[dk, gene, <||>]},
        Sort @ Flatten @ KeyValueMap[Function[{allele, n}, ConstantArray[allele, n]], g]
    ]

cpicPhenotypeMap[gene_] :=
    Block[{dip},
        If[ gene === "VKORC1", Return[vkorc1PhenotypeMap[]]];
        dip = cpicGet["diplotype?genesymbol=eq." <> gene
            <> "&select=generesult,totalactivityscore,diplotypekey"];
        If[ ! ListQ[dip], Return[$Failed]];
        Association @ Map[
            diplotypeKeyAlleles[#["diplotypekey"], gene]
                -> <|"Phenotype" -> #["generesult"], "ActivityScore" -> #["totalactivityscore"]|> &,
            dip
        ]
    ]

(* -- gene-drug guidance: the level-A, guideline-backed actionable drugs and,
   per (drug, phenotype), the single-gene CPIC recommendation.  Multi-gene
   recommendations (e.g. warfarin, which also needs CYP2C9) are left to the
   phenotype-neutral pointer text in the row builder. -- *)
cpicGuidanceData[gene_] :=
    Block[{pairs, actionable, drugIds, recs, recMap},
        pairs = cpicGet["pair?genesymbol=eq." <> gene
            <> "&select=drugid,cpiclevel,guidelineid,removed,drug(name)"];
        If[ ! ListQ[pairs], Return[<|"Drugs" -> {}, "RecMap" -> <||>|>]];
        actionable = Select[pairs,
            StringQ[#["cpiclevel"]] && StringStartsQ[#["cpiclevel"], "A"]
                && ! TrueQ[#["removed"]] && #["guidelineid"] =!= Null &];
        drugIds = DeleteDuplicates @ Map[#["drugid"] &, actionable];
        recs = If[ drugIds === {},
            {},
            cpicGet["recommendation?drugid=in.("
                <> StringRiffle[Map["\"" <> # <> "\"" &, drugIds], ","]
                <> ")&select=drugid,lookupkey,drugrecommendation,classification"]
        ];
        recMap = Association @ Map[
            Function[rec, Block[{lk = rec["lookupkey"]},
                If[ AssociationQ[lk] && Length[lk] === 1 && KeyExistsQ[lk, gene],
                    {rec["drugid"], lk[gene]} -> <|"Rec" -> rec["drugrecommendation"], "Class" -> rec["classification"]|>,
                    Nothing
                ]
            ]],
            If[ ListQ[recs], recs, {}]
        ];
        <|
            "Drugs" -> DeleteDuplicatesBy[
                Map[<|"DrugId" -> #["drugid"], "Drug" -> #["drug"]["name"], "Level" -> #["cpiclevel"]|> &, actionable],
                #["Drug"] &
            ],
            "RecMap" -> recMap
        |>
    ]

(* Ensure the reduced CPIC structure exists under dir; download and build it if
   absent.  Returns <|"Data" -> reduced, "Version" -> str|> or $Failed. *)
prepareCPICData[dir_String] :=
    Block[{reducedFile, releaseFile, cached, perGeneDefs, allRsids, coords, phenoMaps,
           reduced, version},
        reducedFile = cpicReducedPath[dir];
        releaseFile = cpicReleasePath[dir];
        If[ FileExistsQ[reducedFile] && FileExistsQ[releaseFile],
            cached = Quiet @ Import[reducedFile, "WXF"];
            If[ AssociationQ[cached] && KeyExistsQ[cached, "PerGene"],
                Return[<|"Data" -> cached, "Version" -> StringTrim @ Import[releaseFile, "Text"]|>]
            ]
        ];
        Message[PharmacogenomicProfile::download, $cpicAPIBase];
        perGeneDefs = AssociationMap[reduceCPICGeneDef, $cpicGenes];
        If[ AnyTrue[Values[perGeneDefs], # === $Failed &], Return[$Failed]];
        allRsids = DeleteDuplicates @ Flatten @ Map[
            Function[g, Map[#["dbsnpid"] &, perGeneDefs[g]["SNVLocations"]]],
            $cpicGenes
        ];
        coords = ensemblGRCh37Coords[allRsids];
        If[ coords === $Failed, Return[$Failed]];
        phenoMaps = AssociationMap[cpicPhenotypeMap, $cpicGenes];
        If[ AnyTrue[Values[phenoMaps], # === $Failed &], Return[$Failed]];
        reduced = <|
            "Genes" -> $cpicGenes,
            "PerGene" -> Association @ Map[
                Function[g, g -> Block[{r = perGeneDefs[g], locs2},
                    locs2 = Map[
                        Function[loc, <|
                            "Id" -> loc["id"], "RsId" -> loc["dbsnpid"],
                            "Chrom" -> coords[loc["dbsnpid"]][[1]], "Pos" -> coords[loc["dbsnpid"]][[2]]
                        |>],
                        Select[r["SNVLocations"], KeyExistsQ[coords, #["dbsnpid"]] &]
                    ];
                    <|"Gene" -> g, "RefAllele" -> r["RefAllele"], "RefBase" -> r["RefBase"],
                      "GenomicRef" -> r["GenomicRef"], "Locations" -> locs2, "Alleles" -> r["Alleles"],
                      "PhenotypeMap" -> phenoMaps[g], "Guidance" -> cpicGuidanceData[g]|>
                ]],
                $cpicGenes
            ]
        |>;
        version = "CPIC-" <> IntegerString[Hash[reduced], 36];
        reduced = Append[reduced, "Version" -> version];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[reducedFile, reduced, "WXF"];
        Quiet @ Export[releaseFile, version, "Text"];
        <|"Data" -> reduced, "Version" -> version|>
    ]

(* -- star-allele diplotype calling (the testable core) -- *)

pgxColumns[] := {"Gene", "Diplotype", "Phenotype", "ActionableDrug", "CPICGuidance",
    "CPICLevel", "ActivityScore", "Confidence"}

emptyPgxTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ pgxColumns[]]}][[{}]]

(* The base allele A carries at a location: its DefSig value if defined there,
   else the reference base. *)
pgxAlleleBaseAt[allele_, locid_, refBase_] :=
    Lookup[allele["DefSig"], locid, Lookup[refBase, locid, Missing[]]]

(* Subject alleles at each defining location, keyed by CPIC location id.  A
   value is the list of the two called bases (plus strand) or Missing when the
   position was not read / not called (flagged low-confidence). *)
pgxSubjectAllelesByLoc[geneRed_, subjRead_] :=
    Association @ Map[
        Function[loc, Block[{key, sr},
            key = ToString[loc["Chrom"]] <> ":" <> ToString[loc["Pos"]];
            sr = Lookup[subjRead, key, Missing["Absent"]];
            loc["Id"] -> If[ MissingQ[sr],
                Missing["Absent"],
                If[ sr["GT"] === {} || MemberQ[sr["GT"], "."],
                    Missing["NoCall"],
                    Map[
                        Function[p, Block[{i = Quiet @ ToExpression[p]},
                            Which[
                                i === 0, sr["Ref"],
                                IntegerQ[i] && i <= Length[sr["Alt"]], sr["Alt"][[i]],
                                True, Missing[]
                            ]
                        ]],
                        sr["GT"]
                    ]
                ]
            ]
        ]],
        geneRed["Locations"]
    ]

(* Phasing-free diplotype call.  Candidate alleles are the reference allele plus
   every non-structural allele all of whose defining variant bases the subject
   carries; the best-scoring unordered pair (most defining locations matched,
   then most parsimonious) is chosen.  Bases are compared directly, so the call
   is unaffected by the GRCh37 / GRCh38 reference-allele flip.  Structural
   (CNV / hybrid) alleles are excluded - they are not SNV-callable. *)
callDiplotype[geneRed_, subjAlleles_] :=
    Block[{refBase, refName, locids, evalLocs, missingLocs, present, cands, pairs, scored, best},
        refBase = geneRed["RefBase"];
        refName = geneRed["RefAllele"];
        locids = Map[#["Id"] &, geneRed["Locations"]];
        evalLocs = Select[locids, ListQ[subjAlleles[#]] &];
        missingLocs = Select[locids, MissingQ[subjAlleles[#]] &];
        present[a_] := AllTrue[Keys[a["DefSig"]], MemberQ[Lookup[subjAlleles, #, {}], a["DefSig"][#]] &];
        cands = Select[geneRed["Alleles"],
            ! TrueQ[#["Structural"]] && (#["Name"] === refName || (#["DefSig"] =!= <||> && present[#])) &];
        If[ ! MemberQ[Map[#["Name"] &, cands], refName],
            cands = Prepend[cands,
                SelectFirst[geneRed["Alleles"], #["Name"] === refName &,
                    <|"Name" -> refName, "DefSig" -> <||>, "Structural" -> False|>]]
        ];
        pairs = Join[Subsets[cands, {2}], Map[{#, #} &, cands]];
        scored = Map[
            Function[pr, Block[{aa = pr[[1]], bb = pr[[2]], score},
                score = Count[evalLocs,
                    l_ /; Sort[{pgxAlleleBaseAt[aa, l, refBase], pgxAlleleBaseAt[bb, l, refBase]}] === Sort[subjAlleles[l]]];
                <|
                    "Alleles" -> Sort[{aa["Name"], bb["Name"]}],
                    "Score" -> score,
                    "Penalty" -> Length[aa["DefSig"]] + Length[bb["DefSig"]],
                    "Consistent" -> (score === Length[evalLocs])
                |>
            ]],
            pairs
        ];
        best = First @ SortBy[scored, {- #["Score"] &, #["Penalty"] &, #["Alleles"] &}];
        <|
            "Diplotype" -> StringRiffle[best["Alleles"], "/"],
            "Alleles" -> best["Alleles"],
            "Consistent" -> best["Consistent"],
            "Ambiguous" -> (Count[scored, s_ /; s["Score"] === best["Score"] && s["Penalty"] === best["Penalty"]] > 1),
            "MissingSites" -> Length[missingLocs],
            "TotalSites" -> Length[locids],
            "EvaluatedSites" -> Length[evalLocs]
        |>
    ]

(* -- phenotype + confidence + guidance rows -- *)

cpicLookupPhenotype[geneRed_, alleles_List] :=
    Lookup[geneRed["PhenotypeMap"], Key[alleles],
        <|"Phenotype" -> Missing["NoPhenotype"], "ActivityScore" -> Missing[]|>]

pgxConfidence[gene_, call_] :=
    Block[{parts},
        parts = {
            Which[
                call["EvaluatedSites"] === 0, "No defining sites read",
                ! TrueQ[call["Consistent"]], "Not fully consistent with a single diplotype",
                call["MissingSites"] > 0,
                    "Reduced confidence: " <> ToString[call["MissingSites"]] <> " of "
                        <> ToString[call["TotalSites"]] <> " defining sites not read",
                True, "Called"
            ],
            If[ TrueQ[call["Ambiguous"]], "ambiguous (multiple diplotypes fit)", Nothing],
            If[ gene === "CYP2D6",
                "CYP2D6 SNV-only: CNV / hybrid alleles (e.g. *5, *xN) not detectable", Nothing]
        };
        StringRiffle[parts, "; "]
    ]

pgxNormalizeActivity[a_] :=
    Which[
        a === "n/a" || a === "" || MissingQ[a], Missing[],
        StringQ[a], a,
        True, ToString[a]
    ]

(* One row per (gene, actionable drug); a gene with no level-A actionable drug
   still contributes a single row so every covered gene appears. *)
pgxGeneRows[geneRed_, call_, phenoResult_, confidence_] :=
    Block[{gene, phenotype, activity, drugs, rows},
        gene = geneRed["Gene"];
        phenotype = phenoResult["Phenotype"];
        activity = pgxNormalizeActivity[phenoResult["ActivityScore"]];
        drugs = Lookup[geneRed["Guidance"], "Drugs", {}];
        rows = Map[
            Function[d, Block[{rec},
                rec = Lookup[Lookup[geneRed["Guidance"], "RecMap", <||>], Key[{d["DrugId"], phenotype}], Missing[]];
                <|
                    "Gene" -> gene,
                    "Diplotype" -> call["Diplotype"],
                    "Phenotype" -> phenotype,
                    "ActionableDrug" -> d["Drug"],
                    "CPICGuidance" -> If[ MissingQ[rec],
                        "Consult the CPIC guideline (phenotype-specific or multi-gene dosing)", rec["Rec"]],
                    "CPICLevel" -> d["Level"],
                    "ActivityScore" -> activity,
                    "Confidence" -> confidence
                |>
            ]],
            drugs
        ];
        If[ rows === {},
            {<|
                "Gene" -> gene, "Diplotype" -> call["Diplotype"], "Phenotype" -> phenotype,
                "ActionableDrug" -> Missing["NoActionableDrug"],
                "CPICGuidance" -> Missing["NoSingleGeneGuidance"], "CPICLevel" -> Missing[],
                "ActivityScore" -> activity, "Confidence" -> confidence
            |>},
            rows
        ]
    ]

(* The testable compute core: given the reduced CPIC data and the subject's
   reads at the defining positions, produce the full pharmacogenomics Tabular,
   sorted by gene then drug. *)
computePharmacogenomics[reduced_Association, subjRead_Association] :=
    Block[{rows},
        rows = Flatten @ Map[
            Function[g, Block[{geneRed = reduced["PerGene"][g], subjAlleles, call, phenoResult, confidence},
                subjAlleles = pgxSubjectAllelesByLoc[geneRed, subjRead];
                call = callDiplotype[geneRed, subjAlleles];
                phenoResult = cpicLookupPhenotype[geneRed, call["Alleles"]];
                confidence = pgxConfidence[g, call];
                pgxGeneRows[geneRed, call, phenoResult, confidence]
            ]],
            reduced["Genes"]
        ];
        If[ rows === {}, Return[emptyPgxTabular[]]];
        rows = SortBy[rows, {#["Gene"] &, ToString[#["ActionableDrug"]] &}];
        Tabular[Map[KeyTake[#, pgxColumns[]] &, rows]]
    ]

(* Read the subject at the union of every gene's defining GRCh37 positions in a
   single index-restricted pass, returning "chrom:pos" -> {Ref, Alt, GT}.  The
   positions are chr-prefixed to match the subject's contigs. *)
pgxReadSubject[subjectPath_String, reduced_Association, chrPrefix_String] :=
    Block[{coords, regionsFile, out, lines},
        coords = DeleteDuplicates @ Flatten[
            Map[
                Function[g, Map[{ToString[#["Chrom"]], #["Pos"]} &, reduced["PerGene"][g]["Locations"]]],
                reduced["Genes"]
            ],
            1
        ];
        coords = SortBy[coords, {chromKey[#[[1]]], #[[2]]} &];
        regionsFile = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_cpic_pos_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".txt"
        }];
        Export[regionsFile,
            StringRiffle[Map[(chrPrefix <> #[[1]]) <> "\t" <> ToString[#[[2]]] &, coords], "\n"], "Text"];
        out = RunProcess[
            {"sh", "-c", "bcftools view -R " <> shellEscape[regionsFile] <> " -H " <> shellEscape[subjectPath]},
            "StandardOutput"
        ];
        Quiet @ DeleteFile[regionsFile];
        If[ ! StringQ[out], Return[$Failed]];
        lines = Select[StringSplit[out, "\n"], # =!= "" &];
        Association @ Map[
            Function[line, Block[{f = StringSplit[line, "\t"], chrom, alt, gt},
                If[ Length[f] < 10,
                    Nothing,
                    chrom = StringReplace[f[[1]], StartOfString ~~ "chr" -> ""];
                    alt = If[ f[[5]] === ".", {}, StringSplit[f[[5]], ","]];
                    gt = StringSplit[First @ StringSplit[f[[10]], ":"], "/" | "|"];
                    (chrom <> ":" <> f[[2]]) -> <|"Ref" -> f[[4]], "Alt" -> alt, "GT" -> gt|>
                ]
            ]],
            lines
        ]
    ]

(* -- post-computation view filter (applied over the full cached table) -- *)

filterPgxByGenes[t_Tabular, genes_] :=
    If[ genes === All || genes === Automatic,
        t,
        Block[{keep = Map[ToString, Flatten[{genes}]]},
            Select[t, MemberQ[keep, #Gene] &]
        ]
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name).  The sidecar
   stores the full (unfiltered) result so a change to the "Genes" option never
   invalidates it; the operator applies the filter after hydration. -- *)

pgxSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

pgxSidecarTabular[hg_] := FileNameJoin[{pgxSidecarDir[hg], "pharmacogenomics.tabular"}]
pgxSidecarRelease[hg_] := FileNameJoin[{pgxSidecarDir[hg], "pharmacogenomics.release"}]

writePgxSidecar[hg_, t_Tabular, release_String] :=
    Block[{dir = pgxSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[pgxSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[pgxSidecarRelease[hg], release, "Text"];
        t
    ]

loadPgxSidecar[hg_, release_String] :=
    Block[{tf = pgxSidecarTabular[hg], rf = pgxSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= release, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[PharmacogenomicProfile] = {"Genes" -> Automatic, "Reference" -> Automatic}

PharmacogenomicProfile[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{genesOpt, refDir, ref, reduced, version, chrPrefix, cached, subjRead, full,
           computed, ann, newAnn},
        genesOpt = OptionValue["Genes"];
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> cpicReferenceDir[hg], d_String :> d}
        ];
        If[ ! onPathQ["bcftools"] || ! FileExistsQ[hg["Path"] <> ".tbi"],
            Message[PharmacogenomicProfile::noref]; Return[$Failed]
        ];
        ref = prepareCPICData[refDir];
        If[ ref === $Failed, Message[PharmacogenomicProfile::noref]; Return[$Failed]];
        reduced = ref["Data"];
        version = ref["Version"];
        chrPrefix = subjectChrPrefix[hg];
        (* No in-memory short-circuit: the slot holds the previous call's FILTERED
           view, so always rehydrate the full result from the sidecar (a fast
           Parquet import) and re-apply the "Genes" filter.  Reading the slot
           itself (hg["Pharmacogenomics"]) stays instant. *)
        cached = loadPgxSidecar[hg, version];
        subjRead = If[ MatchQ[cached, _Tabular], Null, pgxReadSubject[hg["Path"], reduced, chrPrefix]];
        If[ ! MatchQ[cached, _Tabular] && subjRead === $Failed,
            Message[PharmacogenomicProfile::noref]; Return[$Failed]
        ];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{t = computePharmacogenomics[reduced, subjRead]},
                If[ MatchQ[t, _Tabular], writePgxSidecar[hg, t, version]];
                t
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[PharmacogenomicProfile::noref]; Return[$Failed]];
        computed = filterPgxByGenes[full, genesOpt];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "Pharmacogenomics" -> computed,
            "References" -> Append[Lookup[ann, "References", <||>],
                <|"CPICVersion" -> version, "PharmGKBVersion" -> version|>]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


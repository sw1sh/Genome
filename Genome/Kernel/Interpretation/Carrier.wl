(* Carrier.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === carrier status interpretation ===
   CarrierStatus reuses the ClinVar machinery (it calls ClinVarHits, which
   never re-downloads once the GRCh37 P/LP reference is prepared) to get the
   subject's carried Pathogenic / Likely-pathogenic variants, then annotates
   each hit's gene with its mode of inheritance (MOI) from Genomics England
   PanelApp and classifies the hit.  A heterozygous P/LP variant at an
   autosomal-recessive gene is a healthy carrier (reproductive relevance); a
   homozygous one is a possible recessive-affected case that needs clinical
   review; a variant at a dominant gene is a secondary finding, not carrier
   status.  The gene -> MOI map is fetched per gene from the PanelApp REST API
   (one lookup per distinct gene, majority-voted across the panels the gene
   appears in) and cached under data/references/panelapp_carrier_moi.tsv so
   re-runs never re-hit the API.  The per-subject result is cached under
   data/<subject>/interpretations/, keyed by the panel version and the ClinVar
   release. *)

$carrierPanelUA := $genomeUA
$carrierPanelBase = "https://panelapp.genomicsengland.co.uk/api/v1/"
$carrierPanelAPI = $carrierPanelBase <> "genes/?entity_name="

CarrierStatus::download = "Fetching per-gene mode-of-inheritance from Genomics England PanelApp (`1`); this one-time lookup is cached under data/references/panelapp_carrier_moi.tsv.";
CarrierStatus::noref = "CarrierStatus could not obtain the PanelApp mode-of-inheritance map or the ClinVar reference; the PanelApp lookup or the ClinVar preparation step failed.  Ensure the network is reachable (https://panelapp.genomicsengland.co.uk) and that ClinVarHits succeeds.";

(* -- reference locations, derived from the subject VCF's directory -- *)

carrierReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references"}]

carrierMapPath[dir_String] := FileNameJoin[{dir, "panelapp_carrier_moi.tsv"}]
carrierVersionPath[dir_String] := FileNameJoin[{dir, "panelapp_carrier_moi.version"}]

(* -- MOI normalisation and classification (pure, no network) --
   PanelApp records verbose MOI strings; fold them into the small vocabulary
   the classifier reasons over.  A "BOTH monoallelic and biallelic" gene is
   treated as recessive-capable for carrier purposes: a heterozygote carries
   one recessive allele. *)

carrierNormalizeMOI[raw_String] :=
    Which[
        StringStartsQ[raw, "BOTH monoallelic and biallelic"], "Autosomal recessive/dominant",
        StringStartsQ[raw, "BIALLELIC"], "Autosomal recessive",
        StringStartsQ[raw, "MONOALLELIC"], "Autosomal dominant",
        StringStartsQ[raw, "X-LINKED"], "X-linked",
        StringStartsQ[raw, "MITOCHONDRIAL"], "Mitochondrial",
        True, "Unknown"
    ]
carrierNormalizeMOI[_] := "Unknown"

(* A gene's PanelApp entries carry an MOI each; take the majority informative
   value across the panels the gene appears in. *)
carrierAggregateMOI[results_List] :=
    Block[{moiList, informative, pool},
        moiList = Select[
            Map[Lookup[#, "mode_of_inheritance", ""] &, results],
            StringQ[#] && StringTrim[#] =!= "" &
        ];
        informative = Select[moiList, ! MemberQ[{"Unknown", "Other"}, #] &];
        pool = If[ informative =!= {}, informative, moiList];
        If[ pool === {}, "Unknown", First @ First @ SortBy[Tally[pool], -Last[#] &]]
    ]

carrierClassify[norm_String, zyg_] :=
    Which[
        MemberQ[{"Autosomal recessive", "Autosomal recessive/dominant"}, norm],
            If[ zyg === "Homozygous", "Homozygous (possible affected)", "Carrier"],
        norm === "Autosomal dominant", "Dominant finding",
        norm === "X-linked", "X-linked",
        True, "Unclassified"
    ]

(* Carrier / affected rows sort first (most reproductively / clinically
   relevant), then by gene. *)
carrierClassPriority[c_] :=
    Replace[c, {
        "Homozygous (possible affected)" -> 0,
        "Carrier" -> 1,
        "X-linked" -> 2,
        "Dominant finding" -> 3,
        _ -> 4
    }]

carrierColumns[] :=
    {"Gene", "VariantID", "RsID", "Zygosity", "Inheritance", "CarrierClassification",
     "ClinicalSignificance", "Condition", "ReviewStatus", "PopulationAF", "ImputationQuality"}

emptyCarrierTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ carrierColumns[]]}][[{}]]

(* The testable classification core: takes the ClinVar-hit rows (each an
   Association with at least Gene / VariantID / RsID / Zygosity /
   ClinicalSignificance / Condition / ReviewStatus) and a gene -> normalised-MOI
   map, and returns the classified Tabular.  No network, so the fixture tests
   drive it directly. *)
buildCarrierRows[hitRows_List, moiMap_Association] :=
    Block[{rows},
        rows = Map[
            hit |-> Block[{gene = Lookup[hit, "Gene", Missing[]], zyg, norm},
                zyg = Lookup[hit, "Zygosity", Missing[]];
                norm = Lookup[moiMap, gene, "Unknown"];
                <|
                    "Gene" -> gene,
                    "VariantID" -> Lookup[hit, "VariantID", Missing[]],
                    "RsID" -> Lookup[hit, "RsID", Missing[]],
                    "Zygosity" -> zyg,
                    "Inheritance" -> norm,
                    "CarrierClassification" -> carrierClassify[norm, zyg],
                    "ClinicalSignificance" -> Lookup[hit, "ClinicalSignificance", Missing[]],
                    "Condition" -> Lookup[hit, "Condition", Missing[]],
                    "ReviewStatus" -> Lookup[hit, "ReviewStatus", Missing[]],
                    "PopulationAF" -> Lookup[hit, "PopulationAF", Missing["NotFound"]],
                    "ImputationQuality" -> Lookup[hit, "ImputationQuality", Missing[]]
                |>
            ],
            hitRows
        ];
        If[ rows === {}, Return[emptyCarrierTabular[]]];
        rows = SortBy[rows, {carrierClassPriority[#["CarrierClassification"]], ToString[#["Gene"]]} &];
        Tabular[Map[KeyTake[#, carrierColumns[]] &, rows]]
    ]

carrierApplyIncludeDominant[t_Tabular, includeDom_] :=
    If[ TrueQ[includeDom],
        t,
        Select[t, #CarrierClassification =!= "Dominant finding" &]
    ]

(* Drop carriers whose population frequency exceeds maxAF - a common polymorphism
   with a weak/legacy ClinVar pathogenic label is almost always benign, so carrier
   screening filters it out.  Automatic (or any non-numeric value) keeps all rows,
   and a Missing AF is treated as rare / unknown and kept.  A view filter
   re-applied on every call. *)
carrierApplyMaxAF[t_Tabular, maxAF_] :=
    If[ NumericQ[maxAF],
        Select[t, MissingQ[#PopulationAF] || (NumericQ[#PopulationAF] && #PopulationAF <= maxAF) &],
        t
    ]

(* -- PanelApp per-gene MOI lookup (with retry) --
   The bots endpoint is reliable, but transient 5xx behind the CDN are retried
   a handful of times.  Returns the aggregated raw MOI string (or "Unknown"
   when the gene is reached but in no panel), or $Failed on a network error so
   the gene is left out of the cached map and retried next time. *)

carrierGeneRawMOI[sym_String] :=
    Block[{r, j, out = $Failed, tries = 0},
        While[ tries < 5 && out === $Failed,
            tries++;
            r = Quiet @ URLRead[
                HTTPRequest[$carrierPanelAPI <> URLEncode[sym],
                    <|"Headers" -> {"User-Agent" -> $carrierPanelUA}|>],
                Interactive -> False
            ];
            If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200,
                j = Quiet @ Developer`ReadRawJSONString[r["Body"]];
                out = If[ AssociationQ[j], carrierAggregateMOI[Lookup[j, "results", {}]], $Failed]
                ,
                Pause[1.]
            ]
        ];
        out
    ]

(* -- the gene -> MOI map cache (a tiny TSV under data/references/) -- *)

loadCarrierMap[file_String] :=
    If[ ! FileExistsQ[file],
        <||>,
        Block[{lines = Quiet @ Import[file, {"Text", "Lines"}]},
            If[ ! ListQ[lines], Return[<||>]];
            Association @ Map[
                line |-> Block[{p = StringSplit[line, "\t"]},
                    If[ Length[p] >= 2, p[[1]] -> p[[2]], Nothing]
                ],
                Select[lines, StringTrim[#] =!= "" &]
            ]
        ]
    ]

writeCarrierMap[file_String, map_Association] :=
    Export[file, StringRiffle[KeyValueMap[#1 <> "\t" <> #2 &, map], "\n"], "Text"]

(* Ensure the gene -> normalised-MOI map covers every gene in `genes`, fetching
   any missing ones from PanelApp and appending them to the cached TSV.  The
   version marker is stamped once, when the map is first established.  Returns
   <|"Map" -> assoc, "Version" -> str, "Path" -> file|> or $Failed when there is
   no cache and PanelApp is unreachable. *)
prepareCarrierGenePanel[dir_String, genes_List] :=
    Block[{mapFile, versionFile, existing, version, missing, fetched, updated, reachedAny},
        mapFile = carrierMapPath[dir];
        versionFile = carrierVersionPath[dir];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        existing = loadCarrierMap[mapFile];
        version = If[ FileExistsQ[versionFile], StringTrim @ Import[versionFile, "Text"], Missing[]];
        missing = DeleteDuplicates @ Select[genes, StringQ[#] && ! KeyExistsQ[existing, #] &];
        If[ missing =!= {}, Message[CarrierStatus::download, $carrierPanelBase]];
        fetched = Association @ Map[
            sym |-> Block[{raw = carrierGeneRawMOI[sym]},
                If[ raw === $Failed, Nothing, sym -> carrierNormalizeMOI[raw]]
            ],
            missing
        ];
        reachedAny = Length[fetched] > 0;
        updated = Join[existing, fetched];
        If[ MissingQ[version],
            If[ updated === <||> && ! reachedAny && missing =!= {},
                Return[$Failed]
                ,
                version = "PanelApp-GEL-" <> DateString["ISODate"]
            ]
        ];
        writeCarrierMap[mapFile, updated];
        Export[versionFile, version, "Text"];
        <|"Map" -> updated, "Version" -> version, "Path" -> mapFile|>
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name).  The sidecar
   stores the full (all classifications) result so a change to the
   IncludeDominant option never invalidates it; the operator applies the filter
   after hydration.  The marker keys on both the panel version and the ClinVar
   release the hits came from. -- *)

carrierSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

carrierSidecarTabular[hg_] := FileNameJoin[{carrierSidecarDir[hg], "carrier-status.tabular"}]
carrierSidecarRelease[hg_] := FileNameJoin[{carrierSidecarDir[hg], "carrier-status.release"}]

writeCarrierSidecar[hg_, t_Tabular, marker_String] :=
    Block[{dir = carrierSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[carrierSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[carrierSidecarRelease[hg], marker, "Text"];
        t
    ]

loadCarrierSidecar[hg_, marker_String] :=
    Block[{tf = carrierSidecarTabular[hg], rf = carrierSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= marker, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[CarrierStatus] = {"Panel" -> Automatic, "IncludeDominant" -> True, "MaxPopulationAF" -> 0.01}

CarrierStatus[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{cvHg, hits, genes, clinRelease, panelDir, panel, version, marker,
           cached, full, filtered, ann, newAnn},
        (* Reuse the ClinVar machinery (never re-downloads once prepared) and, with
           it, the per-hit PopulationAF / ImputationQuality columns.  ClinVarHits is
           called with no MaxPopulationAF, so CarrierStatus sees the full hit set and
           applies its own carrier-screening frequency filter below. *)
        cvHg = ClinVarHits[hg];
        If[ ! HumanGenomeQ[cvHg] || ! MatchQ[cvHg["ClinVarHits"], _Tabular],
            Message[CarrierStatus::noref]; Return[$Failed]
        ];
        hits = Normal[cvHg["ClinVarHits"]];
        genes = DeleteDuplicates @ Select[Map[Lookup[#, "Gene", Missing[]] &, hits], StringQ];
        clinRelease = cvHg["References", "ClinVarRelease"];
        panelDir = Replace[
            OptionValue["Panel"],
            {Automatic -> carrierReferenceDir[hg], d_String :> d}
        ];
        panel = prepareCarrierGenePanel[panelDir, genes];
        If[ panel === $Failed, Message[CarrierStatus::noref]; Return[$Failed]];
        version = panel["Version"];
        (* The marker keys on the panel version, the ClinVar release, and the
           frequency-source version (the classification now carries PopulationAF). *)
        marker = version <> "|" <> ToString[clinRelease] <> "|" <> $gnomadFreqSource;
        (* No in-memory short-circuit: the slot holds the previous call's filtered
           view, so returning it unchanged would ignore a new "IncludeDominant" or
           "MaxPopulationAF".  Always rehydrate the full classification from the
           sidecar and re-apply the filters.  Reading hg["Carrier"] stays instant. *)
        (* On-disk sidecar hydrate (the full classification), else compute. *)
        cached = loadCarrierSidecar[hg, marker];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{t = buildCarrierRows[hits, panel["Map"]]},
                If[ MatchQ[t, _Tabular], writeCarrierSidecar[hg, t, marker]];
                t
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[CarrierStatus::noref]; Return[$Failed]];
        filtered = carrierApplyIncludeDominant[
            carrierApplyMaxAF[full, OptionValue["MaxPopulationAF"]],
            OptionValue["IncludeDominant"]
        ];
        (* Thread through cvHg's annotation so the returned HumanGenome carries
           both the ClinVarHits slot and the Carrier slot. *)
        ann = Last[cvHg];
        newAnn = Append[ann, <|
            "Carrier" -> filtered,
            "References" -> Append[Lookup[ann, "References", <||>], "CarrierGenePanelVersion" -> version]
        |>];
        HumanGenome[First[cvHg], newAnn]
    ]


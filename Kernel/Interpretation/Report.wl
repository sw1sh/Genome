(* Report.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === aggregate report ===
   GenomeReport aggregates every already-computed interpretation of a
   HumanGenome into one structured, human-readable report per subject: a
   canonical Association keyed by section, plus a shareable rendered HTML
   document written under data/<subject>/report/ (git-ignored).  GenomeReport
   reuses the other interpretation operators and their per-subject sidecars; it
   never re-implements any analysis.

   GenomeReport is FAST by default.  The "Compute" option defaults to "Cached":
   each section is served from the already-computed in-memory slot or, if that
   is empty, from the per-subject sidecar file read directly (a quick Parquet / WXF
   import that never triggers a reference download); a section that has never
   been run is marked Missing["NotComputed"] and listed under the Overview's
   "SectionsNotRun" rather than firing its (possibly multi-minute) compute.
   "Compute" -> "All" runs every interpretation operator (may take minutes);
   "Compute" -> {slot, ...} refreshes only the named slots and serves the rest
   from cache.

   GenomeReport is a terminal aggregation, so it returns the structured
   Association directly (clearer than re-wrapping a HumanGenome for a value
   nothing filters further) and stashes a copy in the per-subject report-cache
   sidecar data/<subject>/report/report.wxf (the persisted "ReportCache"). *)

(* -- section / slot vocabulary -- *)

$reportSectionOrder = {
    "Overview", "Ancestry", "Pharmacogenomics", "ClinicalVariants",
    "CarrierStatus", "PolygenicRiskScores", "Traits", "GWASHighlights",
    "MissenseHighlights"
}

(* The interpretation slots a "Compute" -> "All" refreshes.  PRS is per-trait, so
   there is no single "compute all traits" call; it is always aggregated from
   whatever scores are already cached. *)
$reportAllSlots = {
    "Sex", "Ancestry", "Haplogroups", "Pharmacogenomics", "ClinVarHits",
    "Carrier", "PRS", "Traits", "GWASAssociations", "AlphaMissenseScores"
}

(* Each report section draws on one or more annotation slots. *)
reportSectionSlots["Overview"] := {"Sex"}
reportSectionSlots["Ancestry"] := {"Ancestry", "Haplogroups"}
reportSectionSlots["Pharmacogenomics"] := {"Pharmacogenomics"}
reportSectionSlots["ClinicalVariants"] := {"ClinVarHits"}
reportSectionSlots["CarrierStatus"] := {"Carrier"}
reportSectionSlots["PolygenicRiskScores"] := {"PRS"}
reportSectionSlots["Traits"] := {"Traits"}
reportSectionSlots["GWASHighlights"] := {"GWASAssociations"}
reportSectionSlots["MissenseHighlights"] := {"AlphaMissenseScores"}
reportSectionSlots[_] := {}

(* Localized section title, keyed "Section.<name>" in $reportLabels; falls back
   to the raw section name for an unknown section. *)
reportSectionTitle[section_String, lang_String] := reportLabel["Section." <> section, lang, section]

(* The operator to run to populate a section, named for the "not yet run" note. *)
reportSectionOperator["Ancestry"] := "AncestryEstimate / HaplogroupCall"
reportSectionOperator["Pharmacogenomics"] := "PharmacogenomicProfile"
reportSectionOperator["ClinicalVariants"] := "ClinVarHits"
reportSectionOperator["CarrierStatus"] := "CarrierStatus"
reportSectionOperator["PolygenicRiskScores"] := "PolygenicRiskScore"
reportSectionOperator["Traits"] := "TraitAssociations"
reportSectionOperator["GWASHighlights"] := "GWASAssociations"
reportSectionOperator["MissenseHighlights"] := "AlphaMissenseScores"
reportSectionOperator[_] := "the corresponding interpretation method"

$reportTopN = 15
$reportGenomeWideSignificance = 5.*^-8
$reportCarrierMaxAF = 0.01

(* -- per-subject report directory (git-ignored under data/) -- *)

reportDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "report"}]

reportHTMLPath[hg_] := FileNameJoin[{reportDir[hg], hg["Subject", "ID"] <> "-report.html"}]

reportCachePath[hg_] := FileNameJoin[{reportDir[hg], "report.wxf"}]

(* The variant count is only reported when it is already cached, so the Overview
   never forces a full genome scan. *)
reportVariantCount[hg_] :=
    Block[{cached = First[First[hg]]["VariantCountCache"]},
        If[ IntegerQ[cached], cached, Missing["NotComputed"]]
    ]

(* -- slot resolution (cached hydrate vs operator refresh) -- *)

(* Read one interpretation slot without triggering any compute or download: the
   in-memory slot if populated, else the per-subject sidecar file imported
   directly, else Missing["NotComputed"].  This never calls an interpretation
   operator, so a "Cached" report can never fire a reference download. *)
reportCachedOr[slotValue_, file_String, fmt_String] :=
    Which[
        ! MissingQ[slotValue], slotValue,
        FileExistsQ[file],
            Replace[Quiet @ Import[file, fmt], Except[_Tabular | _Association] -> Missing["NotComputed"]],
        True, Missing["NotComputed"]
    ]

reportHydrateSlot[hg_, "Ancestry"] :=
    reportCachedOr[hg["Ancestry"], ancestrySidecarPath[hg], "WXF"]
reportHydrateSlot[hg_, "Haplogroups"] :=
    reportCachedOr[hg["Haplogroups"], haplogroupSidecarPath[hg], "WXF"]
reportHydrateSlot[hg_, "PRS"] :=
    reportCachedOr[hg["PRS"], prsSidecarWXF[hg], "WXF"]
reportHydrateSlot[hg_, "Pharmacogenomics"] :=
    reportCachedOr[hg["Pharmacogenomics"], pgxSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "ClinVarHits"] :=
    reportCachedOr[hg["ClinVarHits"], clinVarSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "Carrier"] :=
    reportCachedOr[hg["Carrier"], carrierSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "Traits"] :=
    reportCachedOr[hg["Traits"], traitsSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "AlphaMissenseScores"] :=
    reportCachedOr[hg["AlphaMissenseScores"], alphaMissenseSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "GWASAssociations"] :=
    reportCachedOr[hg["GWASAssociations"], gwasSidecarTabular[hg], "Parquet"]
reportHydrateSlot[hg_, "Sex"] :=
    Block[{s = hg["Subject", "Sex"], cached},
        Which[
            StringQ[s], s,
            FileExistsQ[sexSidecarPath[hg]],
                cached = Quiet @ Import[sexSidecarPath[hg], "WXF"];
                If[ AssociationQ[cached] && StringQ[cached["KaryotypeCall"]],
                    cached["KaryotypeCall"],
                    Missing["NotComputed"]
                ],
            True, Missing["NotComputed"]
        ]
    ]

(* Refresh one slot by invoking its interpretation operator (may be slow / may
   download).  Returns the freshly computed slot value, or Missing on failure. *)
reportSlotOf[computed_, slot_String] :=
    If[ MatchQ[computed, _HumanGenome] && HumanGenomeQ[computed],
        computed[slot],
        Missing["NotComputed"]
    ]

reportComputeSlot[hg_, "Ancestry"] :=
    reportSlotOf[Quiet @ Check[AncestryEstimate[hg], hg], "Ancestry"]
reportComputeSlot[hg_, "Haplogroups"] :=
    Block[{h = Quiet @ Check[HaplogroupCall[hg, "mtDNA"], hg]},
        h = Quiet @ Check[HaplogroupCall[h, "Y"], h];
        reportSlotOf[h, "Haplogroups"]
    ]
reportComputeSlot[hg_, "Pharmacogenomics"] :=
    reportSlotOf[Quiet @ Check[PharmacogenomicProfile[hg], hg], "Pharmacogenomics"]
reportComputeSlot[hg_, "ClinVarHits"] :=
    reportSlotOf[Quiet @ Check[ClinVarHits[hg], hg], "ClinVarHits"]
reportComputeSlot[hg_, "Carrier"] :=
    reportSlotOf[Quiet @ Check[CarrierStatus[hg], hg], "Carrier"]
reportComputeSlot[hg_, "Traits"] :=
    reportSlotOf[Quiet @ Check[TraitAssociations[hg], hg], "Traits"]
reportComputeSlot[hg_, "AlphaMissenseScores"] :=
    reportSlotOf[Quiet @ Check[AlphaMissenseScores[hg], hg], "AlphaMissenseScores"]
reportComputeSlot[hg_, "GWASAssociations"] :=
    reportSlotOf[Quiet @ Check[GWASAssociations[hg], hg], "GWASAssociations"]
reportComputeSlot[hg_, "Sex"] :=
    Replace[Quiet @ Check[ChromosomalSex[hg], $Failed], {
        a_Association :> Lookup[a, "KaryotypeCall", Missing["NotComputed"]],
        _ -> Missing["NotComputed"]
    }]
(* PRS has no single "compute all" call; aggregate whatever is already cached. *)
reportComputeSlot[hg_, "PRS"] := reportHydrateSlot[hg, "PRS"]

reportResolveSlot[hg_, slot_String, computeSet_List] :=
    If[ MemberQ[computeSet, slot],
        reportComputeSlot[hg, slot],
        reportHydrateSlot[hg, slot]
    ]

(* -- option resolution -- *)

reportComputeSet[c_] :=
    Which[
        c === "All", $reportAllSlots,
        c === "Cached", {},
        MatchQ[c, {___String}], c,
        True, Message[GenomeReport::badcompute, c]; {}
    ]

reportResolveSections[spec_] :=
    Which[
        spec === All, $reportSectionOrder,
        MatchQ[spec, {___String}],
            Block[{keep = Select[spec, MemberQ[$reportSectionOrder, #] &]},
                If[ keep === {}, Message[GenomeReport::nosections, spec]; $reportSectionOrder, keep]
            ],
        True, Message[GenomeReport::nosections, spec]; $reportSectionOrder
    ]

(* -- section summaries (the compact structured values) -- *)

reportHaploLabel[hap_, kind_String] :=
    If[ AssociationQ[hap] && AssociationQ[hap[kind]],
        Lookup[hap[kind], "Haplogroup", Missing["NotComputed"]],
        Missing["NotComputed"]
    ]

reportAncestrySection[anc_, hap_] :=
    If[ ! AssociationQ[anc] && ! AssociationQ[hap],
        Missing["NotComputed"],
        <|
            "Superpopulation" ->
                If[ AssociationQ[anc], Lookup[anc, "Superpopulation", Missing[]], Missing["NotComputed"]],
            "SuperpopulationFractions" ->
                If[ AssociationQ[anc], Lookup[anc, "SuperpopulationFractions", Missing[]], Missing["NotComputed"]],
            "mtDNAHaplogroup" -> reportHaploLabel[hap, "mtDNA"],
            "YHaplogroup" -> reportHaploLabel[hap, "Y"]
        |>
    ]

reportNormalPhenotypeQ[p_] := StringQ[p] && StringContainsQ[p, "Normal", IgnoreCase -> True]

reportPgxSection[pgx_] :=
    If[ ! MatchQ[pgx, _Tabular],
        Missing["NotComputed"],
        Block[{rows = Normal[pgx], actionable, normalGenes},
            actionable = Select[rows, ! reportNormalPhenotypeQ[#Phenotype] &];
            normalGenes = DeleteDuplicates @ Map[#Gene &, Select[rows, reportNormalPhenotypeQ[#Phenotype] &]];
            <|
                (* Keep the full-column rows so the renderer can both interpret
                   each finding (needs Phenotype / drug / Confidence / activity)
                   and project a compact table from the same data. *)
                "Actionable" -> Tabular[Take[actionable, UpTo[$reportTopN]]],
                "ActionableGuidanceCount" -> Length[actionable],
                "ActionableGeneCount" -> Length[DeleteDuplicates @ Map[#Gene &, actionable]],
                "NormalGeneCount" -> Length[normalGenes],
                "Tabular" -> pgx
            |>
        ]
    ]

reportClinVarSection[cv_] :=
    If[ ! MatchQ[cv, _Tabular],
        Missing["NotComputed"],
        <|
            (* Carry ReviewStatus and VCVAccession too, so each finding's
               interpretation can flag a weak review and demote the accession to
               its footnote; the rendered table projects a compact subset. *)
            "Hits" -> Take[
                cv[[All, {"Gene", "VariantID", "RsID", "ClinicalSignificance", "ReviewStatus",
                    "Condition", "VCVAccession", "Zygosity", "PopulationAF"}]],
                UpTo[$reportTopN]
            ],
            "Count" -> Length[cv],
            "Tabular" -> cv
        |>
    ]

reportCarrierSection[car_] :=
    If[ ! MatchQ[car, _Tabular],
        Missing["NotComputed"],
        Block[{filtered = carrierApplyMaxAF[car, $reportCarrierMaxAF]},
            <|
                (* Carry RsID and Condition too, so each finding's interpretation
                   can name the condition and demote the IDs to its footnote; the
                   rendered table projects a compact subset. *)
                "Carriers" -> Take[
                    filtered[[All, {"Gene", "VariantID", "RsID", "Zygosity", "Inheritance",
                        "CarrierClassification", "Condition", "PopulationAF"}]],
                    UpTo[$reportTopN]
                ],
                "Count" -> Length[filtered],
                "Classifications" ->
                    If[ Length[filtered] > 0, Counts[Normal[filtered][[All, "CarrierClassification"]]], <||>],
                "MaxPopulationAF" -> $reportCarrierMaxAF
            |>
        ]
    ]

reportPRSRow[e_Association] :=
    <|
        "Trait" -> Lookup[e, "Trait", Missing[]],
        "Percentile" -> Lookup[e, "Percentile", Missing[]],
        "PGSID" -> Lookup[e, "PGSID", Missing[]],
        "Coverage" -> Block[{u = Lookup[e, "NVariantsUsed", Missing[]], x = Lookup[e, "NVariantsExpected", Missing[]]},
            If[ IntegerQ[u] && IntegerQ[x] && x > 0, N[u / x], Missing[]]
        ]
    |>

reportPRSSortKey[row_Association] :=
    If[ NumericQ[row["Percentile"]], -row["Percentile"], Infinity]

reportPRSSection[prs_] :=
    If[ ! (AssociationQ[prs] && Length[prs] > 0),
        Missing["NotComputed"],
        Block[{rows = SortBy[Map[reportPRSRow, Values[prs]], reportPRSSortKey]},
            <|
                "Scores" -> Tabular[rows],
                "Count" -> Length[rows]
            |>
        ]
    ]

reportTraitsSection[tr_] :=
    If[ ! MatchQ[tr, _Tabular],
        Missing["NotComputed"],
        <|
            "Top" -> Take[
                tr[[All, {"RsID", "Genotype", "Magnitude", "Repute", "Summary"}]],
                UpTo[$reportTopN]
            ],
            "Count" -> Length[tr]
        |>
    ]

reportGWASSection[gw_] :=
    If[ ! MatchQ[gw, _Tabular],
        Missing["NotComputed"],
        Block[{sig = Select[gw,
            #CarriesRisk === True && NumericQ[#PValue] && #PValue <= $reportGenomeWideSignificance &]},
            <|
                "Top" -> Take[
                    sig[[All, {"RsID", "Trait", "RiskAllele", "RiskAlleleDosage", "OddsRatioOrBeta", "PValue"}]],
                    UpTo[$reportTopN]
                ],
                "CarriedGenomeWideSignificantCount" -> Length[sig]
            |>
        ]
    ]

reportMissenseSection[am_] :=
    If[ ! MatchQ[am, _Tabular],
        Missing["NotComputed"],
        Block[{lp = Select[am, #AMClass === "likely_pathogenic" &]},
            <|
                "Top" -> Take[
                    lp[[All, {"Gene", "ProteinChange", "AMScore", "Zygosity", "Transcript"}]],
                    UpTo[$reportTopN]
                ],
                "LikelyPathogenicCount" -> Length[lp]
            |>
        ]
    ]

reportSectionValue[hg_, "Ancestry", r_] := reportAncestrySection[r["Ancestry"], r["Haplogroups"]]
reportSectionValue[hg_, "Pharmacogenomics", r_] := reportPgxSection[r["Pharmacogenomics"]]
reportSectionValue[hg_, "ClinicalVariants", r_] := reportClinVarSection[r["ClinVarHits"]]
reportSectionValue[hg_, "CarrierStatus", r_] := reportCarrierSection[r["Carrier"]]
reportSectionValue[hg_, "PolygenicRiskScores", r_] := reportPRSSection[r["PRS"]]
reportSectionValue[hg_, "Traits", r_] := reportTraitsSection[r["Traits"]]
reportSectionValue[hg_, "GWASHighlights", r_] := reportGWASSection[r["GWASAssociations"]]
reportSectionValue[hg_, "MissenseHighlights", r_] := reportMissenseSection[r["AlphaMissenseScores"]]
reportSectionValue[_, _, _] := Missing["NotComputed"]

reportOverview[hg_, computeSet_List, sections_List, avail_Association] :=
    <|
        "Subject" -> hg["Subject", "ID"],
        "Sex" -> reportResolveSlot[hg, "Sex", computeSet],
        "Build" -> hg["Build"],
        "Backend" -> hg["Backend"],
        "VariantCount" -> reportVariantCount[hg],
        "ReferenceVersions" -> hg["References"],
        "SectionsIncluded" -> DeleteCases[sections, "Overview"],
        "SectionsAvailable" -> Keys @ Select[avail, TrueQ],
        "SectionsNotRun" -> Keys @ Select[avail, ! TrueQ[#] &]
    |>

reportAssemble[hg_, sections_List, resolved_Association, computeSet_List] :=
    Block[{vals, avail, overview},
        vals = Association @ Map[
            s |-> s -> reportSectionValue[hg, s, resolved],
            DeleteCases[sections, "Overview"]
        ];
        avail = Association @ KeyValueMap[#1 -> ! MissingQ[#2] &, vals];
        overview = reportOverview[hg, computeSet, sections, avail];
        Association @ Map[
            s |-> s -> If[ s === "Overview", overview, vals[s]],
            sections
        ]
    ]

(* -- localization -- *)

(* The report is rendered from a single localization table so a second language
   is a data change, not a second renderer.  Every user-facing string the HTML
   emits (document chrome, caveat, section titles, field labels, table column
   headers, prose, and the controlled-vocabulary DATA terms - metabolizer
   phenotypes, carrier classifications, zygosity, sex karyotype, superpopulation
   codes, imputation quality, and the curated PRS trait names) is a key here.
   Scientific identifiers (gene symbols, rsIDs, star-allele diplotypes,
   haplogroup labels, PGS / PubMed IDs, drug names, and free-text catalog trait
   strings) are NOT translated: they are never keys, so reportLabel returns them
   unchanged.  Each English value is byte-for-byte what the report emitted before
   localization existed, so "Language" -> "English" is unchanged. *)

$reportLanguages = {"English", "Russian"}

(* HTML lang attribute (BCP 47) for the <html> tag. *)
reportHtmlLang["Russian"] := "ru"
reportHtmlLang[_] := "en"

reportLanguage[lang_String] := If[ MemberQ[$reportLanguages, lang], lang, Message[GenomeReport::badlang, lang]; "English"]
reportLanguage[lang_] := (Message[GenomeReport::badlang, lang]; "English")

$reportLabels = <|
    (* section titles *)
    "Section.Overview" -> <|"English" -> "Overview", "Russian" -> "Обзор"|>,
    "Section.Ancestry" -> <|"English" -> "Genetic ancestry and haplogroups", "Russian" -> "Происхождение"|>,
    "Section.Pharmacogenomics" -> <|"English" -> "Pharmacogenomics", "Russian" -> "Фармакогенетика"|>,
    "Section.ClinicalVariants" -> <|"English" -> "Clinical variants (ClinVar)", "Russian" -> "Клинически значимые варианты"|>,
    "Section.CarrierStatus" -> <|"English" -> "Carrier status", "Russian" -> "Носительство"|>,
    "Section.PolygenicRiskScores" -> <|"English" -> "Polygenic risk scores", "Russian" -> "Полигенные шкалы риска"|>,
    "Section.Traits" -> <|"English" -> "Notable traits", "Russian" -> "Признаки"|>,
    "Section.GWASHighlights" -> <|"English" -> "GWAS highlights", "Russian" -> "Ассоциации GWAS"|>,
    "Section.MissenseHighlights" -> <|"English" -> "Missense highlights (AlphaMissense)", "Russian" -> "Миссенс-предсказания (AlphaMissense)"|>,
    (* document chrome *)
    "Doc.Title" -> <|"English" -> "Personal genome report", "Russian" -> "Отчёт по персональному геному"|>,
    "Doc.Subject" -> <|"English" -> "Subject", "Russian" -> "Образец"|>,
    "Doc.Generated" -> <|"English" -> "generated", "Russian" -> "сформирован"|>,
    "Doc.Footer" -> <|
        "English" -> "Generated by WolframInstitute/Genome. Educational and decision-support use only; not a medical document.",
        "Russian" -> "Сформировано WolframInstitute/Genome. Только для образовательного использования и поддержки принятия решений; не является медицинским документом."
    |>,
    (* caveat block *)
    "Caveat.Heading" -> <|"English" -> "Please read first", "Russian" -> "Пожалуйста, прочитайте сначала"|>,
    "Caveat.Lead" -> <|
        "English" -> "This is an <strong>educational, decision-support summary</strong> generated automatically from a personal genome file. It is <strong>not a clinical or diagnostic document</strong> and was not produced under a validated, regulated clinical pipeline.",
        "Russian" -> "Этот отчёт носит <strong>образовательный характер и предназначен для поддержки принятия решений</strong>. Он сформирован автоматически из файла персонального генома и <strong>не является клиническим или диагностическим документом</strong>; он не был получен в рамках валидированного регулируемого клинического процесса."
    |>,
    "Caveat.Bullet1" -> <|
        "English" -> "Estimates are <strong>population-relative</strong>, not individual predictions of health or disease.",
        "Russian" -> "Оценки являются <strong>популяционно-относительными</strong>, а не индивидуальными прогнозами здоровья или заболевания."
    |>,
    "Caveat.Bullet2" -> <|
        "English" -> "Polygenic risk scores and ancestry estimates are calibrated mostly on <strong>European-ancestry</strong> cohorts and are less accurate for other ancestries.",
        "Russian" -> "Полигенные шкалы риска и оценки происхождения откалиброваны преимущественно на когортах <strong>европейского происхождения</strong> и менее точны для других популяций."
    |>,
    "Caveat.Bullet3" -> <|
        "English" -> "The underlying genotypes are largely <strong>imputed</strong> and may contain errors; a single variant call is not confirmation of anything.",
        "Russian" -> "Лежащие в основе генотипы в значительной степени <strong>импутированы</strong> и могут содержать ошибки; отдельный вызов варианта ничего не подтверждает."
    |>,
    "Caveat.Bullet4" -> <|
        "English" -> "A heterozygous carrier of a recessive variant is <strong>healthy</strong>; carrier results are reproductive information, not a diagnosis.",
        "Russian" -> "Гетерозиготный носитель рецессивного варианта <strong>здоров</strong>; результаты по носительству - это репродуктивная информация, а не диагноз."
    |>,
    "Caveat.Bullet5" -> <|
        "English" -> "<strong>Discuss any result with a qualified clinician or genetic counsellor</strong> before acting on it. Do not change medication on the basis of this report.",
        "Russian" -> "<strong>Обсудите любой результат с квалифицированным врачом или генетическим консультантом</strong>, прежде чем предпринимать какие-либо действия. Не меняйте приём лекарств на основании этого отчёта."
    |>,
    (* Overview field labels *)
    "Ov.Subject" -> <|"English" -> "Subject", "Russian" -> "Образец"|>,
    "Ov.Sex" -> <|"English" -> "Genetic sex", "Russian" -> "Генетический пол"|>,
    "Ov.Build" -> <|"English" -> "Reference build", "Russian" -> "Референсная сборка"|>,
    "Ov.Backend" -> <|"English" -> "Backend", "Russian" -> "Бэкенд"|>,
    "Ov.VariantCount" -> <|"English" -> "Variant count", "Russian" -> "Число вариантов"|>,
    "Ov.SectionsPopulated" -> <|"English" -> "Sections populated", "Russian" -> "Заполненные разделы"|>,
    "Ov.SectionsNotRun" -> <|"English" -> "Sections not yet run", "Russian" -> "Ещё не выполненные разделы"|>,
    "Ov.None" -> <|"English" -> "none", "Russian" -> "нет"|>,
    (* Ancestry labels *)
    "Anc.Superpopulation" -> <|"English" -> "Predominant super-population", "Russian" -> "Преобладающая надпопуляция"|>,
    "Anc.mtDNA" -> <|"English" -> "mtDNA haplogroup (maternal)", "Russian" -> "Гаплогруппа мтДНК (материнская)"|>,
    "Anc.Y" -> <|"English" -> "Y haplogroup (paternal)", "Russian" -> "Гаплогруппа Y (отцовская)"|>,
    "Anc.FractionsHeading" -> <|"English" -> "Super-population fractions", "Russian" -> "Доли надпопуляций"|>,
    (* section prose (interleaved with counts) *)
    "Pgx.Prose1" -> <|"English" -> " actionable gene-drug guidance rows across ", "Russian" -> " действенных рекомендаций по паре ген-препарат по "|>,
    "Pgx.Prose2" -> <|"English" -> " gene(s) with a non-normal phenotype; ", "Russian" -> " ген(ам) с ненормальным фенотипом; "|>,
    "Pgx.Prose3" -> <|"English" -> " gene(s) called normal.", "Russian" -> " ген(ов) отнесены к норме."|>,
    "Pgx.Heading" -> <|"English" -> "Actionable phenotypes", "Russian" -> "Действенные фенотипы"|>,
    "CV.Prose1" -> <|"English" -> " Pathogenic / Likely-pathogenic ClinVar hit(s) carried", "Russian" -> " патогенных / вероятно патогенных находок ClinVar в наличии"|>,
    "CV.Prose2" -> <|
        "English" -> ". A ClinVar label plus a high population frequency is usually a common, benign variant.",
        "Russian" -> ". Метка ClinVar вместе с высокой частотой в популяции обычно указывает на распространённый доброкачественный вариант."
    |>,
    "Car.Prose1" -> <|"English" -> " rare carrier / recessive finding(s) at MaxPopulationAF <= ", "Russian" -> " редких находок носительства / рецессивных находок при MaxPopulationAF <= "|>,
    "Car.Prose2" -> <|
        "English" -> ". A heterozygous carrier is healthy; this is reproductive-risk information.",
        "Russian" -> ". Гетерозиготный носитель здоров; это информация о репродуктивном риске."
    |>,
    "Car.Heading" -> <|"English" -> "Classification counts", "Russian" -> "Число по классификациям"|>,
    "PRS.Prose1" -> <|
        "English" -> " polygenic score(s) computed, each shown below with a percentile band and a plain-language reading. The percentile is population-relative, mostly calibrated on European-ancestry cohorts, and is a statistical tendency, not a diagnosis.",
        "Russian" -> " полигенных шкал вычислено, каждая показана ниже с полосой перцентиля и пояснением простым языком. Перцентиль является популяционно-относительным, откалиброван преимущественно на когортах европейского происхождения и представляет собой статистическую тенденцию, а не диагноз."
    |>,
    "Tr.Prose1" -> <|"English" -> " SNPedia-documented trait genotype(s)", "Russian" -> " задокументированных в SNPedia генотипов признаков"|>,
    "GW.Prose1" -> <|"English" -> " carried genome-wide-significant association(s) (p <= 5e-8)", "Russian" -> " несомых полногеномно-значимых ассоциаций (p <= 5e-8)"|>,
    "GW.Prose2" -> <|
        "English" -> ". A GWAS association is a small population-level signal, not a diagnosis.",
        "Russian" -> ". Ассоциация GWAS - это небольшой сигнал на уровне популяции, а не диагноз."
    |>,
    "MS.Prose1" -> <|"English" -> " carried missense variant(s) AlphaMissense calls likely pathogenic", "Russian" -> " несомых миссенс-вариантов AlphaMissense относит к вероятно патогенным"|>,
    "MS.Prose2" -> <|
        "English" -> ". These are computational predictions, not clinical classifications.",
        "Russian" -> ". Это компьютерные предсказания, а не клинические классификации."
    |>,
    (* "showing the top N ..." note pieces (interleaved with N) *)
    "TopN.Pre" -> <|"English" -> " (showing the top ", "Russian" -> " (показаны первые "|>,
    "TopN.Post" -> <|"English" -> ")", "Russian" -> ")"|>,
    "TopN.PostMagnitude" -> <|"English" -> " by magnitude)", "Russian" -> " по значимости)"|>,
    "TopN.PostPValue" -> <|"English" -> " by p-value)", "Russian" -> " по p-значению)"|>,
    "TopN.PostScore" -> <|"English" -> " by score)", "Russian" -> " по баллу)"|>,
    (* not-yet-computed note (operator name kept as an identifier between them) *)
    "NotRun.Pre" -> <|"English" -> "Not yet computed. Run <code>", "Russian" -> "Ещё не вычислено. Выполните <code>"|>,
    "NotRun.Mid" -> <|
        "English" -> "[hg]</code> (or call <code>GenomeReport</code> with <code>\"Compute\" -> \"All\"</code>) to populate it.",
        "Russian" -> "[hg]</code> (или вызовите <code>GenomeReport</code> с <code>\"Compute\" -> \"All\"</code>), чтобы заполнить раздел."
    |>,
    "Table.NoRows" -> <|"English" -> "No rows.", "Russian" -> "Нет строк."|>,
    (* table column headers - the English value equals the raw column key so the
       English report is byte-for-byte unchanged; identifier-named columns
       (RsID, VariantID, PGSID) are deliberately absent and pass through. *)
    "Col.Gene" -> <|"English" -> "Gene", "Russian" -> "Ген"|>,
    "Col.Diplotype" -> <|"English" -> "Diplotype", "Russian" -> "Диплотип"|>,
    "Col.Phenotype" -> <|"English" -> "Phenotype", "Russian" -> "Фенотип"|>,
    "Col.ActionableDrug" -> <|"English" -> "ActionableDrug", "Russian" -> "Препарат"|>,
    "Col.CPICLevel" -> <|"English" -> "CPICLevel", "Russian" -> "Уровень CPIC"|>,
    "Col.ClinicalSignificance" -> <|"English" -> "ClinicalSignificance", "Russian" -> "Клиническая значимость"|>,
    "Col.Zygosity" -> <|"English" -> "Zygosity", "Russian" -> "Зиготность"|>,
    "Col.Condition" -> <|"English" -> "Condition", "Russian" -> "Заболевание"|>,
    "Col.PopulationAF" -> <|"English" -> "PopulationAF", "Russian" -> "Частота в популяции"|>,
    "Col.Inheritance" -> <|"English" -> "Inheritance", "Russian" -> "Тип наследования"|>,
    "Col.CarrierClassification" -> <|"English" -> "CarrierClassification", "Russian" -> "Классификация носительства"|>,
    "Col.Trait" -> <|"English" -> "Trait", "Russian" -> "Признак/фенотип"|>,
    "Col.Percentile" -> <|"English" -> "Percentile", "Russian" -> "Перцентиль"|>,
    "Col.Coverage" -> <|"English" -> "Coverage", "Russian" -> "Покрытие"|>,
    "Col.Genotype" -> <|"English" -> "Genotype", "Russian" -> "Генотип"|>,
    "Col.Magnitude" -> <|"English" -> "Magnitude", "Russian" -> "Магнитуда"|>,
    "Col.Repute" -> <|"English" -> "Repute", "Russian" -> "Репутация"|>,
    "Col.Summary" -> <|"English" -> "Summary", "Russian" -> "Описание"|>,
    "Col.ProteinChange" -> <|"English" -> "ProteinChange", "Russian" -> "Замена в белке"|>,
    "Col.AMScore" -> <|"English" -> "AMScore", "Russian" -> "Балл AlphaMissense"|>,
    "Col.Transcript" -> <|"English" -> "Transcript", "Russian" -> "Транскрипт"|>,
    "Col.RiskAllele" -> <|"English" -> "RiskAllele", "Russian" -> "Аллель риска"|>,
    "Col.RiskAlleleDosage" -> <|"English" -> "RiskAlleleDosage", "Russian" -> "Доза аллеля риска"|>,
    "Col.OddsRatioOrBeta" -> <|"English" -> "OddsRatioOrBeta", "Russian" -> "ОШ или бета"|>,
    "Col.PValue" -> <|"English" -> "PValue", "Russian" -> "P-значение"|>,
    "Col.Super-population" -> <|"English" -> "Super-population", "Russian" -> "Надпопуляция"|>,
    "Col.Fraction" -> <|"English" -> "Fraction", "Russian" -> "Доля"|>,
    "Col.Classification" -> <|"English" -> "Classification", "Russian" -> "Классификация"|>,
    "Col.Count" -> <|"English" -> "Count", "Russian" -> "Число"|>,
    (* controlled-vocabulary DATA terms - the English value is the term itself *)
    "XY" -> <|"English" -> "XY", "Russian" -> "Мужской (XY)"|>,
    "XX" -> <|"English" -> "XX", "Russian" -> "Женский (XX)"|>,
    "Undetermined" -> <|"English" -> "Undetermined", "Russian" -> "Не определён"|>,
    "EUR" -> <|"English" -> "EUR", "Russian" -> "Европейская (EUR)"|>,
    "EAS" -> <|"English" -> "EAS", "Russian" -> "Восточноазиатская (EAS)"|>,
    "SAS" -> <|"English" -> "SAS", "Russian" -> "Южноазиатская (SAS)"|>,
    "AFR" -> <|"English" -> "AFR", "Russian" -> "Африканская (AFR)"|>,
    "AMR" -> <|"English" -> "AMR", "Russian" -> "Американская (AMR)"|>,
    "Normal Metabolizer" -> <|"English" -> "Normal Metabolizer", "Russian" -> "Нормальный метаболизатор"|>,
    "Intermediate Metabolizer" -> <|"English" -> "Intermediate Metabolizer", "Russian" -> "Промежуточный метаболизатор"|>,
    "Poor Metabolizer" -> <|"English" -> "Poor Metabolizer", "Russian" -> "Медленный метаболизатор"|>,
    "Rapid Metabolizer" -> <|"English" -> "Rapid Metabolizer", "Russian" -> "Быстрый метаболизатор"|>,
    "Ultrarapid Metabolizer" -> <|"English" -> "Ultrarapid Metabolizer", "Russian" -> "Сверхбыстрый метаболизатор"|>,
    "Decreased Function" -> <|"English" -> "Decreased Function", "Russian" -> "Сниженная функция"|>,
    "Increased Function" -> <|"English" -> "Increased Function", "Russian" -> "Повышенная функция"|>,
    "Normal Function" -> <|"English" -> "Normal Function", "Russian" -> "Нормальная функция"|>,
    "Poor Function" -> <|"English" -> "Poor Function", "Russian" -> "Низкая функция"|>,
    "Carrier" -> <|"English" -> "Carrier", "Russian" -> "Носитель"|>,
    "Homozygous (possible affected)" -> <|"English" -> "Homozygous (possible affected)", "Russian" -> "Гомозигота (возможно затронут)"|>,
    "Dominant finding" -> <|"English" -> "Dominant finding", "Russian" -> "Доминантная находка"|>,
    "X-linked" -> <|"English" -> "X-linked", "Russian" -> "Х-сцепленный"|>,
    "Unclassified" -> <|"English" -> "Unclassified", "Russian" -> "Не классифицировано"|>,
    "Heterozygous" -> <|"English" -> "Heterozygous", "Russian" -> "Гетерозигота"|>,
    "Homozygous" -> <|"English" -> "Homozygous", "Russian" -> "Гомозигота"|>,
    "Directly sequenced" -> <|"English" -> "Directly sequenced", "Russian" -> "Прямое секвенирование"|>,
    (* curated PRS trait names (a fixed set); external free-text traits are absent *)
    "LDL cholesterol" -> <|"English" -> "LDL cholesterol", "Russian" -> "ЛПНП-холестерин"|>,
    "HDL cholesterol" -> <|"English" -> "HDL cholesterol", "Russian" -> "ЛПВП-холестерин"|>,
    "Triglycerides" -> <|"English" -> "Triglycerides", "Russian" -> "Триглицериды"|>,
    "Total cholesterol" -> <|"English" -> "Total cholesterol", "Russian" -> "Общий холестерин"|>,
    "Type 2 diabetes" -> <|"English" -> "Type 2 diabetes", "Russian" -> "Диабет 2 типа"|>,
    "BMI" -> <|"English" -> "BMI", "Russian" -> "ИМТ"|>,
    "Coronary artery disease" -> <|"English" -> "Coronary artery disease", "Russian" -> "Ишемическая болезнь сердца"|>,
    "Height" -> <|"English" -> "Height", "Russian" -> "Рост"|>,
    "Breast cancer" -> <|"English" -> "Breast cancer", "Russian" -> "Рак молочной железы"|>,
    "Prostate cancer" -> <|"English" -> "Prostate cancer", "Russian" -> "Рак простаты"|>,
    "Alzheimer's" -> <|"English" -> "Alzheimer's", "Russian" -> "Болезнь Альцгеймера"|>,
    "Atrial fibrillation" -> <|"English" -> "Atrial fibrillation", "Russian" -> "Фибрилляция предсердий"|>,
    (* polygenic-risk interpretation: percentile band labels, the percentile
       word, the per-direction plain-language sentence templates (`num` is the
       percentile, `desc` the trait description), the muted PGS / coverage note
       pieces, and the generic fallback description for an uncurated PGS id. *)
    "PRSBand.VeryHigh" -> <|"English" -> "Very high", "Russian" -> "Очень высокий"|>,
    "PRSBand.High" -> <|"English" -> "High", "Russian" -> "Высокий"|>,
    "PRSBand.AboveAvg" -> <|"English" -> "Above average", "Russian" -> "Выше среднего"|>,
    "PRSBand.Average" -> <|"English" -> "Average", "Russian" -> "Средний"|>,
    "PRSBand.BelowAvg" -> <|"English" -> "Below average", "Russian" -> "Ниже среднего"|>,
    "PRSBand.Low" -> <|"English" -> "Low", "Russian" -> "Низкий"|>,
    "PRSBand.VeryLow" -> <|"English" -> "Very low", "Russian" -> "Очень низкий"|>,
    "PRS.PercentileWord" -> <|"English" -> "percentile", "Russian" -> "перцентиль"|>,
    "PRS.CovPre" -> <|"English" -> ", ", "Russian" -> ", использовано "|>,
    "PRS.CovPost" -> <|"English" -> " of variants used", "Russian" -> " вариантов"|>,
    "PRS.GenericDesc" -> <|
        "English" -> "a polygenic score comparing your combined common-variant score with a reference population",
        "Russian" -> "полигенная шкала, сравнивающая ваш суммарный балл по частым вариантам с референсной популяцией"
    |>,
    "PRSInterp.Higher" -> <|
        "English" -> "Higher than about `num`% of people. In plain terms: `desc`. This is a statistical tendency from many common variants, not a measurement of your actual level or a diagnosis; only a clinical test can confirm that.",
        "Russian" -> "Выше, чем примерно у `num`% людей. Проще говоря: `desc`. Это статистическая тенденция по многим частым вариантам, а не измерение вашего фактического уровня и не диагноз; подтвердить это может только клинический анализ."
    |>,
    "PRSInterp.Lower" -> <|
        "English" -> "Lower than about `num`% of people. In plain terms: `desc`. Because a low score is the less-favorable direction here, this is the direction of concern. It is a statistical tendency, not a measurement.",
        "Russian" -> "Ниже, чем примерно у `num`% людей. Проще говоря: `desc`. Поскольку низкий балл здесь менее благоприятен, именно это направление вызывает настороженность. Это статистическая тенденция, а не измерение."
    |>,
    "PRSInterp.Neutral" -> <|
        "English" -> "Higher than about `num`% of people, i.e. a genetic tendency in this direction. In plain terms: `desc`. It is not a health risk.",
        "Russian" -> "Выше, чем примерно у `num`% людей, то есть генетическая тенденция в эту сторону. Проще говоря: `desc`. Это не риск для здоровья."
    |>,
    "PRSInterp.Unknown" -> <|
        "English" -> "Higher than about `num`% of people. In plain terms: `desc`. Whether a higher or lower score is more favorable is not annotated for this score, so it is reported without a good-or-bad judgement.",
        "Russian" -> "Выше, чем примерно у `num`% людей. Проще говоря: `desc`. Для этой шкалы не указано, какой балл благоприятнее - более высокий или более низкий, поэтому результат приводится без оценки."
    |>,
    "PRSInterp.NoPercentile" -> <|
        "English" -> "This score could not be placed on a population distribution (too few of its variants had a usable population frequency), so no percentile is available. The raw score on its own is not interpretable.",
        "Russian" -> "Эту шкалу не удалось разместить на популяционном распределении (слишком мало её вариантов имели пригодную популяционную частоту), поэтому перцентиль недоступен. Сам по себе сырой балл не поддаётся интерпретации."
    |>,
    (* plain-language section intros - a lay sentence or two under each header;
       abbreviations are expanded on first use here so the reader meets each one
       spelled out before it recurs in a table. *)
    "Intro.Overview" -> <|
        "English" -> "This page summarizes what was read from your genome file and which analyses have been run. It is an educational starting point, not a medical result.",
        "Russian" -> "Эта страница обобщает то, что было прочитано из файла вашего генома и какие анализы были выполнены. Это образовательная отправная точка, а не медицинский результат."
    |>,
    "Intro.Ancestry" -> <|
        "English" -> "This places your genome relative to broad continental reference groups and reports your maternal (mitochondrial DNA, mtDNA) and paternal (Y chromosome) deep-ancestry lineages, called haplogroups. The resolution is continental, not country- or ethnicity-level.",
        "Russian" -> "Этот раздел соотносит ваш геном с широкими континентальными референсными группами и сообщает ваши материнскую (митохондриальная ДНК, мтДНК) и отцовскую (Y-хромосома) линии глубокого происхождения, называемые гаплогруппами. Разрешение континентальное, а не на уровне страны или этнической принадлежности."
    |>,
    "Intro.Pharmacogenomics" -> <|
        "English" -> "How your genes may affect your response to certain medications. A metabolizer phenotype describes how quickly your body may process a drug. This is decision-support to discuss with a clinician or pharmacist, not a prescribing instruction.",
        "Russian" -> "Как ваши гены могут влиять на реакцию на некоторые лекарства. Фенотип метаболизатора описывает, насколько быстро ваш организм может перерабатывать препарат. Это поддержка принятия решений для обсуждения с врачом или фармацевтом, а не указание по назначению."
    |>,
    "Intro.ClinicalVariants" -> <|
        "English" -> "Variants in your genome that a public database called ClinVar links to a health condition. A single flagged variant is not a diagnosis: many people carry it harmlessly, especially when it is common in the general population.",
        "Russian" -> "Варианты в вашем геноме, которые публичная база данных под названием ClinVar связывает с заболеванием. Отдельный отмеченный вариант - это не диагноз: многие люди носят его безвредно, особенно если он часто встречается в общей популяции."
    |>,
    "Intro.CarrierStatus" -> <|
        "English" -> "You are a healthy carrier if you have one copy of a variant linked to a recessive condition. Carriers are not affected themselves; this matters mainly for family planning.",
        "Russian" -> "Вы являетесь здоровым носителем, если у вас есть одна копия варианта, связанного с рецессивным заболеванием. Носители сами не больны; это важно главным образом для планирования семьи."
    |>,
    "Intro.PolygenicRiskScores" -> <|
        "English" -> "A polygenic risk score (PRS) estimates your genetic tendency for a common condition compared with a reference population. A high percentile means your combined common-variant score is higher than most people's - it is a statistical tendency, not a diagnosis or a probability of getting the condition.",
        "Russian" -> "Полигенная шкала риска (PRS) оценивает вашу генетическую предрасположенность к распространённому состоянию по сравнению с референсной популяцией. Высокий перцентиль означает, что ваш суммарный балл по частым вариантам выше, чем у большинства людей - это статистическая тенденция, а не диагноз или вероятность заболеть."
    |>,
    "Intro.Traits" -> <|
        "English" -> "Everyday, mostly non-medical traits linked to your genotype in the community catalog SNPedia, such as taste perception or hair type. These are illustrative associations, not predictions.",
        "Russian" -> "Повседневные, в основном немедицинские признаки, связанные с вашим генотипом в общественном каталоге SNPedia, например восприятие вкуса или тип волос. Это иллюстративные ассоциации, а не прогнозы."
    |>,
    "Intro.GWASHighlights" -> <|
        "English" -> "A genome-wide association study (GWAS) links common variants to traits across large populations. Each association here is a small population-level signal, not a diagnosis, and its effect on any one person is usually tiny. Read each row as one published association you carry (you have the trait-linked risk allele); RiskAlleleDosage is how many copies, 1 or 2, you have.",
        "Russian" -> "Полногеномный поиск ассоциаций (GWAS) связывает частые варианты с признаками в больших популяциях. Каждая ассоциация здесь - это небольшой сигнал на уровне популяции, а не диагноз, и её влияние на конкретного человека обычно ничтожно. Читайте каждую строку как одну опубликованную ассоциацию, которую вы несёте (у вас есть связанный с признаком аллель риска); RiskAlleleDosage - это число копий, 1 или 2, которые у вас есть."
    |>,
    "Intro.MissenseHighlights" -> <|
        "English" -> "AlphaMissense is a computer model that predicts whether a missense variant - one that changes a single amino acid in a protein - is likely to be harmful. These are computational predictions to guide attention, not clinical classifications. Each row is one such variant you carry that the model scores as likely harmful; AMScore, from 0 to 1, is the model's confidence, not a clinical verdict.",
        "Russian" -> "AlphaMissense - это компьютерная модель, которая предсказывает, может ли миссенс-вариант (меняющий одну аминокислоту в белке) быть вредным. Это компьютерные предсказания для привлечения внимания, а не клинические классификации. Каждая строка - это один такой несомый вами вариант, который модель считает вероятно вредным; AMScore, от 0 до 1, - это уверенность модели, а не клинический вывод."
    |>,
    "Intro.Glossary" -> <|
        "English" -> "Plain-language definitions of the technical terms used above. Each links to an authoritative educational resource that opens in a new tab.",
        "Russian" -> "Определения технических терминов, использованных выше, простым языком. Каждый связан с авторитетным образовательным ресурсом, который открывается в новой вкладке."
    |>,
    (* glossary appendix chrome *)
    "Gloss.Title" -> <|"English" -> "Glossary", "Russian" -> "Глоссарий"|>,
    "Gloss.LearnMore" -> <|"English" -> "Learn more", "Russian" -> "Подробнее"|>,
    "Gloss.Cat.Variants" -> <|"English" -> "Variants", "Russian" -> "Варианты"|>,
    "Gloss.Cat.FrequencyQuality" -> <|"English" -> "Frequency and quality", "Russian" -> "Частота и качество"|>,
    "Gloss.Cat.Clinical" -> <|"English" -> "Clinical", "Russian" -> "Клинические термины"|>,
    "Gloss.Cat.Risk" -> <|"English" -> "Risk", "Russian" -> "Риск"|>,
    "Gloss.Cat.Ancestry" -> <|"English" -> "Ancestry", "Russian" -> "Происхождение"|>,
    "Gloss.Cat.Pharmacogenomics" -> <|"English" -> "Pharmacogenomics", "Russian" -> "Фармакогенетика"|>,
    (* pharmacogenomics per-finding interpretation: a plain-language sentence
       keyed by metabolizer-phenotype category (`drug` is the drug name), a
       low-confidence flag, a no-drug fallback, and the muted diplotype / CPIC /
       activity-score footnote template (`dip`, `lvl`, `act`). *)
    "PgxInterp.Normal" -> <|
        "English" -> "Standard response expected; usual dosing of `drug` is typically appropriate.",
        "Russian" -> "Ожидается стандартная реакция; обычная дозировка препарата `drug`, как правило, подходит."
    |>,
    "PgxInterp.Poor" -> <|
        "English" -> "You may process `drug` differently (typically more slowly, or with reduced transport); this can change effectiveness or side-effect risk - discuss dosing with a clinician or pharmacist.",
        "Russian" -> "Вы можете перерабатывать препарат `drug` иначе (обычно медленнее или со сниженным транспортом); это может менять эффективность или риск побочных эффектов - обсудите дозировку с врачом или фармацевтом."
    |>,
    "PgxInterp.Intermediate" -> <|
        "English" -> "Your response to `drug` may be somewhat reduced; this may warrant attention - discuss with a clinician or pharmacist.",
        "Russian" -> "Ваша реакция на препарат `drug` может быть несколько снижена; это может потребовать внимания - обсудите с врачом или фармацевтом."
    |>,
    "PgxInterp.Rapid" -> <|
        "English" -> "You may process `drug` faster than usual, which can reduce effectiveness (or, for a prodrug, raise active drug levels) - discuss with a clinician.",
        "Russian" -> "Вы можете перерабатывать препарат `drug` быстрее обычного, что может снижать эффективность (или, для пролекарства, повышать уровень активного вещества) - обсудите с врачом."
    |>,
    "PgxInterp.Other" -> <|
        "English" -> "Your genetically predicted response to `drug` may differ from the usual - discuss with a clinician or pharmacist.",
        "Russian" -> "Ваша генетически предсказанная реакция на препарат `drug` может отличаться от обычной - обсудите с врачом или фармацевтом."
    |>,
    "PgxInterp.NoDrug" -> <|
        "English" -> "This gene shows a non-standard result, but no specific CPIC level-A medication guidance applies to it here.",
        "Russian" -> "Этот ген показывает нестандартный результат, но конкретных рекомендаций CPIC уровня A по препаратам для него здесь нет."
    |>,
    "PgxInterp.LowConfidence" -> <|
        "English" -> "This gene could only be partially read from this data - treat the call as tentative.",
        "Russian" -> "Этот ген удалось прочитать из этих данных лишь частично - считайте результат предварительным."
    |>,
    "Pgx.Meta" -> <|
        "English" -> "Diplotype `dip`; CPIC level `lvl`; activity score `act`.",
        "Russian" -> "Диплотип `dip`; уровень CPIC `lvl`; балл активности `act`."
    |>,
    (* clinical-variant per-finding interpretation: carrying + zygosity, what the
       condition is, the frequency reality (common variants with legacy pathogenic
       labels are a known false-alarm source), and the not-a-diagnosis / weak-review
       caveat.  `copies`, `cond`, `pct` are slots. *)
    "CV.OneCopy" -> <|"English" -> "one copy", "Russian" -> "одну копию"|>,
    "CV.TwoCopies" -> <|"English" -> "two copies", "Russian" -> "две копии"|>,
    "CV.SomeCopies" -> <|"English" -> "a copy", "Russian" -> "копию"|>,
    "CV.NoCondition" -> <|"English" -> "a health condition", "Russian" -> "заболевание"|>,
    "CVInterp.Finding" -> <|
        "English" -> "You carry `copies` of this variant, which ClinVar links to `cond`.",
        "Russian" -> "Вы несёте `copies` этого варианта, который ClinVar связывает с состоянием: `cond`."
    |>,
    "CVInterp.Common" -> <|
        "English" -> " This variant is common in the general population (about `pct`% of people carry it), so despite the pathogenic label it is very unlikely to cause disease on its own - common variants with legacy pathogenic labels are a known source of false alarms.",
        "Russian" -> " Этот вариант часто встречается в общей популяции (его несут примерно `pct`% людей), поэтому, несмотря на метку патогенности, он сам по себе очень маловероятно вызывает заболевание - частые варианты со старыми метками патогенности являются известным источником ложных тревог."
    |>,
    "CVInterp.Rare" -> <|
        "English" -> " This is a rare variant.",
        "Russian" -> " Это редкий вариант."
    |>,
    "CVInterp.Uncommon" -> <|
        "English" -> " This variant is uncommon in the general population.",
        "Russian" -> " Этот вариант нечасто встречается в общей популяции."
    |>,
    "CVInterp.NotDiagnosis" -> <|
        "English" -> " A ClinVar label is not a diagnosis, and many labeled variants are harmless in any given person.",
        "Russian" -> " Метка ClinVar - это не диагноз, и многие отмеченные варианты безвредны для конкретного человека."
    |>,
    "CVInterp.WeakReview" -> <|
        "English" -> " This entry also has a low ClinVar review status (weak or no assertion criteria), which is lower-evidence.",
        "Russian" -> " У этой записи к тому же низкий статус проверки в ClinVar (слабые критерии или их отсутствие), что означает менее надёжные данные."
    |>,
    (* carrier-status per-finding interpretation: healthy-carrier / reproductive
       framing, with distinct notes for a homozygous (possible affected) and a
       dominant finding.  `cond`, `gene` are slots. *)
    "CarInterp.Carrier" -> <|
        "English" -> "You carry one copy of a variant linked to `cond` (`gene`). As a healthy carrier you are not affected; recessive conditions generally require two copies. This matters mainly for family planning - it is relevant if a reproductive partner also carries a variant in the same gene.",
        "Russian" -> "Вы несёте одну копию варианта, связанного с состоянием `cond` (`gene`). Будучи здоровым носителем, вы не больны; для рецессивных состояний обычно нужны две копии. Это важно главным образом для планирования семьи - это имеет значение, если репродуктивный партнёр также несёт вариант в том же гене."
    |>,
    "CarInterp.Homozygous" -> <|
        "English" -> "Two copies of a variant linked to `cond` (`gene`) were seen. Unlike a healthy single-copy carrier, two copies of a recessive variant can be associated with the condition - this warrants clinical review.",
        "Russian" -> "Обнаружены две копии варианта, связанного с состоянием `cond` (`gene`). В отличие от здорового носителя с одной копией, две копии рецессивного варианта могут быть связаны с заболеванием - это требует клинической оценки."
    |>,
    "CarInterp.Dominant" -> <|
        "English" -> "You carry a variant linked to `cond` (`gene`) in a gene that acts dominantly, so a single copy may be relevant - discuss with a clinician.",
        "Russian" -> "Вы несёте вариант, связанный с состоянием `cond` (`gene`), в гене с доминантным типом действия, поэтому даже одна копия может иметь значение - обсудите с врачом."
    |>,
    "CarInterp.XLinked" -> <|
        "English" -> "You carry a variant linked to `cond` (`gene`) on the X chromosome. X-linked inheritance can affect relatives differently depending on sex - discuss with a clinician.",
        "Russian" -> "Вы несёте вариант, связанный с состоянием `cond` (`gene`), на X-хромосоме. Х-сцепленное наследование может по-разному затрагивать родственников в зависимости от пола - обсудите с врачом."
    |>,
    "CarInterp.Other" -> <|
        "English" -> "You carry a variant linked to `cond` (`gene`). Discuss its relevance for you and your family with a clinician.",
        "Russian" -> "Вы несёте вариант, связанный с состоянием `cond` (`gene`). Обсудите его значение для вас и вашей семьи с врачом."
    |>,
    (* ancestry per-finding framing: the continental best-match caveat, the
       coarse-fractions / statistical-noise note, and the maternal / paternal
       single-lineage haplogroup caveat.  `pop`, `mt`, `y` are slots. *)
    "AncInterp.Super" -> <|
        "English" -> "Your genome most closely matches the `pop` continental reference group - the best broad match, not a country or ethnicity.",
        "Russian" -> "Ваш геном наиболее близок к континентальной референсной группе `pop` - это наилучшее широкое соответствие, а не страна или этническая принадлежность."
    |>,
    "AncInterp.Continental" -> <|
        "English" -> "Genetic ancestry here is estimated at the continental scale (for example European or East Asian), not as a country or ethnic-group assignment.",
        "Russian" -> "Генетическое происхождение здесь оценивается в континентальном масштабе (например, европейское или восточноазиатское), а не как принадлежность к стране или этнической группе."
    |>,
    "AncInterp.Fractions" -> <|
        "English" -> "The breakdown below is coarse. Small non-dominant fractions are usually statistical noise, not evidence of real recent admixture.",
        "Russian" -> "Приведённая ниже разбивка является грубой. Небольшие недоминирующие доли обычно представляют собой статистический шум, а не свидетельство реального недавнего смешения происхождения."
    |>,
    "AncInterp.HaploBoth" -> <|
        "English" -> "Your mitochondrial (mtDNA) haplogroup `mt` traces your direct maternal line back thousands of years; your Y haplogroup `y` traces your direct paternal line. These are two single lineages out of your thousands of ancestors, not your overall ancestry.",
        "Russian" -> "Ваша митохондриальная (мтДНК) гаплогруппа `mt` прослеживает вашу прямую материнскую линию на тысячи лет назад; ваша Y-гаплогруппа `y` прослеживает вашу прямую отцовскую линию. Это две отдельные линии из ваших тысяч предков, а не ваше происхождение в целом."
    |>,
    "AncInterp.HaploMt" -> <|
        "English" -> "Your mitochondrial (mtDNA) haplogroup `mt` traces your direct maternal line back thousands of years. This is a single lineage out of your thousands of ancestors, not your overall ancestry.",
        "Russian" -> "Ваша митохондриальная (мтДНК) гаплогруппа `mt` прослеживает вашу прямую материнскую линию на тысячи лет назад. Это одна линия из ваших тысяч предков, а не ваше происхождение в целом."
    |>,
    "AncInterp.HaploY" -> <|
        "English" -> "Your Y haplogroup `y` traces your direct paternal line back thousands of years. This is a single lineage out of your thousands of ancestors, not your overall ancestry.",
        "Russian" -> "Ваша Y-гаплогруппа `y` прослеживает вашу прямую отцовскую линию на тысячи лет назад. Это одна линия из ваших тысяч предков, а не ваше происхождение в целом."
    |>,
    (* sex karyotype one-liner (Overview): what the call means, in plain language. *)
    "Ov.SexNotePre" -> <|
        "English" -> "Genetic sex is inferred from the balance of X and Y chromosome signal and reflects chromosomal sex, not gender identity: ",
        "Russian" -> "Генетический пол определяется по соотношению сигнала X- и Y-хромосом и отражает хромосомный пол, а не гендерную идентичность: "
    |>,
    "SexNote.XY" -> <|
        "English" -> "one X and one Y chromosome (typical male karyotype).",
        "Russian" -> "одна X- и одна Y-хромосома (типичный мужской кариотип)."
    |>,
    "SexNote.XX" -> <|
        "English" -> "two X chromosomes (typical female karyotype).",
        "Russian" -> "две X-хромосомы (типичный женский кариотип)."
    |>,
    "SexNote.Other" -> <|
        "English" -> "an atypical or undetermined sex-chromosome pattern; interpret with care.",
        "Russian" -> "нетипичный или неопределённый набор половых хромосом; интерпретируйте с осторожностью."
    |>
|>

(* Look up a localized string.  An unknown key (a scientific identifier or an
   external free-text term) resolves to the supplied default, which defaults to
   the key itself; a non-string key (e.g. a Missing value) passes through. *)
reportLabel[key_String, lang_String, default_] :=
    Block[{entry = Lookup[$reportLabels, key, Missing[]]},
        If[ AssociationQ[entry], Lookup[entry, lang, default], default]
    ]
reportLabel[key_String, lang_String] := reportLabel[key, lang, key]
reportLabel[x_, _] := x
reportLabel[x_, _, default_] := default

(* Localized column header; unknown (identifier-named) columns keep their key. *)
reportColHeader[col_String, lang_String] := reportLabel["Col." <> col, lang, col]

(* -- glossary appendix -- *)

(* Every technical term the report can emit, defined in one plain sentence per
   language, grouped into a category, and linked to an authoritative educational
   resource.  This is a curated data table: each entry is a term, an English and
   a Russian definition, and a URL (with an optional Russian-specific URL and an
   optional Russian display term).  Every URL was checked to resolve.  The
   category order and the "Gloss.Cat.<name>" labels drive the rendered
   subheadings. *)
$reportGlossaryCategories = {
    "Variants", "FrequencyQuality", "Clinical", "Risk", "Ancestry", "Pharmacogenomics"
}

$reportGlossary = {
    (* Variants *)
    <|
        "Term" -> "Variant", "TermRU" -> "Вариант", "Category" -> "Variants",
        "DefinitionEN" -> "A place where your DNA differs from the standard reference sequence.",
        "DefinitionRU" -> "Место, где ваша ДНК отличается от стандартной референсной последовательности.",
        "URL" -> "https://medlineplus.gov/genetics/understanding/mutationsanddisorders/genemutation/"
    |>,
    <|
        "Term" -> "SNP (single-nucleotide polymorphism)", "TermRU" -> "SNP (однонуклеотидный полиморфизм)",
        "Category" -> "Variants",
        "DefinitionEN" -> "A variant at a single DNA letter that is common in the population.",
        "DefinitionRU" -> "Вариант в одной букве ДНК, часто встречающийся в популяции.",
        "URL" -> "https://en.wikipedia.org/wiki/Single-nucleotide_polymorphism",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Однонуклеотидный_полиморфизм"
    |>,
    <|
        "Term" -> "rsID", "Category" -> "Variants",
        "DefinitionEN" -> "A stable catalog identifier (such as rs53576) that names a specific known variant across databases.",
        "DefinitionRU" -> "Устойчивый идентификатор из каталога (например, rs53576), обозначающий конкретный известный вариант в разных базах данных.",
        "URL" -> "https://en.wikipedia.org/wiki/DbSNP"
    |>,
    <|
        "Term" -> "Allele", "TermRU" -> "Аллель", "Category" -> "Variants",
        "DefinitionEN" -> "One specific version of the DNA sequence at a given position, for example the A version versus the G version.",
        "DefinitionRU" -> "Конкретный вариант последовательности ДНК в данной позиции, например вариант A против варианта G.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Allele",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Аллель"
    |>,
    <|
        "Term" -> "Genotype", "TermRU" -> "Генотип", "Category" -> "Variants",
        "DefinitionEN" -> "The pair of alleles you carry at a position, one inherited from each parent.",
        "DefinitionRU" -> "Пара аллелей, которые вы несёте в данной позиции, по одному от каждого родителя.",
        "URL" -> "https://www.genome.gov/genetics-glossary/genotype",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Генотип"
    |>,
    <|
        "Term" -> "Reference and alternate allele", "TermRU" -> "Референсный и альтернативный аллель",
        "Category" -> "Variants",
        "DefinitionEN" -> "The reference allele is the letter in the standard genome; the alternate is the differing letter your genome carries.",
        "DefinitionRU" -> "Референсный аллель - это буква в стандартном геноме; альтернативный - отличающаяся буква, которую несёт ваш геном.",
        "URL" -> "https://en.wikipedia.org/wiki/Reference_genome"
    |>,
    <|
        "Term" -> "Zygosity", "TermRU" -> "Зиготность", "Category" -> "Variants",
        "DefinitionEN" -> "Whether your two copies at a position match or differ.",
        "DefinitionRU" -> "Совпадают или различаются две ваши копии в данной позиции.",
        "URL" -> "https://en.wikipedia.org/wiki/Zygosity"
    |>,
    <|
        "Term" -> "Heterozygous", "TermRU" -> "Гетерозигота", "Category" -> "Variants",
        "DefinitionEN" -> "Your two copies at a position carry different alleles.",
        "DefinitionRU" -> "Две ваши копии в данной позиции несут разные аллели.",
        "URL" -> "https://www.genome.gov/genetics-glossary/heterozygous",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Гетерозигота"
    |>,
    <|
        "Term" -> "Homozygous", "TermRU" -> "Гомозигота", "Category" -> "Variants",
        "DefinitionEN" -> "Your two copies at a position carry the same allele.",
        "DefinitionRU" -> "Две ваши копии в данной позиции несут одинаковый аллель.",
        "URL" -> "https://www.genome.gov/genetics-glossary/homozygous",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Гомозигота"
    |>,
    <|
        "Term" -> "Indel", "TermRU" -> "Индел (вставка или делеция)", "Category" -> "Variants",
        "DefinitionEN" -> "A short insertion or deletion of DNA letters, as opposed to a single-letter swap.",
        "DefinitionRU" -> "Короткая вставка или делеция букв ДНК, в отличие от замены одной буквы.",
        "URL" -> "https://en.wikipedia.org/wiki/Indel"
    |>,
    (* Frequency and quality *)
    <|
        "Term" -> "Allele frequency", "TermRU" -> "Частота аллеля", "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "How common an allele is in a population, from 0 to 1.",
        "DefinitionRU" -> "Насколько часто аллель встречается в популяции, от 0 до 1.",
        "URL" -> "https://en.wikipedia.org/wiki/Allele_frequency"
    |>,
    <|
        "Term" -> "MAF (minor allele frequency)", "TermRU" -> "MAF (частота минорного аллеля)",
        "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "The frequency of the less common allele at a site; a high MAF usually marks a common, harmless variant.",
        "DefinitionRU" -> "Частота менее распространённого аллеля в позиции; высокий MAF обычно указывает на частый безвредный вариант.",
        "URL" -> "https://en.wikipedia.org/wiki/Minor_allele_frequency"
    |>,
    <|
        "Term" -> "gnomAD", "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "A large public database of allele frequencies from many populations, used to judge how common a variant is.",
        "DefinitionRU" -> "Крупная публичная база данных частот аллелей из многих популяций, используемая для оценки распространённости варианта.",
        "URL" -> "https://gnomad.broadinstitute.org/"
    |>,
    <|
        "Term" -> "Imputation", "TermRU" -> "Импутация", "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "Statistically inferring genotypes that were not directly measured, using patterns from reference populations.",
        "DefinitionRU" -> "Статистический вывод генотипов, которые не были измерены напрямую, на основе закономерностей в референсных популяциях.",
        "URL" -> "https://en.wikipedia.org/wiki/Imputation_(genetics)"
    |>,
    <|
        "Term" -> "R2 (imputation quality)", "TermRU" -> "R2 (качество импутации)",
        "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "A score from 0 to 1 estimating how reliable an imputed genotype is; higher is better.",
        "DefinitionRU" -> "Оценка от 0 до 1, показывающая надёжность импутированного генотипа; чем выше, тем лучше.",
        "URL" -> "https://en.wikipedia.org/wiki/Imputation_(genetics)"
    |>,
    <|
        "Term" -> "Directly sequenced vs imputed", "TermRU" -> "Прямое секвенирование против импутации",
        "Category" -> "FrequencyQuality",
        "DefinitionEN" -> "Directly sequenced genotypes were actually measured; imputed ones were statistically inferred and are less certain.",
        "DefinitionRU" -> "Прямо секвенированные генотипы были действительно измерены; импутированные выведены статистически и менее надёжны.",
        "URL" -> "https://en.wikipedia.org/wiki/SNP_array"
    |>,
    (* Clinical *)
    <|
        "Term" -> "ClinVar", "Category" -> "Clinical",
        "DefinitionEN" -> "A public archive that links specific variants to health conditions and clinical-significance labels.",
        "DefinitionRU" -> "Публичный архив, связывающий конкретные варианты с заболеваниями и метками клинической значимости.",
        "URL" -> "https://www.ncbi.nlm.nih.gov/clinvar/"
    |>,
    <|
        "Term" -> "Pathogenic / likely pathogenic", "TermRU" -> "Патогенный / вероятно патогенный",
        "Category" -> "Clinical",
        "DefinitionEN" -> "ClinVar labels meaning a variant is judged to cause, or probably cause, disease.",
        "DefinitionRU" -> "Метки ClinVar, означающие, что вариант признан вызывающим или вероятно вызывающим заболевание.",
        "URL" -> "https://www.ncbi.nlm.nih.gov/clinvar/docs/clinsig/"
    |>,
    <|
        "Term" -> "Variant of uncertain significance (VUS)", "TermRU" -> "Вариант неопределённой значимости (VUS)",
        "Category" -> "Clinical",
        "DefinitionEN" -> "A variant for which the evidence is not yet enough to call it harmful or harmless.",
        "DefinitionRU" -> "Вариант, для которого пока недостаточно данных, чтобы признать его вредным или безвредным.",
        "URL" -> "https://en.wikipedia.org/wiki/Variant_of_uncertain_significance"
    |>,
    <|
        "Term" -> "Carrier", "TermRU" -> "Носитель", "Category" -> "Clinical",
        "DefinitionEN" -> "A healthy person with one copy of a recessive variant, who could pass it to children.",
        "DefinitionRU" -> "Здоровый человек с одной копией рецессивного варианта, который может передать её детям.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Carrier"
    |>,
    <|
        "Term" -> "Recessive", "TermRU" -> "Рецессивный", "Category" -> "Clinical",
        "DefinitionEN" -> "An inheritance pattern where two copies of a variant are needed to cause the condition.",
        "DefinitionRU" -> "Тип наследования, при котором для проявления заболевания нужны две копии варианта.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Recessive"
    |>,
    <|
        "Term" -> "Dominant", "TermRU" -> "Доминантный", "Category" -> "Clinical",
        "DefinitionEN" -> "An inheritance pattern where a single copy of a variant can cause the condition.",
        "DefinitionRU" -> "Тип наследования, при котором одной копии варианта достаточно для проявления заболевания.",
        "URL" -> "https://www.genome.gov/genetics-glossary/dominant"
    |>,
    <|
        "Term" -> "ACMG", "Category" -> "Clinical",
        "DefinitionEN" -> "The professional body whose guidelines labs use to classify variants from benign to pathogenic.",
        "DefinitionRU" -> "Профессиональное сообщество, по чьим рекомендациям лаборатории классифицируют варианты от доброкачественных до патогенных.",
        "URL" -> "https://en.wikipedia.org/wiki/American_College_of_Medical_Genetics_and_Genomics"
    |>,
    <|
        "Term" -> "AlphaMissense", "Category" -> "Clinical",
        "DefinitionEN" -> "An AI model that predicts whether a protein-changing (missense) variant is likely to be harmful.",
        "DefinitionRU" -> "Модель искусственного интеллекта, предсказывающая, вреден ли, вероятно, вариант, меняющий белок (миссенс).",
        "URL" -> "https://github.com/google-deepmind/alphamissense"
    |>,
    <|
        "Term" -> "Missense variant", "TermRU" -> "Миссенс-вариант", "Category" -> "Clinical",
        "DefinitionEN" -> "A variant that changes one amino acid in a protein, which may or may not affect its function.",
        "DefinitionRU" -> "Вариант, меняющий одну аминокислоту в белке, что может влиять или не влиять на его функцию.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Missense-Mutation"
    |>,
    <|
        "Term" -> "Penetrance", "TermRU" -> "Пенетрантность", "Category" -> "Clinical",
        "DefinitionEN" -> "The share of people carrying a variant who actually develop the associated trait or disease.",
        "DefinitionRU" -> "Доля людей с вариантом, у которых действительно развивается связанный признак или заболевание.",
        "URL" -> "https://en.wikipedia.org/wiki/Penetrance",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Пенетрантность"
    |>,
    (* Risk *)
    <|
        "Term" -> "GWAS (genome-wide association study)", "TermRU" -> "GWAS (полногеномный поиск ассоциаций)",
        "Category" -> "Risk",
        "DefinitionEN" -> "A study that scans many genomes to find common variants statistically linked to a trait.",
        "DefinitionRU" -> "Исследование, сканирующее множество геномов для поиска частых вариантов, статистически связанных с признаком.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Genome-Wide-Association-Studies"
    |>,
    <|
        "Term" -> "Risk allele", "TermRU" -> "Аллель риска", "Category" -> "Risk",
        "DefinitionEN" -> "The version of a variant that a study associated with slightly higher odds of a trait.",
        "DefinitionRU" -> "Вариант аллеля, который исследование связало с немного повышенной вероятностью признака.",
        "URL" -> "https://www.ebi.ac.uk/gwas/home"
    |>,
    <|
        "Term" -> "Odds ratio (OR)", "TermRU" -> "Отношение шансов (ОШ)", "Category" -> "Risk",
        "DefinitionEN" -> "A number describing how much a variant changes the odds of a trait; 1 means no effect.",
        "DefinitionRU" -> "Число, показывающее, насколько вариант меняет шансы признака; 1 означает отсутствие эффекта.",
        "URL" -> "https://en.wikipedia.org/wiki/Odds_ratio",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Отношение_шансов"
    |>,
    <|
        "Term" -> "Effect size", "TermRU" -> "Величина эффекта", "Category" -> "Risk",
        "DefinitionEN" -> "How strongly a variant is estimated to contribute to a trait; most common variants have tiny effects.",
        "DefinitionRU" -> "Насколько сильно вариант, по оценке, влияет на признак; большинство частых вариантов имеют крошечный эффект.",
        "URL" -> "https://en.wikipedia.org/wiki/Effect_size"
    |>,
    <|
        "Term" -> "PRS (polygenic risk score)", "TermRU" -> "PRS (полигенная шкала риска)",
        "Category" -> "Risk",
        "DefinitionEN" -> "A single number that adds up the small effects of many common variants to estimate genetic predisposition.",
        "DefinitionRU" -> "Единое число, суммирующее небольшие эффекты множества частых вариантов для оценки генетической предрасположенности.",
        "URL" -> "https://en.wikipedia.org/wiki/Polygenic_score"
    |>,
    <|
        "Term" -> "Percentile", "TermRU" -> "Перцентиль", "Category" -> "Risk",
        "DefinitionEN" -> "Where your score falls relative to a reference group; the 90th percentile means higher than 90% of them.",
        "DefinitionRU" -> "Где находится ваш балл относительно референсной группы; 90-й перцентиль означает выше, чем у 90% из них.",
        "URL" -> "https://en.wikipedia.org/wiki/Percentile",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Процентиль"
    |>,
    <|
        "Term" -> "PGS Catalog", "Category" -> "Risk",
        "DefinitionEN" -> "An open catalog of published polygenic scores and how they were built.",
        "DefinitionRU" -> "Открытый каталог опубликованных полигенных шкал и того, как они были построены.",
        "URL" -> "https://www.pgscatalog.org/"
    |>,
    (* Ancestry *)
    <|
        "Term" -> "Haplogroup", "TermRU" -> "Гаплогруппа", "Category" -> "Ancestry",
        "DefinitionEN" -> "A labelled branch of the human family tree traced through mtDNA or the Y chromosome.",
        "DefinitionRU" -> "Помеченная ветвь генеалогического древа человечества, прослеживаемая по мтДНК или Y-хромосоме.",
        "URL" -> "https://en.wikipedia.org/wiki/Haplogroup",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Гаплогруппа"
    |>,
    <|
        "Term" -> "Mitochondrial DNA (mtDNA)", "TermRU" -> "Митохондриальная ДНК (мтДНК)",
        "Category" -> "Ancestry",
        "DefinitionEN" -> "A small piece of DNA passed nearly unchanged from mother to child, tracing the direct maternal line.",
        "DefinitionRU" -> "Небольшой участок ДНК, передаваемый почти без изменений от матери к ребёнку и прослеживающий прямую материнскую линию.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Mitochondrial-DNA",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Митохондриальная_ДНК"
    |>,
    <|
        "Term" -> "Y chromosome", "TermRU" -> "Y-хромосома", "Category" -> "Ancestry",
        "DefinitionEN" -> "A chromosome passed from father to son, tracing the direct paternal line.",
        "DefinitionRU" -> "Хромосома, передаваемая от отца к сыну и прослеживающая прямую отцовскую линию.",
        "URL" -> "https://www.genome.gov/genetics-glossary/Y-Chromosome",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Y-хромосома"
    |>,
    <|
        "Term" -> "Superpopulation", "TermRU" -> "Надпопуляция", "Category" -> "Ancestry",
        "DefinitionEN" -> "A broad continental ancestry grouping (such as European or East Asian) used as a reference.",
        "DefinitionRU" -> "Широкая континентальная группа происхождения (например, европейская или восточноазиатская), используемая как референс.",
        "URL" -> "https://www.internationalgenome.org/"
    |>,
    <|
        "Term" -> "Admixture", "TermRU" -> "Смешанное происхождение", "Category" -> "Ancestry",
        "DefinitionEN" -> "Having ancestry from two or more distinct populations mixed together.",
        "DefinitionRU" -> "Наличие происхождения из двух или более различных популяций, смешанных вместе.",
        "URL" -> "https://en.wikipedia.org/wiki/Genetic_admixture"
    |>,
    <|
        "Term" -> "PCA (principal component analysis)", "TermRU" -> "PCA (метод главных компонент)",
        "Category" -> "Ancestry",
        "DefinitionEN" -> "A math technique that summarizes genome-wide patterns into a few numbers to compare ancestry.",
        "DefinitionRU" -> "Математический метод, обобщающий полногеномные закономерности в несколько чисел для сравнения происхождения.",
        "URL" -> "https://en.wikipedia.org/wiki/Principal_component_analysis",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Метод_главных_компонент"
    |>,
    <|
        "Term" -> "Reference build (GRCh37/hg19)", "TermRU" -> "Референсная сборка (GRCh37/hg19)",
        "Category" -> "Ancestry",
        "DefinitionEN" -> "A specific version of the standard human genome that fixes the coordinate system your data uses.",
        "DefinitionRU" -> "Конкретная версия стандартного генома человека, задающая систему координат, которую использует ваша выборка данных.",
        "URL" -> "https://en.wikipedia.org/wiki/Reference_genome"
    |>,
    (* Pharmacogenomics *)
    <|
        "Term" -> "Pharmacogene", "TermRU" -> "Фармакоген", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A gene whose variants can change how you respond to a medication.",
        "DefinitionRU" -> "Ген, варианты которого могут менять вашу реакцию на лекарство.",
        "URL" -> "https://medlineplus.gov/genetics/understanding/genomicresearch/pharmacogenomics/"
    |>,
    <|
        "Term" -> "Star allele", "TermRU" -> "Звёздный аллель", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "Standard shorthand (such as *1 or *2) naming a specific version of a pharmacogene.",
        "DefinitionRU" -> "Стандартное обозначение (например, *1 или *2) для конкретной версии фармакогена.",
        "URL" -> "https://www.pharmvar.org/"
    |>,
    <|
        "Term" -> "Diplotype", "TermRU" -> "Диплотип", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "The pair of star alleles you carry for a pharmacogene, such as *1/*2.",
        "DefinitionRU" -> "Пара звёздных аллелей, которые вы несёте для фармакогена, например *1/*2.",
        "URL" -> "https://www.pharmvar.org/"
    |>,
    <|
        "Term" -> "Metabolizer phenotype", "TermRU" -> "Фенотип метаболизатора",
        "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A category (poor, intermediate, normal, rapid, or ultrarapid) for how fast you process certain drugs.",
        "DefinitionRU" -> "Категория (медленный, промежуточный, нормальный, быстрый или сверхбыстрый) того, насколько быстро вы перерабатываете определённые препараты.",
        "URL" -> "https://cpicpgx.org/resources/term-standardization/"
    |>,
    <|
        "Term" -> "CYP enzymes", "TermRU" -> "Ферменты CYP", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A family of liver enzymes (such as CYP2D6 and CYP2C19) that break down many common medications.",
        "DefinitionRU" -> "Семейство ферментов печени (например, CYP2D6 и CYP2C19), расщепляющих многие распространённые лекарства.",
        "URL" -> "https://en.wikipedia.org/wiki/Cytochrome_P450",
        "URLRU" -> "https://ru.wikipedia.org/wiki/Цитохром_P450"
    |>,
    <|
        "Term" -> "CPIC", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A consortium that publishes guidelines turning your pharmacogene results into prescribing advice.",
        "DefinitionRU" -> "Консорциум, публикующий рекомендации, которые превращают ваши результаты по фармакогенам в советы по назначению лекарств.",
        "URL" -> "https://cpicpgx.org/"
    |>,
    <|
        "Term" -> "Activity score", "TermRU" -> "Балл активности", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A number summing the function of your two star alleles to predict a metabolizer phenotype.",
        "DefinitionRU" -> "Число, суммирующее функцию ваших двух звёздных аллелей для предсказания фенотипа метаболизатора.",
        "URL" -> "https://cpicpgx.org/resources/term-standardization/"
    |>,
    <|
        "Term" -> "SLCO1B1 (statins)", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A gene whose variants raise the risk of muscle side effects from statin cholesterol drugs.",
        "DefinitionRU" -> "Ген, варианты которого повышают риск мышечных побочных эффектов от статинов (препаратов от холестерина).",
        "URL" -> "https://medlineplus.gov/genetics/gene/slco1b1/"
    |>,
    <|
        "Term" -> "VKORC1 (warfarin)", "Category" -> "Pharmacogenomics",
        "DefinitionEN" -> "A gene whose variants affect the dose of the blood thinner warfarin you need.",
        "DefinitionRU" -> "Ген, варианты которого влияют на нужную вам дозу антикоагулянта варфарина.",
        "URL" -> "https://medlineplus.gov/genetics/gene/vkorc1/"
    |>
}

(* Term display, definition, and link resolve to the requested language, with a
   Russian-specific term / URL only where one was provided. *)
reportGlossaryTerm[entry_Association, "Russian"] := Lookup[entry, "TermRU", entry["Term"]]
reportGlossaryTerm[entry_Association, _] := entry["Term"]

reportGlossaryDef[entry_Association, "Russian"] := entry["DefinitionRU"]
reportGlossaryDef[entry_Association, _] := entry["DefinitionEN"]

reportGlossaryURL[entry_Association, "Russian"] := Lookup[entry, "URLRU", entry["URL"]]
reportGlossaryURL[entry_Association, _] := entry["URL"]

(* -- HTML rendering -- *)

htmlEscape[s_String] :=
    StringReplace[s, {"&" -> "&amp;", "<" -> "&lt;", ">" -> "&gt;", "\"" -> "&quot;"}]
htmlEscape[x_] := htmlEscape[ToString[x]]

(* Compact scientific notation, safe for the enormous exact-rational p-values the
   GWAS catalog carries (Log10 stays exact, so nothing underflows). *)
reportSci[x_] :=
    Block[{e, m},
        If[ TrueQ[x == 0], Return["0"]];
        e = Floor[Log10[Abs[x]]];
        m = N[x / 10^e];
        ToString[NumberForm[m, 3]] <> "e" <> ToString[e]
    ]

reportNumber[x_ ? NumericQ] :=
    Which[
        TrueQ[x == 0], "0",
        IntegerQ[x], ToString[x],
        Abs[x] < 1/1000 || Abs[x] >= 100000, reportSci[x],
        True, ToString[NumberForm[N[x], 4]]
    ]
reportNumber[x_] := ToString[x]

reportPercent[p_] := If[ NumericQ[p], ToString[Round[100 p]] <> "%", "-"]

reportCell[v_] :=
    Which[
        MissingQ[v], "-",
        v === True, "yes",
        v === False, "no",
        v === None, "-",
        NumericQ[v], htmlEscape[reportNumber[v]],
        ListQ[v], htmlEscape[StringRiffle[Map[ToString, v], ", "]],
        True, htmlEscape[ToString[v]]
    ]

(* The plain-text (un-escaped) counterpart of reportCell: a value as a bare
   string with "-" for Missing / None, for composing an interpretation sentence
   or footnote that is htmlEscaped as a whole at the point of emission. *)
reportPlainText[v_] :=
    Which[
        MissingQ[v] || v === None, "-",
        NumericQ[v], reportNumber[v],
        ListQ[v], StringRiffle[Map[ToString, v], ", "],
        True, ToString[v]
    ]

(* Fill a `slot`-templated localized string with a slot -> value Association. *)
reportTemplate[key_String, lang_String, slots_Association] :=
    TemplateApply[StringTemplate[reportLabel[key, lang]], slots]

reportHtmlRow[cells_List, tag_String] :=
    StringJoin["<tr>", Map["<" <> tag <> ">" <> # <> "</" <> tag <> ">" &, cells], "</tr>"]

(* Render a Tabular (or list of same-keyed Associations) as an HTML table.  The
   column headers are localized; the values in the columns named in vocab (a
   controlled-vocabulary set such as {"Phenotype"}) are localized too, while
   every other cell (gene symbols, IDs, free text, numbers) is rendered as-is. *)
reportVocabCell[value_, col_String, lang_String, vocab_List] :=
    reportCell[If[ MemberQ[vocab, col], reportLabel[value, lang], value]]

reportHtmlTable[t_Tabular, lang_String, vocab_List : {}] :=
    reportHtmlTable[Normal[t], Normal[ColumnKeys[t]], lang, vocab]
reportHtmlTable[rows_List, lang_String, vocab_List : {}] :=
    reportHtmlTable[rows, If[ rows === {}, {}, Keys[First[rows]]], lang, vocab]
reportHtmlTable[rows_List, cols_List, lang_String, vocab_List : {}] :=
    If[ rows === {} || cols === {},
        "<p class=\"empty\">" <> reportLabel["Table.NoRows", lang] <> "</p>",
        StringJoin[
            "<div class=\"tablewrap\"><table>\n<thead>",
            reportHtmlRow[Map[htmlEscape[reportColHeader[#, lang]] &, cols], "th"],
            "</thead>\n<tbody>\n",
            StringRiffle[
                Map[
                    row |-> reportHtmlRow[
                        Map[reportVocabCell[Lookup[row, #, Missing[]], #, lang, vocab] &, cols],
                        "td"
                    ],
                    rows
                ],
                "\n"
            ],
            "\n</tbody>\n</table></div>"
        ]
    ]

reportDefList[pairs_List] :=
    StringJoin[
        "<dl>",
        StringJoin @ Map[
            kv |-> "<dt>" <> htmlEscape[kv[[1]]] <> "</dt><dd>" <> kv[[2]] <> "</dd>",
            pairs
        ],
        "</dl>"
    ]

reportNotRunHTML[section_String, lang_String] :=
    StringJoin[
        "<p class=\"notrun\">", reportLabel["NotRun.Pre", lang],
        htmlEscape[reportSectionOperator[section]],
        reportLabel["NotRun.Mid", lang], "</p>"
    ]

(* The "(showing the top N ...)" note; postKey selects the trailing phrase. *)
reportTopNNote[lang_String, postKey_String] :=
    reportLabel["TopN.Pre", lang] <> ToString[$reportTopN] <> reportLabel[postKey, lang]

(* The sex-karyotype one-liner: what the call means, in plain language. *)
reportSexNoteKey[sex_] :=
    Switch[sex, "XY", "SexNote.XY", "XX", "SexNote.XX", _, "SexNote.Other"]

reportSexNote[sex_, lang_String] :=
    If[ MissingQ[sex],
        "",
        StringJoin[
            "<p class=\"finding-interp\">",
            htmlEscape[reportLabel["Ov.SexNotePre", lang]],
            htmlEscape[reportLabel[reportSexNoteKey[sex], lang]],
            "</p>\n"
        ]
    ]

(* Per-section HTML.  A Missing section value renders the "not yet run" note. *)
reportSectionHTML[hg_, "Overview", ov_Association, lang_String] :=
    StringJoin[
        reportDefList[{
            {reportLabel["Ov.Subject", lang], htmlEscape[ov["Subject"]]},
            {reportLabel["Ov.Sex", lang], reportCell[reportLabel[ov["Sex"], lang]]},
            {reportLabel["Ov.Build", lang], htmlEscape[ov["Build"]]},
            {reportLabel["Ov.Backend", lang], htmlEscape[ov["Backend"]]},
            {reportLabel["Ov.VariantCount", lang], reportCell[ov["VariantCount"]]},
            {reportLabel["Ov.SectionsPopulated", lang],
                If[ ov["SectionsAvailable"] === {}, reportLabel["Ov.None", lang],
                    htmlEscape @ StringRiffle[Map[reportSectionTitle[#, lang] &, ov["SectionsAvailable"]], "; "]
                ]},
            {reportLabel["Ov.SectionsNotRun", lang],
                If[ ov["SectionsNotRun"] === {}, reportLabel["Ov.None", lang],
                    htmlEscape @ StringRiffle[Map[reportSectionTitle[#, lang] &, ov["SectionsNotRun"]], "; "]
                ]}
        }],
        reportSexNote[ov["Sex"], lang]
    ]

(* The maternal / paternal single-lineage haplogroup caveat, rendered only for
   the haplogroups that are actually present (labels are scientific identifiers,
   never translated). *)
reportAncestryHaploNote[mt_, y_, lang_String] :=
    Which[
        StringQ[mt] && StringQ[y],
            "<p class=\"finding-interp\">"
                <> htmlEscape[reportTemplate["AncInterp.HaploBoth", lang, <|"mt" -> mt, "y" -> y|>]]
                <> "</p>\n",
        StringQ[mt],
            "<p class=\"finding-interp\">"
                <> htmlEscape[reportTemplate["AncInterp.HaploMt", lang, <|"mt" -> mt|>]]
                <> "</p>\n",
        StringQ[y],
            "<p class=\"finding-interp\">"
                <> htmlEscape[reportTemplate["AncInterp.HaploY", lang, <|"y" -> y|>]]
                <> "</p>\n",
        True, ""
    ]

reportSectionHTML[hg_, "Ancestry", v_Association, lang_String] :=
    StringJoin[
        If[ StringQ[v["Superpopulation"]],
            StringJoin[
                "<p class=\"finding-interp\">",
                htmlEscape[reportTemplate["AncInterp.Super", lang, <|"pop" -> reportLabel[v["Superpopulation"], lang]|>]],
                " ", htmlEscape[reportLabel["AncInterp.Continental", lang]], "</p>\n"
            ],
            ""
        ],
        reportDefList[{
            {reportLabel["Anc.Superpopulation", lang], reportCell[reportLabel[v["Superpopulation"], lang]]},
            {reportLabel["Anc.mtDNA", lang], reportCell[v["mtDNAHaplogroup"]]},
            {reportLabel["Anc.Y", lang], reportCell[v["YHaplogroup"]]}
        }],
        reportAncestryHaploNote[v["mtDNAHaplogroup"], v["YHaplogroup"], lang],
        If[ AssociationQ[v["SuperpopulationFractions"]],
            StringJoin[
                "<h3>", reportLabel["Anc.FractionsHeading", lang], "</h3>\n",
                "<p class=\"finding-interp\">", htmlEscape[reportLabel["AncInterp.Fractions", lang]], "</p>\n",
                reportHtmlTable[
                    KeyValueMap[<|"Super-population" -> #1, "Fraction" -> #2|> &, v["SuperpopulationFractions"]],
                    lang, {"Super-population"}
                ]
            ],
            ""
        ]
    ]

(* -- pharmacogenomics per-finding interpretation --
   Map the metabolizer phenotype to a plain-language reading of the gene-drug
   pair; a Confidence that is anything other than "Called" flags a partial /
   tentative call (e.g. CYP2D6 with uncallable copy-number alleles).  The
   diplotype, CPIC level, and activity score are demoted to a muted footnote. *)
pgxPhenotypeKey[p_] :=
    Which[
        ! StringQ[p], "PgxInterp.Other",
        StringContainsQ[p, "Normal", IgnoreCase -> True], "PgxInterp.Normal",
        StringContainsQ[p, "Intermediate", IgnoreCase -> True], "PgxInterp.Intermediate",
        StringContainsQ[p, "Poor" | "Decreased", IgnoreCase -> True], "PgxInterp.Poor",
        StringContainsQ[p, "Ultrarapid" | "Rapid", IgnoreCase -> True]
            || StringContainsQ[p, "Increased Function", IgnoreCase -> True], "PgxInterp.Rapid",
        True, "PgxInterp.Other"
    ]

pgxLowConfidenceQ[conf_] := StringQ[conf] && conf =!= "Called"

pgxInterpretation[phenotype_, drug_, conf_, lang_String] :=
    Block[{base},
        base = If[ StringQ[drug],
            reportTemplate[pgxPhenotypeKey[phenotype], lang, <|"drug" -> drug|>],
            reportLabel["PgxInterp.NoDrug", lang]
        ];
        If[ pgxLowConfidenceQ[conf], base <> " " <> reportLabel["PgxInterp.LowConfidence", lang], base]
    ]

pgxMetaNote[row_Association, lang_String] :=
    StringJoin[
        reportTemplate["Pgx.Meta", lang, <|
            "dip" -> reportPlainText[row["Diplotype"]],
            "lvl" -> reportPlainText[row["CPICLevel"]],
            "act" -> reportPlainText[row["ActivityScore"]]
        |>],
        If[ pgxLowConfidenceQ[row["Confidence"]], " " <> row["Confidence"], ""]
    ]

reportPgxFindingBlock[row_Association, lang_String] :=
    Block[{drug = row["ActionableDrug"]},
        StringJoin[
            "<div class=\"finding\">\n",
            "<h3>", htmlEscape[reportPlainText[row["Gene"]]],
            If[ StringQ[drug], " - " <> htmlEscape[drug], ""],
            "</h3>\n",
            "<p class=\"finding-interp\">",
            htmlEscape[pgxInterpretation[row["Phenotype"], drug, row["Confidence"], lang]],
            "</p>\n",
            "<p class=\"finding-meta\">", htmlEscape[pgxMetaNote[row, lang]], "</p>\n",
            "</div>\n"
        ]
    ]

reportSectionHTML[hg_, "Pharmacogenomics", v_Association, lang_String] :=
    StringJoin[
        "<p>",
        ToString[v["ActionableGuidanceCount"]], reportLabel["Pgx.Prose1", lang],
        ToString[v["ActionableGeneCount"]], reportLabel["Pgx.Prose2", lang],
        ToString[v["NormalGeneCount"]], reportLabel["Pgx.Prose3", lang], "</p>\n",
        StringJoin @ Map[reportPgxFindingBlock[#, lang] &, Normal[v["Actionable"]]],
        "<h3>", reportLabel["Pgx.Heading", lang], "</h3>",
        reportHtmlTable[
            Normal[v["Actionable"]],
            {"Gene", "Diplotype", "Phenotype", "ActionableDrug", "CPICLevel"},
            lang, {"Phenotype"}
        ]
    ]

(* -- clinical-variant per-finding interpretation --
   Say what the variant is, whether it is carried and in what zygosity, and give
   the crucial frequency context: a common variant (PopulationAF >= 0.05) with a
   legacy pathogenic label is a known false-alarm source.  Close with the
   not-a-diagnosis / weak-review caveat; demote the accession and rsID to a
   footnote. *)
clinvarCopiesLabel[zyg_, lang_String] :=
    Which[
        zyg === "Homozygous", reportLabel["CV.TwoCopies", lang],
        zyg === "Heterozygous", reportLabel["CV.OneCopy", lang],
        True, reportLabel["CV.SomeCopies", lang]
    ]

clinvarConditionText[cond_, lang_String] :=
    If[ StringQ[cond] && StringLength[StringTrim[cond]] > 0
            && ! StringMatchQ[cond, "not_provided" | "not provided" | "-", IgnoreCase -> True],
        cond,
        reportLabel["CV.NoCondition", lang]
    ]

clinvarWeakReviewQ[rev_] :=
    StringQ[rev] && StringContainsQ[rev,
        "no assertion" | "no_assertion" | "no interpretation" | "no_interpretation", IgnoreCase -> True]

clinvarFrequencyText[af_, lang_String] :=
    Which[
        NumericQ[af] && af >= 0.05,
            reportTemplate["CVInterp.Common", lang, <|"pct" -> ToString[Round[100 * af]]|>],
        ! NumericQ[af] || af < 0.01, reportLabel["CVInterp.Rare", lang],
        True, reportLabel["CVInterp.Uncommon", lang]
    ]

clinvarInterpretation[row_Association, lang_String] :=
    StringJoin[
        reportTemplate["CVInterp.Finding", lang, <|
            "copies" -> clinvarCopiesLabel[row["Zygosity"], lang],
            "cond" -> clinvarConditionText[row["Condition"], lang]
        |>],
        clinvarFrequencyText[row["PopulationAF"], lang],
        reportLabel["CVInterp.NotDiagnosis", lang],
        If[ clinvarWeakReviewQ[row["ReviewStatus"]], reportLabel["CVInterp.WeakReview", lang], ""]
    ]

(* The muted footnote holds the demoted secondary detail: significance, review
   status, and the VCV accession / rsID identifiers. *)
clinvarMetaNote[row_Association] :=
    StringRiffle[
        Select[
            {reportPlainText[row["ClinicalSignificance"]], reportPlainText[row["ReviewStatus"]],
                reportPlainText[row["VCVAccession"]], reportPlainText[row["RsID"]]},
            # =!= "-" &
        ],
        "; "
    ]

reportClinVarFindingBlock[row_Association, lang_String] :=
    StringJoin[
        "<div class=\"finding\">\n",
        "<h3>", htmlEscape[If[ StringQ[row["Gene"]], row["Gene"], reportPlainText[row["VariantID"]]]], "</h3>\n",
        "<p class=\"finding-interp\">", htmlEscape[clinvarInterpretation[row, lang]], "</p>\n",
        "<p class=\"finding-meta\">", htmlEscape[clinvarMetaNote[row]], "</p>\n",
        "</div>\n"
    ]

reportSectionHTML[hg_, "ClinicalVariants", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["Count"]], reportLabel["CV.Prose1", lang],
        If[ v["Count"] > $reportTopN, reportTopNNote[lang, "TopN.Post"], ""],
        reportLabel["CV.Prose2", lang], "</p>\n",
        StringJoin @ Map[reportClinVarFindingBlock[#, lang] &, Normal[v["Hits"]]],
        reportHtmlTable[
            Normal[v["Hits"]],
            {"Gene", "VariantID", "RsID", "ClinicalSignificance", "Zygosity", "Condition", "PopulationAF"},
            lang, {"Zygosity"}
        ]
    ]

(* -- carrier-status per-finding interpretation --
   Frame the healthy-carrier / reproductive meaning by classification, with a
   stronger note for a homozygous (possible affected) or a dominant finding.
   Demote the IDs to a footnote.  clinvarConditionText is reused for the "no
   condition text" fallback. *)
carrierInterpKey[cls_] :=
    Switch[cls,
        "Carrier", "CarInterp.Carrier",
        "Homozygous (possible affected)", "CarInterp.Homozygous",
        "Dominant finding", "CarInterp.Dominant",
        "X-linked", "CarInterp.XLinked",
        _, "CarInterp.Other"
    ]

carrierInterpretation[row_Association, lang_String] :=
    reportTemplate[carrierInterpKey[row["CarrierClassification"]], lang, <|
        "cond" -> clinvarConditionText[row["Condition"], lang],
        "gene" -> reportPlainText[row["Gene"]]
    |>]

carrierMetaNote[row_Association] :=
    StringRiffle[
        Select[
            {reportPlainText[row["VariantID"]], reportPlainText[row["RsID"]],
                If[ NumericQ[row["PopulationAF"]], "AF " <> reportNumber[row["PopulationAF"]], "-"]},
            # =!= "-" &
        ],
        "; "
    ]

reportCarrierFindingBlock[row_Association, lang_String] :=
    StringJoin[
        "<div class=\"finding\">\n",
        "<h3>", htmlEscape[If[ StringQ[row["Gene"]], row["Gene"], reportPlainText[row["VariantID"]]]], "</h3>\n",
        "<p class=\"finding-interp\">", htmlEscape[carrierInterpretation[row, lang]], "</p>\n",
        "<p class=\"finding-meta\">", htmlEscape[carrierMetaNote[row]], "</p>\n",
        "</div>\n"
    ]

reportSectionHTML[hg_, "CarrierStatus", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["Count"]], reportLabel["Car.Prose1", lang],
        ToString[v["MaxPopulationAF"]], reportLabel["Car.Prose2", lang], "</p>\n",
        StringJoin @ Map[reportCarrierFindingBlock[#, lang] &, Normal[v["Carriers"]]],
        If[ Length[v["Classifications"]] > 0,
            StringJoin[
                "<h3>", reportLabel["Car.Heading", lang], "</h3>",
                reportHtmlTable[
                    KeyValueMap[<|"Classification" -> #1, "Count" -> #2|> &, v["Classifications"]],
                    lang, {"Classification"}
                ]
            ],
            ""
        ],
        reportHtmlTable[
            Normal[v["Carriers"]],
            {"Gene", "VariantID", "Zygosity", "Inheritance", "CarrierClassification", "PopulationAF"},
            lang, {"Zygosity", "CarrierClassification"}
        ]
    ]

(* -- polygenic-risk interpretation --
   Each curated PGS score carries a plain-language description and a direction of
   health concern: "HigherIsRisk" (a high percentile is the less-favorable
   direction), "LowerIsRisk" (a LOW percentile is less favorable, e.g. HDL, the
   protective cholesterol), or "Neutral" (not a health risk, e.g. height).  The
   description is bilingual inline so each trait is one self-contained entry,
   selected by language exactly as the $reportLabels entries are.  An uncurated
   PGS id (a raw score a user chose to compute) falls back to a generic
   description and an "Unknown" direction, and is reported plainly without any
   good/bad judgement.  The band labels and the per-direction sentence templates
   live in $reportLabels so they localize through reportLabel. *)
$prsTraitMeta = <|
    "PGS000065" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic tendency for LDL ('bad') cholesterol; higher raises cardiovascular risk",
        "Russian" -> "ваша генетическая склонность к уровню ЛПНП ('плохого') холестерина; более высокий повышает сердечно-сосудистый риск"|>|>,
    "PGS000064" -> <|"Direction" -> "LowerIsRisk", "Description" -> <|
        "English" -> "your genetic tendency for HDL ('good', protective) cholesterol; LOWER is less favorable",
        "Russian" -> "ваша генетическая склонность к уровню ЛПВП ('хорошего', защитного) холестерина; более НИЗКИЙ менее благоприятен"|>|>,
    "PGS000066" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic tendency for blood triglycerides (a blood fat); higher is a cardiovascular/metabolic risk factor",
        "Russian" -> "ваша генетическая склонность к уровню триглицеридов в крови (жира крови); более высокий - фактор сердечно-сосудистого/метаболического риска"|>|>,
    "PGS000062" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic tendency for total blood cholesterol",
        "Russian" -> "ваша генетическая склонность к уровню общего холестерина в крови"|>|>,
    "PGS000036" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic predisposition to type 2 diabetes",
        "Russian" -> "ваша генетическая предрасположенность к диабету 2 типа"|>|>,
    "PGS000034" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic tendency toward higher body-mass index",
        "Russian" -> "ваша генетическая склонность к более высокому индексу массы тела"|>|>,
    "PGS000012" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "your genetic predisposition to coronary artery disease (heart disease)",
        "Russian" -> "ваша генетическая предрасположенность к ишемической болезни сердца"|>|>,
    "PGS000297" -> <|"Direction" -> "Neutral", "Description" -> <|
        "English" -> "a classic highly-polygenic trait that influences how tall you are",
        "Russian" -> "классический высокополигенный признак, влияющий на рост"|>|>,
    "PGS000001" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "genetic predisposition to breast cancer (relevant mainly for people with breast tissue)",
        "Russian" -> "генетическая предрасположенность к раку молочной железы (актуально в основном для людей с тканью молочной железы)"|>|>,
    "PGS003419" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "genetic predisposition to prostate cancer (relevant for people with a prostate)",
        "Russian" -> "генетическая предрасположенность к раку простаты (актуально для людей с предстательной железой)"|>|>,
    "PGS000026" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "genetic predisposition to Alzheimer's disease",
        "Russian" -> "генетическая предрасположенность к болезни Альцгеймера"|>|>,
    "PGS000016" -> <|"Direction" -> "HigherIsRisk", "Description" -> <|
        "English" -> "genetic predisposition to atrial fibrillation (an irregular heartbeat)",
        "Russian" -> "генетическая предрасположенность к фибрилляции предсердий (нерегулярному сердцебиению)"|>|>
|>

prsDirection[pgsid_String] :=
    Block[{m = Lookup[$prsTraitMeta, pgsid, Missing[]]},
        If[ AssociationQ[m], Lookup[m, "Direction", "Unknown"], "Unknown"]
    ]
prsDirection[_] := "Unknown"

prsDescription[pgsid_String, lang_String] :=
    Block[{m = Lookup[$prsTraitMeta, pgsid, Missing[]]},
        If[ AssociationQ[m] && AssociationQ[m["Description"]],
            Lookup[m["Description"], lang, m["Description"]["English"]],
            reportLabel["PRS.GenericDesc", lang]
        ]
    ]
prsDescription[_, lang_String] := reportLabel["PRS.GenericDesc", lang]

(* Percentile band (input is the 0-1 CDF percentile): >= 95 very high, 80-95
   high, 60-80 above average, 40-60 average, 20-40 below average, 5-20 low, < 5
   very low. *)
prsBandKey[p_] :=
    Which[
        p >= 95, "PRSBand.VeryHigh",
        p >= 80, "PRSBand.High",
        p >= 60, "PRSBand.AboveAvg",
        p >= 40, "PRSBand.Average",
        p >= 20, "PRSBand.BelowAvg",
        p >= 5, "PRSBand.Low",
        True, "PRSBand.VeryLow"
    ]

prsBand[pct_ ? NumericQ, lang_String] := reportLabel[prsBandKey[Round[100 * pct]], lang]

prsOrdinalSuffix[n_Integer] :=
    Which[
        11 <= Mod[n, 100] <= 13, "th",
        Mod[n, 10] === 1, "st",
        Mod[n, 10] === 2, "nd",
        Mod[n, 10] === 3, "rd",
        True, "th"
    ]

prsPercentilePhrase[p_Integer, "Russian"] := ToString[p] <> "-й " <> reportLabel["PRS.PercentileWord", "Russian"]
prsPercentilePhrase[p_Integer, lang_String] := ToString[p] <> prsOrdinalSuffix[p] <> " " <> reportLabel["PRS.PercentileWord", lang]

(* "99th percentile - Very high" (localized), the trait's headline reading. *)
prsPercentileBand[pct_ ? NumericQ, lang_String] :=
    Block[{p = Round[100 * pct]},
        prsPercentilePhrase[p, lang] <> " - " <> reportLabel[prsBandKey[p], lang]
    ]

prsFillTemplate[key_String, num_Integer, desc_String, lang_String] :=
    TemplateApply[StringTemplate[reportLabel[key, lang]], <|"num" -> ToString[num], "desc" -> desc|>]

(* The plain-language interpretation sentence: composes the percentile, the
   direction of concern, and the trait description.  A LowerIsRisk trait is
   framed as "lower than about (100 - p)% of people"; a Missing percentile (no
   population reference) explains that instead. *)
prsInterpretation[pgsid_, pct_, lang_String] :=
    If[ ! NumericQ[pct],
        reportLabel["PRSInterp.NoPercentile", lang],
        Block[{p = Round[100 * pct], desc = prsDescription[pgsid, lang]},
            Switch[prsDirection[pgsid],
                "HigherIsRisk", prsFillTemplate["PRSInterp.Higher", p, desc, lang],
                "LowerIsRisk", prsFillTemplate["PRSInterp.Lower", 100 - p, desc, lang],
                "Neutral", prsFillTemplate["PRSInterp.Neutral", p, desc, lang],
                _, prsFillTemplate["PRSInterp.Unknown", p, desc, lang]
            ]
        ]
    ]

(* The muted secondary footnote: the PGS id and the fraction of variants used. *)
prsCoverageNote[pgsid_, cov_, lang_String] :=
    StringJoin[
        If[ StringQ[pgsid], htmlEscape[pgsid], "-"],
        If[ NumericQ[cov],
            StringJoin[reportLabel["PRS.CovPre", lang], reportPercent[cov], reportLabel["PRS.CovPost", lang]],
            ""
        ]
    ]

(* One readable block per trait: the trait name and its percentile band as a
   heading, the interpretation sentence, then the small PGS / coverage note. *)
reportPRSTraitBlock[row_Association, lang_String] :=
    Block[{trait = row["Trait"], pct = row["Percentile"], pgsid = row["PGSID"], cov = row["Coverage"]},
        StringJoin[
            "<div class=\"prs-trait\">\n",
            "<h3>", htmlEscape[reportLabel[trait, lang]],
            If[ NumericQ[pct],
                StringJoin[" <span class=\"prs-band\">", htmlEscape[prsPercentileBand[pct, lang]], "</span>"],
                ""
            ],
            "</h3>\n",
            "<p class=\"prs-interp\">", htmlEscape[prsInterpretation[pgsid, pct, lang]], "</p>\n",
            "<p class=\"prs-meta\">", prsCoverageNote[pgsid, cov, lang], "</p>\n",
            "</div>\n"
        ]
    ]

reportSectionHTML[hg_, "PolygenicRiskScores", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["Count"]], reportLabel["PRS.Prose1", lang], "</p>\n",
        StringJoin @ Map[reportPRSTraitBlock[#, lang] &, Normal[v["Scores"]]]
    ]

reportSectionHTML[hg_, "Traits", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["Count"]], reportLabel["Tr.Prose1", lang],
        If[ v["Count"] > $reportTopN, reportTopNNote[lang, "TopN.PostMagnitude"], ""],
        ".</p>",
        reportHtmlTable[v["Top"], lang]
    ]

reportSectionHTML[hg_, "GWASHighlights", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["CarriedGenomeWideSignificantCount"]], reportLabel["GW.Prose1", lang],
        If[ v["CarriedGenomeWideSignificantCount"] > $reportTopN,
            reportTopNNote[lang, "TopN.PostPValue"], ""],
        reportLabel["GW.Prose2", lang], "</p>",
        reportHtmlTable[v["Top"], lang]
    ]

reportSectionHTML[hg_, "MissenseHighlights", v_Association, lang_String] :=
    StringJoin[
        "<p>", ToString[v["LikelyPathogenicCount"]], reportLabel["MS.Prose1", lang],
        If[ v["LikelyPathogenicCount"] > $reportTopN, reportTopNNote[lang, "TopN.PostScore"], ""],
        reportLabel["MS.Prose2", lang], "</p>",
        reportHtmlTable[v["Top"], lang, {"Zygosity"}]
    ]

reportSectionHTML[hg_, section_String, _, lang_String] := reportNotRunHTML[section, lang]

$reportCSS = StringJoin[
    "body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;",
    "line-height:1.5;margin:0;padding:2rem;max-width:60rem;margin:auto;color:#1a1a1a;background:#fff}",
    "h1{font-size:1.7rem;margin-bottom:0.2rem}h2{font-size:1.25rem;border-bottom:2px solid #ddd;padding-bottom:0.2rem;margin-top:2rem}",
    "h3{font-size:1rem;color:#444;margin-bottom:0.3rem}.subtitle{color:#666;margin-top:0}",
    "section{margin-bottom:1.5rem}",
    ".caveat{border:2px solid #c0392b;background:#fdecea;color:#611a15;border-radius:8px;padding:1rem 1.25rem;margin:1.5rem 0}",
    ".caveat h2{border:none;color:#c0392b;margin-top:0}",
    ".tablewrap{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:0.9rem;margin:0.5rem 0}",
    "th,td{border:1px solid #ddd;padding:0.35rem 0.55rem;text-align:left;vertical-align:top}",
    "th{background:#f4f4f4}tr:nth-child(even) td{background:#fafafa}",
    "dl{display:grid;grid-template-columns:auto 1fr;gap:0.25rem 1rem;margin:0.5rem 0}dt{font-weight:600;color:#555}dd{margin:0}",
    ".notrun{color:#888;font-style:italic}.empty{color:#888}code{background:#f0f0f0;padding:0.1rem 0.3rem;border-radius:3px}",
    ".intro{color:#555;margin:0.1rem 0 0.7rem}a{color:#1a6fb5}dl.glossary dt{color:#333}dl.glossary a{white-space:nowrap}",
    ".prs-trait,.finding{margin:0.9rem 0;padding:0.1rem 0 0.1rem 0.8rem;border-left:3px solid #cdd6e0}",
    ".prs-trait h3,.finding h3{color:#1a1a1a;margin:0 0 0.25rem}.prs-band{font-weight:400;font-size:0.9rem;color:#666;white-space:nowrap}",
    ".prs-interp,.finding-interp{margin:0.2rem 0}.prs-meta,.finding-meta{color:#888;font-size:0.8rem;margin:0.25rem 0 0}",
    "footer{margin-top:2.5rem;padding-top:1rem;border-top:1px solid #ddd;color:#888;font-size:0.85rem}",
    "@media(prefers-color-scheme:dark){body{background:#161616;color:#e6e6e6}h2{border-color:#333}h3{color:#bbb}",
    ".subtitle{color:#999}.caveat{background:#2a1512;border-color:#e74c3c;color:#f3c6c0}.caveat h2{color:#ff7062}",
    "th{background:#222}tr:nth-child(even) td{background:#1d1d1d}th,td{border-color:#333}dt{color:#aaa}",
    ".intro{color:#aaa}a{color:#6db3f2}dl.glossary dt{color:#ddd}",
    ".prs-trait,.finding{border-color:#39424e}.prs-trait h3,.finding h3{color:#e6e6e6}.prs-band{color:#9aa6b2}",
    "code{background:#2a2a2a}footer{border-color:#333}}"
]

(* The caveat block: one HTML skeleton, text pieces pulled from $reportLabels so
   the same renderer serves every language. *)
reportCaveatHTML[lang_String] :=
    StringJoin[
        "<div class=\"caveat\">\n<h2>", reportLabel["Caveat.Heading", lang], "</h2>\n",
        "<p>", reportLabel["Caveat.Lead", lang], "</p>\n",
        "<ul>\n",
        "<li>", reportLabel["Caveat.Bullet1", lang], "</li>\n",
        "<li>", reportLabel["Caveat.Bullet2", lang], "</li>\n",
        "<li>", reportLabel["Caveat.Bullet3", lang], "</li>\n",
        "<li>", reportLabel["Caveat.Bullet4", lang], "</li>\n",
        "<li>", reportLabel["Caveat.Bullet5", lang], "</li>\n",
        "</ul>\n</div>\n"
    ]

(* The plain-language lead paragraph under a section header.  A section without
   an "Intro.<name>" label renders nothing, so the intro is opt-in per section. *)
reportSectionIntroHTML[section_String, lang_String] :=
    Block[{intro = reportLabel["Intro." <> section, lang, ""]},
        If[ intro === "", "", StringJoin["<p class=\"intro\">", intro, "</p>\n"]]
    ]

(* The glossary appendix: every $reportGlossary entry grouped under its category
   subheading, each term defined in the requested language with a link (opening
   in a new tab) to an authoritative educational resource. *)
reportGlossaryEntryHTML[entry_Association, lang_String] :=
    StringJoin[
        "<dt>", htmlEscape[reportGlossaryTerm[entry, lang]], "</dt>",
        "<dd>", htmlEscape[reportGlossaryDef[entry, lang]], " ",
        "<a href=\"", htmlEscape[reportGlossaryURL[entry, lang]], "\" target=\"_blank\" rel=\"noopener\">",
        htmlEscape[reportLabel["Gloss.LearnMore", lang]], "</a></dd>"
    ]

reportGlossaryHTML[lang_String] :=
    StringJoin @ Map[
        cat |-> StringJoin[
            "<h3>", htmlEscape[reportLabel["Gloss.Cat." <> cat, lang]], "</h3>\n<dl class=\"glossary\">\n",
            StringRiffle[
                Map[reportGlossaryEntryHTML[#, lang] &, Select[$reportGlossary, #Category === cat &]],
                "\n"
            ],
            "\n</dl>\n"
        ],
        $reportGlossaryCategories
    ]

reportHTML[hg_, structured_Association, sections_List, lang_String] :=
    StringJoin[
        "<!DOCTYPE html>\n<html lang=\"", reportHtmlLang[lang], "\">\n<head>\n<meta charset=\"utf-8\">\n",
        "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n",
        "<title>", reportLabel["Doc.Title", lang], " - ", htmlEscape[hg["Subject", "ID"]], "</title>\n",
        "<style>", $reportCSS, "</style>\n</head>\n<body>\n",
        "<h1>", reportLabel["Doc.Title", lang], "</h1>\n",
        "<p class=\"subtitle\">", reportLabel["Doc.Subject", lang], " <strong>", htmlEscape[hg["Subject", "ID"]], "</strong> &middot; ",
        htmlEscape[hg["Build"]], " &middot; ", reportLabel["Doc.Generated", lang], " ", htmlEscape[DateString["ISODate"]], "</p>\n",
        reportCaveatHTML[lang],
        StringJoin @ Map[
            s |-> StringJoin[
                "<section>\n<h2>", htmlEscape[reportSectionTitle[s, lang]], "</h2>\n",
                reportSectionIntroHTML[s, lang],
                reportSectionHTML[hg, s, structured[s], lang],
                "\n</section>\n"
            ],
            sections
        ],
        "<section>\n<h2>", htmlEscape[reportLabel["Gloss.Title", lang]], "</h2>\n",
        reportSectionIntroHTML["Glossary", lang],
        reportGlossaryHTML[lang],
        "</section>\n",
        "<footer>", reportLabel["Doc.Footer", lang], "</footer>\n</body>\n</html>\n"
    ]

(* -- write + persist -- *)

reportEnsureDir[hg_] :=
    Block[{dir = reportDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        dir
    ]

reportWrite[hg_, structured_Association, sections_List, lang_String] :=
    Block[{path = reportHTMLPath[hg]},
        reportEnsureDir[hg];
        Quiet @ Export[path, reportHTML[hg, structured, sections, lang], "Text", CharacterEncoding -> "UTF-8"];
        path
    ]

reportPersistCache[hg_, structured_Association] :=
    (reportEnsureDir[hg]; Quiet @ Export[reportCachePath[hg], structured, "WXF"];)

(* -- operator -- *)

Options[GenomeReport] = {"Compute" -> "Cached", "Sections" -> All, "Language" -> "English"}

GenomeReport::badcompute = "GenomeReport \"Compute\" value `1` is not \"Cached\", \"All\", or a list of slot names; using \"Cached\".";
GenomeReport::nosections = "GenomeReport \"Sections\" value `1` names no known section; using all sections.";
GenomeReport::badlang = "GenomeReport \"Language\" value `1` is not \"English\" or \"Russian\"; using \"English\".";

GenomeReport[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{sections, computeSet, lang, neededSlots, resolved, structured, htmlFile},
        sections = reportResolveSections[OptionValue["Sections"]];
        computeSet = reportComputeSet[OptionValue["Compute"]];
        lang = reportLanguage[OptionValue["Language"]];
        neededSlots = DeleteCases[
            DeleteDuplicates @ Catenate @ Map[reportSectionSlots, sections],
            "Sex"
        ];
        resolved = Association @ Map[
            slot |-> slot -> reportResolveSlot[hg, slot, computeSet],
            neededSlots
        ];
        structured = reportAssemble[hg, sections, resolved, computeSet];
        htmlFile = reportWrite[hg, structured, sections, lang];
        structured = Append[structured, "ReportFile" -> htmlFile];
        reportPersistCache[hg, structured];
        structured
    ]


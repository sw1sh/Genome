(* GWAS.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === GWAS Catalog association interpretation ===
   GWASAssociations reproduces the per-SNP association report: for each of the
   subject's genotypes that carries a published trait association in the
   NHGRI-EBI GWAS Catalog it reports the rsID, the subject's GRCh37 position and
   genotype, the risk (effect) allele, whether the subject carries it and in how
   many copies, the mapped trait, the effect size, and the citing PubMed
   publication.  The catalog reports its coordinates on GRCh38 while the subject
   is GRCh37, so the join is keyed by rsID (the subject VCF's ID column carries
   rsIDs), which sidesteps liftover entirely; the subject's own GRCh37 position
   is reported.  The catalog is downloaded once (the ontology-annotated,
   one-row-per-SNP release) and reduced to a compact per-association table under
   data/references/gwas/ (git-ignored); the per-subject result is cached under
   data/<subject>/interpretations/, keyed by the catalog release. *)

$gwasSourceURL = "https://ftp.ebi.ac.uk/pub/databases/gwas/releases/latest/gwas-catalog-associations_ontology-annotated-split.zip"
$gwasStatsURL = "https://www.ebi.ac.uk/gwas/api/search/stats"

GWASAssociations::download = "Downloading and reducing the NHGRI-EBI GWAS Catalog associations release from `1`; this one-time fetch (roughly 70 MB zipped) is reduced to a compact per-association table and cached under data/references/gwas/.";
GWASAssociations::noref = "GWASAssociations could not obtain the reduced GWAS Catalog table; the download or the unzip / awk / gzip / sort reduction step failed.  Ensure curl, unzip, awk, gzip and sort are on PATH and the network is reachable.";

(* -- reference locations, derived from the subject VCF's directory so no
   absolute path is ever baked into the source -- *)

gwasReferenceDir[hg_] := FileNameJoin[{DirectoryName[hg["Path"]], "references", "gwas"}]

gwasZipPath[dir_String] :=
    FileNameJoin[{dir, "gwas-catalog-associations_ontology-annotated-split.zip"}]
gwasReducedPath[dir_String] := FileNameJoin[{dir, "gwas_associations_reduced.tsv.gz"}]
gwasRsidsPath[dir_String] := FileNameJoin[{dir, "gwas_rsids.txt"}]
gwasReleasePath[dir_String] := FileNameJoin[{dir, "gwas_catalog.release"}]

(* awk that reduces the 38-column associations TSV to a 15-column per-association
   table, keeping only rows whose SNPS column (22) is a single rsID.  The risk
   allele is the segment after the last "-" of STRONGEST SNP-RISK ALLELE (21)
   ("rs123-A" -> "A", "rs123-?" -> "?").  Empty fields are written as "." so the
   downstream StringSplit keeps every column.  The catalog zip holds several
   year-partitioned members, so the reducer sees a header row at the top of each
   member; the SNPS rsID pattern drops every one of them (their SNPS column reads
   "SNPS"), so no explicit NR == 1 skip is needed.  Output columns: rsid, chr38,
   pos38, riskAllele, RAF, p-value, OR/beta, 95% CI, disease/trait, mapped trait,
   mapped-trait URI, PubMedID, first author, date, journal. *)
gwasReduceAwk[] := StringJoin[
    "BEGIN { OFS = \"\\t\" } ",
    "{ sub(/\\r$/, \"\") } ",
    "$22 ~ /^rs[0-9]+$/ { ",
    "k = split($21, pa, \"-\"); allele = pa[k]; ",
    "print $22, nz($12), nz($13), nz(allele), nz($27), nz($28), nz($31), nz($32), nz($8), nz($35), nz($36), nz($2), nz($3), nz($4), nz($5) ",
    "} ",
    "function nz(x) { return (x == \"\") ? \".\" : x }"
]

(* A real catalog zip decompresses (unzip -p concatenates all members, which are
   year-partitioned association TSVs) to text whose header names the
   STRONGEST SNP-RISK ALLELE column; a failed download (an HTML error page) does
   not. *)
gwasLooksLikeCatalogQ[zip_String] :=
    MatchQ[
        RunProcess[{"sh", "-c",
            "unzip -p " <> shellEscape[zip] <> " 2>/dev/null | head -1 | grep -q 'STRONGEST SNP-RISK ALLELE'"}],
        KeyValuePattern["ExitCode" -> 0]
    ]

(* The catalog release date keys the per-subject cache.  Fetched once from the
   GWAS REST /stats endpoint; Missing when the endpoint is unreachable (the
   caller then falls back to the reduced file's byte count). *)
gwasReleaseString[] :=
    Block[{r, date},
        r = Quiet @ URLRead[HTTPRequest[$gwasStatsURL], Interactive -> False];
        date = If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200,
            Block[{j = Quiet @ Developer`ReadRawJSONString[r["Body"]]},
                If[ AssociationQ[j], Lookup[j, "date", Missing[]], Missing[]]
            ],
            Missing[]
        ];
        If[ StringQ[date], "GWASCatalog-" <> date, Missing[]]
    ]

(* Ensure the reduced per-association table, its unique-rsID set, and the release
   marker exist under dir; download and build them if absent.  Returns
   <|"Path" -> reduced, "RsidsPath" -> rsids, "Release" -> str|> or $Failed. *)
prepareGWASCatalog[dir_String] :=
    Block[{reduced, rsids, releaseFile, zip, tempTsv, rel, res},
        reduced = gwasReducedPath[dir];
        rsids = gwasRsidsPath[dir];
        releaseFile = gwasReleasePath[dir];
        If[ FileExistsQ[reduced] && FileExistsQ[rsids] && FileExistsQ[releaseFile],
            Return[<|
                "Path" -> reduced,
                "RsidsPath" -> rsids,
                "Release" -> StringTrim @ Import[releaseFile, "Text"]
            |>]
        ];
        If[ ! (onPathQ["curl"] && onPathQ["unzip"] && onPathQ["awk"] && onPathQ["gzip"] && onPathQ["sort"]),
            Return[$Failed]
        ];
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        zip = gwasZipPath[dir];
        If[ ! FileExistsQ[zip] || ! gwasLooksLikeCatalogQ[zip],
            Message[GWASAssociations::download, $gwasSourceURL];
            res = RunProcess[{"sh", "-c",
                "curl -L --fail -s -o " <> shellEscape[zip] <> " " <> shellEscape[$gwasSourceURL]}];
            If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! gwasLooksLikeCatalogQ[zip],
                Quiet @ DeleteFile[zip];
                Return[$Failed]
            ]
        ];
        tempTsv = FileNameJoin[{dir, "gwas_associations_reduced.tsv.tmp"}];
        res = RunProcess[{"sh", "-c",
            "unzip -p " <> shellEscape[zip] <> " | awk -F '\\t' " <> shellEscape[gwasReduceAwk[]]
                <> " > " <> shellEscape[tempTsv]}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]] || ! FileExistsQ[tempTsv] || FileByteCount[tempTsv] === 0,
            Quiet @ DeleteFile[tempTsv];
            Return[$Failed]
        ];
        RunProcess[{"sh", "-c",
            "cut -f1 " <> shellEscape[tempTsv] <> " | sort -u > " <> shellEscape[rsids]}];
        RunProcess[{"sh", "-c",
            "gzip -c " <> shellEscape[tempTsv] <> " > " <> shellEscape[reduced]}];
        Quiet @ DeleteFile[tempTsv];
        If[ ! FileExistsQ[reduced] || ! FileExistsQ[rsids] || FileByteCount[reduced] === 0,
            Return[$Failed]
        ];
        rel = Replace[
            gwasReleaseString[],
            Except[_String] :> "GWASCatalog-" <> ToString[FileByteCount[reduced]]
        ];
        Export[releaseFile, rel, "Text"];
        <|"Path" -> reduced, "RsidsPath" -> rsids, "Release" -> rel|>
    ]

(* -- strand-aware risk-allele dosage (pure, fixture-tested) --
   Given the subject's REF, ALT list, GT allele indices and the catalog risk
   allele, return <|"Dosage" -> 0 | 1 | 2, "Carries" -> True | False|>, or
   Missing when the dosage is undecidable: a non-SNV risk allele, an indel /
   complex site, a no-call, or a strand-ambiguous palindrome (the risk allele
   matches a subject allele both directly and under reverse-complement).  The
   site allele set (REF plus listed ALTs) fixes the strand and the palindrome
   test; the called alleles are counted for the dosage, so a homozygous-
   reference call scores 0 (or 2 when the risk allele is the reference). *)
gwasRevComp[b_String] :=
    Replace[b, {"A" -> "T", "T" -> "A", "C" -> "G", "G" -> "C", _ -> ""}]

gwasSNVBaseQ[b_String] := StringMatchQ[b, "A" | "C" | "G" | "T"]

gwasRiskAlleleDosage[ref_, altList_, gtParts_, riskAllele_] :=
    Block[{ra, rc, siteAll, siteSet, called, forward, dosage},
        If[ ! StringQ[riskAllele], Return[Missing[]]];
        ra = ToUpperCase[riskAllele];
        If[ ! gwasSNVBaseQ[ra], Return[Missing[]]];
        If[ ! (StringQ[ref] && gwasSNVBaseQ[ToUpperCase[ref]]), Return[Missing[]]];
        siteAll = Prepend[DeleteCases[ToUpperCase /@ altList, "."], ToUpperCase[ref]];
        If[ ! AllTrue[siteAll, gwasSNVBaseQ], Return[Missing[]]];
        siteSet = Union[siteAll];
        If[ gtParts === {} || AnyTrue[gtParts, ! StringMatchQ[#, DigitCharacter ..] &], Return[Missing[]]];
        called = Map[
            i |-> Which[
                i === 0, ToUpperCase[ref],
                i <= Length[altList], ToUpperCase[altList[[i]]],
                True, Missing[]
            ],
            FromDigits /@ gtParts
        ];
        If[ AnyTrue[called, MissingQ] || ! AllTrue[called, gwasSNVBaseQ], Return[Missing[]]];
        rc = gwasRevComp[ra];
        forward = Which[
            MemberQ[siteSet, ra] && MemberQ[siteSet, rc], Return[Missing[]],
            MemberQ[siteSet, ra], ra,
            MemberQ[siteSet, rc], rc,
            True, ra
        ];
        dosage = Count[called, forward];
        <|"Dosage" -> dosage, "Carries" -> (dosage >= 1)|>
    ]

(* -- value parsers -- *)

gwasNZ[s_] := If[ s === "." || s === "" || ! StringQ[s], Missing[], s]

(* The catalog writes numbers in E notation ("1E-13"); rewrite E -> *^ so
   ToExpression reads the scientific literal. *)
gwasNumeric[s_] :=
    If[ ! StringQ[s] || s === "." || s === "",
        Missing[],
        Block[{v = Quiet @ ToExpression[StringReplace[s, {"E" -> "*^", "e" -> "*^"}]]},
            If[ NumericQ[v], v, Missing[]]
        ]
    ]

(* Risk allele frequency: "NR" (not reported) and unparseable ranges yield
   Missing. *)
gwasFreq[s_] := If[ StringQ[s] && s === "NR", Missing[], gwasNumeric[s]]

gwasYear[s_] :=
    If[ StringQ[s] && StringLength[s] >= 4 && StringMatchQ[StringTake[s, 4], DigitCharacter ..],
        FromDigits @ StringTake[s, 4],
        Missing[]
    ]

(* Subject genotype in base form ("A/G", "C/C") from GT indices and REF/ALT. *)
gwasGenotypeString[ref_String, altList_List, gtParts_List] :=
    StringRiffle[
        Map[
            p |-> If[ StringMatchQ[p, DigitCharacter ..],
                Block[{i = FromDigits[p]},
                    Which[i === 0, ref, i <= Length[altList], altList[[i]], True, "."]
                ],
                "."
            ],
            gtParts
        ],
        "/"
    ]

gwasColumns[] := {
    "RsID", "GRCh37Position", "Genotype", "RiskAllele", "RiskAlleleDosage",
    "CarriesRisk", "Trait", "MappedTrait", "OddsRatioOrBeta", "PValue",
    "RiskAlleleFrequency", "PubMedID", "FirstAuthor", "Year", "Journal"
}

emptyGWASTabular[] :=
    Tabular[{Association[# -> Missing[] & /@ gwasColumns[]]}][[{}]]

(* One join-output line (15 reduced columns then 5 subject columns:
   subjChrom, subjPos37, subjRef, subjAlt, subjGT) to a report row, or Missing
   when the line is malformed. *)
gwasParseJoinedRow[line_String] :=
    Block[{f, rsid, riskAllele, raf, pval, orbeta, trait, mappedTrait, pubmed,
           author, date, journal, chrom, pos, ref, alt, gt, altList, gtParts, dos},
        f = StringSplit[line, "\t"];
        If[ Length[f] < 20, Return[Missing[]]];
        rsid = f[[1]];
        riskAllele = f[[4]];
        raf = f[[5]];
        pval = f[[6]];
        orbeta = f[[7]];
        trait = f[[9]];
        mappedTrait = f[[10]];
        pubmed = f[[12]];
        author = f[[13]];
        date = f[[14]];
        journal = f[[15]];
        chrom = f[[16]];
        pos = f[[17]];
        ref = f[[18]];
        alt = f[[19]];
        gt = f[[20]];
        altList = If[ alt === ".", {}, StringSplit[alt, ","]];
        gtParts = StringSplit[gt, "/" | "|"];
        dos = gwasRiskAlleleDosage[ref, altList, gtParts, riskAllele];
        <|
            "RsID" -> rsid,
            "GRCh37Position" -> chrom <> ":" <> pos,
            "Genotype" -> gwasGenotypeString[ref, altList, gtParts],
            "RiskAllele" -> If[ riskAllele === "." || riskAllele === "?", Missing[], riskAllele],
            "RiskAlleleDosage" -> If[ MissingQ[dos], Missing[], dos["Dosage"]],
            "CarriesRisk" -> If[ MissingQ[dos], Missing[], dos["Carries"]],
            "Trait" -> gwasNZ[trait],
            "MappedTrait" -> gwasNZ[mappedTrait],
            "OddsRatioOrBeta" -> gwasNumeric[orbeta],
            "PValue" -> gwasNumeric[pval],
            "RiskAlleleFrequency" -> gwasFreq[raf],
            "PubMedID" -> gwasNZ[pubmed],
            "FirstAuthor" -> gwasNZ[author],
            "Year" -> gwasYear[date],
            "Journal" -> gwasNZ[journal]
        |>
    ]

gwasPValueSortKey[row_Association] :=
    If[ NumericQ[row["PValue"]], row["PValue"], Infinity]

(* -- subject VCF intersection (streamed) --
   Load the catalog rsID set into an awk hash, then stream the subject VCF once
   and emit "rsid<TAB>chrom<TAB>pos<TAB>ref<TAB>alt<TAB>gt" for every row whose
   ID is documented - all genotypes, 0/0 included (an association report shows a
   genotype regardless of whether it carries the risk allele).  Only the small
   intersected slice is written to the temp file. *)
gwasSubjectRowsAwk[] := StringJoin[
    "FNR == NR { set[$1] = 1; next } ",
    "/^#/ { next } ",
    "($3 in set) { split($10, s, \":\"); print $3 \"\\t\" $1 \"\\t\" $2 \"\\t\" $4 \"\\t\" $5 \"\\t\" s[1] }"
]

writeSubjectGWASKeys[subjectPath_String, rsidsFile_String] :=
    Block[{file, cmd, res},
        file = FileNameJoin[{
            $TemporaryDirectory,
            "wlgenome_gwas_keys_" <> ToString[$ProcessID] <> "_"
                <> ToString[RandomInteger[10^9]] <> ".tsv"
        }];
        cmd = streamCommand[subjectPath] <> " | awk -F '\\t' "
            <> shellEscape[gwasSubjectRowsAwk[]] <> " " <> shellEscape[rsidsFile]
            <> " - > " <> shellEscape[file];
        res = RunProcess[{"sh", "-c", cmd}];
        If[ ! MatchQ[res, KeyValuePattern["ExitCode" -> 0]], Return[$Failed]];
        file
    ]

(* Load the small subject-genotype file into an awk hash keyed by rsID, then
   stream the reduced per-association table once and append the subject's
   chrom / pos / ref / alt / gt to every association row whose rsID the subject
   has a call for.  Bounded working set: only the subject's matched rsIDs are
   held in memory; the ~1M-row reduced table is scanned in a single pass. *)
gwasJoinAwk[] := StringJoin[
    "FNR == NR { subj[$1] = $2 \"\\t\" $3 \"\\t\" $4 \"\\t\" $5 \"\\t\" $6; next } ",
    "($1 in subj) { print $0 \"\\t\" subj[$1] }"
]

(* The testable core: takes explicit paths (like computeClinVarHits) so the
   fixture tests drive it without any download.  Returns the full Tabular of the
   subject's genotypes at catalog-associated SNPs (one row per rsID x
   association), sorted by ascending p-value (strongest associations first). *)
computeGWASAssociations[subjectPath_String, reducedPath_String, rsidsPath_String] :=
    Block[{keysFile, cmd, out, rows},
        keysFile = writeSubjectGWASKeys[subjectPath, rsidsPath];
        If[ keysFile === $Failed, Return[$Failed]];
        cmd = streamCommand[reducedPath] <> " | awk -F '\\t' "
            <> shellEscape[gwasJoinAwk[]] <> " " <> shellEscape[keysFile] <> " -";
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        Quiet @ DeleteFile[keysFile];
        If[ ! StringQ[out], Return[$Failed]];
        rows = DeleteCases[
            Map[gwasParseJoinedRow, Select[StringSplit[out, "\n"], # =!= "" &]],
            _Missing
        ];
        If[ rows === {}, Return[emptyGWASTabular[]]];
        rows = SortBy[rows, {gwasPValueSortKey[#], #["RsID"]} &];
        Tabular[Map[KeyTake[#, gwasColumns[]] &, rows]]
    ]

(* -- post-computation filters (applied over the full cached table) -- *)

gwasTraitMatchQ[row_, needle_String] :=
    Or[
        StringQ[row["Trait"]] && StringContainsQ[ToLowerCase[row["Trait"]], needle],
        StringQ[row["MappedTrait"]] && StringContainsQ[ToLowerCase[row["MappedTrait"]], needle]
    ]

filterGWAS[t_Tabular, trait_, maxP_, carriedOnly_] :=
    Block[{res = t},
        If[ NumericQ[maxP],
            res = Select[res, NumericQ[#PValue] && #PValue <= maxP &]
        ];
        If[ StringQ[trait],
            With[{needle = ToLowerCase[StringTrim[trait]]},
                res = Select[res, gwasTraitMatchQ[#, needle] &]
            ]
        ];
        If[ TrueQ[carriedOnly],
            res = Select[res, #CarriesRisk === True &]
        ];
        res
    ]

(* -- on-disk per-subject sidecar (Parquet under a .tabular name).  The sidecar
   stores the full (unfiltered) result so a change to the Trait / MaxPValue /
   CarriedOnly options never invalidates it; the operator applies the filters
   after hydration. -- *)

gwasSidecarDir[hg_] :=
    FileNameJoin[{DirectoryName[hg["Path"]], hg["Subject", "ID"], "interpretations"}]

gwasSidecarTabular[hg_] := FileNameJoin[{gwasSidecarDir[hg], "gwas-associations.tabular"}]
gwasSidecarRelease[hg_] := FileNameJoin[{gwasSidecarDir[hg], "gwas-associations.release"}]

writeGWASSidecar[hg_, t_Tabular, release_String] :=
    Block[{dir = gwasSidecarDir[hg]},
        Quiet @ If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]];
        Quiet @ Export[gwasSidecarTabular[hg], t, "Parquet", "Compression" -> "ZSTD"];
        Quiet @ Export[gwasSidecarRelease[hg], release, "Text"];
        t
    ]

loadGWASSidecar[hg_, release_String] :=
    Block[{tf = gwasSidecarTabular[hg], rf = gwasSidecarRelease[hg], stored, t},
        If[ ! FileExistsQ[tf] || ! FileExistsQ[rf], Return[Missing["NotCached"]]];
        stored = Quiet @ StringTrim @ Import[rf, "Text"];
        If[ stored =!= release, Return[Missing["NotCached"]]];
        t = Quiet @ Import[tf, {"Parquet", "Tabular"}];
        If[ MatchQ[t, _Tabular], t, Missing["NotCached"]]
    ]

(* -- operator -- *)

Options[GWASAssociations] = {
    "Trait" -> All,
    "MaxPValue" -> 5*^-8,
    "CarriedOnly" -> False,
    "Reference" -> Automatic
}

GWASAssociations[hg_ ? HumanGenomeQ, opts : OptionsPattern[]] :=
    Block[{trait, maxP, carriedOnly, refDir, ref, release, reducedPath, rsidsPath,
           cached, full, computed, ann, newAnn},
        trait = OptionValue["Trait"];
        maxP = OptionValue["MaxPValue"];
        carriedOnly = OptionValue["CarriedOnly"];
        refDir = Replace[
            OptionValue["Reference"],
            {Automatic -> gwasReferenceDir[hg], d_String :> d}
        ];
        ref = prepareGWASCatalog[refDir];
        If[ ref === $Failed, Message[GWASAssociations::noref]; Return[$Failed]];
        release = ref["Release"];
        reducedPath = ref["Path"];
        rsidsPath = ref["RsidsPath"];
        (* No in-memory short-circuit on the slot: the slot holds the previous
           call's FILTERED view, so returning it unchanged would ignore a new
           "Trait" / "MaxPValue" / "CarriedOnly" option.  Always rehydrate the
           full result from the sidecar (a fast Parquet import) and re-apply the
           filters, so every call reflects its own options.  Reading the slot
           itself (hg["GWASAssociations"]) stays instant. *)
        (* On-disk sidecar hydrate (the full result), else compute and persist. *)
        cached = loadGWASSidecar[hg, release];
        full = If[ MatchQ[cached, _Tabular],
            cached,
            Block[{t = computeGWASAssociations[hg["Path"], reducedPath, rsidsPath]},
                If[ MatchQ[t, _Tabular], writeGWASSidecar[hg, t, release]];
                t
            ]
        ];
        If[ ! MatchQ[full, _Tabular], Message[GWASAssociations::noref]; Return[$Failed]];
        computed = filterGWAS[full, trait, maxP, carriedOnly];
        ann = Last[hg];
        newAnn = Append[ann, <|
            "GWASAssociations" -> computed,
            "References" -> Append[Lookup[ann, "References", <||>], "GWASCatalogVersion" -> release]
        |>];
        HumanGenome[First[hg], newAnn]
    ]


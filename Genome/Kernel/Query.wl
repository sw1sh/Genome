(* Query.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === still-stub loaders === *)

ImportGenotypeArray::nyi = "ImportGenotypeArray is not yet implemented.";
ImportGenotypeArray[path_String, opts___] :=
    (Message[ImportGenotypeArray::nyi]; $Failed)

(* === query operators === *)

(* Row-list helpers used by operator-style functions. *)

genomeRows[g_ ? GenomeQ] := Normal @ g["Variants"]
tabularRows[t_Tabular] := Normal[t]

lookupOneRsid[rows_List, rsid_String] :=
    SelectFirst[
        rows,
        Lookup[#, "ID", Missing[]] === rsid &,
        Missing["NotFound", rsid]
    ]

GenotypeLookup[g_ ? GenomeQ, rsid_String] :=
    backendDispatch[g, "Genotype", rsid]

GenotypeLookup[g_ ? GenomeQ, rsids : {__String}] :=
    Block[{rows, byId},
        rows = genomeRows[g];
        byId = GroupBy[
            Select[rows, StringQ[Lookup[#, "ID", Missing[]]] &],
            #["ID"] &,
            First
        ];
        AssociationMap[
            r |-> Lookup[byId, r, Missing["NotFound", r]],
            rsids
        ]
    ]

GenotypeLookup[t_Tabular, rsid_String] :=
    lookupOneRsid[tabularRows[t], rsid]

GenotypeLookup[t_Tabular, rsids : {__String}] :=
    Block[{rows, byId},
        rows = tabularRows[t];
        byId = GroupBy[
            Select[rows, StringQ[Lookup[#, "ID", Missing[]]] &],
            #["ID"] &,
            First
        ];
        AssociationMap[
            r |-> Lookup[byId, r, Missing["NotFound", r]],
            rsids
        ]
    ]

GenotypeLookup[path_String, rsid_String, opts : OptionsPattern[ImportVCF]] :=
    GenotypeLookup[ImportVCF[path, opts], rsid]

GenotypeLookup[path_String, rsids : {__String}, opts : OptionsPattern[ImportVCF]] :=
    GenotypeLookup[ImportVCF[path, opts], rsids]

RegionVariants[g_ ? GenomeQ, chrom_String, {start_Integer, end_Integer}] :=
    backendDispatch[g, "Region", chrom, {start, end}]

RegionVariants[t_Tabular, chrom_String, {start_Integer, end_Integer}] :=
    Block[{rows, kept},
        rows = tabularRows[t];
        kept = Select[
            rows,
            #["CHROM"] === chrom && start <= #["POS"] <= end &
        ];
        rowsToTabular[kept]
    ]

RegionVariants[path_String, chrom_String, {start_Integer, end_Integer},
    opts : OptionsPattern[ImportVCF]] :=
    RegionVariants[
        ImportVCF[
            path,
            "Region" -> {chrom, {start, end}},
            "MaxVariants" -> Infinity,
            opts
        ],
        chrom,
        {start, end}
    ]

(* === analysis ===
   VariantSummary aggregates a variant row set into counts and ratios
   and returns them as a two-column Tabular of {Metric, Value} rows.
   The chromosome ordering helper turns "chr1".."chr22", "chrX", "chrY",
   "chrM" (and their unprefixed forms) into a sortable numeric key so
   the ByChromosome breakdown comes back in the conventional order. *)

chromKey[s_String] :=
    Block[{stripped, digits},
        stripped = If[ StringStartsQ[s, "chr"], StringDrop[s, 3], s];
        Replace[stripped, {
            "X" -> 23,
            "Y" -> 24,
            "M" | "MT" -> 25,
            d_String /; StringMatchQ[d, DigitCharacter ..] :> FromDigits[d],
            _ -> 99
        }]
    ]
chromKey[_] := 100

(* Bucket a VCF GT call into one of homRef / het / homAlt / missing /
   other.  Splits on either "/" (unphased) or "|" (phased). *)
classifyGT[gt_String] :=
    Block[{parts},
        parts = StringSplit[gt, "/" | "|"];
        Which[
            MemberQ[parts, "."], "missing",
            Length[parts] === 0, "other",
            Length[DeleteDuplicates[parts]] === 1,
                If[ First[parts] === "0", "homRef", "homAlt"],
            True, "het"
        ]
    ]
classifyGT[_] := "other"

(* Ts/Tv classifier for a biallelic single-nucleotide variant.
   Returns "Ts", "Tv", or None for indels / multiallelics. *)
tstvClass[ref_String, alts_List] :=
    Block[{a, pair},
        If[ Length[alts] =!= 1, Return[None]];
        a = First[alts];
        If[ StringLength[ref] =!= 1 || StringLength[a] =!= 1, Return[None]];
        If[ !MemberQ[{"A", "C", "G", "T"}, ref] || !MemberQ[{"A", "C", "G", "T"}, a],
            Return[None]
        ];
        pair = Sort[{ref, a}];
        Replace[pair, {
            {"A", "G"} -> "Ts",
            {"C", "T"} -> "Ts",
            _ -> "Tv"
        }]
    ]
tstvClass[___] := None

(* Read the three imputation provenance flags from an INFO Association
   and return the bucket label.  A row sets at most one of these in the
   Minimac4 output, but if none is present we return "NeitherFlag" so
   the resulting counts always cover the row set. *)
imputationBucket[info_Association] :=
    Which[
        TrueQ[Lookup[info, "TYPED", False]], "TYPED",
        TrueQ[Lookup[info, "IMPUTED", False]], "IMPUTED",
        TrueQ[Lookup[info, "TYPED_ONLY", False]], "TYPED_ONLY",
        True, "NeitherFlag"
    ]
imputationBucket[_] := "NeitherFlag"

variantSummaryRows[rows_List] :=
    Block[{total, variantRows, byChrom, chromOrdered, byFilter, byGenotype,
           byImpute, tstvCounts, ts, tv, ratio},
        total = Length[rows];
        variantRows = Count[rows, r_ /; Lookup[r, "ALT", {}] =!= {}];
        (* Lookup[{}, "CHROM"] gives Missing["KeyAbsent", ...] rather than an empty
           list, so an empty row set reached Counts as a Missing and raised
           Counts::invrp.  Map with a Nothing default is empty-safe and also drops
           a row that carries no CHROM at all. *)
        byChrom = Counts[Map[Lookup[#, "CHROM", Nothing] &, rows]];
        chromOrdered = KeySortBy[byChrom, chromKey];
        byFilter = Counts[Catenate @ Lookup[rows, "FILTER", {}]];
        byGenotype = Counts[Map[classifyGT[Lookup[#, "GT", ""]] &, rows]];
        byImpute = Merge[
            {
                <|"TYPED" -> 0, "IMPUTED" -> 0, "TYPED_ONLY" -> 0, "NeitherFlag" -> 0|>,
                Counts[Map[imputationBucket[Lookup[#, "INFO", <||>]] &, rows]]
            },
            Total
        ];
        tstvCounts = Counts @ DeleteCases[
            Map[tstvClass[Lookup[#, "REF", ""], Lookup[#, "ALT", {}]] &, rows],
            None
        ];
        ts = Lookup[tstvCounts, "Ts", 0];
        tv = Lookup[tstvCounts, "Tv", 0];
        ratio = If[ tv === 0, Missing[], N[ts / tv]];
        {
            <|"Metric" -> "TotalRows", "Value" -> total|>,
            <|"Metric" -> "VariantRows", "Value" -> variantRows|>,
            <|"Metric" -> "ByChromosome", "Value" -> chromOrdered|>,
            <|"Metric" -> "ByFilter", "Value" -> byFilter|>,
            <|"Metric" -> "ByGenotypeClass", "Value" -> byGenotype|>,
            <|"Metric" -> "ByImputationFlag", "Value" -> byImpute|>,
            <|"Metric" -> "TransitionTransversionRatio", "Value" -> ratio|>
        }
    ]

variantSummaryTabular[t_Tabular] :=
    Tabular @ variantSummaryRows[tabularRows[t]]

variantSummaryTabular[rows_List] :=
    Tabular @ variantSummaryRows[rows]

VariantSummary[g_ ? GenomeQ] :=
    backendDispatch[g, "Summary"]

VariantSummary[t_Tabular] := variantSummaryTabular[t]

VariantSummary[path_String, opts : OptionsPattern[ImportVCF]] :=
    VariantSummary[ImportVCF[path, opts]]

(* ToBioSequence will build a Wolfram BioSequence.  Reference genome
   data comes from GenomeData (GeneData does not exist in WL 15.0).
   Note also that on a BioSequence, Part / span extraction fails;
   StringTake works - so any subsequence logic here must go through
   StringTake rather than seq[[start ;; end]].  See
   ../docs/wl-biosequence-guide.md. *)
ToBioSequence::nyi = "ToBioSequence is not yet implemented.";
ToBioSequence[args___] := (Message[ToBioSequence::nyi]; $Failed)


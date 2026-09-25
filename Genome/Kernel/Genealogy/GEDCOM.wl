(* GEDCOM.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === GEDCOM 5.5.1 reader ===
   A GEDCOM line is  LEVEL [@XREF@] TAG [VALUE].  Level 0 opens a record;
   every deeper line nests under the closest preceding line one level up.
   CONT / CONC continue the preceding line's value (CONT adds a newline,
   CONC concatenates), so they are folded away before the tree is built
   and never surface as nodes of their own.

   The reader is deliberately tolerant: an unknown tag is kept verbatim in
   the node tree and simply ignored by the record extractors, so a vendor
   extension (Genotek writes _MIDN for the patronymic and _MARNM for a
   married surname) never fails the parse. *)

$gedcomMonths = <|
    "JAN" -> 1, "FEB" -> 2, "MAR" -> 3, "APR" -> 4, "MAY" -> 5, "JUN" -> 6,
    "JUL" -> 7, "AUG" -> 8, "SEP" -> 9, "OCT" -> 10, "NOV" -> 11, "DEC" -> 12
|>

(* Range and approximation keywords GEDCOM allows in front of a DATE value.
   They are stripped before the date tokens are read; the verbatim value is
   preserved alongside the parsed date so "ABT 1900" stays visible. *)
$gedcomDateKeywords = {"ABT", "EST", "CAL", "BEF", "AFT", "INT", "FROM", "BET", "AND", "TO"}

gedcomLexLine[line_String] :=
    Block[{trimmed, head, level, rest, restParts, hasXref, xref, tagValue, tv},
        trimmed = StringTrim @ StringDelete[line, "\:feff"];
        If[ trimmed === "", Return[Missing[]]];
        head = StringSplit[trimmed, " ", 2];
        If[ ! StringMatchQ[First[head], DigitCharacter ..], Return[Missing[]]];
        level = FromDigits[First[head]];
        rest = If[ Length[head] >= 2, head[[2]], ""];
        hasXref = StringStartsQ[rest, "@"];
        restParts = StringSplit[rest, " ", 2];
        xref = If[ hasXref, StringTrim[First[restParts], "@"], Missing[]];
        tagValue = If[ hasXref, If[ Length[restParts] >= 2, restParts[[2]], ""], rest];
        tv = StringSplit[tagValue, " ", 2];
        <|
            "Level" -> level,
            "Xref" -> xref,
            "Tag" -> If[ tv === {}, "", ToUpperCase @ First[tv]],
            "Value" -> If[ Length[tv] >= 2, tv[[2]], ""]
        |>
    ]

(* Split groups a line together with the CONT / CONC lines that follow it,
   so each group folds into a single node in one pass. *)
gedcomFoldContinuations[lines_List] :=
    Map[
        grp |-> MapAt[
            StringJoin[#, StringJoin @ Map[If[ #["Tag"] === "CONT", "\n", ""] <> #["Value"] &, Rest[grp]]] &,
            First[grp],
            "Value"
        ],
        Split[lines, MatchQ[#2["Tag"], "CONT" | "CONC"] &]
    ]

gedcomNodes[lines_List, level_Integer] :=
    Block[{pos, ends},
        If[ lines === {}, Return[{}]];
        pos = Flatten @ Position[lines[[All, "Level"]], level, {1}];
        If[ pos === {}, Return[{}]];
        ends = Append[Rest[pos] - 1, Length[lines]];
        MapThread[
            {s, e} |-> Append[lines[[s]], "Children" -> gedcomNodes[Take[lines, {s + 1, e}], level + 1]],
            {pos, ends}
        ]
    ]

(* === node accessors === *)

gedcomChild[node_Association, tag_String] :=
    SelectFirst[Lookup[node, "Children", {}], #["Tag"] === tag &, Missing["NotFound", tag]]

gedcomChildren[node_Association, tag_String] :=
    Select[Lookup[node, "Children", {}], #["Tag"] === tag &]

gedcomValue[node_Association, tag_String] :=
    Replace[gedcomChild[node, tag], {_Missing -> Missing["NotAvailable"], n_Association :> n["Value"]}]

gedcomValues[node_Association, tag_String] :=
    Lookup[gedcomChildren[node, tag], "Value", {}]

(* An @XREF@ pointer value ("@F1@") reduces to the bare key ("F1"). *)
gedcomPointer[v_] := If[ StringQ[v] && StringStartsQ[v, "@"], StringTrim[v, "@"], v]

gedcomNonEmpty[v_] := If[ StringQ[v] && StringTrim[v] =!= "", StringTrim[v], Missing["NotAvailable"]]

(* === date parsing ===
   The record's own granularity is preserved: a year-only entry stays a
   year-granularity DateObject rather than silently becoming 1 January,
   which matters because most pre-1900 genealogical dates are year-only
   and a fabricated day would read as evidence it is not. *)

parseGedcomDate[v_] := Missing["NotAvailable"] /; ! StringQ[v]

parseGedcomDate[s_String] :=
    Block[{tokens, year, monthToken, month, day},
        tokens = Select[
            StringSplit @ ToUpperCase @ StringTrim[s],
            ! MemberQ[$gedcomDateKeywords, #] &
        ];
        year = SelectFirst[tokens, StringMatchQ[#, DigitCharacter ..] && StringLength[#] >= 3 &, Missing[]];
        If[ MissingQ[year], Return[Missing["NotAvailable"]]];
        monthToken = SelectFirst[tokens, KeyExistsQ[$gedcomMonths, #] &, Missing[]];
        month = If[ MissingQ[monthToken], Missing[], $gedcomMonths[monthToken]];
        day = SelectFirst[tokens, StringMatchQ[#, DigitCharacter ..] && StringLength[#] <= 2 &, Missing[]];
        Which[
            ! MissingQ[month] && ! MissingQ[day],
                DateObject[{FromDigits[year], month, FromDigits[day]}, "Day"],
            ! MissingQ[month],
                DateObject[{FromDigits[year], month}, "Month"],
            True,
                DateObject[{FromDigits[year]}, "Year"]
        ]
    ]

(* The year alone, which is what the tree layout, the date range and the
   consistency checks actually compare on. *)
gedcomYear[d_DateObject] := Quiet @ Check[First @ DateValue[d, {"Year"}], Missing["NotAvailable"]]
gedcomYear[_] := Missing["NotAvailable"]

(* === name parsing ===
   GEDCOM writes the surname between slashes inside the NAME value:
   "Ivan Fedorovich /Sidorov/".  Sub-tags GIVN / SURN / _MIDN / _MARNM
   override the slash split when present, which is how a patronymic and a
   married surname survive the round trip. *)

parseGedcomName[v_] :=
    Block[{value = If[ StringQ[v], v, ""], surname, given},
        surname = Replace[
            StringCases[value, "/" ~~ s : Shortest[___] ~~ "/" :> s, 1],
            {{} -> "", {s_} :> s}
        ];
        given = StringTrim @ StringReplace[value, "/" ~~ Shortest[___] ~~ "/" -> ""];
        <|
            "Full" -> StringTrim @ StringReplace[value, "/" -> ""],
            "Given" -> given,
            "Surname" -> StringTrim[surname]
        |>
    ]

(* A display name that never comes back empty: the GEDCOM "NAME  //" form
   (a known-to-exist person whose name was never recorded) would otherwise
   render as a blank card in every plot. *)
gedcomDisplayName[given_, surname_, id_] :=
    Block[{parts = Select[{given, surname}, StringQ[#] && StringTrim[#] =!= "" &]},
        If[ parts === {},
            "Unknown (" <> ToString[id] <> ")",
            StringRiffle[Map[StringTrim, parts], " "]
        ]
    ]

(* === record extraction === *)

(* One dated event (BIRT / DEAT / MARR / DIV) flattened onto a key prefix,
   keeping both the parsed date and the verbatim GEDCOM text. *)
gedcomEvent[node_Association, tag_String, prefix_String] :=
    Block[{ev = gedcomChild[node, tag], dateText, placeText},
        If[ MissingQ[ev],
            Return[<|
                prefix -> Missing["NotAvailable"],
                prefix <> "Text" -> Missing["NotAvailable"],
                prefix <> "Place" -> Missing["NotAvailable"]
            |>]
        ];
        dateText = gedcomNonEmpty @ gedcomValue[ev, "DATE"];
        placeText = gedcomNonEmpty @ gedcomValue[ev, "PLAC"];
        <|
            prefix -> parseGedcomDate[dateText],
            prefix <> "Text" -> dateText,
            prefix <> "Place" -> placeText
        |>
    ]

gedcomPerson[node_Association] :=
    Block[{nameNode, parsed, given, middle, surname, married, id},
        id = Lookup[node, "Xref", Missing["NotAvailable"]];
        nameNode = gedcomChild[node, "NAME"];
        parsed = parseGedcomName[If[ MissingQ[nameNode], "", nameNode["Value"]]];
        given = Replace[
            If[ MissingQ[nameNode], Missing[], gedcomNonEmpty @ gedcomValue[nameNode, "GIVN"]],
            _Missing :> gedcomNonEmpty[parsed["Given"]]
        ];
        middle = If[ MissingQ[nameNode], Missing["NotAvailable"], gedcomNonEmpty @ gedcomValue[nameNode, "_MIDN"]];
        surname = Replace[
            If[ MissingQ[nameNode], Missing[], gedcomNonEmpty @ gedcomValue[nameNode, "SURN"]],
            _Missing :> gedcomNonEmpty[parsed["Surname"]]
        ];
        married = If[ MissingQ[nameNode], Missing["NotAvailable"], gedcomNonEmpty @ gedcomValue[nameNode, "_MARNM"]];
        Join[
            <|
                "ID" -> id,
                (* The verbatim NAME value keeps the patronymic in the display
                   name ("Ivan Fedorovich Sidorov"); the given / surname join
                   is the fallback for a record that only has the sub-tags. *)
                "Name" -> Replace[
                    gedcomNonEmpty[parsed["Full"]],
                    _Missing :> gedcomDisplayName[
                        Replace[given, _Missing -> ""],
                        Replace[surname, _Missing -> ""],
                        id
                    ]
                ],
                "GivenName" -> given,
                "MiddleName" -> middle,
                "Surname" -> surname,
                "MarriedName" -> married,
                "Sex" -> Replace[gedcomValue[node, "SEX"], {
                    "M" -> "Male",
                    "F" -> "Female",
                    _ -> Missing["Unknown"]
                }]
            |>,
            gedcomEvent[node, "BIRT", "BirthDate"],
            gedcomEvent[node, "DEAT", "DeathDate"],
            <|
                (* DEAT with no DATE (the bare "1 DEAT Y" form) still asserts
                   the person is dead, so deceased is a separate fact from
                   having a death date. *)
                "Deceased" -> ! MissingQ[gedcomChild[node, "DEAT"]],
                "Occupation" -> gedcomNonEmpty @ gedcomValue[node, "OCCU"],
                "Note" -> gedcomNonEmpty @ gedcomValue[node, "NOTE"],
                "ParentFamilies" -> Map[gedcomPointer, gedcomValues[node, "FAMC"]],
                "SpouseFamilies" -> Map[gedcomPointer, gedcomValues[node, "FAMS"]]
            |>
        ]
    ]

gedcomFamily[node_Association] :=
    Join[
        <|
            "ID" -> Lookup[node, "Xref", Missing["NotAvailable"]],
            "Husband" -> gedcomPointer @ gedcomValue[node, "HUSB"],
            "Wife" -> gedcomPointer @ gedcomValue[node, "WIFE"],
            "Children" -> Map[gedcomPointer, gedcomValues[node, "CHIL"]]
        |>,
        gedcomEvent[node, "MARR", "MarriageDate"],
        gedcomEvent[node, "DIV", "DivorceDate"]
    ]

(* === header === *)

gedcomHeader[nodes_List] :=
    Block[{head, sourceNode, submNode, submitters},
        head = SelectFirst[nodes, #["Tag"] === "HEAD" &, Missing[]];
        submitters = Select[nodes, #["Tag"] === "SUBM" &];
        If[ MissingQ[head],
            Return[<|"Source" -> Missing["NotAvailable"], "Encoding" -> Missing["NotAvailable"],
                "GEDCOMVersion" -> Missing["NotAvailable"], "Submitter" -> Missing["NotAvailable"]|>]
        ];
        sourceNode = gedcomChild[head, "SOUR"];
        submNode = If[ submitters === {}, Missing[], First[submitters]];
        <|
            "Source" -> Replace[
                gedcomNonEmpty[If[ MissingQ[sourceNode], "", sourceNode["Value"]]],
                _Missing -> Missing["NotAvailable"]
            ],
            "SourceName" -> If[ MissingQ[sourceNode], Missing["NotAvailable"], gedcomNonEmpty @ gedcomValue[sourceNode, "NAME"]],
            "Encoding" -> gedcomNonEmpty @ gedcomValue[head, "CHAR"],
            "GEDCOMVersion" -> Replace[
                gedcomChild[head, "GEDC"],
                {_Missing -> Missing["NotAvailable"], g_Association :> gedcomNonEmpty @ gedcomValue[g, "VERS"]}
            ],
            "Submitter" -> If[ MissingQ[submNode], Missing["NotAvailable"], gedcomNonEmpty @ gedcomValue[submNode, "NAME"]]
        |>
    ]

(* === ImportGEDCOM === *)

ImportGEDCOM::nofile = "ImportGEDCOM could not find the file `1`.";
ImportGEDCOM::noindi = "ImportGEDCOM parsed `1` but found no INDI records; the file may not be GEDCOM, or may use an encoding this reader cannot decode (only UTF-8, UTF-16 and ASCII are supported, not ANSEL).";

Options[ImportGEDCOM] = {
    CharacterEncoding -> Automatic
}

ImportGEDCOM[path_String, opts : OptionsPattern[]] :=
    Block[{text, encoding, lines, nodes, indi, fam, people, families},
        If[ ! FileExistsQ[path],
            Message[ImportGEDCOM::nofile, path];
            Return[$Failed]
        ];
        encoding = Replace[OptionValue[CharacterEncoding], Automatic -> "UTF-8"];
        text = Quiet @ Import[path, "Text", CharacterEncoding -> encoding];
        If[ ! StringQ[text], Return[$Failed]];
        lines = DeleteCases[
            Map[gedcomLexLine, StringSplit[text, {"\r\n", "\n", "\r"}]],
            _Missing
        ];
        nodes = gedcomNodes[gedcomFoldContinuations[lines], 0];
        indi = Select[nodes, #["Tag"] === "INDI" && StringQ[#["Xref"]] &];
        fam = Select[nodes, #["Tag"] === "FAM" && StringQ[#["Xref"]] &];
        If[ indi === {},
            Message[ImportGEDCOM::noindi, path];
            Return[$Failed]
        ];
        people = Association @ Map[#["Xref"] -> gedcomPerson[#] &, indi];
        families = Association @ Map[#["Xref"] -> gedcomFamily[#] &, fam];
        FamilyTree @ Join[
            <|
                "People" -> people,
                "Families" -> families,
                "Path" -> path
            |>,
            gedcomHeader[nodes]
        ]
    ]

ImportGEDCOM[File[path_String], opts : OptionsPattern[]] := ImportGEDCOM[path, opts]

(* === ExportGEDCOM ===
   The inverse of the reader, written so that a tree read from a GEDCOM and
   written again reproduces its records: the verbatim date text is kept when
   there is one, so "ABT 1900" survives, and the vendor tags for a patronymic
   and a married surname are written where the record has them, since the
   services that wrote them read them back. *)

ExportGEDCOM::notTree = "ExportGEDCOM expects a FamilyTree; received `1`.";

Options[ExportGEDCOM] = {
    "Submitter" -> Automatic,
    "LineEnding" -> "\n"
}

gedcomDateFromObject[d_DateObject] :=
    Block[{parts = Quiet @ Check[DateValue[d, {"Year", "Month", "Day"}], $Failed]},
        Which[
            ! ListQ[parts], Missing[],
            d["Granularity"] === "Year", ToString[parts[[1]]],
            d["Granularity"] === "Month", gedcomDateText[parts[[1]], parts[[2]], None],
            True, gedcomDateText[parts[[1]], parts[[2]], parts[[3]]]
        ]
    ]
gedcomDateFromObject[_] := Missing[]

gedcomEventLines[p_Association, tag_String, prefix_String, deceasedFallback_] :=
    Block[{text, place},
        text = Replace[Lookup[p, prefix <> "Text", Missing[]], Except[_String] :> gedcomDateFromObject @ Lookup[p, prefix, Missing[]]];
        place = Lookup[p, prefix <> "Place", Missing[]];
        Which[
            StringQ[text] || StringQ[place],
                Join[
                    {"1 " <> tag},
                    If[ StringQ[text], {"2 DATE " <> text}, {}],
                    If[ StringQ[place], {"2 PLAC " <> place}, {}]
                ],
            deceasedFallback, {"1 " <> tag <> " Y"},
            True, {}
        ]
    ]

gedcomPersonLines[a_Association, id_String] :=
    Block[{p = a["People"][id], given, middle, surname, married},
        given = Replace[Lookup[p, "GivenName", Missing[]], Except[_String] -> ""];
        middle = Replace[Lookup[p, "MiddleName", Missing[]], Except[_String] -> ""];
        surname = Replace[Lookup[p, "Surname", Missing[]], Except[_String] -> ""];
        married = Lookup[p, "MarriedName", Missing[]];
        Join[
            {
                "0 @" <> id <> "@ INDI",
                "1 NAME " <> StringTrim[StringRiffle @ Select[{given, middle}, # =!= "" &]] <> " /" <> surname <> "/"
            },
            If[ given =!= "", {"2 GIVN " <> given}, {}],
            If[ middle =!= "", {"2 _MIDN " <> middle}, {}],
            If[ surname =!= "", {"2 SURN " <> surname}, {}],
            If[ StringQ[married], {"2 _MARNM " <> married}, {}],
            Replace[Lookup[p, "Sex", Missing[]], {"Male" -> {"1 SEX M"}, "Female" -> {"1 SEX F"}, _ -> {}}],
            gedcomEventLines[p, "BIRT", "BirthDate", False],
            gedcomEventLines[p, "DEAT", "DeathDate", TrueQ[Lookup[p, "Deceased", False]]],
            Replace[Lookup[p, "Occupation", Missing[]], {s_String :> {"1 OCCU " <> s}, _ -> {}}],
            Replace[Lookup[p, "Note", Missing[]], {s_String :> Prepend[Map["2 CONT " <> # &, Rest @ StringSplit[s, "\n"]], "1 NOTE " <> First[StringSplit[s, "\n"], ""]], _ -> {}}],
            Map["1 FAMC @" <> # <> "@" &, Select[Lookup[p, "ParentFamilies", {}], KeyExistsQ[a["Families"], #] &]],
            Map["1 FAMS @" <> # <> "@" &, Select[Lookup[p, "SpouseFamilies", {}], KeyExistsQ[a["Families"], #] &]]
        ]
    ]

gedcomFamilyLines[a_Association, fid_String] :=
    Block[{f = a["Families"][fid]},
        Join[
            {"0 @" <> fid <> "@ FAM"},
            Replace[Lookup[f, "Husband", Missing[]], {s_String :> {"1 HUSB @" <> s <> "@"}, _ -> {}}],
            Replace[Lookup[f, "Wife", Missing[]], {s_String :> {"1 WIFE @" <> s <> "@"}, _ -> {}}],
            Map["1 CHIL @" <> # <> "@" &, Select[Lookup[f, "Children", {}], StringQ]],
            gedcomEventLines[f, "MARR", "MarriageDate", False],
            gedcomEventLines[f, "DIV", "DivorceDate", False]
        ]
    ]

ExportGEDCOM[path_String, ft_ ? FamilyTreeQ, opts : OptionsPattern[]] :=
    Block[{a = First[ft], submitter, lines, eol},
        submitter = Replace[OptionValue["Submitter"], Automatic :> Lookup[a, "Submitter", Missing[]]];
        eol = Replace[OptionValue["LineEnding"], Except[_String] -> "\n"];
        lines = Join[
            {
                "0 HEAD",
                "1 SOUR WolframInstitute/Genome",
                "2 NAME WolframInstitute/Genome family tree export",
                "1 GEDC",
                "2 VERS 5.5.1",
                "2 FORM LINEAGE-LINKED",
                "1 CHAR UTF-8"
            },
            If[ StringQ[submitter], {"1 SUBM @SUB1@", "0 @SUB1@ SUBM", "1 NAME " <> submitter}, {}],
            Catenate @ Map[gedcomPersonLines[a, #] &, Keys[a["People"]]],
            Catenate @ Map[gedcomFamilyLines[a, #] &, Keys[a["Families"]]],
            {"0 TRLR"}
        ];
        Export[path, StringRiffle[lines, eol] <> eol, "Text", CharacterEncoding -> "UTF-8"]
    ]

ExportGEDCOM[path_String, x_, opts : OptionsPattern[]] := (Message[ExportGEDCOM::notTree, x]; $Failed)

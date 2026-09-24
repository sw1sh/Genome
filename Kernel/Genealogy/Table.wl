(* Table.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === the family table ===
   The flat spreadsheet a genealogy service exports beside its GEDCOM: one
   row per person, and the links written as NAMES rather than as record
   keys - "Father: Ivanov Ivan Sergeevich" - which is what makes it
   readable in a spreadsheet and what makes reading it back a resolution
   problem.  Two conventions differ from GEDCOM and are inverted on the way
   through: the table's surname column holds the CURRENT surname (a married
   name where there is one) with the birth surname in its own column, where
   GEDCOM keeps the birth surname as SURN and the married name as _MARNM;
   and a table has no family records at all, so the unions are rebuilt from
   the father, mother, spouse and children columns of every row together,
   which is also how a person nobody names - a wife recorded with no name -
   still gets her family, from her own row.  Dates are day.month.year, with
   the day or the month simply absent when the record does not have them. *)

(* Column names as the Genotek export writes them, and the English names
   this paclet accepts and can write instead. *)
$familyTableColumns = {
    {"ID", "ID", "\:0049\:0044"},
    {"Surname", "Surname", "\:0424\:0430\:043c\:0438\:043b\:0438\:044f"},
    {"GivenName", "GivenName", "\:0418\:043c\:044f"},
    {"MiddleName", "MiddleName", "\:041e\:0442\:0447\:0435\:0441\:0442\:0432\:043e"},
    {"MaidenName", "MaidenName", "\:0414\:0435\:0432\:0438\:0447\:044c\:044f \:0444\:0430\:043c\:0438\:043b\:0438\:044f"},
    {"Sex", "Sex", "\:041f\:043e\:043b"},
    {"BirthDate", "BirthDate", "\:0414\:0430\:0442\:0430 \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f"},
    {"BirthPlace", "BirthPlace", "\:041c\:0435\:0441\:0442\:043e \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f"},
    {"DeathDate", "DeathDate", "\:0414\:0430\:0442\:0430 \:0441\:043c\:0435\:0440\:0442\:0438"},
    {"DeathPlace", "DeathPlace", "\:041c\:0435\:0441\:0442\:043e \:0441\:043c\:0435\:0440\:0442\:0438"},
    {"Status", "Status", "\:0421\:0442\:0430\:0442\:0443\:0441"},
    {"Father", "Father", "\:041e\:0442\:0435\:0446"},
    {"Mother", "Mother", "\:041c\:0430\:0442\:044c"},
    {"Spouse", "Spouse", "\:0421\:0443\:043f\:0440\:0443\:0433(\:0430)"},
    {"Children", "Children", "\:0414\:0435\:0442\:0438"}
}

(* header text (either language, case-folded) -> canonical column *)
$familyTableHeaderIndex := $familyTableHeaderIndex =
    Association @ Catenate @ Map[
        c |-> {ToLowerCase[c[[2]]] -> c[[1]], ToLowerCase[c[[3]]] -> c[[1]]},
        $familyTableColumns
    ]

$deceasedWords = {"\:0443\:043c\:0435\:0440(\:043b\:0430)", "\:0443\:043c\:0435\:0440", "\:0443\:043c\:0435\:0440\:043b\:0430", "\:0443\:043c\:0435\:0440\:043b", "deceased", "dead", "yes", "y"}

(* === CSV === *)

(* Genotek writes a byte-order mark, semicolons and CRLF; a spreadsheet
   saved by hand writes any of those differently, so the delimiter is
   sniffed from the header line. *)
familyTableDelimiter[text_String, setting_] :=
    Replace[setting, {
        Automatic :> Block[{header = First[StringSplit[text, "\n" | "\r\n" | "\r"], ""]},
            If[ StringCount[header, ";"] >= StringCount[header, ","], ";", ","]
        ],
        d_String :> d,
        _ -> ";"
    }]

(* The CSV importer does not honour a field-separator option for this
   format, so the records are split here: a quoted field may hold the
   delimiter, a doubled quote and a newline, and the file may end without a
   final line break.  One pass over the characters, carrying the quote state. *)
csvRecords[text_String, delim_String] :=
    Block[{chars = Characters[text], n, state, records},
        n = Length[chars];
        state = Fold[
            {st, i} |-> Block[{c = chars[[i]], next = If[ i < n, chars[[i + 1]], ""], q = st[[1]], field = st[[2]], row = st[[3]], rows = st[[4]]},
                Which[
                    q && c === "\"" && next === "\"", {True, field <> "\"", row, rows, i + 1},
                    c === "\"", {! q, field, row, rows, i},
                    ! q && c === delim, {False, "", Append[row, field], rows, i},
                    ! q && (c === "\n" || c === "\r"),
                        If[ c === "\r" && next === "\n",
                            {False, "", {}, Append[rows, Append[row, field]], i + 1},
                            {False, "", {}, Append[rows, Append[row, field]], i}
                        ],
                    True, {q, field <> c, row, rows, i}
                ]
            ] /. {a_, b_, c_, d_, skipTo_} :> {a, b, c, d, skipTo},
            {False, "", {}, {}, 0},
            Range[n]
        ];
        (* the fold cannot skip an index, so a doubled quote and a CRLF each
           mark the character they consumed; drop the rows those leave *)
        records = Append[state[[4]], Append[state[[3]], state[[2]]]];
        Select[records, AnyTrue[#, StringTrim[#] =!= "" &] &]
    ]

(* A field that carries the delimiter, a quote or a newline is quoted, with
   inner quotes doubled, which is the CSV rule every reader agrees on. *)
csvField[s_String, delim_String] :=
    If[ StringContainsQ[s, delim | "\"" | "\n" | "\r"],
        "\"" <> StringReplace[s, "\"" -> "\"\""] <> "\"",
        s
    ]
csvField[_, _] := ""

(* === import === *)

ImportFamilyTable::nofile = "ImportFamilyTable could not find the file `1`.";
ImportFamilyTable::noheader = "ImportFamilyTable found none of the expected columns in the header of `1`; a family table needs at least a surname or given-name column.";
ImportFamilyTable::unresolved = "ImportFamilyTable could not match `1` reference(s) to a row by name and left them out: `2`.";
ImportFamilyTable::ambiguous = "ImportFamilyTable found more than one row named `1`; the first is used.";

Options[ImportFamilyTable] = {
    "Delimiter" -> Automatic,
    CharacterEncoding -> Automatic
}

(* "25.08.1907" / "08.1907" / "1907", at the granularity the cell states,
   plus the GEDCOM text form the record keeps beside it. *)
parseTableDate[s_] :=
    Block[{t, parts, nums},
        t = If[ StringQ[s], StringTrim[s], ""];
        If[ t === "", Return[{Missing["NotAvailable"], Missing["NotAvailable"]}]];
        parts = StringSplit[t, "." | "/" | "-"];
        If[ ! AllTrue[parts, StringMatchQ[#, DigitCharacter ..] &],
            (* something GEDCOM-shaped or free text: keep it and let the
               GEDCOM date parser have a go *)
            Return[{parseGedcomDate[t], t}]
        ];
        nums = Map[FromDigits, parts];
        Which[
            Length[nums] === 3 && nums[[3]] > 31, {DateObject[{nums[[3]], nums[[2]], nums[[1]]}, "Day"], gedcomDateText[nums[[3]], nums[[2]], nums[[1]]]},
            Length[nums] === 3, {DateObject[{nums[[1]], nums[[2]], nums[[3]]}, "Day"], gedcomDateText[nums[[1]], nums[[2]], nums[[3]]]},
            Length[nums] === 2 && nums[[2]] > 31, {DateObject[{nums[[2]], nums[[1]]}, "Month"], gedcomDateText[nums[[2]], nums[[1]], None]},
            Length[nums] === 2, {DateObject[{nums[[1]], nums[[2]]}, "Month"], gedcomDateText[nums[[1]], nums[[2]], None]},
            Length[nums] === 1, {DateObject[{nums[[1]]}, "Year"], ToString[nums[[1]]]},
            True, {Missing["NotAvailable"], t}
        ]
    ]

$gedcomMonthNames = {"JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"}

gedcomDateText[year_Integer, month_Integer, None] /; 1 <= month <= 12 :=
    $gedcomMonthNames[[month]] <> " " <> ToString[year]
gedcomDateText[year_Integer, month_Integer, day_Integer] /; 1 <= month <= 12 :=
    StringPadLeft[ToString[day], 2, "0"] <> " " <> $gedcomMonthNames[[month]] <> " " <> ToString[year]
gedcomDateText[year_Integer, ___] := ToString[year]

parseTableSex[s_] :=
    Replace[ToLowerCase @ If[ StringQ[s], StringTrim[s], ""], {
        "\:043c" | "m" | "male" | "\:043c\:0443\:0436" | "\:043c\:0443\:0436\:0441\:043a\:043e\:0439" -> "Male",
        "\:0436" | "f" | "female" | "\:0436\:0435\:043d" | "\:0436\:0435\:043d\:0441\:043a\:0438\:0439" -> "Female",
        _ -> Missing["Unknown"]
    }]

(* Names are matched after collapsing the spelling noise a hand-kept table
   accumulates: case, extra spaces, and the yo / ye pair, which the same
   person's row and another row's reference routinely disagree on. *)
nameKey[s_String] :=
    ToLowerCase @ StringReplace[
        StringRiffle @ StringSplit[StringTrim[s]],
        {"\:0451" -> "\:0435", "\:0401" -> "\:0415"}
    ]
nameKey[_] := ""

(* The name a table writes when it refers to a person: current surname,
   given name, patronymic. *)
tableReferenceName[p_Association] :=
    StringRiffle @ Select[
        {
            Replace[Lookup[p, "MarriedName", Missing[]], Except[_String] :> Lookup[p, "Surname", Missing[]]],
            Lookup[p, "GivenName", Missing[]],
            Lookup[p, "MiddleName", Missing[]]
        },
        StringQ[#] && StringTrim[#] =!= "" &
    ]

tableRowToPerson[row_Association, id_String] :=
    Block[{surname, maiden, given, middle, married, birth, death, deceasedWord},
        surname = gedcomNonEmpty @ Lookup[row, "Surname", Missing[]];
        maiden = gedcomNonEmpty @ Lookup[row, "MaidenName", Missing[]];
        given = gedcomNonEmpty @ Lookup[row, "GivenName", Missing[]];
        middle = gedcomNonEmpty @ Lookup[row, "MiddleName", Missing[]];
        (* the table's surname is the current one; with a maiden name beside
           it, the current one is the married name and the maiden name is
           the birth surname GEDCOM calls SURN *)
        married = If[ StringQ[maiden] && StringQ[surname] && nameKey[maiden] =!= nameKey[surname], surname, Missing["NotAvailable"]];
        If[ StringQ[married], surname = maiden];
        birth = parseTableDate @ Lookup[row, "BirthDate", ""];
        death = parseTableDate @ Lookup[row, "DeathDate", ""];
        deceasedWord = MemberQ[$deceasedWords, ToLowerCase @ StringTrim @ Replace[Lookup[row, "Status", ""], Except[_String] -> ""]];
        <|
            "ID" -> id,
            "Name" -> Replace[
                StringRiffle @ Select[{given, middle, surname}, StringQ],
                "" :> gedcomDisplayName["", "", id]
            ],
            "GivenName" -> given,
            "MiddleName" -> middle,
            "Surname" -> surname,
            "MarriedName" -> married,
            "Sex" -> parseTableSex @ Lookup[row, "Sex", ""],
            "BirthDate" -> birth[[1]],
            "BirthDateText" -> birth[[2]],
            "BirthDatePlace" -> gedcomNonEmpty @ Lookup[row, "BirthPlace", Missing[]],
            "DeathDate" -> death[[1]],
            "DeathDateText" -> death[[2]],
            "DeathDatePlace" -> gedcomNonEmpty @ Lookup[row, "DeathPlace", Missing[]],
            "Deceased" -> (deceasedWord || ! MissingQ[death[[1]]] || StringQ[death[[2]]]),
            "Occupation" -> Missing["NotAvailable"],
            "Note" -> Missing["NotAvailable"],
            "ParentFamilies" -> {},
            "SpouseFamilies" -> {}
        |>
    ]

(* Split a cell that lists several people. *)
tableNameList[s_] :=
    If[ StringQ[s], Select[Map[StringTrim, StringSplit[s, ";"]], # =!= "" &], {}]

(* === family reconstruction ===
   A union is keyed by its ordered pair {father, mother}, either of which may
   be None.  Every row contributes what it knows: its own parents make it a
   child of that pair, its spouse makes a pair, and its children are children
   of the pair it forms with its spouse.  A child that turns up under both a
   one-parent pair and a two-parent pair containing that parent belongs to
   the fuller one. *)

orderedPair[a_Association, x_, y_] :=
    Block[{sx = Lookup[Lookup[a, x, <||>], "Sex", Missing[]], sy = Lookup[Lookup[a, y, <||>], "Sex", Missing[]]},
        Which[
            sx === "Female" || sy === "Male", {y, x},
            True, {x, y}
        ]
    ]

rebuildFamilies[people_Association, links_List] :=
    Block[{entries, families, pruned, keys},
        (* links: {"Child", child, father, mother} | {"Couple", x, y} | {"Child", child, x, y} from a parent's own row *)
        entries = Map[
            Replace[#, {
                {"Couple", x_, y_} :> {orderedPair[people, x, y], {}},
                {"Child", c_, f_, m_} :> {{Replace[f, Except[_String] -> None], Replace[m, Except[_String] -> None]}, {c}}
            }] &,
            links
        ];
        families = Merge[Map[Rule @@ # &, entries], DeleteDuplicates @* Catenate];
        (* a one-parent key whose child also sits under a two-parent key with
           that parent is the same family, recorded twice *)
        pruned = Association @ KeyValueMap[
            {key, kids} |-> key -> Select[
                kids,
                c |-> ! (MemberQ[key, None] && AnyTrue[
                    Keys[families],
                    k2 |-> k2 =!= key && FreeQ[k2, None] && MemberQ[k2, First @ DeleteCases[key, None]] && MemberQ[families[k2], c]
                ])
            ],
            families
        ];
        pruned = KeySelect[pruned, ! (MemberQ[#, None] && pruned[#] === {}) &];
        keys = Keys[pruned];
        Association @ MapIndexed[
            {key, i} |-> ("F" <> ToString[First[i]]) -> <|
                "ID" -> "F" <> ToString[First[i]],
                "Husband" -> Replace[key[[1]], None -> Missing["NotAvailable"]],
                "Wife" -> Replace[key[[2]], None -> Missing["NotAvailable"]],
                "Children" -> pruned[key],
                "MarriageDate" -> Missing["NotAvailable"],
                "MarriageDateText" -> Missing["NotAvailable"],
                "MarriageDatePlace" -> Missing["NotAvailable"],
                "DivorceDate" -> Missing["NotAvailable"],
                "DivorceDateText" -> Missing["NotAvailable"],
                "DivorceDatePlace" -> Missing["NotAvailable"]
            |>,
            keys
        ]
    ]

attachFamilies[people_Association, families_Association] :=
    Map[
        p |-> Join[
            p,
            <|
                "ParentFamilies" -> Keys @ Select[families, MemberQ[#["Children"], p["ID"]] &],
                "SpouseFamilies" -> Keys @ Select[families, #["Husband"] === p["ID"] || #["Wife"] === p["ID"] &]
            |>
        ],
        people
    ]

ImportFamilyTable[path_String, opts : OptionsPattern[]] :=
    Block[{text, delim, table, header, columns, rows, ids, people, fullIndex, shortIndex, rowById, keysOf, cellNames, mutualQ,
           resolve, unresolved, links, families},
        If[ ! FileExistsQ[path],
            Message[ImportFamilyTable::nofile, path];
            Return[$Failed]
        ];
        text = Quiet @ Import[path, "Text", CharacterEncoding -> Replace[OptionValue[CharacterEncoding], Automatic -> "UTF-8"]];
        If[ ! StringQ[text], Return[$Failed]];
        text = StringDelete[text, "\:feff"];
        delim = familyTableDelimiter[text, OptionValue["Delimiter"]];
        table = csvRecords[text, delim];
        If[ ! MatchQ[table, {{__} ..}], Return[$Failed]];
        header = Map[StringTrim @ ToString[#] &, First[table]];
        columns = Map[Lookup[$familyTableHeaderIndex, ToLowerCase[#], Missing[]] &, header];
        If[ ! AnyTrue[columns, MemberQ[{"Surname", "GivenName"}, #] &],
            Message[ImportFamilyTable::noheader, path];
            Return[$Failed]
        ];
        rows = Map[
            r |-> Association @ MapThread[
                If[ StringQ[#1], #1 -> ToString[#2], Nothing] &,
                {columns, PadRight[r, Length[columns], ""]}
            ],
            Select[Rest[table], AnyTrue[#, StringTrim[ToString[#]] =!= "" &] &]
        ];
        ids = MapIndexed[
            Replace[gedcomNonEmpty @ Lookup[#1, "ID", ""], _Missing :> "I" <> ToString[First[#2]]] &,
            rows
        ];
        people = Association @ MapThread[#2 -> tableRowToPerson[#1, #2] &, {rows, ids}];
        (* current-name and birth-name keys both resolve, since a reference
           may use either *)
        (* Every form a reference may take resolves: the current or the birth
           surname, with or without the patronymic.  Precedence matters: a
           reference is matched against each person's OWN full name first,
           so "Ivanov Ivan" finds the Ivan who has no patronymic before
           it is tried as a shortening of "Ivanov Ivan Sergeevich".  Only
           a reference that matches nobody in full falls back to the two-part
           key, and a two-part key several people share is reported and the
           first is used, rather than silently. *)
        fullIndex = Merge[
            Catenate @ KeyValueMap[
                {id, p} |-> Block[{given = Lookup[p, "GivenName", Missing[]], middle = Lookup[p, "MiddleName", Missing[]],
                                   surnames = DeleteDuplicates @ Select[Lookup[p, {"MarriedName", "Surname"}, Missing[]], StringQ]},
                    DeleteCases[Map[nameKey[StringRiffle @ Select[{#, given, middle}, StringQ]] -> id &, surnames], "" -> _]
                ],
                people
            ],
            DeleteDuplicates
        ];
        shortIndex = Merge[
            Catenate @ KeyValueMap[
                {id, p} |-> Block[{given = Lookup[p, "GivenName", Missing[]],
                                   surnames = DeleteDuplicates @ Select[Lookup[p, {"MarriedName", "Surname"}, Missing[]], StringQ]},
                    DeleteCases[Map[nameKey[StringRiffle @ Select[{#, given}, StringQ]] -> id &, surnames], "" -> _]
                ],
                people
            ],
            DeleteDuplicates
        ];
        unresolved = {};
        (* A short key several people share is settled by mutuality: the
           child a row names is the candidate whose own row names that row
           as a parent, a parent is the candidate whose row lists this row
           among its children, a spouse the one whose row names this row as
           spouse.  A grandfather and a grandson sharing a surname and a
           given name, the grandson written without his patronymic in his
           parents' children cell, is the case this decides. *)
        rowById = AssociationThread[ids -> rows];
        keysOf = rid |-> Block[{p = people[rid]},
            DeleteCases[
                Catenate @ Map[
                    sn |-> {
                        nameKey[StringRiffle @ Select[{sn, Lookup[p, "GivenName", Missing[]], Lookup[p, "MiddleName", Missing[]]}, StringQ]],
                        nameKey[StringRiffle @ Select[{sn, Lookup[p, "GivenName", Missing[]]}, StringQ]]
                    },
                    DeleteDuplicates @ Select[Lookup[p, {"MarriedName", "Surname"}, Missing[]], StringQ]
                ],
                ""
            ]
        ];
        cellNames = {cid, cols} |-> Map[nameKey, Catenate @ Map[tableNameList @ Lookup[rowById[cid], #, ""] &, cols]];
        mutualQ = {cid, rid, column} |-> Block[{mine = keysOf[rid]},
            IntersectingQ[
                mine,
                Replace[column, {
                    "Children" :> cellNames[cid, {"Father", "Mother"}],
                    "Father" | "Mother" :> cellNames[cid, {"Children"}],
                    "Spouse" :> cellNames[cid, {"Spouse"}],
                    _ -> {}
                }]
            ]
        ];
        resolve = {s, rid, column} |-> Block[{key = nameKey[s], full, short, mutual},
            full = Lookup[fullIndex, key, {}];
            short = Lookup[shortIndex, key, {}];
            Which[
                full =!= {}, First[full],
                short === {}, unresolved = Append[unresolved, s]; Missing[],
                Length[short] === 1, First[short],
                True,
                    mutual = Select[short, mutualQ[#, rid, column] &];
                    If[ Length[mutual] === 1,
                        First[mutual],
                        Message[ImportFamilyTable::ambiguous, s]; First[short]
                    ]
            ]
        ];
        links = Catenate @ MapThread[
            {row, id} |-> Block[{f, m, spouses, kids},
                f = Replace[gedcomNonEmpty @ Lookup[row, "Father", ""], {s_String :> resolve[s, id, "Father"], _ -> Missing[]}];
                m = Replace[gedcomNonEmpty @ Lookup[row, "Mother", ""], {s_String :> resolve[s, id, "Mother"], _ -> Missing[]}];
                spouses = Select[Map[resolve[#, id, "Spouse"] &, tableNameList @ Lookup[row, "Spouse", ""]], StringQ];
                kids = Select[Map[resolve[#, id, "Children"] &, tableNameList @ Lookup[row, "Children", ""]], StringQ];
                Join[
                    If[ StringQ[f] || StringQ[m], {{"Child", id, f, m}}, {}],
                    Map[{"Couple", id, #} &, spouses],
                    Map[
                        c |-> Block[{pair = If[ spouses === {}, orderedPair[people, id, None], orderedPair[people, id, First[spouses]]]},
                            {"Child", c, pair[[1]], pair[[2]]}
                        ],
                        kids
                    ]
                ]
            ],
            {rows, ids}
        ];
        If[ unresolved =!= {},
            Message[ImportFamilyTable::unresolved, Length[DeleteDuplicates[unresolved]], DeleteDuplicates[unresolved]]
        ];
        families = rebuildFamilies[people, links];
        FamilyTree[<|
            "People" -> attachFamilies[people, families],
            "Families" -> families,
            "Path" -> path,
            "Source" -> "FamilyTable",
            "SourceName" -> FileNameTake[path],
            "Encoding" -> "UTF-8",
            "GEDCOMVersion" -> Missing["NotAvailable"],
            "Submitter" -> Missing["NotAvailable"]
        |>]
    ]

ImportFamilyTable[File[path_String], opts : OptionsPattern[]] := ImportFamilyTable[path, opts]

(* === export === *)

ExportFamilyTable::notTree = "ExportFamilyTable expects a FamilyTree; received `1`.";

Options[ExportFamilyTable] = {
    "Headers" -> "Russian",
    "Delimiter" -> ";",
    "ByteOrderMark" -> True,
    "LineEnding" -> "\r\n"
}

tableDate[p_Association, key_String] :=
    Block[{d = Lookup[p, key, Missing[]], text = Lookup[p, key <> "Text", Missing[]], parts},
        Which[
            MatchQ[d, _DateObject],
                parts = Quiet @ Check[DateValue[d, {"Year", "Month", "Day"}], $Failed];
                Which[
                    ! ListQ[parts], Replace[text, Except[_String] -> ""],
                    d["Granularity"] === "Year", ToString[parts[[1]]],
                    d["Granularity"] === "Month", StringPadLeft[ToString[parts[[2]]], 2, "0"] <> "." <> ToString[parts[[1]]],
                    True, StringPadLeft[ToString[parts[[3]]], 2, "0"] <> "." <> StringPadLeft[ToString[parts[[2]]], 2, "0"] <> "." <> ToString[parts[[1]]]
                ],
            StringQ[text], text,
            True, ""
        ]
    ]

tableRow[a_Association, id_String, headers_String] :=
    Block[{p = a["People"][id], name, families, father, mother, spouses, children, refName},
        refName = pid |-> Replace[Lookup[a["People"], pid, Missing[]], {q_Association :> tableReferenceName[q], _ -> ""}];
        {father, mother} = fatherMother[a, id];
        spouses = spouseIDs[a, id];
        children = childIDs[a, id];
        {
            id,
            Replace[Lookup[p, "MarriedName", Missing[]], Except[_String] :> Replace[Lookup[p, "Surname", Missing[]], Except[_String] -> ""]],
            Replace[Lookup[p, "GivenName", Missing[]], Except[_String] -> ""],
            Replace[Lookup[p, "MiddleName", Missing[]], Except[_String] -> ""],
            If[ StringQ[Lookup[p, "MarriedName", Missing[]]], Replace[Lookup[p, "Surname", Missing[]], Except[_String] -> ""], ""],
            Replace[Lookup[p, "Sex", Missing[]], {
                "Male" :> If[ headers === "English", "M", "\:043c"],
                "Female" :> If[ headers === "English", "F", "\:0436"],
                _ -> ""
            }],
            tableDate[p, "BirthDate"],
            Replace[Lookup[p, "BirthDatePlace", Missing[]], Except[_String] -> ""],
            tableDate[p, "DeathDate"],
            Replace[Lookup[p, "DeathDatePlace", Missing[]], Except[_String] -> ""],
            If[ TrueQ[Lookup[p, "Deceased", False]], If[ headers === "English", "deceased", "\:0443\:043c\:0435\:0440(\:043b\:0430)"], ""],
            If[ StringQ[father], refName[father], ""],
            If[ StringQ[mother], refName[mother], ""],
            StringRiffle[Map[refName, spouses], "; "],
            StringRiffle[Map[refName, children], "; "]
        }
    ]

ExportFamilyTable[path_String, ft_ ? FamilyTreeQ, opts : OptionsPattern[]] :=
    Block[{a = First[ft], headers, delim, eol, lines, text},
        headers = Replace[OptionValue["Headers"], Except["English" | "Russian"] -> "Russian"];
        delim = Replace[OptionValue["Delimiter"], Except[_String] -> ";"];
        eol = Replace[OptionValue["LineEnding"], Except[_String] -> "\r\n"];
        lines = Prepend[
            Map[StringRiffle[Map[csvField[#, delim] &, tableRow[a, #, headers]], delim] &, Keys[a["People"]]],
            StringRiffle[Map[csvField[If[ headers === "English", #[[2]], #[[3]]], delim] &, $familyTableColumns], delim]
        ];
        text = If[ TrueQ[OptionValue["ByteOrderMark"]], "\:feff", ""] <> StringRiffle[lines, eol] <> eol;
        Export[path, text, "Text", CharacterEncoding -> "UTF-8"]
    ]

ExportFamilyTable[path_String, x_, opts : OptionsPattern[]] := (Message[ExportFamilyTable::notTree, x]; $Failed)

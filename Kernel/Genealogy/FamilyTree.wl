(* FamilyTree.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === the FamilyTree head ===
   FamilyTree[<|"People" -> <|id -> person|>, "Families" -> <|id -> family|>, ...|>]

   Unlike Genome, a FamilyTree is NOT a lazy handle to a file: a GEDCOM is
   small enough to hold whole, and every query below is an in-memory graph
   walk.  The consequence for privacy is the opposite of Genome's, and it
   matters: rendering a real FamilyTree as a notebook OUTPUT embeds the
   entire payload - every relative's name, birth date and birthplace - in
   the notebook source, because the summary box is an InterpretationBox
   holding the object.  Documentation examples therefore build a synthetic
   tree; see the Privacy section of ../../AGENTS.md.

   Relationships are stored the way GEDCOM states them, through family
   records rather than as direct parent pointers, so a couple's children
   stay grouped under the union that produced them and a remarriage does
   not silently merge two sets of half-siblings. *)

$familyTreeRequiredKeys = {"People", "Families"}

FamilyTreeQ[FamilyTree[a_Association]] :=
    AllTrue[$familyTreeRequiredKeys, KeyExistsQ[a, #] &] &&
        AssociationQ[a["People"]] && AssociationQ[a["Families"]]
FamilyTreeQ[_] := False

(* === construction from plain person records ===
   FamilyTree[{<|"ID" -> ..., "Father" -> ..., "Mother" -> ...|>, ...}] builds
   the family records the rest of the code walks, so a tree can be written by
   hand without going through a GEDCOM file.  One family is synthesised per
   distinct parent pair. *)

FamilyTree::badpeople = "FamilyTree expects a list of person Associations each carrying an \"ID\"; `1` does not have that shape.";

familyKeyFor[father_, mother_] :=
    "F:" <> Replace[father, Except[_String] -> "?"] <> "+" <> Replace[mother, Except[_String] -> "?"]

FamilyTree[people : {__Association}] :=
    Block[{withIds, byId, pairs, families, parentFamilyOf, spouseFamiliesOf},
        If[ ! AllTrue[people, StringQ[Lookup[#, "ID", Missing[]]] &],
            Message[FamilyTree::badpeople, Short[people]];
            Return[$Failed]
        ];
        withIds = Association @ Map[#["ID"] -> # &, people];
        pairs = DeleteDuplicates @ Map[
            p |-> {Lookup[p, "Father", Missing[]], Lookup[p, "Mother", Missing[]]},
            Select[people, StringQ[Lookup[#, "Father", Missing[]]] || StringQ[Lookup[#, "Mother", Missing[]]] &]
        ];
        families = Association @ Map[
            pair |-> familyKeyFor @@ pair -> <|
                "ID" -> familyKeyFor @@ pair,
                "Husband" -> Replace[First[pair], Except[_String] -> Missing["NotAvailable"]],
                "Wife" -> Replace[Last[pair], Except[_String] -> Missing["NotAvailable"]],
                "Children" -> Map[
                    #["ID"] &,
                    Select[
                        people,
                        {Lookup[#, "Father", Missing[]], Lookup[#, "Mother", Missing[]]} === pair &
                    ]
                ],
                "MarriageDate" -> Missing["NotAvailable"],
                "MarriageDateText" -> Missing["NotAvailable"],
                "MarriageDatePlace" -> Missing["NotAvailable"]
            |>,
            pairs
        ];
        parentFamilyOf = p |-> Block[{k = familyKeyFor[Lookup[p, "Father", Missing[]], Lookup[p, "Mother", Missing[]]]},
            If[ KeyExistsQ[families, k] && (StringQ[Lookup[p, "Father", Missing[]]] || StringQ[Lookup[p, "Mother", Missing[]]]),
                {k},
                {}
            ]
        ];
        spouseFamiliesOf = p |-> Keys @ Select[
            families,
            #["Husband"] === p["ID"] || #["Wife"] === p["ID"] &
        ];
        byId = Map[
            p |-> Join[
                <|
                    "Name" -> Lookup[p, "Name", gedcomDisplayName[
                        Lookup[p, "GivenName", ""], Lookup[p, "Surname", ""], p["ID"]]],
                    "GivenName" -> Missing["NotAvailable"],
                    "MiddleName" -> Missing["NotAvailable"],
                    "Surname" -> Missing["NotAvailable"],
                    "MarriedName" -> Missing["NotAvailable"],
                    "Sex" -> Missing["Unknown"],
                    "BirthDate" -> Missing["NotAvailable"],
                    "BirthDateText" -> Missing["NotAvailable"],
                    "BirthDatePlace" -> Missing["NotAvailable"],
                    "DeathDate" -> Missing["NotAvailable"],
                    "DeathDateText" -> Missing["NotAvailable"],
                    "DeathDatePlace" -> Missing["NotAvailable"],
                    "Deceased" -> False,
                    "Occupation" -> Missing["NotAvailable"],
                    "Note" -> Missing["NotAvailable"]
                |>,
                KeyDrop[p, {"Father", "Mother"}],
                <|
                    "ParentFamilies" -> parentFamilyOf[p],
                    "SpouseFamilies" -> spouseFamiliesOf[p]
                |>
            ],
            withIds
        ];
        FamilyTree[<|
            "People" -> byId,
            "Families" -> families,
            "Source" -> "Association",
            "Path" -> Missing["NotAvailable"]
        |>]
    ]

(* === person resolution ===
   Every operator takes either a raw GEDCOM key ("I11") or a name fragment,
   because nobody remembers xref keys.  An ambiguous fragment returns the
   candidate list rather than silently picking one. *)

FamilyTree::nomatch = "No person in the tree matches `1`.";
FamilyTree::ambiguous = "`1` matches more than one person: `2`.  Use a longer fragment or the record key.";

resolvePerson[a_Association, id_String] /; KeyExistsQ[a["People"], id] := id

resolvePerson[a_Association, spec_String] :=
    Block[{matches},
        matches = Keys @ Select[
            a["People"],
            StringContainsQ[
                StringRiffle @ Select[
                    Lookup[#, {"Name", "GivenName", "MiddleName", "Surname", "MarriedName"}, ""],
                    StringQ
                ],
                spec,
                IgnoreCase -> True
            ] &
        ];
        Which[
            Length[matches] === 1, First[matches],
            matches === {}, Message[FamilyTree::nomatch, spec]; Missing["NotFound", spec],
            True,
                Message[FamilyTree::ambiguous, spec, Lookup[Values @ KeyTake[a["People"], matches], "Name"]];
                Missing["Ambiguous", matches]
        ]
    ]

resolvePerson[a_Association, x_] := Missing["NotFound", x]

(* === kinship walks === *)

parentIDs[a_Association, id_String] :=
    DeleteDuplicates @ Select[
        Catenate @ Map[
            f |-> Lookup[Lookup[a["Families"], f, <||>], {"Husband", "Wife"}, Missing[]],
            Lookup[Lookup[a["People"], id, <||>], "ParentFamilies", {}]
        ],
        StringQ[#] && KeyExistsQ[a["People"], #] &
    ]

childIDs[a_Association, id_String] :=
    DeleteDuplicates @ Select[
        Catenate @ Map[
            f |-> Lookup[Lookup[a["Families"], f, <||>], "Children", {}],
            Lookup[Lookup[a["People"], id, <||>], "SpouseFamilies", {}]
        ],
        StringQ[#] && KeyExistsQ[a["People"], #] &
    ]

spouseIDs[a_Association, id_String] :=
    DeleteDuplicates @ Select[
        Catenate @ Map[
            f |-> DeleteCases[Lookup[Lookup[a["Families"], f, <||>], {"Husband", "Wife"}, Missing[]], id],
            Lookup[Lookup[a["People"], id, <||>], "SpouseFamilies", {}]
        ],
        StringQ[#] && KeyExistsQ[a["People"], #] &
    ]

siblingIDs[a_Association, id_String] :=
    DeleteCases[
        DeleteDuplicates @ Select[
            Catenate @ Map[
                f |-> Lookup[Lookup[a["Families"], f, <||>], "Children", {}],
                Lookup[Lookup[a["People"], id, <||>], "ParentFamilies", {}]
            ],
            StringQ[#] && KeyExistsQ[a["People"], #] &
        ],
        id
    ]

(* Breadth-first closure over a step function, returning id -> distance.
   The visited set makes it cycle-safe, which matters because a mis-entered
   tree can genuinely contain a person who is their own ancestor. *)
kinshipClosure[step_, a_Association, id_String, maxDepth_] :=
    Block[{result},
        result = NestWhile[
            st |-> Block[{frontier, next},
                frontier = st["Frontier"];
                next = Association @ Map[
                    # -> st["Depth"] + 1 &,
                    DeleteDuplicates @ Select[
                        Catenate @ Map[step[a, #] &, frontier],
                        ! KeyExistsQ[st["Seen"], #] &
                    ]
                ];
                <|
                    "Seen" -> Join[st["Seen"], next],
                    "Frontier" -> Keys[next],
                    "Depth" -> st["Depth"] + 1
                |>
            ],
            <|"Seen" -> <|id -> 0|>, "Frontier" -> {id}, "Depth" -> 0|>,
            st |-> st["Frontier"] =!= {} && st["Depth"] < maxDepth
        ];
        KeyDrop[result["Seen"], id]
    ]

ancestorDistances[a_Association, id_String, maxDepth_] := kinshipClosure[parentIDs, a, id, maxDepth]
descendantDistances[a_Association, id_String, maxDepth_] := kinshipClosure[childIDs, a, id, maxDepth]

(* === generation index ===
   A person's generation is one deeper than their deepest known parent, which
   is what puts a couple with very different ancestor depths on the same row.
   Computed over a topological order; a cyclic (mis-entered) tree falls back
   to a flat index rather than failing. *)
generationIndex[a_Association] :=
    Block[{ids, edges, g, order},
        ids = Keys[a["People"]];
        edges = Catenate @ Map[
            child |-> Map[DirectedEdge[#, child] &, parentIDs[a, child]],
            ids
        ];
        g = Graph[ids, DeleteDuplicates[edges]];
        order = Quiet @ Check[TopologicalSort[g], $Failed];
        If[ order === $Failed,
            Return[AssociationMap[0 &, ids]]
        ];
        Fold[
            {gen, id} |-> Append[
                gen,
                id -> Replace[Map[Lookup[gen, #, 0] &, parentIDs[a, id]], {
                    {} -> 0,
                    ps_List :> Max[ps] + 1
                }]
            ],
            <||>,
            order
        ]
    ]

(* === FamilyTree properties === *)

familyTreePeople[a_Association] := a["People"]

personRow[a_Association, id_String] :=
    Block[{p = a["People"][id]},
        <|
            "ID" -> id,
            "Name" -> Lookup[p, "Name", Missing["NotAvailable"]],
            "Sex" -> Lookup[p, "Sex", Missing["Unknown"]],
            "Birth" -> gedcomYear @ Lookup[p, "BirthDate", Missing[]],
            "Death" -> gedcomYear @ Lookup[p, "DeathDate", Missing[]],
            "BirthPlace" -> Lookup[p, "BirthDatePlace", Missing["NotAvailable"]],
            "Parents" -> Length @ parentIDs[a, id],
            "Children" -> Length @ childIDs[a, id]
        |>
    ]

(* Tabular refuses a zero-row list of Associations, and Tabular[{}] loses the
   column names with it.  Filtering every row out of a one-row template keeps
   an empty result the same SHAPE as a full one, so a caller can read column
   names off a search that found nothing. *)
tabularOrEmpty[rows_List, cols_List] :=
    If[ rows === {},
        Select[Tabular[{AssociationMap[Missing["NotAvailable"] &, cols]}], False &],
        Tabular[rows]
    ]

$personColumns = {"ID", "Name", "Sex", "Birth", "Death", "BirthPlace", "Parents", "Children"}

familyTreeTabular[a_Association, ids_List] :=
    tabularOrEmpty[Map[personRow[a, #] &, ids], $personColumns]

lifeYears[p_Association, lang_ : "English"] :=
    Block[{b = gedcomYear @ Lookup[p, "BirthDate", Missing[]], d = gedcomYear @ Lookup[p, "DeathDate", Missing[]]},
        Which[
            IntegerQ[b] && IntegerQ[d], ToString[b] <> "-" <> ToString[d],
            IntegerQ[b] && TrueQ[Lookup[p, "Deceased", False]], ToString[b] <> "-?",
            IntegerQ[b], kinBorn[lang] <> ToString[b],
            IntegerQ[d], kinDied[lang] <> ToString[d],
            True, ""
        ]
    ]

familyTreeYearRange[a_Association] :=
    Block[{years},
        years = Select[
            Catenate @ Map[
                p |-> {gedcomYear @ Lookup[p, "BirthDate", Missing[]], gedcomYear @ Lookup[p, "DeathDate", Missing[]]},
                Values[a["People"]]
            ],
            IntegerQ
        ];
        If[ years === {}, Missing["NotAvailable"], {Min[years], Max[years]}]
    ]

familyTreeSurnames[a_Association] :=
    ReverseSort @ Counts @ Select[
        Catenate @ Map[
            p |-> DeleteDuplicates @ Select[Lookup[p, {"Surname", "MarriedName"}, Missing[]], StringQ],
            Values[a["People"]]
        ],
        StringQ
    ]

(* === consistency checks ===
   Every rule below is a hard biological or chronological impossibility, or a
   flag on a value far enough outside the plausible range to be worth a look.
   This is the cheapest real value a parsed tree gives back: transcription
   slips in dates are extremely common and they propagate into every archive
   query built from the record. *)

issueRow[severity_, id_, name_, issue_, detail_] :=
    <|"Severity" -> severity, "ID" -> id, "Person" -> name, "Issue" -> issue, "Detail" -> detail|>

$issueColumns = {"Severity", "ID", "Person", "Issue", "Detail"}

selfIssues[a_Association, id_String] :=
    Block[{p = a["People"][id], b, d, name},
        name = Lookup[p, "Name", id];
        b = gedcomYear @ Lookup[p, "BirthDate", Missing[]];
        d = gedcomYear @ Lookup[p, "DeathDate", Missing[]];
        Join[
            If[ IntegerQ[b] && IntegerQ[d] && d < b,
                {issueRow["Error", id, name, "Death before birth", ToString[b] <> " -> " <> ToString[d]]},
                {}
            ],
            If[ IntegerQ[b] && IntegerQ[d] && d - b > 120,
                {issueRow["Error", id, name, "Implausible lifespan", ToString[d - b] <> " years"]},
                {}
            ],
            If[ ! StringQ[Lookup[p, "Surname", Missing[]]] && ! StringQ[Lookup[p, "GivenName", Missing[]]],
                {issueRow["Warning", id, name, "No name recorded", "the GEDCOM NAME value is empty"]},
                {}
            ],
            If[ parentIDs[a, id] === {} && childIDs[a, id] === {} && spouseIDs[a, id] === {},
                {issueRow["Warning", id, name, "Not connected", "no parents, children or spouse in the tree"]},
                {}
            ]
        ]
    ]

parentChildIssues[a_Association, id_String] :=
    Block[{p = a["People"][id], childBirth, name},
        name = Lookup[p, "Name", id];
        childBirth = gedcomYear @ Lookup[p, "BirthDate", Missing[]];
        If[ ! IntegerQ[childBirth], Return[{}]];
        Catenate @ Map[
            parent |-> Block[{pp = a["People"][parent], pb, pd, pname, gap},
                pname = Lookup[pp, "Name", parent];
                pb = gedcomYear @ Lookup[pp, "BirthDate", Missing[]];
                pd = gedcomYear @ Lookup[pp, "DeathDate", Missing[]];
                gap = If[ IntegerQ[pb], childBirth - pb, Missing[]];
                Join[
                    If[ IntegerQ[gap] && gap < 12,
                        {issueRow[
                            "Error", id, name, "Parent too young",
                            pname <> " would have been " <> ToString[gap] <> " at this birth"
                        ]},
                        {}
                    ],
                    If[ IntegerQ[gap] && gap > 55 && Lookup[pp, "Sex", ""] === "Female",
                        {issueRow[
                            "Warning", id, name, "Mother implausibly old",
                            pname <> " would have been " <> ToString[gap] <> " at this birth"
                        ]},
                        {}
                    ],
                    If[ IntegerQ[pd] && childBirth > pd + 1,
                        {issueRow[
                            "Error", id, name, "Born after parent died",
                            pname <> " died " <> ToString[pd] <> ", child born " <> ToString[childBirth]
                        ]},
                        {}
                    ]
                ]
            ],
            parentIDs[a, id]
        ]
    ]

danglingIssues[a_Association] :=
    Catenate @ KeyValueMap[
        {fid, f} |-> Block[{refs},
            refs = Select[
                Join[Lookup[f, {"Husband", "Wife"}, Missing[]], Lookup[f, "Children", {}]],
                StringQ
            ];
            Map[
                ref |-> issueRow["Error", fid, fid, "Dangling family reference", "family points at unknown person " <> ref],
                Select[refs, ! KeyExistsQ[a["People"], #] &]
            ]
        ],
        a["Families"]
    ]

cycleIssues[a_Association] :=
    Map[
        id |-> issueRow[
            "Error", id, Lookup[a["People"][id], "Name", id], "Ancestor cycle",
            "this person is recorded as their own ancestor"
        ],
        Select[Keys[a["People"]], KeyExistsQ[ancestorDistances[a, #, 40], #] &]
    ]

duplicateIssues[a_Association] :=
    Catenate @ Map[
        grp |-> Map[
            id |-> issueRow[
                "Warning", id, Lookup[a["People"][id], "Name", id], "Possible duplicate",
                "shares name and birth year with " <> ToString[Length[grp] - 1] <> " other record(s)"
            ],
            grp
        ],
        Select[
            Values @ GroupBy[
                Select[Keys[a["People"]], IntegerQ[gedcomYear[Lookup[a["People"][#], "BirthDate", Missing[]]]] &],
                {Lookup[a["People"][#], "Name", ""], gedcomYear[Lookup[a["People"][#], "BirthDate", Missing[]]]} &
            ],
            Length[#] > 1 &
        ]
    ]

familyTreeIssues[a_Association] :=
    Block[{rows},
        rows = Join[
            Catenate @ Map[selfIssues[a, #] &, Keys[a["People"]]],
            Catenate @ Map[parentChildIssues[a, #] &, Keys[a["People"]]],
            danglingIssues[a],
            cycleIssues[a],
            duplicateIssues[a]
        ];
        tabularOrEmpty[SortBy[rows, {Replace[#["Severity"], {"Error" -> 0, _ -> 1}], #["Person"]} &], $issueColumns]
    ]

(* === graph and plot === *)

(* Family vertices are wrapped in a list so a GEDCOM whose INDI and FAM
   keys collide still yields distinct vertices. *)
familyVertex[fid_String] := {"FAM", fid}

sexColor["Male"] := StandardBlue
sexColor["Female"] := StandardRed
sexColor[_] := StandardGray

(* The families that lie entirely inside a restricted person set, plus their
   spouse links, so a filtered plot never dangles an edge into a person the
   caller asked to leave out. *)
inducedFamilies[a_Association, ids_List] :=
    Block[{keep = Association @ Map[# -> True &, ids]},
        Select[
            a["Families"],
            AnyTrue[
                Join[Lookup[#, {"Husband", "Wife"}, Missing[]], Lookup[#, "Children", {}]],
                StringQ[#] && KeyExistsQ[keep, #] &
            ] &
        ]
    ]

familyTreeEdges[a_Association, ids_List] :=
    Block[{keep, families},
        keep = Association @ Map[# -> True &, ids];
        families = inducedFamilies[a, ids];
        Catenate @ KeyValueMap[
            {fid, f} |-> Join[
                Map[
                    DirectedEdge[#, familyVertex[fid]] &,
                    Select[Lookup[f, {"Husband", "Wife"}, Missing[]], StringQ[#] && KeyExistsQ[keep, #] &]
                ],
                Map[
                    DirectedEdge[familyVertex[fid], #] &,
                    Select[Lookup[f, "Children", {}], StringQ[#] && KeyExistsQ[keep, #] &]
                ]
            ],
            families
        ]
    ]

(* === drawing ===
   A person is drawn from primitives in printer points: a rounded square
   carrying the initials, coloured by sex, with the name under it and a
   second line for the relationship to the root or the life years, and a
   dark corner on the square when the person is dead.  Drawing from
   primitives rather than from an Inset of a typeset expression is what lets
   the layout know each card's exact size, and it is why every layout below
   has to hand back coordinates in points: the card is 64 points wide
   whatever the coordinates are, so the coordinates must be points too. *)

$cardBox = 64.
$cardRadius = 10.
$cardNameOffset = 46.
$cardSubOffset = 60.
$cardLineStep = 13.5
$cardHeight = 100.
$pedigreeRowHeight = 152.
$pedigreePitch = 150.
$pedigreeBusDrop = 56.
$pedigreeSingleParentDrop = 72.
$placeholderBox = 34.
$familyNodeRadius = 4.5
$familyTreeCardGap = 16.
$familyTreeRowGap = 30.

sexFill["Male"] := LightDarkSwitched[Lighter[StandardBlue, 0.3], Darker[StandardBlue, 0.25]]
sexFill["Female"] := LightDarkSwitched[Lighter[StandardRed, 0.35], Darker[StandardRed, 0.25]]
sexFill[_] := LightDarkSwitched[Lighter[StandardGray, 0.3], Darker[StandardGray, 0.2]]
$rootFill = LightDarkSwitched[StandardOrange, Darker[StandardOrange, 0.15]]
$cardTextColor = LightDarkSwitched[GrayLevel[0.15], GrayLevel[0.9]]
$cardSubColor = LightDarkSwitched[GrayLevel[0.5], GrayLevel[0.65]]
$connectorColor = LightDarkSwitched[GrayLevel[0.72], GrayLevel[0.45]]
$placeholderColor = LightDarkSwitched[GrayLevel[0.75], GrayLevel[0.4]]

(* The full dates a record states, at the granularity it states them, which
   is what a reader needs to order a document; lifeYears is the compact form. *)
lifeDates[p_Association, lang_ : "English"] :=
    Block[{b = tableDate[p, "BirthDate"], d = tableDate[p, "DeathDate"]},
        Which[
            b =!= "" && d =!= "", b <> " - " <> d,
            b =!= "" && TrueQ[Lookup[p, "Deceased", False]], b <> " - ?",
            b =!= "", kinBorn[lang] <> b,
            d =!= "", kinDied[lang] <> d,
            True, ""
        ]
    ]

personInitials[p_Association, tr_ : None] :=
    Block[{parts = Select[Lookup[p, {"GivenName", "Surname"}, Missing[]], StringQ[#] && StringTrim[#] =!= "" &]},
        parts = Map[applyTransliteration[StringTrim[#], tr] &, parts];
        parts = Select[parts, # =!= "" &];
        If[ parts === {}, "?", StringJoin @ Map[ToUpperCase @ StringTake[#, 1] &, parts]]
    ]

(* Given name and surname only, the way a chart labels a card; the patronymic
   is in the record and in the full-name property, not on the picture. *)
personShortName[p_Association, tr_ : None, lang_ : "English"] :=
    Block[{parts = Select[Lookup[p, {"GivenName", "Surname"}, Missing[]], StringQ[#] && StringTrim[#] =!= "" &]},
        If[ parts === {},
            kinNoName[lang],
            StringRiffle[Map[applyTransliteration[StringTrim[#], tr] &, parts], " "]
        ]
    ]

(* "Labels" names the lines a card carries, in the order they appear.  A
   component the record cannot fill contributes nothing rather than a blank
   line, so a card never grows for information it does not have. *)
$labelComponents = {"Name", "Relationship", "Years", "Dates"}

labelComponentText[p_Association, "Name", relation_, lang_, tr_] := personShortName[p, tr, lang]
labelComponentText[p_Association, "Relationship", relation_, lang_, tr_] := Replace[relation, Except[_String] -> ""]
labelComponentText[p_Association, "Years", relation_, lang_, tr_] := lifeYears[p, lang]
labelComponentText[p_Association, "Dates", relation_, lang_, tr_] := lifeDates[p, lang]
labelComponentText[_, _, _, _, _] := ""

personCardSpec[p_Association, components_List, rootQ_, relation_, highlighted_, lang_ : "English", tr_ : None] :=
    Block[{lines},
        lines = DeleteCases[
            Map[labelComponentText[p, #, relation, lang, tr] &, components],
            ""
        ];
        <|
            "Type" -> "Card",
            "Initials" -> personInitials[p, tr],
            "Name" -> If[ components =!= {} && First[components] === "Name" && lines =!= {}, First[lines], ""],
            "Subs" -> If[ components =!= {} && First[components] === "Name" && lines =!= {}, Rest[lines], lines],
            "Fill" -> If[ rootQ, $rootFill, sexFill[Lookup[p, "Sex", Missing[]]]],
            "Deceased" -> TrueQ[Lookup[p, "Deceased", False]],
            "Highlighted" -> TrueQ[highlighted]
        |>
    ]

FamilyTreePlot::badlabels = "`1` is not a label specification; use None, All, Automatic, one of `2`, or a list of them.  Using Automatic.";

(* Automatic is the sensible default for the drawing at hand: what a chart
   built around one person shows, and the compact form once the picture has
   too many people for three lines each. *)
resolveLabels[value_, default_List, many_] :=
    Block[{expand},
        expand = c |-> Replace[c, {
            "NameRelationship" -> {"Name", "Relationship"},
            "NameYears" -> {"Name", "Years"},
            "NameDates" -> {"Name", "Dates"},
            s_String /; MemberQ[$labelComponents, s] :> {s},
            _ -> $Failed
        }];
        Replace[value, {
            None | False -> {},
            All | True -> {"Name", "Relationship", "Dates"},
            Automatic :> If[ TrueQ[many], {"Name"}, default],
            l_List :> Block[{parts = Map[expand, l]},
                If[ MemberQ[parts, $Failed],
                    Message[FamilyTreePlot::badlabels, value, $labelComponents];
                    If[ TrueQ[many], {"Name"}, default],
                    DeleteDuplicates @ Catenate[parts]
                ]
            ],
            other_ :> Block[{parts = expand[other]},
                If[ parts === $Failed,
                    Message[FamilyTreePlot::badlabels, other, $labelComponents];
                    If[ TrueQ[many], {"Name"}, default],
                    parts
                ]
            ]
        }]
    ]

cardWidth[spec_Association] :=
    Max[
        $cardBox,
        5.9 * StringLength[spec["Name"]],
        Max @ Prepend[Map[5.2 * StringLength[#] &, Lookup[spec, "Subs", {}]], 0.]
    ] + 12.

cardHeight[spec_Association] :=
    Block[{subs = Lookup[spec, "Subs", {}]},
        If[ spec["Name"] === "" && subs === {},
            $cardBox,
            $cardHeight - $cardLineStep + $cardLineStep * (1 + Length[subs]) -
                If[ spec["Name"] === "", $cardNameOffset - $cardBox / 2, 0.]
        ]
    ]

drawCard[spec_Association, {x_, y_}] :=
    Block[{h = $cardBox / 2, hl = spec["Highlighted"]},
        {
            EdgeForm[If[ hl, Directive[StandardOrange, AbsoluteThickness[2.5]], None]],
            FaceForm[spec["Fill"]],
            Rectangle[{x - h, y - h}, {x + h, y + h}, RoundingRadius -> $cardRadius],
            If[ spec["Deceased"],
                {
                    FaceForm[LightDarkSwitched[GrayLevel[0.12], GrayLevel[0.02]]], EdgeForm[None],
                    Polygon[{{x + h - 22, y + h - 2}, {x + h - 9, y + h - 2}, {x + h - 2, y + h - 9}, {x + h - 2, y + h - 22}}]
                },
                {}
            ],
            Text[Style[spec["Initials"], 19, White, FontWeight -> Bold], {x, y}],
            If[ spec["Name"] =!= "", Text[Style[spec["Name"], 10, $cardTextColor], {x, y - $cardNameOffset}], {}],
            MapIndexed[
                Text[Style[#1, 8.5, $cardSubColor],
                    {x, y - If[ spec["Name"] === "", $cardNameOffset, $cardSubOffset] - (First[#2] - 1) * $cardLineStep}] &,
                Lookup[spec, "Subs", {}]
            ]
        }
    ]

(* Vertex drawings are precomputed and the shape function closes over THEM,
   never over the tree.  A Graph carries its options inside the expression, so
   a closure over the payload would travel with every rendered plot and put
   every birthplace, note and family link into the notebook that shows it.
   These specs carry only what the picture already displays. *)
familyTreeVertexShape[shapes_Association][pos_, v_, size_] :=
    Replace[
        Lookup[shapes, Key[v], Missing[]],
        {
            spec_Association /; spec["Type"] === "Card" :> drawCard[spec, pos],
            {"Node", color_} :> {Opacity[0.9], color, EdgeForm[None], Disk[pos, $familyNodeRadius]},
            {"Hidden"} :> {},
            {"Placeholder", label_String} :> Block[{h = $placeholderBox / 2},
                {
                    EdgeForm[Directive[$placeholderColor, Dashing[{3, 3}], AbsoluteThickness[1]]], FaceForm[None],
                    Rectangle[pos - {h, h}, pos + {h, h}, RoundingRadius -> 7],
                    Text[Style[label, 7, $placeholderColor], pos]
                }
            ],
            _ -> {}
        }
    ]

vertexWidth[shapes_Association, v_] :=
    Replace[Lookup[shapes, Key[v], Missing[]], {
        spec_Association /; spec["Type"] === "Card" :> cardWidth[spec],
        {"Node", _} -> 2. * $familyNodeRadius,
        {"Hidden"} -> 1.,
        {"Placeholder", _} -> $placeholderBox,
        _ -> 10.
    }]

vertexHeight[shapes_Association, v_] :=
    Replace[Lookup[shapes, Key[v], Missing[]], {
        spec_Association /; spec["Type"] === "Card" :> cardHeight[spec],
        {"Node", _} -> 2. * $familyNodeRadius,
        {"Hidden"} -> 1.,
        {"Placeholder", _} -> $placeholderBox,
        _ -> 10.
    }]

(* === the pedigree layout ===
   The chart a genealogy service draws: the root at the bottom, ancestors
   fanning out above it, the father's line on the left and the mother's on
   the right at every generation, so a person's ancestry reads as a binary
   tree of slots.  Each ancestor's own siblings sit beside them, on the side
   away from the centre.  With "Direction" -> "Both" the root's descendants
   hang below.  Everything is in printer points. *)

(* The first parent family that exists in the tree, split into father and
   mother, since which side of the chart a parent goes on depends on it. *)
fatherMother[a_Association, id_String] :=
    Block[{fam},
        fam = SelectFirst[
            Lookup[Lookup[a["People"], id, <||>], "ParentFamilies", {}],
            KeyExistsQ[a["Families"], #] &,
            None
        ];
        If[ fam === None,
            {Missing[], Missing[]},
            Map[
                If[ StringQ[#] && KeyExistsQ[a["People"], #], #, Missing[]] &,
                Lookup[a["Families"][fam], {"Husband", "Wife"}, Missing[]]
            ]
        ]
    ]

(* id -> {generation, slot}: the root at {0, 0}, a father at {g + 1, 2 k}, a
   mother at {g + 1, 2 k + 1}.  Breadth-first with a visited set, so a
   mis-entered cycle terminates. *)
pedigreeSlots[a_Association, root_String, maxGens_] :=
    Block[{state},
        state = NestWhile[
            st |-> Block[{id, g, k, father, mother, next, slots = st["Slots"]},
                {id, g, k} = First[st["Queue"]];
                {father, mother} = fatherMother[a, id];
                next = Select[
                    {{father, g + 1, 2 k}, {mother, g + 1, 2 k + 1}},
                    StringQ[First[#]] && ! KeyExistsQ[slots, First[#]] && g < maxGens &
                ];
                <|
                    "Queue" -> Join[Rest[st["Queue"]], next],
                    "Slots" -> Join[slots, Association @ Map[#[[1]] -> {#[[2]], #[[3]]} &, next]]
                |>
            ],
            <|"Queue" -> {{root, 0, 0}}, "Slots" -> <|root -> {0, 0}|>|>,
            #["Queue"] =!= {} &
        ];
        state["Slots"]
    ]

(* The siblings that hang beside an ancestor: their brothers and sisters that
   are not themselves on the direct line. *)
pedigreeSiblings[a_Association, slots_Association] :=
    Association @ KeyValueMap[
        {id, gk} |-> id -> Select[siblingIDs[a, id], ! KeyExistsQ[slots, #] &],
        slots
    ]

pedigreeSide[{0, _}] := "Left"
pedigreeSide[{g_, k_}] := If[ k < 2^(g - 1), "Left", "Right"]

pedigreePlacement[a_Association, root_String, maxGens_, descendantsQ_] :=
    Block[{slots, siblings, rows, pitch, width, coords, singles, spouseFams, spouses, descendants, people},
        slots = pedigreeSlots[a, root, maxGens];
        siblings = pedigreeSiblings[a, slots];
        rows = GroupBy[Keys[slots], slots[#][[1]] &];
        pitch = $pedigreePitch;
        (* Wide enough that, in every row, an ancestor plus the siblings
           hanging off it fits in the slot the binary tree gives it. *)
        width = Max @ Prepend[
            KeyValueMap[
                {g, ids} |-> 2^g * (1 + Max @ Prepend[Map[Length[siblings[#]] &, ids], 0]) * pitch,
                rows
            ],
            pitch
        ];
        coords = Association @ KeyValueMap[
            {id, gk} |-> id -> {((gk[[2]] + 0.5) / 2^gk[[1]] - 0.5) * width, gk[[1]] * $pedigreeRowHeight},
            slots
        ];
        (* A lone known parent is centred over its child rather than left in
           the father's or mother's half-slot; the chart reads as a line, not
           as a gap. *)
        singles = Select[
            Keys[slots],
            Count[fatherMother[a, #], _String] === 1 && slots[#][[1]] < maxGens &
        ];
        coords = Fold[
            {c, id} |-> Block[{parent = First @ Select[fatherMother[a, id], StringQ]},
                If[ KeyExistsQ[c, parent], Append[c, parent -> {c[id][[1]], c[parent][[2]]}], c]
            ],
            coords,
            SortBy[singles, slots[#][[1]] &]
        ];
        coords = Join[
            coords,
            Association @ Catenate @ KeyValueMap[
                {id, sibs} |-> Block[{dir = If[ pedigreeSide[slots[id]] === "Left", -1, 1]},
                    MapIndexed[#1 -> coords[id] + {dir * First[#2] * pitch, 0} &, sibs]
                ],
                siblings
            ]
        ];
        (* Descendants: each generation is one row below the last, ordered by
           the parent's position and spaced evenly under the root, with each
           parent's spouse placed beside them so the couple has a union. *)
        spouses = <||>;
        descendants = <||>;
        If[ descendantsQ,
            Block[{level = {root}, depth = 0, placedSpouse},
                While[ level =!= {} && depth < maxGens,
                    placedSpouse = Association @ Catenate @ Map[
                        id |-> Map[# -> coords[id] + {pitch, 0} &, Take[Select[spouseIDs[a, id], ! KeyExistsQ[coords, #] &], UpTo[1]]],
                        level
                    ];
                    coords = Join[coords, placedSpouse];
                    spouses = Join[spouses, placedSpouse];
                    level = DeleteDuplicates @ Catenate @ Map[childIDs[a, #] &, level];
                    level = Select[level, ! KeyExistsQ[coords, #] &];
                    depth++;
                    If[ level =!= {},
                        level = SortBy[level, Mean[Map[Lookup[coords, #, {0, 0}][[1]] &, parentIDs[a, #]]] &];
                        coords = Join[
                            coords,
                            Association @ MapIndexed[
                                #1 -> {coords[root][[1]] + (First[#2] - (Length[level] + 1) / 2) * pitch, -depth * $pedigreeRowHeight} &,
                                level
                            ]
                        ];
                        descendants = Join[descendants, AssociationMap[depth &, level]]
                    ]
                ]
            ]
        ];
        people = Keys[coords];
        <|
            "Coordinates" -> coords,
            "People" -> people,
            "Slots" -> slots,
            "Pitch" -> pitch,
            (* the people whose parents are entirely unknown get the
               placeholders a chart shows above its top row *)
            "Orphans" -> Select[Keys[slots], fatherMother[a, #] === {Missing[], Missing[]} &]
        |>
    ]

(* The unions that link the placed people: a family with at least one placed
   spouse and at least one placed child.  A couple's union sits between them
   on their row; a lone parent's union sits below that parent's label, so the
   line to the child starts under the text rather than through it. *)
pedigreeFamilies[a_Association, coords_Association] :=
    Association @ KeyValueMap[
        {fid, f} |-> Block[{sp, ch},
            sp = Select[Lookup[f, {"Husband", "Wife"}, Missing[]], StringQ[#] && KeyExistsQ[coords, #] &];
            ch = Select[Lookup[f, "Children", {}], StringQ[#] && KeyExistsQ[coords, #] &];
            If[ sp === {} || ch === {},
                Nothing,
                fid -> <|
                    "Spouses" -> sp,
                    "Children" -> ch,
                    "Position" -> If[ Length[sp] === 2,
                        {Mean[Map[coords[#][[1]] &, sp]], coords[First[sp]][[2]]},
                        coords[First[sp]] - {0, $pedigreeSingleParentDrop}
                    ]
                |>
            ]
        ],
        a["Families"]
    ]

(* Connectors: a couple line between two spouses, and an elbow from the union
   down to a bus line and across to each child.  A lone parent's union has no
   couple line, since it already sits below the parent. *)
pedigreeEdgeShape[pts_List, DirectedEdge[_, {"FAM", _}]] :=
    If[ Abs[pts[[1, 2]] - pts[[-1, 2]]] < 0.5,
        {$connectorColor, AbsoluteThickness[1.2], Line[{pts[[1]], pts[[-1]]}]},
        {}
    ]

pedigreeEdgeShape[pts_List, DirectedEdge[{"FAM", _}, _]] :=
    Block[{u = pts[[1]], c = pts[[-1]], bus},
        bus = c[[2]] + $cardBox / 2 + $pedigreeBusDrop - $cardBox / 2;
        {
            $connectorColor, AbsoluteThickness[1.2], JoinForm["Round"],
            Line[{u, {u[[1]], bus}, {c[[1]], bus}, {c[[1]], c[[2]] + $cardBox / 2}}]
        }
    ]

pedigreeEdgeShape[pts_List, _] := {$connectorColor, AbsoluteThickness[1.2], Line[pts]}

(* === the layered layout ===
   Everybody in the tree, generation by generation, for a picture of a whole
   file rather than of one person's ancestry.  The layered embedding decides
   the structure; this stretches it horizontally by the smallest factor that
   keeps neighbouring cards in every row apart, which preserves the
   embedding's alignments and crossing order, and gives each row only the
   height its own contents need. *)
layeredLayout[vertices_List, edges_List, shapes_Association] :=
    Block[{base, byV, rows, rowKeys, scale, rowSpans, centers},
        base = Graph[vertices, edges, GraphLayout -> {"LayeredDigraphEmbedding", "Orientation" -> Top}];
        byV = AssociationThread[VertexList[base] -> GraphEmbedding[base]];
        rows = GroupBy[vertices, Round[byV[#][[2]], 0.001] &];
        rowKeys = ReverseSort @ Keys[rows];
        scale = Max @ Prepend[
            Catenate @ Map[
                row |-> Block[{sorted = SortBy[row, byV[#][[1]] &]},
                    If[ Length[sorted] < 2,
                        {},
                        Table[
                            Block[{u = sorted[[i]], w = sorted[[i + 1]], d},
                                d = byV[w][[1]] - byV[u][[1]];
                                (* A near-tie is treated like a tie: stretching
                                   the whole chart to separate two vertices the
                                   embedding put on top of each other would make
                                   the picture arbitrarily wide. *)
                                If[ d <= 0.01,
                                    1.,
                                    ((vertexWidth[shapes, u] + vertexWidth[shapes, w]) / 2 + $familyTreeCardGap) / d
                                ]
                            ],
                            {i, Length[sorted] - 1}
                        ]
                    ]
                ],
                Values[rows]
            ],
            1.
        ];
        rowSpans = AssociationMap[k |-> Max @ Map[vertexHeight[shapes, #] &, rows[k]], rowKeys];
        centers = Association @ Rest @ FoldList[
            {prev, k} |-> k -> Last[prev] - (rowSpans[First[prev]] / 2 + $familyTreeRowGap + rowSpans[k] / 2),
            First[rowKeys] -> 0.,
            Rest[rowKeys]
        ];
        centers = Prepend[centers, First[rowKeys] -> 0.];
        AssociationMap[
            v |-> {byV[v][[1]] * scale, centers[Round[byV[v][[2]], 0.001]]},
            vertices
        ]
    ]

(* === a caller's own GraphLayout ===
   The embedding is taken as given and scaled uniformly until no two vertices
   sit closer than a card, so the cards, whose size is fixed in points, land
   on it without overlapping.  A layout that puts two vertices on the same
   point cannot be separated by scaling and is left alone. *)
customLayout[vertices_List, edges_List, shapes_Association, layout_] :=
    Block[{base, emb, pairs, need, have, scale},
        base = Graph[vertices, edges, GraphLayout -> layout];
        emb = AssociationThread[VertexList[base] -> GraphEmbedding[base]];
        pairs = Subsets[vertices, {2}];
        need = Max @ Prepend[Map[Max[vertexWidth[shapes, #], vertexHeight[shapes, #]] &, vertices], 1.] + $familyTreeCardGap;
        have = Min @ Prepend[Select[Map[EuclideanDistance[emb[#[[1]]], emb[#[[2]]]] &, pairs], # > 0.01 &], Infinity];
        scale = If[ have === Infinity, 1., need / have];
        Map[scale * # &, emb]
    ]

(* === FamilyTreePlot === *)

Options[FamilyTreePlot] = {
    "Root" -> Automatic,
    "Layout" -> "Pedigree",
    "Generations" -> Automatic,
    "Direction" -> Automatic,
    "Labels" -> Automatic,
    "Highlight" -> {},
    "Placeholders" -> Automatic,
    "Language" -> "English",
    "Transliteration" -> None,
    GraphLayout -> Automatic,
    ImageSize -> Automatic
}

(* The root of a pedigree when none is named: the person with the most
   ancestors in the tree, which is who a file exported from a genealogy
   service is built around; the latest born breaks a tie. *)
automaticRoot[a_Association] :=
    Block[{ids = Keys[a["People"]]},
        If[ ids === {}, Return[Missing["NotAvailable"]]];
        First @ MaximalBy[
            ids,
            {Length @ ancestorDistances[a, #, 40], Replace[gedcomYear @ Lookup[a["People"][#], "BirthDate", Missing[]], _Missing -> -Infinity]} &
        ]
    ]

resolvePlotRoot[a_Association, opts_List] :=
    Block[{root = OptionValue[FamilyTreePlot, opts, "Root"]},
        Which[
            root === Automatic, automaticRoot[a],
            root === All || root === None, Missing["NotAvailable"],
            True, Replace[resolvePerson[a, root], Except[_String] -> Missing["NotAvailable"]]
        ]
    ]

(* Which people the layered plot covers: everybody, or the relatives of a root
   within a generation budget, plus the spouses that complete each couple on
   the way. *)
layeredPersonSet[a_Association, root_, gens_, direction_] :=
    Block[{ids, up, down},
        If[ ! StringQ[root], Return[Keys[a["People"]]]];
        up = If[ MemberQ[{"Both", "Ancestors", "Up"}, direction], Keys @ ancestorDistances[a, root, gens], {}];
        down = If[ MemberQ[{"Both", "Descendants", "Down"}, direction], Keys @ descendantDistances[a, root, gens], {}];
        ids = DeleteDuplicates @ Join[{root}, up, down];
        DeleteDuplicates @ Join[ids, Catenate @ Map[spouseIDs[a, #] &, ids]]
    ]

familyTreePlotFrame[vertices_List, edges_List, shapes_Association, coords_Association, extras_List, headroom_, edgeShape_, opts_List] :=
    Block[{xs, ys, plotRange, imageSize},
        xs = Map[v |-> {coords[v][[1]] - vertexWidth[shapes, v] / 2, coords[v][[1]] + vertexWidth[shapes, v] / 2}, vertices];
        ys = Map[v |-> {coords[v][[2]] - vertexHeight[shapes, v] + $cardBox / 2, coords[v][[2]] + $cardBox / 2}, vertices];
        (* headroom is what the Prolog draws above the top row, which the
           vertex extents cannot know about *)
        plotRange = {
            {Min[xs[[All, 1]]] - 16., Max[xs[[All, 2]]] + 16.},
            {Min[ys[[All, 1]]] - 12., Max[ys[[All, 2]]] + 12. + headroom}
        };
        (* PlotRange spans exactly as many points as ImageSize, so one
           coordinate unit is one printer point and every card lands where the
           layout put it.  The cap keeps a pathological layout from asking for
           an image the front end cannot allocate. *)
        imageSize = Replace[
            OptionValue[FamilyTreePlot, opts, ImageSize],
            Automatic :> Map[Min[#, 6000.] &, {plotRange[[1, 2]] - plotRange[[1, 1]], plotRange[[2, 2]] - plotRange[[2, 1]]}]
        ];
        Graph[
            vertices, edges,
            VertexShapeFunction -> familyTreeVertexShape[shapes],
            VertexCoordinates -> Map[coords, vertices],
            EdgeShapeFunction -> edgeShape,
            Prolog -> extras,
            PlotRange -> plotRange,
            PlotRangePadding -> None,
            ImageSize -> imageSize,
            FilterRules[
                FilterRules[opts, Options[Graph]],
                Except[{VertexShapeFunction, VertexCoordinates, EdgeShapeFunction, GraphLayout, ImageSize, PlotRange, Prolog}]
            ]
        ]
    ]

FamilyTreePlot[ft_ ? FamilyTreeQ, opts : OptionsPattern[]] :=
    Block[{a = First[ft], root, layout, gens, direction, labelMode, highlight, relationOf, cardFor, lang, tr,
           placement, coords, families, people, vertices, edges, shapes, extras, ids, userLayout},
        root = resolvePlotRoot[a, {opts}];
        userLayout = OptionValue[GraphLayout];
        layout = Which[
            userLayout =!= Automatic, "Graph",
            ! StringQ[root], "Layered",
            True, Replace[OptionValue["Layout"], Except["Pedigree" | "Layered"] -> "Pedigree"]
        ];
        gens = Replace[OptionValue["Generations"], {Automatic | All | Infinity -> 100}];
        direction = Replace[OptionValue["Direction"], Automatic :> If[ layout === "Pedigree", "Ancestors", "Both"]];
        highlight = Select[Map[resolvePerson[a, #] &, Flatten[{OptionValue["Highlight"]}]], StringQ];
        lang = kinshipLanguage[OptionValue["Language"]];
        tr = resolveTransliteration[OptionValue["Transliteration"]];
        relationOf = If[ StringQ[root], id |-> familyTreeRelationship[a, root, id, lang], id |-> Missing[]];
        cardFor = {id, mode} |-> personCardSpec[a["People"][id], mode, id === root, relationOf[id], MemberQ[highlight, id], lang, tr];
        If[ layout === "Pedigree",
            placement = pedigreePlacement[a, root, gens, MemberQ[{"Both", "Descendants", "Down"}, direction]];
            coords = placement["Coordinates"];
            people = placement["People"];
            labelMode = resolveLabels[OptionValue["Labels"], {"Name", "Relationship"}, Length[people] > 80];
            families = pedigreeFamilies[a, coords];
            coords = Join[coords, Association @ KeyValueMap[familyVertex[#1] -> #2["Position"] &, families]];
            edges = Catenate @ KeyValueMap[
                {fid, f} |-> Join[
                    Map[DirectedEdge[#, familyVertex[fid]] &, f["Spouses"]],
                    Map[DirectedEdge[familyVertex[fid], #] &, f["Children"]]
                ],
                families
            ];
            vertices = Join[people, Map[familyVertex, Keys[families]]];
            shapes = Join[
                AssociationMap[cardFor[#, labelMode] &, people],
                Association @ KeyValueMap[
                    familyVertex[#1] -> If[ Length[#2["Spouses"]] === 2, {"Node", $connectorColor}, {"Hidden"}] &,
                    families
                ]
            ];
            (* the placeholders a chart shows above the people whose parents
               are entirely unknown, with a bracket joining them to the card *)
            extras = If[ TrueQ[Replace[OptionValue["Placeholders"], Automatic -> True]],
                Catenate @ Map[
                    id |-> Block[{c = coords[id], top, gap = 0.19 * placement["Pitch"], h = $placeholderBox / 2},
                        top = c + {0, $cardBox / 2 + 58};
                        {
                            $placeholderColor, AbsoluteThickness[1],
                            Line[{c + {0, $cardBox / 2}, c + {0, $cardBox / 2 + 20}}],
                            Line[{{c[[1]] - gap, c[[2]] + $cardBox / 2 + 20}, {c[[1]] + gap, c[[2]] + $cardBox / 2 + 20}}],
                            Line[{{c[[1]] - gap, c[[2]] + $cardBox / 2 + 20}, {c[[1]] - gap, top[[2]] - h}}],
                            Line[{{c[[1]] + gap, c[[2]] + $cardBox / 2 + 20}, {c[[1]] + gap, top[[2]] - h}}],
                            familyTreeVertexShape[<|"f" -> {"Placeholder", kinSlotFather[lang]}, "m" -> {"Placeholder", kinSlotMother[lang]}|>][top - {gap, 0}, "f", 0],
                            familyTreeVertexShape[<|"f" -> {"Placeholder", kinSlotFather[lang]}, "m" -> {"Placeholder", kinSlotMother[lang]}|>][top + {gap, 0}, "m", 0]
                        }
                    ],
                    placement["Orphans"]
                ],
                {}
            ];
            Return @ familyTreePlotFrame[
                vertices, edges, shapes, coords, extras,
                If[ extras === {}, 0., 58. + $placeholderBox / 2 + 4.],
                pedigreeEdgeShape, {opts}
            ]
        ];
        (* layered, or a caller's own embedding: the whole file unless a root
           was actually named, since "everybody" is what this layout is for *)
        If[ OptionValue["Root"] === Automatic, root = Missing["NotAvailable"]; relationOf = id |-> Missing[]];
        ids = layeredPersonSet[a, root, gens, direction];
        edges = familyTreeEdges[a, ids];
        vertices = DeleteDuplicates @ Join[ids, Cases[edges, {"FAM", _String}, {2}]];
        If[ vertices === {}, Return[Graph[{}, {}]]];
        labelMode = resolveLabels[
            OptionValue["Labels"],
            If[ StringQ[root], {"Name", "Relationship"}, {"Name", "Years"}],
            Length[ids] > 80
        ];
        shapes = AssociationMap[
            v |-> If[ MatchQ[v, {"FAM", _String}],
                {"Node", LightDarkSwitched[GrayLevel[0.45], GrayLevel[0.7]]},
                cardFor[v, labelMode]
            ],
            vertices
        ];
        coords = If[ layout === "Graph",
            customLayout[vertices, edges, shapes, userLayout],
            layeredLayout[vertices, edges, shapes]
        ];
        familyTreePlotFrame[
            vertices, edges, shapes, coords, {}, 0.,
            ({$connectorColor, AbsoluteThickness[1.2], Line[#1]} &),
            {opts}
        ]
    ]

FamilyTreePlot[ft_ ? FamilyTreeQ, root_String, opts : OptionsPattern[]] :=
    FamilyTreePlot[ft, "Root" -> root, opts]

FamilyTreePlot::notTree = "FamilyTreePlot expects a FamilyTree; received `1`.";
FamilyTreePlot[x_, opts : OptionsPattern[]] := (Message[FamilyTreePlot::notTree, x]; $Failed)

(* === relationship between two people === *)

familyTreeRelationship[a_Association, from_String, to_String, lang_ : "English"] :=
    kinshipPhrase[kinshipDescriptor[a, from, to], kinshipLanguage[lang]]

(* === FamilyTree SubValues === *)

FamilyTree[a_Association]["People"] := a["People"]
FamilyTree[a_Association]["Families"] := a["Families"]
FamilyTree[a_Association]["Path"] := Lookup[a, "Path", Missing["NotAvailable"]]
FamilyTree[a_Association]["Source"] := Lookup[a, "Source", Missing["NotAvailable"]]
FamilyTree[a_Association]["Header"] := KeyDrop[a, {"People", "Families"}]
FamilyTree[a_Association]["PersonCount"] := Length[a["People"]]
FamilyTree[a_Association]["FamilyCount"] := Length[a["Families"]]
FamilyTree[a_Association]["IDs"] := Keys[a["People"]]
FamilyTree[a_Association]["Surnames"] := familyTreeSurnames[a]
FamilyTree[a_Association]["YearRange"] := familyTreeYearRange[a]
FamilyTree[a_Association]["Generations"] := generationIndex[a]
FamilyTree[a_Association]["GenerationCount"] :=
    Block[{gen = generationIndex[a]}, If[ gen === <||>, 0, Max[Values[gen]] + 1]]
FamilyTree[a_Association]["Issues"] := familyTreeIssues[a]

FamilyTree[a_Association]["Dataset"] := familyTreeTabular[a, Keys[a["People"]]]
FamilyTree[a_Association]["Tabular"] := familyTreeTabular[a, Keys[a["People"]]]

FamilyTree[a_Association]["Person", spec_] :=
    Block[{id = resolvePerson[a, spec]},
        If[ StringQ[id], Prepend[a["People"][id], "ID" -> id], id]
    ]

FamilyTree[a_Association]["Find", spec_String] :=
    familyTreeTabular[
        a,
        Keys @ Select[
            a["People"],
            StringContainsQ[
                StringRiffle @ Select[Lookup[#, {"Name", "GivenName", "MiddleName", "Surname", "MarriedName"}, ""], StringQ],
                spec,
                IgnoreCase -> True
            ] &
        ]
    ]

FamilyTree[a_Association]["Parents", spec_] :=
    Block[{id = resolvePerson[a, spec]}, If[ StringQ[id], familyTreeTabular[a, parentIDs[a, id]], id]]

FamilyTree[a_Association]["Children", spec_] :=
    Block[{id = resolvePerson[a, spec]}, If[ StringQ[id], familyTreeTabular[a, childIDs[a, id]], id]]

FamilyTree[a_Association]["Siblings", spec_] :=
    Block[{id = resolvePerson[a, spec]}, If[ StringQ[id], familyTreeTabular[a, siblingIDs[a, id]], id]]

FamilyTree[a_Association]["Spouses", spec_] :=
    Block[{id = resolvePerson[a, spec]}, If[ StringQ[id], familyTreeTabular[a, spouseIDs[a, id]], id]]

FamilyTree[a_Association]["Ancestors", spec_, gens : (_Integer | Infinity) : Infinity] :=
    Block[{id = resolvePerson[a, spec]},
        If[ StringQ[id],
            familyTreeTabular[a, Keys @ ancestorDistances[a, id, Replace[gens, Infinity -> 100]]],
            id
        ]
    ]

FamilyTree[a_Association]["Descendants", spec_, gens : (_Integer | Infinity) : Infinity] :=
    Block[{id = resolvePerson[a, spec]},
        If[ StringQ[id],
            familyTreeTabular[a, Keys @ descendantDistances[a, id, Replace[gens, Infinity -> 100]]],
            id
        ]
    ]

FamilyTree[a_Association]["Relationships", spec_, lang_ : "English"] :=
    Block[{id = resolvePerson[a, spec], language},
        If[ ! StringQ[id], Return[id]];
        language = kinshipLanguage[lang];
        tabularOrEmpty[
            Map[
                other |-> <|
                    "ID" -> other,
                    "Name" -> Lookup[a["People"][other], "Name", Missing["NotAvailable"]],
                    "Relationship" -> familyTreeRelationship[a, id, other, language],
                    "Birth" -> gedcomYear @ Lookup[a["People"][other], "BirthDate", Missing[]],
                    "Death" -> gedcomYear @ Lookup[a["People"][other], "DeathDate", Missing[]]
                |>,
                DeleteCases[Keys[a["People"]], id]
            ],
            {"ID", "Name", "Relationship", "Birth", "Death"}
        ]
    ]

FamilyTree[a_Association]["Relationship", from_, to_, lang_ : "English"] :=
    Block[{f = resolvePerson[a, from], t = resolvePerson[a, to]},
        If[ StringQ[f] && StringQ[t], familyTreeRelationship[a, f, t, lang], Missing["NotFound"]]
    ]

FamilyTree[a_Association]["Graph", opts___Rule] := FamilyTreePlot[FamilyTree[a], opts]
FamilyTree[a_Association]["Plot", opts___Rule] := FamilyTreePlot[FamilyTree[a], opts]

(* === FamilyTree UpValues === *)

FamilyTree /: Length[ft : FamilyTree[a_Association]] /; FamilyTreeQ[ft] := Length[a["People"]]

FamilyTree /: Normal[ft : FamilyTree[a_Association]] /; FamilyTreeQ[ft] := a

FamilyTree /: Keys[ft : FamilyTree[a_Association]] /; FamilyTreeQ[ft] := Keys[a["People"]]

(* === display ===
   The summary box reports counts and spans only.  It deliberately shows no
   name: a rendered box travels inside the notebook it was evaluated in. *)

$familyTreeAccent = RGBColor[0.85, 0.53, 0.20]

$familyTreeIcon[color_] :=
    Graphics[
        {
            CapForm["Round"],
            {Opacity[0.55], color, AbsoluteThickness[1.3],
                Line[{{{-1., 1.}, {0., 0.35}}, {{1., 1.}, {0., 0.35}}, {{0., 0.35}, {0., -0.15}},
                    {{-1., -0.8}, {0., -0.15}}, {{1., -0.8}, {0., -0.15}}}]},
            {color, EdgeForm[None], Disk[{-1., 1.}, 0.26], Disk[{1., 1.}, 0.26], Disk[{0., -0.15}, 0.26]},
            {Opacity[0.6], color, EdgeForm[None], Disk[{-1., -0.8}, 0.22], Disk[{1., -0.8}, 0.22]}
        },
        PlotRange -> {{-1.45, 1.45}, {-1.2, 1.4}},
        AspectRatio -> Automatic,
        ImageSize -> Dynamic[{
            Automatic,
            3.2 CurrentValue["FontCapHeight"] / AbsoluteCurrentValue[Magnification]
        }],
        Background -> None,
        ImagePadding -> 0
    ]

familyTreeSummaryItems[a_Association] :=
    Block[{range = familyTreeYearRange[a], issues},
        (* The consistency pass walks an ancestor closure per person, so it is
           only cheap on a tree of moderate size.  A big tree reports "not
           checked" rather than stalling every time the box is rendered. *)
        issues = If[ Length[a["People"]] <= 300,
            Quiet @ Check[Length[familyTreeIssues[a]], Missing[]],
            Missing["NotComputed"]
        ];
        {
            {
                BoxForm`SummaryItem[{"people: ", Length[a["People"]]}],
                BoxForm`SummaryItem[{"families: ", Length[a["Families"]]}],
                BoxForm`SummaryItem[{"years: ",
                    Replace[range, {{lo_, hi_} :> ToString[lo] <> "-" <> ToString[hi], _ -> "unknown"}]}]
            },
            {
                BoxForm`SummaryItem[{"generations: ", FamilyTree[a]["GenerationCount"]}],
                BoxForm`SummaryItem[{"surnames: ", Length @ familyTreeSurnames[a]}],
                BoxForm`SummaryItem[{"source: ", Replace[Lookup[a, "Source", Missing[]], _Missing -> "unknown"]}],
                BoxForm`SummaryItem[{"issues: ", Replace[issues, {0 -> "none", _Missing -> "not checked"}]}]
            }
        }
    ]

FamilyTree /: MakeBoxes[ft : FamilyTree[a_Association], form : StandardForm | TraditionalForm] /;
    FamilyTreeQ[ft] && TrueQ[BoxForm`UseIcons] :=
    With[{items = familyTreeSummaryItems[a]},
        BoxForm`ArrangeSummaryBox[
            FamilyTree, ft, $familyTreeIcon[$familyTreeAccent],
            First[items], Last[items], form,
            "Interpretable" -> Automatic
        ]
    ]

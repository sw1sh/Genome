(* Search.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* === genealogical record search ===
   One query shape, many record sets.  Providers fall into three classes and
   the distinction is not cosmetic, it is what the caller has to know:

     "Open"        a public HTTP API that needs no credential.  WikiTree,
                   Otkrytyi Spisok (the Soviet repression database, through
                   its MediaWiki API), Wikidata and Open Archives are queried
                   directly and return parsed records.
     "Credential"  a real API behind an OAuth token the user must obtain
                   themselves.  FamilySearch and Geni are wired up and stay
                   dormant until a token is present, so they never fail
                   noisily on a machine that has none.
     "Browser"     an archive with a search interface and NO public API.
                   Pamyat Naroda, Yandex Archive and Find a Grave are in this
                   class.  A plain HTTP fetch of their search page returns a
                   JavaScript shell or an anti-bot interstitial, so the query
                   is run in a real browser through the Playwright runner in
                   Assets/genealogy-browser.mjs, and the results are extracted
                   from the rendered page.  A saved session (GenealogyLogin)
                   unlocks the ones that gate results behind an account.
                   When the runner cannot start, or the archive answers with a
                   security check, the provider degrades to the deep link that
                   runs the query in the user's own browser and SAYS SO,
                   rather than reporting an empty result as an answer.

   Every provider maps onto the same row shape, so results from all of them
   concatenate into one Tabular:

     Provider, Name, Birth, Death, Place, Detail, URL

   NOTE that a search sends the name and dates it was given to a third party.
   Nothing is sent until GenealogySearch is called, and only the fields of the
   one person queried are sent, never the tree. *)

$genealogyProviders = <|
    "WikiTree" -> <|
        "Class" -> "Open",
        "Coverage" -> "Global single collaborative tree, strongest for Europe and North America",
        "Site" -> "https://www.wikitree.com"
    |>,
    "OpenList" -> <|
        "Class" -> "Open",
        "Coverage" -> "Otkrytyi Spisok: 3.3M victims of Soviet political repression, from regional Books of Memory",
        "Site" -> "https://ru.openlist.wiki"
    |>,
    "PermGenerations" -> <|
        "Class" -> "Open",
        "Coverage" -> "Pokoleniya Permskogo Kraya: an indexed name register of births, marriages and deaths from the metrical books of Perm guberniya, each record naming the parents and citing its archival file",
        "Site" -> "https://pokolenia.permkrai.ru"
    |>,
    "Wikidata" -> <|
        "Class" -> "Open",
        "Coverage" -> "Notable people with structured birth and death dates and parent links",
        "Site" -> "https://www.wikidata.org"
    |>,
    "OpenArchives" -> <|
        "Class" -> "Open",
        "Coverage" -> "Open Archives: civil registration and church records, mostly Dutch and Belgian archives",
        "Site" -> "https://www.openarchieven.nl"
    |>,
    "FamilySearch" -> <|
        "Class" -> "Credential",
        "Coverage" -> "Billions of indexed records worldwide, including Russian metrical books",
        "Site" -> "https://www.familysearch.org",
        "Credential" -> "FamilySearchToken",
        "Environment" -> "FAMILYSEARCH_TOKEN"
    |>,
    "Geni" -> <|
        "Class" -> "Credential",
        "Coverage" -> "Geni world family tree profiles",
        "Site" -> "https://www.geni.com",
        "Credential" -> "GeniToken",
        "Environment" -> "GENI_TOKEN"
    |>,
    "PamyatNaroda" -> <|
        "Class" -> "Browser",
        "Coverage" -> "Soviet WWII service, award, casualty and burial documents (subsumes OBD Memorial and Podvig Naroda)",
        "Site" -> "https://pamyat-naroda.ru"
    |>,
    "YandexArchive" -> <|
        "Class" -> "Browser",
        "Coverage" -> "Handwriting-searchable metrical books, confession lists and revision tales for the digitised regions",
        "Site" -> "https://yandex.ru/archive"
    |>,
    "FindAGrave" -> <|
        "Class" -> "Browser",
        "Coverage" -> "Headstone photographs and burial records",
        "Site" -> "https://www.findagrave.com"
    |>
|>

$genealogyResultColumns = {"Provider", "Name", "Birth", "Death", "Place", "Detail", "URL"}

GenealogySearch::badquery = "GenealogySearch could not build a query from `1`; give a name string, an Association of criteria, or a FamilyTree together with a person.";
GenealogySearch::unknownProvider = "`1` is not a known genealogy provider.  GenealogySearch[\"Providers\"] lists them.";
GenealogySearch::provider = "The `1` provider did not answer (network failure, a rate limit, or an unexpected response); its records are missing from this result.";

(* === credentials ===
   A token is read from the environment first (the non-interactive path used
   by scripts) and from SystemCredential second.  Neither is ever written to
   a result row. *)
genealogyToken[provider_String] :=
    Block[{spec = Lookup[$genealogyProviders, provider, <||>], env, cred},
        env = Lookup[spec, "Environment", Missing[]];
        env = If[ StringQ[env], Environment[env], $Failed];
        If[ StringQ[env] && StringTrim[env] =!= "", Return[StringTrim[env]]];
        cred = Lookup[spec, "Credential", Missing[]];
        cred = If[ StringQ[cred], Quiet @ SystemCredential[cred], $Failed];
        If[ StringQ[cred] && StringTrim[cred] =!= "", StringTrim[cred], Missing["NoCredential", provider]]
    ]

genealogyProviderAvailableQ[provider_String] :=
    Replace[Lookup[$genealogyProviders, provider, <||>]["Class"], {
        "Open" -> True,
        "Credential" :> StringQ[genealogyToken[provider]],
        (* A browser provider still answers with a link when the runner is
           missing, but "available" means it can actually search. *)
        "Browser" :> genealogyBrowserReadyQ[],
        _ -> False
    }]

(* === HTTP === *)

genealogyJSON[url_String] := genealogyJSON[url, {}]

genealogyJSON[url_String, headers_List] :=
    Block[{r},
        r = Quiet @ URLRead[
            HTTPRequest[url, <|"Headers" -> Join[{"User-Agent" -> $genomeUA}, headers]|>],
            Interactive -> False
        ];
        If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200,
            Replace[Quiet @ Developer`ReadRawJSONString[r["Body"]], Except[_Association | _List] -> $Failed],
            $Failed
        ]
    ]

(* Drop the criteria a provider was not given, so an empty field never
   becomes a literal empty query parameter. *)
presentParams[rules_List] := Select[rules, StringQ[Last[#]] && StringTrim[Last[#]] =!= "" &]

(* === query normalisation ===
   The canonical query keys are GivenName, MiddleName, Surname, BirthYear,
   DeathYear, Place and Text.  A bare string is split on the convention each
   script actually uses: Cyrillic names are written surname first, Latin
   names given name first. *)

(* WL's regex engine does not support the Unicode script property that would
   express "contains a Cyrillic letter", and a failed StringContainsQ returns
   unevaluated, which silently poisons the Which it sits in.  A codepoint test
   is both supported and cheaper. *)
cyrillicQ[s_String] := AnyTrue[ToCharacterCode[s], 1024 <= # <= 1279 &]
cyrillicQ[_] := False

genealogyFullName[q_Association] :=
    StringRiffle @ Select[
        Lookup[q, {"GivenName", "MiddleName", "Surname"}, Missing[]],
        StringQ[#] && StringTrim[#] =!= "" &
    ]

normalizeGenealogyQuery[q_Association] :=
    Join[
        <|
            "GivenName" -> Missing["NotAvailable"],
            "MiddleName" -> Missing["NotAvailable"],
            "Surname" -> Missing["NotAvailable"],
            "BirthYear" -> Missing["NotAvailable"],
            "DeathYear" -> Missing["NotAvailable"],
            "Place" -> Missing["NotAvailable"],
            "Text" -> Missing["NotAvailable"]
        |>,
        Select[q, StringQ[#] || IntegerQ[#] &]
    ]

normalizeGenealogyQuery[s_String] :=
    Block[{tokens, cyrillic},
        tokens = Select[StringSplit[StringTrim[s]], # =!= "" &];
        cyrillic = cyrillicQ[s];
        Which[
            Length[tokens] === 0, normalizeGenealogyQuery[<|"Text" -> s|>],
            Length[tokens] === 1, normalizeGenealogyQuery[<|"Surname" -> First[tokens], "Text" -> s|>],
            cyrillic,
                normalizeGenealogyQuery[<|
                    "Surname" -> tokens[[1]],
                    "GivenName" -> tokens[[2]],
                    "MiddleName" -> If[ Length[tokens] >= 3, tokens[[3]], Missing["NotAvailable"]],
                    "Text" -> s
                |>],
            True,
                normalizeGenealogyQuery[<|
                    "GivenName" -> First[tokens],
                    "MiddleName" -> If[ Length[tokens] >= 3, tokens[[2]], Missing["NotAvailable"]],
                    "Surname" -> Last[tokens],
                    "Text" -> s
                |>]
        ]
    ]

(* A person record out of a FamilyTree carries exactly the fields a query
   wants, so searching for an ancestor is a lookup away. *)
personToQuery[person_Association] :=
    normalizeGenealogyQuery @ <|
        "GivenName" -> Lookup[person, "GivenName", Missing[]],
        "MiddleName" -> Lookup[person, "MiddleName", Missing[]],
        "Surname" -> Lookup[person, "Surname", Missing[]],
        "BirthYear" -> gedcomYear @ Lookup[person, "BirthDate", Missing[]],
        "DeathYear" -> gedcomYear @ Lookup[person, "DeathDate", Missing[]],
        "Place" -> Lookup[person, "BirthDatePlace", Missing[]],
        "Text" -> Lookup[person, "Name", Missing[]]
    |>

resultRow[provider_String, name_, birth_, death_, place_, detail_, url_] :=
    <|
        "Provider" -> provider,
        "Name" -> Replace[name, Except[_String] -> Missing["NotAvailable"]],
        "Birth" -> birth,
        "Death" -> death,
        "Place" -> Replace[place, Except[_String] -> Missing["NotAvailable"]],
        "Detail" -> Replace[detail, Except[_String] -> Missing["NotAvailable"]],
        "URL" -> Replace[url, Except[_String] -> Missing["NotAvailable"]]
    |>

(* Leading year of an ISO-ish date string, ignoring the 0000 and 00 fillers
   WikiTree and GEDCOM both use for an unknown component. *)
leadingYear[s_] :=
    Block[{m},
        If[ ! StringQ[s], Return[Missing["NotAvailable"]]];
        m = StringCases[s, StartOfString ~~ y : (DigitCharacter ~~ DigitCharacter ~~ DigitCharacter ~~ DigitCharacter) :> y, 1];
        If[ m === {} || First[m] === "0000", Missing["NotAvailable"], FromDigits @ First[m]]
    ]

(* === spelling variants ===
   Unstressed "o" and "a" are pronounced identically in Russian, so a surname
   that a clerk wrote by ear drifts between them, and the drift is not even
   consistent within one family: a tree can hold a Safonov and a Safanov who
   are father and son.  An archive name index matches the string it was given,
   so searching one spelling silently misses the other, and "silently" is the
   problem: the caller sees a short result list, not a warning.

   The swap is confined to the ROOT.  A Russian surname suffix (-ov, -ev, -in,
   -sky and their feminine forms) is orthographically stable, so varying it
   only manufactures nonsense and multiplies requests.  The variant count is
   capped, since each one costs a query per provider. *)

$surnameSuffixes = {
    "\:043e\:0432\:0430", "\:0435\:0432\:0430", "\:0438\:043d\:0430", "\:044b\:043d\:0430",
    "\:0441\:043a\:0430\:044f", "\:0441\:043a\:0438\:0439", "\:0441\:043a\:043e\:0439",
    "\:043e\:0432", "\:0435\:0432", "\:0451\:0432", "\:0438\:043d", "\:044b\:043d"
}

$maxSurnameVariants = 4

surnameSpellingVariants[s_String] :=
    Block[{suffix, root, positions, combos},
        suffix = SelectFirst[$surnameSuffixes, StringEndsQ[s, #, IgnoreCase -> True] &, ""];
        root = StringDrop[s, -StringLength[suffix]];
        positions = Flatten @ Position[Characters[root], "\:0430" | "\:043e"];
        If[ positions === {} || Length[positions] > 4, Return[{s}]];
        combos = Tuples[{"\:0430", "\:043e"}, Length[positions]];
        DeleteDuplicates @ Prepend[
            Take[
                Map[
                    c |-> StringJoin[ReplacePart[Characters[root], Thread[positions -> c]]] <> suffix,
                    combos
                ],
                UpTo[$maxSurnameVariants]
            ],
            s
        ]
    ]

surnameSpellingVariants[_] := {}

(* The queries one call actually runs: the query as given, plus the same query
   under each alternative spelling of its surname. *)
genealogyQueryVariants[q_Association, setting_] :=
    Block[{surname, variants},
        surname = Lookup[q, "Surname", Missing[]];
        If[ ! StringQ[surname] || setting === False, Return[{q}]];
        variants = surnameSpellingVariants[surname];
        If[ setting === Automatic && Length[variants] > $maxSurnameVariants, Return[{q}]];
        Map[
            v |-> Append[q, "Surname" -> v],
            If[ TrueQ[setting] || setting === Automatic, variants, {surname}]
        ]
    ]

(* === WikiTree === *)

$wikiTreeFields = "Id,Name,FirstName,MiddleName,LastNameAtBirth,LastNameCurrent,BirthDate,DeathDate,BirthLocation,DeathLocation,Gender"

wikiTreeSearch[q_Association, n_Integer] :=
    Block[{params, json, matches},
        params = Join[
            {"action" -> "searchPerson", "fields" -> $wikiTreeFields, "limit" -> ToString[n]},
            presentParams[{
                "FirstName" -> Lookup[q, "GivenName", Missing[]],
                "LastName" -> Lookup[q, "Surname", Missing[]],
                "BirthDate" -> Replace[Lookup[q, "BirthYear", Missing[]], {y_Integer :> ToString[y] <> "-00-00", _ -> Missing[]}]
            }]
        ];
        json = genealogyJSON @ URLBuild["https://api.wikitree.com/api.php", params];
        If[ json === $Failed, Return[$Failed]];
        matches = Lookup[Replace[json, {l_List :> First[l, <||>], a_Association :> a}], "matches", {}];
        If[ ! ListQ[matches], Return[{}]];
        Map[
            m |-> resultRow[
                "WikiTree",
                StringRiffle @ Select[
                    Lookup[m, {"FirstName", "MiddleName", "LastNameAtBirth"}, Missing[]],
                    StringQ[#] && StringTrim[#] =!= "" &
                ],
                leadingYear @ Lookup[m, "BirthDate", Missing[]],
                leadingYear @ Lookup[m, "DeathDate", Missing[]],
                Lookup[m, "BirthLocation", Missing[]],
                StringRiffle[Select[{Lookup[m, "Gender", Missing[]], Lookup[m, "Name", Missing[]]}, StringQ], " / "],
                Replace[Lookup[m, "Name", Missing[]], {s_String :> "https://www.wikitree.com/wiki/" <> URLEncode[s], _ -> Missing[]}]
            ],
            (* A private profile comes back as an Id with no Name; it carries no
               readable record, so it is dropped rather than shown as a blank. *)
            Select[matches, AssociationQ[#] && StringQ[Lookup[#, "Name", Missing[]]] &]
        ]
    ]

(* === Otkrytyi Spisok (ru.openlist.wiki) ===
   Full-text search is disabled on the wiki, but every person is one page
   titled "Surname Given Patronymic (year)", so a prefix search over titles
   is the supported way in.  Each page body is a "Formular" template whose
   pipe-separated fields carry the record: birth date and place, nationality,
   arrest date, sentence, article, rehabilitation and the source Book of
   Memory.  Those fields are parsed rather than the rendered HTML. *)

openListTitleSearch[prefix_String, n_Integer] :=
    Block[{json},
        json = genealogyJSON @ URLBuild[
            "https://ru.openlist.wiki/api.php",
            {"action" -> "query", "list" -> "prefixsearch", "pssearch" -> prefix,
             "pslimit" -> ToString[n], "format" -> "json"}
        ];
        If[ ! AssociationQ[json], Return[$Failed]];
        Select[Lookup[Lookup[json, "query", <||>], "prefixsearch", {}], AssociationQ]
    ]

openListPageText[titles_List] :=
    Block[{json, pages},
        If[ titles === {}, Return[<||>]];
        json = genealogyJSON @ URLBuild[
            "https://ru.openlist.wiki/api.php",
            {"action" -> "query", "prop" -> "revisions", "rvprop" -> "content",
             "format" -> "json", "titles" -> StringRiffle[titles, "|"]}
        ];
        If[ ! AssociationQ[json], Return[<||>]];
        pages = Lookup[Lookup[json, "query", <||>], "pages", <||>];
        Association @ Map[
            p |-> Lookup[p, "title", ""] -> Replace[
                Lookup[p, "revisions", {}],
                {{r_Association, ___} :> Lookup[r, "*", ""], _ -> ""}
            ],
            Values[pages]
        ]
    ]

parseOpenListFormular[wikitext_String] :=
    Block[{body},
        body = Replace[
            StringCases[wikitext, "{{" ~~ ("\:0428\:0430\:0431\:043b\:043e\:043d:" | "") ~~ "\:0424\:043e\:0440\:043c\:0443\:043b\:044f\:0440" ~~ b : Shortest[___] ~~ "\n}}", 1],
            {{} -> "", {s_String} :> s}
        ];
        Association @ Cases[
            StringSplit[body, "\n"],
            l_String /; StringStartsQ[StringTrim[l], "|"] :>
                Replace[
                    StringSplit[StringDrop[StringTrim[l], 1], "=", 2],
                    {
                        {k_String, v_String} :> StringTrim[k] -> StringTrim[v],
                        _ -> Nothing
                    }
                ]
        ]
    ]

openListSearch[q_Association, n_Integer] :=
    Block[{prefix, hits, titles, texts},
        prefix = StringTrim @ StringRiffle @ Select[
            Lookup[q, {"Surname", "GivenName", "MiddleName"}, Missing[]],
            StringQ[#] && StringTrim[#] =!= "" &
        ];
        If[ prefix === "", prefix = Replace[Lookup[q, "Text", Missing[]], Except[_String] -> ""]];
        If[ prefix === "", Return[{}]];
        hits = openListTitleSearch[prefix, n];
        If[ hits === $Failed, Return[$Failed]];
        titles = Select[Lookup[hits, "title", {}], StringQ];
        texts = openListPageText[titles];
        Map[
            title |-> Block[{fields = parseOpenListFormular[Lookup[texts, title, ""]], detail},
                detail = StringRiffle[
                    Select[
                        {
                            Lookup[fields, "\:043d\:0430\:0446\:0438\:043e\:043d\:0430\:043b\:044c\:043d\:043e\:0441\:0442\:044c", Missing[]],
                            Replace[Lookup[fields, "\:0434\:0430\:0442\:0430 \:0430\:0440\:0435\:0441\:0442\:0430 1", Missing[]], s_String :> "arrested " <> s],
                            Lookup[fields, "\:043f\:0440\:0438\:0433\:043e\:0432\:043e\:0440 1", Missing[]],
                            Replace[Lookup[fields, "\:0441\:0442\:0430\:0442\:044c\:044f 1", Missing[]], s_String :> "art. " <> s],
                            Lookup[fields, "\:0438\:0441\:0442\:043e\:0447\:043d\:0438\:043a\:0438 \:0434\:0430\:043d\:043d\:044b\:0445", Missing[]]
                        },
                        StringQ
                    ],
                    "; "
                ];
                resultRow[
                    "OpenList",
                    StringTrim @ StringReplace[title, "(" ~~ Shortest[___] ~~ ")" -> ""],
                    leadingYear @ Lookup[fields, "\:0434\:0430\:0442\:0430 \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f", Missing[]],
                    Missing["NotAvailable"],
                    Lookup[fields, "\:043c\:0435\:0441\:0442\:043e \:0440\:043e\:0436\:0434\:0435\:043d\:0438\:044f", Missing[]],
                    detail,
                    "https://ru.openlist.wiki/" <> URLEncode @ StringReplace[title, " " -> "_"]
                ]
            ],
            titles
        ]
    ]

(* === Pokoleniya Permskogo Kraya ===
   A regional name index rather than a scan repository, which is what makes it
   worth a provider of its own: a hit is already a parsed record, and its card
   names both parents and cites the archival file (fond, opis, delo) the entry
   sits in, so a result can be ordered or read without a further search.  The
   search endpoint is a plain server-rendered GET, so this needs no browser;
   the result table is read with the HTML importer rather than by pattern
   matching on markup. *)

$permGenerationsBase = "https://pokolenia.permkrai.ru"

permGenerationsURL[q_Association] :=
    URLBuild[
        $permGenerationsBase <> "/records/search/",
        Join[
            {"kind" -> "0"},
            presentParams[{
                "lastname" -> Lookup[q, "Surname", Missing[]],
                "firstname" -> Lookup[q, "GivenName", Missing[]],
                "place" -> Lookup[q, "Place", Missing[]],
                "year" -> Replace[Lookup[q, "BirthYear", Missing[]], y_Integer :> ToString[y]]
            }],
            (* A year on its own is too strict for a nineteenth century record,
               where the register year and the stated year often differ. *)
            If[ IntegerQ[Lookup[q, "BirthYear", Missing[]]], {"interval" -> "3"}, {}]
        ]
    ]

genealogyHTML[url_String] :=
    Block[{r},
        r = Quiet @ URLRead[
            HTTPRequest[url, <|"Headers" -> {"User-Agent" -> $genomeUA}|>],
            Interactive -> False
        ];
        If[ MatchQ[r, _HTTPResponse] && r["StatusCode"] === 200, r["Body"], $Failed]
    ]

(* "11.05.1894" -> 1894 *)
permYear[s_] :=
    Block[{m},
        If[ ! StringQ[s], Return[Missing["NotAvailable"]]];
        m = StringCases[s, d : (DigitCharacter ~~ DigitCharacter ~~ DigitCharacter ~~ DigitCharacter) ~~ EndOfString :> d, 1];
        If[ m === {}, Missing["NotAvailable"], FromDigits @ First[m]]
    ]

(* The record card carries the part that matters: both parents and the
   archival citation.  One extra request per row, so it is capped by
   MaxResults and only made when "Detailed" is on. *)
permGenerationsDetail[url_String] :=
    Block[{body, text, father, mother, source, origin},
        body = genealogyHTML[url];
        If[ ! StringQ[body], Return[Missing["NotAvailable"]]];
        text = Quiet @ ImportString[body, {"HTML", "Plaintext"}];
        If[ ! StringQ[text], Return[Missing["NotAvailable"]]];
        text = StringReplace[text, WhitespaceCharacter .. -> " "];
        father = StringCases[text, "\:041e\:0442\:0435\:0446 " ~~ v : Except[","] .. :> StringTrim[v], 1];
        mother = StringCases[text, "\:041c\:0430\:0442\:044c " ~~ v : Except[","] .. :> StringTrim[v], 1];
        origin = StringCases[text, "\:041c\:0435\:0441\:0442\:043e \:043f\:0440\:043e\:0438\:0441\:0445\:043e\:0436\:0434\:0435\:043d\:0438\:044f: " ~~ v : Shortest[__] ~~ (" \:041a\:0440\:0435\:0441\:0442" | " \:0414\:0430\:0442\:0430" | " \:041e\:0442\:0435\:0446") :> StringTrim[v], 1];
        (* The card's plaintext runs straight into the page footer, so the
           citation is cut at the contacts block rather than at a tag. *)
        source = Map[
            StringTrim @ First @ StringSplit[#, "\:041a\:043e\:043d\:0442\:0430\:043a\:0442", 2, IgnoreCase -> True] &,
            StringCases[text, "\:0418\:0441\:0442\:043e\:0447\:043d\:0438\:043a: " ~~ v : Shortest[__] ~~ EndOfString :> v, 1]
        ];
        StringRiffle[
            Select[
                {
                    Replace[father, {{f_} :> "father " <> f, _ -> Missing[]}],
                    Replace[mother, {{m_} :> "mother " <> m, _ -> Missing[]}],
                    Replace[origin, {{o_} :> o, _ -> Missing[]}],
                    Replace[source, {{x_} :> x, _ -> Missing[]}]
                },
                StringQ
            ],
            "; "
        ]
    ]

permGenerationsSearch[q_Association, n_Integer] :=
    Block[{body, data, table, links, rows},
        If[ ! StringQ[Lookup[q, "Surname", Missing[]]], Return[{}]];
        body = genealogyHTML[permGenerationsURL[q]];
        If[ ! StringQ[body], Return[$Failed]];
        data = Quiet @ ImportString[body, {"HTML", "Data"}];
        (* A record with no stated place has three cells rather than four, so
           the table is matched loosely and the rows are padded. *)
        table = Map[
            PadRight[#, 4, ""] &,
            SelectFirst[
                Flatten[{data}, 1],
                MatchQ[#, {{_String, _String, _String, ___String} ..}] &,
                {}
            ]
        ];
        links = Select[
            Replace[Quiet @ ImportString[body, {"HTML", "Hyperlinks"}], Except[_List] -> {}],
            StringQ[#] && StringContainsQ[#, "/records/view/"] &
        ];
        rows = Take[table, UpTo[n]];
        MapIndexed[
            {row, i} |-> Block[{kind = row[[1]], name = row[[2]], date = row[[3]], place = row[[4]], url, year, detail},
                url = If[ Length[links] >= First[i], $permGenerationsBase <> links[[First[i]]], Missing[]];
                year = permYear[date];
                detail = If[
                    TrueQ[$genealogyPermDetail] && StringQ[url],
                    Block[{d = permGenerationsDetail[url]},
                        Pause[0.3];
                        If[ StringQ[d] && d =!= "", kind <> "; " <> d, kind]
                    ],
                    kind
                ];
                resultRow[
                    "PermGenerations",
                    name,
                    If[ StringContainsQ[kind, "\:0440\:043e\:0436\:0434\:0435\:043d\:0438\:0438"], year, Missing["NotAvailable"]],
                    If[ StringContainsQ[kind, "\:0441\:043c\:0435\:0440\:0442\:0438"], year, Missing["NotAvailable"]],
                    place,
                    detail,
                    url
                ]
            ],
            rows
        ]
    ]

(* === Wikidata === *)

wikidataClaimYear[claims_Association, property_String] :=
    Block[{c, time},
        c = Lookup[claims, property, {}];
        If[ ! ListQ[c] || c === {}, Return[Missing["NotAvailable"]]];
        time = Lookup[
            Lookup[Lookup[Lookup[First[c], "mainsnak", <||>], "datavalue", <||>], "value", <||>],
            "time",
            Missing[]
        ];
        If[ ! StringQ[time], Return[Missing["NotAvailable"]]];
        leadingYear @ StringDelete[time, StartOfString ~~ "+"]
    ]

wikidataSearch[q_Association, n_Integer] :=
    Block[{name, language, search, ids, entities},
        name = Replace[Lookup[q, "Text", Missing[]], Except[_String] :> genealogyFullName[q]];
        If[ ! StringQ[name] || StringTrim[name] === "", Return[{}]];
        language = If[ cyrillicQ[name], "ru", "en"];
        search = genealogyJSON @ URLBuild[
            "https://www.wikidata.org/w/api.php",
            {"action" -> "wbsearchentities", "search" -> name, "language" -> language,
             "uselang" -> language, "format" -> "json", "limit" -> ToString[n], "type" -> "item"}
        ];
        If[ ! AssociationQ[search], Return[$Failed]];
        ids = Select[Lookup[Lookup[search, "search", {}], "id", {}], StringQ];
        If[ ids === {}, Return[{}]];
        entities = genealogyJSON @ URLBuild[
            "https://www.wikidata.org/w/api.php",
            {"action" -> "wbgetentities", "ids" -> StringRiffle[ids, "|"],
             "props" -> "labels|descriptions|claims", "languages" -> language <> "|en",
             "format" -> "json"}
        ];
        If[ ! AssociationQ[entities], Return[$Failed]];
        Map[
            id |-> Block[{e = Lookup[Lookup[entities, "entities", <||>], id, <||>], claims, label, description},
                claims = Lookup[e, "claims", <||>];
                label = Lookup[Lookup[Lookup[e, "labels", <||>], language, <||>], "value", Missing[]];
                label = Replace[label, Except[_String] :> Lookup[Lookup[Lookup[e, "labels", <||>], "en", <||>], "value", Missing[]]];
                description = Lookup[Lookup[Lookup[e, "descriptions", <||>], language, <||>], "value", Missing[]];
                description = Replace[description, Except[_String] :> Lookup[Lookup[Lookup[e, "descriptions", <||>], "en", <||>], "value", Missing[]]];
                resultRow[
                    "Wikidata",
                    label,
                    wikidataClaimYear[claims, "P569"],
                    wikidataClaimYear[claims, "P570"],
                    Missing["NotAvailable"],
                    description,
                    "https://www.wikidata.org/wiki/" <> id
                ]
            ],
            ids
        ]
    ]

(* === Open Archives === *)

openArchivesDate[d_] :=
    If[ AssociationQ[d] && IntegerQ[Lookup[d, "year", Missing[]]], d["year"], Missing["NotAvailable"]]

openArchivesSearch[q_Association, n_Integer] :=
    Block[{name, json, docs},
        name = Replace[genealogyFullName[q], "" :> Replace[Lookup[q, "Text", Missing[]], Except[_String] -> ""]];
        If[ name === "", Return[{}]];
        json = genealogyJSON @ URLBuild[
            "https://api.openarch.nl/1.0/records/search.json",
            {"name" -> name, "number_show" -> ToString[n]}
        ];
        If[ ! AssociationQ[json], Return[$Failed]];
        docs = Select[Lookup[Lookup[json, "response", <||>], "docs", {}], AssociationQ];
        Map[
            d |-> Block[{year = openArchivesDate[Lookup[d, "eventdate", Missing[]]], eventType},
                eventType = Lookup[d, "eventtype", Missing[]];
                resultRow[
                    "OpenArchives",
                    Lookup[d, "personname", Missing[]],
                    If[ eventType === "Geboorte", year, Missing["NotAvailable"]],
                    If[ eventType === "Overlijden", year, Missing["NotAvailable"]],
                    Replace[Lookup[d, "eventplace", Missing[]], {{p_String, ___} :> p, p_String :> p, _ -> Missing[]}],
                    StringRiffle[
                        Select[{eventType, Lookup[d, "sourcetype", Missing[]], Lookup[d, "archive", Missing[]]}, StringQ],
                        "; "
                    ],
                    Lookup[d, "url", Missing[]]
                ]
            ],
            docs
        ]
    ]

(* === FamilySearch (token) ===
   The records search speaks GEDCOM X served as an Atom feed; each entry's
   title is the indexed record's display name and its id resolves to the ark
   the browser opens. *)

familySearchSearch[q_Association, n_Integer] :=
    Block[{token, criteria, json, entries},
        token = genealogyToken["FamilySearch"];
        If[ ! StringQ[token], Return[{}]];
        criteria = StringRiffle[
            Select[
                {
                    Replace[Lookup[q, "GivenName", Missing[]], s_String :> "givenName:\"" <> s <> "\""],
                    Replace[Lookup[q, "Surname", Missing[]], s_String :> "surname:\"" <> s <> "\""],
                    Replace[Lookup[q, "BirthYear", Missing[]], y_Integer :> "birthLikeDate:" <> ToString[y]],
                    Replace[Lookup[q, "Place", Missing[]], s_String :> "birthLikePlace:\"" <> s <> "\""]
                },
                StringQ
            ],
            " "
        ];
        If[ criteria === "", Return[{}]];
        json = genealogyJSON[
            URLBuild["https://api.familysearch.org/platform/records/search", {"q" -> criteria, "count" -> ToString[n]}],
            {"Authorization" -> "Bearer " <> token, "Accept" -> "application/x-gedcomx-atom+json"}
        ];
        If[ ! AssociationQ[json], Return[$Failed]];
        entries = Select[Lookup[json, "entries", {}], AssociationQ];
        Map[
            e |-> Block[{person, names},
                person = Replace[
                    Lookup[Lookup[Lookup[e, "content", <||>], "gedcomx", <||>], "persons", {}],
                    {{p_Association, ___} :> p, _ -> <||>}
                ];
                names = Replace[
                    Lookup[person, "names", {}],
                    {{nm_Association, ___} :> Lookup[nm, "nameForms", {}], _ -> {}}
                ];
                resultRow[
                    "FamilySearch",
                    Replace[Lookup[e, "title", Missing[]], Except[_String] :> Replace[names, {{nf_Association, ___} :> Lookup[nf, "fullText", Missing[]], _ -> Missing[]}]],
                    Missing["NotAvailable"],
                    Missing["NotAvailable"],
                    Missing["NotAvailable"],
                    Replace[Lookup[e, "id", Missing[]], Except[_String] -> Missing["NotAvailable"]],
                    Replace[
                        Lookup[e, "links", <||>],
                        {l_Association :> Lookup[Lookup[l, "self", <||>], "href", Missing[]], _ -> Missing[]}
                    ]
                ]
            ],
            entries
        ]
    ]

(* === Geni (token) === *)

geniSearch[q_Association, n_Integer] :=
    Block[{token, name, json, results},
        token = genealogyToken["Geni"];
        If[ ! StringQ[token], Return[{}]];
        name = Replace[genealogyFullName[q], "" :> Replace[Lookup[q, "Text", Missing[]], Except[_String] -> ""]];
        If[ name === "", Return[{}]];
        json = genealogyJSON @ URLBuild[
            "https://www.geni.com/api/profile/search",
            {"names" -> name, "access_token" -> token}
        ];
        If[ ! AssociationQ[json], Return[$Failed]];
        results = Take[Select[Lookup[json, "results", {}], AssociationQ], UpTo[n]];
        Map[
            r |-> resultRow[
                "Geni",
                Lookup[r, "name", Missing[]],
                leadingYear @ Lookup[Lookup[Lookup[r, "birth", <||>], "date", <||>], "formatted_date", Missing[]],
                leadingYear @ Lookup[Lookup[Lookup[r, "death", <||>], "date", <||>], "formatted_date", Missing[]],
                Lookup[Lookup[Lookup[r, "birth", <||>], "location", <||>], "place_name", Missing[]],
                Lookup[r, "about_me", Missing[]],
                Lookup[r, "profile_url", Lookup[r, "url", Missing[]]]
            ],
            results
        ]
    ]

(* === the browser runner ===
   Assets/genealogy-browser.mjs drives Playwright and prints one JSON result.
   It is found through the paclet's Asset extension when installed, and beside
   this file when running from a checkout; GENOME_BROWSER_RUNNER overrides
   both.  Node and playwright-core are the user's to install, so every failure
   path here degrades to a link rather than to an error. *)

$genealogySearchFile = $InputFileName

GenealogySearch::browser = "The `1` provider could not be searched in a browser (`2`).  Falling back to a search link for it.";
GenealogySearch::runner = "The genealogy browser runner could not be located.  Reinstall the paclet, or set GENOME_BROWSER_RUNNER to the path of genealogy-browser.mjs.";

genealogyRunnerPath[] :=
    Block[{env, asset, local},
        env = Environment["GENOME_BROWSER_RUNNER"];
        If[ StringQ[env] && FileExistsQ[env], Return[env]];
        asset = Quiet @ Check[PacletObject["WolframInstitute/Genome"]["AssetLocation", "GenealogyBrowser"], $Failed];
        If[ StringQ[asset] && FileExistsQ[asset], Return[asset]];
        (* a checkout: Kernel/Genealogy/Search.wl -> Assets/genealogy-browser.mjs *)
        local = FileNameJoin[{
            ParentDirectory[DirectoryName[$genealogySearchFile], 2],
            "Assets", "genealogy-browser.mjs"
        }];
        If[ FileExistsQ[local], local, Missing["NotFound"]]
    ]

(* A stored browser session is per user and per provider, and it holds
   cookies, so it lives outside the repository and outside the paclet. *)
genealogyStateDirectory[] :=
    Block[{env = Environment["GENOME_BROWSER_STATE"]},
        If[ StringQ[env] && StringTrim[env] =!= "",
            env,
            FileNameJoin[{$UserBaseDirectory, "ApplicationData", "WolframInstitute", "Genome", "browser-state"}]
        ]
    ]

genealogyStatePath[provider_String] :=
    FileNameJoin[{genealogyStateDirectory[], provider <> ".json"}]

genealogyBrowserReadyQ[] :=
    StringQ[genealogyRunnerPath[]] && onPathQ["node"]

(* Run one job through the runner.  The job travels as a temp file rather than
   on the command line so a Cyrillic query needs no shell quoting at all. *)
runGenealogyBrowser[job_Association, timeout_ : 180] :=
    Block[{runner, jobFile, res, out},
        runner = genealogyRunnerPath[];
        If[ ! StringQ[runner], Return[<|"ok" -> False, "kind" -> "no-runner", "error" -> "runner not found"|>]];
        jobFile = FileNameJoin[{$TemporaryDirectory, "genome-browser-job-" <> ToString[$ProcessID] <> "-" <> ToString[RandomInteger[10^9]] <> ".json"}];
        Export[jobFile, job, "JSON"];
        res = TimeConstrained[
            RunProcess[{"node", runner, jobFile}],
            timeout,
            <|"ExitCode" -> -1, "StandardOutput" -> "", "StandardError" -> "timed out in the kernel"|>
        ];
        Quiet @ DeleteFile[jobFile];
        If[ ! AssociationQ[res], Return[<|"ok" -> False, "kind" -> "error", "error" -> "could not run node"|>]];
        out = Quiet @ Developer`ReadRawJSONString[StringTrim @ Lookup[res, "StandardOutput", ""]];
        If[ ! AssociationQ[out],
            Return[<|
                "ok" -> False,
                "kind" -> "error",
                "error" -> StringTake[StringTrim @ Lookup[res, "StandardError", "no output from the runner"], UpTo[300]]
            |>]
        ];
        out
    ]

browserRow[provider_String, r_Association] :=
    resultRow[
        provider,
        Lookup[r, "name", Missing[]],
        Replace[Lookup[r, "birth", Missing[]], Except[_Integer] -> Missing["NotAvailable"]],
        Replace[Lookup[r, "death", Missing[]], Except[_Integer] -> Missing["NotAvailable"]],
        Lookup[r, "place", Missing[]],
        Lookup[r, "detail", Missing[]],
        Lookup[r, "url", Missing[]]
    ]

browserSearch[provider_String, q_Association, n_Integer] :=
    Block[{url, out, rows},
        url = providerURL[provider, q];
        If[ ! StringQ[url], Return[{}]];
        out = runGenealogyBrowser[<|
            "mode" -> "search",
            "provider" -> provider,
            "url" -> url,
            "max" -> n,
            "statePath" -> genealogyStatePath[provider],
            "headless" -> True,
            "timeoutMs" -> 45000
        |>];
        If[ ! TrueQ[Lookup[out, "ok", False]],
            Message[GenealogySearch::browser, provider, Lookup[out, "kind", "error"]];
            Return[linkSearch[provider, q]]
        ];
        rows = Lookup[out, "rows", {}];
        If[ ! ListQ[rows] || rows === {},
            (* An archive that answered and found nothing is a real answer, but
               the link is still worth handing back so the query can be widened
               by hand. *)
            Return[linkSearch[provider, q]]
        ];
        Map[browserRow[provider, #] &, Select[rows, AssociationQ]]
    ]

(* === GenealogyLogin ===
   Headed browser, driven by the person, cookies saved on close.  No password
   ever reaches this process or the kernel. *)

GenealogyLogin::provider = "GenealogyLogin works on the browser-class providers `1`.";
GenealogyLogin::failed = "GenealogyLogin could not save a session for `1`: `2`.";

genealogyLoginURL["PamyatNaroda"] = "https://pamyat-naroda.ru/"
genealogyLoginURL["YandexArchive"] = "https://passport.yandex.ru/auth?retpath=https%3A%2F%2Fyandex.ru%2Farchive"
genealogyLoginURL["FindAGrave"] = "https://www.findagrave.com/login"
genealogyLoginURL[_] = Missing["NotAvailable"]

GenealogyLogin[provider_String] :=
    Block[{out, statePath},
        If[ Lookup[Lookup[$genealogyProviders, provider, <||>], "Class", None] =!= "Browser",
            Message[GenealogyLogin::provider,
                Keys @ Select[$genealogyProviders, #["Class"] === "Browser" &]];
            Return[$Failed]
        ];
        statePath = genealogyStatePath[provider];
        out = runGenealogyBrowser[
            <|
                "mode" -> "login",
                "provider" -> provider,
                "url" -> genealogyLoginURL[provider],
                "statePath" -> statePath,
                "loginTimeoutMs" -> 900000
            |>,
            960
        ];
        If[ TrueQ[Lookup[out, "ok", False]],
            statePath,
            Message[GenealogyLogin::failed, provider, Lookup[out, "kind", "error"]];
            $Failed
        ]
    ]

GenealogyLogin[x_] := (Message[GenealogyLogin::provider, Keys @ Select[$genealogyProviders, #["Class"] === "Browser" &]]; $Failed)

(* === link providers ===
   No public API exists for these, so the provider returns the deep link that
   runs the query in a browser rather than pretending to have searched. *)

pamyatNarodaURL[q_Association] :=
    URLBuild[
        "https://pamyat-naroda.ru/heroes/",
        presentParams[{
            "last_name" -> Lookup[q, "Surname", Missing[]],
            "first_name" -> Lookup[q, "GivenName", Missing[]],
            "middle_name" -> Lookup[q, "MiddleName", Missing[]],
            "birth_year" -> Replace[Lookup[q, "BirthYear", Missing[]], y_Integer :> ToString[y]]
        }]
    ]

yandexArchiveURL[q_Association] :=
    URLBuild[
        "https://yandex.ru/archive/search",
        {"text" -> Replace[genealogyFullName[q], "" :> Replace[Lookup[q, "Text", Missing[]], Except[_String] -> ""]]}
    ]

findAGraveURL[q_Association] :=
    URLBuild[
        "https://www.findagrave.com/memorial/search",
        presentParams[{
            "firstname" -> Lookup[q, "GivenName", Missing[]],
            "lastname" -> Lookup[q, "Surname", Missing[]],
            "birthyear" -> Replace[Lookup[q, "BirthYear", Missing[]], y_Integer :> ToString[y]],
            "deathyear" -> Replace[Lookup[q, "DeathYear", Missing[]], y_Integer :> ToString[y]]
        }]
    ]

providerURL[provider_String, q_Association] :=
    Replace[provider, {
        "PamyatNaroda" :> pamyatNarodaURL[q],
        "YandexArchive" :> yandexArchiveURL[q],
        "FindAGrave" :> findAGraveURL[q],
        _ -> Missing[]
    }]

linkSearch[provider_String, q_Association] :=
    Block[{url},
        url = providerURL[provider, q];
        If[ ! StringQ[url], Return[{}]];
        {resultRow[
            provider,
            Replace[genealogyFullName[q], "" :> Replace[Lookup[q, "Text", Missing[]], Except[_String] -> "?"]],
            Lookup[q, "BirthYear", Missing["NotAvailable"]],
            Lookup[q, "DeathYear", Missing["NotAvailable"]],
            Lookup[q, "Place", Missing["NotAvailable"]],
            "no public API: open this URL to run the search in a browser",
            url
        ]}
    ]

(* === dispatch === *)

providerSearch["WikiTree", q_Association, n_Integer] := wikiTreeSearch[q, n]
providerSearch["OpenList", q_Association, n_Integer] := openListSearch[q, n]
providerSearch["PermGenerations", q_Association, n_Integer] := permGenerationsSearch[q, n]
providerSearch["Wikidata", q_Association, n_Integer] := wikidataSearch[q, n]
providerSearch["OpenArchives", q_Association, n_Integer] := openArchivesSearch[q, n]
providerSearch["FamilySearch", q_Association, n_Integer] := familySearchSearch[q, n]
providerSearch["Geni", q_Association, n_Integer] := geniSearch[q, n]
providerSearch[p : ("PamyatNaroda" | "YandexArchive" | "FindAGrave"), q_Association, n_Integer] :=
    If[ TrueQ[$genealogyUseBrowser] && genealogyBrowserReadyQ[],
        browserSearch[p, q, n],
        linkSearch[p, q]
    ]
providerSearch[p_String, _Association, _Integer] := (Message[GenealogySearch::unknownProvider, p]; {})

Options[GenealogySearch] = {
    "Providers" -> Automatic,
    "MaxResults" -> 10,
    "IncludeLinks" -> True,
    "Browser" -> Automatic,
    "Detailed" -> True,
    "Variants" -> Automatic
}

(* Whether a provider whose hit list is a summary should follow each hit to its
   record card.  On for PermGenerations, where the card is where the parents
   and the archival citation live; it costs one extra request per row. *)
$genealogyPermDetail = True

(* Set for the duration of one GenealogySearch call.  False keeps the
   browser-class providers in link mode, which is what an offline run, a test
   and a documentation build all want. *)
$genealogyUseBrowser = True

resolveProviders[opts_List] :=
    Block[{requested, includeLinks},
        requested = OptionValue[GenealogySearch, opts, "Providers"];
        includeLinks = TrueQ[OptionValue[GenealogySearch, opts, "IncludeLinks"]];
        Replace[requested, {
            All :> Keys[$genealogyProviders],
            Automatic :> Select[
                Keys[$genealogyProviders],
                Replace[$genealogyProviders[#]["Class"], {
                    "Open" -> True,
                    "Credential" :> genealogyProviderAvailableQ[#],
                    (* A browser provider is kept even when the runner is
                       missing: it then contributes its search link, which is
                       what the class did before the runner existed. *)
                    "Browser" -> includeLinks,
                    _ -> False
                }] &
            ],
            p_String :> {p},
            l_List :> l,
            other_ :> (Message[GenealogySearch::unknownProvider, other]; {})
        }]
    ]

(* The provider table, with the availability each class actually has right
   now, so "why did FamilySearch return nothing" has a visible answer. *)
GenealogySearch["Providers"] :=
    Tabular @ KeyValueMap[
        {name, spec} |-> <|
            "Provider" -> name,
            "Class" -> spec["Class"],
            "Available" -> genealogyProviderAvailableQ[name],
            "Coverage" -> spec["Coverage"],
            "Site" -> spec["Site"]
        |>,
        $genealogyProviders
    ]

GenealogySearch[query : (_String | _Association), opts : OptionsPattern[]] :=
    Block[{q, queries, providers, n, rows, $genealogyUseBrowser = $genealogyUseBrowser,
           $genealogyPermDetail = $genealogyPermDetail},
        q = normalizeGenealogyQuery[query];
        providers = resolveProviders[{opts}];
        $genealogyUseBrowser = Replace[OptionValue["Browser"], {Automatic -> True, b_ :> TrueQ[b]}];
        $genealogyPermDetail = TrueQ[OptionValue["Detailed"]];
        n = Replace[OptionValue["MaxResults"], Except[_Integer ? Positive] -> 10];
        queries = genealogyQueryVariants[q, OptionValue["Variants"]];
        rows = Map[
            (* NOT wrapped in Quiet: each provider already quiets its own HTTP
               noise, and the messages that do get here are the ones the caller
               must see, above all "this archive refused, here is a link
               instead".  Swallowing that turns a refusal into an apparently
               empty result. *)
            p |-> Catenate @ Map[
                qv |-> Block[{res = providerSearch[p, qv, n]},
                    If[ res === $Failed,
                        Message[GenealogySearch::provider, p];
                        {},
                        Replace[res, Except[_List] -> {}]
                    ]
                ],
                queries
            ],
            providers
        ];
        (* Two spellings of one surname can return the same record, so the
           merged result is deduplicated on the whole row rather than on the
           name that found it. *)
        tabularOrEmpty[DeleteDuplicates @ Catenate[rows], $genealogyResultColumns]
    ]

GenealogySearch[ft_ ? FamilyTreeQ, spec_, opts : OptionsPattern[]] :=
    Block[{person = ft["Person", spec]},
        If[ ! AssociationQ[person], Return[person]];
        GenealogySearch[personToQuery[person], opts]
    ]

GenealogySearch[x_, opts : OptionsPattern[]] := (Message[GenealogySearch::badquery, x]; $Failed)

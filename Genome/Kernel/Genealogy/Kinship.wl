(* Kinship.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  See wl/GUIDE.md for style. *)

(* === naming a kinship ===
   Two stages, because the two halves are different problems.  First the tree
   is walked into a DESCRIPTOR - a structural statement of how two people are
   related, with no words in it - and then a descriptor is rendered into a
   phrase in one language.  Adding a language touches only the second half,
   and a bug in the walk cannot hide behind a plausible-looking word.

   The systems differ in more than vocabulary.  English names a collateral
   relation by cousin degree and removal ("second cousin once removed").
   Russian, and the Romance and Germanic languages, name it by the
   GENERATION the person sits in (brother / uncle / grandfather, nephew /
   grandson) and mark the collateral distance on that word - which is why a
   grandparent's brother is a "great-uncle" in English but a "двоюродный
   дедушка" (a cousin-grandfather) in Russian.  Both systems are implemented
   from the same two numbers, so neither is a translation of the other. *)

$kinshipLanguages = {"English", "Russian", "Spanish", "Portuguese", "Italian", "Latvian", "German", "French"}

$defaultKinshipLanguage = "English"

FamilyTree::badlang = "`1` is not one of the supported languages `2`; using `3`.";

kinshipLanguage[lang_String] /; MemberQ[$kinshipLanguages, lang] := lang
kinshipLanguage[Automatic] := $defaultKinshipLanguage
kinshipLanguage[lang_] := (
    Message[FamilyTree::badlang, lang, $kinshipLanguages, $defaultKinshipLanguage];
    $defaultKinshipLanguage
)

(* Pick the form a term takes for the sex of the person being named.  Every
   term in every language goes through here, so an unknown sex always has a
   neutral form to fall back to rather than guessing. *)
bySex[sex_, male_String, female_String, neutral_String] :=
    Replace[sex, {"Male" -> male, "Female" -> female, _ -> neutral}]

(* German builds one word out of the pieces, so only the first letter of the
   compound is capitalized: Urgro\:00dfvater, not UrGro\:00dfvater. *)
deCompound[parts__String] :=
    Block[{w = ToLowerCase @ StringJoin[parts]},
        ToUpperCase[StringTake[w, 1]] <> StringDrop[w, 1]
    ]

(* Repeat a language's "one generation further back" particle. *)
rep[s_String, n_Integer] := StringJoin @ ConstantArray[s, Max[n, 0]]

(* === direct line === *)

(* kinAncestor[lang, n, sex]: n generations up.  1 is a parent. *)
kinAncestor["English", 1, sex_] := bySex[sex, "father", "mother", "parent"]
kinAncestor["English", n_, sex_] := rep["great-", n - 2] <> bySex[sex, "grandfather", "grandmother", "grandparent"]
kinAncestor["Russian", 1, sex_] := bySex[sex, "\:043e\:0442\:0435\:0446", "\:043c\:0430\:0442\:044c", "\:0440\:043e\:0434\:0438\:0442\:0435\:043b\:044c"]
kinAncestor["Russian", n_, sex_] := rep["\:043f\:0440\:0430", n - 2] <> bySex[sex, "\:0434\:0435\:0434\:0443\:0448\:043a\:0430", "\:0431\:0430\:0431\:0443\:0448\:043a\:0430", "\:0434\:0435\:0434\:0443\:0448\:043a\:0430 \:0438\:043b\:0438 \:0431\:0430\:0431\:0443\:0448\:043a\:0430"]
kinAncestor["Spanish", 1, sex_] := bySex[sex, "padre", "madre", "progenitor"]
kinAncestor["Spanish", 2, sex_] := bySex[sex, "abuelo", "abuela", "abuelo"]
kinAncestor["Spanish", 3, sex_] := bySex[sex, "bisabuelo", "bisabuela", "bisabuelo"]
kinAncestor["Spanish", n_, sex_] := rep["tatara", n - 3] <> bySex[sex, "abuelo", "abuela", "abuelo"]
kinAncestor["Portuguese", 1, sex_] := bySex[sex, "pai", "m\[ATilde]e", "progenitor"]
kinAncestor["Portuguese", 2, sex_] := bySex[sex, "av\:00f4", "av\[OAcute]", "av\:00f4"]
kinAncestor["Portuguese", 3, sex_] := bySex[sex, "bisav\:00f4", "bisav\[OAcute]", "bisav\:00f4"]
kinAncestor["Portuguese", n_, sex_] := rep["tatara", n - 3] <> bySex[sex, "av\:00f4", "av\[OAcute]", "av\:00f4"]
kinAncestor["Italian", 1, sex_] := bySex[sex, "padre", "madre", "genitore"]
kinAncestor["Italian", 2, sex_] := bySex[sex, "nonno", "nonna", "nonno"]
kinAncestor["Italian", 3, sex_] := bySex[sex, "bisnonno", "bisnonna", "bisnonno"]
kinAncestor["Italian", n_, sex_] := rep["tris", n - 3] <> bySex[sex, "nonno", "nonna", "nonno"]
kinAncestor["Latvian", 1, sex_] := bySex[sex, "t\:0113vs", "m\:0101te", "vec\:0101ks"]
kinAncestor["Latvian", n_, sex_] := rep["vec", n - 1] <> bySex[sex, "t\:0113vs", "m\:0101mi\:0146a", "vec\:0101ks"]
kinAncestor["German", 1, sex_] := bySex[sex, "Vater", "Mutter", "Elternteil"]
kinAncestor["German", n_, sex_] := deCompound[rep["Ur", n - 2], bySex[sex, "Gro\:00dfvater", "Gro\:00dfmutter", "Gro\:00dfelternteil"]]
kinAncestor["French", 1, sex_] := bySex[sex, "p\[EGrave]re", "m\[EGrave]re", "parent"]
kinAncestor["French", n_, sex_] := rep["arri\[EGrave]re-", n - 2] <> bySex[sex, "grand-p\[EGrave]re", "grand-m\[EGrave]re", "grand-parent"]

(* kinDescendant[lang, n, sex]: n generations down.  1 is a child. *)
kinDescendant["English", 1, sex_] := bySex[sex, "son", "daughter", "child"]
kinDescendant["English", n_, sex_] := rep["great-", n - 2] <> bySex[sex, "grandson", "granddaughter", "grandchild"]
kinDescendant["Russian", 1, sex_] := bySex[sex, "\:0441\:044b\:043d", "\:0434\:043e\:0447\:044c", "\:0440\:0435\:0431\:0451\:043d\:043e\:043a"]
kinDescendant["Russian", n_, sex_] := rep["\:043f\:0440\:0430", n - 2] <> bySex[sex, "\:0432\:043d\:0443\:043a", "\:0432\:043d\:0443\:0447\:043a\:0430", "\:0432\:043d\:0443\:043a \:0438\:043b\:0438 \:0432\:043d\:0443\:0447\:043a\:0430"]
kinDescendant["Spanish", 1, sex_] := bySex[sex, "hijo", "hija", "hijo"]
kinDescendant["Spanish", 2, sex_] := bySex[sex, "nieto", "nieta", "nieto"]
kinDescendant["Spanish", 3, sex_] := bySex[sex, "bisnieto", "bisnieta", "bisnieto"]
kinDescendant["Spanish", n_, sex_] := rep["tatara", n - 3] <> bySex[sex, "nieto", "nieta", "nieto"]
kinDescendant["Portuguese", 1, sex_] := bySex[sex, "filho", "filha", "filho"]
kinDescendant["Portuguese", 2, sex_] := bySex[sex, "neto", "neta", "neto"]
kinDescendant["Portuguese", 3, sex_] := bySex[sex, "bisneto", "bisneta", "bisneto"]
kinDescendant["Portuguese", n_, sex_] := rep["tatara", n - 3] <> bySex[sex, "neto", "neta", "neto"]
kinDescendant["Italian", 1, sex_] := bySex[sex, "figlio", "figlia", "figlio"]
kinDescendant["Italian", 2, sex_] := bySex[sex, "nipote", "nipote", "nipote"]
kinDescendant["Italian", n_, sex_] := rep["tris", n - 3] <> If[ n === 3, "bis", ""] <> "nipote"
kinDescendant["Latvian", 1, sex_] := bySex[sex, "d\:0113ls", "meita", "b\:0113rns"]
kinDescendant["Latvian", n_, sex_] := rep["maz", n - 1] <> bySex[sex, "d\:0113ls", "meita", "b\:0113rns"]
kinDescendant["German", 1, sex_] := bySex[sex, "Sohn", "Tochter", "Kind"]
kinDescendant["German", n_, sex_] := deCompound[rep["Ur", n - 2], bySex[sex, "Enkel", "Enkelin", "Enkelkind"]]
kinDescendant["French", 1, sex_] := bySex[sex, "fils", "fille", "enfant"]
kinDescendant["French", n_, sex_] := rep["arri\[EGrave]re-", n - 2] <> bySex[sex, "petit-fils", "petite-fille", "petit-enfant"]

(* === collateral relations ===
   m   = Min[up, down], the collateral distance: 1 is the sibling line,
         2 the first-cousin line, 3 the second-cousin line.
   off = down - up, the generation the person sits in relative to the
         subject: 0 is the same generation, negative older, positive younger. *)

(* The base word, before any collateral marking: what a person that many
   generations away would be called if they were on the sibling line. *)
kinCollateralBase[lang_, off_, sex_] :=
    Which[
        off === 0, kinSibling[lang, sex],
        off === -1, kinPibling[lang, sex],
        off <= -2, kinAncestor[lang, -off, sex],
        off === 1, kinNibling[lang, sex],
        True, kinDescendant[lang, off, sex]
    ]

kinSibling["English", sex_] := bySex[sex, "brother", "sister", "sibling"]
kinSibling["Russian", sex_] := bySex[sex, "\:0431\:0440\:0430\:0442", "\:0441\:0435\:0441\:0442\:0440\:0430", "\:0431\:0440\:0430\:0442 \:0438\:043b\:0438 \:0441\:0435\:0441\:0442\:0440\:0430"]
kinSibling["Spanish", sex_] := bySex[sex, "hermano", "hermana", "hermano"]
kinSibling["Portuguese", sex_] := bySex[sex, "irm\[ATilde]o", "irm\[ATilde]", "irm\[ATilde]o"]
kinSibling["Italian", sex_] := bySex[sex, "fratello", "sorella", "fratello"]
kinSibling["Latvian", sex_] := bySex[sex, "br\:0101lis", "m\:0101sa", "br\:0101lis vai m\:0101sa"]
kinSibling["German", sex_] := bySex[sex, "Bruder", "Schwester", "Geschwister"]
kinSibling["French", sex_] := bySex[sex, "fr\:00e8re", "s\:0153ur", "fr\:00e8re ou s\:0153ur"]

kinPibling["English", sex_] := bySex[sex, "uncle", "aunt", "uncle or aunt"]
kinPibling["Russian", sex_] := bySex[sex, "\:0434\:044f\:0434\:044f", "\:0442\:0451\:0442\:044f", "\:0434\:044f\:0434\:044f \:0438\:043b\:0438 \:0442\:0451\:0442\:044f"]
kinPibling["Spanish", sex_] := bySex[sex, "t\[IAcute]o", "t\[IAcute]a", "t\[IAcute]o"]
kinPibling["Portuguese", sex_] := bySex[sex, "tio", "tia", "tio"]
kinPibling["Italian", sex_] := bySex[sex, "zio", "zia", "zio"]
kinPibling["Latvian", sex_] := bySex[sex, "t\:0113vocis", "tante", "t\:0113vocis vai tante"]
kinPibling["German", sex_] := bySex[sex, "Onkel", "Tante", "Onkel oder Tante"]
kinPibling["French", sex_] := bySex[sex, "oncle", "tante", "oncle ou tante"]

kinNibling["English", sex_] := bySex[sex, "nephew", "niece", "nephew or niece"]
kinNibling["Russian", sex_] := bySex[sex, "\:043f\:043b\:0435\:043c\:044f\:043d\:043d\:0438\:043a", "\:043f\:043b\:0435\:043c\:044f\:043d\:043d\:0438\:0446\:0430", "\:043f\:043b\:0435\:043c\:044f\:043d\:043d\:0438\:043a \:0438\:043b\:0438 \:043f\:043b\:0435\:043c\:044f\:043d\:043d\:0438\:0446\:0430"]
kinNibling["Spanish", sex_] := bySex[sex, "sobrino", "sobrina", "sobrino"]
kinNibling["Portuguese", sex_] := bySex[sex, "sobrinho", "sobrinha", "sobrinho"]
kinNibling["Italian", sex_] := bySex[sex, "nipote", "nipote", "nipote"]
kinNibling["Latvian", sex_] := bySex[sex, "br\:0101\:013cad\:0113ls", "br\:0101\:013cameita", "br\:0101\:013cab\:0113rns"]
kinNibling["German", sex_] := bySex[sex, "Neffe", "Nichte", "Neffe oder Nichte"]
kinNibling["French", sex_] := bySex[sex, "neveu", "ni\[EGrave]ce", "neveu ou ni\[EGrave]ce"]

(* English names a collateral relation by cousin degree and removal. *)
$ordinalWords = <|1 -> "first", 2 -> "second", 3 -> "third", 4 -> "fourth", 5 -> "fifth",
    6 -> "sixth", 7 -> "seventh", 8 -> "eighth", 9 -> "ninth", 10 -> "tenth"|>

ordinalWord[n_Integer] := Lookup[$ordinalWords, n, ToString[n] <> "th"]

removedPhrase[0] := ""
removedPhrase[1] := " once removed"
removedPhrase[2] := " twice removed"
removedPhrase[n_Integer] := " " <> ToString[n] <> " times removed"

kinCollateral["English", m_, off_, sex_] :=
    Which[
        m >= 2, ordinalWord[m - 1] <> " cousin" <> removedPhrase[Abs[off]],
        off === 0, kinSibling["English", sex],
        off === -1, kinPibling["English", sex],
        off <= -2, rep["great-", -off - 1] <> kinPibling["English", sex],
        off === 1, kinNibling["English", sex],
        True, rep["great-", off - 1] <> kinNibling["English", sex]
    ]

(* Russian marks the collateral distance on the generation word itself: a
   grandparent's brother is a cousin-grandfather, a parent's cousin a
   cousin-uncle.  The count is one less on the words that are already
   collateral - brother, uncle, nephew - and full on the direct-line words a
   collateral relative borrows, which is what forces the mark onto
   \:0434\:0435\:0434\:0443\:0448\:043a\:0430 and \:0432\:043d\:0443\:043a. *)
kinDegreeCount[m_, off_] := If[ Abs[off] <= 1, m - 1, m]

$ruDegreeAdjectives = <|
    2 -> {"\:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:0434\:0432\:043e\:044e\:0440\:043e\:0434\:043d\:0430\:044f"},
    3 -> {"\:0442\:0440\:043e\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:0442\:0440\:043e\:044e\:0440\:043e\:0434\:043d\:0430\:044f"},
    4 -> {"\:0447\:0435\:0442\:0432\:0435\:0440\:043e\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:0447\:0435\:0442\:0432\:0435\:0440\:043e\:044e\:0440\:043e\:0434\:043d\:0430\:044f"},
    5 -> {"\:043f\:044f\:0442\:0438\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:043f\:044f\:0442\:0438\:044e\:0440\:043e\:0434\:043d\:0430\:044f"},
    6 -> {"\:0448\:0435\:0441\:0442\:0438\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:0448\:0435\:0441\:0442\:0438\:044e\:0440\:043e\:0434\:043d\:0430\:044f"},
    7 -> {"\:0441\:0435\:043c\:0438\:044e\:0440\:043e\:0434\:043d\:044b\:0439", "\:0441\:0435\:043c\:0438\:044e\:0440\:043e\:0434\:043d\:0430\:044f"}
|>

kinCollateral["Russian", m_, off_, sex_] :=
    Block[{c = kinDegreeCount[m, off], adj},
        If[ c === 0, Return[kinCollateralBase["Russian", off, sex]]];
        adj = Lookup[$ruDegreeAdjectives, c + 1,
            {ToString[c + 1] <> "-\:044e\:0440\:043e\:0434\:043d\:044b\:0439", ToString[c + 1] <> "-\:044e\:0440\:043e\:0434\:043d\:0430\:044f"}];
        bySex[sex, First[adj], Last[adj], First[adj]] <> " " <> kinCollateralBase["Russian", off, sex]
    ]

(* A grandparent's sibling and a sibling's grandchild get a compound word of
   their own in the Romance and Germanic languages, not a marked grandparent:
   ti\:00f3 abuelo, prozio, Gro\:00dfonkel, grand-oncle. *)
kinGreatPibling["Spanish", k_, sex_] := bySex[sex, "t\[IAcute]o ", "t\[IAcute]a ", "t\[IAcute]o "] <> kinAncestor["Spanish", k, sex]
kinGreatPibling["Portuguese", k_, sex_] := bySex[sex, "tio-", "tia-", "tio-"] <> kinAncestor["Portuguese", k, sex]
kinGreatPibling["Italian", k_, sex_] := rep["pro", k - 1] <> bySex[sex, "zio", "zia", "zio"]
kinGreatPibling["German", k_, sex_] := deCompound[rep["Ur", k - 2], bySex[sex, "Gro\:00dfonkel", "Gro\:00dftante", "Gro\:00dfonkel"]]
kinGreatPibling["French", k_, sex_] := rep["arri\[EGrave]re-", k - 2] <> bySex[sex, "grand-oncle", "grand-tante", "grand-oncle"]
kinGreatPibling["Latvian", k_, sex_] := rep["vec", k - 1] <> bySex[sex, "vec\:0101ku br\:0101lis", "vec\:0101ku m\:0101sa", "vec\:0101ku br\:0101lis vai m\:0101sa"]

kinGreatNibling["Spanish", k_, sex_] := bySex[sex, "sobrino ", "sobrina ", "sobrino "] <> kinDescendant["Spanish", k, sex]
kinGreatNibling["Portuguese", k_, sex_] := bySex[sex, "sobrinho-", "sobrinha-", "sobrinho-"] <> kinDescendant["Portuguese", k, sex]
kinGreatNibling["Italian", k_, sex_] := rep["pro", k - 1] <> "nipote"
kinGreatNibling["German", k_, sex_] := deCompound[rep["Ur", k - 2], bySex[sex, "Gro\:00dfneffe", "Gro\:00dfnichte", "Gro\:00dfneffe"]]
kinGreatNibling["French", k_, sex_] := rep["arri\[EGrave]re-", k - 2] <> bySex[sex, "petit-neveu", "petite-ni\[EGrave]ce", "petit-neveu"]
kinGreatNibling["Latvian", k_, sex_] := bySex[sex, "br\:0101\:013ca ", "m\:0101sas ", "br\:0101\:013ca "] <> kinDescendant["Latvian", k, sex]

(* The cousin ordinal these languages use runs one behind the Russian
   adjective: a first cousin is a primo HERMANO, and primo segundo is already
   a second cousin.  On an uncle or a nephew the ordinal is the full count,
   which is what makes a parent's first cousin a t\:00edo segundo. *)
$kinOrdinals = <|
    "Spanish" -> <|1 -> {"hermano", "hermana"}, 2 -> {"segundo", "segunda"}, 3 -> {"tercero", "tercera"}, 4 -> {"cuarto", "cuarta"}, 5 -> {"quinto", "quinta"}|>,
    "Portuguese" -> <|1 -> {"", ""}, 2 -> {"em segundo grau", "em segundo grau"}, 3 -> {"em terceiro grau", "em terceiro grau"}, 4 -> {"em quarto grau", "em quarto grau"}, 5 -> {"em quinto grau", "em quinto grau"}|>,
    "Italian" -> <|1 -> {"primo", "prima"}, 2 -> {"secondo", "seconda"}, 3 -> {"terzo", "terza"}, 4 -> {"quarto", "quarta"}, 5 -> {"quinto", "quinta"}|>,
    "French" -> <|1 -> {"germain", "germaine"}, 2 -> {"au deuxi\[EGrave]me degr\[EAcute]", "au deuxi\[EGrave]me degr\[EAcute]"}, 3 -> {"au troisi\[EGrave]me degr\[EAcute]", "au troisi\[EGrave]me degr\[EAcute]"}, 4 -> {"au quatri\[EGrave]me degr\[EAcute]", "au quatri\[EGrave]me degr\[EAcute]"}, 5 -> {"au cinqui\[EGrave]me degr\[EAcute]", "au cinqui\[EGrave]me degr\[EAcute]"}|>,
    "German" -> <|1 -> {"", ""}, 2 -> {"zweiten Grades", "zweiten Grades"}, 3 -> {"dritten Grades", "dritten Grades"}, 4 -> {"vierten Grades", "vierten Grades"}, 5 -> {"f\[UDoubleDot]nften Grades", "f\[UDoubleDot]nften Grades"}|>,
    "Latvian" -> <|1 -> {"", ""}, 2 -> {"otr\:0101s pak\:0101pes", "otr\:0101s pak\:0101pes"}, 3 -> {"tre\:0161\:0101s pak\:0101pes", "tre\:0161\:0101s pak\:0101pes"}, 4 -> {"ceturt\:0101s pak\:0101pes", "ceturt\:0101s pak\:0101pes"}, 5 -> {"piekt\:0101s pak\:0101pes", "piekt\:0101s pak\:0101pes"}|>
|>

kinOrdinal[lang_, k_, sex_] :=
    Block[{forms = Lookup[$kinOrdinals[lang], k, {ToString[k], ToString[k]}]},
        bySex[sex, First[forms], Last[forms], First[forms]]
    ]

kinCousin["Spanish", sex_] := bySex[sex, "primo", "prima", "primo"]
kinCousin["Portuguese", sex_] := bySex[sex, "primo", "prima", "primo"]
kinCousin["Italian", sex_] := bySex[sex, "cugino", "cugina", "cugino"]
kinCousin["French", sex_] := bySex[sex, "cousin", "cousine", "cousin"]
kinCousin["German", sex_] := bySex[sex, "Cousin", "Cousine", "Cousin"]
kinCousin["Latvian", sex_] := bySex[sex, "br\:0101l\:0113ns", "m\:0101s\:012bca", "br\:0101l\:0113ns vai m\:0101s\:012bca"]

kinCollateral[lang_, m_, off_, sex_] :=
    Which[
        m === 1 && off === 0, kinSibling[lang, sex],
        m === 1 && off === -1, kinPibling[lang, sex],
        m === 1 && off <= -2, kinGreatPibling[lang, -off, sex],
        m === 1 && off === 1, kinNibling[lang, sex],
        m === 1, kinGreatNibling[lang, off, sex],
        True,
            Block[{base, ordinal},
                base = If[ off === 0, kinCousin[lang, sex], kinCollateralBase[lang, off, sex]];
                ordinal = kinOrdinal[lang, If[ off === 0, m - 1, m], sex];
                Which[
                    ordinal === "", base,
                    lang === "Latvian", ordinal <> " " <> base,
                    True, base <> " " <> ordinal
                ]
            ]
    ]

(* === the line: through the father or through the mother === *)

kinLine["English", line_, phrase_, _] := If[ line === "Paternal", "paternal ", "maternal "] <> phrase
kinLine["Russian", line_, phrase_, _] := phrase <> If[ line === "Paternal", " \:043f\:043e \:043e\:0442\:0446\:0443", " \:043f\:043e \:043c\:0430\:0442\:0435\:0440\:0438"]
kinLine["Spanish", line_, phrase_, sex_] := phrase <> If[ line === "Paternal", bySex[sex, " paterno", " paterna", " paterno"], bySex[sex, " materno", " materna", " materno"]]
kinLine["Portuguese", line_, phrase_, sex_] := phrase <> If[ line === "Paternal", bySex[sex, " paterno", " paterna", " paterno"], bySex[sex, " materno", " materna", " materno"]]
kinLine["Italian", line_, phrase_, sex_] := phrase <> If[ line === "Paternal", bySex[sex, " paterno", " paterna", " paterno"], bySex[sex, " materno", " materna", " materno"]]
kinLine["French", line_, phrase_, sex_] := phrase <> If[ line === "Paternal", bySex[sex, " paternel", " paternelle", " paternel"], bySex[sex, " maternel", " maternelle", " maternel"]]
kinLine["German", line_, phrase_, _] := phrase <> If[ line === "Paternal", " v\[ADoubleDot]terlicherseits", " m\[UDoubleDot]tterlicherseits"]
kinLine["Latvian", line_, phrase_, _] := phrase <> If[ line === "Paternal", " no t\:0113va puses", " no m\:0101tes puses"]

(* === marriage, step and in-law === *)

kinSpouse["English", sex_] := bySex[sex, "husband", "wife", "spouse"]
kinSpouse["Russian", sex_] := bySex[sex, "\:043c\:0443\:0436", "\:0436\:0435\:043d\:0430", "\:0441\:0443\:043f\:0440\:0443\:0433"]
kinSpouse["Spanish", sex_] := bySex[sex, "marido", "esposa", "c\[OAcute]nyuge"]
kinSpouse["Portuguese", sex_] := bySex[sex, "marido", "esposa", "c\[OAcute]njuge"]
kinSpouse["Italian", sex_] := bySex[sex, "marito", "moglie", "coniuge"]
kinSpouse["Latvian", sex_] := bySex[sex, "v\:012brs", "sieva", "laul\:0101tais"]
kinSpouse["German", sex_] := bySex[sex, "Ehemann", "Ehefrau", "Ehepartner"]
kinSpouse["French", sex_] := bySex[sex, "mari", "\[EAcute]pouse", "conjoint"]

(* A step-parent is the spouse of a parent who is not a parent; a step-child
   the mirror of it. *)
kinStep["English", "Parent", sex_] := bySex[sex, "stepfather", "stepmother", "step-parent"]
kinStep["English", "Child", sex_] := bySex[sex, "stepson", "stepdaughter", "stepchild"]
kinStep["English", "Sibling", sex_] := bySex[sex, "stepbrother", "stepsister", "step-sibling"]
kinStep["Russian", "Parent", sex_] := bySex[sex, "\:043e\:0442\:0447\:0438\:043c", "\:043c\:0430\:0447\:0435\:0445\:0430", "\:043e\:0442\:0447\:0438\:043c \:0438\:043b\:0438 \:043c\:0430\:0447\:0435\:0445\:0430"]
kinStep["Russian", "Child", sex_] := bySex[sex, "\:043f\:0430\:0441\:044b\:043d\:043e\:043a", "\:043f\:0430\:0434\:0447\:0435\:0440\:0438\:0446\:0430", "\:043f\:0430\:0441\:044b\:043d\:043e\:043a \:0438\:043b\:0438 \:043f\:0430\:0434\:0447\:0435\:0440\:0438\:0446\:0430"]
kinStep["Russian", "Sibling", sex_] := bySex[sex, "\:0441\:0432\:043e\:0434\:043d\:044b\:0439 \:0431\:0440\:0430\:0442", "\:0441\:0432\:043e\:0434\:043d\:0430\:044f \:0441\:0435\:0441\:0442\:0440\:0430", "\:0441\:0432\:043e\:0434\:043d\:044b\:0439 \:0431\:0440\:0430\:0442 \:0438\:043b\:0438 \:0441\:0435\:0441\:0442\:0440\:0430"]
kinStep["Spanish", "Parent", sex_] := bySex[sex, "padrastro", "madrastra", "padrastro"]
kinStep["Spanish", "Child", sex_] := bySex[sex, "hijastro", "hijastra", "hijastro"]
kinStep["Spanish", "Sibling", sex_] := bySex[sex, "hermanastro", "hermanastra", "hermanastro"]
kinStep["Portuguese", "Parent", sex_] := bySex[sex, "padrasto", "madrasta", "padrasto"]
kinStep["Portuguese", "Child", sex_] := bySex[sex, "enteado", "enteada", "enteado"]
kinStep["Portuguese", "Sibling", sex_] := bySex[sex, "meio-irm\[ATilde]o", "meia-irm\[ATilde]", "meio-irm\[ATilde]o"]
kinStep["Italian", "Parent", sex_] := bySex[sex, "patrigno", "matrigna", "patrigno"]
kinStep["Italian", "Child", sex_] := bySex[sex, "figliastro", "figliastra", "figliastro"]
kinStep["Italian", "Sibling", sex_] := bySex[sex, "fratellastro", "sorellastra", "fratellastro"]
kinStep["Latvian", "Parent", sex_] := bySex[sex, "pat\:0113vs", "pam\:0101te", "pat\:0113vs vai pam\:0101te"]
kinStep["Latvian", "Child", sex_] := bySex[sex, "pad\:0113ls", "pameita", "pad\:0113ls vai pameita"]
kinStep["Latvian", "Sibling", sex_] := bySex[sex, "pusbr\:0101lis", "pusm\:0101sa", "pusbr\:0101lis vai pusm\:0101sa"]
kinStep["German", "Parent", sex_] := bySex[sex, "Stiefvater", "Stiefmutter", "Stiefelternteil"]
kinStep["German", "Child", sex_] := bySex[sex, "Stiefsohn", "Stieftochter", "Stiefkind"]
kinStep["German", "Sibling", sex_] := bySex[sex, "Stiefbruder", "Stiefschwester", "Stiefgeschwister"]
kinStep["French", "Parent", sex_] := bySex[sex, "beau-p\[EGrave]re", "belle-m\[EGrave]re", "beau-parent"]
kinStep["French", "Child", sex_] := bySex[sex, "beau-fils", "belle-fille", "bel enfant"]
kinStep["French", "Sibling", sex_] := bySex[sex, "demi-fr\:00e8re", "demi-s\:0153ur", "demi-fr\:00e8re ou demi-s\:0153ur"]

(* Half-siblings share one parent.  Russian distinguishes which one:
   \:0435\:0434\:0438\:043d\:043e\:043a\:0440\:043e\:0432\:043d\:044b\:0439 for the same father, \:0435\:0434\:0438\:043d\:043e\:0443\:0442\:0440\:043e\:0431\:043d\:044b\:0439 for the same mother. *)
kinHalfSibling["Russian", line_, sex_] :=
    If[ line === "Paternal",
        bySex[sex, "\:0435\:0434\:0438\:043d\:043e\:043a\:0440\:043e\:0432\:043d\:044b\:0439 \:0431\:0440\:0430\:0442", "\:0435\:0434\:0438\:043d\:043e\:043a\:0440\:043e\:0432\:043d\:0430\:044f \:0441\:0435\:0441\:0442\:0440\:0430", "\:0435\:0434\:0438\:043d\:043e\:043a\:0440\:043e\:0432\:043d\:044b\:0439 \:0431\:0440\:0430\:0442 \:0438\:043b\:0438 \:0441\:0435\:0441\:0442\:0440\:0430"],
        bySex[sex, "\:0435\:0434\:0438\:043d\:043e\:0443\:0442\:0440\:043e\:0431\:043d\:044b\:0439 \:0431\:0440\:0430\:0442", "\:0435\:0434\:0438\:043d\:043e\:0443\:0442\:0440\:043e\:0431\:043d\:0430\:044f \:0441\:0435\:0441\:0442\:0440\:0430", "\:0435\:0434\:0438\:043d\:043e\:0443\:0442\:0440\:043e\:0431\:043d\:044b\:0439 \:0431\:0440\:0430\:0442 \:0438\:043b\:0438 \:0441\:0435\:0441\:0442\:0440\:0430"]
    ]
kinHalfSibling["English", _, sex_] := bySex[sex, "half-brother", "half-sister", "half-sibling"]
kinHalfSibling["Spanish", _, sex_] := bySex[sex, "medio hermano", "media hermana", "medio hermano"]
kinHalfSibling["Portuguese", _, sex_] := bySex[sex, "meio-irm\[ATilde]o", "meia-irm\[ATilde]", "meio-irm\[ATilde]o"]
kinHalfSibling["Italian", _, sex_] := bySex[sex, "fratellastro", "sorellastra", "fratellastro"]
kinHalfSibling["Latvian", _, sex_] := bySex[sex, "pusbr\:0101lis", "pusm\:0101sa", "pusbr\:0101lis vai pusm\:0101sa"]
kinHalfSibling["German", _, sex_] := bySex[sex, "Halbbruder", "Halbschwester", "Halbgeschwister"]
kinHalfSibling["French", _, sex_] := bySex[sex, "demi-fr\:00e8re", "demi-s\:0153ur", "demi-fr\:00e8re ou demi-s\:0153ur"]

(* In-laws.  Russian keeps a separate word for every position, which is the
   whole point of naming them at all: \:0442\:0435\:0441\:0442\:044c is a wife's father and \:0441\:0432\:0451\:043a\:043e\:0440 a
   husband's, and the two are never interchangeable.  "via" is the sex of the
   spouse the relation runs through. *)
kinInLaw["Russian", "Parent", sex_, via_] :=
    If[ via === "Female",
        bySex[sex, "\:0442\:0435\:0441\:0442\:044c", "\:0442\:0451\:0449\:0430", "\:0442\:0435\:0441\:0442\:044c \:0438\:043b\:0438 \:0442\:0451\:0449\:0430"],
        bySex[sex, "\:0441\:0432\:0451\:043a\:043e\:0440", "\:0441\:0432\:0435\:043a\:0440\:043e\:0432\:044c", "\:0441\:0432\:0451\:043a\:043e\:0440 \:0438\:043b\:0438 \:0441\:0432\:0435\:043a\:0440\:043e\:0432\:044c"]
    ]
kinInLaw["Russian", "Child", sex_, _] := bySex[sex, "\:0437\:044f\:0442\:044c", "\:043d\:0435\:0432\:0435\:0441\:0442\:043a\:0430", "\:0437\:044f\:0442\:044c \:0438\:043b\:0438 \:043d\:0435\:0432\:0435\:0441\:0442\:043a\:0430"]
kinInLaw["Russian", "Sibling", sex_, via_] :=
    If[ via === "Female",
        bySex[sex, "\:0448\:0443\:0440\:0438\:043d", "\:0441\:0432\:043e\:044f\:0447\:0435\:043d\:0438\:0446\:0430", "\:0448\:0443\:0440\:0438\:043d \:0438\:043b\:0438 \:0441\:0432\:043e\:044f\:0447\:0435\:043d\:0438\:0446\:0430"],
        bySex[sex, "\:0434\:0435\:0432\:0435\:0440\:044c", "\:0437\:043e\:043b\:043e\:0432\:043a\:0430", "\:0434\:0435\:0432\:0435\:0440\:044c \:0438\:043b\:0438 \:0437\:043e\:043b\:043e\:0432\:043a\:0430"]
    ]
kinInLaw["English", "Parent", sex_, _] := bySex[sex, "father-in-law", "mother-in-law", "parent-in-law"]
kinInLaw["English", "Child", sex_, _] := bySex[sex, "son-in-law", "daughter-in-law", "child-in-law"]
kinInLaw["English", "Sibling", sex_, _] := bySex[sex, "brother-in-law", "sister-in-law", "sibling-in-law"]
kinInLaw["Spanish", "Parent", sex_, _] := bySex[sex, "suegro", "suegra", "suegro"]
kinInLaw["Spanish", "Child", sex_, _] := bySex[sex, "yerno", "nuera", "yerno"]
kinInLaw["Spanish", "Sibling", sex_, _] := bySex[sex, "cu\[NTilde]ado", "cu\[NTilde]ada", "cu\[NTilde]ado"]
kinInLaw["Portuguese", "Parent", sex_, _] := bySex[sex, "sogro", "sogra", "sogro"]
kinInLaw["Portuguese", "Child", sex_, _] := bySex[sex, "genro", "nora", "genro"]
kinInLaw["Portuguese", "Sibling", sex_, _] := bySex[sex, "cunhado", "cunhada", "cunhado"]
kinInLaw["Italian", "Parent", sex_, _] := bySex[sex, "suocero", "suocera", "suocero"]
kinInLaw["Italian", "Child", sex_, _] := bySex[sex, "genero", "nuora", "genero"]
kinInLaw["Italian", "Sibling", sex_, _] := bySex[sex, "cognato", "cognata", "cognato"]
kinInLaw["Latvian", "Parent", sex_, via_] :=
    If[ via === "Female",
        bySex[sex, "sievast\:0113vs", "sievasm\:0101te", "sievas vec\:0101ki"],
        bySex[sex, "v\:012brat\:0113vs", "v\:012bram\:0101te", "v\:012bra vec\:0101ki"]
    ]
kinInLaw["Latvian", "Child", sex_, _] := bySex[sex, "znots", "vedekla", "znots vai vedekla"]
kinInLaw["Latvian", "Sibling", sex_, _] := bySex[sex, "svainis", "svaine", "svainis vai svaine"]
kinInLaw["German", "Parent", sex_, _] := bySex[sex, "Schwiegervater", "Schwiegermutter", "Schwiegerelternteil"]
kinInLaw["German", "Child", sex_, _] := bySex[sex, "Schwiegersohn", "Schwiegertochter", "Schwiegerkind"]
kinInLaw["German", "Sibling", sex_, _] := bySex[sex, "Schwager", "Schw\[ADoubleDot]gerin", "Schwager oder Schw\[ADoubleDot]gerin"]
kinInLaw["French", "Parent", sex_, _] := bySex[sex, "beau-p\[EGrave]re", "belle-m\[EGrave]re", "beau-parent"]
kinInLaw["French", "Child", sex_, _] := bySex[sex, "gendre", "belle-fille", "gendre ou belle-fille"]
kinInLaw["French", "Sibling", sex_, _] := bySex[sex, "beau-fr\:00e8re", "belle-s\:0153ur", "beau-fr\:00e8re ou belle-s\:0153ur"]

(* The generic affinal case, for anything the language has no single word
   for: the spouse of a named relative. *)
kinSpouseOf["English", rel_, sex_] := rel <> "'s " <> kinSpouse["English", sex]
kinSpouseOf["Russian", rel_, sex_] := kinSpouse["Russian", sex] <> " (" <> rel <> ")"
kinSpouseOf[lang_, rel_, sex_] := kinSpouse[lang, sex] <> " (" <> rel <> ")"

kinUnrelated["English"] = "unrelated"
kinUnrelated["Russian"] = "\:043d\:0435 \:0440\:043e\:0434\:0441\:0442\:0432\:0435\:043d\:043d\:0438\:043a"
kinUnrelated["Spanish"] = "sin parentesco"
kinUnrelated["Portuguese"] = "sem parentesco"
kinUnrelated["Italian"] = "non imparentato"
kinUnrelated["Latvian"] = "nav radinieks"
kinUnrelated["German"] = "nicht verwandt"
kinUnrelated["French"] = "sans lien de parent\[EAcute]"

kinSelf["English"] = "self"
kinSelf["Russian"] = "\:044d\:0442\:043e \:044f"
kinSelf["Spanish"] = "yo"
kinSelf["Portuguese"] = "eu"
kinSelf["Italian"] = "io"
kinSelf["Latvian"] = "es"
kinSelf["German"] = "ich"
kinSelf["French"] = "moi"

(* The life-years line under a card, which is prose too. *)
kinBorn["English"] = "b. "
kinBorn["Russian"] = "\:0440. "
kinBorn["Spanish"] = "n. "
kinBorn["Portuguese"] = "n. "
kinBorn["Italian"] = "n. "
kinBorn["Latvian"] = "dz. "
kinBorn["German"] = "geb. "
kinBorn["French"] = "n\[EAcute] "
kinDied["English"] = "d. "
kinDied["Russian"] = "\:0443\:043c. "
kinDied["Spanish"] = "f. "
kinDied["Portuguese"] = "f. "
kinDied["Italian"] = "m. "
kinDied["Latvian"] = "mir. "
kinDied["German"] = "gest. "
kinDied["French"] = "d\[EAcute]c. "


(* The words the picture itself needs, beyond the kinship terms. *)
kinNoName["English"] = "no name"
kinNoName["Russian"] = "\:0431\:0435\:0437 \:0438\:043c\:0435\:043d\:0438"
kinNoName["Spanish"] = "sin nombre"
kinNoName["Portuguese"] = "sem nome"
kinNoName["Italian"] = "senza nome"
kinNoName["Latvian"] = "bez v\:0101rda"
kinNoName["German"] = "ohne Namen"
kinNoName["French"] = "sans nom"

kinSlotFather["English"] = "father"
kinSlotFather["Russian"] = "\:043e\:0442\:0435\:0446"
kinSlotFather["Spanish"] = "padre"
kinSlotFather["Portuguese"] = "pai"
kinSlotFather["Italian"] = "padre"
kinSlotFather["Latvian"] = "t\:0113vs"
kinSlotFather["German"] = "Vater"
kinSlotFather["French"] = "p\:00e8re"

kinSlotMother["English"] = "mother"
kinSlotMother["Russian"] = "\:043c\:0430\:0442\:044c"
kinSlotMother["Spanish"] = "madre"
kinSlotMother["Portuguese"] = "m\:00e3e"
kinSlotMother["Italian"] = "madre"
kinSlotMother["Latvian"] = "m\:0101te"
kinSlotMother["German"] = "Mutter"
kinSlotMother["French"] = "m\:00e8re"

(* === the descriptor: walking the tree === *)

(* Which of the subject's parents the relation runs through, when it runs
   through exactly one of them. *)
kinshipLine[a_Association, from_String, to_String] :=
    Block[{father, mother, viaFather, viaMother},
        {father, mother} = fatherMother[a, from];
        viaFather = StringQ[father] && (father === to || KeyExistsQ[ancestorDistances[a, father, 40], to] ||
            MemberQ[Keys @ descendantDistances[a, father, 40], to]);
        viaMother = StringQ[mother] && (mother === to || KeyExistsQ[ancestorDistances[a, mother, 40], to] ||
            MemberQ[Keys @ descendantDistances[a, mother, 40], to]);
        Which[
            viaFather && ! viaMother, "Paternal",
            viaMother && ! viaFather, "Maternal",
            True, Missing["NotAvailable"]
        ]
    ]

(* A collateral relative's line: the side of the family the common ancestor
   sits on. *)
kinshipLineVia[a_Association, from_String, ancestor_String] :=
    Block[{father, mother, inFather, inMother},
        {father, mother} = fatherMother[a, from];
        inFather = StringQ[father] && (father === ancestor || KeyExistsQ[ancestorDistances[a, father, 40], ancestor]);
        inMother = StringQ[mother] && (mother === ancestor || KeyExistsQ[ancestorDistances[a, mother, 40], ancestor]);
        Which[
            inFather && ! inMother, "Paternal",
            inMother && ! inFather, "Maternal",
            True, Missing["NotAvailable"]
        ]
    ]

(* The blood half, which never recurses: self, a line up, a line down, a
   collateral branch, or nothing.  Keeping it separate from the affinal half
   is not tidiness - the affinal half probes through spouses, and letting it
   probe through itself makes two people who are related only by marriage
   ask each other the same question forever. *)
kinshipBlood[a_Association, from_String, to_String] :=
    Block[{sex, fromAnc, toAnc, common, best, up, down, fromParents, toParents, shared},
        sex = Lookup[a["People"][to], "Sex", Missing[]];
        If[ from === to, Return[<|"Kind" -> "Self", "Sex" -> sex|>]];
        fromAnc = Prepend[ancestorDistances[a, from, 40], from -> 0];
        toAnc = Prepend[ancestorDistances[a, to, 40], to -> 0];
        common = Keys @ KeyTake[fromAnc, Keys[toAnc]];
        If[ common === {}, Return[Missing["NotRelated"]]];
        best = First @ MinimalBy[common, {fromAnc[#] + toAnc[#], Max[fromAnc[#], toAnc[#]]} &, 1];
        up = fromAnc[best];
        down = toAnc[best];
        Which[
            up === 0, <|"Kind" -> "Descendant", "Down" -> down, "Sex" -> sex|>,
            down === 0,
                <|"Kind" -> "Ancestor", "Up" -> up, "Sex" -> sex,
                  "Line" -> If[ up >= 2, kinshipLine[a, from, to], Missing["NotAvailable"]]|>,
            True,
                fromParents = Sort @ parentIDs[a, from];
                toParents = Sort @ parentIDs[a, to];
                shared = Intersection[fromParents, toParents];
                If[ up === 1 && down === 1 && Length[shared] === 1 &&
                        (Length[fromParents] > 1 || Length[toParents] > 1),
                    <|"Kind" -> "HalfSibling", "Sex" -> sex, "Line" -> kinshipLineVia[a, from, First[shared]]|>,
                    <|
                        "Kind" -> "Collateral", "Up" -> up, "Down" -> down,
                        "Degree" -> Min[up, down], "Offset" -> down - up, "Sex" -> sex,
                        "Line" -> If[ up >= 2, kinshipLineVia[a, from, best], Missing["NotAvailable"]]
                    |>
                ]
        ]
    ]

kinshipDescriptor[a_Association, from_String, to_String] :=
    Block[{sex, blood, stepParent, stepChild, inLaw, viaSpouse},
        sex = Lookup[a["People"][to], "Sex", Missing[]];
        If[ from === to, Return[<|"Kind" -> "Self", "Sex" -> sex|>]];
        (* marriage first: a spouse is not a blood relation and outranks one *)
        If[ MemberQ[spouseIDs[a, from], to], Return[<|"Kind" -> "Spouse", "Sex" -> sex|>]];
        blood = kinshipBlood[a, from, to];
        If[ AssociationQ[blood], Return[blood]];
        (* step relations: a parent's spouse who is not a parent, and its mirror *)
        stepParent = AnyTrue[parentIDs[a, from], MemberQ[spouseIDs[a, #], to] &] && ! MemberQ[parentIDs[a, from], to];
        If[ stepParent, Return[<|"Kind" -> "StepParent", "Sex" -> sex|>]];
        stepChild = AnyTrue[parentIDs[a, to], MemberQ[spouseIDs[a, #], from] &] && ! MemberQ[parentIDs[a, to], from];
        If[ stepChild, Return[<|"Kind" -> "StepChild", "Sex" -> sex|>]];
        If[ AnyTrue[parentIDs[a, from], p |-> AnyTrue[parentIDs[a, to], q |-> MemberQ[spouseIDs[a, p], q]]],
            Return[<|"Kind" -> "StepSibling", "Sex" -> sex|>]
        ];
        (* a blood relative of the subject's spouse *)
        inLaw = SelectFirst[
            Map[
                s |-> Block[{d = kinshipBlood[a, s, to]},
                    If[ AssociationQ[d] && d["Kind"] =!= "Self", <|"Spouse" -> s, "Descriptor" -> d|>, Missing[]]
                ],
                spouseIDs[a, from]
            ],
            AssociationQ,
            Missing[]
        ];
        If[ AssociationQ[inLaw],
            Block[{d = inLaw["Descriptor"], viaSex = Lookup[a["People"][inLaw["Spouse"]], "Sex", Missing[]]},
                Return @ Which[
                    d["Kind"] === "Ancestor" && d["Up"] === 1, <|"Kind" -> "InLawParent", "Sex" -> sex, "Via" -> viaSex|>,
                    d["Kind"] === "HalfSibling" || (d["Kind"] === "Collateral" && d["Up"] === 1 && d["Down"] === 1),
                        <|"Kind" -> "InLawSibling", "Sex" -> sex, "Via" -> viaSex|>,
                    True, <|"Kind" -> "OfSpouse", "Sex" -> sex, "Through" -> d, "Via" -> viaSex|>
                ]
            ]
        ];
        (* the spouse of a blood relative *)
        viaSpouse = SelectFirst[
            Map[
                s |-> Block[{d = kinshipBlood[a, from, s]},
                    If[ AssociationQ[d] && d["Kind"] =!= "Self", <|"Relative" -> s, "Descriptor" -> d|>, Missing[]]
                ],
                spouseIDs[a, to]
            ],
            AssociationQ,
            Missing[]
        ];
        If[ AssociationQ[viaSpouse],
            Block[{d = viaSpouse["Descriptor"]},
                Return @ Which[
                    d["Kind"] === "Descendant" && d["Down"] === 1, <|"Kind" -> "InLawChild", "Sex" -> sex|>,
                    d["Kind"] === "Collateral" && d["Up"] === 1 && d["Down"] === 1,
                        <|"Kind" -> "InLawSibling", "Sex" -> sex, "Via" -> Missing["NotAvailable"]|>,
                    True, <|"Kind" -> "SpouseOf", "Sex" -> sex, "Through" -> d|>
                ]
            ]
        ];
        <|"Kind" -> "Unrelated", "Sex" -> sex|>
    ]

(* === the descriptor, rendered === *)

kinshipPhrase[desc_Association, lang_String] :=
    Block[{sex = Lookup[desc, "Sex", Missing[]], line = Lookup[desc, "Line", Missing[]], phrase},
        phrase = Switch[desc["Kind"],
            "Self", kinSelf[lang],
            "Ancestor", kinAncestor[lang, desc["Up"], sex],
            "Descendant", kinDescendant[lang, desc["Down"], sex],
            "HalfSibling", kinHalfSibling[lang, line, sex],
            "Collateral", kinCollateral[lang, desc["Degree"], desc["Offset"], sex],
            "Spouse", kinSpouse[lang, sex],
            "StepParent", kinStep[lang, "Parent", sex],
            "StepChild", kinStep[lang, "Child", sex],
            "StepSibling", kinStep[lang, "Sibling", sex],
            "InLawParent", kinInLaw[lang, "Parent", sex, Lookup[desc, "Via", Missing[]]],
            "InLawChild", kinInLaw[lang, "Child", sex, Missing[]],
            "InLawSibling", kinInLaw[lang, "Sibling", sex, Lookup[desc, "Via", Missing[]]],
            "SpouseOf" | "OfSpouse", kinSpouseOf[lang, kinshipPhrase[desc["Through"], lang], sex],
            _, kinUnrelated[lang]
        ];
        (* the line is worth naming only where the language names it, and
           only where the relation has two sides to tell apart *)
        If[ MemberQ[{"Ancestor", "Collateral", "HalfSibling"}, desc["Kind"]] && StringQ[line] &&
                ! (desc["Kind"] === "HalfSibling" && lang === "Russian"),
            kinLine[lang, line, phrase, sex],
            phrase
        ]
    ]

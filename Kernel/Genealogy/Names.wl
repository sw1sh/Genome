(* Names.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  See wl/GUIDE.md for style. *)

(* === transliterating a name ===
   A pedigree read from a Russian service is written in Cyrillic, and the
   archives, journals and DNA-match lists it has to be compared against are
   written in Latin.  The built-in Transliterate is no use for this: it maps
   by stripping diacritics, so \:0429\:0435\:0440\:0431\:0430\:043a\:043e\:0432 \:042e\:0440\:0438\:0439 comes back as "Serbakov Urij"
   with the \:0448, \:0436 and \:044e distinctions simply gone, which is unsearchable and
   unpronounceable.  These are the two standards a genealogist actually
   meets:

     "BGN"       BGN/PCGN, the romanization used in English-language atlases
                 and by most archives that publish in Latin script.  \:0410\:043d\:0434\:0440\:0435\:0439
                 becomes Andrey, \:0429\:0435\:0440\:0431\:0430\:043a\:043e\:0432 Shcherbakov.  The readable one,
                 and the default.
     "Passport"  ICAO Doc 9303, the standard on a Russian passport since
                 2014, and therefore the spelling on modern documents.
                 \:0410\:043d\:0434\:0440\:0435\:0439 becomes Andrei, \:042e\:0440\:0438\:0439 Iurii.
     "Scientific" the scholarly ISO 9 transliteration, through the built-in
                 Transliterate, for citing a source rather than searching.

   Ukrainian and Belarusian letters are included, since a tree from the
   region routinely carries them. *)

$transliterationSchemes = {"BGN", "Passport", "Scientific"}

$bgnMap = <|
    "\:0430" -> "a", "\:0431" -> "b", "\:0432" -> "v", "\:0433" -> "g", "\:0434" -> "d", "\:0435" -> "e", "\:0451" -> "yo",
    "\:0436" -> "zh", "\:0437" -> "z", "\:0438" -> "i", "\:0439" -> "y", "\:043a" -> "k", "\:043b" -> "l", "\:043c" -> "m",
    "\:043d" -> "n", "\:043e" -> "o", "\:043f" -> "p", "\:0440" -> "r", "\:0441" -> "s", "\:0442" -> "t", "\:0443" -> "u",
    "\:0444" -> "f", "\:0445" -> "kh", "\:0446" -> "ts", "\:0447" -> "ch", "\:0448" -> "sh", "\:0449" -> "shch",
    "\:044a" -> "", "\:044b" -> "y", "\:044c" -> "", "\:044d" -> "e", "\:044e" -> "yu", "\:044f" -> "ya",
    "\:0456" -> "i", "\:0457" -> "yi", "\:0454" -> "ye", "\:0491" -> "g", "\:045e" -> "w"
|>

$passportMap = <|
    "\:0430" -> "a", "\:0431" -> "b", "\:0432" -> "v", "\:0433" -> "g", "\:0434" -> "d", "\:0435" -> "e", "\:0451" -> "e",
    "\:0436" -> "zh", "\:0437" -> "z", "\:0438" -> "i", "\:0439" -> "i", "\:043a" -> "k", "\:043b" -> "l", "\:043c" -> "m",
    "\:043d" -> "n", "\:043e" -> "o", "\:043f" -> "p", "\:0440" -> "r", "\:0441" -> "s", "\:0442" -> "t", "\:0443" -> "u",
    "\:0444" -> "f", "\:0445" -> "kh", "\:0446" -> "ts", "\:0447" -> "ch", "\:0448" -> "sh", "\:0449" -> "shch",
    "\:044a" -> "ie", "\:044b" -> "y", "\:044c" -> "", "\:044d" -> "e", "\:044e" -> "iu", "\:044f" -> "ia",
    "\:0456" -> "i", "\:0457" -> "i", "\:0454" -> "e", "\:0491" -> "g", "\:045e" -> "u"
|>

transliterationMap["BGN"] := $bgnMap
transliterationMap["Passport"] := $passportMap

(* One character.  An upper-case letter transliterates as its lower-case form
   with the result capitalized, so \:0429 gives "Shch" at the head of a name and
   not "SHCH". *)
transliterateChar[map_Association, c_String] :=
    Block[{lower = ToLowerCase[c], mapped},
        mapped = Lookup[map, lower, Missing[]];
        Which[
            ! StringQ[mapped], c,
            c === lower, mapped,
            mapped === "", "",
            True, ToUpperCase[StringTake[mapped, 1]] <> StringDrop[mapped, 1]
        ]
    ]

(* A word written entirely in capitals stays entirely in capitals, which is
   how surnames are written on many archival forms. *)
transliterateWord[map_Association, w_String] :=
    Block[{out = StringJoin[transliterateChar[map, #] & /@ Characters[w]]},
        If[ StringLength[w] > 1 && UpperCaseQ[w], ToUpperCase[out], out]
    ]

transliterateName[s_String, "Scientific"] := Transliterate[s]

transliterateName[s_String, scheme_String] /; MemberQ[{"BGN", "Passport"}, scheme] :=
    Block[{map = transliterationMap[scheme]},
        StringJoin @ Map[
            piece |-> If[ StringMatchQ[piece, (WordCharacter | "\:0451" | "\:0401") ..], transliterateWord[map, piece], piece],
            StringSplit[s, x : Except[WordCharacter] :> x]
        ]
    ]

transliterateName[s_String, _] := s
transliterateName[s_, _] := s

FamilyTree::badtransliteration = "`1` is not one of the transliteration schemes `2`; names are left as they are.";

(* None / False leave a name alone; Automatic and True pick the readable
   standard. *)
resolveTransliteration[None | False] := None
resolveTransliteration[Automatic | True] := "BGN"
resolveTransliteration[scheme_String] /; MemberQ[$transliterationSchemes, scheme] := scheme
resolveTransliteration[x_] := (Message[FamilyTree::badtransliteration, x, $transliterationSchemes]; None)

applyTransliteration[s_String, None] := s
applyTransliteration[s_String, scheme_String] := transliterateName[s, scheme]
applyTransliteration[s_, _] := s

#!/usr/bin/env wolframscript
(* ::Package:: *)

(* sync_paclet_symbols.wls - keep the Kernel extension's "Symbols" list in
   PacletInfo.wl equal to the context's public symbols.

   Why this exists: the click-to-copy boxes on the resource pages wrap a
   documented symbol as PacletSymbol["WolframInstitute/Genome", "Name"], and
   PacletResource decides which names to wrap by reading "Symbols" off the
   Kernel extension of the paclet's own PacletInfo (pacletDeclaredSymbols0 ->
   fullPacletObjectInfo -> Extensions -> {"Kernel", ...} -> "Symbols").  With
   no such key the lookup gives Missing["NotFound"] and every symbol renders
   as plain text.  The deploy scripts also PIN that function in the deploying
   kernel, but a pin only helps the machine doing the deploy: an installed
   copy, or anyone calling PacletSymbol themselves, reads the declaration.

   Run from the repository root; publish.wls runs it before deploying.  Exits
   1 when it rewrote the file under -check (so CI can fail on a stale list). *)

repoRoot = ParentDirectory[DirectoryName[$InputFileName]];
pacletDir = FileNameJoin[{repoRoot, "Genome"}];
infoFile = FileNameJoin[{pacletDir, "PacletInfo.wl"}];
context = "WolframInstitute`Genome`";
checkOnly = MemberQ[Rest[$ScriptCommandLine], "-check"];

PacletDirectoryLoad[pacletDir];
Quiet @ Needs[context];

(* Fully qualified, the form every shipping paclet declares and the form the
   C2C wrapper matches against; Names gives the short name once the context is
   on $ContextPath, so requalify. *)
symbols = Sort[(context <> Last[StringSplit[#, "`"]]) & /@ Names[context <> "*"]];
If[ symbols === {},
    Print["sync_paclet_symbols: no symbols found in ", context, " - is the paclet loadable?"];
    Exit[1]
];

text = Import[infoFile, "Text"];

(* The Kernel extension is the one block that carries "Context"; rewrite that
   block only, so every other extension and the file's formatting survive. *)
kernelBlock = StringCases[text,
    Shortest["{" ~~ ws1 : WhitespaceCharacter ... ~~ "\"Kernel\"," ~~ body__ ~~ "\n        }"] :>
        {"{" <> ws1 <> "\"Kernel\"," <> body <> "\n        }", body}, 1];

If[ kernelBlock === {},
    Print["sync_paclet_symbols: could not find the Kernel extension block in ", infoFile];
    Exit[1]
];

{oldBlock, oldBody} = First[kernelBlock];

(* the body without any existing Symbols entry, trailing comma tidied *)
strippedBody = StringTrim[
    StringReplace[oldBody,
        ("," ~~ WhitespaceCharacter ... ~~ "\"Symbols\"" ~~ WhitespaceCharacter ... ~~ "->" ~~
            WhitespaceCharacter ... ~~ "{" ~~ Shortest[___] ~~ "}") -> ""],
    WhitespaceCharacter ...];

symbolList = StringRiffle[("\"" <> # <> "\"") & /@ symbols, ",\n                "];
newBlock = "{\n            \"Kernel\",\n            " <> strippedBody <>
    ",\n            \"Symbols\" -> {\n                " <> symbolList <> "\n            }\n        }";

newText = StringReplacePart[text, newBlock,
    First @ StringPosition[text, oldBlock, 1]];

If[ newText === text,
    Print["sync_paclet_symbols: already in sync (", Length[symbols], " symbols)"];
    Exit[0]
];

If[ checkOnly,
    Print["sync_paclet_symbols: PacletInfo.wl is STALE - run scripts/sync_paclet_symbols.wls"];
    Exit[1]
];

Export[infoFile, newText, "Text"];
Print["sync_paclet_symbols: wrote ", Length[symbols], " symbols into ", FileNameTake[infoFile]];

#!/usr/bin/env wolframscript
(* ::Package:: *)

(* DocumentationBuild the authoring notebooks into publishable ref/guide/tutorial pages,
   then VERIFY the built structure.

   scripts/build_notebooks.wls converts docs/en/**.md into authoring notebooks under
   Genome/Documentation/English.  Those are not yet documentation pages:
   DocumentationBuild is what turns a flat authoring notebook into a page with a Usage
   line, a collapsible Details section and - the part that silently goes missing when this
   stage is skipped - an Examples section with its own ExampleSection subsections and
   example counts.  A page that never went through this stage looks fine to build_notebooks.wls
   and to the test suite, and is visibly broken in the documentation viewer.

   So this script does not just build: it asserts the built cell structure.  A ref page must
   carry a Usage cell, a PrimaryExamplesSection and at least one ExampleSection; a guide must
   carry a GuideTitle and at least one guide-function link section.  A page that builds
   without error but comes out missing its Examples section is reported as a FAILURE.

   The build needs the output to sit inside a COPY of the paclet, so DocumentationBuild can
   resolve this paclet's symbols against it without overwriting the authoring sources under
   Genome/Documentation.  That copy must NOT live inside the repository:
   PacletDirectoryLoad on the repo root discovers a nested PacletInfo.wl as a second paclet,
   and the copy then WINS the resolution - PacletObject["WolframInstitute/Genome"]["Location"]
   returns the build copy, which has no docs/ tree.  That silently redirects documentation
   tests and makes taxonomy tests vacuous, and a stale copy would shadow the working tree's
   kernel code for anything doing PacletDirectoryLoad on the repo.  So the copy goes outside
   the repository, under $TemporaryDirectory; GENOME_DOCBUILD_DIR overrides the location.

   Usage:
     wolframscript -f scripts/docbuild.wls                      (* every page *)
     wolframscript -f scripts/docbuild.wls Genome ImportVCF     (* named pages only *)

   Requires a Front End.  Pages build on a kernel pool; GENOME_DOCBUILD_KERNELS overrides
   the worker count, GENOME_DOCBUILD_TIMEOUT the per-page limit in seconds. *)

repoRoot = ParentDirectory[DirectoryName[$InputFileName]]
srcPaclet = FileNameJoin[{repoRoot, "Genome"}]
buildPaclet = Replace[Environment["GENOME_DOCBUILD_DIR"],
    Except[_String?(StringLength[#] > 0 &)] :>
        FileNameJoin[{$TemporaryDirectory, "WolframInstituteGenome-docbuild"}]]
srcDoc = FileNameJoin[{srcPaclet, "Documentation"}]
destDoc = FileNameJoin[{buildPaclet, "Documentation"}]
linkBase = "WolframInstitute/Genome"

(* DocumentationBuild's hyperlink rewriter calls StringTake on a possibly empty segment; the
   message is noise and the built output is correct. *)
Off[StringTake::take]
Off[FrontEndObject::notavail]

If[ ! DirectoryQ[srcDoc],
    Print["docbuild: ", srcDoc, " not found - run scripts/build_notebooks.wls first."];
    Exit[1]
]

(* A build copy inside the repository would be discovered as a second paclet and shadow the
   real one (see the header).  Refuse rather than corrupt the test environment. *)
If[ StringStartsQ[ExpandFileName[buildPaclet], ExpandFileName[repoRoot] <> $PathnameSeparator],
    Print["docbuild: refusing to build into ", buildPaclet,
        " - it is inside the repository and would shadow the paclet. Set GENOME_DOCBUILD_DIR elsewhere."];
    Exit[1]
]

(* Fresh copy of the paclet minus the doc trees, so PacletDirectoryLoad on the build copy
   resolves this paclet's symbols while DocumentationBuild writes pages into it. *)
If[ DirectoryQ[buildPaclet], DeleteDirectory[buildPaclet, DeleteContents -> True]];
CreateDirectory[buildPaclet, CreateIntermediateDirectories -> True];
Do[
    With[{name = FileNameTake[item], dest = FileNameJoin[{buildPaclet, FileNameTake[item]}]},
        Which[
            MemberQ[{"build", "Documentation", "docs", ".git"}, name], Null,   (* docs trees are rebuilt, not copied *)
            DirectoryQ[item], CopyDirectory[item, dest],
            True, CopyFile[item, dest]
        ]
    ],
    {item, FileNames["*", srcPaclet]}
]

PacletDirectoryLoad[buildPaclet]
Needs["DocumentationBuild`"]

srcEng = FileNameJoin[{srcDoc, "English"}]
destEng = FileNameJoin[{destDoc, "English"}]

allPages = FileNames["*.nb", srcEng, Infinity]

(* A bare name on the command line selects by file base name. *)
wanted = Rest[$ScriptCommandLine]
pages = If[ wanted === {}, allPages, Select[allPages, MemberQ[wanted, FileBaseName[#]] &]]

If[ pages === {},
    Print["docbuild: no pages matched ", wanted];
    Exit[1]
]

outOf[f_] := FileNameJoin[Join[{destEng}, Drop[FileNameSplit[f], Length[FileNameSplit[srcEng]]]]]
relOf[f_] := FileNameJoin[Drop[FileNameSplit[f], Length[FileNameSplit[srcEng]]]]

(* ---------------------------------------------------------------- structure verification *)

(* Which kind of page this is, from its location in the tree. *)
pageKind[f_] := Which[
    StringContainsQ[relOf[f], "Formats"], "Format",
    StringContainsQ[relOf[f], "ReferencePages"], "Symbol",
    StringContainsQ[relOf[f], "Guides"], "Guide",
    True, "Tutorial"
]

cellStyles[nbexpr_] := Cases[nbexpr, Cell[_, s_String, ___] :> s, Infinity]

(* Returns {} when the page is structurally sound, else a list of complaints.  The Examples
   assertions are the point of this script: DocumentationBuild is the ONLY stage that
   produces PrimaryExamplesSection / ExampleSection, so their absence means the page went
   out as a flat authoring notebook. *)
structureProblems[f_, nbexpr_] := Module[{styles = cellStyles[nbexpr], kind = pageKind[f], bad = {}},
    Switch[kind,
        "Symbol",
            If[ ! MemberQ[styles, "Usage"], AppendTo[bad, "no Usage cell"]];
            If[ ! MemberQ[styles, "ObjectName"], AppendTo[bad, "no ObjectName cell"]];
            If[ ! MemberQ[styles, "PrimaryExamplesSection"], AppendTo[bad, "NO Examples section"]];
            If[ ! MemberQ[styles, "ExampleSection"], AppendTo[bad, "no ExampleSection subsection"]];
            If[ ! MemberQ[styles, "Input"], AppendTo[bad, "no example Input cell"]],
        "Format",
            (* a built format page titles itself with ObjectNameAlt (not ObjectName) and carries
               FormatUsage / ImportExportSection / ElementsSection; its examples are what must
               survive the build *)
            If[ ! IntersectingQ[styles, {"ObjectNameAlt", "ObjectName"}], AppendTo[bad, "no ObjectNameAlt cell"]];
            If[ ! MemberQ[styles, "ImportExportSection"], AppendTo[bad, "no ImportExportSection"]];
            If[ ! MemberQ[styles, "PrimaryExamplesSection"], AppendTo[bad, "NO Examples section"]];
            If[ ! MemberQ[styles, "Input"], AppendTo[bad, "no example Input cell"]],
        "Guide",
            If[ ! MemberQ[styles, "GuideTitle"], AppendTo[bad, "no GuideTitle cell"]];
            If[ ! IntersectingQ[styles, {"GuideFunctionsSection", "GuideText", "GuideFunctionsSubsection"}],
                AppendTo[bad, "no guide body section"]],
        _,
            If[ ! IntersectingQ[styles, {"Title", "TechNoteTitle", "TutorialTitle", "Section", "TOCChapter"}],
                AppendTo[bad, "no title/section cell"]]
    ];
    bad
]

(* -------------------------------------------------------------------------------- build *)

timeout = Replace[Quiet@ToExpression[Environment["GENOME_DOCBUILD_TIMEOUT"]], Except[_?Positive] -> 300]
nkernels = Replace[Quiet@ToExpression[Environment["GENOME_DOCBUILD_KERNELS"]], Except[_Integer?Positive] -> Max[2, Min[8, $ProcessorCount]]]

buildOne[f_] := Module[{nb, out = outOf[f], nbexpr, bad},
    If[ ! TrueQ[$gnWorkerReady],
        Needs["DocumentationBuild`"]; PacletDirectoryLoad[$gnBuildPaclet];
        Off[StringTake::take]; Off[FrontEndObject::notavail]; $gnWorkerReady = True
    ];
    (* Success is the return value, not the absence of messages: benign warnings (a See Also
       link to a page not in the local index) are not build failures. *)
    nb = Quiet @ TimeConstrained[
        UsingFrontEnd @ DocumentationBuild`DocumentationBuildNotebook[
            $gnSrcDoc, Import[f], "LinkBase" -> $gnLinkBase, "BuildSearchIndex" -> False],
        $gnTimeout, $TimedOut
    ];
    If[ ! MatchQ[nb, _NotebookObject], Return[{f, "BUILD FAILED", {}}]];
    (* NotebookSave cannot create intermediate directories, and the built tree mirrors the
       source tree (Guides/, ReferencePages/Symbols/, Tutorials/) - without this the save
       silently goes nowhere and the page reads back as unimportable. *)
    Quiet @ CreateDirectory[DirectoryName[out], CreateIntermediateDirectories -> True];
    UsingFrontEnd[NotebookSave[nb, out]];
    UsingFrontEnd[NotebookClose[nb]];
    nbexpr = Quiet @ Import[out];
    If[ Head[nbexpr] =!= Notebook, Return[{f, "UNREADABLE OUTPUT", {}}]];
    bad = structureProblems[f, nbexpr];
    {f, If[bad === {}, "ok", "STRUCTURE"], bad}
]

Print["docbuild: ", Length[pages], " page(s) -> ", destDoc];

LaunchKernels[nkernels];
$gnBuildPaclet = buildPaclet; $gnSrcDoc = srcDoc; $gnLinkBase = linkBase; $gnTimeout = timeout;
DistributeDefinitions[buildOne, structureProblems, cellStyles, pageKind, outOf, relOf,
    srcEng, destEng, $gnBuildPaclet, $gnSrcDoc, $gnLinkBase, $gnTimeout];

results = ParallelMap[buildOne, pages];

(* stragglers retry serially on the master: a wedged worker front end usually builds fine here *)
Module[{failed = Position[results, {_, "BUILD FAILED" | "UNREADABLE OUTPUT", _}]},
    If[ failed =!= {},
        Print["docbuild: retrying ", Length[failed], " straggler(s) serially"];
        $gnWorkerReady = True;
        Scan[Function[pos, results[[First[pos]]] = buildOne[pages[[First[pos]]]]], failed]
    ]
]

Scan[
    Function[r,
        Print[
            Switch[r[[2]], "ok", "  ok    ", _, "  FAIL  "],
            relOf[r[[1]]],
            If[r[[2]] === "ok", "", "   <- " <> r[[2]] <> If[r[[3]] === {}, "", ": " <> StringRiffle[r[[3]], ", "]]]
        ]
    ],
    results
]

nok = Count[results, {_, "ok", _}]
Print[""];
Print[If[nok === Length[results], "PASS  ", "FAIL  "],
    "built and structurally verified ", nok, "/", Length[results], " documentation pages"]

(* An Examples section on every ref page is the specific thing this stage exists to prove.
   Only pages that actually built and were read back count as having one - a page that failed
   to build has an empty complaint list and must not be scored as passing this check. *)
Module[{refs = Select[results, pageKind[First[#]] === "Symbol" &]},
    Print["      ref pages with an Examples section: ",
        Count[refs, r_ /; MemberQ[{"ok", "STRUCTURE"}, r[[2]]] && ! MemberQ[r[[3]], "NO Examples section"]],
        "/", Length[refs]]
]

Exit[If[nok === Length[results], 0, 1]]

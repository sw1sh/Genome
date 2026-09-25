#!/usr/bin/env wolframscript
(* ::Package:: *)

(* The NOTEBOOK builder.  (The documentation SITE builder is scripts/build_docs.wls,
   which frames these notebooks' rendered pages in a single-page browser.)

   Convert the markdown documentation sources to notebooks with MarkdownToNotebook
   (the `mtn` cloud resource function).  Each docs/en/**/*.md becomes a
   DocumentationTools *authoring* notebook (Usage/Details/Examples filled into the
   template) written under Genome/Documentation/English.  These authoring
   notebooks are the editable artifacts you inspect and hand-tweak; a later publish
   step runs DocumentationBuild on a copy at deploy time, so this script never
   overwrites them with built output.

   Layout (source -> built notebook):
     docs/en/Guides/**/<Name>.md                  -> Documentation/English/Guides/<Name>.nb
     docs/en/Tutorials/**/<Name>.md               -> Documentation/English/Tutorials/<Name>.nb
     docs/en/ReferencePages/Symbols/**/<Name>.md  -> Documentation/English/ReferencePages/Symbols/<Name>.nb
     docs/en/ReferencePages/Formats/**/<Name>.md  -> Documentation/English/ReferencePages/Formats/<Name>.nb

   $paclet below names the paclet directory the notebooks are written into.

   docs/en/Guides/Genome.md is the root landing page: it builds to
   Guides/Genome.nb, which is the "MainPage" the paclet's Documentation
   extension points at.

   Output is FLAT by basename, regardless of how the source is nested - the
   documentation system resolves guide/symbol URIs in a flat namespace
   (guide/<Name> -> Guides/<Name>.nb), and the sidebar hierarchy comes from the
   guide-to-guide link graph, not the directory layout.  Each output root is wiped
   first so a moved or renamed source leaves no stale notebook behind.

   Tutorials build with EvaluateSeparator -> None so their examples thread state
   across sections (a narrative walkthrough, not independent reference cells).

   Requires a Wolfram Cloud connection (the converter is a deployed resource
   function).  Exits 1 if any notebook fails to build.

   Usage (from the repo root):
     wolframscript -f scripts/build_notebooks.wls
*)

repoRoot = ParentDirectory[DirectoryName[$InputFileName]]
(* Examples evaluate in this kernel, and the three interpretation pages read the
   anonymized subject callset by a repo-relative path (data/subject_genome.vcf.gz),
   so the build runs from the repository root whatever directory launched it. *)
SetDirectory[repoRoot]

$paclet   = "Genome"
langDir   = FileNameJoin[{repoRoot, "docs", "en"}]
pacletDir = FileNameJoin[{repoRoot, $paclet}]
docOut    = FileNameJoin[{pacletDir, "Documentation", "English"}]

(* Register the paclet so its own documented symbols' contexts resolve while
   converting (every public symbol lives in WolframInstitute`Genome`). *)
PacletDirectoryLoad[pacletDir]

guidesSrc    = FileNameJoin[{langDir, "Guides"}]
guidesOut    = FileNameJoin[{docOut, "Guides"}]
tutorialsSrc = FileNameJoin[{langDir, "Tutorials"}]
tutorialsOut = FileNameJoin[{docOut, "Tutorials"}]
symbolsSrc   = FileNameJoin[{langDir, "ReferencePages", "Symbols"}]
symbolsOut   = FileNameJoin[{docOut, "ReferencePages", "Symbols"}]
formatsSrc   = FileNameJoin[{langDir, "ReferencePages", "Formats"}]
formatsOut   = FileNameJoin[{docOut, "ReferencePages", "Formats"}]

If[ ! $CloudConnected,
    With[{user = Environment["WOLFRAM_CLOUD_USER"], pass = Environment["WOLFRAM_CLOUD_PASSWORD"]},
        If[ StringQ[user] && StringQ[pass], CloudConnect[user, pass], CloudConnect[]]
    ]
]

If[ ! $CloudConnected,
    Print["Wolfram Cloud connection failed - set WOLFRAM_CLOUD_USER and WOLFRAM_CLOUD_PASSWORD for non-interactive (CI) use."];
    Exit[1]
]

(* MarkdownToNotebook: a local checkout via GENOME_MTN (plain top-level definitions, so
   Get-ing it defines the symbol in the current context), else the published cloud
   resource.  The same override publish.wls honors, so both halves of the pipeline can be
   built against fixes that are not published yet. *)
With[{e = Environment["GENOME_MTN"]},
    If[ StringQ[e] && e =!= "" && FileExistsQ[e],
        Get[e]; mtn = MarkdownToNotebook,
        mtn = ResourceFunction["https://www.wolframcloud.com/obj/nikm/DeployedResources/Function/MarkdownToNotebook"]
    ]
]

If[ ! (Head[mtn] === ResourceFunction || OwnValues[mtn] =!= {} || DownValues[mtn] =!= {}),
    Print["MarkdownToNotebook is unavailable (set GENOME_MTN to a local checkout, or check network access)"];
    Exit[1]
]

(* Named pages: page basenames on the command line (`... build_notebooks.wls
   FamilyTreePlot ImportVCF`) rebuild only those sources and leave every other
   notebook where it is.  A page that evaluates nothing but its own synthetic
   fixture can be refreshed this way on a machine without the subject callset,
   where a full build would wipe the tree and re-evaluate every page against data
   it cannot read.  When publish.wls Gets this script, $ScriptCommandLine is
   publish.wls's own, with no page names, so a publish always builds everything. *)
$only = Rest[$ScriptCommandLine];
pick[srcs_List] := If[ $only === {}, srcs, Select[srcs, MemberQ[$only, FileBaseName[#]] &]]

(* A full build wipes and recreates each output root, so a moved source leaves no
   stale notebook.  A named-pages build only makes sure the roots exist. *)
freshDir[dir_] := (
    If[ DirectoryQ[dir] && $only === {}, DeleteDirectory[dir, DeleteContents -> True]];
    If[ ! DirectoryQ[dir], CreateDirectory[dir, CreateIntermediateDirectories -> True]]
)
freshDir /@ {guidesOut, tutorialsOut, symbolsOut, formatsOut}

(* Output is FLAT by basename, regardless of how the source is nested.  The
   documentation system resolves guide/symbol URIs in a flat namespace
   (guide/<Name> -> Guides/<Name>.nb), so a nested output path breaks every
   cross-link and the navigation sidebar.  The sidebar HIERARCHY is built from the
   guide-to-guide link graph, not from directories - so flat output still yields
   the full nested tree. *)
build[src_, out_, opts___] := (
    Print["building ", FileNameTake[src], " -> ", FileNameTake[out]];
    mtn[src, out, opts];
    If[ FileExistsQ[out],
        {out, True},
        Print["  FAILED: ", FileNameTake[src]];
        {out, False}
    ]
)

guideResults = build[#, FileNameJoin[{guidesOut, FileBaseName[#] <> ".nb"}]] & /@ pick[Sort[FileNames["*.md", guidesSrc, Infinity]]]

tutorialResults = build[#, FileNameJoin[{tutorialsOut, FileBaseName[#] <> ".nb"}], "EvaluateSeparator" -> None] & /@ pick[Sort[FileNames["*.md", tutorialsSrc, Infinity]]]

symbolResults = build[#, FileNameJoin[{symbolsOut, FileBaseName[#] <> ".nb"}]] & /@ pick[Sort[FileNames["*.md", symbolsSrc, Infinity]]]

(* Format pages (Template: Format) build like symbol pages, into ReferencePages/Formats. *)
formatResults = If[ DirectoryQ[formatsSrc],
    build[#, FileNameJoin[{formatsOut, FileBaseName[#] <> ".nb"}]] & /@ pick[Sort[FileNames["*.md", formatsSrc, Infinity]]],
    {}]

results = Join[guideResults, tutorialResults, symbolResults, formatResults]
nBuilt = Count[results, {_, True}]
nFail = Count[results, {_, False}]

Print[""]
If[ results === {},
    Print["NOTE  no markdown sources found under ", langDir, " - nothing to build"];
    Exit[0]
]

(* Exit only on failure (fail-fast, also aborts a publish that Get-s this); on
   success fall through with no Exit so a Get-ing script continues.  Standalone,
   the script exits 0 at end. *)
If[ nFail > 0,
    Print["FAIL  built ", nBuilt, "/", Length[results], " authoring notebooks under Genome/Documentation/English"];
    Exit[1],
    Print["PASS  built ", nBuilt, "/", Length[results], " authoring notebooks under Genome/Documentation/English"]
]

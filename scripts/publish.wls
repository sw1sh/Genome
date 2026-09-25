#!/usr/bin/env wolframscript
(* ::Package:: *)

(* Publish the Genome paclet publicly to the Wolfram Cloud.

   The scripted equivalent of the "Deploy -> Publicly in the cloud" button on a paclet
   ResourceDefinition notebook: scrape the paclet resource from that notebook and
   CloudDeploy it with Permissions -> "Public", to the location the button computes
   (<account>/DeployedResources/Paclet/<Publisher>/<Name>, the slash kept as a path
   separator).  That is what makes the resource shingle and its bundled documentation
   serve and anonymously resolve, so anyone can

     PacletInstall[ResourceObject[
       "https://www.wolframcloud.com/obj/<account>/DeployedResources/Paclet/WolframInstitute/Genome"],
       ForceVersionInstall -> True]

   It packs the paclet, uploads the raw archive, and scrapes + CloudDeploys the paclet
   resource with a hero image, a hierarchical Guides sidebar, and the deploy
   correctness/perf patches.

   Nothing is written into the repository except the authoring notebooks that
   build_notebooks.wls regenerates under Genome/Documentation/English (gitignored build
   output).  The ResourceDefinition.nb and the
   .paclet archive are both produced inside throwaway directories under $TemporaryDirectory,
   and the ONLY paclet registered is the staging copy (registering Genome/ as well
   would give two copies of the same Name/Version, and PacletExtensionFiles / the scrape
   then resolve an ambiguous PacletObject and fail).

   What it does, in order:
     1. Connect to the Wolfram Cloud (WOLFRAM_CLOUD_USER / WOLFRAM_CLOUD_PASSWORD for CI).
     2. Ensure the documentation notebooks exist under Genome/Documentation/English,
        running scripts/build_notebooks.wls if they are missing.  Set
        GENOME_PUBLISH_BUILT_DOCS=<dir> (a directory containing English/) to bundle an
        externally built - e.g. DocumentationBuild'd via scripts/docbuild.wls - doc tree
        instead.
     3. Stage a clean paclet copy OUTSIDE the repo (PacletInfo + Kernel + Documentation +
        Tests + Assets + README), so the archive and the scrape never pick up docs/ sources,
        scripts/, or - the one that matters here - anything under data/.
        GENOME_PUBLISH_DIR overrides the staging location.  Register only this copy.
     4. Build ResourceDefinition.nb from docs/ResourceDefinition.md straight into the
        staging copy, under a Front End.
     5. Upload the raw Genome.paclet archive to a public CloudObject (a plain download).
     6. Scrape the resource and CloudDeploy it publicly; print the resource-page URL and
        the PacletInstall command.

   Prerequisites: a Wolfram Cloud connection and a usable Front End (the scrape opens the
   definition notebook).  Idempotent: re-running redeploys to the same location.

   Usage: wolframscript -f scripts/publish.wls *)


repoRoot = ParentDirectory[DirectoryName[$InputFileName]]

(* the paclet lives in Genome/; its doc SOURCES live beside it in docs/ *)
$paclet   = "Genome"
pacletDir = FileNameJoin[{repoRoot, $paclet}]
docsDir   = FileNameJoin[{repoRoot, "docs"}]

pacletName = "WolframInstitute/Genome"
archiveName = "Genome.paclet"

resDefSrc = FileNameJoin[{docsDir, "ResourceDefinition.md"}]
docEng    = FileNameJoin[{pacletDir, "Documentation", "English"}]

stageDir = Replace[Environment["GENOME_PUBLISH_DIR"],
    Except[_String?(StringLength[#] > 0 &)] :>
        FileNameJoin[{$TemporaryDirectory, "WolframInstituteGenome-publish"}]]

archiveDir = FileNameJoin[{$TemporaryDirectory, "WolframInstituteGenome-archive"}]

stagedResDef = FileNameJoin[{stageDir, "ResourceDefinition.nb"}]

(* Sanity ceiling on what may be uploaded.  A clean Genome paclet is small and bounded:
   Kernel is ~0.4 MB of .wl source, Tests ~0.15 MB, the built documentation tree a few MB
   of notebooks, plus one hero PNG of a megabyte or two - call it under 10 MB in the worst
   case, so 60 MB leaves comfortable headroom for more pages and assets.  Puzzles can
   afford 100 MB; this repo cannot.  data/ holds personal genomic PII where a SINGLE file
   (one chromosome VCF, a genotyping array export, a Parquet shard) runs from tens of
   megabytes to gigabytes, so a low ceiling is the last line of defence that turns
   "a genome file got swept into the archive" from a public data leak into a hard abort.
   It also still catches the mundane failures the check exists for: a stray .paclet, a
   build copy, or a followed symlink bundled by mistake. *)
maxArchiveBytes = 60 * 10^6

(* A staging copy inside the repository would be discovered as a second paclet and shadow
   the real one during the scrape (see docbuild.wls's header).  Refuse it. *)
If[ StringStartsQ[ExpandFileName[stageDir], ExpandFileName[repoRoot] <> $PathnameSeparator],
    Print["publish: refusing to stage into ", stageDir,
        " - it is inside the repository and would shadow the paclet. Set GENOME_PUBLISH_DIR elsewhere."];
    Exit[1]
]

(* DocumentationBuild's HTML transform emits a harmless StringTake::take; the scrape uses the
   same path.  Silence it so real output stands out. *)
Off[StringTake::take]


(* ---------------------------------------------------------------- 1. cloud connection *)

If[ ! $CloudConnected,
    With[{user = Environment["WOLFRAM_CLOUD_USER"], pass = Environment["WOLFRAM_CLOUD_PASSWORD"]},
        If[ StringQ[user] && StringQ[pass], CloudConnect[user, pass], CloudConnect[]]
    ]
]

If[ ! $CloudConnected,
    Print["publish: Wolfram Cloud connection failed - set WOLFRAM_CLOUD_USER and WOLFRAM_CLOUD_PASSWORD for non-interactive use."];
    Exit[1]
]

Print["publish: connected as ", $CloudUserID]

(* An account pin.  The block above keeps whatever identity the kernel already
   holds, and a wolframscript kernel arrives connected with the machine's last
   cached credential - which is shared by every wolframscript session on the
   machine, and once sent a publish to another account.  With
   GENOME_CLOUD_ACCOUNT set (an account id, or a full .../obj/<id> root), refuse
   to deploy under any other cloud id. *)
(* $CloudRootDirectory is CloudObject[url] when connected and None when not. *)
accountMatchQ[want_String] :=
    MatchQ[$CloudRootDirectory, CloudObject[_String, ___]] &&
    StringEndsQ[First[$CloudRootDirectory], "/obj/" <> Last[StringSplit[want, "/"]]]

With[{want = Environment["GENOME_CLOUD_ACCOUNT"]},
    If[ StringQ[want] && want =!= "" && ! accountMatchQ[want],
        (* The identity the kernel arrived with is another account's - on this
           machine the desktop front end is signed in as one, and every notebook
           evaluation there rewrites the recent-user store wolframscript kernels
           start from.  Reconnecting is the fix, but only when this run HOLDS a
           credential to reconnect with: CloudDisconnect[] clears the machine's
           saved login, so disconnecting on the hope that CloudConnect[] can
           prompt leaves every wolframscript kernel on the machine unable to
           connect at all, with no way back but an interactive sign-in.  That
           happened once.  Without the environment pair, refuse and leave the
           connection - and the saved login - exactly as they were. *)
        With[{user = Environment["WOLFRAM_CLOUD_USER"], pass = Environment["WOLFRAM_CLOUD_PASSWORD"]},
            If[ ! (StringQ[user] && StringQ[pass]),
                Print["publish: kernel arrived connected as ", $CloudUserID,
                      " but GENOME_CLOUD_ACCOUNT=", want, "."];
                Print["publish: refusing to deploy under another account, and refusing to disconnect -"];
                Print["publish: set WOLFRAM_CLOUD_USER and WOLFRAM_CLOUD_PASSWORD, or sign the machine"];
                Print["publish: back in to ", want, " (CloudConnect in a notebook), then re-run."];
                Exit[1]
            ];
            Print["publish: kernel arrived connected as ", $CloudUserID, " - reconnecting as ", user];
            CloudDisconnect[];
            CloudConnect[user, pass];
            If[ ! TrueQ[$CloudConnected],
                Print["publish: CloudConnect as ", user, " FAILED - the WOLFRAM_CLOUD_USER / ",
                      "WOLFRAM_CLOUD_PASSWORD pair was rejected (a quoted value read without ",
                      "the shell unquoting it is the usual cause)"];
                Exit[1]
            ]
        ];
        If[ ! TrueQ[$CloudConnected] || ! accountMatchQ[want],
            Print["publish: connected account root is ",
                  If[MatchQ[$CloudRootDirectory, CloudObject[_String, ___]], First[$CloudRootDirectory], "(not connected)"],
                  " but GENOME_CLOUD_ACCOUNT=", want,
                  " - refusing to deploy under another account"];
            Exit[1]
        ];
        Print["publish: reconnected as ", $CloudUserID]
    ]
]

(* The documentation examples - the resource page's included - evaluate against the subject
   callset at data/subject_genome.vcf.gz, by that repo-relative path.  ImportVCF on a missing
   file does not fail: it returns an empty Genome handle (build Unknown, no samples), so every
   example after it ships unevaluated.  The resource page went out exactly that way once, with
   a verification that looked only for Failure and $Failed and so passed.  Refuse instead. *)
SetDirectory[repoRoot]
If[ ! FileExistsQ[FileNameJoin[{repoRoot, "data", "subject_genome.vcf.gz"}]],
    Print["publish: ABORT - data/subject_genome.vcf.gz is not readable at the repository root (",
          repoRoot, "). The documentation examples evaluate against it; supply data/ there (a",
          " directory or a symlink) and re-run."];
    Exit[1]
]

If[ ! FileExistsQ[resDefSrc],
    Print["publish: ", resDefSrc, " not found."];
    Exit[1]
]


(* --------------------------------------------------- 2. build the documentation PAGES *)

(* The deployed resource must ship DocumentationBuild'd pages, NOT the flat MarkdownToNotebook
   authoring notebooks: an authoring notebook renders with a doubled section rule and its examples
   collapsed under "Examples Initialization" - the "pre-built" look.  So (re)build the authoring
   notebooks from the current markdown (build_notebooks.wls, picking up any new or changed source),
   then DocumentationBuild them into real pages (docbuild.wls), and stage THOSE.  Set
   GENOME_PUBLISH_BUILT_DOCS=<built English dir> to skip both builds and stage a tree built
   elsewhere; GENOME_PUBLISH_SKIP_DOCBUILD=1 stages the authoring notebooks as-is (fast, but
   renders pre-built). *)
prebuilt = Environment["GENOME_PUBLISH_BUILT_DOCS"]

runStep[label_, script_] := With[{res = RunProcess[{"wolframscript", "-f", FileNameJoin[{repoRoot, "scripts", script}]}]},
    Print[res["StandardOutput"]];
    If[ res["ExitCode"] =!= 0,
        Print["publish: ", label, " failed"]; Print[res["StandardError"]]; Exit[1]]
]

(* Keep PacletInfo's declared "Symbols" equal to the context before anything is
   staged.  The click-to-copy boxes wrap a documented symbol as PacletSymbol[...]
   only for names on that list, and it is read from the paclet's own PacletInfo,
   so a symbol added since the last sync would ship unwrapped. *)
runStep["sync_paclet_symbols.wls", "sync_paclet_symbols.wls"]

builtEng =
    Which[
        StringQ[prebuilt] && DirectoryQ[prebuilt],
            Print["publish: GENOME_PUBLISH_BUILT_DOCS set - staging pre-built docs from ", prebuilt];
            prebuilt,
        Environment["GENOME_PUBLISH_SKIP_DOCBUILD"] === "1",
            Print["publish: GENOME_PUBLISH_SKIP_DOCBUILD=1 - staging authoring notebooks (they render pre-built)"];
            If[ FileNames["*.nb", docEng, Infinity] === {}, runStep["build_notebooks.wls", "build_notebooks.wls"]];
            docEng,
        True,
            (* GENOME_PUBLISH_REUSE_NOTEBOOKS=1 keeps the authoring notebooks already under
               Genome/Documentation/English instead of regenerating them from markdown, and
               still DocumentationBuilds them through the normal path below.  Regenerating
               re-evaluates every page against the subject callset in data/; reusing lets a
               machine without it publish what was last built, after refreshing any page it
               can (build_notebooks.wls <Name> rebuilds just that page). *)
            If[ Environment["GENOME_PUBLISH_REUSE_NOTEBOOKS"] === "1" && FileNames["*.nb", docEng, Infinity] =!= {},
                Print["publish: GENOME_PUBLISH_REUSE_NOTEBOOKS=1 - reusing the ",
                      Length[FileNames["*.nb", docEng, Infinity]], " authoring notebooks, not rebuilding them"],
                Print["publish: building authoring notebooks (build_notebooks.wls) ..."];
                runStep["build_notebooks.wls", "build_notebooks.wls"]
            ];
            Print["publish: DocumentationBuild'ing the pages (docbuild.wls) ..."];
            runStep["docbuild.wls", "docbuild.wls"];
            With[{dbEng = FileNameJoin[{$TemporaryDirectory, "WolframInstituteGenome-docbuild", "Documentation", "English"}]},
                If[ ! DirectoryQ[dbEng] || FileNames["*.nb", dbEng, Infinity] === {},
                    Print["publish: docbuild produced no pages at ", dbEng]; Exit[1]];
                dbEng
            ]
    ]


(* ------------------------------------------------- 3. stage a clean copy (outside repo) *)

If[ DirectoryQ[stageDir], DeleteDirectory[stageDir, DeleteContents -> True]]
CreateDirectory[stageDir, CreateIntermediateDirectories -> True]

copyFrom[base_, name_] := With[{src = FileNameJoin[{base, name}], dst = FileNameJoin[{stageDir, name}]},
    Which[
        ! FileExistsQ[src] && ! DirectoryQ[src], Null,
        DirectoryQ[src], CopyDirectory[src, dst],
        True, CopyFile[src, dst]
    ]
]
(* paclet components come from Genome/.  LibraryResources is a placeholder for a future
   compiled library: the paclet declares no such extension today, so copyFrom skips it.
   Kept so adding one needs no change here.  Symmetry with the
   PacletInfo extension set and is simply skipped while the paclet has no compiled library *)
copyFrom[pacletDir, #] & /@ {"PacletInfo.wl", "Kernel", "Tests", "LibraryResources", "Assets"}

(* The repository README rides along as the paclet's README: it is written for someone
   installing the resource first, and for someone building it second. *)
copyFrom[repoRoot, "README.md"]

(* Documentation: stage the built English tree chosen above (docbuild output by default). *)
With[{destDoc = FileNameJoin[{stageDir, "Documentation"}]},
    CreateDirectory[destDoc];
    CopyDirectory[builtEng, FileNameJoin[{destDoc, "English"}]]
]

If[ ! FileExistsQ[FileNameJoin[{stageDir, "Documentation", "English", "Guides", "Genome.nb"}]],
    Print["publish: staged copy is missing the main guide Documentation/English/Guides/Genome.nb"];
    Exit[1]
]

(* PacletInfo declares an Asset extension for Assets/hero.png; without it the shingle
   deploys with no hero.  Not fatal - warn and carry on. *)
If[ ! FileExistsQ[FileNameJoin[{stageDir, "Assets", "hero.png"}]],
    Print["publish: WARNING - no Assets/hero.png in the staged copy; the shingle will have no hero image"]
]

(* Register ONLY the staging copy - one paclet, resolved unambiguously by the scrape. *)
PacletDirectoryLoad[stageDir]


(* --------------------------------- 4. build ResourceDefinition.nb into the staging copy *)

(* MarkdownToNotebook: a local checkout via GENOME_MTN, else the published cloud resource. *)
With[{e = Environment["GENOME_MTN"]},
    If[ StringQ[e] && e =!= "" && FileExistsQ[e],
        Get[e],
        MarkdownToNotebook = ResourceFunction[ResourceObject["https://www.wolframcloud.com/obj/nikm/DeployedResources/Function/MarkdownToNotebook"]]
    ]
]
If[ ! (OwnValues[MarkdownToNotebook] =!= {} || DownValues[MarkdownToNotebook] =!= {}),
    Print["publish: MarkdownToNotebook is unavailable (set GENOME_MTN to a local checkout, or check network access)"];
    Exit[1]
]

Print["publish: building ResourceDefinition.nb from ", FileNameTake[resDefSrc], " into the staging copy"]
UsingFrontEnd @ TimeConstrained[MarkdownToNotebook[resDefSrc, stagedResDef], 300]
If[ ! FileExistsQ[stagedResDef],
    Print["publish: failed to build ", stagedResDef];
    Exit[1]
]
(* NOTE: do NOT post-process the notebook to strip the (empty) ExampleNotebook scaffold group
   here.  Deleting cells from the built notebook at {0, Infinity} corrupts the structure the
   scrape relies on - verified to turn a working scrape (ResourceObject) into a failure
   (NoPacletInfoFileCell).  The empty Examples scaffold is harmless in the deployed resource. *)


(* ---------------------------------------------------- 5. upload the raw paclet archive *)

(* Sanity: a clean Genome paclet is a few megabytes.  Refuse to upload or deploy anything
   wildly larger - that only happens when something (a genomic data file, a stray archive,
   a build copy, a followed symlink) has been bundled by mistake.  See maxArchiveBytes. *)
With[{files = Select[FileNames["*", stageDir, Infinity], ! DirectoryQ[#] &]},
    With[{stagedBytes = Total[FileByteCount /@ files]},
        Print["publish: staged paclet is ", NumberForm[stagedBytes/10.^6, {6, 2}], " MB across ",
            Length[files], " files"];
        If[ ! (NumberQ[stagedBytes] && stagedBytes <= maxArchiveBytes),
            Print["publish: ABORT - staged paclet is ", stagedBytes,
                " bytes, not within the sane ", maxArchiveBytes/10^6, " MB limit. Refusing to upload/deploy."];
            Exit[1]
        ]
    ]
]

Module[{archive, target},
    (* Write the archive OUTSIDE the staging dir: CreatePacletArchive[dir, dir] would drop the
       .paclet inside the very directory that the resource scrape then re-archives, bundling the
       paclet inside itself.  Keep it separate. *)
    If[ DirectoryQ[archiveDir], DeleteDirectory[archiveDir, DeleteContents -> True]];
    CreateDirectory[archiveDir, CreateIntermediateDirectories -> True];
    archive = CreatePacletArchive[stageDir, archiveDir];
    If[ ! StringQ[archive] || ! FileExistsQ[archive],
        Print["publish: CreatePacletArchive failed"]; Exit[1]
    ];
    Print["publish: archive ", FileNameTake[archive], " is ", NumberForm[FileByteCount[archive]/10.^6, {6, 2}], " MB"];
    If[ FileByteCount[archive] > maxArchiveBytes,
        Print["publish: ABORT - archive exceeds ", maxArchiveBytes/10^6, " MB. Refusing to upload."];
        Exit[1]
    ];
    target = CloudObject[archiveName, $CloudRootDirectory];
    Print["publish: uploading raw archive -> ", First[target]];
    CopyFile[archive, target, OverwriteTarget -> True];
    SetOptions[target, Permissions -> "Public"];
    Print["publish: archive public at ", First[target]]
]


(* ------------------------ 6. custom-site deploy machinery, then scrape and deploy public *)

(* Headless deploy needs the TOLERANT scrape: the definition notebook's PacletManifest is filled
   by an interactive PacletDirectoryChooser cell that only populates when a person clicks it in a
   visible front end, so a strict gate would reject the notebook (NoPacletInfoFileCell).  The paclet
   metadata is scraped straight from the directory regardless, giving a valid, installable resource.
   pmScrapeAndDeploy reads PM_SCRAPE_TOLERANT; set it here unless GENOME_SCRAPE_STRICT=1 forces
   strict (only meaningful with a real interactive front end). *)
If[ Environment["GENOME_SCRAPE_STRICT"] =!= "1", SetEnvironment["PM_SCRAPE_TOLERANT" -> "1"] ]

(* deploy_common.wls is the custom site: the no-purge/delta deploy patches,
   the string-Details htmlFragmentExport fix, the PacletSymbol C2C symbol pin, the hero-image
   injection and the (unused here, see below) hierarchical Guides sidebar, plus the headless
   pmScrapeAndDeploy. *)
Get[FileNameJoin[{repoRoot, "scripts", "deploy_common.wls"}]]

pmInstallDeployPatches[pacletName, "WolframInstitute`Genome`"]

(* No pmInstallTreeSidebar here: this paclet ships exactly one guide (Guides/Genome), so there is
   no guide-to-guide hierarchy to render and the tree would collapse to an empty <ul> (the root
   guide is the seed, and the seed is never listed as its own child).  The stock flat Guides rail
   is the right rendering for a single guide; install the tree only once a second guide links out
   of the root. *)

(* the shingle hero (the headless Interactive -> False scrape does not capture the HeroImage cell) *)
With[{heroFile = FileNameJoin[{stageDir, "Assets", "hero.png"}]},
    pmInjectHero[If[FileExistsQ[heroFile], Quiet @ Import[heroFile], $Failed]]
]

result = pmScrapeAndDeploy[stagedResDef, pacletName]

url = FirstCase[{result}, c_CloudObject :> First[c], Missing[], Infinity]
If[ MissingQ[url],
    url = FirstCase[{result}, s_String /; StringContainsQ[s, "wolframcloud.com"], Missing[], Infinity]
]

If[ MissingQ[url],
    If[ FailureQ[result],
        Print["publish: deploy failed - ", result["Message"]],
        Print["publish: deploy did not return a URL. Result: ", result]
    ];
    Exit[1]
]

(* The deploy returning a URL is not evidence that anything is AT that URL: a run whose
   example- and definition-notebook deploys failed still yielded a URL, printed "published:",
   and left no resource object behind at all.  Confirm the object is really there, and that a
   signed-out visitor can read it, before claiming success. *)
Module[{listed, anon},
    listed = Quiet @ Check[
        MemberQ[First /@ CloudObjects[ParentDirectory[CloudObject[url]]], url], False];
    anon = Quiet @ Check[
        URLRead[HTTPRequest[url], "StatusCode", Authentication -> None], $Failed];
    If[ ! TrueQ[listed],
        Print["publish: FAILED - no resource object at ", url];
        Print["publish: the deploy reported a URL but created nothing; read the log above for"];
        Print["publish: CloudObject::cloudnf or CloudDeploy::appearancenotsup."];
        Exit[1]
    ];
    Print["publish: resource object confirmed present"];
    Print["publish: anonymous read -> ", anon,
        If[anon === 200, " (public)", " (NOT publicly readable - check the permissions pass)"]]
]

Print[""]
Print["published: ", url]
Print["install:   PacletInstall[ResourceObject[\"", url, "\"], ForceVersionInstall -> True]"]
Exit[0]

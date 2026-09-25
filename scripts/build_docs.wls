#!/usr/bin/env wolframscript
(* ::Package:: *)

(* The documentation SITE builder.  (The NOTEBOOK builder - markdown to authoring
   notebooks - is scripts/build_notebooks.wls; this script frames what that one produces.)

   Build the Genome single-page documentation browser, for either target:

     wolframscript -f scripts/build_docs.wls site    build + DEPLOY the cloud shell
     wolframscript -f scripts/build_docs.wls local   render offline + assemble under build/local-docs
     DRYRUN=1 wolframscript -f scripts/build_docs.wls <target>   print the tree, no render/deploy

   site: the stock paclet shingle deploys each documentation page as a "delayed
   embed" that fetches /statichtml/<page>.nb?maxwaitmillis=1000 at request time --
   one second is not enough to render these notebooks, so every page except a
   pre-warmed one comes back empty, and in-content links escape into the old
   chrome. So we deploy ONE page -- index.html -- that frames the resource's live
   Documentation/{guide,ref,tutorial}/<Name>.html embed pages: a persistent
   collapsible tree on the left, a single <iframe> in the middle, a same-origin
   click hook routing in-content links through the loader.

   local: the same shell, rendered offline - no cloud render and no deploy: each
   authoring notebook goes to static HTML through the headless FrontEnd
   (DocumentationBuild`DocumentationBuildHTML, hash-keyed .html-cache so a no-change
   rebuild takes seconds) and BASE points at the local files. The one thing this target
   cannot work out offline is the cloud address behind the front-page rail entry, so
   that is looked up at most once, under a time cap, and remembered in
   .html-cache/cloud-account.txt; every later build reads the file and touches the
   network not at all. Serve it with:
     python3 -m http.server --directory build/local-docs 8000
   GENOME_LOCAL_ONLY=Guides/Genome renders ONE page; GENOME_HTML_CACHE=0 forces a
   full render. Output: build/local-docs/ (staged + swapped, so a running server
   never sees a half-wiped site).

   The nav model is the guide-to-guide link graph, exactly as in the PureMath port this
   comes from - but this paclet ships ONE guide (Guides/Genome) and a flat set of symbol
   pages, so the tree collapses to a single root with no children.  Rather than render an
   empty rail, a childless root is listed as its own entry, and any guide the graph never
   reaches is appended after it; the moment a second guide is linked from a section
   heading of Genome.md, the nested rendering takes over with no change here.

   A Get-ing script can set the global genomeDocsTarget = "site" first, which takes
   precedence over the command line. *)

target = If[ StringQ[genomeDocsTarget], genomeDocsTarget,
    If[ Length[$ScriptCommandLine] >= 2, ToLowerCase[$ScriptCommandLine[[2]]], ""]];
If[ ! MemberQ[{"site", "local"}, target],
    Print["usage: wolframscript -f scripts/build_docs.wls site|local"];
    Exit[1]
];
say[args___] := Print["build_docs[", target, "]: ", args];

repoRoot    = ParentDirectory[DirectoryName[$InputFileName]];
(* Doc sources live in docs/{en,web}, beside the paclet in Genome/. *)
$paclet     = "Genome";
docsRoot    = FileNameJoin[{repoRoot, "docs"}];
guidesDir   = FileNameJoin[{docsRoot, "en", "Guides"}];
symbolsDir  = FileNameJoin[{docsRoot, "en", "ReferencePages", "Symbols"}];
tutorialDir = FileNameJoin[{docsRoot, "en", "Tutorials"}];
formatsDir  = FileNameJoin[{docsRoot, "en", "ReferencePages", "Formats"}];
webDir      = FileNameJoin[{docsRoot, "web"}];
$rootGuide  = "Genome";

(* ---- site-target config ---- *)
$target      = "Genome";   (* cloud dir for the shell, under the account root (wolframinstitute) *)
$resourceRel = "DeployedResources/Paclet/WolframInstitute/Genome";  (* where publish.wls deploys *)

If[ ! DirectoryQ[guidesDir], say["Guides dir not found: ", guidesDir]; Exit[1] ];

(* template assets (separate .css/.js/.html so editors syntax-highlight them) *)
readAsset[f_] := Module[{p = FileNameJoin[{webDir, f}]},
    If[FileExistsQ[p], Import[p, "Text"], say["missing asset ", p]; Exit[1]]];

(* ==================== shared nav model (guides / symbols / tech notes) ==================== *)

guideFiles = FileNames["*.md", guidesDir, Infinity];
nameToFile = Association[(FileBaseName[#] -> #) & /@ guideFiles];

guideText[name_] := guideText[name] =
    Replace[nameToFile[name], {f_String :> Import[f, "Text"], _ :> ""}];

(* YAML quotes any frontmatter title containing ": " - the notebook build unquotes it, so the
   rail must too, or those pages read as quoted in the nav. *)
unquoteTitle[t_String] := Replace[StringTrim[t],
    s_String /; StringLength[s] > 1 && StringMatchQ[s, ("\"" ~~ ___ ~~ "\"") | ("'" ~~ ___ ~~ "'")] :>
        StringTake[s, {2, -2}]];

guideTitle[name_] := Module[{m},
    m = StringCases[guideText[name],
            StartOfLine ~~ "Title:" ~~ Whitespace... ~~ t : Except["\n"].. :> t, 1];
    If[m === {}, name, unquoteTitle[First[m]]]
];

(* guides linked from a section heading, in the order the guide lists them *)
linkedGuides[name_] :=
    DeleteDuplicates @ StringCases[guideText[name],
        StartOfLine ~~ "#" .. ~~ Whitespace... ~~ "[" ~~ Shortest[__] ~~
            "](paclet:WolframInstitute/Genome/guide/" ~~ child : (WordCharacter ..) ~~ ")"
        :> child
    ];

(* A guide's children are the guides ITS BODY LINKS from section headings, in that curated order -
   the guide-to-guide link graph, NOT the directory layout. A guide legitimately belongs under every
   area that lists it, so the tree does NOT dedup globally: that starves whole areas of their
   children. Only the ANCESTOR path is excluded, which breaks cycles while keeping every legitimate
   placement; the nav focuses the instance you clicked (see docs/web/docs_site.js), so duplicates
   are navigable rather than confusing. *)
childGuides[name_] :=
    {#, guideTitle[#]} & /@ Select[linkedGuides[name], KeyExistsQ[nameToFile, #] &];

(* Frontmatter Keywords are the vocabulary a reader actually searches by ("haplogroup" finds
   Ancestry, "drug response" finds Pharmacogenomics, whose titles say none of it), so carry them
   into the rail for the filter to match alongside the title. *)
keywordsOf[f_] := Replace[
    StringCases[Import[f, "Text"],
        StartOfLine ~~ "Keywords:" ~~ Whitespace... ~~ "[" ~~ k : Except["]"] .. ~~ "]" :> k, 1],
    {{k_String} :> ToLowerCase @ StringRiffle[StringTrim /@ StringSplit[k, ","], " "], _ -> ""}]

symbolFiles = If[DirectoryQ[symbolsDir], FileNames["*.md", symbolsDir, Infinity], {}];
(* symbols go in the right rail (flat, alphabetical); not nested under guides *)
symbolsAll = Sort @ DeleteDuplicates[FileBaseName /@ symbolFiles];
symbolKeywords = Association[(FileBaseName[#] -> keywordsOf[#]) & /@ symbolFiles];

(* tech notes go on the left under the guides, after a thick delimiter *)
tutorialTitle[f_] := Module[{m},
    m = StringCases[Import[f, "Text"],
            StartOfLine ~~ "Title:" ~~ Whitespace... ~~ t : Except["\n"].. :> t, 1];
    If[m === {}, FileBaseName[f], unquoteTitle[First[m]]]];
(* A backbone placeholder is frontmatter and nothing else. It belongs in the rail (it is the
   planned shape of the docs) but should not read as a written page, so mark the ones with no
   prose after the closing --- and let the stylesheet mute them. *)
tutorialFilledQ[f_] := StringLength @ StringTrim @ StringDelete[
    Import[f, "Text"], StartOfString ~~ "---" ~~ Shortest[___] ~~ "\n---"] > 0

(* an "application" keyword (vs the default "tutorial") sorts a tech note into the
   Applications group of the rail: worked analyses, kept apart from the pedagogical
   walkthroughs. *)
applicationQ[{_, _, _, kw_String}] := StringContainsQ[kw, "application"];

(* formats: a labeled panel on the left, between the guides and the tech notes; the deployed
   page of a format lives at Documentation/ref/format/<Name> *)
formats = If[DirectoryQ[formatsDir],
    SortBy[({FileBaseName[#], FileBaseName[#], keywordsOf[#]} &) /@ FileNames["*.md", formatsDir], First], {}];

tutorials = If[DirectoryQ[tutorialDir],
    SortBy[({FileBaseName[#], tutorialTitle[#], tutorialFilledQ[#], keywordsOf[#]} &) /@ FileNames["*.md", tutorialDir], First], {}];

(* ---- the guide tree (guides only; ancestor-path cycle break, duplicates allowed) ---- *)
buildGuide[name_, title_, seen_] :=
    If[ MemberQ[seen, name],
        Nothing,
        <|"name" -> name, "title" -> title, "type" -> "guide",
          "children" -> (buildGuide[#[[1]], #[[2]], Append[seen, name]] & /@ childGuides[name])|>
    ];

leafNode[name_] := <|"name" -> name, "title" -> guideTitle[name], "type" -> "guide", "children" -> {}|>;

tree = buildGuide[$rootGuide, guideTitle[$rootGuide], {}];
countNodes[n_] := 1 + Total[countNodes /@ Lookup[n, "children", {}]];

collectGuides[node_] := Join[{{"guide", node["name"]}}, Join @@ (collectGuides /@ Lookup[node, "children", {}])];

(* What the left rail lists.  With a hierarchy, the root guide is the shell's home and the rail
   starts at its children (PureMath's shape).  With none - the single-guide case this paclet is in
   today - the rail would be an empty <ul>, so list the root itself.  Either way, any guide the
   link graph never reaches is appended as a leaf, so a new guide is visible before it is linked. *)
reached = collectGuides[tree][[All, 2]];
orphanGuides = Sort @ Complement[Keys[nameToFile], reached];
railNodes = Join[
    If[ tree["children"] === {}, {tree}, tree["children"]],
    leafNode /@ orphanGuides
];

entries = DeleteDuplicates @ Join[
    collectGuides[tree],
    ({"guide", #} &) /@ orphanGuides,
    ({"ref", #} &) /@ symbolsAll,
    ({"ref/format", #[[1]]} &) /@ formats,
    ({"tutorial", #[[1]]} &) /@ tutorials
];
plural[n_, word_] := ToString[n] <> " " <> word <> If[n === 1, "", "s"];
say[plural[countNodes[tree] + Length[orphanGuides], "guide"], ", ",
    plural[Length[symbolsAll], "symbol"], ", ", plural[Length[formats], "format"], ", ", plural[Length[tutorials], "tutorial"],
    " -> ", plural[Length[entries], "page"]];

(* ---- DRYRUN: print the structure and stop (no cloud, no render) ---- *)
If[ Environment["DRYRUN"] === "1",
    Module[{show},
        show[n_, d_] := (
            Print[StringRepeat["  ", d], "+ ", n["name"],
                If[n["title"] =!= n["name"], " (" <> n["title"] <> ")", ""]];
            show[#, d + 1] & /@ Lookup[n, "children", {}];);
        show[#, 0] & /@ railNodes;
        If[ tutorials =!= {},
            Print["--- tutorials (left, under guides) ---"];
            Print["  = " <> #[[1]] <> " (" <> #[[2]] <> ")" <>
                If[TrueQ[applicationQ[#]], "  [application]", ""] <>
                If[TrueQ[#[[3]]], "", "  [stub]"]] & /@ tutorials];
        If[ formats =!= {},
            Print["--- formats (left, between guides and tutorials) ---"];
            Print["  = " <> #[[1]]] & /@ formats];
        Print["--- symbols (right rail): ", Length[symbolsAll], " ---"];
        Print["  " <> #] & /@ symbolsAll];
    say["DRYRUN, stopping before ", If[target === "site", "deploy", "render"]]; Exit[0]
];

(* ==================== local target: offline render of every page ==================== *)

If[ target === "local",
    Needs["PacletTools`"];
    Needs["DocumentationBuild`"];
    pacletDir = FileNameJoin[{repoRoot, "Genome"}];
    docsDir   = FileNameJoin[{pacletDir, "Documentation"}];
    (* build into a STAGING dir and swap at the end, so a running local server never serves a
       half-wiped site *)
    siteDirFinal = FileNameJoin[{repoRoot, "build", "local-docs"}];
    siteDir      = FileNameJoin[{repoRoot, "build", "local-docs.new"}];
    linkBase     = "WolframInstitute/Genome";
    PacletDirectoryLoad[pacletDir];
    If[ ! DirectoryQ[docsDir],
        say["no Documentation dir at ", docsDir, " - run build_notebooks.wls first"];
        Exit[1]
    ];

    (* Hash-keyed caching: .html-cache keeps each rendered page keyed by a hash of its SOURCE
       authoring notebook (+ $Version + salt), plus the shared web-asset bundles under "_assets".
       Unchanged pages copy from the cache; only changed/new pages touch the FrontEnd, so a
       no-change rebuild takes seconds instead of minutes. *)
    If[ DirectoryQ[siteDir], DeleteDirectory[siteDir, DeleteContents -> True]];
    CreateDirectory[siteDir, CreateIntermediateDirectories -> True];

    only       = Environment["GENOME_LOCAL_ONLY"];
    renderOpts = {"CompleteHTMLQ" -> True, "LinkBase" -> linkBase};
    $cacheOn   = Environment["GENOME_HTML_CACHE"] =!= "0";
    htmlCache  = FileNameJoin[{repoRoot, ".html-cache"}];
    assetCache = FileNameJoin[{htmlCache, "_assets"}];
    If[ $cacheOn && ! DirectoryQ[htmlCache], CreateDirectory[htmlCache, CreateIntermediateDirectories -> True]];
    typeOf[src_] := Which[
        StringContainsQ[src, "Guides"], "guide",
        StringContainsQ[src, "Tutorials"], "tutorial",
        StringContainsQ[src, "Formats"], "ref/format",
        True, "ref"];
    keyOf[src_] := Hash[{FileHash[src, "SHA256", "Base64Encoding"], $Version, "2"}, "SHA256", "HexString"];
    cachedOf[src_] := FileNameJoin[{htmlCache, keyOf[src] <> ".html"}];
    outOf[src_] := FileNameJoin[{siteDir, "html", typeOf[src], FileBaseName[src] <> ".html"}];
    (* A page is TWO artifacts, not one: <Name>.html plus Files/<Name>.en/ holding every
       rasterized output it shows (an ImportVCF page alone carries two dozen PNGs).  Caching only
       the HTML makes a cache-hit rebuild produce a site whose pages have no images - it looked
       right because the first, cold build renders both.  So the sidecar directory is cached and
       restored with its page. *)
    filesOf[src_] := FileNameJoin[{siteDir, "html", typeOf[src], "Files", FileBaseName[src] <> ".en"}];
    cachedFilesOf[src_] := FileNameJoin[{htmlCache, keyOf[src] <> ".files"}];
    srcPages = Join @@ (FileNames["*.nb", FileNameJoin[{docsDir, "English", #}], Infinity] & /@
        {"Guides", "ReferencePages", "Tutorials"});
    If[ srcPages === {},
        say["no authoring notebooks under ", FileNameJoin[{docsDir, "English"}],
            " - run build_notebooks.wls first"];
        Exit[1]
    ];

    If[ StringQ[only] && only =!= "",
        (* single-page smoke path (also stores into the cache) *)
        result = UsingFrontEnd @ DocumentationBuild`DocumentationBuildHTML[docsDir, siteDir,
            "SingleFile" -> FileNameJoin[Join[{docsDir, "English"}, FileNameSplit[only <> ".nb"]]],
            Sequence @@ renderOpts];
        say["render -> ", result],

        Module[{hits, misses},
            {hits, misses} = If[ $cacheOn,
                {Select[srcPages, FileExistsQ[cachedOf[#]] &], Select[srcPages, ! FileExistsQ[cachedOf[#]] &]},
                {{}, srcPages}];
            say["html cache ", Length[hits], " hit / ", Length[misses], " to render"];
            (* all-hit but no cached asset bundle: render one page anyway so the shared assets appear *)
            If[ misses === {} && ! DirectoryQ[assetCache],
                misses = {FileNameJoin[{docsDir, "English", "Guides", $rootGuide <> ".nb"}]}];
            Which[
                misses === {} && DirectoryQ[assetCache],
                (* all cached: no FrontEnd at all - copy assets + pages *)
                Scan[CopyDirectory[#, FileNameJoin[{siteDir, FileNameTake[#]}]] &, Select[FileNames["*", assetCache], DirectoryQ]],

                Length[misses] > 8,
                (* mostly cold: one whole-tree render beats a per-file call each (assets come along).
                   PureMath switches over at 400 because it has thousands of pages; this paclet has
                   two dozen, so the crossover sits an order of magnitude lower - a cold build is a
                   single render, and only a handful of edited pages take the per-file path. *)
                result = UsingFrontEnd @ DocumentationBuild`DocumentationBuildHTML[docsDir, siteDir, Sequence @@ renderOpts];
                say["full render -> ", Head[result]],

                True,
                (* few changes: render just the misses (shared assets come along with the first).
                   TimeConstrained per page - a whole-tree render can wedge on a dead FE with no way
                   to skip; here a hung page times out, is reported, and the run goes on. *)
                Do[
                    say["rendering ", FileBaseName[m]];
                    If[ TimeConstrained[
                            UsingFrontEnd @ DocumentationBuild`DocumentationBuildHTML[docsDir, siteDir,
                                "SingleFile" -> m, Sequence @@ renderOpts]; True,
                            300, False] =!= True,
                        say["TIMED OUT rendering ", FileBaseName[m], " - skipped"]],
                    {m, misses}]
            ];
            (* fill in the cache hits, page and image sidecar alike (renders above never overwrite
               them - different pages) *)
            Scan[
                Function[src, With[{out = outOf[src], fl = filesOf[src], cfl = cachedFilesOf[src]},
                    If[ ! FileExistsQ[out],
                        If[! DirectoryQ[DirectoryName[out]], CreateDirectory[DirectoryName[out], CreateIntermediateDirectories -> True]];
                        CopyFile[cachedOf[src], out]];
                    If[ DirectoryQ[cfl] && ! DirectoryQ[fl],
                        If[! DirectoryQ[DirectoryName[fl]], CreateDirectory[DirectoryName[fl], CreateIntermediateDirectories -> True]];
                        CopyDirectory[cfl, fl]]]],
                hits];
            (* store fresh renders + the shared asset bundles for the next run *)
            If[ $cacheOn,
                Scan[
                    Function[src, With[{out = outOf[src], fl = filesOf[src], cfl = cachedFilesOf[src]},
                        If[ FileExistsQ[out] && ! FileExistsQ[cachedOf[src]], CopyFile[out, cachedOf[src]]];
                        If[ DirectoryQ[fl] && ! DirectoryQ[cfl], CopyDirectory[fl, cfl]]]],
                    misses];
                If[ misses =!= {} || ! DirectoryQ[assetCache],
                    Quiet @ If[DirectoryQ[assetCache], DeleteDirectory[assetCache, DeleteContents -> True]];
                    CreateDirectory[assetCache, CreateIntermediateDirectories -> True];
                    Scan[If[DirectoryQ[#] && FileNameTake[#] =!= "html", CopyDirectory[#, FileNameJoin[{assetCache, FileNameTake[#]}]]] &,
                        FileNames["*", siteDir]]]]
        ]
    ];

    (* DocumentationBuildHTML writes pages under siteDir/html/{guide,ref,tutorial}/ and the shared
       web assets at siteDir/. The nav shell's loader builds page URLs as BASE + "/Documentation/" +
       id + ".html", so rename html -> Documentation to match (same depth, so the pages' ../../
       asset paths still resolve to siteDir). *)
    With[{h = FileNameJoin[{siteDir, "html"}], d = FileNameJoin[{siteDir, "Documentation"}]},
        If[ ! DirectoryQ[h],
            say["render produced no pages (", h, " missing) - aborting"]; Exit[1]];
        RenameDirectory[h, d]
    ];

    (* asset-path skew (WL 15.0): the generated pages reference language-assets-v2 but the shipped
       bundle is named language-assets - duplicate it so the header/global/guide CSS + JS resolve. *)
    With[{la = FileNameJoin[{siteDir, "language-assets"}], la2 = FileNameJoin[{siteDir, "language-assets-v2"}]},
        If[ DirectoryQ[la] && ! DirectoryQ[la2], CopyDirectory[la, la2]]];

    (* CHROME REPAIR.  DocumentationBuildHTML wraps every page in the wolfram.com chrome -
       global header band, sticky page header with a site-search form, left menu rail, a second
       copy of the See Also links - and the shipped bundle styles none of those containers, so
       offline they stack above the content as raw markup.  docs_local_page.css removes the
       chrome the offline build cannot support; inline it so a page is correct however it is
       opened, file:// included.  Applied AFTER the cache is written, so the cache keeps the
       untouched render and an edit to the sheet takes effect on the next build with no
       cache bust. *)
    With[{chrome = readAsset["docs_local_page.css"]},
        Scan[
            Function[page,
                With[{html = Import[page, "Text"]},
                    If[ StringContainsQ[html, "</head>"],
                        Export[page,
                            StringReplace[html,
                                "</head>" -> "<style>\n" <> chrome <> "</style>\n</head>", 1],
                            "Text"]]]],
            FileNames["*.html", FileNameJoin[{siteDir, "Documentation"}], Infinity]]
    ];
];

(* ==================== site target: connect and derive the account bases ==================== *)

If[ target === "site",
    (* $CloudRootDirectory is the account root (CloudObject[".../obj/wolframinstitute"]); both the paclet
       resource and our docs dir live under it, so deriving from it makes this run under any cloud
       id (local or CI) without hardcoding the account. *)
    If[ ! $CloudConnected,
        With[{u = Environment["WOLFRAM_CLOUD_USER"], p = Environment["WOLFRAM_CLOUD_PASSWORD"]},
            If[StringQ[u] && StringQ[p], CloudConnect[u, p], CloudConnect[]]]];
    If[ ! $CloudConnected, say["cloud connection failed"]; Exit[1] ];
    (* The same account pin publish.wls honours.  A wolframscript kernel arrives
       connected with the machine's recent-user store, which the desktop front
       end rewrites with ITS login on every notebook evaluation.  With
       GENOME_CLOUD_ACCOUNT set, a mismatched identity is replaced - but only
       with the environment credentials: CloudDisconnect[] clears the machine's
       saved login, and a bare CloudConnect[] cannot prompt here, so
       disconnecting without credentials in hand would leave no wolframscript
       kernel on the machine able to connect.  Without them, refuse and leave the
       connection alone. *)
    With[{want = Environment["GENOME_CLOUD_ACCOUNT"],
          rootOK = Function[w, MatchQ[$CloudRootDirectory, CloudObject[_String, ___]] &&
              StringEndsQ[First[$CloudRootDirectory], "/obj/" <> Last[StringSplit[w, "/"]]]]},
        If[ StringQ[want] && want =!= "" && ! rootOK[want],
            With[{u = Environment["WOLFRAM_CLOUD_USER"], p = Environment["WOLFRAM_CLOUD_PASSWORD"]},
                If[ ! (StringQ[u] && StringQ[p]),
                    say["kernel is connected as ", $CloudUserID, " but GENOME_CLOUD_ACCOUNT=", want,
                        " - set WOLFRAM_CLOUD_USER and WOLFRAM_CLOUD_PASSWORD; refusing, and not disconnecting"];
                    Exit[1]
                ];
                say["kernel arrived connected as ", $CloudUserID, " - reconnecting as ", u];
                CloudDisconnect[];
                CloudConnect[u, p]
            ];
            If[ ! TrueQ[$CloudConnected] || ! rootOK[want],
                say["could not connect as GENOME_CLOUD_ACCOUNT=", want, " - refusing to deploy"];
                Exit[1]
            ];
            say["reconnected as ", $CloudUserID]
        ]
    ];
    accountBase = First[$CloudRootDirectory];
    $base = accountBase <> "/" <> $resourceRel;
    say["account root ", accountBase];
];

(* ==================== the paclet front page (the resource shingle) ==================== *)

(* The shell frames the resource's Documentation/{guide,ref,tutorial} pages - and those are a
   DIFFERENT artifact from the resource shingle, the paclet's front page, which is where the
   install line, the References and the front-page examples live.  Nothing in the rail led there,
   so from this site the front page was unreachable; the rail now opens with an entry for it.

   The URL is the binding the site target already deploys against - the account root plus
   $resourceRel - so a different cloud id needs no edit here.

   Resolving it on the LOCAL target needs care, because $CloudConnected is not a free read:
   in wolframscript it performs an authentication handshake, a few seconds against a healthy
   cloud and unbounded against a slow or unreachable one, which is exactly the kind of stall a
   target that renders offline must not take on every build.  So the account is resolved at
   most once and then remembered in .html-cache/cloud-account.txt, and the one probe that can
   resolve it runs under a single time cap covering the connection check as well as the
   lookup.  Order: GENOME_CLOUD_ACCOUNT (an account id, or a full .../obj/<id> root), the
   remembered value, then that capped probe - and if all three come up empty the entry is left
   out rather than pointed somewhere wrong.  A site build, which is connected anyway, writes
   the remembered value as a side effect, so on a machine that has deployed once the local
   build never probes at all.  To point the entry elsewhere, set GENOME_CLOUD_ACCOUNT or
   delete the note. *)

trimSlash[u_String] := StringDelete[u, "/" ~~ EndOfString];

accountCacheFile = FileNameJoin[{repoRoot, ".html-cache", "cloud-account.txt"}];
rememberedAccount[] := If[ FileExistsQ[accountCacheFile],
    Replace[Quiet @ Import[accountCacheFile, "Text"],
        {s_String :> trimSlash[StringTrim[s]], _ -> ""}],
    ""];
(* rewritten rather than written-once, so a site build under a second cloud id corrects a
   stale note instead of leaving every later local build pointed at the first one *)
rememberAccount[u_String] := (
    If[ u =!= "" && rememberedAccount[] =!= u,
        Quiet @ CreateDirectory[DirectoryName[accountCacheFile], CreateIntermediateDirectories -> True];
        Quiet @ Export[accountCacheFile, u, "Text"]];
    u);
(* one cap over BOTH the handshake and the lookup, so an unreachable cloud costs 30s once
   rather than however long its connect happens to take, on every build *)
probeAccount[] := rememberAccount @ Replace[
    Quiet @ TimeConstrained[If[TrueQ[$CloudConnected], $CloudRootDirectory, None], 30],
    {CloudObject[u_String, ___] :> trimSlash[u], _ -> ""}];

accountRoot[] := With[{env = Environment["GENOME_CLOUD_ACCOUNT"], seen = rememberedAccount[]},
    Which[
        StringQ[env] && StringStartsQ[env, "http"], trimSlash[env],
        StringQ[env] && env =!= "",                 trimSlash[$CloudBase] <> "/obj/" <> env,
        seen =!= "",                                seen,
        True,                                       probeAccount[]
    ]
];

(* the site target already has it, and its value is what a later local build reuses *)
If[ ! StringQ[accountBase], accountBase = accountRoot[], rememberAccount[trimSlash[accountBase]]];
frontURL = If[ accountBase === "", "", accountBase <> "/" <> $resourceRel <> "/"];
say[If[ frontURL === "",
    "no cloud account resolved - front-page entry omitted (set GENOME_CLOUD_ACCOUNT)",
    "front page " <> frontURL]];

(* ==================== shared shell assembly ==================== *)

esc[s_] := StringReplace[ToString[s],
    {"&" -> "&amp;", "<" -> "&lt;", ">" -> "&gt;", "\"" -> "&quot;"}];

(* sidebar links carry data-id; the loader builds the page URL *)
aTag[id_, label_, cls_, kw_ : ""] :=
    "<a class=\"" <> cls <> "\" data-id=\"" <> esc[id] <> "\"" <>
        If[kw === "", "", " data-kw=\"" <> esc[kw] <> "\""] <>
        " href=\"#" <> esc[id] <> "\">" <> esc[label] <> "</a>";

liOf[node_] := Module[{kids = Lookup[node, "children", {}], a},
    a = aTag["guide/" <> node["name"], node["title"], "gd",
        Replace[Lookup[nameToFile, node["name"], None], {f_String :> keywordsOf[f], _ -> ""}]];
    If[ kids === {},
        "<li class=\"leaf\">" <> a <> "</li>",
        "<li class=\"branch\"><details><summary>" <> a <>
            "</summary><ul>" <> StringJoin[liOf /@ kids] <> "</ul></details></li>"
    ]
];

(* left rail: the guide tree, then - only when there are any - a thick delimiter and the tech
   notes in two labeled groups.  An empty Tutorials directory must not leave a labeled empty list
   hanging under the guides. *)
tutorialGroup[label_, items_, cls_] :=
    If[ items === {}, "",
        StringJoin[
            "<div class=\"nav-label\">", label, "</div>",
            "<ul class=\"nav-tutorials\">",
            StringJoin[("<li>" <> aTag["tutorial/" <> #[[1]], #[[2]],
                If[TrueQ[#[[3]]], cls, "tut tut-stub"], #[[4]]] <> "</li>" &) /@ items],
            "</ul>"]];

(* The rail carries no entry for the front page: on the site the shingle is already what the shell
   frames at home, and the brand in the header goes back to it, so a card saying so was a label for
   the page the reader starts on. *)
formatsGroup = If[ formats === {}, "",
    StringJoin[
        "<div class=\"nav-sep\"></div>",
        "<div class=\"nav-label\">Formats</div>",
        "<ul class=\"nav-tutorials\">",
        StringJoin[("<li>" <> aTag["ref/format/" <> #[[1]], #[[2]], "tut", #[[3]]] <> "</li>" &) /@ formats],
        "</ul>"]];

sidebar = StringJoin[
    "<div class=\"nav-label\">", If[Length[railNodes] === 1, "Guide", "Guides"], "</div>",
    "<ul class=\"nav-root\">", StringJoin[liOf /@ railNodes], "</ul>",
    formatsGroup,
    If[ tutorials === {}, "", "<div class=\"nav-sep\"></div>"],
    tutorialGroup["Tutorials", Select[tutorials, ! applicationQ[#] &], "tut"],
    tutorialGroup["Applications", Select[tutorials, applicationQ], "app"]
];

(* right rail: the symbols, flat and alphabetical *)
symbolsHTML = StringJoin[
    "<div class=\"nav-label\">Symbols</div>",
    "<ul class=\"nav-symbols\">",
    StringJoin[("<li>" <> aTag["ref/" <> #, #, "sym", Lookup[symbolKeywords, #, ""]] <> "</li>" &) /@ symbolsAll],
    "</ul>"
];

(* BASE and HOME are the only per-target differences in the shell: the site frames the deployed
   resource's live embed pages; local frames the just-rendered files with a relative BASE, whose
   cloud-embedder prefetch (gated on BASE containing "/obj/") self-skips. *)
{base, homeURL} = If[ target === "site",
    {$base, $base <> "/"},
    {".", "./Documentation/guide/" <> $rootGuide <> ".html"}];

(* the notebook host page (docs_page.html): a standalone window-scrolled document that injects the
   /statichtml pre-render into the very container it hands the embedder, so hydration is in place
   and the shell's iframe never swaps documents. Site-only; the local target has no embed pages,
   and an empty PAGE makes the shell frame the built files as before. *)
pageURL = If[ target === "site", accountBase <> "/" <> $target <> "Page", ""];

(* The header's "Resource page" button follows whatever is open to its cloud twin, so it means
   something only where a cloud twin exists.  On the local target BASE is "." and the button
   resolves to local files - at home to "./", the shell reopening itself in a new tab - while the
   rail's front-page entry, an out-arrow away from it, already goes to the deployed resource
   properly.  Two near-identical affordances of which one is dead is worse than one, so local
   gets no button and docs_site.js's setTwin() no-ops on the missing element. *)
twinButton = If[ target =!= "site", "",
    StringJoin[
        "<a class=\"home\" id=\"resourcelink\" href=\"", esc[base], "/\" target=\"_blank\" rel=\"noopener\">",
        "Resource page<svg viewBox=\"0 0 24 24\"><path d=\"M7 17 17 7M9 7h8v8\" /></svg></a>"]];

jsContent = TemplateApply[StringTemplate[readAsset["docs_site.js"]],
    <|"BASE" -> base, "HOME" -> homeURL, "PAGE" -> pageURL, "ROOT" -> $rootGuide|>];
indexHTML = TemplateApply[
    StringTemplate[readAsset["docs_site.html"]],
    <|
        "title"   -> esc[tree["title"]],
        "css"     -> readAsset["docs_site.css"],
        "twin"    -> twinButton,
        "homeURL" -> esc[homeURL],
        "sidebar" -> sidebar,
        "symbols" -> symbolsHTML,
        "js"      -> jsContent
    |>
];
If[ ! StringQ[indexHTML], say["index assembly failed"]; Exit[1] ];
say["index.html assembled, ", StringLength[indexHTML], " chars"];

(* ==================== deliver ==================== *)

If[ target === "local",
    Export[FileNameJoin[{siteDir, "index.html"}], indexHTML, "Text"];
    (* atomic-ish swap: the old site serves until this instant *)
    If[ DirectoryQ[siteDirFinal], DeleteDirectory[siteDirFinal, DeleteContents -> True]];
    RenameDirectory[siteDir, siteDirFinal];
    say["swapped into ", siteDirFinal];
    say["serve -> python3 -m http.server --directory ", siteDirFinal, " 8000   (http://localhost:8000)"],

    (* site: deploy just our shell page; the center iframe loads the resource's live embed pages *)
    Module[{cleanCloud, result},
        cleanCloud[co_] := (Module[{ch = Quiet @ CloudObjects[co]}, If[ListQ[ch], cleanCloud /@ ch]]; Quiet @ DeleteObject[co]);
        cleanCloud[CloudObject[$target]];   (* clear a stale re-host directory if present *)
        result = CloudExport[
            TemplateApply[StringTemplate[readAsset["docs_page.html"]], <|"BASE" -> base|>],
            {"String", "text/html"}, CloudObject[$target <> "Page"], Permissions -> "Public"];
        If[ MatchQ[result, _CloudObject],
            Print["published: ", First[result]],
            say["host page deploy failed: ", result]; Exit[1]
        ];
        result = CloudExport[indexHTML, {"String", "text/html"}, CloudObject[$target], Permissions -> "Public"];
        If[ MatchQ[result, _CloudObject],
            Print["published: ", First[result]],
            say["deploy failed: ", result]; Exit[1]
        ]
    ]
];
Exit[0]

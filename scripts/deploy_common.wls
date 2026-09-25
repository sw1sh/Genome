#!/usr/bin/env wolframscript
(* ::Package:: *)

(* Shared Wolfram Cloud deploy machinery for the Genome paclet
   (WolframInstitute/Genome via publish.wls).

   Get this file, then drive a deploy with:
     pmInstallDeployPatches[pacletName, context]  - all the generic deploy fixes + the
         pacletDeclaredSymbols pin (the only paclet-specific patch; built from Names[context<>"*"]).
     pmInjectHero[image]                           - inject a shingle hero image (optional).
     pmInstallTreeSidebar[guidesDir, rootGuide]    - hierarchical Guides rail (optional; the
         default stock rail is flat - fine for paclets with a single guide, and this call
         self-disables when the guides carry no guide-to-guide down-links).
     pmScrapeAndDeploy[defNb, pacletName]          - headless scrape + public CloudDeploy.

   Every fix here is documented at its definition; they were all root-caused against
   PacletResource's Deploy.m / Notebooks.m / Utilities.m. See the cloud-deploy memory. *)

Needs["PacletResource`"]
(* The scrape/deploy path calls PacletTools`PacletExtensionFiles to enumerate the doc files,
   but under a headless Needs sequence PacletTools is not autoloaded, so the call stays symbolic
   and cascades into Values::invrl / FileNameSplit::fstr / Complement::heads (and a downstream
   StringTake::take on the resulting empty string). Loading it explicitly is the actual fix. *)
Needs["PacletTools`"]

(* ====================================================================== *)
(* Worker kernels.  Every parallel step here launches its workers through   *)
(* pmLaunchWorkers, sized by GENOME_DOCBUILD_KERNELS - the same count the   *)
(* page build uses, and the one every documented publish sets to 2.  The    *)
(* scrape used to launch Max[8, $ProcessorCount] on its own: sixteen workers *)
(* on this machine, each starting a front end and a kernel of its own, and   *)
(* with other sessions holding licence seats they all sat at 0% CPU for half  *)
(* an hour without failing (2026-09-25).  A warm scrape cache hid it: with    *)
(* nothing to transform, the pool never did any work.                         *)
(* ====================================================================== *)
pmWorkerCount[] := With[{e = Environment["GENOME_DOCBUILD_KERNELS"]},
	If[ StringQ[e] && StringMatchQ[e, DigitCharacter ..] && ToExpression[e] > 0,
		ToExpression[e],
		Max[2, Min[8, $ProcessorCount]]]]

pmLaunchWorkers[timeout_] :=
	If[ Length[Kernels[]] === 0,
		Print["deploy: launching ", pmWorkerCount[], " worker kernels"];
		Quiet @ TimeConstrained[LaunchKernels[pmWorkerCount[]], timeout, CloseKernels[]]]

(* ====================================================================== *)
(* Cloud directory records.                                                 *)
(* A cloud directory whose own metadata record has gone missing still SERVES  *)
(* its children: <dir>/HeroImage.png resolves, <dir> does not.  It disappears  *)
(* from its parent's listing, CloudObjectInformation and CloudObjects on it    *)
(* fail with cloudnf, and the deploy dies at "Deploying ResourceObject" on      *)
(* CloudObject::cloudnf - after a full successful build, and with the paclet     *)
(* archive and every page already uploaded, so nothing in the log says what      *)
(* is wrong.  The whole resource was unreachable for a day that way.             *)
(* CreateDirectory writes a fresh record and the children reattach untouched.    *)
(* ====================================================================== *)
pmCloudDirectoryRecordQ[co_] := Quiet @ Check[CloudObjectInformation[co, "FileType"], $Failed] =!= $Failed

pmEnsureCloudDirectory[co_] :=
	If[ ! pmCloudDirectoryRecordQ[co],
		Print["deploy: cloud directory record missing - recreating ", First[co]];
		If[ Head[Quiet @ Check[CreateDirectory[co], $Failed]] =!= CloudObject,
			Print["deploy: WARNING - could not recreate ", First[co]]]]

pmEnsureCloudDirectories[root_, relDirs_List] := Scan[
	pmEnsureCloudDirectory,
	Prepend[FileNameJoin[Prepend[#, root]] & /@ SortBy[relDirs, Length], root]]

(* The deploy root is the one directory that must NOT be conjured on a first
   deploy - an empty one there is harmless, but creating it would hide a
   genuinely-new resource behind a directory the shingle then deploys into.
   So repair it only on the evidence that it was deployed before: its own
   record is gone while the index page it serves is still there. *)
pmRepairDeployRoot[co_] :=
	If[ ! pmCloudDirectoryRecordQ[co] && pmCloudDirectoryRecordQ[FileNameJoin[{co, "index.html"}]],
		Print["deploy: deploy root has children but no record of itself - repairing"];
		pmEnsureCloudDirectory[co]]

(* The record is only half of a deploy root.  Resource resolution runs entirely
   through the object's MetaInformation: ResourceObject[CloudObject[url]] reads
   its "ResourceLocation" and CloudGets THAT, and with the key absent it falls
   back to CloudGet on the directory itself - which can never succeed, so
   PacletInstall[ResourceObject[url]] dies on Get::noopen while every page, the
   hero and the front page serve perfectly.  CreateDirectory does not write it
   and neither does the shingle CloudDeploy onto an existing root, so rebuild it
   from the ResourceObject.wl the tree already carries. *)
pmEnsureResourcePointer[co_] := Module[{meta, loc, res},
	If[ ! pmCloudDirectoryRecordQ[co], Return[Null]];
	meta = Replace[Lookup[Options[co, MetaInformation], MetaInformation, {}], Except[_List] -> {}];
	If[ ! FreeQ[meta, "ResourceLocation"], Return[Null]];
	loc = FileNameJoin[{co, "ResourceObject.wl"}];
	res = Quiet @ Check[CloudGet[loc], $Failed];
	If[ Head[res] =!= ResourceObject,
		Print["deploy: WARNING - deploy root carries no ResourceLocation and ",
			"ResourceObject.wl is unreadable; the resource will not resolve"];
		Return[Null]];
	Print["deploy: deploy root carries no ResourceLocation - restoring it"];
	SetOptions[co, MetaInformation -> {
		"Description" -> res["Description"],
		"ResourceLocation" -> loc,
		"ResourceType" -> res["ResourceType"],
		"UUID" -> res["UUID"],
		"Name" -> res["Name"]}]
]

(* ====================================================================== *)
(* No-purge in-place documentation merge.                                   *)
(* The stock "DocumentationNotebooks" deploy CopyDirectory's into a target   *)
(* it first DeleteObject's, 404ing every page for the whole redeploy. This   *)
(* copies each processed notebook in place (overwrite, no purge) and returns *)
(* EXACTLY those .nb CloudObjects (one per processDir file) as the resource's *)
(* "DocumentationNotebooks" - returning recursiveCloudObjects instead would   *)
(* also pull in stale .html, which createSidebarHTML maps .html -> .html,     *)
(* doubling every page in the nav rail. *)
(* ====================================================================== *)
pmMergeDeployDocs[root_, dir_, opts : OptionsPattern[CloudObject]] :=
	Module[{target, files, total, tasks, manifest, hashes, toUpload, deployed},
		target = FileNameJoin[{root, "Documentation"}];
		files = Select[FileNames["*", dir, Infinity], ! DirectoryQ[#] &];
		total = Length[files];
		(* Pre-compute each file's destination CloudObject HERE (addEmbeddedOptions is a
		   PacletResource internal), so the parallel workers - which inherit this kernel's cloud
		   login - only have to CopyFile. *)
		tasks = Map[
			Function[file,
				Module[{parts = Drop[FileNameSplit[file], Length[FileNameSplit[dir]]], co},
					co = FileNameJoin[Join[{target}, parts]];
					{file, PacletResource`Private`addEmbeddedOptions[co], co, FileNameJoin[parts]}
				]
			],
			files
		];
		(* Upload DELTA: a cloud-side manifest (rel -> sha of the processed file) records what the
		   target already holds; only changed/missing pages upload. The scrape cache makes unchanged
		   pages byte-stable, so the hashes agree across runs. Cloud-side because the tarball save
		   runs before the deploy phase. PM_UPLOAD_DELTA=0 (or deleting GenomeDeployManifest.wl)
		   forces a full re-upload - the recovery for any cloud-side drift (manual page deletes). *)
		manifest = If[ Environment["PM_UPLOAD_DELTA"] === "0", <||>,
			Replace[Quiet @ Check[CloudGet[CloudObject["GenomeDeployManifest.wl"]], <||>], Except[_Association] -> <||>]];
		hashes = Association @ Map[#[[4]] -> FileHash[#[[1]], "SHA256", "Base64Encoding"] &, tasks];
		toUpload = Select[tasks, Lookup[manifest, #[[4]]] =!= hashes[#[[4]]] &];
		Print["deploy: merging ", total, " documentation pages into ", First[target],
			" (", Length[toUpload], " changed, ", total - Length[toUpload], " already up to date; no purge)"];
		(* every directory this merge writes into must hold a record of itself *)
		pmEnsureCloudDirectories[root,
			Prepend[#, "Documentation"] & /@ Prepend[
				DeleteDuplicates[
					Most /@ (Drop[FileNameSplit[#], Length[FileNameSplit[dir]]] & /@ files)],
				{}]];
		pmLaunchWorkers[90];
		(* Block-wise upload with MASTER-side progress prints: worker Print forwarding is swallowed
		   inside the ScrapeResource/CloudDeploy output capture, master prints land. *)
		Module[{done = 0},
			Do[
				ParallelMap[(CopyFile[#[[1]], #[[2]], OverwriteTarget -> True]; #[[3]]) &, block];
				done += Length[block];
				Print["deploy: uploaded ", done, "/", Length[toUpload], " pages"],
				{block, Partition[toUpload, UpTo[50]]}
			]
		];
		If[ Environment["PM_UPLOAD_DELTA"] =!= "0",
			Quiet @ Check[
				(CloudPut[hashes, CloudObject["GenomeDeployManifest.wl"]];
				 SetOptions[CloudObject["GenomeDeployManifest.wl"], Permissions -> "Private"]),
				Print["deploy: WARNING - manifest save failed; next run re-uploads everything"]]];
		(* the resource needs EVERY page's CloudObject (uploaded or already present) *)
		deployed = tasks[[All, 3]];
		(* Always run the permissions pass. It used to be skipped when nothing uploaded, because
		   enumerating the tree cost ~15 min - but that skip assumed the previous pass had SUCCEEDED,
		   and a failed enumeration returns {} silently ("setting permissions on 0 directories"),
		   so the tree could stay private forever with every run declaring itself unchanged. With
		   pmCloudDirectories the whole pass is ~25s, so there is nothing left to save by skipping. *)
		If[ Environment["PM_SKIP_PERMS"] === "1",
			Print["deploy: permissions pass skipped (PM_SKIP_PERMS=1)"],
			PacletResource`Private`setCODirectoryPermissions[CloudObject[target], OptionValue[CloudObject, {opts}, Permissions]]];
		Print["deploy: documentation merge complete (", total, " pages, ", Length[toUpload], " uploaded)"];
		deployed
	]

(* ====================================================================== *)
(* pmParallelizeScrapeProcessing - the scrape's ~30-min silent core is       *)
(* PacletResource`Notebooks`ProcessNotebookForEmbedding[dir, ...]: a SERIAL   *)
(* single-kernel Map of the per-notebook web transform (C2C PacletSymbol      *)
(* wrapping, cloud link rewriting, re-serialization) over every built page.   *)
(* Each per-file call is independent - own read/transform/write, and the      *)
(* $validRefs dynamic rebinds from the "PackageURIs" option inside the        *)
(* per-file form - so replace the directory clause with a ParallelMap.        *)
(* Workers lazily Needs the machinery themselves (vendor contexts are not in  *)
(* $DistributedContexts, so nothing vendor gets auto-shipped); pages whose    *)
(* parallel transform fails are retried serially on the master so a flaky     *)
(* worker can never silently DROP a page from the deployed resource.          *)
(* Emits "scrape:"/"scrape>" markers for the CI status page.                  *)
(* PM_PARALLEL_SCRAPE=0 restores the stock serial behavior.                   *)
(* ====================================================================== *)
pmParallelizeScrapeProcessing[] := (
	If[ Environment["PM_PARALLEL_SCRAPE"] === "0", Return[Null, CompoundExpression]];
	Quiet @ Needs["PacletResource`"];
	If[ DownValues[PacletResource`Notebooks`ProcessNotebookForEmbedding] === {},
		Print["deploy: WARNING - ProcessNotebookForEmbedding not loaded; scrape stays serial"];
		Return[Null, CompoundExpression]
	];
	Unprotect[PacletResource`Notebooks`ProcessNotebookForEmbedding];
	(* identical LHS pattern to the stock directory clause -> this assignment REPLACES it.
	   The per-file form re-derives $validRefs from the "PackageURIs" option (toValidRefs), so the
	   workers need no ambient Block state as long as that option is EXPLICIT - resolve the
	   Automatic case from the master's ambient value up front. *)
	PacletResource`Notebooks`ProcessNotebookForEmbedding[
		dir_? DirectoryQ, type_, opts : OptionsPattern[]
	] :=
	Module[{files, os, processed, failedIdx, pmHits = {}, missRes = {}},
		files = FileNames["*.nb", dir, Infinity, IgnoreCase -> True];
		os = {opts};
		If[ (FreeQ[os, "PackageURIs"] || ! FreeQ[os, HoldPattern["PackageURIs" -> Automatic]]) &&
				ValueQ[PacletResource`Notebooks`Private`$validRefs],
			os = Append[DeleteCases[os, HoldPattern["PackageURIs" -> _]],
				"PackageURIs" -> PacletResource`Notebooks`Private`$validRefs]];
		If[ Length[files] < 24,
			(* small sets (example notebooks etc.): stock serial path *)
			processed = Map[PacletResource`Notebooks`ProcessNotebookForEmbedding[#, type, Sequence @@ os] &, files],

			(* scrape CACHE: the transform is deterministic per source file (in-place under
			   OverwriteTarget), so key the OUTPUT by a hash of the source + kernel version + salt and
			   copy hits instead of re-transforming. The cache dir rides the CI cache tarball.
			   PM_SCRAPE_CACHE=0 disables. *)
			Module[{cacheOn, cacheDir, keyOf, cacheFile, hitQ},
				cacheOn = Environment["PM_SCRAPE_CACHE"] =!= "0";
				cacheDir = FileNameJoin[{Directory[], ".scrape-cache"}];
				If[ cacheOn && ! DirectoryQ[cacheDir], Quiet @ CreateDirectory[cacheDir]];
				keyOf[f_] := Hash[{FileHash[f, "SHA256", "Base64Encoding"], $Version, "1"}, "SHA256", "HexString"];
				cacheFile = If[cacheOn, AssociationMap[FileNameJoin[{cacheDir, keyOf[#] <> ".nb"}] &, files], <||>];
				hitQ = If[cacheOn, AssociationMap[FileExistsQ[cacheFile[#]] &, files], AssociationMap[False &, files]];
				pmHits = Pick[Keys[hitQ], Values[hitQ], True];
				Scan[Quiet @ CopyFile[cacheFile[#], #, OverwriteTarget -> True] &, pmHits];
				files = Pick[Keys[hitQ], Values[hitQ], False];   (* misses still to transform *)
				Print["scrape: cache ", Length[pmHits], " hit / ", Length[files], " to transform"];
				(* store a freshly-transformed output under its SOURCE key (hash taken pre-transform
				   would differ - key from the cacheFile map built before any transform ran) *)
				$pmScrapeCacheStore = Function[f, If[cacheOn && KeyExistsQ[cacheFile, f] && FileExistsQ[f], Quiet @ CopyFile[f, cacheFile[f], OverwriteTarget -> True]]];
			];

			Print["scrape: processing ", Length[files], " documentation notebooks in parallel"];
			pmLaunchWorkers[240];
			(* block-wise with MASTER-side progress prints: worker Print forwarding is swallowed
			   inside the ScrapeResource output capture, master prints reach the log *)
			missRes = Module[{done = 0, res = {}, blockRes},
				Do[
					blockRes = With[{ty = type, o = os},
						ParallelMap[
							Function[f, Module[{r},
								(* lazy self-init: works on original AND resurrected kernels *)
								If[ ! TrueQ[$pmScrapeReady],
									Needs["DefinitionNotebookClient`"]; Quiet @ Needs["PacletResource`"];
									Off[StringTake::take]; Off[FrontEndObject::notavail]; $pmScrapeReady = True];
								(* classify by RETURN VALUE (path String or a legit Missing), never by
								   messages - a benign warning must not get a page dropped. TimeConstrained:
								   a dead-FE worker must time out into the serial retry, not stall the block. *)
								r = Quiet @ TimeConstrained[
									PacletResource`Notebooks`ProcessNotebookForEmbedding[f, ty, Sequence @@ o], 300, $TimedOut];
								If[ MatchQ[r, _String | _Missing], r, Missing["ProcessingFailed"]]
							]],
							block
						]];
					Scan[Print["scrape> FAIL ", FileNameTake[#]] &,
						Pick[block, MatchQ[Missing["ProcessingFailed"]] /@ blockRes]];
					res = Join[res, blockRes];
					done += Length[block];
					Print["scrape: processed ", done, "/", Length[files], " pages"],
					{block, Partition[files, UpTo[64]]}
				];
				res
			];
			(* master retry for parallel failures - a page must never be dropped by a flaky worker *)
			failedIdx = Flatten @ Position[missRes, Missing["ProcessingFailed"], {1}, Heads -> False];
			If[ failedIdx =!= {},
				Print["scrape: retrying ", Length[failedIdx], " page(s) serially on the master kernel"];
				Scan[
					Function[i, Module[{r},
						r = Quiet @ TimeConstrained[
							PacletResource`Notebooks`ProcessNotebookForEmbedding[files[[i]], type, Sequence @@ os], 600, $TimedOut];
						missRes[[i]] = If[MatchQ[r, _String | _Missing], r, Missing["ProcessingFailed"]];
						Print["scrape> ", If[MatchQ[missRes[[i]], Missing["ProcessingFailed"]], "FAIL ", "ok "],
							FileNameTake[files[[i]]], " (serial retry)"]]],
					failedIdx]];
			(* store freshly-transformed outputs into the scrape cache; join hits + misses *)
			If[ ValueQ[$pmScrapeCacheStore], Scan[$pmScrapeCacheStore, Cases[missRes, _String]]];
			processed = Join[pmHits, missRes]
		];
		DeleteMissing @ processed
	];
	Print["deploy: parallel scrape processing installed (PM_PARALLEL_SCRAPE=0 to disable)"]
);

(* ====================================================================== *)
(* pmCloudDirectories - the directory tree under a cloud object, cheaply.    *)
(* The vendor walker discovers a leaf by calling CloudObjects on it and      *)
(* getting {} back: one serial HTTPS round trip per PAGE (~0.36s), so a      *)
(* 3000-page deploy spends 18+ min proving that files are files. Only the    *)
(* directories are wanted. Every deployed page carries an extension          *)
(* (.nb/.html) and every directory carries none, so only extension-less      *)
(* children are probed - an unfamiliar extension stays a candidate, so a     *)
(* dotted directory name is still found. Probes drop from #pages to #dirs.   *)
(* CloudObjectInformation cannot do this: it is not batched server-side      *)
(* (0.44s per object, worse than probing). PM_FAST_PERMS=0 restores the      *)
(* vendor walk.                                                             *)
(* ====================================================================== *)
$pmLeafExtensions = {
	"nb", "html", "htm", "m", "wl", "wls", "wxf", "mx", "txt", "json", "xml",
	"css", "js", "png", "gif", "jpg", "jpeg", "svg", "pdf", "zip", "gz", "paclet"
};

pmDirCandidateQ[co_CloudObject] :=
	! MemberQ[$pmLeafExtensions, ToLowerCase @ FileExtension @ FileNameTake @ First @ co];

pmCloudDirectories[co_CloudObject] := Module[{dirs = {}, walk},
	walk[dir_] := With[{kids = Replace[Quiet @ Check[CloudObjects[dir], {}], Except[_List] -> {}]},
		If[ kids =!= {},
			AppendTo[dirs, dir];
			Scan[walk, Select[kids, pmDirCandidateQ]]]];
	walk[co];
	dirs
];

pmSaveEmbedManifest[] := If[ TrueQ[$pmEmbedManifestDirty] && AssociationQ[$pmEmbedManifest],
	Quiet @ Check[
		(CloudPut[$pmEmbedManifest, CloudObject["GenomeEmbedManifest.wl"]];
		 SetOptions[CloudObject["GenomeEmbedManifest.wl"], Permissions -> "Private"];
		 $pmEmbedManifestDirty = False;
		 Print["deploy: embed manifest saved (", Length[$pmEmbedManifest], " pages)"]),
		Print["deploy: WARNING - embed manifest save failed; next run regenerates embeds"]]];

(* ====================================================================== *)
(* pmInstrumentDeployProgress - make the whole vendor deploy narrate itself. *)
(* setDNCProgress is called at EVERY step of the PacletResource deploy       *)
(* (incl. per-page "Creating documentation page: X" in the embed loop) but   *)
(* only sets an invisible notebook-UI variable - route it to Print too, and  *)
(* the entire post-merge phase logs for free. The permissions pass           *)
(* (setCODirectoryPermissions) is a serial SetPermissions Scan over the      *)
(* cloud directory tree - parallelize it in blocks with progress prints.     *)
(* ====================================================================== *)
pmInstrumentDeployProgress[] := (
	Quiet @ Needs["PacletResource`"];
	(* 1: progress events -> the log (keep the UI assignment for fidelity) *)
	If[ DownValues[PacletResource`Private`setDNCProgress] =!= {},
		Unprotect[PacletResource`Private`setDNCProgress];
		PacletResource`Private`setDNCProgress[expr_] := (
			Print["deploy: ", expr];
			DefinitionNotebookClient`$StripeProgressDisplay = expr
		);
		Print["deploy: vendor progress events routed to the log"],
		Print["deploy: WARNING - setDNCProgress not found; vendor steps stay silent"]
	];
	(* 2: parallel + logged permissions pass (identical LHS -> replaces the serial clause;
	   the more-specific Automatic clause is untouched) *)
	If[ DownValues[PacletResource`Private`setCODirectoryPermissions] =!= {},
		Unprotect[PacletResource`Private`setCODirectoryPermissions];
		PacletResource`Private`setCODirectoryPermissions[HoldPattern[co_CloudObject], perm_] :=
		Module[{dirs, done = 0, fails = 0, t},
			Print["deploy: enumerating cloud directories for permissions"];
			{t, dirs} = AbsoluteTiming @ If[Environment["PM_FAST_PERMS"] === "0",
				Quiet @ Check[
					PacletResource`Private`recursiveCloudObjects[co, "Association"]["Directories"], {}],
				pmCloudDirectories[co]];
			If[ ! ListQ[dirs], dirs = {}];
			Print["deploy: enumerated in ", Round[t, 0.1], "s"];
			If[ dirs === {},
				Print["deploy: WARNING - enumeration found no directories; the tree keeps its old permissions"]];
			Print["deploy: setting permissions on ", Length[dirs], " directories"];
			Do[
				If[ Length[Kernels[]] > 0,
					fails += Count[ParallelMap[Quiet @ Check[SetPermissions[#, perm]; 0, 1] &, block], 1],
					Scan[(fails += Quiet @ Check[SetPermissions[#, perm]; 0, 1]) &, block]];
				done += Length[block];
				Print["deploy: permissions ", done, "/", Length[dirs], " directories",
					If[fails > 0, " (" <> ToString[fails] <> " failed)", ""]],
				{block, Partition[dirs, UpTo[32]]}
			];
			Quiet @ SetPermissions[co, perm];
			co
		];
		Print["deploy: parallel permissions pass installed"],
		Print["deploy: WARNING - setCODirectoryPermissions not found; permissions stay serial"]
	];
	(* 3: embed-page DELTA. Each embed page is a pure function of (resource info, sidebar html, url)
	   - a CloudDeploy'd Delayed template - so a per-url signature manifest lets unchanged pages skip
	   their CloudDeploy entirely (the dominant warm deploy cost: ~22 min for ~2000 pages). Content
	   edits do not change the wrapper; only page add/remove/rename (sidebar/urls) or resource-info
	   changes do. Misses run a faithful reimplementation of the tiny stock body (all deps checked
	   below); the manifest is saved by pmScrapeAndDeploy after the deploy. PM_EMBED_DELTA=0 disables. *)
	If[ Environment["PM_EMBED_DELTA"] =!= "0" &&
			DownValues[PacletResource`Private`createDocumentationEmbedPage] =!= {} &&
			DownValues[PacletResource`Private`shingleTemplate] =!= {} &&
			DownValues[PacletResource`Private`staticHTMLURL] =!= {} &&
			DownValues[PacletResource`Private`deployDelayedEmbedTemplate] =!= {},
		Unprotect[PacletResource`Private`createDocumentationEmbedPage];
		PacletResource`Private`createDocumentationEmbedPage[as_Association, sidebar_String, url_String] :=
		Module[{sig, template, nbURL, staticURL, copts, params, r},
			If[ ! AssociationQ[$pmEmbedManifest],
				$pmEmbedManifest = Replace[Quiet @ Check[CloudGet[CloudObject["GenomeEmbedManifest.wl"]], <||>], Except[_Association] -> <||>];
				$pmEmbedManifestDirty = False];
			(* context = the SIDEBAR only, hashed once per session. Two lessons cooked in: hashing the
			   resource-info assoc per call cost ~1s x 1989 (it embeds every page's skeleton data), and
			   including it at all churned the signature every run - each scrape mints a fresh resource
			   (UUID/dates), so nothing ever matched. The wrapper's real variance is (sidebar, url):
			   the sidebar changes exactly when pages are added/removed/retitled. A genuine
			   resource-info change (e.g. new hero) needs a manual: delete GenomeEmbedManifest.wl. *)
			If[ ! StringQ[$pmEmbedCtxSig],
				$pmEmbedCtxSig = Hash[sidebar, "SHA256", "HexString"];
				Print["deploy: embed context sig ", StringTake[$pmEmbedCtxSig, 12],
					" (manifest ", Length[$pmEmbedManifest], " pages)"]];
			sig = Hash[{$pmEmbedCtxSig, url}, "SHA256", "HexString"];
			If[ Lookup[$pmEmbedManifest, url] === sig,
				PacletResource`Private`setDNCProgress["Documentation page unchanged: " <> FileBaseName[url]];
				CloudObject[url],
				(* faithful stock body (Deploy.m createDocumentationEmbedPage), System Enclose *)
				r = Enclose @ Module[{},
					PacletResource`Private`setDNCProgress["Creating documentation page: " <> FileBaseName[url]];
					template  = Confirm @ PacletResource`Private`shingleTemplate["DocumentationPage"];
					nbURL     = StringReplace[url, ".html" ~~ EndOfString -> ".nb"];
					staticURL = ConfirmBy[PacletResource`Private`staticHTMLURL[nbURL], StringQ];
					copts     = Flatten @ {PacletResource`Private`$cloudObjectOpts};
					params    = ConfirmBy[<|KeyDrop[as, "DefinitionNotebook"], "NotebookURL" -> nbURL, "NavSidebar" -> sidebar|>, AssociationQ];
					PacletResource`Private`deployDelayedEmbedTemplate[url, template, params, staticURL, copts]];
				If[ ! FailureQ[r],
					$pmEmbedManifest[url] = sig;
					$pmEmbedManifestDirty = True;
					(* checkpoint every 250 pages: saving only after the whole deploy meant an interrupted
					   run threw away every embed page it had already made - a crash at 2000 of 3017 cost
					   all 2000, because the next run trusts the manifest, not the cloud *)
					$pmEmbedSinceSave = 1 + Replace[$pmEmbedSinceSave, Except[_Integer] -> 0];
					If[ $pmEmbedSinceSave >= 250, pmSaveEmbedManifest[]; $pmEmbedSinceSave = 0]];
				r]
		];
		Print["deploy: embed-page delta installed (PM_EMBED_DELTA=0 to disable)"],
		If[ Environment["PM_EMBED_DELTA"] =!= "0",
			Print["deploy: WARNING - embed-page internals not all found; embeds regenerate every run"]]
	];
);

(* ====================================================================== *)
(* pmInstallDeployPatches - apply every generic deploy fix, plus the         *)
(* paclet-specific pacletDeclaredSymbols pin (the C2C PacletSymbol list).     *)
(* ====================================================================== *)
pmInstallDeployPatches[pacletName_String, context_String] := Module[{},

	(* DocumentationBuild's RewriteHyperlinkString does StringTake[c, -1] on a possibly-empty
	   hyperlink segment - a Module-local with no global symbol to patch, some of it front-end-side
	   out of reach of a scoped Quiet - so switch the message off for the whole run. *)
	Off[StringTake::take];

	(* AppearanceElements: on 2026-09-22 the cloud began rejecting the option outright for this
	   account - CloudDeploy::appearancenotsup, "not supported with your current subscription" -
	   and not merely a particular value: None, {} and even Automatic, the DEFAULT, all fail while
	   omitting the option succeeds.  Gating the default is not a plausible plan limit, so read it
	   as a cloud-side regression rather than an entitlement.
	   It is fatal, silently: PacletResource threads $embeddedOptions into the example- and
	   definition-notebook deploys, those fail, the ResourceObject deploy then finds nothing
	   (CloudObject::cloudnf) and NO resource object is created - while publish.wls still prints
	   "published:".  That is how a whole resource went missing with a success message.
	   The option only suppresses the cloud chrome, so dropping it costs a toolbar on the embedded
	   notebooks and buys a deploy that completes.  Probed rather than assumed, so the day the
	   cloud accepts it again the patch stops applying on its own. *)
	Module[{probe = CloudObject["pm-appearance-probe.html"], ok},
		ok = Quiet @ Check[
			Head[CloudDeploy["probe", probe, AppearanceElements -> None]] === CloudObject, False];
		Quiet @ Check[DeleteObject[probe], Null];
		If[ ok,
			Print["deploy: AppearanceElements accepted; leaving the deploy options alone"],
			Quiet @ Unprotect[PacletResource`Private`$embeddedOptions];
			PacletResource`Private`$embeddedOptions = Sequence[];
			With[{dropAE = HoldPattern[AppearanceElements -> _] :> Sequence[]},
				Quiet @ Unprotect[
					PacletResource`Private`cloudExportPacletResourceContent,
					PacletResource`Private`cloudDeployPacletWebFile,
					PacletResource`Private`cloudDeployNB];
				DownValues[PacletResource`Private`cloudExportPacletResourceContent] =
					DownValues[PacletResource`Private`cloudExportPacletResourceContent] /. dropAE;
				DownValues[PacletResource`Private`cloudDeployPacletWebFile] =
					DownValues[PacletResource`Private`cloudDeployPacletWebFile] /. dropAE;
				DownValues[PacletResource`Private`cloudDeployNB] =
					DownValues[PacletResource`Private`cloudDeployNB] /. dropAE
			];
			Print["deploy: AppearanceElements REJECTED by the cloud - option stripped from the deploy"]
		]
	];

	(* No-purge: strip the redundant Quiet[DeleteObject[...]] from the three deploy functions
	   (each is immediately followed by an OverwriteTarget copy) and replace the
	   "DocumentationNotebooks" rule with the in-place merge above. *)
	If[DownValues[PacletResource`Private`cloudExportPacletResourceContent] =!= {} &&
			DownValues[PacletResource`Private`cloudDeployPacletWebFile] =!= {},
		With[{noPurge = HoldPattern[Quiet[DeleteObject[_], ___]] :> Null},
			Quiet @ Unprotect[
				PacletResource`Private`cloudExportPacletResourceContent,
				PacletResource`Private`cloudDeployPacletWebFile,
				PacletResource`Private`cloudDeployNB
			];
			DownValues[PacletResource`Private`cloudExportPacletResourceContent] =
				DownValues[PacletResource`Private`cloudExportPacletResourceContent] /. noPurge;
			DownValues[PacletResource`Private`cloudDeployPacletWebFile] =
				DownValues[PacletResource`Private`cloudDeployPacletWebFile] /. noPurge;
			DownValues[PacletResource`Private`cloudDeployNB] =
				DownValues[PacletResource`Private`cloudDeployNB] /. noPurge;
			PrependTo[
				DownValues[PacletResource`Private`cloudDeployPacletWebFile],
				HoldPattern[PacletResource`Private`cloudDeployPacletWebFile[
						as_, root_, "DocumentationNotebooks", dir_?DirectoryQ, opts : OptionsPattern[CloudObject]
				]] :> pmMergeDeployDocs[root, dir, opts]
			]
		];
		Print["deploy: no-purge deploy installed (resource + page deletes stripped, docs merged)"]
		,
		Print["deploy: WARNING - deploy internals not found; stock purging deploy in effect"]
	];

	(* prefetchURL does a throwaway URLRead warm-up that prints URLRead::invhttp on a slow fetch;
	   keep its URL return, drop the warm-up. *)
	If[DownValues[PacletResource`Private`prefetchURL] =!= {},
		Quiet @ Unprotect[PacletResource`Private`prefetchURL];
		PacletResource`Private`prefetchURL[url_] := URLBuild @ URLParse @ url;
		Print["deploy: prefetchURL cache warm-up disabled"]
		,
		Print["deploy: WARNING - prefetchURL not found; cache warm-up URLRead in effect"]
	];

	(* DeployedResourceShingle's processshingleData calls htmlFragmentExport, undefined anywhere
	   in the system, breaking a string-valued Details section. The detail is already an HTML
	   fragment, so define it as identity (after loading the shingle stack so it lands right). *)
	ResourceSystemClient`Private`loadDeployResourceShingle[];
	If[DownValues[DeployedResourceShingle`Private`htmlFragmentExport] === {} &&
			OwnValues[DeployedResourceShingle`Private`htmlFragmentExport] === {},
		DeployedResourceShingle`Private`htmlFragmentExport[s_String] := s;
		Print["deploy: defined missing htmlFragmentExport (identity for HTML fragments)"]
	];

	(* PacletSymbol boxes are left as the stock fancy boxes (paclet icon + framed short label, with a
	   tooltip carrying the full PacletSymbol[...]): documented symbols render fancy on the web and,
	   crucially, paste as the usual import-free PacletSymbol boxes. The short display label comes
	   from symLabelBox, so the full-context "Symbols" names stay readable. *)

	(* Pin pacletDeclaredSymbols: PacletInfo declares "Symbols", but at deploy time
	   pacletDeclaredSymbols re-resolves the paclet by name via fullPacletObjectInfo, which on a
	   machine with an older copy registered can resolve to one whose PacletInfo predates the
	   declaration, leaving documented code unwrapped. Return the symbols we are deploying
	   regardless of which copy wins. *)
	Quiet @ Needs[context];
	With[
		{pmSyms = Sort[(context <> #) & /@ (Last[StringSplit[#, "`"]] & /@ Names[context <> "*"])]},
		If[pmSyms =!= {} && DownValues[PacletResource`Private`pacletDeclaredSymbols] =!= {},
			Quiet @ Unprotect[PacletResource`Private`pacletDeclaredSymbols];
			PrependTo[DownValues[PacletResource`Private`pacletDeclaredSymbols],
				HoldPattern[PacletResource`Private`pacletDeclaredSymbols[pacletName]] :> pmSyms];
			PrependTo[DownValues[PacletResource`Private`pacletDeclaredSymbols],
				HoldPattern[PacletResource`Private`pacletDeclaredSymbols[KeyValuePattern["Name" -> pacletName]]] :> pmSyms];
			Print["deploy: pinned pacletDeclaredSymbols to ", Length[pmSyms], " ", pacletName, " symbols"]
			,
			Print["deploy: WARNING - could not enumerate ", context, " symbols; PacletSymbol C2C may be empty"]
		]
	];
]

(* ====================================================================== *)
(* pmInjectHero - inject a shingle hero image.                              *)
(* The headless Interactive -> False scrape does not capture the definition  *)
(* notebook's HeroImage cell, so augment deployExtraPacletWebFiles to add an *)
(* IMAGE expression (not a file path: the file-path branch falls through to   *)
(* Missing[] and no hero is deployed). *)
(* ====================================================================== *)
pmInjectHero[heroImg_] :=
	If[ImageQ[heroImg] || MatchQ[heroImg, _Graphics | _Graphics3D],
		Quiet @ Unprotect[PacletResource`Private`deployExtraPacletWebFiles];
		PrependTo[
			DownValues[PacletResource`Private`deployExtraPacletWebFiles],
			HoldPattern[PacletResource`Private`deployExtraPacletWebFiles[
					id_,
					as_?(AssociationQ[#] && KeyExistsQ[#, "PacletFile"] && ! KeyExistsQ[#, "HeroImage"] &),
					root_, opts___]] :>
				PacletResource`Private`deployExtraPacletWebFiles[id, Append[as, "HeroImage" -> heroImg], root, opts]
		];
		Print["deploy: hero-image injection patch installed"]
		,
		Print["deploy: WARNING - hero asset not found/unreadable; skipping hero injection"]
	]

(* ====================================================================== *)
(* pmInstallTreeSidebar - render the left-rail Guides nav as the guide       *)
(* hierarchy (areas -> subtopics -> ...) built from the guide-to-guide       *)
(* down-links, instead of PacletResource's flat by-doc-type list. rootGuide  *)
(* is the top guide whose children seed the tree. *)
(* ====================================================================== *)
pmInstallTreeSidebar[guidesDir_String, rootGuide_String] := Module[{},
	$guideChildMap = Association[ Function[f,
		FileBaseName[f] -> DeleteCases[
			DeleteDuplicates @ Cases[
				Cases[Import[f, "NB"], Cell[c_, "GuideFunctionsSection" | "GuideFunctionsSubsection" | "GuideTOCLink", ___] :> c, Infinity],
				(ButtonBox[_, ___, ButtonData -> u_String, ___] | TemplateBox[{___, u_String, ___}, _, ___]) /;
					StringMatchQ[u, "paclet:" ~~ ___ ~~ "guide/" ~~ __] :> Last[StringSplit[u, "/"]],
				Infinity],
			FileBaseName[f]] ] /@ FileNames["*.nb", guidesDir] ];

	(* No guide-to-guide down-link anywhere means there is no hierarchy to draw.  rootGuide seeds
	   the tree and is never listed as its own child, so the rail would render as an empty <ul> -
	   strictly worse than the stock flat list.  Leave the stock rail alone in that case. *)
	If[ Union @@ Values[$guideChildMap] === {},
		Print["deploy: no guide hierarchy (", Length[$guideChildMap],
			" guide(s), no guide-to-guide links) - keeping the stock flat Guides rail"];
		Return[Null, Module]
	];

	Quiet @ Unprotect[PacletResource`Private`createSidebarLinkSection];
	PacletResource`Private`createSidebarLinkSection["Guides", urls_] := Module[
		{urlStr, nameToUrl, nameToTitle, liOf, roots, css, js},
		urlStr[e_] := If[AssociationQ[e], Lookup[e, "URL", ""], e];
		nameToUrl   = Association[(FileBaseName[StringReplace[urlStr[#], ".html" ~~ EndOfString -> ""]] -> urlStr[#]) & /@ urls];
		nameToTitle = Association[Cases[urls, e_?AssociationQ :> (FileBaseName[StringReplace[urlStr[e], ".html" ~~ EndOfString -> ""]] -> Lookup[e, "Title", Nothing])]];
		liOf[name_, seen_] := If[MemberQ[seen, name], Nothing,
			With[ {kids = Lookup[$guideChildMap, name, {}], url = Lookup[nameToUrl, name, None], label = Lookup[nameToTitle, name, name]},
				If[ kids === {},
					XMLElement["li", {}, { If[url =!= None, XMLElement["a", {"href" -> url}, {label}], label] }],
					XMLElement["li", {}, { XMLElement["details", {}, {
						XMLElement["summary", {}, { If[url =!= None, XMLElement["a", {"href" -> url}, {label}], label] }],
						XMLElement["ul", {}, DeleteCases[liOf[#, Append[seen, name]] & /@ kids, Nothing]] }] }]
				] ] ];
		roots = Lookup[$guideChildMap, rootGuide, {}];
		If[roots === {}, roots = Sort[Keys[nameToUrl]]];
		css = StringJoin[
			".guide-tree,.guide-tree ul{list-style:none;margin:0;padding:0}",
			".guide-tree ul{padding-left:1em}",
			".guide-tree details>summary{display:block;position:relative;cursor:pointer;list-style:none;padding-right:1.6em}",
			".guide-tree details>summary::-webkit-details-marker{display:none}",
			".guide-tree details>summary::after{content:\"\\25B8\";position:absolute;right:.8em;top:50%;transform:translateY(-50%);color:#999}",
			".guide-tree details[open]>summary::after{content:\"\\25BE\"}",
			".guide-tree summary>a{display:inline}"];
		js = StringJoin[
			"(function(){function R(){try{var SK='pmSb',OK='pmSbO';",
			"var sb=document.getElementById('pac-nav-sidebar')||document.getElementById('pac-nav-sidebar-frame');if(!sb)return;",
			"var sc=sb;while(sc&&sc.scrollHeight<=sc.clientHeight&&sc.parentElement)sc=sc.parentElement;",
			"var o={};try{o=JSON.parse(sessionStorage.getItem(OK)||'{}')}catch(e){}",
			"var ds=document.querySelectorAll('.guide-tree details');",
			"for(var i=0;i<ds.length;i++){(function(d){var s=d.querySelector('summary');var k=s?s.textContent.trim():String(i);",
			"if(o[k])d.open=true;d.addEventListener('toggle',function(){o[k]=d.open;try{sessionStorage.setItem(OK,JSON.stringify(o))}catch(e){}})})(ds[i])}",
			"var v=sessionStorage.getItem(SK);if(v!==null)sc.scrollTop=parseFloat(v);",
			"sb.addEventListener('click',function(e){var t=e.target;if(t&&t.closest&&t.closest('a')){try{sessionStorage.setItem(SK,String(sc.scrollTop))}catch(x){}}})",
			"}catch(e){}}if(document.readyState!=='loading')R();else document.addEventListener('DOMContentLoaded',R)})();"];
		<| "Label" -> "Guides",
		   "Links" -> { XMLElement["div", {}, {
				XMLElement["style", {}, {css}],
				XMLElement["ul", {"class" -> "guide-tree"}, DeleteCases[liOf[#, {rootGuide}] & /@ roots, Nothing]],
				XMLElement["script", {}, {js}] }] } |> ];
	Print["deploy: hierarchical Tree sidebar enabled (", Length[$guideChildMap], " guides)"]
]

(* ====================================================================== *)
(* pmScrapeAndDeploy - headless equivalent of "Deploy -> Publicly in the    *)
(* cloud": open the definition notebook in place, warm up paclet resolution, *)
(* scrape with Interactive -> False, and CloudDeploy to the location the     *)
(* button computes (<account>/DeployedResources/Paclet/<Publisher>/<Name>,   *)
(* slash kept) with Permissions -> "Public". Returns the deploy result. *)
(* ====================================================================== *)
(* A failed scrape reports only "Scraping the resource ... failed", which says nothing about which
   check blocked it - the strict gate fails on ANY Error-level issue. Name them, and point at the
   tolerant path, so the next person does not have to bisect the vendor's inspectors. Passes a
   successful scrape straight through. *)
pmReportScrapeBlockers[nbo_][res_] := (
	If[ ! MatchQ[res, _ResourceObject],
		Print["deploy: the scrape was blocked; definition-notebook issues:"];
		Scan[
			Print["  [", Lookup[#, "Level", "?"], "] ", Lookup[#, "Tag", "?"]] &,
			Replace[Quiet @ Check[Normal @ DefinitionNotebookClient`CheckDefinitionNotebook[nbo], {}],
				Except[_List] -> {}]];
		Print["  (only Error-level issues block; PM_SCRAPE_TOLERANT=1 deploys anyway, as CI does)"]];
	res
)

pmScrapeAndDeploy[defNb_String, pacletName_String] := Module[{pmScrapeRes},
	Needs["DefinitionNotebookClient`"];
	Needs["PacletResource`DefinitionNotebook`"];
	(* ScrapeResource runs CodeInspector over the paclet's .wl/.m source as an incidental code lint -
	   which is irrelevant to publishing DOCS (that code is covered by the test suite), and on the
	   daily-build pod image its bundled CodeParser fires a WLIntegerExpr "value.has_value()" assertion
	   that corrupts the parse and - via "FailureCondition" -> "Error" - kills the scrape. Disable the
	   lint at its source: force the scrape's per-file gate codeInspectFileQ to False, so no .wl/.m file
	   is ever handed to CodeInspector/CodeParser during the scrape (no assertion, no findings). The
	   scrape's other, genuinely-relevant checks are untouched. (The pod-gated PM_SCRAPE_TOLERANT
	   fallback below is kept as belt-and-suspenders until a pod run confirms this alone suffices.) *)
	Quiet[
		Unprotect[DefinitionNotebookClient`Inspectors`PackagePrivate`codeInspectFileQ];
		DownValues[DefinitionNotebookClient`Inspectors`PackagePrivate`codeInspectFileQ] =
			{HoldPattern[DefinitionNotebookClient`Inspectors`PackagePrivate`codeInspectFileQ[_]] :> False}
	];
	(* the scrape's dominant cost is its serial per-notebook web transform; parallelize it *)
	pmParallelizeScrapeProcessing[];
	(* narrate every vendor deploy step + parallel/logged permissions pass *)
	pmInstrumentDeployProgress[];
	pmScrapeRes = UsingFrontEnd @ TimeConstrained[
		Enclose @ Module[{nbo},
			nbo = ConfirmMatch[
				NotebookOpen[defNb, Visible -> False],
				_NotebookObject,
				"Opening the definition notebook failed."
			];
			(* warm up paclet resolution: the definition notebook resolves its paclet relative to
			   its own directory, and a freshly-opened notebook misses until PacletObject and
			   ScrapePacletDirectory have each run once *)
			PacletObject[pacletName];
			Quiet[PacletResource`DefinitionNotebook`ScrapePacletDirectory[nbo]];
			WithCleanup[
				Module[{res, co},
					res = ConfirmMatch[
						DefinitionNotebookClient`ScrapeResource[
							"Paclet", nbo,
							Interactive -> False,
							(* Pod escape hatch (PM_SCRAPE_TOLERANT=1): the image's parser noise raises
						   spurious Error-level code inspections that are absent on a normal install,
						   so don't let them fail the scrape there. CloudDeploy still validates the
						   resource. Normal/local/runner deploys keep the strict "Error" gate. *)
						"FailureCondition" -> If[Environment["PM_SCRAPE_TOLERANT"] === "1", None, "Error"]
						] // pmReportScrapeBlockers[nbo],
						_ResourceObject,
						"Scraping the resource from the definition notebook failed."
					];
					ResourceSystemClient`Private`loadDeployResourceShingle[];
					co = Replace[
						DeployedResourceShingle`Private`defaultCloudObjectLocation["Paclet", res["Name"]],
						Except[_CloudObject] :> CloudObject[]
					];
					pmRepairDeployRoot[co];
					With[{obj = CloudDeploy[res, co, Permissions -> "Public"]},
						ResourceRegister[res, "Cloud", "StoreContent" -> False];
						pmEnsureResourcePointer[co];
						obj
					]
				],
				NotebookClose[nbo]
			]
		],
		5400,
		$TimedOut
	];
	(* persist the embed-page signature manifest even if a later step timed out/failed - the work
	   already done must count toward the next run (see pmInstrumentDeployProgress part 3) *)
	pmSaveEmbedManifest[];
	pmScrapeRes
]

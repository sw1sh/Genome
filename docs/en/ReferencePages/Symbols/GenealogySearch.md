---
Template: Symbol
Name: GenealogySearch
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenealogySearch
Keywords: [genealogy, archives, records, search, WikiTree, FamilySearch, Wikidata, repression, ancestors]
SeeAlso: [GenealogyLogin, FamilyTree, ImportGEDCOM, FamilyTreePlot, FamilyTreeQ]
RelatedGuides: [Genome]
---

## Usage

<code>[GenealogySearch]()[*query*]</code> searches the genealogical record providers for *query* and gives one [Tabular]() of results.

<code>[GenealogySearch]()[*tree*, *person*]</code> builds the query from a person in a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

<code>[GenealogySearch]()["Providers"]</code> tabulates the providers and their current availability.

## Details & Options

- *query* is a name string, or an [Association]() of the criteria `"GivenName"`, `"MiddleName"`, `"Surname"`, `"BirthYear"`, `"DeathYear"`, `"Place"` and `"Text"`. The [Association]() form is the precise one.
- A bare string is split on the convention each script uses: a name written in Cyrillic is read surname first, a name in Latin script given name first.
- Every provider maps onto one row shape, so results from all of them concatenate into a single table with the columns `"Provider"`, `"Name"`, `"Birth"`, `"Death"`, `"Place"`, `"Detail"` and `"URL"`.
- Providers fall into three classes, and the distinction is not cosmetic. It is what tells you why a provider returned what it did.

| | |
|---|---|
| `"Open"` | a public API needing no credential, queried directly |
| `"Credential"` | a real API behind a token you obtain yourself, dormant until the token is set |
| `"Browser"` | an archive with a search interface and no public API, searched by driving a real browser |

- The open providers are `"WikiTree"`, the single collaborative world tree; `"OpenList"`, the Otkrytyi Spisok database of victims of Soviet political repression, queried through its MediaWiki API and parsed out of each record's template, so a result carries the arrest date, sentence, article, rehabilitation and the Book of Memory it came from; `"PermGenerations"`, the name index of the metrical books of Perm guberniya; `"Wikidata"`, for people with structured birth and death dates; and `"OpenArchives"`, the civil registration and church records of mostly Dutch and Belgian archives.
- `"PermGenerations"` is the one provider whose hits are already genealogy rather than pointers to it. Each record names the parents and cites the archival file it sits in, in the form `GAPK F.37.Op.6.D.494`, together with the church, uezd, volost and village, so a hit can be ordered from the archive or read on the spot without a further search. Reaching that detail costs one extra request per row, which `"Detailed" -> False` switches off.
- The credential providers are `"FamilySearch"` and `"Geni"`. Each reads its token from an environment variable first and from [SystemCredential]() second: `FAMILYSEARCH_TOKEN` or `"FamilySearchToken"`, and `GENI_TOKEN` or `"GeniToken"`. Without a token the provider contributes nothing and issues no message, so a machine with no credentials still gets a clean result.
- The browser providers are `"PamyatNaroda"`, for Soviet WWII service, award, casualty and burial documents; `"YandexArchive"`, for handwriting-searchable metrical books, confession lists and revision tales; and `"FindAGrave"`, for headstone photographs and burial records. None of them publishes an API, and a plain HTTP fetch of their search page returns a JavaScript shell or an anti-bot interstitial, so the query is run in a real browser and the results are read off the rendered page.
- Driving a browser needs [Node.js](https://nodejs.org) with the `playwright-core` package, and a Chrome or Chromium build for it to launch. Where any of that is missing, the browser providers stay usable in a reduced form: they give back the deep link that runs the query in your own browser, and the `"Available"` column of the provider table reports [False]() so the difference is visible rather than silent.
- `"YandexArchive"` returns archival pages rather than people. Each row is a scanned page of a metrical book, revision tale or confession list whose handwriting recognition matched the query, with `"Name"` naming the archival unit and `"Detail"` carrying the recognized text around the match, which is usually the part worth reading.
- An archive that gates results behind an account is unlocked by a stored session. <code>[GenealogyLogin](paclet:WolframInstitute/Genome/ref/GenealogyLogin)</code> opens a browser window at that provider's sign-in page and saves the cookies it ends up with, so no password ever passes through the kernel.
- A provider that fails to answer, whether from a network failure, a rate limit, an anti-bot check or an unexpected response, issues a message saying which and contributes either a search link or nothing, rather than being reported as having found nothing. An empty result and a refusal are different answers and are never conflated.

The following options can be given:

| | | |
|---|---|---|
| `"Providers"` | [Automatic]() | which providers to query: [Automatic]() means every available one, [All]() means every known one, or give a name or a list of names |
| `"MaxResults"` | 10 | how many records to ask each provider for |
| `"IncludeLinks"` | [True]() | include the browser-class providers when `"Providers"` is [Automatic]() |
| `"Browser"` | [Automatic]() | drive a browser for the browser-class providers; [False]() keeps them in link mode, which is what an offline run wants |
| `"Detailed"` | [True]() | follow each `"PermGenerations"` hit to its record card for the parents and the archival citation |
| `"Variants"` | [Automatic]() | also search the alternative o/a spellings of the surname; [False]() searches only the spelling given |

- Unstressed `o` and `a` are pronounced identically in Russian, so a surname written down by ear drifts between them, and the drift is not consistent even within one family: a tree can hold a Safonov and a Safanov who are father and son. An archive name index matches the string it is given, so searching one spelling silently misses the other. `"Variants"` runs the query once per alternative spelling and merges the results, deduplicated.
- The substitution is confined to the surname root. A Russian surname suffix is orthographically stable, so varying it would only manufacture nonsense and multiply requests, and a root with no `o` or `a` in it expands to itself alone, costing nothing.
- A search sends the queried name and dates to the selected third-party services. Nothing leaves the machine until `GenealogySearch` is called, and only the fields of the one person queried are sent, never the tree.

## Basic Examples

A search is a network call by nature, so the first examples here run real ones against the open providers; the rest use the provider table, which is local, and the browser providers with `"Browser" -> False`, which builds their search URL by construction instead of running it.

A person with structured dates in Wikidata comes back with them:

```wl
GenealogySearch["Leo Tolstoy", "Providers" -> "Wikidata", "MaxResults" -> 2] // Dataset
```

The Perm name index answers with archival records: each row is one metrical-book entry, and the detail names the parents and cites the file the entry sits in, which is what a genealogist orders from the archive:

```wl
GenealogySearch[<|"Surname" -> "Попов", "GivenName" -> "Адриан"|>, "Providers" -> "PermGenerations"] // Dataset
```

The table says what exists and what is usable right now:

```wl
GenealogySearch["Providers"] // Dataset
```

---

Availability is per class: the open and link providers are always usable, and a credential provider becomes available once its token is set:

```wl
GenealogySearch["Providers"] // Dataset
```

---

With the browser switched off, a browser provider gives back the deep link that runs the query, with the criteria already filled in:

```wl
GenealogySearch[<|"Surname" -> "Doe", "GivenName" -> "John", "BirthYear" -> 1900|>, "Providers" -> "FindAGrave", "Browser" -> False] // Dataset
```

## Scope

The results of every provider share one row shape, whatever the provider is:

```wl
GenealogySearch["Doe", "Providers" -> "PamyatNaroda", "Browser" -> False] // Dataset
```

---

Several providers can be asked at once, and their rows concatenate:

```wl
GenealogySearch[<|"Surname" -> "Doe", "GivenName" -> "John"|>, "Providers" -> {"FindAGrave", "PamyatNaroda", "YandexArchive"}, "Browser" -> False] // Dataset
```

---

Given a tree and a person, the query is built from that person's record. A small pedigree, written as a GEDCOM file:

```wl
FileNameTake[
    demoTreeFile = Export[
        FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}],
        "0 HEAD
    1 SOUR DEMO
    1 GEDC
    2 VERS 5.5.1
    1 CHAR UTF-8
    0 @I1@ INDI
    1 NAME John /Doe/
    2 GIVN John
    2 SURN Doe
    1 SEX M
    1 BIRT
    2 DATE 12 MAR 1900
    1 DEAT
    2 DATE 1975
    1 FAMS @F1@
    0 @I2@ INDI
    1 NAME Jane /Roe/
    2 GIVN Jane
    2 SURN Roe
    2 _MARNM Doe
    1 SEX F
    1 BIRT
    2 DATE 1902
    1 FAMS @F1@
    0 @I3@ INDI
    1 NAME Richard Q /Doe/
    2 GIVN Richard
    2 _MIDN Q
    2 SURN Doe
    1 SEX M
    1 BIRT
    2 DATE JUL 1930
    1 FAMC @F1@
    1 FAMS @F2@
    0 @I4@ INDI
    1 NAME Mary /Poe/
    2 GIVN Mary
    2 SURN Poe
    1 SEX F
    1 BIRT
    2 DATE 1932
    1 FAMS @F2@
    0 @I5@ INDI
    1 NAME Sam /Doe/
    2 GIVN Sam
    2 SURN Doe
    1 SEX M
    1 BIRT
    2 DATE 05 FEB 1960
    1 FAMC @F2@
    0 @I6@ INDI
    1 NAME Ann /Doe/
    2 GIVN Ann
    2 SURN Doe
    1 SEX F
    1 BIRT
    2 DATE 1962
    1 FAMC @F2@
    0 @F1@ FAM
    1 HUSB @I1@
    1 WIFE @I2@
    1 CHIL @I3@
    0 @F2@ FAM
    1 HUSB @I3@
    1 WIFE @I4@
    1 CHIL @I5@
    1 CHIL @I6@
    0 TRLR",
        "Text"
    ]
]
```

<!-- => "demo-tree.ged" -->

An ancestor's birth and death years reach the archive without being retyped:

```wl
GenealogySearch[ImportGEDCOM[demoTreeFile], "I1", "Providers" -> "FindAGrave", "Browser" -> False] // Dataset
```

---

The person can be named by a fragment rather than a record key, exactly as elsewhere:

```wl
GenealogySearch[ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]], "Richard", "Providers" -> "PamyatNaroda", "Browser" -> False] // Dataset
```

A surname is also searched under its alternative spellings. In link mode one row comes back per spelling, and the spelling that finds the record is often not the one given:

```wl
GenealogySearch[<|"Surname" -> "Сафонов"|>, "Providers" -> "FindAGrave", "Browser" -> False, "Variants" -> True] // Dataset
```

## Properties and Relations

A credential provider with no token configured contributes no rows and says nothing about it:

```wl
Length @ GenealogySearch["John Doe", "Providers" -> {"FamilySearch", "Geni"}]
```

<!-- => 0 -->

---

The result is always a [Tabular](), including when nothing was found, and an empty one keeps the column names so a caller can read the shape off it:

```wl
Normal @ GenealogySearch["John Doe", "Providers" -> "FamilySearch"]["ColumnKeys"]
```

<!-- => {"Provider", "Name", "Birth", "Death", "Place", "Detail", "URL"} -->

---

`"IncludeLinks" -> False` drops the link providers from an [Automatic]() provider set, which is what to pass when only searched records are wanted. It does not override an explicit request, so naming a link provider still gives its URL:

```wl
GenealogySearch[<|"Surname" -> "Doe"|>, "Providers" -> "YandexArchive", "IncludeLinks" -> False, "Browser" -> False] // Dataset
```

## Possible Issues

An argument a query cannot be built from gives <code>[$Failed]()</code> with a message:

```wl
Quiet @ GenealogySearch[42]
```

<!-- => $Failed -->

---

The open providers rate-limit anonymous callers. When one refuses, `GenealogySearch` issues a message naming it and leaves its rows out, rather than reporting an empty result as an answer. Ask for fewer providers, or retry later.

A row that carries the detail `no public API: open this URL to run the search in a browser` is not a search result. It is the query, addressed. Open the URL to run it, or install the browser runner so the query runs here.

The archives in the browser class defend themselves against automated traffic, and Pamyat Naroda in particular will answer a security check instead of results for some networks and after enough requests. That case is reported, not hidden:

```wl
Quiet @ Length @ GenealogySearch[<|"Surname" -> "Doe"|>, "Providers" -> "PamyatNaroda", "Browser" -> False]
```

<!-- => 1 -->

When it happens with the browser on, `GenealogySearch` issues its message naming the provider and the reason, and the row you get back is the search link. Signing in with <code>[GenealogyLogin](paclet:WolframInstitute/Genome/ref/GenealogyLogin)</code> is what usually clears it.

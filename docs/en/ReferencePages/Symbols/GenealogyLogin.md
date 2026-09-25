---
Template: Symbol
Name: GenealogyLogin
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/GenealogyLogin
Keywords: [genealogy, archives, login, session, cookies, browser, Playwright, Pamyat Naroda, Yandex Archive, Find a Grave]
SeeAlso: [GenealogySearch, FamilyTree, ImportGEDCOM, FamilyTreePlot]
RelatedGuides: [Genome]
---

## Usage

<code>[GenealogyLogin]()[*provider*]</code> opens a browser window at the sign-in page of a browser-class <code>[GenealogySearch](paclet:WolframInstitute/Genome/ref/GenealogySearch)</code> provider and saves the session it ends up with.

## Details & Options

- *provider* is one of the browser-class providers: `"PamyatNaroda"`, `"YandexArchive"` or `"FindAGrave"`. Any other provider gives <code>[$Failed]()</code> with a message naming the ones that take a session.
- The window is a real, visible browser. You sign in there by hand, including any second factor or captcha, and then close the window; closing it is the signal to save.
- No password reaches the kernel. The browser collects the credentials, and only the resulting cookies and local storage are written out. Nothing about the sign-in appears in the notebook, in the paclet, or in any log this function writes.
- The saved session goes to one file per provider under <code>[$UserBaseDirectory]()</code>, in `ApplicationData/WolframInstitute/Genome/browser-state`. Set the environment variable `GENOME_BROWSER_STATE` to keep them somewhere else. That location is deliberately outside the paclet and outside any repository: a session file is a live credential for the account that made it.
- Later <code>[GenealogySearch](paclet:WolframInstitute/Genome/ref/GenealogySearch)</code> calls to that provider reuse the session automatically, with no further argument.
- A session buys two different things depending on the archive: results that are only shown to signed-in users, and passage through the anti-bot checks these archives apply to unrecognised traffic.
- Sessions expire the way they do in any browser. When a search starts refusing again, run `GenealogyLogin` once more to replace the stored session.
- `GenealogyLogin` needs the same machinery the browser providers need: [Node.js](https://nodejs.org) with `playwright-core`, and a Chrome or Chromium build to drive. Without them it gives <code>[$Failed]()</code> with a message rather than opening anything.
- The function returns the path of the file it wrote, so the result can be checked, backed up or deleted.

## Basic Examples

The providers that take a session are the browser-class ones, which the provider table names:

```wl
GenealogySearch["Providers"] // Dataset
```

---

Asking for a session on a provider that has an API instead gives <code>[$Failed]()</code>, with a message listing the ones that do take one:

```wl
Quiet @ GenealogyLogin["WikiTree"]
```

<!-- => $Failed -->

---

The whole flow is one call, which opens a window at the Yandex sign-in page, waits for you to sign in and close it, and returns the file it saved:

```
GenealogyLogin["YandexArchive"]
```

## Scope

The sessions live in a directory of their own under <code>[$UserBaseDirectory]()</code>, one file per provider, unless `GENOME_BROWSER_STATE` moves them:

```wl
FileNameSplit[FileNameJoin[{$UserBaseDirectory, "ApplicationData", "WolframInstitute", "Genome", "browser-state"}]][[-3 ;;]]
```

<!-- => {"WolframInstitute", "Genome", "browser-state"} -->

## Properties and Relations

Once a session exists, nothing about a search changes: <code>[GenealogySearch](paclet:WolframInstitute/Genome/ref/GenealogySearch)</code> picks it up on its own, and a query is built the same way whichever provider answers it. An open provider answers here, with a real person's dates, in the same row shape a browser provider with a stored session answers in:

```wl
GenealogySearch["Leo Tolstoy", "Providers" -> "Wikidata", "MaxResults" -> 1] // Dataset
```

## Possible Issues

A session file is a credential. Anyone who can read it can act as that account on that archive, so it is kept out of the paclet and out of version control by default, and it should be treated like any other stored login rather than copied around or committed.

Deleting the file is the way to sign out; the next search then runs anonymously, with whatever that archive shows to anonymous callers:

```wl
FileNameJoin[{$UserBaseDirectory, "ApplicationData", "WolframInstitute", "Genome", "browser-state", "YandexArchive.json"}]
```

<!-- => the full path the file was written to -->

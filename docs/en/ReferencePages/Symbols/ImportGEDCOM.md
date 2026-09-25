---
Template: Symbol
Name: ImportGEDCOM
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ImportGEDCOM
Keywords: [GEDCOM, genealogy, pedigree, family tree, import, ancestry, kinship]
SeeAlso: [FamilyTree, FamilyTreeQ, FamilyTreePlot, GenealogySearch, ExportGEDCOM, ImportFamilyTable]
RelatedGuides: [Genome]
---

## Usage

<code>[ImportGEDCOM]()[*path*]</code> reads the GEDCOM genealogy file *path* and gives a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

<code>[ImportGEDCOM]()[*path*, *opts*]</code> reads it with the options below.

## Details & Options

- GEDCOM is the interchange format every genealogy service exports to, so `ImportGEDCOM` is the way a tree built on Geni, MyHeritage, Ancestry, FamilySearch or Genotek reaches the Wolfram Language.
- A GEDCOM line is a level number, an optional cross-reference key, a tag, and a value. Level 0 opens a record and deeper levels nest under it. `ImportGEDCOM` reads GEDCOM 5.5.1 and the 5.5 and 7.0 files that share its tag vocabulary.
- `INDI` records become the `"People"` slot of the result, keyed by their cross-reference key with the surrounding at-signs stripped, so `@I1@` becomes `"I1"`.
- Each person record carries `"ID"`, `"Name"`, `"GivenName"`, `"MiddleName"`, `"Surname"`, `"MarriedName"`, `"Sex"`, `"BirthDate"`, `"BirthDateText"`, `"BirthDatePlace"`, `"DeathDate"`, `"DeathDateText"`, `"DeathDatePlace"`, `"Deceased"`, `"Occupation"`, `"Note"`, `"ParentFamilies"` and `"SpouseFamilies"`.
- `FAM` records become the `"Families"` slot, each carrying `"ID"`, `"Husband"`, `"Wife"`, `"Children"`, `"MarriageDate"` and `"DivorceDate"` with their text and place fields.
- Relationships are held the way GEDCOM states them, through family records rather than as direct parent pointers, so a couple's children stay grouped under the union that produced them and a remarriage does not merge two sets of half-siblings.
- A date is parsed at the granularity the record states. `12 MAR 1900` gives a day, `JUL 1930` gives a month, and `1902` gives a year. A year-only entry never acquires a January 1st, because a fabricated day later reads as evidence that the record does not contain.
- The approximation and range keywords `ABT`, `EST`, `CAL`, `BEF`, `AFT`, `INT`, `FROM`, `BET`, `AND` and `TO` are stripped before the date tokens are read, and the verbatim GEDCOM value is kept alongside in the matching `"...Text"` field.
- The surname is taken from between the slashes of the `NAME` value, and the `GIVN`, `SURN`, `_MIDN` and `_MARNM` sub-tags override that split when present. `_MIDN` is the vendor tag several services use for a patronymic, and `_MARNM` for a married surname.
- An unknown tag is kept in the parsed node tree and ignored by the record extractors, so a vendor extension never fails the read.
- `CONT` and `CONC` continuation lines are folded into the value of the line they continue and never appear as records of their own.
- A `DEAT` record with no date, the bare `1 DEAT Y` form, still sets `"Deceased"` to [True](). Being dead and having a recorded death date are separate facts.
- <code>[ImportGEDCOM]()[[File](paclet:ref/File)[*path*]]</code> is equivalent to the string form.

The following options can be given:

| | | |
|---|---|---|
| [CharacterEncoding]() | [Automatic]() | encoding of the file; [Automatic]() means `"UTF-8"` |

- `ImportGEDCOM` gives <code>[$Failed]()</code> and issues a message when the file does not exist, and when the file parses but contains no `INDI` record at all.
- Only UTF-8, UTF-16 and ASCII are decodable. ANSEL, the legacy encoding some pre-2000 GEDCOM writers emit, is not supported; such a file reads as mojibake or fails outright.

## Basic Examples

The examples run on a small synthetic pedigree: three generations of an invented family, six people in two family records. Every name and date in it is made up; no real genealogy is read and nothing reaches the network. The pedigree is written to a temporary file:

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

Read it into a tree. The summary box gives the size and span of the pedigree rather than any of its names:

```wl
demoTree = ImportGEDCOM[demoTreeFile]
```


The people are keyed by their GEDCOM cross-reference key:

```wl
demoTree["IDs"]
```

<!-- => {"I1", "I2", "I3", "I4", "I5", "I6"} -->


One person record carries the parsed name parts, the dates, and the families the person belongs to:

```wl
demoTree["Person", "I3"]
```

<!-- => <|"ID" -> "I3", "Name" -> "Richard Q Doe", "GivenName" -> "Richard", "MiddleName" -> "Q", "Surname" -> "Doe", "MarriedName" -> Missing["NotAvailable"], "Sex" -> "Male", "BirthDate" -> DateObject[{1930, 7}, "Month"], "BirthDateText" -> "JUL 1930", "BirthDatePlace" -> Missing["NotAvailable"], "DeathDate" -> Missing["NotAvailable"], "DeathDateText" -> Missing["NotAvailable"], "DeathDatePlace" -> Missing["NotAvailable"], "Deceased" -> False, "Occupation" -> Missing["NotAvailable"], "Note" -> Missing["NotAvailable"], "ParentFamilies" -> {"F1"}, "SpouseFamilies" -> {"F2"}|> -->

## Scope

A tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

Dates keep the granularity of the record. A full date gives a day, a month-and-year entry gives a month, and a bare year stays a year:

```wl
Lookup[demoTree["People"], {"I1", "I3", "I2"}][[All, "BirthDate"]]
```

<!-- => {DateObject[{1900, 3, 12}, "Day"], DateObject[{1930, 7}, "Month"], DateObject[{1902}, "Year"]} -->


The verbatim GEDCOM text is kept beside every parsed date, which is where an approximation keyword survives:

```wl
demoTree["Person", "I2"]["BirthDateText"]
```

<!-- => "1902" -->


A married surname recorded in the vendor `_MARNM` tag is kept separately from the birth surname:

```wl
{demoTree["Person", "I2"]["Surname"], demoTree["Person", "I2"]["MarriedName"]}
```

<!-- => {"Roe", "Doe"} -->


The header fields of the file come back through the `"Header"` property:

```wl
KeyDrop[demoTree["Header"], "Path"]
```

<!-- => <|"Source" -> "DEMO", "SourceName" -> Missing["NotAvailable"], "Encoding" -> "UTF-8", "GEDCOMVersion" -> "5.5.1", "Submitter" -> Missing["NotAvailable"]|> -->

## Properties and Relations

The tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

The result satisfies <code>[FamilyTreeQ](paclet:WolframInstitute/Genome/ref/FamilyTreeQ)</code>, which is what every genealogy operator dispatches on:

```wl
FamilyTreeQ[demoTree]
```

<!-- => True -->


The whole pedigree flattens into one table of people through the `"Tabular"` property:

```wl
First @ Normal @ demoTree["Tabular"]
```

<!-- => <|"ID" -> "I1", "Name" -> "John Doe", "Sex" -> "Male", "Birth" -> 1900, "Death" -> 1975, "BirthPlace" -> Missing["NotAvailable"], "Parents" -> 0, "Children" -> 1|> -->


<code>[FamilyTreePlot](paclet:WolframInstitute/Genome/ref/FamilyTreePlot)</code> draws the parsed tree:

```wl
FamilyTreePlot[demoTree]
```

## Possible Issues

A path that does not exist gives <code>[$Failed]()</code> with a message rather than an empty tree:

```wl
Quiet @ ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "no-such-tree.ged"}]]
```

<!-- => $Failed -->

---

So does a file that parses as text but holds no individual records, which is how a wrong file type or an undecodable encoding presents:

```wl
Quiet @ ImportGEDCOM[Export[FileNameJoin[{$TemporaryDirectory, "not-a-tree.ged"}], "hello", "Text"]]
```

<!-- => $Failed -->

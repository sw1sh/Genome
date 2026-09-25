---
Template: Symbol
Name: ExportGEDCOM
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ExportGEDCOM
Keywords: [GEDCOM, genealogy, family tree, export, write, Genotek]
SeeAlso: [ImportGEDCOM, ImportFamilyTable, ExportFamilyTable, FamilyTree]
RelatedGuides: [Genome]
---

## Usage

<code>[ExportGEDCOM]()[*path*, *tree*]</code> writes the <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> *tree* to *path* as a GEDCOM 5.5.1 file.

<code>[ExportGEDCOM]()[*path*, *tree*, *opts*]</code> writes it with the options below.

## Details & Options

- One `INDI` record is written per person: the name with the surname between slashes, the `GIVN`, `SURN`, `_MIDN` and `_MARNM` sub-tags where the record has a given name, surname, patronymic or married name, the sex, the birth and death events with their date and place, an occupation and a note where present, and the `FAMC` and `FAMS` links to the family records.
- One `FAM` record is written per family: husband, wife, children, and the marriage and divorce events where present.
- A date is written from the verbatim text the record keeps, so `ABT 1900` survives the trip; a record whose date exists only as a parsed value is written at that value's granularity, `25 AUG 1907`, `AUG 1907` or `1907`.
- A person marked deceased with no death date is written as `1 DEAT Y`, the form GEDCOM uses for the fact without the date.
- The vendor tags `_MIDN` and `_MARNM` are written because the services that emit them read them back; a reader that does not know them ignores them.
- The header names this paclet as the source and, by default, carries the submitter the tree was read with.
- A tree read with <code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> and written again reproduces its records, key for key.
- The result is the path written, as [Export]() gives it.

The following options can be given:

| | | |
|---|---|---|
| `"Submitter"` | [Automatic]() | the submitter name in the header; [Automatic]() keeps the one the tree was read with, [None]() writes none |
| `"LineEnding"` | `"\n"` | the line terminator |

- `ExportGEDCOM` gives <code>[$Failed]()</code> with a message when the second argument is not a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

## Basic Examples

The examples on this page run against a small synthetic family written to a temporary file. Every name and date in it is made up, and nothing on this page reaches the network.

```wl
FileNameTake[
    demoTableFile = Export[
        FileNameJoin[{$TemporaryDirectory, "demo-table.csv"}],
        "ID;Surname;GivenName;MiddleName;MaidenName;Sex;BirthDate;BirthPlace;DeathDate;DeathPlace;Status;Father;Mother;Spouse;Children
    I1;Doe;John;;;M;12.03.1900;;1975;;deceased;;;Doe Jane;Doe Richard Q
    I2;Doe;Jane;;Roe;F;1902;;;;;;;Doe John;Doe Richard Q
    I3;Doe;Richard;Q;;M;07.1930;;;;;Doe John;Doe Jane;Poe Mary;\"Doe Sam; Doe Ann\"
    I4;Poe;Mary;;;F;1932;;;;;;;Doe Richard Q;\"Doe Sam; Doe Ann\"
    I5;Doe;Sam;;;M;05.02.1960;;;;;Doe Richard;Poe Mary;;
    I6;Doe;Ann;;;F;1962;;;;;Doe Richard Q;Poe Mary;;",
        "Text"
    ]
]
```

<!-- => "demo-table.csv" -->

Read the table and write it out as GEDCOM, which is the conversion a table usually needs:

```wl
demoTable = ImportFamilyTable[demoTableFile]
```

```wl
FileNameTake[demoGedcomFile = ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-from-table.ged"}], demoTable]]
```

<!-- => "demo-from-table.ged" -->

The file opens with a standard header:

```wl
Import[demoGedcomFile, "Lines"][[1 ;; 4]]
```

<!-- => {"0 HEAD", "1 SOUR WolframInstitute/Genome", "2 NAME WolframInstitute/Genome family tree export", "1 GEDC"} -->

It holds one individual record per person and one family record per union:

```wl
Block[{lines = Import[demoGedcomFile, "Lines"]},
    {Count[lines, s_ /; StringEndsQ[s, " INDI"]], Count[lines, s_ /; StringEndsQ[s, " FAM"]]}
]
```

<!-- => {6, 2} -->

## Scope

Each section re-reads the table written above:

```wl
demoTable = ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-table.csv"}]]
```

A person's record carries the name split into its tags, the sex, the dated events and the family links. The grandmother's married name goes out as the vendor tag the services read:

```wl
Block[{lines = Import[ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-from-table.ged"}], demoTable], "Lines"], start},
    start = First @ FirstPosition[lines, "0 @I2@ INDI"];
    lines[[start ;; start + 7]]
]
```

<!-- => {"0 @I2@ INDI", "1 NAME Jane /Roe/", "2 GIVN Jane", "2 SURN Roe", "2 _MARNM Doe", "1 SEX F", "1 BIRT", "2 DATE 1902"} -->

Dates go out at the granularity the record has, so a month-and-year birth is written without a day:

```wl
Block[{lines = Import[ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-from-table.ged"}], demoTable], "Lines"]},
    Select[lines, StringStartsQ[#, "2 DATE "] &]
]
```

<!-- => {"2 DATE 12 MAR 1900", "2 DATE 1975", "2 DATE 1902", "2 DATE JUL 1930", "2 DATE 1932", "2 DATE 05 FEB 1960", "2 DATE 1962"} -->

## Properties and Relations

```wl
demoTable = ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-table.csv"}]]
```

A tree written as GEDCOM and read back with <code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> has the same people and families, which makes the pair a lossless round trip:

```wl
Block[{back = ImportGEDCOM[ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-roundtrip.ged"}], demoTable]]},
    {Normal[back]["People"] === Normal[demoTable]["People"], Normal[back]["Families"] === Normal[demoTable]["Families"]}
]
```

<!-- => {True, True} -->

## Possible Issues

A second argument that is not a tree gives <code>[$Failed]()</code> with a message:

```wl
Quiet @ ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "x.ged"}], "not a tree"]
```

<!-- => $Failed -->

---

The writer emits UTF-8. A GEDCOM reader from the ANSEL era may not decode Cyrillic names in it; every current genealogy service does.

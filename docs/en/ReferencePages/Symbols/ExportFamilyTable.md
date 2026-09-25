---
Template: Symbol
Name: ExportFamilyTable
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ExportFamilyTable
Keywords: [genealogy, family tree, CSV, table, spreadsheet, export, Genotek, GEDCOM]
SeeAlso: [ImportFamilyTable, ExportGEDCOM, ImportGEDCOM, FamilyTree]
RelatedGuides: [Genome]
---

## Usage

<code>[ExportFamilyTable]()[*path*, *tree*]</code> writes the <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> *tree* to *path* as a flat family table, one row per person.

<code>[ExportFamilyTable]()[*path*, *tree*, *opts*]</code> writes it with the options below.

## Details & Options

- The table written is the one a genealogy service imports: an identifier, surname, given name, patronymic, maiden name, sex, birth and death dates and places, a status, and the father, mother, spouse and children, each named by their current surname, given name and patronymic. Several spouses or children are listed in one cell, separated by a semicolon and a space, and a cell that carries the delimiter is quoted.
- The surname column receives the current surname, the married name where the record has one, and the maiden-name column then receives the birth surname. This is the inverse of GEDCOM's convention and is what <code>[ImportFamilyTable](paclet:WolframInstitute/Genome/ref/ImportFamilyTable)</code> undoes on the way back.
- Dates are written as `12.03.1900`, `07.1930` or `1902`, at the granularity the record has. A date the record only holds as text, such as `ABT 1900`, is written as that text.
- With the default options the file matches the Genotek export in layout: Russian column headers, a semicolon delimiter, a byte-order mark and CRLF line endings, so it can be handed back to the service that wrote the original.
- A table has no family records, so a family's own dates, a marriage or a divorce, are not written. The unions themselves survive, since they are rebuilt from the named links on the way back.
- The result is the path written, as [Export]() gives it.

The following options can be given:

| | | |
|---|---|---|
| `"Headers"` | `"Russian"` | the column headers: `"Russian"`, the Genotek layout, or `"English"` |
| `"Delimiter"` | `";"` | the field separator |
| `"ByteOrderMark"` | [True]() | start the file with a UTF-8 byte-order mark |
| `"LineEnding"` | `"\r\n"` | the line terminator |

- `ExportFamilyTable` gives <code>[$Failed]()</code> with a message when the second argument is not a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

## Basic Examples

The examples on this page run against a small synthetic family written to a temporary file. Every name and date in it is made up, and nothing on this page reaches the network.

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

Read it and write it out as a table. English headers keep the example readable; the default writes the Genotek layout:

```wl
demoTree = ImportGEDCOM[demoTreeFile]
```

```wl
FileNameTake[demoTableFile = ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-tree.csv"}], demoTree, "Headers" -> "English", "ByteOrderMark" -> False]]
```

<!-- => "demo-tree.csv" -->

The first row after the header is the grandfather: current surname, dates at the record's granularity, a status, and his wife and son named rather than keyed:

```wl
Import[demoTableFile, "Lines"][[2]]
```

<!-- => "I1;Doe;John;;;M;12.03.1900;;1975;;deceased;;;Doe Jane;Doe Richard Q" -->

## Scope

Each section re-reads the fixture and re-imports the tree:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

A woman with a married name gets it in the surname column and her birth surname in the maiden-name column:

```wl
Import[ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-tree.csv"}], demoTree, "Headers" -> "English", "ByteOrderMark" -> False], "Lines"][[3]]
```

<!-- => "I2;Doe;Jane;;Roe;F;1902;;;;;;;Doe John;Doe Richard Q" -->

Several children share one cell, quoted because the cell holds the delimiter:

```wl
Import[ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-tree.csv"}], demoTree, "Headers" -> "English", "ByteOrderMark" -> False], "Lines"][[4]]
```

<!-- => "I3;Doe;Richard;Q;;M;07.1930;;;;;Doe John;Doe Jane;Poe Mary;\"Doe Sam; Doe Ann\"" -->

The default headers are the Russian ones the Genotek export uses, and the default file starts with a UTF-8 byte-order mark, which a text import strips and a byte import shows as the three bytes it is:

```wl
Take[Import[ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-tree-ru.csv"}], demoTree], "Byte"], 3]
```

<!-- => {239, 187, 191} -->

## Properties and Relations

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

A tree written as a table and read back with <code>[ImportFamilyTable](paclet:WolframInstitute/Genome/ref/ImportFamilyTable)</code> has the same people and the same links:

```wl
Block[{back = ImportFamilyTable[ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-roundtrip.csv"}], demoTree]]},
    {back["PersonCount"], back["FamilyCount"], back["Relationship", "I5", "I1"], Normal[back["Children", "I3"]][[All, "ID"]]}
]
```

<!-- => {6, 2, "paternal grandfather", {"I5", "I6"}} -->

## Possible Issues

A second argument that is not a tree gives <code>[$Failed]()</code> with a message:

```wl
Quiet @ ExportFamilyTable[FileNameJoin[{$TemporaryDirectory, "x.csv"}], "not a tree"]
```

<!-- => $Failed -->

---

Family keys are not part of a table. A tree that goes out as a table and comes back has its families renumbered in order of first appearance, and a marriage date, which lives on the family record, does not survive the trip. <code>[ExportGEDCOM](paclet:WolframInstitute/Genome/ref/ExportGEDCOM)</code> keeps both.

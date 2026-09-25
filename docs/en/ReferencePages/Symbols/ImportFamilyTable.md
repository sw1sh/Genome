---
Template: Symbol
Name: ImportFamilyTable
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/ImportFamilyTable
Keywords: [genealogy, family tree, CSV, table, spreadsheet, import, Genotek, GEDCOM]
SeeAlso: [ExportFamilyTable, ExportGEDCOM, ImportGEDCOM, FamilyTree]
RelatedGuides: [Genome]
---

## Usage

<code>[ImportFamilyTable]()[*path*]</code> reads the flat family table at *path*, one row per person, and gives a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

<code>[ImportFamilyTable]()[*path*, *opts*]</code> reads it with the options below.

## Details & Options

- A family table is the spreadsheet a genealogy service exports beside its GEDCOM: one row per person with an identifier, surname, given name, patronymic, maiden name, sex, birth and death dates and places, a status, and the person's father, mother, spouse and children. The Genotek export is the reference layout; a table kept by hand in a spreadsheet with the same columns reads the same way.
- Column headers are recognised in Russian, as Genotek writes them, and in English: `ID`, `Surname`, `GivenName`, `MiddleName`, `MaidenName`, `Sex`, `BirthDate`, `BirthPlace`, `DeathDate`, `DeathPlace`, `Status`, `Father`, `Mother`, `Spouse`, `Children`. Header case does not matter, a column that is absent reads as missing, and a column that is not recognised is ignored.
- The father, mother, spouse and children cells name people rather than key them, as `Doe Richard Q`, and are resolved against the rows by name. A reference resolves whether it uses the current or the birth surname and whether or not it carries the patronymic, in that order of confidence: a person's own full name first, the surname-and-given-name key as a fallback. A short key that several rows share, as when a grandfather and a grandson share a surname and a given name, is settled by mutuality: the child a row names is the candidate whose own row names that row as a parent, and likewise for a parent or a spouse. A name that matches no row is reported and left out; a short key that mutuality cannot settle either is reported and the first row is used.
- A table has no family records, so the unions a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> is built from are rebuilt from those cells across every row together: a row's parents make it the child of that couple, its spouse makes a couple, and its children are the children of the couple it forms with its spouse. This is also how a person nobody names, such as a wife recorded with no name, still gets her family, from her own row.
- The table's surname column holds the current surname, and a maiden name beside it is the birth surname. GEDCOM keeps them the other way about, the birth surname as the surname and the married name as a separate tag, so a row with a maiden name reads with `"Surname"` set to the maiden name and `"MarriedName"` to the surname column.
- Dates are read at the granularity the cell states: `12.03.1900` gives a day, `07.1930` a month and `1902` a year, and the GEDCOM text form is kept beside the parsed date as `"BirthDateText"`. A cell in a GEDCOM date form such as `ABT 1900` is read by the GEDCOM date parser.
- Sex is `м` or `ж`, or `M`, `F`, `Male`, `Female`. A status of `умер(ла)`, `deceased` or `dead`, or any death date, marks the person deceased.
- The delimiter is sniffed from the header line, semicolon or comma, and a byte-order mark at the start of the file is ignored. Fields may be quoted, and a quoted field may carry the delimiter, doubled quotes and line breaks.
- Person keys come from the `ID` column when there is one and are numbered `I1`, `I2`, ... otherwise. Family keys are always numbered `F1`, `F2`, ... in order of first appearance.

The following options can be given:

| | | |
|---|---|---|
| `"Delimiter"` | [Automatic]() | the field separator; [Automatic]() sniffs semicolon or comma from the header |
| [CharacterEncoding]() | [Automatic]() | encoding of the file; [Automatic]() means UTF-8 |

- `ImportFamilyTable` gives <code>[$Failed]()</code> with a message when the file does not exist, and when its header holds neither a surname nor a given-name column.

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

Read it. The table names its people rather than keying them, and the families are rebuilt from the father, mother, spouse and children cells:

```wl
demoTable = ImportFamilyTable[demoTableFile]
```

Two families were rebuilt from six rows:

```wl
{demoTable["PersonCount"], demoTable["FamilyCount"]}
```

<!-- => {6, 2} -->

The links are the same ones a GEDCOM would carry:

```wl
{Normal[demoTable["Parents", "I5"]][[All, "ID"]], demoTable["Relationship", "I5", "I1"]}
```

<!-- => {{"I3", "I4"}, "paternal grandfather"} -->

## Scope

Each section re-reads the fixture written above:

```wl
demoTable = ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-table.csv"}]]
```

A maiden name beside the surname column reads as the birth surname, with the surname column becoming the married name, which is how GEDCOM keeps them:

```wl
Lookup[demoTable["Person", "I2"], {"Surname", "MarriedName"}]
```

<!-- => {"Roe", "Doe"} -->

Dates keep the granularity of the cell:

```wl
Lookup[demoTable["People"], {"I1", "I3", "I2"}][[All, "BirthDate"]]
```

<!-- => {DateObject[{1900, 3, 12}, "Day"], DateObject[{1930, 7}, "Month"], DateObject[{1902}, "Year"]} -->

The GEDCOM text form of each date is kept beside it, ready to be written out again:

```wl
demoTable["Person", "I1"]["BirthDateText"]
```

<!-- => "12 MAR 1900" -->

A status word marks a person deceased, as does a death date:

```wl
{demoTable["Person", "I1"]["Deceased"], demoTable["Person", "I3"]["Deceased"]}
```

<!-- => {True, False} -->

A reference without the patronymic still resolves. The fifth row names its father as `Doe Richard`, and he is found:

```wl
Normal[demoTable["Parents", "I5"]][[1, "Name"]]
```

<!-- => "Richard Q Doe" -->

## Properties and Relations

```wl
demoTable = ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "demo-table.csv"}]]
```

The result is an ordinary <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>, so everything that works on a tree read from GEDCOM works on it, drawing included:

```wl
FamilyTreePlot[demoTable]
```

<code>[ExportGEDCOM](paclet:WolframInstitute/Genome/ref/ExportGEDCOM)</code> writes it out as GEDCOM, which is the conversion a table usually needs:

```wl
Count[Import[ExportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-from-table.ged"}], demoTable], "Lines"], s_ /; StringEndsQ[s, " INDI"]]
```

<!-- => 6 -->

## Possible Issues

A path that does not exist gives <code>[$Failed]()</code> with a message:

```wl
Quiet @ ImportFamilyTable[FileNameJoin[{$TemporaryDirectory, "no-such-table.csv"}]]
```

<!-- => $Failed -->

---

So does a file whose header carries none of the expected columns:

```wl
Quiet @ ImportFamilyTable[Export[FileNameJoin[{$TemporaryDirectory, "not-a-table.csv"}], "a;b;c", "Text"]]
```

<!-- => $Failed -->

---

A reference that matches no row is reported and left out, rather than inventing a person. The tree still reads; the link is missing.

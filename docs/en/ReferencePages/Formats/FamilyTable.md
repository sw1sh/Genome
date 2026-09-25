---
Template: Format
Name: FamilyTable
Extension: .csv
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/format/FamilyTable
Description: The flat one-row-per-person family table a genealogy service exports beside its GEDCOM, read as a FamilyTree and written from one.
Keywords: [family table, CSV, spreadsheet, genealogy, pedigree, Genotek, import, export]
SeeAlso: [FamilyTree, ImportFamilyTable, ExportFamilyTable, ImportGEDCOM, Import, Export]
RelatedGuides: [Genome]
---

# FamilyTable

FamilyTable is the flat spreadsheet a genealogy service exports beside its GEDCOM: one row per person, with the person's father, mother, spouse and children written as names rather than as record keys. The Genotek export is the reference layout. Loading the WolframInstitute/Genome paclet registers the FamilyTable import and export converters, which read such a table as a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> and write one back. The file is CSV, so the format is always named explicitly; a bare `.csv` imports as CSV.

## Background & Context

- Plain-text CSV. The delimiter is sniffed from the header line, semicolon or comma, and a byte-order mark is ignored on import.
- Column headers are recognised in Russian, as Genotek writes them, and in English: `ID`, `Surname`, `GivenName`, `MiddleName`, `MaidenName`, `Sex`, `BirthDate`, `BirthPlace`, `DeathDate`, `DeathPlace`, `Status`, `Father`, `Mother`, `Spouse`, `Children`.
- The surname column holds the current surname and the maiden-name column the birth surname; GEDCOM keeps them the other way about, and the converters invert the convention in both directions.
- A table has no family records. The unions are rebuilt from the father, mother, spouse and children cells of every row together, which is also how a person nobody names still gets her family, from her own row.
- The registered converters are the same code as <code>[ImportFamilyTable](paclet:WolframInstitute/Genome/ref/ImportFamilyTable)</code> and <code>[ExportFamilyTable](paclet:WolframInstitute/Genome/ref/ExportFamilyTable)</code>.

## Import & Export

- `Import["file.csv", "FamilyTable"]` imports a family table, returning a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.
- `Import["file.csv", {"FamilyTable", elem}]` imports the specified element.

---

- `Export["file.csv", tree, "FamilyTable"]` writes a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> as a family table in the Genotek layout.

## Import Elements

| "Data" | the tree as a FamilyTree (default) |
|---|---|
| "People" | the person records, an Association keyed by record key |
| "Families" | the family records rebuilt from the named links |
| "Tabular" | every person as one row of a Tabular |
| "Graph" | the pedigree drawn with FamilyTreePlot |

## Options

| "Delimiter" | Automatic |
|---|---|
| "Headers" | "Russian" |
| "ByteOrderMark" | True |
| "LineEnding" | "\r\n" |

- `"Delimiter"` applies on import and export; [Automatic]() sniffs it from the header on import, and export writes a semicolon.
- `"Headers"` chooses the column headers written on export: `"Russian"`, the Genotek layout, or `"English"`.
- `"ByteOrderMark"` and `"LineEnding"` control the bytes written on export; the defaults reproduce the Genotek export.

## Examples

### Basic Examples

The examples on this page run against a small synthetic file written to a temporary file; every name, date and genotype in it is made up, and nothing on this page reaches the network.

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

Import it. The families are rebuilt from the named links in the rows:

```wl
demoTable = Import[demoTableFile, "FamilyTable"]
```

Six people, two rebuilt families, and the links a GEDCOM would carry:

```wl
{demoTable["PersonCount"], demoTable["FamilyCount"], demoTable["Relationship", "I5", "I1"]}
```

<!-- => {6, 2, "paternal grandfather"} -->

Export writes the table back, in the Genotek layout by default; with English headers the first data row reads:

```wl
Import[Export[FileNameJoin[{$TemporaryDirectory, "demo-table-out.csv"}], demoTable, "FamilyTable", "Headers" -> "English", "ByteOrderMark" -> False], "Lines"][[2]]
```

<!-- => "I1;Doe;John;;;M;12.03.1900;;1975;;deceased;;;Doe Jane;Doe Richard Q" -->

### Import Elements

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

The elements available for a file:

```wl
Import[demoTableFile, {"FamilyTable", "Elements"}]
```

<!-- => {"Data", "Families", "Graph", "People", "Summary", "Tabular"} -->

The "Families" element shows the unions rebuilt from the rows, each with its parents and children:

```wl
Import[demoTableFile, {"FamilyTable", "Families"}][[All, {"Husband", "Wife", "Children"}]]
```

<!-- => <|"F1" -> <|"Husband" -> "I1", "Wife" -> "I2", "Children" -> {"I3"}|>, "F2" -> <|"Husband" -> "I3", "Wife" -> "I4", "Children" -> {"I5", "I6"}|>|> -->

### Options

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

A table converts to GEDCOM through the tree, which is the conversion a table usually needs:

```wl
Count[Import[Export[FileNameJoin[{$TemporaryDirectory, "demo-from-table.ged"}], Import[demoTableFile, "FamilyTable"], "GEDCOM"], "Lines"], s_ /; StringEndsQ[s, " INDI"]]
```

<!-- => 6 -->

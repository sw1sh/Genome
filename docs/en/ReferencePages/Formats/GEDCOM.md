---
Template: Format
Name: GEDCOM
Extension: .ged
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/format/GEDCOM
Description: GEDCOM 5.5.1 genealogy interchange files, read as a FamilyTree and written from one.
Keywords: [GEDCOM, genealogy, pedigree, family tree, import, export, Genotek, Geni, MyHeritage, FamilySearch]
SeeAlso: [FamilyTree, ImportGEDCOM, ExportGEDCOM, FamilyTreePlot, Import, Export]
RelatedGuides: [Genome]
---

# GEDCOM

GEDCOM is the genealogy interchange format: a line-oriented text file of individual and family records that every genealogy service exports to and reads back, and the form in which a family tree built on Genotek, Geni, MyHeritage, Ancestry or FamilySearch leaves that service. Loading the WolframInstitute/Genome paclet registers the GEDCOM import and export converters, which read a file as a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> and write one back.

## Background & Context

- Plain-text format, UTF-8 in every current export; the paclet also decodes UTF-16 and ASCII, not the legacy ANSEL.
- A line is a level number, an optional cross-reference key, a tag and a value. Level 0 opens a record and every deeper line nests under the closest preceding line one level up; `CONT` and `CONC` continue the preceding value.
- `INDI` records hold people, `FAM` records hold unions, and relationships are stored through the unions, so a couple's children stay grouped under the union that produced them.
- Dates are read at the granularity the record states: `25 AUG 1907` gives a day, `AUG 1907` a month and `1907` a year, never a fabricated 1 January. The verbatim date text is kept beside the parsed date.
- The vendor tags `_MIDN` (a patronymic) and `_MARNM` (a married surname) are read and written, since the services that emit them read them back.
- The registered converters are the same code as <code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> and <code>[ExportGEDCOM](paclet:WolframInstitute/Genome/ref/ExportGEDCOM)</code>; the format is a second door to it.

## Import & Export

- `Import["file.ged", "GEDCOM"]` imports a GEDCOM file, returning a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.
- `Import["file.ged", {"GEDCOM", elem}]` imports the specified element.
- `ImportString["data", "GEDCOM"]` imports a tree from GEDCOM text held in a string.

---

- `Export["file.ged", tree, "GEDCOM"]` writes a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> as GEDCOM 5.5.1.
- `ExportString[tree, "GEDCOM"]` gives the GEDCOM text of a tree as a string.

## Import Elements

| "Data" | the tree as a FamilyTree (default) |
|---|---|
| "People" | the person records, an Association keyed by record key |
| "Families" | the family records, an Association keyed by record key |
| "Header" | the source, encoding, version and submitter of the file |
| "Tabular" | every person as one row of a Tabular |
| "Graph" | the pedigree drawn with FamilyTreePlot |

## Options

| CharacterEncoding | Automatic |
|---|---|
| "Submitter" | Automatic |
| "LineEnding" | "\n" |

- [CharacterEncoding]() applies on import; [Automatic]() means UTF-8.
- `"Submitter"` names the submitter written into the header on export; [Automatic]() keeps the one the tree was read with.
- `"LineEnding"` is the line terminator written on export.

## Examples

### Basic Examples

The examples on this page run against a small synthetic file written to a temporary file; every name, date and genotype in it is made up, and nothing on this page reaches the network.

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

Import it as a tree. The result displays as a summary box giving the size and span of the pedigree:

```wl
demoTree = Import[demoTreeFile, "GEDCOM"]
```

Six people in two family records:

```wl
{demoTree["PersonCount"], demoTree["FamilyCount"]}
```

<!-- => {6, 2} -->

Export writes the tree back out, and the file reads back to the same records:

```wl
Import[Export[FileNameJoin[{$TemporaryDirectory, "demo-tree-out.ged"}], demoTree, "GEDCOM"], "GEDCOM"]["PersonCount"]
```

<!-- => 6 -->

ExportString gives the GEDCOM text itself. Its first lines are the header:

```wl
Take[StringSplit[ExportString[demoTree, "GEDCOM"], "\n"], 4]
```

<!-- => {"0 HEAD", "1 SOUR WolframInstitute/Genome", "2 NAME WolframInstitute/Genome family tree export", "1 GEDC"} -->

### Import Elements

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

The elements available for a file:

```wl
Import[demoTreeFile, {"GEDCOM", "Elements"}]
```

<!-- => {"Data", "Families", "Graph", "Header", "People", "Summary", "Tabular"} -->

The "People" element is the person records keyed by record key:

```wl
Keys[Import[demoTreeFile, {"GEDCOM", "People"}]]
```

<!-- => {"I1", "I2", "I3", "I4", "I5", "I6"} -->

The "Header" element is what the file says about itself:

```wl
KeyDrop[Import[demoTreeFile, {"GEDCOM", "Header"}], "Path"]
```

<!-- => <|"Source" -> "DEMO", "SourceName" -> Missing["NotAvailable"], "Encoding" -> "UTF-8", "GEDCOMVersion" -> "5.5.1", "Submitter" -> Missing["NotAvailable"]|> -->

The "Graph" element draws the pedigree:

```wl
Import[demoTreeFile, {"GEDCOM", "Graph"}]
```

### Options

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

`"Submitter"` names the submitter written into the header:

```wl
Select[StringSplit[ExportString[Import[demoTreeFile, "GEDCOM"], "GEDCOM", "Submitter" -> "Demo Submitter"], "\n"], StringStartsQ[#, "1 NAME"] &][[1]]
```

<!-- => "1 NAME Demo Submitter" -->

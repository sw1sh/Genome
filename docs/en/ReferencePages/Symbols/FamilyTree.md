---
Template: Symbol
Name: FamilyTree
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/FamilyTree
Keywords: [family tree, pedigree, genealogy, kinship, ancestors, descendants, relationship, GEDCOM]
SeeAlso: [ImportGEDCOM, FamilyTreeQ, FamilyTreePlot, GenealogySearch, ExportGEDCOM, ImportFamilyTable, ExportFamilyTable]
RelatedGuides: [Genome]
---

## Usage

<code>[FamilyTree]()[*assoc*]</code> is a parsed pedigree holding people, the family records that link them, and the header of the file they came from.

<code>[FamilyTree]()[{*person*&#8321;, *person*&#8322;, ...}]</code> builds one from plain person [Association]() objects carrying `"ID"` and optional `"Father"` and `"Mother"` keys.

<code>*tree*[*property*]</code> gives a property of the tree, and <code>*tree*[*property*, *person*]</code> a property of one person in it.

## Details & Options

- A `FamilyTree` is normally produced by <code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> rather than written by hand.
- Unlike <code>[Genome](paclet:WolframInstitute/Genome/ref/Genome)</code>, a `FamilyTree` is not a lazy handle to a file. A pedigree is small enough to hold whole, and every query below is an in-memory graph walk.
- The payload carries `"People"`, an [Association]() of person records keyed by their record key, `"Families"`, the union records that link them, and the header fields `"Source"`, `"SourceName"`, `"Encoding"`, `"GEDCOMVersion"`, `"Submitter"` and `"Path"`.
- A person is named in any operator either by its record key, as in `"I3"`, or by any fragment of its name, as in `"Richard"`. A fragment that matches nobody, or more than one person, gives a [Missing]() result with a message naming the candidates.
- The list form synthesises one family record per distinct parent pair, so a tree can be written by hand without going through a GEDCOM file. Each element must carry a string `"ID"`.

The following properties give information about the whole tree:

| | |
|---|---|
| `"People"` | the person records, keyed by record key |
| `"Families"` | the family records, keyed by record key |
| `"IDs"` | the person record keys |
| `"PersonCount"`, `"FamilyCount"` | how many of each the tree holds |
| `"Tabular"`, `"Dataset"` | every person as one row of a [Tabular]() |
| `"Header"` | the source, encoding, version and path the tree was read from |
| `"Surnames"` | counts per surname, birth and married names together |
| `"YearRange"` | the first and last year any record mentions |
| `"Generations"` | each person's generation index, counted from the deepest known parent |
| `"GenerationCount"` | how many generations the tree spans |
| `"Issues"` | the consistency problems found in the records |

The following properties take a person:

| | |
|---|---|
| `"Person"` | the person record, with its key prepended |
| `"Find"` | every person whose name contains a fragment, as a [Tabular]() |
| `"Parents"`, `"Children"`, `"Siblings"`, `"Spouses"` | the immediate relatives |
| `"Ancestors"`, `"Descendants"` | the closure in that direction, optionally limited to a number of generations |
| `"Relationship"` | the kinship term relating two people, optionally in a given language |
| `"Relationships"` | how everyone else in the tree is related to one person, as a [Tabular]() |
| `"Graph"`, `"Plot"` | the drawing, equivalent to <code>[FamilyTreePlot](paclet:WolframInstitute/Genome/ref/FamilyTreePlot)</code> |

- <code>*tree*["Relationship", *a*, *b*, *language*]</code> and <code>*tree*["Relationships", *person*, *language*]</code> name the kinship in `"English"`, `"Russian"`, `"Spanish"`, `"Portuguese"`, `"Italian"`, `"Latvian"`, `"German"` or `"French"`; the default is English. The terms are as specific as the language is, with the side a grandparent or an uncle comes down, separate words for half-siblings, step-relations and in-laws, and the full Russian in-law vocabulary in which a wife's father and a husband's father are different words.
- `"Relationship"` names the second person relative to the first. It reports a direct line as `"father"`, `"grandmother"`, `"great-grandson"` and so on, a collateral line as `"sister"`, `"uncle"`, `"niece"`, and anything further out as `"second cousin once removed"`. A person reached only by marriage is named through their spouse, and an unconnected person gives `"unrelated"`.
- The kinship walks are cycle-safe, so a mis-entered tree in which somebody is their own ancestor is reported by `"Issues"` rather than looping.
- `"Issues"` checks each record against the others and reports a death before a birth, an implausible lifespan, a parent too young or a mother implausibly old at a birth, a child born after a parent died, a person recorded as their own ancestor, a family pointing at an unknown person, an unnamed person, an unconnected person, and a likely duplicate. Each row carries a severity of `"Error"` or `"Warning"`.
- [Length]() gives the number of people, [Keys]() their record keys, and [Normal]() the whole payload.
- A `FamilyTree` displays as a summary box reporting counts and spans only, and never a name. The distinction matters, because a rendered object travels inside the notebook that shows it: displaying a real pedigree writes every relative's name, date and birthplace into that notebook's source. Use a synthetic tree in anything you intend to share.

## Basic Examples

A small synthetic pedigree written to a temporary file stands in for a real one: three generations of an invented family, six people in two family records. Every name and date in it is made up, no real genealogy is read, and nothing reaches the network. Writing the file gives back its name:

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

Read it into a `FamilyTree`:

```wl
demoTree = ImportGEDCOM[demoTreeFile]
```


The tree knows its own size and span:

```wl
{demoTree["PersonCount"], demoTree["FamilyCount"], demoTree["GenerationCount"], demoTree["YearRange"]}
```

<!-- => {6, 2, 3, {1900, 1975}} -->


Every person flattens into one table:

```wl
demoTree["Tabular"] // Dataset
```

## Scope

A tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

The immediate relatives of one person come back as tables of the same shape:

```wl
demoTree["Parents", "I5"] // Dataset
```


A person can be named by a fragment instead of a record key:

```wl
demoTree["Person", "Richard"]["ID"]
```

<!-- => "I3" -->


The ancestor closure walks as far as the records go:

```wl
Sort @ Normal[demoTree["Ancestors", "I5"]][[All, "ID"]]
```

<!-- => {"I1", "I2", "I3", "I4"} -->


A generation limit stops it early:

```wl
Sort @ Normal[demoTree["Ancestors", "I5", 1]][[All, "ID"]]
```

<!-- => {"I3", "I4"} -->


The descendant closure runs the other way:

```wl
Sort @ Normal[demoTree["Descendants", "I1"]][[All, "ID"]]
```

<!-- => {"I3", "I5", "I6"} -->


`"Relationship"` names the second person relative to the first, and reverses correctly:

```wl
{demoTree["Relationship", "I5", "I1"], demoTree["Relationship", "I1", "I5"]}
```

<!-- => {"paternal grandfather", "grandson"} -->


The same relation in another language is not a translation of the English one. English counts cousin degree and removal; Russian names the generation and marks the collateral distance on it:

```wl
{demoTree["Relationship", "I5", "I1", "Russian"], demoTree["Relationship", "I5", "I1", "Spanish"]}
```

<!-- => {"дедушка по отцу", "abuelo paterno"} -->

Everyone's relation to one person comes back in one table:

```wl
demoTree["Relationships", "I5"]
```

Collateral and marital links are named too:

```wl
{demoTree["Relationship", "I5", "I6"], demoTree["Relationship", "I1", "I2"]}
```

<!-- => {"sister", "wife"} -->


Generation indices count from the deepest known parent, which is what puts a couple on one row however different their own ancestor depths are:

```wl
KeySort @ demoTree["Generations"]
```

<!-- => <|"I1" -> 0, "I2" -> 0, "I3" -> 1, "I4" -> 0, "I5" -> 2, "I6" -> 2|> -->


Surnames are counted across birth and married names; Jane Roe's married name makes her the fifth Doe in a six-person tree:

```wl
demoTree["Surnames"]
```

<!-- => <|"Doe" -> 5, "Roe" -> 1, "Poe" -> 1|> -->


A tree can also be built directly from person records, without a GEDCOM file. One family record is synthesised per distinct parent pair:

```wl
builtTree = FamilyTree[{
    <|"ID" -> "a", "Name" -> "A Root", "Sex" -> "Male"|>,
    <|"ID" -> "b", "Name" -> "B Root", "Sex" -> "Female"|>,
    <|"ID" -> "c", "Name" -> "C Child", "Sex" -> "Female", "Father" -> "a", "Mother" -> "b"|>
}]
```


It supports the same operators:

```wl
{builtTree["PersonCount"], builtTree["FamilyCount"], builtTree["Relationship", "c", "a"]}
```

<!-- => {3, 1, "father"} -->

## Properties and Relations

The fixture tree:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

[Length]() gives the number of people:

```wl
Length[demoTree]
```

<!-- => 6 -->


The consistency pass reports nothing on a tree whose dates agree:

```wl
Length @ demoTree["Issues"]
```

<!-- => 0 -->


Move one birth to five years after the father's, and the impossible date is caught. Both parents are flagged, since a birth five years after the father's is also three years after the mother's:

```wl
Normal @ ImportGEDCOM[
    Export[
        FileNameJoin[{$TemporaryDirectory, "demo-tree-broken.ged"}],
        StringReplace[Import[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}], "Text"], "2 DATE 05 FEB 1960" -> "2 DATE 05 FEB 1935"],
        "Text"
    ]
]["Issues"][[All, {"Severity", "Issue"}]]
```

<!-- => {<|"Severity" -> "Error", "Issue" -> "Parent too young"|>, <|"Severity" -> "Error", "Issue" -> "Parent too young"|>} -->


<code>[GenealogySearch](paclet:WolframInstitute/Genome/ref/GenealogySearch)</code> takes a tree and a person and builds the archive query from that record:

```wl
GenealogySearch[demoTree, "I1", "Providers" -> "FindAGrave"] // Dataset
```

## Possible Issues

The fixture, read into a tree:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```


A name fragment that matches more than one person does not silently pick one. It gives a [Missing]() result naming the candidates:

```wl
Quiet @ demoTree["Person", "Doe"]
```

<!-- => Missing["Ambiguous", {"I1", "I2", "I3", "I5", "I6"}] -->


A fragment that matches nobody gives a [Missing]() result too:

```wl
Quiet @ demoTree["Person", "Nobody"]
```

<!-- => Missing["NotFound", "Nobody"] -->

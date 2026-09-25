---
Template: Symbol
Name: FamilyTreePlot
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/FamilyTreePlot
Keywords: [family tree, pedigree, genealogy, plot, graph, visualization, ancestors, descendants]
SeeAlso: [FamilyTree, ImportGEDCOM, FamilyTreeQ, GenealogySearch]
RelatedGuides: [Genome]
---

## Usage

<code>[FamilyTreePlot]()[*tree*]</code> draws a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> as a generation-layered pedigree.

<code>[FamilyTreePlot]()[*tree*, *person*]</code> centres the drawing on one person.

## Details & Options

- The default drawing is the chart a genealogy service draws. The root person sits at the bottom; the ancestors fan out above, with the father's line on the left and the mother's on the right at every generation, so an ancestry reads as a binary tree of slots. Each ancestor's own brothers and sisters sit beside them, on the side away from the centre, and a lone known parent is centred over their child.
- Each person is one rounded card carrying their initials, coloured by sex, with the lines `"Labels"` asks for underneath: `father`, `grandmother`, `great-aunt`, `first cousin once removed`. A dark corner on the card marks a person recorded as dead; the root's card is orange; a person with no recorded name shows a question mark.
- A couple is joined by a line, and their children hang from the union on it through an elbow: down to a bus line between the rows, across, and down to the child. A lone parent's line to the child starts under the parent's label.
- Above the people whose parents are entirely unknown, dashed `father` and `mother` boxes mark where the tree stops.
- With `"Root" -> Automatic` the root is the person with the most ancestors in the tree, which is who a file exported from a genealogy service is built around; the latest born breaks a tie.
- `"Layout" -> "Layered"` draws everybody in the file instead, generation by generation, for a picture of a whole tree rather than of one person's ancestry. The layered embedding decides the structure; the drawing is then stretched horizontally by the smallest factor that keeps neighbouring cards in every row apart, and rows holding only family nodes are given only the height they need.
- Every placement is computed in printer points, because the cards are drawn from primitives at a fixed point size. With <code>[ImageSize]() -> [Automatic]()</code> the picture is sized to fit that layout exactly, capped at 6000 points on a side, which is why a wide pedigree gives a wide image rather than an unreadable square one.
- `"Labels"` names the lines a card carries, in the order they are given. The components are `"Name"` (given name and surname), `"Relationship"` (how the person stands to the root), `"Years"` (the compact `1907-1977`, or `b. 1964` when only one year is known) and `"Dates"` (the full `25.08.1907 - 26.06.1977`, at the granularity each record states). `{"Name", "Relationship", "Dates"}` is what [All]() means, [None]() draws the cards with no text at all, and [Automatic]() shows the name and the relationship, or the name alone once the picture holds more than eighty people. `"NameRelationship"`, `"NameYears"` and `"NameDates"` are accepted as the two-component lists they name.
- A component the record cannot fill contributes no line rather than a blank one, so a card never grows for information it does not have: with no root to relate to, `"Relationship"` is simply absent.
- `"Language"` takes `"English"`, `"Russian"`, `"Spanish"`, `"Portuguese"`, `"Italian"`, `"Latvian"`, `"German"` or `"French"`, and governs every word the picture writes, not only the relationship: the `b.` and `d.` before a lone year, the dashed `father` and `mother` placeholders, and the label on a person whose name the file does not record.
- The relationship terms are as specific as the language is. A grandparent or an uncle is named with the side it comes down, `paternal grandfather` and `дедушка по отцу`, `maternal uncle` and `дядя по матери`. Half-siblings, step-parents, step-children and in-laws have their own words, and Russian keeps the full in-law vocabulary, where a wife's father (`тесть`) and a husband's father (`свёкор`) are never the same word.
- Collateral relatives are named the way each language actually names them, which is not a translation of one system into another. English counts cousin degree and removal, so a grandparent's sibling is a `great-uncle` and a parent's cousin a `first cousin once removed`. Russian, and the Romance and Germanic languages, name the generation the person sits in and mark the collateral distance on it, so the same two people are a `двоюродный дедушка` and a `двоюродный дядя`, and in Spanish a `tío abuelo` and a `tío segundo`. Russian also keeps apart two relations English calls by one name: a cousin's child is a `двоюродный племянник` where a parent's cousin is a `двоюродный дядя`, and both are a first cousin once removed in English.
- `"Transliteration"` romanizes the names on the cards and the initials in them, without touching the records. `"BGN"` is the BGN/PCGN romanization used by English-language atlases and most archives that publish in Latin script, and the readable choice: `Андрей` becomes `Andrey` and `Щербаков` becomes `Shcherbakov`. `"Passport"` is ICAO Doc 9303, the spelling on a Russian passport since 2014, where the same names are `Andrei` and `Shcherbakov`. `"Scientific"` is the scholarly transliteration, through the built-in [Transliterate]().
- Colours are Standard colors and switch with the notebook theme, so the drawing reads on light and dark backgrounds.
- The drawing carries only the labels it shows. It does not close over the pedigree, so a plot pasted into a notebook does not carry the birthplaces, notes and family structure that are not on the picture.

The following options can be given:

| | | |
|---|---|---|
| `"Root"` | [Automatic]() | the person the chart is built around; [Automatic]() picks the person with the most ancestors |
| `"Layout"` | `"Pedigree"` | `"Pedigree"` for the root's ancestry, `"Layered"` for everybody in the file |
| `"Direction"` | [Automatic]() | which way to walk from the root: `"Ancestors"`, `"Descendants"` or `"Both"`; a pedigree defaults to `"Ancestors"`, a layered drawing to `"Both"` |
| `"Generations"` | [Automatic]() | how many generations from the root to walk; [Automatic]() means all of them |
| `"Labels"` | [Automatic]() | which lines a card carries: [All](), [None](), one of `"Name"`, `"Relationship"`, `"Years"`, `"Dates"`, or a list of them in the order they should appear |
| `"Highlight"` | `{}` | people to outline, named by record key or name fragment |
| `"Placeholders"` | [Automatic]() | draw the dashed father and mother boxes above the people whose parents are unknown |
| `"Language"` | `"English"` | the language of every word on the picture: the relationship labels, the life-year prefixes, the parent placeholders |
| `"Transliteration"` | [None]() | romanize the names: [None]() leaves them as written, `"BGN"`, `"Passport"` or `"Scientific"` transliterate them |

- Any other [Graph]() option is passed through. An explicit [GraphLayout]() replaces the built-in placement with that embedding, scaled uniformly until no two vertices sit closer than a card, so the cards land on it without overlapping.
- With `"Direction" -> "Both"` the root's descendants hang below the root, each generation one row further down, with each parent's spouse beside them so the couple has a union.
- A pedigree shows the people connected to the root through parents, children and their siblings. A person in the file who is not connected to the root that way does not appear in it; `"Layout" -> "Layered"` shows everybody.
- `FamilyTreePlot` gives <code>[$Failed]()</code> with a message when its first argument is not a <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>.

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

Read it into a tree:

```wl
demoTree = ImportGEDCOM[demoTreeFile]
```


Draw the whole pedigree:

```wl
FamilyTreePlot[demoTree]
```


The result is a [Graph](), with one vertex per person and one per family:

```wl
{VertexCount[FamilyTreePlot[demoTree]], EdgeCount[FamilyTreePlot[demoTree]]}
```

<!-- => {8, 7} -->

## Scope

A tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

Centring on a named person draws that person's ancestry, with their siblings beside them:

```wl
FamilyTreePlot[demoTree, "Root" -> "I5"]
```


The second argument is shorthand for `"Root"`:

```wl
FamilyTreePlot[demoTree, "I5"]
```


A generation budget stops the walk early:

```wl
FamilyTreePlot[demoTree, "Root" -> "I5", "Generations" -> 1]
```

`"Direction" -> "Both"` hangs the root's descendants below it as well. Centred on the grandfather, that is the whole file:

```wl
FamilyTreePlot[demoTree, "Root" -> "I1", "Direction" -> "Both"]
```

`"Layout" -> "Layered"` draws everybody in the file generation by generation, which is the picture to reach for when the file holds several unconnected branches:

```wl
FamilyTreePlot[demoTree, "Layout" -> "Layered"]
```

The placeholders above the top row can be switched off:

```wl
FamilyTreePlot[demoTree, "Placeholders" -> False]
```


`"Highlight"` outlines the people to look at, named by record key or by name fragment:

```wl
FamilyTreePlot[demoTree, "Highlight" -> {"Richard", "I1"}]
```


`"Labels" -> All` puts the relationship and the full dates under the name:

```wl
FamilyTreePlot[demoTree, "Labels" -> All]
```

A list asks for exactly those lines, in that order, so a chart can carry the dates without the relationship:

```wl
FamilyTreePlot[demoTree, "Labels" -> {"Name", "Dates"}]
```

A single component is a card with only that line:

```wl
FamilyTreePlot[demoTree, "Labels" -> "Years"]
```

`"Language"` writes every word on the picture in that language, the relationship labels included:

```wl
FamilyTreePlot[demoTree, "Language" -> "Russian"]
```

`"Transliteration"` romanizes the names and the initials without touching the records underneath:

```wl
FamilyTreePlot[demoTree, "Transliteration" -> "BGN"]
```

`"Labels" -> None` leaves only the cards and their initials, which is what a pedigree of a few hundred people needs:

```wl
FamilyTreePlot[demoTree, "Labels" -> None]
```


Passing an explicit [GraphLayout]() hands the placement back to the built-in embedding:

```wl
FamilyTreePlot[demoTree, GraphLayout -> "SpringElectricalEmbedding", ImageSize -> 400]
```

## Properties and Relations

The tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```

The `"Graph"` property of a tree is the same drawing:

```wl
demoTree["Graph", "Root" -> "I5"]
```


A pedigree covers the root, the ancestor closure, the siblings hanging beside each of them, and the family unions that link them:

```wl
VertexCount @ FamilyTreePlot[demoTree, "Root" -> "I5"]
```

<!-- => 8 -->


Because the result is an ordinary [Graph](), the graph functions apply to it. The family nodes are the vertices that are not person keys:

```wl
Cases[VertexList[FamilyTreePlot[demoTree]], {"FAM", id_} :> id]
```

<!-- => {"F1", "F2"} -->

## Possible Issues

A tree read from the fixture:

```wl
demoTree = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]
```


A first argument that is not a tree gives <code>[$Failed]()</code> with a message:

```wl
Quiet @ FamilyTreePlot["not a tree"]
```

<!-- => $Failed -->


Card widths are estimated from the label text rather than measured, so that the drawing lays out identically with and without a front end. A label in a script whose glyphs are much wider than the estimate can crowd its neighbours; `"Labels" -> "Name"` or a larger [ImageSize]() resolves it:

```wl
FamilyTreePlot[demoTree, "Labels" -> "Name"]
```

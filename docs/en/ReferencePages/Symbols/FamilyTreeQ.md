---
Template: Symbol
Name: FamilyTreeQ
Context: WolframInstitute`Genome`
Paclet: WolframInstitute/Genome
URI: WolframInstitute/Genome/ref/FamilyTreeQ
Keywords: [family tree, pedigree, genealogy, predicate, test, type check]
SeeAlso: [FamilyTree, ImportGEDCOM, FamilyTreePlot, GenealogySearch]
RelatedGuides: [Genome]
---

## Usage

<code>[FamilyTreeQ]()[*expr*]</code> gives [True]() if *expr* is a valid <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code> object, and [False]() otherwise.

## Details & Options

- `FamilyTreeQ` gives [True]() when *expr* is `FamilyTree[a]` for an [Association]() `a` that carries a `"People"` [Association]() and a `"Families"` [Association]().
- Any other expression gives [False](), including a `FamilyTree` whose payload is missing one of those keys or holds something other than an [Association]() under it.
- The test is total: every expression gives [True]() or [False](). No message is issued, and no argument returns unevaluated.
- The test is structural. It inspects the payload keys, walks no relationship, and asserts nothing about the file the tree was read from.
- `FamilyTreeQ` is the pattern the genealogy operators dispatch on, so a value that passes it supports the full property surface of <code>[FamilyTree](paclet:WolframInstitute/Genome/ref/FamilyTree)</code>, <code>[FamilyTreePlot](paclet:WolframInstitute/Genome/ref/FamilyTreePlot)</code> and the two-argument form of <code>[GenealogySearch](paclet:WolframInstitute/Genome/ref/GenealogySearch)</code>.
- A tree from <code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> always satisfies `FamilyTreeQ`.

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

A tree read from it passes:

```wl
FamilyTreeQ[ImportGEDCOM[demoTreeFile]]
```

<!-- => True -->

---

An expression that is not a `FamilyTree` at all gives [False]():

```wl
FamilyTreeQ[42]
```

<!-- => False -->

---

So does a `FamilyTree` whose payload is missing a required key:

```wl
FamilyTreeQ[FamilyTree[<|"People" -> <||>|>]]
```

<!-- => False -->

## Scope

A tree built from plain person records satisfies the test as well:

```wl
FamilyTreeQ[FamilyTree[{<|"ID" -> "a", "Name" -> "A Root"|>}]]
```

<!-- => True -->

---

An empty but well-formed payload passes, because the test is structural and a pedigree with no people is a valid, if useless, one:

```wl
FamilyTreeQ[FamilyTree[<|"People" -> <||>, "Families" -> <||>|>]]
```

<!-- => True -->

---

<code>[ImportGEDCOM](paclet:WolframInstitute/Genome/ref/ImportGEDCOM)</code> gives <code>[$Failed]()</code> when a file cannot be read. That value is not a tree, and `FamilyTreeQ` reports it as such without issuing a message:

```wl
FamilyTreeQ[$Failed]
```

<!-- => False -->

## Properties and Relations

`FamilyTreeQ` is exactly the payload-key test, so checking those keys by hand agrees with it:

```wl
Block[{t = ImportGEDCOM[FileNameJoin[{$TemporaryDirectory, "demo-tree.ged"}]]},
    AllTrue[{"People", "Families"}, AssociationQ[Lookup[First[t], #, Null]] &]
]
```

<!-- => True -->

---

A payload that fails the test matches no UpValue, so [Length]() falls back to its built-in meaning and counts the arguments of the expression instead of its people:

```wl
Length[FamilyTree[<|"People" -> <||>|>]]
```

<!-- => 1 -->

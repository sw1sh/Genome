(* ::Package:: *)

PacletObject[<|
    "Name" -> "WolframInstitute/Genome",
    "PublisherID" -> "WolframInstitute",
    "Version" -> "0.8.0",
    "WolframVersion" -> "14.2+",
    "Description" -> "A lazy handle to a VCF on disk: streaming backends, region and rsID queries as Tabular, a human interpretation layer over public reference data, and a GEDCOM pedigree alongside it",

    "Creator" -> "Genome contributors",
    "License" -> "MIT",
    "Keywords" -> {
        "genomics", "genome", "VCF", "variants", "bioinformatics", "ClinVar",
        "ancestry", "haplogroup", "pharmacogenomics", "polygenic risk", "GWAS",
        "AlphaMissense", "tabix", "genealogy", "GEDCOM", "family tree", "pedigree", "kinship", "transliteration"
    },
    "Categories" -> {"Life Sciences", "Bioinformatics"},
    "PrimaryContext" -> "WolframInstitute`Genome`",
    "Extensions" -> {
        {
            "Kernel",
            "Root" -> "Kernel",
            "Context" -> {"WolframInstitute`Genome`"},
            "Symbols" -> {
                "WolframInstitute`Genome`AlphaMissenseScores",
                "WolframInstitute`Genome`AncestryEstimate",
                "WolframInstitute`Genome`CarrierStatus",
                "WolframInstitute`Genome`ChromosomalSex",
                "WolframInstitute`Genome`ClinVarHits",
                "WolframInstitute`Genome`ExportFamilyTable",
                "WolframInstitute`Genome`ExportGEDCOM",
                "WolframInstitute`Genome`FamilyTree",
                "WolframInstitute`Genome`FamilyTreePlot",
                "WolframInstitute`Genome`FamilyTreeQ",
                "WolframInstitute`Genome`GenealogyLogin",
                "WolframInstitute`Genome`GenealogySearch",
                "WolframInstitute`Genome`Genome",
                "WolframInstitute`Genome`GenomeQ",
                "WolframInstitute`Genome`GenomeReport",
                "WolframInstitute`Genome`GenomeToParquet",
                "WolframInstitute`Genome`GenotypeLookup",
                "WolframInstitute`Genome`GWASAssociations",
                "WolframInstitute`Genome`HaplogroupCall",
                "WolframInstitute`Genome`HumanGenome",
                "WolframInstitute`Genome`HumanGenomeQ",
                "WolframInstitute`Genome`ImportFamilyTable",
                "WolframInstitute`Genome`ImportGEDCOM",
                "WolframInstitute`Genome`ImportGenotypeArray",
                "WolframInstitute`Genome`ImportVCF",
                "WolframInstitute`Genome`ImportVCFHeader",
                "WolframInstitute`Genome`PharmacogenomicProfile",
                "WolframInstitute`Genome`PolygenicRiskScore",
                "WolframInstitute`Genome`RegionVariants",
                "WolframInstitute`Genome`ToBioSequence",
                "WolframInstitute`Genome`TraitAssociations",
                "WolframInstitute`Genome`VariantSummary"
            }
        },
        {
            "Documentation",
            "Root" -> "Documentation",
            "Language" -> "English",
            "MainPage" -> "Guides/Genome"
        },
        {
            "Test",
            "Root" -> "Tests",
            "Method" -> "Experimental-v1"
        },
        {
            "Asset",
            "Root" -> "Assets",
            "Assets" -> {
                {"HeroImage", "hero.png"},
                {"GenealogyBrowser", "genealogy-browser.mjs"}
            }
        }
    }
|>]
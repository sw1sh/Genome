(* Common.wl - part of the WolframInstitute`Genome` paclet.
   A raw implementation file: Get-loaded by Kernel/Genome.wl from
   inside Begin["`Private`"], so it inherits the WolframInstitute`Genome`Private`
   context and has no BeginPackage of its own.  Public ::usage strings
   live in Kernel/Genome.wl; see wl/GUIDE.md for style. *)

(* Summary-box icon shared by the Genome and HumanGenome displays: a short DNA
   duplex, two phase-shifted strands with base-pair rungs between them.  Sized
   in font-cap-height units so it scales with the surrounding cell rather than
   being pinned to a pixel size. *)
$genomeIcon[color_] :=
    Graphics[
        {
            CapForm["Round"],
            {color, AbsoluteThickness[1.7],
                Line[Table[{t, Sin[t]}, {t, 0., 4. Pi, Pi/24}]],
                Line[Table[{t, Sin[t + Pi]}, {t, 0., 4. Pi, Pi/24}]]},
            {Opacity[0.45], color, AbsoluteThickness[1.2],
                Table[Line[{{t, Sin[t]}, {t, Sin[t + Pi]}}], {t, Pi/6, 4. Pi, Pi/6}]}
        },
        PlotRange -> {{-0.4, 4. Pi + 0.4}, {-1.5, 1.5}},
        AspectRatio -> Automatic,
        ImageSize -> Dynamic[{
            Automatic,
            3.2 CurrentValue["FontCapHeight"] / AbsoluteCurrentValue[Magnification]
        }],
        Background -> None,
        ImagePadding -> 0
    ]

(* The accent each head displays in: the paclet's teal for a plain Genome, the
   interpretation layer's purple for a HumanGenome. *)
$genomeAccent = RGBColor[0.184, 0.682, 0.561]
$humanGenomeAccent = RGBColor[0.478, 0.420, 0.816]

(* User-Agent for the public APIs that ask callers to identify themselves
   (SNPedia's bots endpoint, Genomics England PanelApp).  This paclet ships
   publicly, so the default must carry no personal data.  Set GENOME_CONTACT to
   append your own contact address when running a large or repeated crawl -
   those services ask for one as a courtesy, not as a requirement. *)
$genomeUA := With[{contact = Environment["GENOME_CONTACT"]},
    If[ StringQ[contact] && StringLength[contact] > 0,
        "WolframInstitute-Genome/1.0 (" <> contact <> ")",
        "WolframInstitute-Genome/1.0"
    ]
]


(* === shell helpers === *)

(* Single-quote a string for /bin/sh and escape any embedded quotes. *)
shellEscape[s_String] := "'" <> StringReplace[s, "'" -> "'\\''"] <> "'"

(* Pick the right decompressor for a path.  gzcat handles .gz, .bgz and
   (transparently) plain text on macOS, but we still special-case the
   .vcf extension so a non-gzip file is just `cat`'d through. *)
streamCommand[path_String] :=
    If[ StringMatchQ[path, ___ ~~ (".gz" | ".bgz") ~~ EndOfString, IgnoreCase -> True],
        "gzcat " <> shellEscape[path],
        "cat " <> shellEscape[path]
    ]

(* Return True when a program is on PATH.  Uses `command -v` under /bin/sh
   so it works for both shell builtins and external binaries. *)
onPathQ[program_String] :=
    Block[{res},
        res = RunProcess[{"sh", "-c", "command -v " <> shellEscape[program] <> " >/dev/null 2>&1"}];
        MatchQ[res, KeyValuePattern["ExitCode" -> 0]]
    ]

(* === meta-line parsers ===
   The meta lines we care about (INFO / FORMAT / FILTER / contig / ALT)
   all share the shape

       ##Tag=<ID=...,key2=val2,...>

   plus there are bare key=value meta lines like ##fileformat=... and
   ##source=...  We don't fully parse the embedded Description="..."
   text - we just capture the Tag, the ID, and (for contigs) the
   integer Length, which is all the higher layers need. *)

parseStructuredMeta[tag_String, body_String] :=
    Block[{idMatch, lenMatch, id, length},
        idMatch = StringCases[body, "ID=" ~~ v : Shortest[__] ~~ ("," | EndOfString) :> v, 1];
        id = If[ idMatch === {}, Missing[], First[idMatch]];
        If[ tag === "contig",
            lenMatch = StringCases[body, "length=" ~~ d : DigitCharacter .. :> d, 1];
            length = If[ lenMatch === {}, Missing[], FromDigits @ First[lenMatch]];
            <|"Tag" -> tag, "ID" -> id, "Length" -> length|>
            ,
            <|"Tag" -> tag, "ID" -> id|>
        ]
    ]

(* Parse one ## meta line.  Returns either a structured association
   (for Tag=<...> forms) or a Tag -> value rule for bare ##key=value
   forms.  Returns Missing[] if the line doesn't match. *)
parseMetaLine[line_String] :=
    Block[{m, tag, rest},
        m = StringCases[line,
            StartOfString ~~ "##" ~~ t : (WordCharacter ..) ~~ "=" ~~ r___ ~~ EndOfString :> {t, r},
            1
        ];
        If[ m === {}, Return[Missing[]]];
        {tag, rest} = First[m];
        If[ StringStartsQ[rest, "<"] && StringEndsQ[rest, ">"],
            parseStructuredMeta[tag, StringTake[rest, {2, -2}]]
            ,
            tag -> rest
        ]
    ]

(* Stream all header lines (those starting with "#") into a list. *)
readHeaderLines[path_String] :=
    Block[{cmd, out},
        cmd = streamCommand[path] <> " | awk '/^#/{print; next} {exit}'";
        out = RunProcess[{"sh", "-c", cmd}, "StandardOutput"];
        If[ !StringQ[out], Return[$Failed]];
        StringSplit[out, "\n"]
    ]

(* === build inference ===
   We don't have ##reference= in the source file, so infer from the
   contig lengths.  chr1 length and (for GRCh38 disambiguation) chrM
   length are enough to distinguish the three common builds. *)
inferBuild[contigs_List] :=
    Block[{lookup, chr1, chrM},
        lookup = Association @ Map[
            c |-> Lookup[c, "ID", Missing[]] -> Lookup[c, "Length", Missing[]],
            contigs
        ];
        chr1 = Lookup[lookup, "chr1", Lookup[lookup, "1", Missing[]]];
        chrM = Lookup[lookup, "chrM", Lookup[lookup, "MT", Lookup[lookup, "M", Missing[]]]];
        Which[
            chr1 === 249250621, "GRCh37/hg19",
            chr1 === 248956422 && chrM === 16569, "GRCh38",
            chr1 === 248387328, "T2T-CHM13v2.0",
            True, "Unknown"
        ]
    ]


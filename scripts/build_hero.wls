#!/usr/bin/env wolframscript
(* Genome hero: a Circos-style circular genome plot.

   The ring is the GRCh37 reference itself: 22 autosomes plus X, Y and MT drawn
   as ideograms scaled to their real assembly lengths, with the real centromere
   constriction of each chromosome.  Reading from the outside in, each concentric
   track stands for one of the paclet's analysis domains, and everything converges
   on the report hub at the centre:

     outer index blocks   Backends            Tabix random access, Parquet row groups
     ideogram ring        Reference           GRCh37 lengths and centromeres
     X / Y / MT arcs      Ancestry & lineage  sex, mtDNA and Y haplogroups
     bar track            Import              variants loaded per 10 Mb window
     point track          Clinical            per variant pathogenicity scores
     heat ring            Traits & risk       polygenic weight along the genome
     chords               Query               region and point lookups
     hub                  Report              every track above, one document

   PRIVACY / REPRODUCIBILITY.  Nothing here is read from anybody's genome.  The
   only real numbers in this file are public reference constants (GRCh37
   chromosome lengths and UCSC hg19 centromere coordinates).  Every plotted
   value in the bar, point, heat and chord tracks is synthetic: it comes from the
   fixed SeedRandom below or from an analytic periodic curve, so the render is reproducible
   pixel for pixel, and the export drops the timestamp chunks so the FILE is byte for byte
   reproducible too.

   Run:  wolframscript -f scripts/build_hero.wls
*)

root = ParentDirectory[DirectoryName[ExpandFileName[$InputFileName]]];
outDir = FileNameJoin[{root, "Genome", "Assets"}];
outFile = FileNameJoin[{outDir, "hero.png"}];
If[ ! DirectoryQ[outDir], CreateDirectory[outDir, CreateIntermediateDirectories -> True]];

(* imgSize is the LAYOUT size in points (font sizes below are absolute, so they are
   scaled by hand against it); rasterSize is the pixel width of the PNG.  Both are pinned
   here because ImageSize alone hands the pixel count to the host display - a Retina Mac
   rasterises it at 2x and a 1x or headless Linux box at 1x, so the same commit would
   otherwise ship a half-resolution asset depending on where it was built. *)
imgSize = 3000;
rasterSize = 6000;
fs[frac_] := frac imgSize;       (* font sizes are absolute, so scale them by hand *)

(* ---------------- palette ---------------- *)

ground = RGBColor["#06080c"];
glow = RGBColor["#0b1524"];
steel = RGBColor["#8496ad"];
dimSteel = RGBColor["#4d5a6d"];
paper = RGBColor["#ccd8e8"];      (* ideogram body *)
paperAlt = RGBColor["#a7b6cb"];   (* alternating chromosome, for separation *)
pinchCol = RGBColor["#5d6b81"];   (* centromere *)

cImport = RGBColor["#31d1bd"];    (* teal      *)
cBackend = RGBColor["#3d9ae6"];   (* azure     *)
cQuery = RGBColor["#7d6ceb"];     (* indigo    *)
cLineage = RGBColor["#cc63dc"];   (* orchid    *)
cClinical = RGBColor["#f2584f"];  (* coral     *)
cTrait = RGBColor["#f5a33c"];     (* amber     *)
cReport = RGBColor["#ffd45e"];    (* gold      *)

(* ---------------- reference constants ---------------- *)

(* GRCh37 / hg19 chromosome lengths in bases, and the UCSC hg19 centromere gap
   interval.  Public reference values, written as literals on purpose. *)
chroms = {
  {"1", 249250621, 121535434, 124535434},
  {"2", 243199373, 92326171, 95326171},
  {"3", 198022430, 90504854, 93504854},
  {"4", 191154276, 49660117, 52660117},
  {"5", 180915260, 46405641, 49405641},
  {"6", 171115067, 58830166, 61830166},
  {"7", 159138663, 58054331, 61054331},
  {"8", 146364022, 43838887, 46838887},
  {"9", 141213431, 47367679, 50367679},
  {"10", 135534747, 39254935, 42254935},
  {"11", 135006516, 51644205, 54644205},
  {"12", 133851895, 34856694, 37856694},
  {"13", 115169878, 16000000, 19000000},
  {"14", 107349540, 16000000, 19000000},
  {"15", 102531392, 17000000, 20000000},
  {"16", 90354753, 35335801, 38335801},
  {"17", 81195210, 22263006, 25263006},
  {"18", 78077248, 15460898, 18460898},
  {"19", 59128983, 24681782, 27681782},
  {"20", 63025520, 26369569, 29369569},
  {"21", 48129895, 11288129, 14288129},
  {"22", 51304566, 13000000, 16000000},
  {"X", 155270560, 58632012, 61632012},
  {"Y", 59373566, 10104553, 13104553},
  {"MT", 16569, None, None}
};

names = chroms[[All, 1]];
lens = chroms[[All, 2]];
nChr = Length[chroms];
nuc = 24;                         (* 1 to 22, X, Y: everything drawn to scale *)

(* ---------------- angular layout ---------------- *)

gapTop = 10 Degree;               (* the conventional circos gap, at 12 o'clock *)
gapChr = 0.55 Degree;
mtArc = 2.2 Degree;               (* MT is 16.6 kb: at genome scale it has no arc *)

usable = 360 Degree - gapTop - (nChr - 1) gapChr - mtArc;
perBase = usable/Total[lens[[;; nuc]]];

aStart = ConstantArray[0., nChr];
aEnd = ConstantArray[0., nChr];
cursor = 90 Degree - gapTop/2;    (* clockwise from just right of 12 o'clock *)
Do[
  aStart[[i]] = cursor;
  aEnd[[i]] = cursor - If[i <= nuc, lens[[i]] perBase, mtArc];
  cursor = aEnd[[i]] - gapChr,
  {i, nChr}];

polar[a_, r_] := r {Cos[a], Sin[a]};
angleAt[i_, frac_] := aStart[[i]] + frac (aEnd[[i]] - aStart[[i]]);
posAngle[i_, p_] := angleAt[i, p/lens[[i]]];

arcPts[a1_, a2_, r_] := polar[#, r] & /@ Subdivide[a1, a2, Max[2, Ceiling[Abs[a2 - a1]/(0.35 Degree)]]];
band[a1_, a2_, r1_, r2_] := Polygon[Join[arcPts[a1, a2, r1], Reverse[arcPts[a1, a2, r2]]]];
(* A rounded arc segment whose PAINTED extent is exactly a1 to a2 - the invariant the ring
   depends on, since the footnote claims real assembly length.  A cap of half-width w
   centred on the midline at radius rm covers ArcSin[w/rm] of angle either side of its
   centre, so centring the caps ON the endpoints paints that much phantom sequence past
   each end: 1.65 deg here, 3.3 deg per chromosome, six times the 0.55 deg gap between
   chromosomes.  So the band and its caps are inset by that half-angle instead.  A segment
   shorter than its own two caps (chrY's p arm, MT, the acrocentric short arms) gets a cap
   flattened along the arc - an ellipse w deep and rm Sin[cap] wide, rotated so its deep
   axis is radial - which keeps the full ring thickness and the rounded profile while still
   ending where the chromosome does. *)
roundBand[a1_, a2_, r1_, r2_] :=
  Module[{rm = (r1 + r2)/2, w = (r2 - r1)/2, cap, ax, dir, b1, b2},
    cap = Min[ArcSin[Min[1, w/rm]], Abs[a2 - a1]/2];
    ax = rm Sin[cap];                (* along-arc semi-axis; equals w for a full cap *)
    dir = Sign[a2 - a1];
    b1 = a1 + dir cap; b2 = a2 - dir cap;
    {band[b1, b2, r1, r2],
     Rotate[Disk[polar[b1, rm], {w, ax}], b1, polar[b1, rm]],
     Rotate[Disk[polar[b2, rm], {w, ax}], b2, polar[b2, rm]]}
  ];

(* ---------------- track radii ---------------- *)

rParq = {1.058, 1.076};           (* Parquet row groups   *)
rTbx = {1.022, 1.040};            (* Tabix index blocks   *)
rIdeo = {0.944, 1.000};           (* ideogram ring        *)
rBar = {0.802, 0.930};            (* import density       *)
rDot = {0.656, 0.786};            (* clinical scores      *)
rHeat = {0.524, 0.596};           (* traits and risk      *)
rChord = 0.498;                   (* query links          *)
rHub = 0.302;
rLabel = 1.152;

(* ---------------- synthetic tracks ---------------- *)

SeedRandom[20260830];
smooth[v_] := MovingAverage[Join[{First[v]}, v, {Last[v]}], 3];

(* Bar track: a smoothed random walk per chromosome, thinned near the centromere
   and the telomeres the way a real callable density is.  Synthetic throughout. *)
density[len_, cen_] :=
  Module[{nb, v, p, dip},
    nb = Max[5, Round[len/10000000]];
    v = Nest[smooth, RandomReal[{0, 1}, nb], 2];
    v = Rescale[v, MinMax[v], {0.24, 1.}];
    p = (Range[nb] - 0.5) len/nb;
    dip = If[cen === None, ConstantArray[1., nb], 1 - 0.82 Exp[-((p - cen)/(0.05 len))^2]];
    v dip (1 - 0.45 Exp[-(p/(0.022 len))^2]) (1 - 0.45 Exp[-((len - p)/(0.022 len))^2])
  ];
bars = Table[density[lens[[i]], If[chroms[[i, 3]] === None, None, Mean[{chroms[[i, 3]], chroms[[i, 4]]}]]], {i, nuc}];

(* Point track: 1100 synthetic variants, scores drawn from a beta so that most sit
   low and a handful reach the pathogenic end of the track. *)
nPts = 1100;
ptChr = RandomChoice[N[lens[[;; nuc]]] -> Range[nuc], nPts];
ptFrac = RandomReal[{0, 1}, nPts];
ptScore = RandomVariate[BetaDistribution[1.7, 4.2], nPts];

(* Heat track: an analytic periodic curve, a seeded truncated Fourier series,
   with a little per tile jitter so it reads as binned weight rather than a ramp. *)
harm = Range[3, 16];
amps = RandomReal[{0.2, 1}, Length[harm]]/harm^0.7;
phases = RandomReal[{0, 2 Pi}, Length[harm]];
wave[a_] := Total[amps Sin[harm a + phases]];
waveRange = MinMax[wave /@ Subdivide[0., 2 Pi, 720]];
waveAt[a_] := Rescale[wave[a], waveRange, {0.04, 1.}];

(* Chords: 30 synthetic locus to locus links. *)
nChord = 30;
chordEnds = Table[{RandomChoice[N[lens[[;; nuc]]] -> Range[nuc]], RandomReal[]}, {nChord}, {2}];
chordW = RandomReal[{0.4, 1}, nChord];

(* ---------------- drawing ---------------- *)

(* soft radial bloom behind the ring, built from stacked translucent discs *)
bloom = Table[{Opacity[0.016], glow, Disk[{0, 0}, r]}, {r, Subdivide[1.42, 0.24, 44]}];

(* Backends: stylised index granularity.  Fine blocks stand for Tabix random
   access, coarse blocks for Parquet row groups; the block rhythm is nominal. *)
indexRing[step_, radii_, col_, op_] :=
  Table[
    Module[{len = lens[[i]], k, a1, a2},
      Table[
        a1 = posAngle[i, Min[k step, len]];
        a2 = posAngle[i, Min[(k + 1) step, len]];
        If[EvenQ[k] && a1 =!= a2, {Opacity[op], col, band[a1, a2, radii[[1]], radii[[2]]]}, {}],
        {k, 0, Ceiling[len/step] - 1}]
    ],
    {i, nuc}];

ideogram = Table[
  Module[{nm = names[[i]], len = lens[[i]], cs = chroms[[i, 3]], ce = chroms[[i, 4]],
          col, a1, a2, ac, pinch = 0.34 Degree},
    a1 = aStart[[i]]; a2 = aEnd[[i]];
    col = Which[nm === "MT", RGBColor["#ff8fd8"], nm === "Y", RGBColor["#a24fd0"], nm === "X", cLineage,
      OddQ[i], paper, True, paperAlt];
    If[cs === None,
      {col, roundBand[a1, a2, rIdeo[[1]], rIdeo[[2]]]},
      ac = posAngle[i, Mean[{cs, ce}]];
      {
        col,
        roundBand[a1, ac + pinch, rIdeo[[1]], rIdeo[[2]]],
        roundBand[ac - pinch, a2, rIdeo[[1]], rIdeo[[2]]],
        pinchCol, band[ac + pinch, ac - pinch, rIdeo[[1]] + 0.016, rIdeo[[2]] - 0.016]
      }
    ]
  ],
  {i, nChr}];

(* a 25 Mb ruler engraved into the ideogram, so the ring is visibly to scale *)
ruler = Table[
  Module[{len = lens[[i]], cs = chroms[[i, 3]], ce = chroms[[i, 4]], a},
    Table[
      If[cs =!= None && cs - 4000000 < p < ce + 4000000, {},
        a = posAngle[i, p];
        {Opacity[0.55], ground, Thickness[0.0008], Line[{polar[a, rIdeo[[1]] + 0.004], polar[a, rIdeo[[2]] - 0.004]}]}
      ],
      {p, 25000000, len - 12000000, 25000000}]
  ],
  {i, nuc}];

barBase = {Opacity[0.28], dimSteel, Thickness[0.0006], Circle[{0, 0}, rBar[[1]]]};

sectorMarks = Table[
  {Opacity[0.10], steel, Thickness[0.0006],
   Line[{polar[aStart[[i]], rChord], polar[aStart[[i]], rIdeo[[1]] - 0.006]}]},
  {i, nuc}];

barTrack = Table[
  Module[{v = bars[[i]], nb, len = lens[[i]], a1, a2, am, half, r},
    nb = Length[v];
    Table[
      a1 = angleAt[i, (k - 1)/nb]; a2 = angleAt[i, k/nb];
      am = (a1 + a2)/2; half = 0.40 (a1 - a2);
      r = rBar[[1]] + v[[k]] (rBar[[2]] - rBar[[1]]);
      {Blend[{Darker[cImport, 0.55], cImport, Lighter[cImport, 0.35]}, v[[k]]],
       band[am + half, am - half, rBar[[1]], r]},
      {k, nb}]
  ],
  {i, nuc}];

dotTrack = Table[
  Module[{a = angleAt[ptChr[[k]], ptFrac[[k]]], s = ptScore[[k]], r, hot},
    r = rDot[[1]] + s (rDot[[2]] - rDot[[1]]);
    hot = s > 0.72;
    {If[hot, {Opacity[0.22], cClinical, Disk[polar[a, r], 0.013]}, {}],
     Opacity[If[hot, 1, 0.85]],
     Blend[{RGBColor["#4a5468"], RGBColor["#b8564f"], cClinical, RGBColor["#ff8f66"]}, s],
     Disk[polar[a, r], 0.0032 + 0.0042 s]}
  ],
  {k, nPts}];

heatTrack = Table[
  Module[{len = lens[[i]], nb, a1, a2, v},
    nb = Max[4, Round[len/9000000]];
    Table[
      a1 = angleAt[i, (k - 1)/nb]; a2 = angleAt[i, k/nb];
      v = Clip[waveAt[(a1 + a2)/2] + RandomReal[{-0.15, 0.15}], {0.02, 1}]^1.5;
      {Blend[{RGBColor["#17100a"], RGBColor["#5c3210"], RGBColor["#c8801f"], RGBColor["#ffce7d"]}, v],
       band[a1, a2 + 0.03 Degree, rHeat[[1]], rHeat[[2]]]},
      {k, nb}]
  ],
  {i, nuc}];

(* the pathogenic end of the point track, marked the way a score cutoff is *)
dotGuide = {Opacity[0.28], cClinical, Thickness[0.0007],
  Dashing[{0.004, 0.006}], Circle[{0, 0}, rDot[[1]] + 0.72 (rDot[[2]] - rDot[[1]])]};

chordTrack = Table[
  Module[{p1, p2, w = chordW[[k]]},
    p1 = polar[angleAt @@ chordEnds[[k, 1]], rChord];
    p2 = polar[angleAt @@ chordEnds[[k, 2]], rChord];
    {{Opacity[0.17 + 0.30 w], Blend[{cQuery, RGBColor["#4fb4ef"]}, 0.55 w], Thickness[0.0006 + 0.0016 w],
      CapForm["Round"], BezierCurve[{p1, 0.22 (p1 + p2), p2}]},
     {Opacity[0.7], Blend[{cQuery, RGBColor["#4fb4ef"]}, 0.55 w], Disk[p1, 0.0038], Disk[p2, 0.0038]}}
  ],
  {k, nChord}];

chrLabels = Table[
  Text[Style[names[[i]], If[MemberQ[{"X", "Y", "MT"}, names[[i]]], Lighter[cLineage, 0.35], paper],
      FontFamily -> "Helvetica Neue", FontWeight -> Bold, FontSize -> fs[If[names[[i]] === "MT", 0.0115, 0.0145]]],
    polar[(aStart[[i]] + aEnd[[i]])/2, rLabel]],
  {i, nChr}];

tracked[s_] := StringRiffle[Characters[s], "\[ThinSpace]"];

hub = {
  ground, Disk[{0, 0}, rHub],
  {Opacity[0.55], cReport, Thickness[0.0012], Circle[{0, 0}, rHub]},
  {Opacity[0.22], cReport, Thickness[0.0008], Circle[{0, 0}, rHub + 0.018]},
  Text[Style[tracked["WOLFRAM INSTITUTE"], dimSteel, FontFamily -> "Helvetica Neue",
      FontSize -> fs[0.008]], {0, 0.104}],
  Text[Style["Genome", White, FontFamily -> "Helvetica Neue", FontWeight -> Bold,
      FontSize -> fs[0.0425]], {0, 0.004}],
  {Opacity[0.5], cReport, Thickness[0.0009], Line[{{-0.088, -0.082}, {0.088, -0.082}}]},
  Text[Style[tracked["REPORT"], cReport, FontFamily -> "Helvetica Neue",
      FontSize -> fs[0.0098]], {0, -0.128}]
};

topMark = Text[Style[tracked["GRCh37"], steel, FontFamily -> "Helvetica Neue",
    FontSize -> fs[0.0105]], {0, 1.253}];

(* ---------------- legend ---------------- *)

glyph[kind_, {x_, y_}, col_] := Module[{u = 0.030},
  {col,
   Switch[kind,
    "bars", With[{hs = {0.017, 0.031, 0.022, 0.039, 0.026}},
      Table[Rectangle[{x - u + 0.0132 (k - 1), y - 0.020}, {x - u + 0.0132 (k - 1) + 0.0085, y - 0.020 + hs[[k]]}],
        {k, Length[hs]}]],
    "blocks", Table[Rectangle[{x - u + 0.0165 k, y - 0.007}, {x - u + 0.0165 k + 0.010, y + 0.007}], {k, 0, 2}],
    "chord", {Thickness[0.0016], CapForm["Round"],
      Line[{{x - u, y + 0.018}, {x + u, y + 0.018}}],
      BezierCurve[{{x - u + 0.004, y + 0.016}, {x, y - 0.030}, {x + u - 0.004, y + 0.016}}]},
    "lineage", {Rectangle[{x - 0.024, y - 0.021}, {x - 0.010, y + 0.021}],
      Rectangle[{x + 0.002, y - 0.021}, {x + 0.016, y + 0.008}]},
    "dots", With[{ds = {0.010, 0.032, 0.018, 0.040, 0.014, 0.028}},
      Table[Disk[{x - u + 0.0118 (k - 1), y - 0.020 + ds[[k]]}, 0.0058], {k, Length[ds]}]],
    "heat", With[{vs = {0.25, 0.55, 0.8, 1.}},
      Table[{Blend[{RGBColor["#3a2510"], RGBColor["#5c3210"], RGBColor["#c8801f"], RGBColor["#ffce7d"]}, vs[[k]]],
        Rectangle[{x - u + 0.0155 (k - 1), y - 0.014}, {x - u + 0.0155 (k - 1) + 0.0115, y + 0.014}]},
        {k, Length[vs]}]],
    "ring", {Thickness[0.0016], Circle[{x, y}, 0.021], Disk[{x, y}, 0.007]}
   ]}
];

legend = {
  {"Import", cImport, "bars", "ImportVCF, genotype arrays"},
  {"Backends", cBackend, "blocks", "Tabix, Parquet, awk stream"},
  {"Query", cQuery, "chord", "GenotypeLookup, regions"},
  {"Ancestry", cLineage, "lineage", "sex, mtDNA and Y lineage"},
  {"Clinical", cClinical, "dots", "ClinVarHits, CarrierStatus"},
  {"Traits & risk", cTrait, "heat", "GWAS, polygenic risk"},
  {"Report", cReport, "ring", "every track, one document"}
};

legendGfx = Table[
  Module[{cx = -1.17 + 0.39 (i - 1), it = legend[[i]]},
    {glyph[it[[3]], {cx - 0.147, -1.312}, it[[2]]],
     Text[Style[it[[1]], it[[2]], FontFamily -> "Helvetica Neue", FontWeight -> Bold,
        FontSize -> fs[0.0135]], {cx - 0.107, -1.312}, {-1, 0}],
     Text[Style[it[[4]], steel, FontFamily -> "Helvetica Neue", FontSize -> fs[0.0092]],
      {cx - 0.178, -1.390}, {-1, 0}]}
  ],
  {i, Length[legend]}];

footNote = Text[Style["GRCh37 ideograms drawn to real assembly length; MT arc is nominal. Track values are seeded synthetic data.",
    RGBColor["#3a4657"], FontFamily -> "Helvetica Neue", FontSize -> fs[0.008]], {0, -1.442}];

g = Graphics[{
    bloom,
    {Opacity[0.32], dimSteel, Thickness[0.0006], Line[{{-1.30, -1.232}, {1.30, -1.232}}]},
    indexRing[60000000, rParq, cBackend, 0.45],
    indexRing[10000000, rTbx, cBackend, 0.95],
    sectorMarks,
    chordTrack,
    heatTrack,
    dotGuide,
    dotTrack,
    barBase,
    barTrack,
    ideogram,
    ruler,
    chrLabels,
    topMark,
    hub,
    legendGfx,
    footNote
  },
  Background -> ground, PlotRange -> {{-1.39, 1.39}, {-1.478, 1.30}},
  PlotRangePadding -> None, AspectRatio -> Automatic, ImagePadding -> None];

img = Rasterize[g, ImageSize -> imgSize, RasterSize -> rasterSize, Background -> ground];
(* hero.png is a TRACKED asset, so the file - not just the pixels - has to be reproducible:
   without this the PNG carries an eXIf DateTime and a tEXt Creation Time, and every rebuild
   dirties the working tree with a zero-pixel diff. *)
Export[outFile, img, IncludeMetaInformation -> None];
Print["wrote ", outFile, " ", ImageDimensions[img], " ", FileByteCount[outFile], " bytes"];

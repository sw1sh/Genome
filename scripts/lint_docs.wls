#!/usr/bin/env wolframscript
(* House-style lint for the repo's markdown: the paclet doc sources under docs/
   plus the top-level pages (README, AGENTS, GUIDE).
   The top level is in scope because a WL context name ends in a
   backtick, so a context written in a single-backtick span (`System`Private`)
   closes the span early and silently corrupts the text - a class of bug that had
   reached both GUIDE.md and the #73 audit ledger while they were unlinted.
   Outside fenced ``` blocks it checks that
     - every inline code span closes with a run of the same backtick length,
       within its paragraph and on a single line (CommonMark allows a span to
       swallow a newline, which is how a wrapped span silently breaks a page), and
     - every paragraph has an even number of $ characters outside code spans
       (each $...$ formula opened is closed), and
     - no <code> ... </code> span carries a backslash macro, a superscript, an
       expression subscript, a dollar-wrapped ellipsis or two tokens in one slot
       (inside a span the $...$ is an argument slot, not a LaTeX span, so each of
       these leaks raw onto the built page), and
     - no word sits raw in inline math, in prose or in a signature slot
       (a word there sets as a product of italic letters), and
     - tables on symbol pages use a blank header row, as required by the
       reference-page convention (option tables, Notes property tables, etc.).
   It also checks that every `#| annotation:` marker carries a leading date in
   YY.MM.DD order (year >= 24, month 01-12, day 01-31); a reversed DD.MM.YY such
   as 20.07.26 for 2026-07-20 parses as a plausible date and otherwise slips past
   review. Only a numeric date is checked, so the skill's literal `YY.MM.DD`
   placeholder and prose mentions are left alone.
   Prints file:line findings and exits 1 if any. *)

repoDir = FileNameDrop[ExpandFileName[First[$ScriptCommandLine]], -2];

files = Join[
	(* top-level pages: README.md, AGENTS.md, CLAUDE.md, CONTRIBUTING.md, GUIDE.md, ... *)
	FileNames["*.md", repoDir],
	(* docs/** - the published doc sources and the ResourceDefinition.md
	   front page, the one public page the lint once never saw *)
	Join @@ Map[
		FileNames["*.md", FileNameJoin[{repoDir, #}], Infinity] &,
		Select[{"docs"},
			DirectoryQ[FileNameJoin[{repoDir, #}]] &]
	]
];

violations = {};
report[f_, line_, msg_] := AppendTo[violations, StringJoin[StringDrop[f, StringLength[repoDir] + 1], ":", ToString[line], ": ", msg]];

(* paragraphs as {lineNumber, text} runs, with the YAML frontmatter block and
   fenced code blocks removed *)
paragraphs[lines_List] := Module[{inFence = False, start = 1, kept},
	If[Length[lines] > 0 && StringTrim[lines[[1]]] === "---",
		start = 1 + FirstCase[Range[2, Length[lines]], i_ /; StringTrim[lines[[i]]] === "---" :> i, 1]
	];
	kept = Reap[
		Do[
			Which[
				StringMatchQ[StringTrim[lines[[i]]], "```" ~~ ___], inFence = ! inFence,
				! inFence, Sow[{i, lines[[i]]}]
			],
			{i, start, Length[lines]}
		]
	][[2]];
	If[kept === {}, {}, Split[First[kept], StringTrim[#2[[2]]] =!= "" &]] // Map[Select[StringTrim[#[[2]]] =!= "" &]] // Select[# =!= {} &]
]

(* CommonMark inline-code scan over one paragraph: an opener run of n backticks is
   closed by the next run of exactly n; the span must not contain a newline *)
(* blank a substring range, preserving newlines so line numbering survives *)
blankRange[text_, {a_, b_}] := StringReplacePart[text,
	StringReplace[StringTake[text, {a, b}], Except["\n"] -> " "], {a, b}]

(* A $...$ inside a <code> ... </code> span is the documentation template's
   ARGUMENT SLOT, not a LaTeX span: the slot understands a plain name and a plain
   subscript ($x_1$, $q_{max}$) and passes a Unicode letter through, but no
   backslash macro survives it. The macro leaks onto the built page as a literal
   dollar, a literal backslash and the macro name, so \alpha must be written as
   the Unicode letter and \dots / \ldots as a plain ellipsis character. Math in
   PROSE is parsed by the LaTeX handler, where the macros are correct - this rule
   looks only inside the span, and skips a backticked run within it (literal WL
   source, where a character escape is real code). *)
(* Four constructs beyond a macro break the same way, each checked against the
   converter: a SUPERSCRIPT ($m^2$ leaks both dollars), a SUBSCRIPT THAT IS AN
   EXPRESSION ($a_{k-1}$ sets the operator outside the script and reads a_k - 1),
   a DOLLAR-WRAPPED ELLIPSIS ($...$ leaks its dollars even with the character
   inside) and TWO TOKENS IN ONE SLOT ($a b$). A slot already carrying a
   backslash belongs to the macro rule above, so it is left to it. The Unicode
   superscript digit that fixes $m^2$ does NOT compose with a subscript - $m_0^2$
   has no slot spelling at all and has to be rewritten. *)
superscriptDigits = "\.b2\.b3\.b9\:2070\:2074\:2075\:2076\:2077\:2078\:2079";
slotProblem[slot_String] := Module[
	{s = StringTake[slot, {2, -2}], scripts},
	scripts = StringCases[s, RegularExpression["_\\{([^}]*)\\}"] -> "$1"];
	Which[
		StringContainsQ[s, "\\"], Missing[],
		StringContainsQ[s, "_"] && StringContainsQ[s, Alternatives @@ Append[Characters[superscriptDigits], "^"]],
			"a subscript and a superscript together - a slot carries one script only; name the argument plainly and let the prose square it",
		StringContainsQ[s, "^"],
			"a superscript - take the Unicode superscript digit, or set the formula in prose math beside the span",
		AnyTrue[scripts, StringContainsQ[#, RegularExpression["[-+*/ ]"]] &],
			"a subscript that is an expression - it sets the operator outside the script, so $a_{k-1}$ reads a_k - 1",
		StringContainsQ[s, "\[Ellipsis]"],
			"a dollar-wrapped ellipsis - write the bare character next to the slots",
		StringContainsQ[s, RegularExpression["[A-Za-z0-9]\\s+[A-Za-z0-9]"]],
			"two tokens in one slot - give each its own $...$",
		True, Missing[]
	]
]

(* A WORD NEVER SITS RAW IN INLINE MATH. $topology$ is a product of eight italic
   letters, so the built page reads t o p o l o g y, not the word. An argument
   placeholder takes the markdown italic form (*topology*); a word a formula
   genuinely needs takes \text{...} or the macro that already exists for it
   (\max, \gcd, \deg). What counts as a word here: a run of THREE OR MORE letters
   that are lowercase after the first. Everything else is left alone, because the
   mathematics is full of juxtaposed single-letter symbols - $ab$, $dx$, $xy$,
   $uv$ and $BC$ are products, $NkT$, $gMr$, $hZZ$, $iHt$, $LTL$ and $SU$ are
   symbol runs. Two-letter runs are left to the author for that reason: the docs
   spell about two hundred distinct ones and not one of them is a word. Three
   letters is where the reading flips, and the genuine cases above that line are
   few enough to name one by one in the allowlist below. *)

(* THE ALLOWLIST. Each entry is a real run of mathematical symbols that happens
   to spell letters. To add one, put it in the group it belongs to with a comment
   naming the mathematics - a bare string with no reason is what this rule
   exists to catch. *)
mathWordAllowlist = {
	(* index runs - abstract or tensor indices written side by side *)
	"abc", "acb", "abcd", "acbd", "bacd", "acd", "bcd", (* Riemann, Weyl, Cotton, Levi-Civita, f^{abc} *)
	"ijk", "jik", "ijm", "mkl",                         (* structure constants f_{ijk} and the Jacobi identity *)
	"smn", "srn",                                       (* R^r{}_{smn}, contracted to R_{sn} *)
	"trtr",                                             (* the (t,r,t,r) component of the Weyl tensor *)
	"xxx",                                              (* the third x-derivative, u_{xxx} *)
	(* words over an alphabet - the rewriting pages spell their strings out *)
	"aaa", "aba", "bab", "abab", "ababab", "abababab",
	(* products of single-letter variables *)
	"xyz",                                              (* the monomial x y z *)
	"ikx"                                               (* i k x, in e^{ikx} *)
};

(* These macros SET their argument as text - the letters inside are typeset as a
   word already, which is exactly what the rule asks for. *)
mathTextWrappers = "text|textrm|textit|textbf|textsf|mathit|mathrm|mathbf|mathsf|mathtt|mathcal|mathbb|mathfrak|mathscr|operatorname|begin|end";
(* Words left raw in one math span. exemptScripts is for a <code> argument slot,
   where a plain subscript is the sanctioned spelling ($v_{min}$) because a macro
   leaks there; in prose a word in a script is a word like any other ($Z_{Ising}$
   is written $Z_{\text{Ising}}$). *)
mathWordRuns[math_String, exemptScripts_ : False] := Module[{s},
	s = StringReplace[math, RegularExpression["^\\$+|\\$+$"] -> ""];
	s = StringReplace[s, RegularExpression["\\\\(" <> mathTextWrappers <> ")\\*?\\s*\\{[^{}]*\\}"] -> " "];
	s = StringReplace[s, RegularExpression["\\\\[A-Za-z]+"] -> " "];  (* any other macro is a rendered symbol, not letters *)
	s = StringReplace[s, RegularExpression["[A-Za-z]+(?=_)"] -> " "]; (* a subscripted name is a sanctioned spelling *)
	If[ exemptScripts,
		s = StringReplace[s, RegularExpression["_(\\{[^{}]*\\}|[A-Za-z0-9]+)"] -> " "]
	];
	DeleteDuplicates @ Select[
		StringCases[s, RegularExpression["[A-Za-z][a-z]{2,}"]],
		! MemberQ[mathWordAllowlist, #] &
	]
]
(* every $...$ or $$...$$ span in a stretch of text, as {start, end} pairs *)
mathSpans[text_String] := StringPosition[text,
	RegularExpression["\\$\\$[^$]*\\$\\$|\\$[^$]*\\$"], Overlaps -> False]

lintCodeSpan[f_, line_, inner_String] := Module[
	{macros, slots},
	macros = DeleteDuplicates[StringCases[inner, RegularExpression["\\\\[A-Za-z]+"]]];
	If[ macros =!= {},
		report[f, line, StringJoin[
			"backslash macro ", StringRiffle[macros, ", "], " inside a <code> span - ",
			"the $...$ there is an argument slot, not a LaTeX span, so the macro leaks ",
			"raw onto the built page: use the Unicode letter, or a plain ellipsis character"]]
	];
	slots = DeleteDuplicates[StringCases[inner, RegularExpression["\\$[^$]*\\$"]]];
	Scan[
		report[f, line, StringJoin[
			"argument slot ", First[#], " in a <code> span carries ", Last[#],
			" (the slot is not a LaTeX span, so it does not survive to the built page)"]] &,
		Select[Map[{#, slotProblem[#]} &, slots], ! MissingQ[Last[#]] &]
	];
	(* the word rule, in the slot's own terms: a placeholder is spelled *name* *)
	Scan[
		Function[slot,
			Scan[
				report[f, line, StringJoin[
					"the word \"", #, "\" sits raw in the signature slot ", slot,
					" - it sets as a product of italic letters, so an argument placeholder ",
					"takes the markdown italic form *", #, "* here and everywhere else it appears"]] &,
				mathWordRuns[slot, True]
			]
		],
		slots
	]
]

(* CommonMark-order scan: backtick code spans bind before raw HTML, so pair the
   backtick runs first, then blank only the <code>...</code> pairs whose tags lie
   OUTSIDE backtick spans (real markup, which legitimately carries WL context
   backticks and $arg$ tokens), and lint the result *)
scanParagraph[f_, para_List] := Module[
	{text, offsets, lineAt, pairSpans, spans, inSpan, opens, closes, inner, tagPairs, runs, i, j, n},
	text = StringRiffle[para[[All, 2]], "\n"];
	(* author-only <!-- ... --> comments are stripped by the converter *)
	text = StringReplace[text,
		s : ("<!--" ~~ Shortest[___] ~~ "-->") :> StringReplace[s, Except["\n"] -> " "]];
	offsets = Prepend[Accumulate[StringLength /@ para[[All, 2]]] + Range[Length[para]], 0];
	lineAt = Function[pos, para[[LengthWhile[Most[offsets], # < pos &], 1]]];
	pairSpans = Function[t, Module[{rs, k, m, len, out = {}},
		rs = StringPosition[t, RegularExpression["`+"], Overlaps -> False];
		k = 1;
		While[k <= Length[rs],
			len = rs[[k, 2]] - rs[[k, 1]] + 1;
			m = SelectFirst[Range[k + 1, Length[rs]], rs[[#, 2]] - rs[[#, 1]] + 1 === len &, Missing[]];
			If[MissingQ[m],
				AppendTo[out, {rs[[k, 1]], rs[[k, 2]], "stray"}]; k++,
				AppendTo[out, {rs[[k, 1]], rs[[m, 2]], "span"}]; k = m + 1
			]
		];
		out
	]];
	spans = pairSpans[text];
	inSpan = Function[pos, AnyTrue[spans, #[[3]] === "span" && #[[1]] <= pos <= #[[2]] &]];
	opens = Select[StringPosition[text, "<code>"], ! inSpan[#[[1]]] &];
	closes = Select[StringPosition[text, "</code>"], ! inSpan[#[[1]]] &];
	While[opens =!= {},
		j = SelectFirst[closes, #[[1]] > opens[[1, 2]] &, Missing[]];
		If[MissingQ[j], Break[]];
		(* lint the span's own content first, with any backticked run inside it blanked *)
		inner = StringTake[text, {opens[[1, 2]] + 1, j[[1]] - 1}];
		inner = Fold[blankRange[#1, Most[#2]] &, inner, Select[pairSpans[inner], #[[3]] === "span" &]];
		lintCodeSpan[f, lineAt[opens[[1, 1]]], inner];
		text = blankRange[text, {opens[[1, 1]], j[[2]]}];
		opens = Select[opens, #[[1]] > j[[2]] &];
		closes = Select[closes, #[[1]] > j[[2]] &]
	];
	(* the lint proper, on the comment- and markup-blanked text *)
	spans = pairSpans[text];
	Do[
		Switch[s[[3]],
			"stray", report[f, lineAt[s[[1]]], "backtick code span never closes (stray or unbalanced backticks)"],
			"span", If[StringContainsQ[StringTake[text, {s[[1]], s[[2]]}], "\n"],
				report[f, lineAt[s[[1]]], "backtick code span wraps across a line break - keep each span whole on one line"]]
		],
		{s, spans}
	];
	(* $-parity, and the word rule, on the text outside code spans *)
	Module[{stripped = Fold[blankRange[#1, Most[#2]] &, text, Select[spans, #[[3]] === "span" &]]},
		If[OddQ[StringCount[stripped, "$"]],
			report[f, para[[1, 1]], "unbalanced $ math delimiters in this paragraph (outside code spans)"]
		];
		Scan[
			Function[p,
				Scan[
					report[f, lineAt[p[[1]]], StringJoin[
						"the word \"", #, "\" sits raw in inline math ", StringTake[stripped, p],
						" - it sets as a product of italic letters: an argument placeholder takes ",
						"the markdown italic form *", #, "*, a word a formula needs takes \\text{", #, "}",
						" (a genuine run of symbols goes on mathWordAllowlist in this script)"]] &,
					mathWordRuns[StringTake[stripped, p]]
				]
			],
			mathSpans[stripped]
		]
	]
]

(* every ```wl code cell must PARSE - SyntaxQ, no evaluation - so a
   mistranscribed example (an unclosed <| ... |>, a dropped bracket) fails CI
   instead of shipping as a broken cell *)
lintCells[f_, lines_List] := Module[{inCell = False, start = 0, buf = {}},
	Do[
		Which[
			! inCell && StringTrim[lines[[i]]] === "```wl",
				inCell = True; start = i + 1; buf = {},
			inCell && StringTrim[lines[[i]]] === "```",
				inCell = False;
				If[! SyntaxQ[StringRiffle[buf, "\n"]],
					report[f, start, "wl code cell does not parse (SyntaxQ False - check brackets)"]],
			inCell, AppendTo[buf, lines[[i]]]
		],
		{i, Length[lines]}
	]
]

(* Tables on symbol ref pages (option tables, Notes property tables, etc.) are
   layout tables, not data tables. A named header renders as an unwanted first
   row in the reference notebook; the header cells must be blank instead. Detect
   the pattern generically: any row immediately followed by a |---|---| separator
   whose cells are not all blank. *)
blankHeaderQ[row_String] := StringMatchQ[StringTrim[row], "|" ~~ ((Whitespace... ~~ "|") ...)]
separatorQ[row_String] := StringMatchQ[StringTrim[row],
	"|" ~~ ((Whitespace... ~~ ":"... ~~ "-".. ~~ ":"... ~~ Whitespace... ~~ "|") ..)]
lintTableHeaders[f_, lines_List] := If[
	StringContainsQ[f, FileNameJoin[{"ReferencePages", "Symbols"}]],
	Do[
		If[ separatorQ[lines[[i]]] && i > 1 && ! blankHeaderQ[lines[[i - 1]]],
			report[f, i - 1, "table header cells must be blank (use | | | |)"]
		],
		{i, Length[lines]}
	]
]

(* every `#| annotation:` marker's leading date must be YY.MM.DD, not a reversed
   DD.MM.YY. Only a numeric d+.d+.d+ right after the marker is checked; a literal
   `YY.MM.DD` placeholder or prose has no such token and is skipped. *)
lintAnnotationDates[f_, lines_List] := Do[
	Module[{hits, yy, mm, dd},
		If[StringContainsQ[lines[[i]], "#|"] && StringContainsQ[lines[[i]], "annotation:"],
			hits = StringCases[lines[[i]],
				"annotation:" ~~ WhitespaceCharacter ... ~~
					a : (DigitCharacter ..) ~~ "." ~~ b : (DigitCharacter ..) ~~ "." ~~ c : (DigitCharacter ..) :> {a, b, c}];
			If[hits =!= {},
				{yy, mm, dd} = ToExpression /@ hits[[1]];
				If[! (24 <= yy <= 99 && 1 <= mm <= 12 && 1 <= dd <= 31),
					report[f, i,
						"annotation date not in YY.MM.DD order (need year 24-99, month 01-12, day 01-31): got " <> StringRiffle[hits[[1]], "."]]
				]
			]
		]
	],
	{i, Length[lines]}
]

Do[
	Module[{lines = StringSplit[Import[f, "Text"], "\n", All]},
		Scan[scanParagraph[f, #] &, paragraphs[lines]];
		lintCells[f, lines];
		lintTableHeaders[f, lines];
		lintAnnotationDates[f, lines]
	],
	{f, files}
];

If[violations === {},
	Print["lint_docs: ", Length[files], " files clean"],
	Scan[Print, violations];
	Print["lint_docs: ", Length[violations], " finding(s) in ", Length[files], " files"];
	Exit[1]
]

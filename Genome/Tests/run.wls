#!/usr/bin/env wolframscript
(* run.wls - Run every *.wlt file in this directory under TestReport
   and report status to stdout.  Exits 1 if any test failed.

   Invoke from the repo root:
       wolframscript -f Genome/Tests/run.wls
*)

testsDir = DirectoryName[$InputFileName];
pacletDir = FileNameJoin[{testsDir, ".."}];

PacletDirectoryLoad[pacletDir];
Get["WolframInstitute`Genome`"];

allFiles = FileNames["*.wlt", testsDir];

report = If[ allFiles === {}, Null, TestReport[allFiles]];

passed = If[report === Null, 0, report["TestsSucceededCount"]];
failed = If[report === Null, 0, report["TestsFailedCount"]];

WriteString["stdout",
    "wl tests: ", ToString[passed], " passed, ",
                  ToString[failed], " failed\n"];

Do[
    WriteString["stdout",
        "  FAIL  ", r["TestID"], "  (", r["Outcome"], ")\n",
        "         expected: ", ToString[r["ExpectedOutput"], InputForm], "\n",
        "         actual:   ", ToString[r["ActualOutput"], InputForm], "\n"
    ],
    {r, If[ report === Null,
        {},
        Select[Values[report["TestResults"]], #["Outcome"] =!= "Success" &]
    ]}
];

Exit[If[failed > 0, 1, 0]]

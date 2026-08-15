#!/usr/bin/env python3
# ---------------------------------------------------------------------------
# parse-junit.py — convert a Pester JUnitXml result into a per-scenario JSON
# summary for the Windows VM runner's machine-readable result record.
#
# Usage:
#   python3 scripts/windows-testing/parse-junit.py <windows-unit.xml>
#
# Output (stdout): a JSON object with run totals and one entry per test case.
# Scenario IDs (I-01, S-04, R-02, ...) are extracted from the leading
# "<LETTER>-<NN>" token in each test name when present.
# ---------------------------------------------------------------------------
import json
import re
import sys
import xml.etree.ElementTree as ET

SCENARIO_RE = re.compile(r"^([A-Z]-\d{2})\b")


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: parse-junit.py <junit.xml>", file=sys.stderr)
        return 2

    root = ET.parse(sys.argv[1]).getroot()
    scenarios = []

    for suite in root.findall("testsuite"):
        suite_name = suite.get("name", "").replace("\\", "/")
        file_name = suite_name.rsplit("tests/windows/", 1)[-1]
        for case in suite.findall("testcase"):
            name = case.get("name", "")
            status = case.get("status", "Passed")
            if case.find("failure") is not None or case.find("error") is not None:
                status = "Failed"
            elif case.find("skipped") is not None:
                status = "Skipped"

            match = SCENARIO_RE.match(name)
            scenarios.append({
                "id": match.group(1) if match else None,
                "name": name,
                "describe": name.partition(".")[0],
                "status": status,
                "time": float(case.get("time", 0) or 0),
                "file": file_name,
            })

    passed = sum(1 for s in scenarios if s["status"] == "Passed")
    failed = sum(1 for s in scenarios if s["status"] == "Failed")
    skipped = sum(1 for s in scenarios if s["status"] == "Skipped")

    result = {
        "totals": {
            "tests": int(root.get("tests", 0)),
            "errors": int(root.get("errors", 0)),
            "failures": int(root.get("failures", 0)),
            "disabled": int(root.get("disabled", 0)),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        },
        "scenarios": scenarios,
    }
    json.dump(result, sys.stdout, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())

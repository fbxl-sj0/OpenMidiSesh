"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_reporting_lifetime.py
Purpose: Keep included-source suppressions alive through conversion checks.
Responsibilities: Exercise assignment and conversion passes with real compiler facts.
This file does not replace compiler models or suppress an entire rule family.
"""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def check_reporting(linter: Path, compiler: Path, includes: Path) -> None:
    with tempfile.TemporaryDirectory(prefix='fblint-reporting-') as temporary:
        directory = Path(temporary)
        root = directory / 'root.bas'
        header = directory / 'included.bi'
        root.write_text("' Project: reporting lifetime regression\n"
                        "' File: root.bas\n"
                        "' Purpose: Compile the included conversion fixture.\n"
                        "' Responsibilities: Supply its real compilation context.\n"
                        "' This file does not define substitute semantic facts.\n"
                        '#include "included.bi"\n'
                        "' end of root.bas\n")
        source = ("' Project: reporting lifetime regression\n"
                  "' File: included.bi\n"
                  "' Purpose: Exercise suppression after assignment checks.\n"
                  "' Responsibilities: Retain one suppressed and one visible cast.\n"
                  "' This file does not hide every conversion finding.\n"
                  'dim as integer original\n'
                  "' fblint: disable-next-line FBL-NUM-037 -- Identity cast for the suppression test.\n"
                  'dim as integer suppressed = cint(original)\n'
                  'dim as integer visible = cint(original)\n'
                  'print suppressed + visible\n'
                  "' end of included.bi\n")
        header.write_text(source)
        expected_lines = {number for number, line in enumerate(source.splitlines(), 1)
                          if ' = cint(original)' in line}
        suppressed_line = min(expected_lines)
        common = [str(linter.resolve()), '--no-config', '--profile', 'strict',
                  '--target', 'windows', '--require-semantic', '--compiler',
                  str(compiler.resolve()), '--compiler-target', 'win64',
                  '--compiler-backend', 'gcc', '--compiler-include', str(directory),
                  '--compiler-include', str(includes.resolve()), '--semantic-root',
                  str(root), '--select', 'FBL-ASSIGN-005,FBL-NUM-037',
                  '--fail-on-warning', '--format', 'jsonl', '--show-semantic']
        for honor in (True, False):
            arguments = common + ['--honor-suppressions' if honor else '--no-suppressions']
            result = subprocess.run(arguments + [str(root), str(header)],
                                    capture_output=True, text=True, timeout=120)
            rows = [json.loads(line) for line in result.stdout.splitlines()
                    if line.startswith('{')]
            summaries = [row for row in rows if row.get('type') == 'summary']
            statuses = [row for row in rows if row.get('type') == 'semantic']
            findings = [row for row in rows if row.get('type') == 'finding']
            wanted = expected_lines - {suppressed_line} if honor else expected_lines
            if (result.returncode != 1 or len(summaries) != 1 or
                    summaries[0]['operational_errors'] != 0 or
                    summaries[0]['errors'] != 0 or
                    summaries[0]['warnings'] != len(wanted) or
                    len(statuses) != 2 or
                    not all(row['required'] and row['accepted'] for row in statuses) or
                    len(findings) != len(wanted) or
                    {row['line'] for row in findings} != wanted or
                    any(row['rule'] != 'FBL-NUM-037' for row in findings)):
                raise RuntimeError('Included reporting lifetime failed:\n' +
                                   result.stdout + result.stderr)
            print(f'reporting_lifetime_honor_{honor}=pass', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--linter', type=Path, required=True)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--includes', type=Path, required=True)
    options = parser.parse_args()
    check_reporting(options.linter, options.compiler, options.includes)

# end of tools/fblint/test_reporting_lifetime.py

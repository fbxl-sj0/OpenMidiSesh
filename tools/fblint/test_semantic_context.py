"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_semantic_context.py
Purpose: Require real compiler facts for included implementation files.
Responsibilities: Exercise active and absent sources, build flags and spaces.
This file does not install tools or accept heuristic fallback.
"""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile


def check_context(linter: Path, compiler: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="fblint-context-") as temporary:
        directory = Path(temporary) / "context with spaces"
        directory.mkdir()
        root = directory / "root.bas"
        header = directory / "included.bi"
        implementation = directory / "included.bas"
        absent = directory / "absent.bas"
        root.write_text('#ifdef CONTEXT_TEST\n#include "included.bi"\n'
                        '#include "included.bas"\n#endif\n')
        header.write_text('declare function ContextValue() as integer\n')
        implementation.write_text('function ContextValue() as integer\n'
                                  ' return 7\nend function\n')
        absent.write_text('dim missingValue as integer\n')
        common = [str(linter.resolve()), '--no-config', '--compiler', str(compiler.resolve()),
                  '--compiler-target', 'win64', '--compiler-backend', 'gcc',
                  '--compiler-multithreaded', '--require-semantic', '--format', 'jsonl',
                  '--select', 'FBL310', '--semantic-root', str(root),
                  '--compiler-include', str(directory)]
        cases = (
            ('included', ['--compiler-define', 'CONTEXT_TEST', str(implementation), str(header)], 0),
            ('absent', ['--compiler-define', 'CONTEXT_TEST', str(absent)], 2),
            ('inactive', [str(implementation)], 2),
        )
        for name, arguments, expected in cases:
            result = subprocess.run(common + arguments, capture_output=True, text=True,
                                    timeout=120, check=False)
            if result.returncode != expected:
                raise RuntimeError(f'{name}: exit {result.returncode}, expected {expected}\n'
                                   + result.stdout + result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
            statuses = [row for row in rows if row.get('type') == 'semantic']
            expected_count = 2 if name == 'included' else 1
            if len(statuses) != expected_count or not all(row['required'] for row in statuses):
                raise RuntimeError(f'{name}: source coverage is incomplete: {statuses}')
            if not all(row['accepted'] == (name == 'included') for row in statuses):
                raise RuntimeError(f'{name}: incorrect compiler acceptance: {statuses}')
            print(f'semantic_context_{name}=pass', flush=True)
        root.write_text(root.read_text() + 'UnknownContextCall\n')
        result = subprocess.run(common + ['--compiler-define', 'CONTEXT_TEST',
                                str(implementation), str(header)], capture_output=True,
                                text=True, timeout=120, check=False)
        rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
        statuses = [row for row in rows if row.get('type') == 'semantic']
        if result.returncode != 2 or len(statuses) != 2 or any(row['accepted'] for row in statuses):
            raise RuntimeError('A failed compilation context was accepted: ' + result.stdout + result.stderr)
        print('semantic_context_compile_failure=pass', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--linter', type=Path, default=Path(r'C:\fblint\fb_linter.exe'))
    parser.add_argument('--compiler', type=Path, default=Path(r'C:\FreeBASIC\fbc.exe'))
    options = parser.parse_args()
    check_context(options.linter, options.compiler)

# end of tools/fblint/test_semantic_context.py

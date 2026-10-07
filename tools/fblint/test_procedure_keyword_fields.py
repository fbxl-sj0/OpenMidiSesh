"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_procedure_keyword_fields.py
Purpose: Distinguish keyword-named fields from procedure headers.
Responsibilities: Require genuine exports and reject missing member headers.
This file does not install tools or generate substitute compiler facts.
"""

import argparse
import json
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import unquote


def check_fields(linter: Path, compiler: Path, reader: Path, includes: Path) -> None:
    source = Path(__file__).with_suffix('.bas').resolve()
    with tempfile.TemporaryDirectory(prefix='fblint-keyword-fields-') as temporary:
        directory = Path(temporary)
        model = directory / 'fields.fbcsem'
        subprocess.run([str(compiler), '-r', '-gen', 'gcc', '-target', 'win64',
                        '-i', str(includes), '-semantic-model', str(model),
                        '-o', str(directory / 'fields.c'), str(source)], check=True)
        result = subprocess.run([
            str(linter), '--no-config', '--profile', 'strict', '--compiler', str(compiler),
            '--compiler-target', 'win64', '--compiler-backend', 'gcc',
            '--compiler-multithreaded', '--compiler-include', str(includes),
            '--require-semantic', '--honor-suppressions', '--fail-on-warning',
            '--strict-headers', '--strict-tabs', '--format', 'jsonl', str(source)
        ], check=True, text=True, capture_output=True)
        records = [json.loads(line) for line in result.stdout.splitlines() if line.startswith('{')]
        summary = next(row for row in records if row.get('type') == 'summary')
        if (summary['semantic_accepted'] != 1 or summary['semantic_unavailable'] != 0
                or summary['errors'] != 0 or summary['warnings'] != 0
                or summary['operational_errors'] != 0):
            raise AssertionError(summary)
        original = model.read_text(encoding='utf-8').splitlines()
        subprocess.run([str(reader), str(model), 'valid'], check=True)
        for role in ('prototype', 'definition'):
            headers = [row for row in original if row.startswith('K\t')
                       and '\tprocedure-typing-input:' in row
                       and unquote(row.split('\t')[4]).split('\t')[1] == role]
            if not headers:
                raise AssertionError('Compiler export has no ' + role + ' header')
            rows = original.copy()
            rows.remove(headers[0])
            footer = rows[-1].split('\t')
            if footer[0] != 'END' or int(footer[12]) < 1:
                raise AssertionError('Compiler export has no valid detail count')
            footer[12] = str(int(footer[12]) - 1)
            rows[-1] = '\t'.join(footer)
            # Reuse one small mutation file; the native reader checks every fact.
            mutation = directory / 'missing-header.fbcsem'
            mutation.write_text('\n'.join(rows) + '\n', encoding='utf-8')
            subprocess.run([str(reader), str(mutation), 'invalid'], check=True)
            print('missing-' + role + '=rejected')
        print('PROCEDURE_KEYWORD_FIELDS_PASS')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('linter', 'compiler', 'reader', 'includes'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    check_fields(args.linter.resolve(strict=True), args.compiler.resolve(strict=True),
                 args.reader.resolve(strict=True), args.includes.resolve(strict=True))

# end of tools/fblint/test_procedure_keyword_fields.py

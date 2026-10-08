"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_boolean_index_cache.py
Purpose: Export real compiler records for the native Boolean cache regression.
Responsibilities: Distinct Boolean operand graphs with authoritative validation.
This file does not manufacture model rows or replace compiler analysis.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile


def check_boolean_index(compiler: Path, reader: Path) -> None:
    with tempfile.TemporaryDirectory(prefix='fblint-boolean-') as temporary:
        directory = Path(temporary)
        models = []
        sources = (
            'dim as integer left_value, right_value\n'
            'if left_value > 0 andalso right_value < 5 then\n'
            '    print left_value\n'
            'end if\n',
            'dim as boolean ready\n'
            'dim as integer count\n'
            'if not ready orelse count = 3 then\n'
            '    count += 1\n'
            'end if\n',
        )
        for number, contents in enumerate(sources):
            source = directory / f'source-{number}.bas'
            model = directory / f'source-{number}.fbcsem'
            source.write_text(contents)
            subprocess.run([str(compiler.resolve()), '-target', 'win64', '-gen', 'gcc',
                            '-semantic-model', str(model), '-r', '-o',
                            str(directory / f'source-{number}.c'), str(source)],
                           check=True, capture_output=True, text=True, timeout=120)
            models.append(model)
        subprocess.run([str(reader.resolve()), *(str(model) for model in models)],
                       check=True, timeout=120)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--reader', type=Path, required=True)
    options = parser.parse_args()
    check_boolean_index(options.compiler, options.reader)

# end of tools/fblint/test_boolean_index_cache.py

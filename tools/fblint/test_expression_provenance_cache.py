"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_expression_provenance_cache.py
Purpose: Export real expression provenance for the native cache regression.
Responsibilities: Distinct evaluated and unevaluated inputs with full model validation.
This file does not manufacture model rows or replace compiler analysis.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile


def check_provenance(compiler: Path, reader: Path) -> None:
    with tempfile.TemporaryDirectory(prefix='fblint-provenance-') as temporary:
        directory = Path(temporary)
        models = []
        sources = (
            'dim as integer value\n'
            'dim as integer items(0 to 3)\n'
            'print sizeof(cint(value + items(1)))\n'
            'print ubound(items), cint(value)\n',
            'dim as double value\n'
            'dim as integer result = cint(value * 2)\n'
            'print result\n',
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
    check_provenance(options.compiler, options.reader)

# end of tools/fblint/test_expression_provenance_cache.py

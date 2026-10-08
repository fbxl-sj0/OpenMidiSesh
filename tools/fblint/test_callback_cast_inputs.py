"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_callback_cast_inputs.py
Purpose: Exercise callback ownership against genuine compiler exports.
Responsibilities: Retain void cast calls and reject a different callback signature.
This file does not qualify GUI sources or manufacture a successful compiler model.
"""

import argparse
from pathlib import Path
import subprocess
import tempfile
from urllib.parse import unquote


def check_callbacks(compiler: Path, reader: Path) -> None:
    with tempfile.TemporaryDirectory(prefix='fblint-callback-casts-') as temporary:
        directory = Path(temporary)
        source = directory / 'callback-casts.bas'
        source.write_text('#lang "fb"\n'
                          'dim shared sink as integer\n'
                          'private sub FirstHandler(byval value as integer)\n'
                          ' sink += value\nend sub\n'
                          'private sub SecondHandler(byval value as long)\n'
                          ' sink += value\nend sub\n'
                          'private function ValueHandler(byval value as integer) as integer\n'
                          ' return value\nend function\n'
                          'cast(sub(byval as integer), @FirstHandler)(1)\n'
                          'cast(sub(byval as long), @SecondHandler)(2)\n'
                          'cast(function(byval as integer) as integer, @ValueHandler)(3)\n')
        model = directory / 'callbacks.fbcsem'
        subprocess.run([str(compiler.resolve()), '-target', 'win64', '-gen', 'gcc',
                        '-semantic-model', str(model), '-r', '-o', str(directory / 'callbacks.c'),
                        str(source)], check=True, capture_output=True, text=True, timeout=120)
        subprocess.run([str(reader.resolve()), str(model), 'valid'], check=True, timeout=120)
        rows = model.read_text().splitlines()
        endings = {r[1]: r[3] for line in rows if (r := line.split('\t'))[0] == 'STE'}
        callbacks = [(index, r) for index, line in enumerate(rows)
                     if (r := line.split('\t'))[0] == 'K'
                     and r[3].startswith('callback-convention-input:')
                     and endings[unquote(r[4]).split('\t')[0]] == 'unmatched']
        if len(callbacks) != 2 or callbacks[0][1][2] == callbacks[1][1][2]:
            raise RuntimeError('Compiler did not export the two distinct unmatched void casts')
        # Both symbols and their signatures remain valid. Only this receipt's
        # claimed signature changes, leaving no matching owned indirect call.
        index, fields = callbacks[0]
        fields[2] = callbacks[1][1][2]
        rows[index] = '\t'.join(fields)
        mutation = directory / 'different-signature.fbcsem'
        mutation.write_text('\n'.join(rows) + '\n')
        subprocess.run([str(reader.resolve()), str(mutation), 'callback-invalid'],
                       check=True, timeout=120)
        print('CALLBACK_CAST_INPUTS_PASS: valid void calls, different signature rejected')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--reader', type=Path, required=True)
    options = parser.parse_args()
    check_callbacks(options.compiler, options.reader)

# end of tools/fblint/test_callback_cast_inputs.py

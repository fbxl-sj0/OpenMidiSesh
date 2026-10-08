"""
Project: OpenSesh validator regression checks
File: tools/fblint/test_anonymous_enum_replay.py
Purpose: Test anonymous enum identity with three genuine compiler exports.
Responsibilities: Check generated-name independence and changed subtype rejection.
This file does not qualify complete replay frames or install the validator.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def check(compiler: Path, reader: Path) -> None:
    body = ('enum NamedKeys\n NamedKey = 0\nend enum\n'
            'enum\n FirstUp = 1\n FirstDown = 2\nend enum\n'
            'enum\n SecondUp = 1\n SecondDown = 2\nend enum\n'
            'function ChooseKey(byval direction as integer) as integer\n'
            ' return iif(direction = 0, CHOICEUp, CHOICEDown)\nend function\n')
    with tempfile.TemporaryDirectory(prefix='fblint-enum-replay-') as temporary:
        directory = Path(temporary)
        outputs = {}; names = {}
        for name, prefix, choice in (
                ('baseline', '', 'First'),
                ('renumbered', 'type CounterShift\n union\n  padding as integer\n end union\nend type\n', 'First'),
                ('changed_subtype', '', 'Second')):
            source = directory / (name + '.bas'); model = directory / (name + '.fbcsem')
            source.write_text(prefix + body.replace('CHOICE', choice))
            subprocess.run([str(compiler.resolve()), '-gen', 'gcc', '-target', 'win64',
                            '-semantic-model', str(model), '-r', '-o', str(directory / (name + '.c')),
                            str(source)], capture_output=True, text=True, check=True, timeout=120)
            result = subprocess.run([str(reader.resolve()), str(model)], capture_output=True,
                                    text=True, check=False, timeout=120)
            if result.returncode != 0:
                raise RuntimeError(name + ': native enum reader failed: ' + result.stdout + result.stderr)
            if 'ANONYMOUS_ENUM_KEYS_PASS' not in result.stdout:
                raise RuntimeError(name + ': native enum checks did not pass')
            outputs[name] = result.stdout
            rows = [line.split('\t') for line in model.read_text().splitlines() if line.startswith('T\t')]
            names[name] = [row[2] for row in rows if row[3] == 'enum' and row[18] == 'compiler']
        if names['baseline'] == names['renumbered'] or outputs['baseline'] != outputs['renumbered']:
            raise RuntimeError('Compiler-generated enum renumbering changed replay keys')
        if outputs['baseline'] == outputs['changed_subtype']:
            raise RuntimeError('Different anonymous enum identities produced equal replay keys')
        print('ANONYMOUS_ENUM_REPLAY_PASS: generated names, distinct subtypes, source names, unchanged records')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--compiler', required=True, type=Path)
    parser.add_argument('--reader', required=True, type=Path)
    args = parser.parse_args()
    check(args.compiler, args.reader)

# end of test_anonymous_enum_replay.py

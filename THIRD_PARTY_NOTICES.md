# Third-party notices

OpenSesh is built with the components below. These notices apply to
their respective components and do not replace the OpenSesh license
in `LICENSE` and `COPYING`.

## omaGUI

OpenSesh incorporates omaGUI source through the FreeBASIC include
tree. The exact runtime subset is vendored under `vendor/omaGui` and verified
against `vendor/omaGui/SNAPSHOT.sha256`.

MIT License

Copyright (c) 2026 jasonkfirth

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Embedded omaGui bitmap fonts

The default, compact bold, and large heading glyph tables are printable-ASCII
subsets generated from Liberation Sans and Liberation Serif. Their source font
metadata records:

- Digitized data copyright (c) 2010 Google Corporation, with Reserved Font
  Arimo, Tinos and Cousine.
- Copyright (c) 2012 Red Hat, Inc., with Reserved Font Name Liberation.

The generated tables use neutral omaGui identifiers and remain under the SIL
Open Font License 1.1. The complete copyright notice and license are included
in `vendor/omaGui/assets/fonts/OFL-1.1.txt`.

No bitmap-font conversion made from Windows Arial files is compiled or
included in the OpenSesh release source. Those historical omaGui
development files are outside the vendored payload.

## FreeBASIC runtime, gfxlib, and sfxlib

The audited builds use FreeBASIC 1.20.x. The compiler is a build dependency
and is not included in the OpenSesh source archive. Native
executables statically link FreeBASIC runtime, graphics, and sound code. The
audited Win64 compiler and critical linked archives have exact identities in
`windows_toolchain_lock.json`.

Copyright (C) 2004-2025 The FreeBASIC development team.

The FreeBASIC distribution states that its compiler is GPL version 2 or later,
and that its runtime and graphics libraries are LGPL version 2 or later with
this static-linking exception:

> As a special exception, the copyright holders of this library give you
> permission to link this library with independent modules to produce an
> executable, regardless of the license terms of these independent modules,
> and to copy and distribute the resulting executable under terms of your
> choice, provided that you also meet, for each linked independent module, the
> terms and conditions of the license of that module. An independent module is
> a module which is not derived from or based on this library. If you modify
> this library, you may extend this exception to your version of the library,
> but you are not obligated to do so. If you do not wish to do so, delete this
> exception statement from your version.

The LGPL version 2.1 text is included in `COPYING.LESSER`. The complete
FreeBASIC distribution remains the authoritative source for its component and
toolchain notices.

## dr_libs: dr_wav and dr_mp3

The FreeBASIC sfxlib archive linked into the audited executable contains
dr_wav and dr_mp3 from David Reid's dr_libs. OpenSesh records the
MIT No Attribution alternative offered by that project.

Copyright 2020 David Reid

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Upstream: <https://github.com/mackron/dr_libs>

## stb_vorbis

The FreeBASIC sfxlib archive linked into the audited executable contains
stb_vorbis. OpenSesh records the MIT alternative offered by the stb
project.

Copyright (c) 2017 Sean Barrett

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Upstream: <https://github.com/nothings/stb>

<!-- end of THIRD_PARTY_NOTICES.md -->

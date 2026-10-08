The shared omaGUI source includes an optional navigation profile for games with
a logical canvas and controller or touch controls. Define
`OMAGUI_NAVIGATION_EXTENSIONS` consistently in the application and its GUI runtime
unit. Define `OMAGUI_IMPLEMENTATION` in exactly one runtime unit.

The normal desktop profile retains its existing widget behavior. The navigation
profile adds input scopes, explicit directional neighbors, semantic controller
actions, bounded key repeat, contact phases, large list rows and swipe scrolling.
It uses the same registry identities, clipping stack and widget implementations.
Neighbors and delayed activation targets are borrowed references checked against
their registration IDs before use. All calls and mutable state belong to the GUI
thread. Native pointer events are sampled once by the common input backend.

`backend_SetDisplayOptions`, `backend_SetTextScale` and
`backend_SetHighContrast` preserve the game's display preferences. Layout remains
in logical coordinates. The viewport applies a gfxlib WINDOW transform and maps
native pointer coordinates back to that canvas. Direct framebuffer and GPU point
writers bypass WINDOW, so this profile uses the portable glyph fallback. Standard
desktop applications retain the glyph-span and GPU batching paths.

The row, column and grid containers validate dimensions up to 32767, up to 4096
children or grid cells and weights up to 65535 before layout arithmetic. Checked
metadata setters reject unsupported inputs. Direct metadata writes are validated
when a container is applied; invalid metadata reports overflow and leaves child
rectangles unchanged.

Legacy applications can import declarations in fblite without changing dialect.
Compile the GUI runtime as its own fb unit to bound compiler memory. The native
tests `navigation_profile_smoke.bas` and `native_boundary_smoke.bas` qualify the
profile and the Windows import boundary. These are headless development tests;
they do not certify a browser, Android or controller device deployment.

Host clipboard integration remains an explicit opt-in through
`OMAGUI_ENABLE_HOST_CLIPBOARD`. Unix builds support Wayland, xclip, xsel and optional
Python/Tk ownership. Payloads travel through bounded native pipes, never through
shell command interpolation. Windows imports use a private namespace and bound
reads by the native allocation size.

<!-- end of NAVIGATION.md -->

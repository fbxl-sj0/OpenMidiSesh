# Portable file browser

The shared file dialog keeps the existing open, save and folder factories and
result states. It owns its location and never changes the application's current
directory. Applications must still perform the actual document read or write.

The default desktop layout is 720 by 480 pixels, fitted to the backend viewport.
Its sizable border keeps controls inside the window; narrow layouts hide the
places sidebar and optional details columns. The supported minimum is 360 by 300.

Controls include places, an editable location and Go button, Back/Next/Up,
Refresh, a sortable folder-first details table, live search, visible semicolon
wildcard filters, Show hidden, and a filename field in open and save modes.
Single selection fills the filename. Double-click opens a folder or accepts a
file. The folder picker keeps a separate Open Folder action and Select result.

Keyboard commands are Ctrl+L for location, Ctrl+F for search, Ctrl+H for hidden
files, Alt+Left/Right for history, Alt+Up for the parent, and F5 for refresh.
Enter in location navigates; Enter in filename accepts; Tab follows normal GUI
focus traversal; Escape cancels. New folder uses the filename field temporarily;
Escape first abandons folder creation without closing the dialog.

Saving an existing pathname requires a second explicit Replace action by
default. `filedialog_SetConfirmOverwrite(dialog, 0)` disables this when the host
application already owns confirmation. No file is replaced by the dialog itself.
`filedialog_SetDefaultExtension` optionally appends one extension to names with
no dot. `filedialog_AddPlace` supplies an application-specific shortcut and
`filedialog_SetSort` selects Name, Type, Size or Modified order.

Each directory scan is cached, capped at 4095 entries and one MiB of raw names.
The parent row has reserved identity zero; other rows carry stable cache indexes.
Control characters are sanitized only for display, never used to reconstruct
pathnames. Search, filters, sorting by name/type, and idle updates do not enumerate
the directory again. F5 explicitly refreshes stale directory contents.

Metadata is loaded for at most eight visible entries per update. Choosing size
or modified-date sort queries the currently filtered entries once. File content
streams are never opened for listing, existence or metadata checks, avoiding
blocking Unix devices and FIFOs. Windows provides safe sizes from its native
directory record. Legacy portable runtimes show a dash for size; unavailable
timestamps also show a dash. This is an attribute-only browser, not a native
shell integration or a Unicode filename conversion layer.

`tests/filedialog_browser_smoke.bas` uses a supplied private fixture directory
containing alpha/beta directories and existing.txt, [literal].bas, zebra.bas,
apple.txt and .hidden.txt. It creates one `created-by-dialog` folder there.
Its optional second argument saves desktop and compact BMP renders. Define
FILEDIALOG_TEST_PORTABLE on Windows to test the runtime filesystem path as well.

<!-- end of FILEDIALOG.md -->

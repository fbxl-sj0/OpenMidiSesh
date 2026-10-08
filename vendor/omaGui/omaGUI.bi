/'
    Project: omaGUI
    ---------------

    File: omaGUI.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for omaGUI.

    Purpose:

        Provide the public omaGUI declarations and, when selected by one
        program source file, compile the complete omaGUI implementation.

    Responsibilities:

        - expose all omaGUI backend and widget declarations
        - prevent duplicate declarations through a single include guard
        - assemble implementation units when OMAGUI_IMPLEMENTATION is defined

    This file intentionally does NOT contain:

        - application-specific GUI layout
        - editor state or game rules
        - platform-specific behavior outside omaGUI backend modules
'/

#ifndef __OMAGUI_BI__
#define __OMAGUI_BI__

' --- HEADERS ---
#include once "src/backend/backend.bi"
#include once "src/backend/input.bi"
#include once "src/backend/theme.bi"
#include once "src/backend/clipboard.bi"
#include once "src/backend/font_data.bi"
#include once "src/system/filesystem.bi"
#include once "src/system/byte_span.bi"
#include once "src/images/raster_image.bi"
#include once "src/archive/chmarchive.bi"

#include once "src/widgets/widgets.bi"
#include once "src/widgets/button.bi"
#include once "src/widgets/textbox.bi"
#include once "src/widgets/checkbox.bi"
#include once "src/widgets/radiobox.bi"
#include once "src/widgets/label.bi"
#include once "src/widgets/groupbox.bi"
#include once "src/widgets/textsurface.bi"
#include once "src/widgets/pixelsurface.bi"
#include once "src/widgets/picturebox.bi"
#include once "src/widgets/combobox.bi"
#include once "src/widgets/timerwidget.bi"
#include once "src/widgets/scrollbar.bi"
#include once "src/widgets/spinbutton.bi"
#include once "src/widgets/listbox.bi"
#include once "src/widgets/filesystemlistbox.bi"
#include once "src/widgets/htmlview.bi"
#include once "src/widgets/rtfview.bi"
#include once "src/widgets/subwindow.bi"
#include once "src/widgets/filedialog.bi"
#include once "src/widgets/confirmdialog.bi"
#include once "src/widgets/colordialog.bi"
#include once "src/widgets/inputdialog.bi"
#include once "src/widgets/menu.bi"
#include once "src/widgets/menubar.bi"
#include once "src/widgets/toolbar.bi"
#include once "src/widgets/statusbar.bi"
#include once "src/widgets/splitter.bi"
#include once "src/widgets/linewidget.bi"
#include once "src/widgets/rectwidget.bi"
#include once "src/widgets/themeframe.bi"
#include once "src/widgets/circlewidget.bi"
#include once "src/widgets/curvewidget.bi"
#include once "src/widgets/canvas.bi"
#include once "src/widgets/graphicshape.bi"

#ifdef OMAGUI_NAVIGATION_EXTENSIONS
#include once "src/backend/navigation_input.bi"
#include once "src/backend/navigation_viewport.bi"
#include once "src/widgets/navigation.bi"
#include once "src/widgets/layout.bi"
#endif

' --- IMPLEMENTATIONS ---
' Only include implementations once per binary.
' Define OMAGUI_IMPLEMENTATION in ONE source file before including this.
#ifdef OMAGUI_IMPLEMENTATION
    ' This explicit one-binary implementation assembly is the omaGUI build model. FBLINT-ALLOW-BAS-INCLUDES
    #include once "src/backend/theme.bas"
    #include once "src/backend/font_data_full.bas"
    #include once "src/backend/backend_gfxlib.bas"
    #include once "src/backend/input_gfxlib.bas"
    #include once "src/backend/clipboard.bas"
    #include once "src/system/filesystem.bas"
    #include once "src/images/raster_image.bas"
    #include once "src/archive/chm_lzx.bas"
    #include once "src/archive/chmarchive.bas"
    #include once "src/widgets/widgets.bas"
    #include once "src/widgets/button.bas"
    #include once "src/widgets/textbox.bas"
    #include once "src/widgets/textbox_history.bas"
    #include once "src/widgets/textbox_indent.bas"
    #include once "src/widgets/menu.bas"
    #include once "src/widgets/menubar.bas"
    #include once "src/widgets/toolbar.bas"
    #include once "src/widgets/statusbar.bas"
    #include once "src/widgets/splitter.bas"
    #include once "src/widgets/checkbox.bas"
    #include once "src/widgets/label.bas"
    #include once "src/widgets/groupbox.bas"
    #include once "src/widgets/textsurface.bas"
    #include once "src/widgets/pixelsurface.bas"
    #include once "src/widgets/picturebox.bas"
    #include once "src/widgets/combobox.bas"
    #include once "src/widgets/timerwidget.bas"
    #include once "src/widgets/scrollbar.bas"
    #include once "src/widgets/spinbutton.bas"
    #include once "src/widgets/listbox.bas"
    #include once "src/widgets/wildcard.bas"
    #include once "src/widgets/filesystemlistbox.bas"
    #include once "src/widgets/htmlview.bas"
    #include once "src/widgets/rtfview.bas"
    #include once "src/widgets/subwindow.bas"
    #include once "src/widgets/filedialog.bas"
    #include once "src/widgets/confirmdialog.bas"
    #include once "src/widgets/colordialog.bas"
    #include once "src/widgets/inputdialog.bas"
    #include once "src/widgets/radiobox.bas"
    #include once "src/widgets/linewidget.bas"
    #include once "src/widgets/rectwidget.bas"
    #include once "src/widgets/themeframe.bas"
    #include once "src/widgets/circlewidget.bas"
    #include once "src/widgets/curvewidget.bas"
    #include once "src/widgets/canvas.bas"
    #include once "src/widgets/graphicshape.bas"
#ifdef OMAGUI_NAVIGATION_EXTENSIONS
    #include once "src/backend/navigation_input.bas"
    #include once "src/backend/navigation_viewport.bas"
    #include once "src/widgets/navigation.bas"
    #include once "src/widgets/layout.bas"
#endif
#endif

#endif
' end of omaGUI.bi

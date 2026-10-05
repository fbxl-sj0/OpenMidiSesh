/'
    Project: OpenSesh
    ---------------------------

    File: omagui_runtime.bas

    Copyright (C) 2026 OpenSesh contributors
    SPDX-License-Identifier: GPL-3.0-or-later

    Targets: FreeBASIC fb dialect; shared Windows/Linux x64 and Android editor builds.

    Module API: Instantiates vendor/omaGui/omaGUI.bi once with OMAGUI_IMPLEMENTATION.

    Purpose:

        Compile the vendored omaGui implementation as its own translation unit.

    Responsibilities:

        - instantiate the shared omaGui widget, input, and gfxlib backends once
        - keep GUI implementation storage outside the application entry module
        - select the redistributable OpenSesh font tables

    This file intentionally does NOT contain:

        - OpenSesh document or editor behavior
        - platform-specific MIDI selection
        - application startup or shutdown policy
'/

#lang "fb"

#define OMAGUI_REDISTRIBUTABLE_FONTS
#define OMAGUI_IMPLEMENTATION
#include once "omaGUI.bi"

/' end of omagui_runtime.bas '/

/'
    Project: omaGUI
    ---------------

    File: htmlview.bi

    Targets: FreeBASIC fb dialect; the including application selects the native backend.
    Module API: omaGUI declarations and implementation for htmlview.

    Purpose:

        Declare a small, portable HTML document viewer widget.

    Responsibilities:

        - expose a BASIC-shaped API for HTML text and file loading
        - expose cooperative single-threaded document loading
        - retain bounded layout, scrolling, title, anchor, and link state
        - retain bounded rules from linked local stylesheets
        - expose link activation through polling or an optional callback
        - expose an optional application image provider with clear ownership

    This file intentionally does NOT contain:

        - networking, URL fetching, or shell launching
        - JavaScript, executable CSS, or browser-engine integration
        - platform-specific web controls
'/

#ifndef __HTMLVIEW_BI__
#define __HTMLVIEW_BI__

#include once "src/widgets/widgets.bi"
#include once "src/images/raster_image.bi"

Const HTMLVIEW_MAX_DOCUMENT_BYTES As LongInt = 2097152
Const HTMLVIEW_MAX_LAYOUT_ITEMS As Long = 65536
Const HTMLVIEW_MAX_ANCHORS As Integer = 4096
Const HTMLVIEW_MAX_CSS_RULES As Integer = 128
Const HTMLVIEW_MAX_STYLESHEET_BYTES As LongInt = 65536
Const HTMLVIEW_MAX_IMAGE_PIXELS As ULongInt = 33554432ULL

Const HTMLVIEW_ITEM_TEXT As Integer = 1
Const HTMLVIEW_ITEM_RULE As Integer = 2
Const HTMLVIEW_ITEM_IMAGE As Integer = 3
Const HTMLVIEW_ITEM_BOX As Integer = 4

Const HTMLVIEW_LOAD_FAILED As Integer = -1
Const HTMLVIEW_LOAD_CANCELLED As Integer = -2
Const HTMLVIEW_LOAD_IDLE As Integer = 0
Const HTMLVIEW_LOAD_LOADING As Integer = 1
Const HTMLVIEW_LOAD_COMPLETE As Integer = 2

Type HtmlViewItem
    As Integer itemKind
    As Integer x, y, w, h
    As Integer fontId, scaleX, scaleY
    As Integer underline, codeBackground
    As ULong color
    As ULong backgroundColor
    As String text
    As String href
    As RasterImage Ptr image
    As HtmlViewItem Ptr nextItem
End Type

Type HtmlViewAnchor
    As String nameText
    As Integer y
End Type

Type HtmlViewCssRule
    As String selectorText
    As String declarationText
End Type

Type HtmlViewData
    As String sourceHtml
    As String basePath
    As String titleText
    As String plainText
    As String lastError
    As String pendingLink
    As String armedLink
    As String styleSheetText
    As Integer cssRuleCount
    As HtmlViewCssRule cssRules(0 To HTMLVIEW_MAX_CSS_RULES - 1)
    As HtmlViewItem Ptr firstItem
    As HtmlViewItem Ptr lastItem
    As Long itemCount
    As Integer anchorCount
    As HtmlViewAnchor anchors(0 To HTMLVIEW_MAX_ANCHORS - 1)
    As Integer contentHeight
    As Integer scrollY
    As Integer layoutWidth
    As Integer mouseLatch
    As Integer keyLatch
    As Integer layoutIncomplete
    As Integer padding
    As ULong backgroundColor
    As ULong textColor
    As ULong linkColor
    As ULong codeBackgroundColor
    As ULong documentBackgroundColor
    As ULong documentTextColor
    As ULong documentLinkColor
    As Widget Ptr verticalScrollbar
    As Any Ptr linkHandler
    As Any Ptr linkContext
    As Any Ptr imageHandler
    As Any Ptr imageContext
    As Any Ptr resourceHandler
    As Any Ptr resourceContext
    /'
        Cooperative loader ownership

        loadContext is an opaque implementation-owned staging document.  The
        active item list remains renderable until that context completes and
        transfers ownership atomically on the GUI thread.
    '/
    As Any Ptr loadContext
    As String loadError
    As Integer loadState
    As Integer loadProgress
End Type

/'
    Link callback signature

    A handler passed to htmlview_SetLinkHandler must have this shape:

        Sub Handler( _
            ByVal htmlWidget As Widget Ptr, _
            ByVal href As String, _
            ByVal context As Any Ptr _
        )

    The viewer never opens the link itself. This keeps navigation policy,
    network access, and external program launching under application control.
'/

Declare Function htmlview_Create( _
    ByVal nm As String, _
    ByVal x As Integer, ByVal y As Integer, _
    ByVal w As Integer, ByVal h As Integer _
) As Widget Ptr

Declare Function htmlview_SetHtml( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String _
) As Integer
Declare Function htmlview_LoadFile( _
    ByVal htmlWidget As Widget Ptr, ByVal filePath As String _
) As Integer
Declare Function htmlview_BeginSetHtml( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String _
) As Integer
Declare Function htmlview_BeginSetHtmlAtPath( _
    ByVal htmlWidget As Widget Ptr, ByVal htmlText As String, _
    ByVal basePath As String _
) As Integer
Declare Function htmlview_BeginLoadFile( _
    ByVal htmlWidget As Widget Ptr, ByVal filePath As String _
) As Integer
Declare Function htmlview_UpdateLoad( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal timeBudgetMilliseconds As Integer = 4 _
) As Integer
Declare Function htmlview_IsLoading(ByVal htmlWidget As Widget Ptr) As Integer
Declare Function htmlview_GetLoadState(ByVal htmlWidget As Widget Ptr) As Integer
Declare Function htmlview_GetLoadProgress(ByVal htmlWidget As Widget Ptr) As Integer
Declare Function htmlview_GetLoadError(ByVal htmlWidget As Widget Ptr) As String
Declare Sub htmlview_CancelLoad(ByVal htmlWidget As Widget Ptr)
Declare Sub htmlview_Clear(ByVal htmlWidget As Widget Ptr)
Declare Function htmlview_Reflow(ByVal htmlWidget As Widget Ptr) As Integer
Declare Sub htmlview_SetBasePath( _
    ByVal htmlWidget As Widget Ptr, ByVal directoryPath As String _
)

Declare Sub htmlview_SetColors( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal backgroundColor As ULong, _
    ByVal textColor As ULong, _
    ByVal linkColor As ULong _
)
Declare Sub htmlview_SetLinkHandler( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal handler As Any Ptr, _
    ByVal context As Any Ptr = 0 _
)

/'
    Image callback signature

    An image handler provides application-owned schemes such as "dd:image:0":

        Function Handler( _
            ByVal source As String, _
            ByVal context As Any Ptr, _
            ByRef loadedImage As RasterImage Ptr, _
            ByRef errorMessage As String _
        ) As Integer

    On success, ownership of loadedImage transfers to the viewer. Returning
    zero leaves ordinary relative and absolute local-file loading available.
'/
Declare Sub htmlview_SetImageHandler( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal handler As Any Ptr, _
    ByVal context As Any Ptr = 0 _
)

/'
    Resource callback signature

    A handler passed to htmlview_SetResourceHandler can provide linked
    stylesheets or other small text resources from an application-owned
    namespace such as "chm://style.css". Returning zero allows ordinary
    local-file loading only when the resolved path is not a URI scheme.
'/
Declare Sub htmlview_SetResourceHandler( _
    ByVal htmlWidget As Widget Ptr, _
    ByVal handler As Any Ptr, _
    ByVal context As Any Ptr = 0 _
)

Declare Function htmlview_GetTitle(ByVal htmlWidget As Widget Ptr) As String
Declare Function htmlview_GetPlainText(ByVal htmlWidget As Widget Ptr) As String
Declare Function htmlview_GetLastError(ByVal htmlWidget As Widget Ptr) As String
Declare Function htmlview_GetBasePath(ByVal htmlWidget As Widget Ptr) As String
Declare Function htmlview_GetContentHeight(ByVal htmlWidget As Widget Ptr) As Integer
Declare Function htmlview_GetScroll(ByVal htmlWidget As Widget Ptr) As Integer
Declare Sub htmlview_SetScroll(ByVal htmlWidget As Widget Ptr, ByVal pixelOffset As Integer)
Declare Function htmlview_GotoAnchor( _
    ByVal htmlWidget As Widget Ptr, ByVal anchorName As String _
) As Integer
Declare Function htmlview_PopLink( _
    ByVal htmlWidget As Widget Ptr, ByRef href As String _
) As Integer

Declare Sub htmlview_Render(ByVal htmlWidget As Widget Ptr)
Declare Sub htmlview_Update(ByVal htmlWidget As Widget Ptr)
Declare Sub htmlview_Destroy(ByVal htmlWidget As Widget Ptr)

#endif

/' end of htmlview.bi '/

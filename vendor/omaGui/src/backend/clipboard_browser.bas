/'
    Project: omaGUI
    File: clipboard_browser.bas
    Purpose: Bridge bounded UTF-8 text to the browser Clipboard API.
    Responsibilities: Permission-aware asynchronous reads, writes and cancellation.
    This file does not contain widget selection, focus or editing rules.
    Threading: Called on the browser main thread; promises never call into BASIC.
'/
#lang "fb"

Extern "C"
    Declare Function clipboard_BrowserScript Alias "emscripten_run_script_int" _
        (ByVal scriptText As Const ZString Ptr) As Long
    Declare Function clipboard_BrowserString Alias "emscripten_run_script_string" _
        (ByVal scriptText As Const ZString Ptr) As ZString Ptr
End Extern

Private Sub clipboard_BrowserInitialize()
    /'
        Start keyboard reads during the trusted key event, before SDL queues
        the key for a later GUI frame. Firefox and Safari require activation
        for reads. A generation discards results from cancelled permission
        prompts. No polling callback can re-enter the BASIC widget dispatcher.
        The listener belongs to this Module and ignores surrounding HTML fields.
        An unused keyboard preparation expires after one second so a later
        Paste button cannot accidentally reuse that old clipboard snapshot.
        C/X/V use gfxlib scan codes 46/45/47 and modifier bits Control=1,
        Shift=4. The 64-record queue is drained by input_gfxlib each frame.
        Its matching keyups never reach SDL, which avoids duplicate commands.
        gui_Init enables command capture. Clipboard-only callers retain their
        own event handlers and only get the trusted-event read preparation.
    '/
    Dim As String scriptText = _
        "(function(){if(Module.omaGUIClipboard)return 1;" & _
        "var b={text:'',status:-1,generation:0,prepared:false,preparedAt:0,captureKeys:false,hostEnabled:true,keys:[],held:{},overflow:false};" & _
        "b.bound=function(t){var cap=" & LTrim(Str(CLIPBOARD_MAX_TEXT_BYTES)) & ";" & _
        "t=String(t).slice(0,cap).replace(/\u0000/g,'');var bytes=new TextEncoder().encode(t);" & _
        "return new TextDecoder().decode(bytes.subarray(0,cap),{stream:true});};" & _
        "b.cancel=function(){++b.generation;b.prepared=false;b.status=-1;return 0;};" & _
        "b.begin=function(){var id=++b.generation;b.status=0;if(!b.hostEnabled){b.status=1;return;}" & _
        "if(typeof navigator==='undefined'||!navigator.clipboard||!navigator.clipboard.readText){b.status=1;return;}" & _
        "try{navigator.clipboard.readText().then(function(t){if(id===b.generation){b.text=b.bound(t);b.status=1;}}," & _
        "function(){if(id===b.generation)b.status=-1;});}catch(e){b.status=-1;}};" & _
        "b.request=function(){if(b.prepared&&Date.now()-b.preparedAt<1000){b.prepared=false;}else{b.prepared=false;b.begin();}return b.status;};" & _
        "b.write=function(t){b.cancel();b.text=b.bound(t);if(!b.hostEnabled)return 0;" & _
        "if(typeof navigator==='undefined'||!navigator.clipboard||!navigator.clipboard.writeText)return 0;" & _
        "try{navigator.clipboard.writeText(b.text).catch(function(){});}catch(e){}return 0;};" & _
        "b.nextKey=function(){return b.keys.length?b.keys.shift():0;};" & _
        "if(typeof window!=='undefined')window.addEventListener('keydown',function(e){" & _
        "var key=e.key.toLowerCase(),scan={c:46,x:45,v:47}[key];" & _
        "if(scan&&(e.ctrlKey||e.metaKey)&&!e.altKey&&Module.canvas&&" & _
        "(e.target===Module.canvas||document.activeElement===Module.canvas||" & _
        "(e.target.hasAttribute&&e.target.hasAttribute('data-fb-soft-keyboard')))){" & _
        "if(b.captureKeys){" & _
        "e.preventDefault();e.stopImmediatePropagation();b.held[key]=true;if(e.repeat)return;" & _
        "if(b.keys.length>=64){b.keys.length=0;b.overflow=true;b.cancel();return;}" & _
        "b.keys.push(scan|((1|(e.shiftKey?4:0))<<8));}" & _
        "if(!e.repeat&&key==='v'){b.begin();b.prepared=true;b.preparedAt=Date.now();}}},true);" & _
        "if(typeof window!=='undefined')window.addEventListener('keyup',function(e){var key=e.key.toLowerCase();" & _
        "if(b.held[key]){delete b.held[key];e.preventDefault();e.stopImmediatePropagation();}},true);" & _
        "if(typeof window!=='undefined')window.addEventListener('blur',function(){b.cancel();b.keys.length=0;b.held={};});" & _
        "Module.omaGUIClipboard=b;return 1;})()"
    clipboard_BrowserScript StrPtr(scriptText)
End Sub

Private Sub clipboard_BrowserSetText(ByRef textValue As Const String)
    clipboard_BrowserInitialize
    ' Only the pointer and byte count enter JavaScript source. Clipboard text
    ' never becomes executable source, even when it contains quotes/newlines.
    Dim As String pointerText = LTrim(Str(Cast(UInteger, StrPtr(textValue))))
    Dim As String scriptText = "Module.omaGUIClipboard.write(new TextDecoder().decode(HEAPU8.subarray(" & _
        pointerText & "," & pointerText & "+" & LTrim(Str(Len(textValue))) & "),{stream:true}))"
    clipboard_BrowserScript StrPtr(scriptText)
End Sub

' end of clipboard_browser.bas

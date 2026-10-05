<#
    Project: OpenSesh
    ---------------------------

    File: tests/verify_windows_manifest.ps1

    Purpose:

        Verify the process manifest embedded in a built Windows editor.

    Responsibilities:

        - read resource ID 1 directly from the executable's RT_MANIFEST table
        - parse the embedded bytes as XML
        - enforce the reviewed privilege, compatibility, and DPI declarations

    This file intentionally does NOT contain:

        - a build step
        - runtime DPI measurements
        - installer or code-signing checks
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $ExecutablePath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$resolvedExecutable = [System.IO.Path]::GetFullPath($ExecutablePath)
if (-not (Test-Path -LiteralPath $resolvedExecutable -PathType Leaf)) {
    throw "Windows executable was not found: $resolvedExecutable"
}

if (-not ('OpenSesh.NativeResourceReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace OpenSesh
{
    public static class NativeResourceReader
    {
        private const uint LoadLibraryAsDataFile = 0x00000002;
        private const uint LoadLibraryAsImageResource = 0x00000020;

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr LoadLibraryEx(
            string fileName,
            IntPtr file,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr FindResource(
            IntPtr module,
            IntPtr name,
            IntPtr type);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint SizeofResource(
            IntPtr module,
            IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LoadResource(
            IntPtr module,
            IntPtr resource);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LockResource(IntPtr resourceData);

        [DllImport("kernel32.dll")]
        private static extern bool FreeLibrary(IntPtr module);

        public static byte[] Read(string executablePath, int identifier, int type)
        {
            IntPtr module = LoadLibraryEx(
                executablePath,
                IntPtr.Zero,
                LoadLibraryAsDataFile | LoadLibraryAsImageResource);

            if (module == IntPtr.Zero)
                throw new Win32Exception(Marshal.GetLastWin32Error());

            try
            {
                IntPtr resource = FindResource(
                    module,
                    new IntPtr(identifier),
                    new IntPtr(type));

                if (resource == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                uint size = SizeofResource(module, resource);
                if (size == 0 || size > Int32.MaxValue)
                    throw new InvalidOperationException("Manifest resource size is invalid.");

                IntPtr loadedResource = LoadResource(module, resource);
                if (loadedResource == IntPtr.Zero)
                    throw new Win32Exception(Marshal.GetLastWin32Error());

                IntPtr resourceBytes = LockResource(loadedResource);
                if (resourceBytes == IntPtr.Zero)
                    throw new InvalidOperationException("Manifest resource data is unavailable.");

                byte[] result = new byte[size];
                Marshal.Copy(resourceBytes, result, 0, checked((int)size));
                return result;
            }
            finally
            {
                FreeLibrary(module);
            }
        }
    }
}
'@
}

# RT_MANIFEST is resource type 24. Windows uses integer resource ID 1 for the
# application manifest selected by the process loader.
$manifestBytes = [OpenSesh.NativeResourceReader]::Read(
    $resolvedExecutable,
    1,
    24)
if ($manifestBytes.Length -le 0) {
    throw 'The embedded Windows manifest is empty.'
}

$memoryStream = New-Object System.IO.MemoryStream(,$manifestBytes)
$xmlReader = $null
try {
    $readerSettings = New-Object System.Xml.XmlReaderSettings
    $readerSettings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
    $readerSettings.XmlResolver = $null
    $xmlReader = [System.Xml.XmlReader]::Create($memoryStream, $readerSettings)
    $manifest = New-Object System.Xml.XmlDocument
    $manifest.XmlResolver = $null
    $manifest.Load($xmlReader)
}
finally {
    if ($null -ne $xmlReader) {
        $xmlReader.Dispose()
    }
    $memoryStream.Dispose()
}

$namespaces = New-Object System.Xml.XmlNamespaceManager($manifest.NameTable)
$namespaces.AddNamespace('asmv1', 'urn:schemas-microsoft-com:asm.v1')
$namespaces.AddNamespace('asmv3', 'urn:schemas-microsoft-com:asm.v3')
$namespaces.AddNamespace('compat', 'urn:schemas-microsoft-com:compatibility.v1')
$namespaces.AddNamespace('dpi2005', 'http://schemas.microsoft.com/SMI/2005/WindowsSettings')
$namespaces.AddNamespace('dpi2016', 'http://schemas.microsoft.com/SMI/2016/WindowsSettings')

function Get-RequiredNode {
    param(
        [Parameter(Mandatory = $true)]
        [string] $XPath,
        [Parameter(Mandatory = $true)]
        [string] $Description
    )

    $nodes = @($manifest.SelectNodes($XPath, $namespaces))
    if ($nodes.Count -ne 1) {
        throw "Expected one $Description declaration; found $($nodes.Count)."
    }
    return $nodes[0]
}

$identity = Get-RequiredNode `
    -XPath '/asmv1:assembly/asmv1:assemblyIdentity' `
    -Description 'assembly identity'
if ($identity.GetAttribute('name') -ne 'OpenSesh.opensesh' -or
    $identity.GetAttribute('processorArchitecture') -ne 'amd64' -or
    $identity.GetAttribute('type') -ne 'win32') {
    throw 'The embedded Windows assembly identity is inconsistent.'
}

$execution = Get-RequiredNode `
    -XPath '/asmv1:assembly/asmv3:trustInfo/asmv3:security/asmv3:requestedPrivileges/asmv3:requestedExecutionLevel' `
    -Description 'requested execution level'
if ($execution.GetAttribute('level') -ne 'asInvoker' -or
    $execution.GetAttribute('uiAccess') -ne 'false') {
    throw 'The editor must run asInvoker without privileged UI access.'
}

$supportedOs = Get-RequiredNode `
    -XPath '/asmv1:assembly/compat:compatibility/compat:application/compat:supportedOS' `
    -Description 'supported Windows generation'
if ($supportedOs.GetAttribute('Id').ToLowerInvariant() -ne
    '{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}') {
    throw 'The supported Windows generation identifier is inconsistent.'
}

$dpiAware = Get-RequiredNode `
    -XPath '/asmv1:assembly/asmv3:application/asmv3:windowsSettings/dpi2005:dpiAware' `
    -Description 'legacy DPI awareness'
$dpiAwareness = Get-RequiredNode `
    -XPath '/asmv1:assembly/asmv3:application/asmv3:windowsSettings/dpi2016:dpiAwareness' `
    -Description 'current DPI awareness'
if ($dpiAware.InnerText.Trim().ToLowerInvariant() -ne 'true' -or
    $dpiAwareness.InnerText.Trim() -ne 'System') {
    throw 'The editor must use the reviewed system-DPI awareness model.'
}

Write-Output 'manifest_resource=present'
Write-Output 'execution_level=asInvoker'
Write-Output 'ui_access=false'
Write-Output 'windows_generation=10_or_later'
Write-Output 'dpi_awareness=System'
Write-Output 'manifest_status=ok'

# end of tests/verify_windows_manifest.ps1

param(
    [string]$Executable = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Debug/kanade.exe')
)

$ErrorActionPreference = 'Stop'
$Executable = (Resolve-Path -LiteralPath $Executable).Path

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class KanadeCloseTest {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")]
    public static extern bool PostMessage(IntPtr window, uint message, UIntPtr wparam, IntPtr lparam);
}
'@

# Exercise real process shutdown: a widget test cannot detect native heap
# corruption that happens after the Dart VM has already stopped.
foreach ($mode in @('Normal', 'Maximized', 'Minimized', 'CaptionClose')) {
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new($Executable)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $app = [System.Diagnostics.Process]::Start($startInfo)
    try {
        $deadline = [DateTime]::UtcNow.AddSeconds(45)
        do {
            $app.Refresh()
            if ($app.HasExited) { throw "$mode : app exited before opening its window ($($app.ExitCode))" }
            $window = $app.MainWindowHandle
            if ($window -ne [IntPtr]::Zero) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($window -eq [IntPtr]::Zero) { throw "$mode : window did not open" }

        # setupWindow shows the window before app providers attach SMTC.
        Start-Sleep -Seconds 3
        if ($mode -eq 'Maximized') { [void][KanadeCloseTest]::ShowWindow($window, 3) }
        if ($mode -eq 'Minimized') { [void][KanadeCloseTest]::ShowWindow($window, 6) }
        if ($mode -eq 'CaptionClose') {
            $sent = [KanadeCloseTest]::PostMessage($window, 0x0112, [UIntPtr]0xF060, [IntPtr]::Zero)
        } else {
            $sent = $app.CloseMainWindow()
        }
        if (-not $sent) { throw "$mode : could not request close" }
        if (-not $app.WaitForExit(15000)) { throw "$mode : app did not exit within 15 seconds" }
        if ($app.ExitCode -ne 0) {
            throw ('{0} : abnormal exit 0x{1:X8}' -f $mode, $app.ExitCode)
        }
        Write-Output "PASS: $mode exits cleanly"
    } finally {
        if (-not $app.HasExited) {
            $app.Kill()
            $app.WaitForExit()
        }
        $app.Dispose()
    }
}

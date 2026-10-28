$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this script in an administrator PowerShell window.'
}

Get-Process -Name QQMusic | Out-Null

$filterOutput = @(& pktmon filter list)
if ($LASTEXITCODE -ne 0) { throw ($filterOutput -join "`n") }
$filterNames = @($filterOutput | ForEach-Object {
    if ($_ -match '^\s*\d+\s+(\S+)') { $Matches[1] }
})
if (@($filterNames | Where-Object { $_ -notmatch '^KanadeQQMusic(?:-\d+)?$' }).Count -gt 0) {
    throw 'Other PktMon filters exist. Leave them unchanged and report this message.'
}
if ($filterNames.Count -gt 0) {
    & pktmon filter remove
    if ($LASTEXITCODE -ne 0) { throw 'Could not replace the previous capture filter.' }
}

$outputDirectory = Split-Path -Parent $PSScriptRoot
$capturePath = Join-Path $outputDirectory ('qqmusic-pc-discovery-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.etl')
$socketLogPath = [IO.Path]::ChangeExtension($capturePath, '.sockets.jsonl')
$captureStarted = $false
$socketLog = $null
try {
    Write-Host 'Discovery capture records ALL local network traffic for 30 seconds; keep the files local.'
    & pktmon start --capture --comp all --pkt-size 0 --file-size 16 --file-name $capturePath
    if ($LASTEXITCODE -ne 0) { throw 'Could not start packet capture.' }
    $captureStarted = $true
    $socketLog = [IO.StreamWriter]::new($socketLogPath, $false, [Text.UTF8Encoding]::new($false))
    Write-Host 'CAPTURING: search for a NEW keyword in official QQMusic now. Capture stops in 30 seconds.'
    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ([DateTime]::UtcNow -lt $deadline) {
        $musicProcesses = @(Get-Process -Name QQMusic, QQMusicExternal, qmbrowser -ErrorAction SilentlyContinue)
        $musicProcessIds = @($musicProcesses.Id)
        $socketRows = @(& netstat -ano | ForEach-Object {
            $fields = $_.Trim() -split '\s+'
            if ($fields[0] -in @('TCP', 'UDP') -and [int]$fields[-1] -in $musicProcessIds) {
                [pscustomobject]@{
                    protocol = $fields[0]
                    local = $fields[1]
                    remote = $fields[2]
                    pid = [int]$fields[-1]
                }
            }
        })
        $record = @{
            time = [DateTime]::UtcNow.ToString('o')
            processes = @($musicProcesses | Select-Object Id, ProcessName)
            sockets = $socketRows
        } | ConvertTo-Json -Depth 4 -Compress
        $socketLog.WriteLine($record)
        Start-Sleep -Milliseconds 250
    }
}
finally {
    if ($captureStarted) { & pktmon stop }
    if ($null -ne $socketLog) { $socketLog.Dispose() }
}

& pktmon etl2pcap $capturePath --out ([IO.Path]::ChangeExtension($capturePath, '.pcapng'))
if ($LASTEXITCODE -ne 0) { throw 'Could not convert the capture to pcapng.' }
Write-Host "QQMusic connection log: $socketLogPath"

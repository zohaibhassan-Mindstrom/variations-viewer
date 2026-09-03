Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName System.Net.Http

# If this folder ships with its own copy of ffmpeg (in "ffmpeg\bin" next to this file),
# put it at the very front of PATH so it's found before anything on the system - a fresh
# copy of this whole folder then works completely offline, no setup, no internet, ever.
$bundledFfmpegDir = Join-Path $PSScriptRoot 'ffmpeg\bin'
if ((Test-Path -LiteralPath (Join-Path $bundledFfmpegDir 'ffmpeg.exe')) -and
    (Test-Path -LiteralPath (Join-Path $bundledFfmpegDir 'ffprobe.exe'))) {
    if (($env:Path -split ';') -notcontains $bundledFfmpegDir) {
        $env:Path = "$bundledFfmpegDir;$env:Path"
    }
}

function Select-FolderModern {
    param([string]$InitialPath)
    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title = "Select the folder to scan for videos (subfolders included)"
    $dlg.CheckFileExists = $false
    $dlg.CheckPathExists = $true
    $dlg.ValidateNames = $false
    $dlg.Multiselect = $false
    $dlg.FileName = "Select Folder"
    if ($InitialPath) { $dlg.InitialDirectory = $InitialPath }
    if ($dlg.ShowDialog() -ne $true) { return $null }
    return [System.IO.Path]::GetDirectoryName($dlg.FileName)
}

function Get-ClipboardPathIfValid {
    try {
        if ([System.Windows.Forms.Clipboard]::ContainsText()) {
            $t = [System.Windows.Forms.Clipboard]::GetText().Trim().Trim('"')
            if ($t -and (Test-Path -LiteralPath $t -PathType Container)) { return $t }
        }
    } catch {}
    return ""
}

function Get-VideoFrameDataUri {
    param(
        [string]$VideoPath,
        [int]$TargetFrame,
        [int]$Width,
        [int]$Quality,
        [int]$CompressionLevel,
        [string]$TempDir
    )

    $durStr = & ffprobe -v error -show_entries format=duration -of csv=p=0 -- "$VideoPath" 2>$null
    $fpsStr = & ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of csv=p=0 -- "$VideoPath" 2>$null

    $duration = 0.0
    [double]::TryParse($durStr, [ref]$duration) | Out-Null

    $fps = 0.0
    if ($fpsStr -match '^\s*(\d+)\s*/\s*(\d+)\s*$') {
        $num = [double]$matches[1]; $den = [double]$matches[2]
        if ($den -ne 0) { $fps = $num / $den }
    }

    $frameIndex = $TargetFrame
    if ($fps -gt 0 -and $duration -gt 0) {
        $totalFrames = [math]::Floor($fps * $duration)
        if ($totalFrames -gt 0) {
            $frameIndex = [math]::Min($TargetFrame, $totalFrames - 1)
        }
    }
    if ($frameIndex -lt 0) { $frameIndex = 0 }

    $outFile = Join-Path $TempDir ([System.IO.Path]::GetRandomFileName() + ".webp")
    $vf = "select=eq(n\,$frameIndex),scale=${Width}:-2"
    & ffmpeg -y -v error -i "$VideoPath" -vf $vf -vframes 1 -c:v libwebp -quality $Quality -compression_level $CompressionLevel -- "$outFile" 2>$null

    if (-not (Test-Path -LiteralPath $outFile) -or (Get-Item -LiteralPath $outFile).Length -eq 0) {
        if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }
        return $null
    }

    $bytes = [System.IO.File]::ReadAllBytes($outFile)
    Remove-Item -LiteralPath $outFile -Force
    $b64 = [Convert]::ToBase64String($bytes)
    return "data:image/webp;base64,$b64"
}

function Get-ScanMode {
    param([Parameter(Mandatory)][string]$Path)
    $segments = $Path -split '[\\/]' | Where-Object { $_ -ne '' }
    if ($segments | Where-Object { $_ -ieq 'Videos' }) { return 'Video' }
    if ($segments | Where-Object { $_ -ieq 'Playables' }) { return 'Playable' }
    return 'Ambiguous'
}

function Select-PlayableHtmlFile {
    param([AllowEmptyCollection()][object[]]$Candidates = @())
    $list = @($Candidates)
    if ($list.Count -eq 0) { return $null }
    if ($list.Count -eq 1) { return $list[0] }

    $preferred = @($list | Where-Object { $_.Name -imatch '_applovin\.html$' })
    if ($preferred.Count -eq 1) { return $preferred[0] }
    return $null
}

function Find-PlayableCandidates {
    param([Parameter(Mandatory)][string]$Root)

    $variationDirs = Get-ChildItem -LiteralPath $Root -Directory
    $candidates = @()

    foreach ($dir in $variationDirs) {
        $htmlFiles = @(Get-ChildItem -LiteralPath $dir.FullName -Recurse -File -Filter '*.html' |
            Where-Object {
                $relativeDir = $_.DirectoryName.Substring($dir.FullName.Length)
                $relativeDir -imatch '(^|[\\/])applovin([\\/]|$)'
            })

        $chosen = Select-PlayableHtmlFile -Candidates $htmlFiles

        if ($chosen) {
            $candidates += [PSCustomObject]@{ File = $chosen.FullName; Label = $dir.Name }
        } elseif ($htmlFiles.Count -eq 0) {
            Write-Host "SKIP (no playable .html found under 'applovin'): $($dir.FullName)"
        } else {
            Write-Host "SKIP (ambiguous, multiple .html candidates): $($dir.FullName)"
        }
    }

    return @($candidates | Sort-Object Label)
}

function Find-VideoCandidates {
    param(
        [Parameter(Mandatory)][string]$Root,
        [AllowEmptyCollection()][System.IO.FileInfo[]]$AllVideos = @(),
        [string]$DurationTag = ""
    )

    $groups = $AllVideos | Group-Object DirectoryName
    $candidates = @()

    foreach ($g in $groups) {
        $dirPath = $g.Name
        $filesInDir = $g.Group

        if ($dirPath -eq $Root) {
            foreach ($f in $filesInDir) {
                $candidates += [PSCustomObject]@{ File = $f.FullName; Label = $f.BaseName }
            }
            continue
        }

        $match = $filesInDir | Where-Object { $_.BaseName -match '1080x1920' } | Select-Object -First 1
        if (-not $match -and $filesInDir.Count -eq 1) { $match = $filesInDir[0] }

        if ($match) {
            $folderName = Split-Path $dirPath -Leaf
            $candidates += [PSCustomObject]@{ File = $match.FullName; Label = $folderName }
        } else {
            Write-Host "SKIP (ambiguous, no 1080x1920 file): $dirPath"
        }
    }

    if ($DurationTag) {
        $before = $candidates.Count
        $candidates = $candidates | Where-Object { $_.Label -match [regex]::Escape($DurationTag) }
        $skipped = $before - $candidates.Count
        if ($skipped -gt 0) { Write-Host "Filtered out $skipped variation(s) not tagged '$DurationTag'." }
    }

    return @($candidates | Sort-Object Label)
}

function Resolve-LongPath {
    param([Parameter(Mandatory)][string]$Path)
    try {
        return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    } catch {
        if ($Path -notmatch '^\\\\\?\\') { return "\\?\$Path" }
        throw
    }
}

function Test-FfmpegAvailable {
    return (Get-Command ffmpeg -ErrorAction SilentlyContinue) -and (Get-Command ffprobe -ErrorAction SilentlyContinue)
}

function Update-SessionPathFromRegistry {
    # winget writes the newly-installed program's folder into the persistent (registry)
    # PATH, but a process that was already running before the install started doesn't
    # pick that up automatically - Windows only re-reads PATH for new processes. Refresh
    # this session's $env:Path from the registry so a just-installed tool can be found
    # without needing to close and reopen this window.
    $machinePath = [System.Environment]::GetEnvironmentVariable('Path', 'Machine')
    $userPath = [System.Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = @($machinePath, $userPath) -join ';'
}

function Install-FfmpegIfMissing {
    if (Test-FfmpegAvailable) { return $true }

    Write-Host "ffmpeg isn't installed on this computer yet - installing it automatically (one-time, needs internet)..."

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host "winget (Windows' app installer) isn't available on this computer, so this can't be automatic."
        Write-Host "Install it yourself: open PowerShell and run 'winget install Gyan.FFmpeg', then run this tool again."
        return $false
    }

    & winget install --id Gyan.FFmpeg -e --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
    $wingetExitCode = $LASTEXITCODE

    Update-SessionPathFromRegistry

    if (Test-FfmpegAvailable) {
        Write-Host "ffmpeg installed successfully."
        Write-Host ""
        return $true
    }

    if ($wingetExitCode -ne 0) {
        Write-Host "Automatic ffmpeg install failed (winget exit code $wingetExitCode)."
    } else {
        Write-Host "ffmpeg was installed, but this window can't quite see it yet."
    }
    Write-Host "Try closing this window and running the tool again - if that doesn't work, open PowerShell and run 'winget install Gyan.FFmpeg' yourself."
    return $false
}

function Resolve-EdgePath {
    $cmd = Get-Command msedge -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        (Join-Path ${env:ProgramFiles} 'Microsoft\Edge\Application\msedge.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe')
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return $null
}

function Get-FreeTcpPort {
    $listener = New-Object System.Net.Sockets.TcpListener ([System.Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $listener.Stop()
    return $port
}

function Receive-CdpMessage {
    param([Parameter(Mandatory)]$WebSocket, [Parameter(Mandatory)]$CancellationToken)
    $chunkSize = 65536
    $buffer = New-Object byte[] $chunkSize
    $ms = New-Object System.IO.MemoryStream
    try {
        while ($true) {
            $seg = New-Object System.ArraySegment[byte] (,$buffer)
            $result = $WebSocket.ReceiveAsync($seg, $CancellationToken).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) { return $null }
            $ms.Write($buffer, 0, $result.Count)
            if ($result.EndOfMessage) { break }
        }
        return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
    } finally {
        $ms.Dispose()
    }
}

function Wait-CdpMessage {
    param([Parameter(Mandatory)]$WebSocket, [Parameter(Mandatory)][scriptblock]$Predicate, [int]$TimeoutMs = 15000)
    $cts = New-Object System.Threading.CancellationTokenSource($TimeoutMs)
    try {
        while ($true) {
            $text = Receive-CdpMessage -WebSocket $WebSocket -CancellationToken $cts.Token
            if ($null -eq $text) { throw "CDP WebSocket closed unexpectedly" }
            $obj = $text | ConvertFrom-Json
            if (& $Predicate $obj) { return $obj }
        }
    } finally {
        $cts.Dispose()
    }
}

function Send-CdpCommand {
    param([Parameter(Mandatory)]$WebSocket, [Parameter(Mandatory)][int]$Id, [Parameter(Mandatory)][string]$Method, $Params = @{}, [int]$TimeoutMs = 5000)
    $json = (@{ id = $Id; method = $Method; params = $Params } | ConvertTo-Json -Compress -Depth 10)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
    $seg = New-Object System.ArraySegment[byte] (,$bytes)
    $cts = New-Object System.Threading.CancellationTokenSource($TimeoutMs)
    try {
        $WebSocket.SendAsync($seg, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, $cts.Token).GetAwaiter().GetResult() | Out-Null
    } finally {
        $cts.Dispose()
    }
}

function Get-PlayableSnapshotDataUri {
    param(
        [Parameter(Mandatory)][string]$HtmlPath,
        [Parameter(Mandatory)][string]$EdgePath,
        [int]$WaitMs = 2500,
        [int]$CaptureWidth = 1080,
        [int]$CaptureHeight = 1920,
        [int]$ThumbWidth = 540,
        [int]$Quality = 92,
        [int]$CompressionLevel = 6,
        [Parameter(Mandatory)][string]$TempDir
    )

    # Headless Edge's one-shot "--screenshot --virtual-time-budget" CLI mode looks like the
    # simplest way to capture a page, but virtual-time-budget mode caps requestAnimationFrame
    # to firing once, no matter how long the budget is - so any rAF-driven canvas/WebGL
    # content (i.e. virtually every playable ad engine) never gets past its first, usually
    # blank, frame. Real capture instead requires driving Edge over the DevTools Protocol
    # (CDP) with a genuine wall-clock wait, so the playable's own render loop actually runs.

    # Windows PowerShell 5.1's Start-Process -ArgumentList joins array elements with a
    # plain space and does NOT quote elements that contain spaces themselves (unlike `&`,
    # which quotes each argument correctly). $edgeProfileDir (under $TempDir) can contain
    # spaces (e.g. a user profile folder like "C:\Users\Jane Doe\..."), so it must be quoted
    # here ourselves, or a space splits it into extra bare tokens Edge misreads as additional
    # URL targets ("Multiple targets are not supported"). $fileUri needs no such handling -
    # [uri]::AbsoluteUri already percent-encodes spaces and other reserved characters.
    function Format-EdgeArg([string]$Arg) {
        if ($Arg -match '\s') { return '"' + $Arg + '"' }
        return $Arg
    }

    # Everything that can throw (file copy, process launch, network I/O) must run inside this
    # try - the caller's per-candidate loop has no try/catch of its own, so an exception
    # escaping this function would abort the entire scan and lose every card already
    # captured, not just this one. Every resource created below is torn down in the finally
    # block regardless of how far execution got.
    $rawPng = $null
    $proc = $null
    $client = $null
    $ws = $null
    $shortHtmlCopy = $null
    $edgeProfileDir = $null
    try {
        $fullPath = Resolve-LongPath -Path $HtmlPath

        # Chromium's own file-loading code (unlike .NET/PowerShell's file APIs) fails to open
        # local files whose full path exceeds Windows' classic 260-character MAX_PATH - it
        # reports ERR_FILE_NOT_FOUND even though the file genuinely exists and is readable.
        # Box-synced folder trees routinely produce paths well past that limit. Since AppLovin
        # playables are single self-contained HTML files with no external asset references,
        # copying to a short temp filename sidesteps the limit entirely. Copy from $fullPath
        # (which may carry a \\?\ long-path prefix) rather than a stripped version, so the
        # copy itself isn't blocked by the same MAX_PATH limit it exists to work around.
        $shortHtmlCopy = Join-Path $TempDir ([System.IO.Path]::GetRandomFileName() + ".html")
        Copy-Item -LiteralPath $fullPath -Destination $shortHtmlCopy -Force
        $fileUri = ([uri]$shortHtmlCopy).AbsoluteUri

        $edgeProfileDir = Join-Path $TempDir ('edge-profile-' + [System.IO.Path]::GetRandomFileName())
        New-Item -ItemType Directory -Force -Path $edgeProfileDir | Out-Null

        $port = Get-FreeTcpPort
        $userDataDirArg = Format-EdgeArg "--user-data-dir=$edgeProfileDir"

        # Single navigation straight to the target URL at launch (rather than opening about:blank
        # and issuing a second Page.navigate over CDP) - navigating away from about:blank via CDP
        # was found to abort unpredictably for some local files, while navigating directly at
        # launch is reliable.
        $edgeArgs = @("--headless=new", "--hide-scrollbars", "--window-size=$CaptureWidth,$CaptureHeight", "--remote-debugging-port=$port", $userDataDirArg, "--no-first-run", "--no-default-browser-check", "$fileUri")
        $proc = Start-Process -FilePath $EdgePath -ArgumentList $edgeArgs -PassThru -WindowStyle Hidden

        $client = New-Object System.Net.Http.HttpClient
        $target = $null
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($sw.ElapsedMilliseconds -lt 10000) {
            try {
                $listJson = $client.GetStringAsync("http://127.0.0.1:$port/json/list").GetAwaiter().GetResult()
                if ($listJson) {
                    $targets = $listJson | ConvertFrom-Json
                    $target = $targets | Where-Object { $_.type -eq 'page' -and $_.webSocketDebuggerUrl } | Select-Object -First 1
                    if ($target) { break }
                }
            } catch {}
            Start-Sleep -Milliseconds 200
        }
        if (-not $target) { throw "No usable Edge DevTools page target found" }

        $ws = New-Object System.Net.WebSockets.ClientWebSocket
        $connectCts = New-Object System.Threading.CancellationTokenSource(10000)
        try {
            $ws.ConnectAsync([uri]$target.webSocketDebuggerUrl, $connectCts.Token).GetAwaiter().GetResult() | Out-Null
        } finally {
            $connectCts.Dispose()
        }

        # --window-size alone doesn't reliably control the actual rendered viewport in
        # headless mode; force it explicitly so captures come out at the requested size.
        # deviceScaleFactor=1 (not 0/"use host default") keeps the pixel dimensions
        # deterministic regardless of the host machine's display scaling.
        Send-CdpCommand -WebSocket $ws -Id 1 -Method "Emulation.setDeviceMetricsOverride" -Params @{ width = $CaptureWidth; height = $CaptureHeight; deviceScaleFactor = 1; mobile = $false }
        Wait-CdpMessage -WebSocket $ws -Predicate { param($o) $o.id -eq 1 } | Out-Null

        $ready = $false
        $readySw = [System.Diagnostics.Stopwatch]::StartNew()
        $reqId = 100
        while ($readySw.ElapsedMilliseconds -lt 15000) {
            $reqId++
            Send-CdpCommand -WebSocket $ws -Id $reqId -Method "Runtime.evaluate" -Params @{ expression = "document.readyState" }
            $resp = Wait-CdpMessage -WebSocket $ws -Predicate { param($o) $o.id -eq $reqId } -TimeoutMs 5000
            if ($resp.result.result.value -eq "complete") { $ready = $true; break }
            Start-Sleep -Milliseconds 200
        }
        if (-not $ready) { throw "Page never reached readyState=complete" }

        # real wall-clock wait so the playable's own rAF-driven render loop actually runs
        Start-Sleep -Milliseconds $WaitMs

        Send-CdpCommand -WebSocket $ws -Id 999 -Method "Page.captureScreenshot" -Params @{ format = "png" }
        $shot = Wait-CdpMessage -WebSocket $ws -Predicate { param($o) $o.id -eq 999 } -TimeoutMs 15000

        $pngBytes = [Convert]::FromBase64String($shot.result.data)
        $rawPng = Join-Path $TempDir ([System.IO.Path]::GetRandomFileName() + ".png")
        [System.IO.File]::WriteAllBytes($rawPng, $pngBytes)
    } catch {
        $rawPng = $null
    } finally {
        if ($ws) {
            try { if ($ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) { $ws.Abort() } } catch {}
            try { $ws.Dispose() } catch {}
        }
        if ($client) { try { $client.Dispose() } catch {} }
        if ($proc) {
            try {
                if (-not $proc.HasExited) {
                    $proc.Kill()
                    $proc.WaitForExit(5000) | Out-Null
                }
            } catch {}
        }
        if ($edgeProfileDir) { Remove-Item -LiteralPath $edgeProfileDir -Recurse -Force -ErrorAction SilentlyContinue }
        if ($shortHtmlCopy) { Remove-Item -LiteralPath $shortHtmlCopy -Force -ErrorAction SilentlyContinue }
    }

    if (-not $rawPng -or -not (Test-Path -LiteralPath $rawPng) -or (Get-Item -LiteralPath $rawPng).Length -eq 0) {
        if ($rawPng -and (Test-Path -LiteralPath $rawPng)) { Remove-Item -LiteralPath $rawPng -Force }
        return $null
    }

    $outWebp = Join-Path $TempDir ([System.IO.Path]::GetRandomFileName() + ".webp")
    $vf = "scale=${ThumbWidth}:-2"
    & ffmpeg -y -v error -i "$rawPng" -vf $vf -c:v libwebp -quality $Quality -compression_level $CompressionLevel -- "$outWebp" 2>$null

    Remove-Item -LiteralPath $rawPng -Force -ErrorAction SilentlyContinue

    if (-not (Test-Path -LiteralPath $outWebp) -or (Get-Item -LiteralPath $outWebp).Length -eq 0) {
        if (Test-Path -LiteralPath $outWebp) { Remove-Item -LiteralPath $outWebp -Force }
        return $null
    }

    $bytes = [System.IO.File]::ReadAllBytes($outWebp)
    Remove-Item -LiteralPath $outWebp -Force
    $b64 = [Convert]::ToBase64String($bytes)
    return "data:image/webp;base64,$b64"
}

function Resolve-ScanMode {
    param([Parameter(Mandatory)][string]$Path)

    $mode = Get-ScanMode -Path $Path
    if ($mode -ne 'Ambiguous') { return $mode }

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Choose mode"
    $form.Size = New-Object System.Drawing.Size(480, 230)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true

    $label = New-Object System.Windows.Forms.Label
    $label.Text = "Couldn't tell from the folder path whether these are Videos or Playables (HTML ads).`n`nWhich one is it?"
    $label.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $label.SetBounds(20, 20, 430, 90)
    $form.Controls.Add($label)

    $videoButton = New-Object System.Windows.Forms.Button
    $videoButton.Text = "Video"
    $videoButton.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $videoButton.SetBounds(70, 130, 150, 50)
    $videoButton.DialogResult = [System.Windows.Forms.DialogResult]::Yes
    $form.Controls.Add($videoButton)

    $playableButton = New-Object System.Windows.Forms.Button
    $playableButton.Text = "Playable"
    $playableButton.Font = New-Object System.Drawing.Font("Segoe UI", 11)
    $playableButton.SetBounds(260, 130, 150, 50)
    $playableButton.DialogResult = [System.Windows.Forms.DialogResult]::No
    $form.Controls.Add($playableButton)

    $form.AcceptButton = $videoButton

    $result = $form.ShowDialog()
    $form.Dispose()

    if ($result -eq [System.Windows.Forms.DialogResult]::No) { return 'Playable' }
    return 'Video'
}

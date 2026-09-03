<#
Creative Board
Recursively scans a chosen folder for videos, grabs frame #80 (falling back to the
last available frame on short clips) from each, and builds a single self-contained
HTML board (grid + click-to-zoom lightbox) with every frame embedded as base64 WebP.

Folder layout it understands:
  - A variation subfolder containing several resolution exports of the same video
    (e.g. .../darkblue/xxx_1080x1920_darkblue.mp4, xxx_1024x768_darkblue.mp4, ...)
    -> picks the file whose name contains "1080x1920", labels the card with the
       subfolder name (e.g. "darkblue").
  - Video files sitting directly in the chosen root (no subfolder) -> each file is
    its own card, labeled by filename.
  - A subfolder with exactly one video and no "1080x1920" match -> uses that one file.
  - A subfolder with multiple videos and no "1080x1920" match -> skipped, with a
    console warning (ambiguous - can't guess which resolution you want).

The generated HTML is written to your Windows temp folder and opened in your
default browser. Nothing is written back into the folder you scanned. Saving a
copy elsewhere (Box, Desktop, wherever) is entirely up to you from there -
it's a normal, fully self-contained .html file.
#>

param(
    [string]$Path,
    [int]$TargetFrameIndex = 79,   # 0-based -> "frame 80"
    [int]$ThumbWidth = 540,        # ~half of 1080, keeps the file sane at 100+ videos
    [int]$Quality = 92,
    [int]$CompressionLevel = 6,    # 0-6; higher = smaller file at identical quality, slower encode
    [string]$DurationTag = "30s",  # only keep variations whose name contains this tag; "" disables the filter ("Video" mode only)
    [int]$PlayableWaitMs = 2500,        # how long (virtual time) to let a playable run before capturing
    [int]$PlayableCaptureWidth = 1080,  # headless browser window width used for playable capture
    [int]$PlayableCaptureHeight = 1920  # headless browser window height used for playable capture
)

. (Join-Path $PSScriptRoot "frame-board-functions.ps1")

# --- resolve target folder ---
if (-not $Path) {
    $suggested = Get-ClipboardPathIfValid
    $Path = Select-FolderModern -InitialPath $suggested
    if (-not $Path) { Write-Host "Cancelled."; exit }
}
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Write-Host "Not a valid folder: $Path"
    exit 1
}
$root = (Resolve-Path -LiteralPath $Path).Path

$mode = Resolve-ScanMode -Path $root
Write-Host "Detected mode: $mode"
Write-Host ""

if (-not (Install-FfmpegIfMissing)) {
    exit 1
}

if ($mode -eq 'Video') {
    $videoExts = @('.mp4', '.mov', '.mkv', '.avi', '.webm', '.m4v')
    $allVideos = Get-ChildItem -LiteralPath $root -Recurse -File | Where-Object { $videoExts -contains $_.Extension.ToLower() }

    if ($allVideos.Count -eq 0) {
        Write-Host "No video files found under: $root"
        exit
    }

    $candidates = Find-VideoCandidates -Root $root -AllVideos $allVideos -DurationTag $DurationTag
} else {
    $edgePath = Resolve-EdgePath
    if (-not $edgePath) {
        Write-Host "Microsoft Edge not found. It ships with Windows 10/11 - check your install."
        exit 1
    }
    $candidates = Find-PlayableCandidates -Root $root
}
$n = $candidates.Count
if ($n -eq 0) { Write-Host "Nothing to process."; exit }

Write-Host "Found $n variation(s) under: $root"
Write-Host ""

$tempDir = Join-Path $env:TEMP ("frame-board-frames-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$results = @()
$i = 0
foreach ($c in $candidates) {
    $i++
    Write-Host ("[{0}/{1}] {2} ..." -f $i, $n, $c.Label) -NoNewline
    if ($mode -eq 'Video') {
        $dataUri = Get-VideoFrameDataUri -VideoPath $c.File -TargetFrame $TargetFrameIndex -Width $ThumbWidth -Quality $Quality -CompressionLevel $CompressionLevel -TempDir $tempDir
    } else {
        $dataUri = Get-PlayableSnapshotDataUri -HtmlPath $c.File -EdgePath $edgePath -WaitMs $PlayableWaitMs -CaptureWidth $PlayableCaptureWidth -CaptureHeight $PlayableCaptureHeight -ThumbWidth $ThumbWidth -Quality $Quality -CompressionLevel $CompressionLevel -TempDir $tempDir
    }
    if ($dataUri) {
        Write-Host " OK"
        $results += [PSCustomObject]@{ name = $c.Label; img = $dataUri }
    } else {
        Write-Host " FAILED"
    }
}

Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

$ok = $results.Count
$failed = $n - $ok
Write-Host ""
Write-Host "Done: $ok processed, $failed failed."

if ($ok -eq 0) {
    Write-Host "No frames extracted successfully - nothing to build."
    exit
}

$templatePath = Join-Path $PSScriptRoot "board-template.html"
if (-not (Test-Path -LiteralPath $templatePath)) {
    Write-Host "board-template.html not found next to the script - can't build the viewer."
    exit 1
}

$cardsJson = $results | ConvertTo-Json -Compress -Depth 3
if ($results.Count -eq 1) { $cardsJson = "[$cardsJson]" }
$cardsJson = $cardsJson -replace '</', '<\/'
$rootJson = ($root | ConvertTo-Json -Compress) -replace '</', '<\/'
$genTime = Get-Date -Format "yyyy-MM-dd HH:mm"

$html = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8
$html = $html.Replace('__CARDS_JSON__', $cardsJson)
$html = $html.Replace('__ROOT_PATH_JSON__', $rootJson)
$html = $html.Replace('__GENERATED_AT__', $genTime)

$reportPath = Join-Path $env:TEMP ("frame-board-{0}.html" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
Set-Content -LiteralPath $reportPath -Value $html -Encoding UTF8
Write-Host "Viewer written to: $reportPath"
Write-Host "(It's a normal, self-contained .html file - save/move a copy anywhere you like.)"
Start-Process $reportPath

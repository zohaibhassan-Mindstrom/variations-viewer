# 🎬 Creative Board

**Compare all your video and playable ad variations on one page — instead of opening them one by one.**

![Platform](https://img.shields.io/badge/platform-Windows%2010%2F11-0078D6?logo=windows&logoColor=white)
![Shell](https://img.shields.io/badge/shell-PowerShell-5391FE?logo=powershell&logoColor=white)
![Requires](https://img.shields.io/badge/requires-ffmpeg-007808)
![Output](https://img.shields.io/badge/output-self--contained%20HTML-orange)
![No install for viewers](https://img.shields.io/badge/viewing%20the%20board-zero%20install-brightgreen)

Point it at a folder full of video variations *or* HTML playable ads, and
it builds one self-contained web page showing a picture from each, side
by side — so you can compare all of them at a glance instead of opening
20+ files one by one.

No coding knowledge needed to use it. Everything technical is explained
below, and the last couple of sections are for anyone who wants to
fine-tune it.

## Table of Contents

- [Who Can Use This](#who-can-use-this)
- [Quick Start](#quick-start)
- [What You'll See](#what-youll-see)
- [How It Picks What to Show](#how-it-picks-what-to-show)
  - [Video mode](#video-mode)
  - [Playable mode (HTML ads)](#playable-mode-html-ads)
- [First-Time Setup](#first-time-setup)
- [FAQ](#faq)
- [Advanced: Tuning the Defaults](#advanced-tuning-the-defaults)
- [Project Structure](#project-structure)
- [Requirements](#requirements)

## Who Can Use This

There are two different things here, with two different answers:

- **The finished board** (the web page this tool produces, especially once
  you click 💾 Save) — works for **anyone, on anything**. Windows, Mac,
  Linux, phone, tablet — any modern browser can open it, with no internet
  connection and nothing installed. You can email it, message it, put it on
  a USB stick, whatever you like — it'll just work. This is the part you
  hand to clients, teammates, anyone.

- **The tool that builds the board** (`Make Frame Board.bat`) — only works
  on **Windows**. It needs **ffmpeg**, but installs it automatically the
  first time it's needed (see [First-Time Setup](#first-time-setup)) — no
  separate download or install step for anyone. It won't run on a Mac or
  Linux machine at all, but on Windows a teammate can just copy this whole
  folder and double-click, nothing to set up first.

## Quick Start

1. **Double-click `Make Frame Board.bat`.**
2. A window pops up asking you to pick a folder. Choose the folder that
   contains your variations — it looks inside every subfolder
   automatically, you don't need to point it at each one individually.
3. A black console window appears and lists each variation as it works
   through them. When it's done, **your web browser opens automatically**
   showing the finished board. That's it.

> **Tip:** the first time you run it on a folder stored in Box, it can be
> slow — see [the FAQ](#faq) below, that's normal and only happens once.

## What You'll See

- A grid of picture cards, one per video/playable, named after the
  video/folder.
- A **search box** at the top — type part of a name (e.g. `dark`) and the
  grid instantly narrows down to matching cards.
- **Click any card** to select it — selected cards get a highlighted
  border and checkmark. A small **"N selected" badge** appears next to
  Save; click it to see the list of selected names, with buttons to
  **📋 Copy** them (as a count + one name per line, ready to paste into a
  message) or **Clear** the selection. Selections stay put even while
  you're using the search box.
- A **💾 Save button** — click it to download the whole page (including
  every picture on it) as one file you can keep, rename, and share however
  you like — email it, put it on a USB stick, upload it anywhere. It will
  keep working forever, even with no internet connection, because every
  picture is baked directly into the file (nothing is loaded from the
  internet when you open it).

## How It Picks What to Show

The tool automatically detects whether you're pointing it at videos or
playables, based on the folder path (`\Videos\` vs `\Playables\`) — no
extra clicks needed. It tells you which mode it picked at the top of the
console output. If the path is under neither, a small popup asks you
which one it is.

### Video mode

Say your folder looks like this (this is a real example from a Box folder):

```
Cylinder Lego Color 1/Brainage/
├── ..._30s_1080x1920_darkblue/
│     ├── ..._1000x1000_darkblue.mp4
│     ├── ..._1080x1920_darkblue.mp4   <- this one gets picked
│     └── ..._1920x1080_darkblue.mp4
├── ..._30s_1080x1920_darkgreen/
│     └── (same pattern)
└── ..._59s_1080x1920_darkblue/        <- this whole folder gets skipped
      └── (same pattern)
```

The rules it follows:

1. Each **subfolder** is treated as one "variation" (one card on the board).
2. Inside that subfolder, if there are several versions of the same video at
   different sizes, it picks the one with **1080x1920** in its name (the
   tall, phone-screen-shaped one) and ignores the rest.
3. It only keeps variations whose name contains **"30s"** — anything marked
   with a different length (like "59s"), or with no length mentioned at all,
   is skipped. (This can be changed — see
   [Advanced: Tuning the Defaults](#advanced-tuning-the-defaults).)
4. From the picked video, it grabs a single picture from **frame 80** —
   roughly 2.5–3 seconds in. This is deliberate: the very first frame of a
   video is often a blank/black loading frame, so it skips ahead a bit to
   land on the real content. If a video is shorter than that, it just uses
   its last frame instead.

If a subfolder has multiple videos and none of them says "1080x1920", the
tool skips it and prints a warning in the console rather than guessing
wrong — you'd need to rename things so there's one clear choice.

### Playable mode (HTML ads)

- Each subfolder is still one variation (one card on the board), same as
  with videos.
- The tool looks inside that variation for an `applovin` folder containing
  the playable's `.html` file, opens it in an invisible ("headless") copy
  of Microsoft Edge, lets it actually run for about 2.5 real seconds, and
  takes a snapshot — the playable equivalent of grabbing frame 80 from a
  video.
- If a variation has more than one `.html` file under `applovin` and it's
  not clear which one to use, it's skipped with a console warning, rather
  than guessing.
- The "only 30s variations" duration filter doesn't apply here, since
  playable names don't follow that convention — every variation found is
  processed.

This mode needs **Microsoft Edge**, which is already built into Windows
10/11 — nothing extra to install.

## First-Time Setup

There's nothing to do — it's fully automatic, and usually needs no
internet connection at all. This tool relies on a free, well-known tool
called **ffmpeg** (it does the actual video-reading and
picture-extraction):

- **If you got this folder directly from a teammate** (Box, a zip, a USB
  stick — anything other than downloading just the code from GitHub), it
  already includes its own copy of ffmpeg in an `ffmpeg` subfolder.
  Nothing to install, no internet needed, ever — it just works.
- **If you only got the code from GitHub** (that copy leaves ffmpeg out —
  it's too large for a code repository), the very first time you run the
  tool on a computer that doesn't have ffmpeg yet, it installs it for you
  automatically (via `winget`, the installer already built into Windows)
  before continuing. You'll see it happen in the console window — it just
  takes a little longer that one time, and needs an internet connection
  for that one step. Every run after that is instant, same as normal.

If that computer somehow doesn't have `winget` either (very rare — it
ships with Windows 10/11 by default) and there's no bundled `ffmpeg`
folder either, the tool will tell you clearly and give you the one-line
command to run yourself instead.

Nothing else needs installing. Windows already has everything else this
tool needs built in.

## FAQ

<details>
<summary><strong>Why did it take 20+ minutes the first time, but seconds the second time?</strong></summary>
<br>

Your videos live in Box, which only downloads them to your computer the
moment something actually needs to open them (this is normal Box behavior,
not something this tool controls). The very first time you scan a folder,
Box has to fetch every video from the cloud before this tool can look at
it — that's the slow part, and it's Box's download speed, not this tool.
Once Box has a video cached locally, reading it again is instant, so a
re-run on the same folder is much faster (in testing: 22 videos in about 8
seconds, once cached).
</details>

<details>
<summary><strong>Why is the generated file a few megabytes, when other tools I've seen are tiny (50KB)?</strong></summary>
<br>

Those tiny files usually don't actually contain any pictures — they just
point at pictures hosted somewhere online (a "link"), so they only work as
long as that link stays alive and you're connected to the internet. This
tool instead bakes every picture directly into the file, so it's slightly
bigger but works forever, offline, and can never break or go missing.
</details>

<details>
<summary><strong>Does this upload my videos or pictures anywhere?</strong></summary>
<br>

No. Everything happens entirely on your own computer. The finished web
page is saved to your computer's temporary files folder and opened in your
browser — nothing is sent over the internet by this tool.
</details>

<details>
<summary><strong>Can I keep a permanent copy of the board?</strong></summary>
<br>

Yes — click the 💾 Save button on the page itself and choose where to save it.
</details>

## Advanced: Tuning the Defaults

Everything below is optional. The tool works fine out of the box with no
changes — this section is only for adjusting exactly how it behaves.

`make-frame-board.ps1` accepts these parameters (or edit the defaults
directly at the top of the file):

| Parameter | Default | What it controls |
|---|---|---|
| `TargetFrameIndex` | `79` (0-based, i.e. "frame 80") | Which frame of the video to capture. |
| `ThumbWidth` | `540` pixels | Output picture width; height follows automatically. Lower = smaller file, softer image. |
| `Quality` | `92` | WebP (the picture format used) compression quality, 0–100. Lower = smaller file, more compression artifacts. |
| `CompressionLevel` | `6` | How hard the encoder tries to shrink the file at the *same* quality (0–6). Higher = a bit smaller, a bit slower to generate — no visual downside. |
| `DurationTag` | `"30s"` | Only keep video variations whose name contains this text (Video mode only). Pass `""` (empty) to stop filtering by duration entirely. |
| `PlayableWaitMs` | `2500` | How long (real time) to let a playable run before capturing a snapshot. |
| `PlayableCaptureWidth` | `1080` | Headless browser viewport width used to capture a playable. |
| `PlayableCaptureHeight` | `1920` | Headless browser viewport height used to capture a playable. |

Example — process everything regardless of duration, at a smaller size:

```powershell
powershell -File "make-frame-board.ps1" -DurationTag "" -ThumbWidth 360 -Quality 80
```

Rough size guide at the current settings (540px wide, quality 92): about
125KB per picture, so ~2.7MB for 22 variations, or ~12MB for 100.

## Project Structure

| File | Purpose |
|---|---|
| `Make Frame Board.bat` | **Double-click this to run the tool.** |
| `make-frame-board.ps1` | The orchestrator — handles the folder picker, ties everything together, and calls into `frame-board-functions.ps1` to do the actual work. You don't need to open this. |
| `frame-board-functions.ps1` | The function library — folder scanning, video/playable capture, page building. Dot-sourced by `make-frame-board.ps1`; must stay in the same folder. You don't need to open this. |
| `board-template.html` | A blank template the tool fills in with real pictures each time you run it. Don't open this one directly — on its own it's just empty placeholders and will look broken. |
| `ffmpeg/` | The bundled copy of ffmpeg, if this folder came with one (see [First-Time Setup](#first-time-setup)). Keep it in the same folder — don't rename or move it out. |
| `tests/` | Automated (Pester) tests for the function library. Only relevant if you're changing the code. |

## Requirements

- Windows 10 or 11.
- **ffmpeg** installed (see [First-Time Setup](#first-time-setup) above).
- **Microsoft Edge** for Playable mode (already built into Windows 10/11).
- No admin rights needed, nothing else to install.

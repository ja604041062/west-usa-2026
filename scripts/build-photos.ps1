# 照片／影片壓縮管線
#
# 讀取 data/points.js 裡每個地點的 srcFolder，把使用者分類好的原始照片
# 與影片轉成網頁可用的版本，並產生 data/photos.js 供前端讀取。
#
# 照片：轉成兩種尺寸 —— 縮圖（600px 寬，面板照片牆用）與大圖
#       （2000px 寬，燈箱用）。
# 影片：長邊壓到 1280px、幀率上限 30fps、H.264 CRF 28、音訊 AAC，
#       並額外擷取一張畫面當縮圖（跟照片縮圖同樣是 600px 寬，面板
#       照片牆才能混排）。
#
# 照片壓縮只用 Windows 內建的 .NET System.Drawing；影片壓縮需要
# ffmpeg（用 winget install --id Gyan.FFmpeg 安裝，這台電腦上已裝好）。
#
# 可重複執行任意多次：已經是最新的輸出不會重新處理，只有新增或
# 修改過的來源檔案才會被處理。使用者之後補照片/影片，把檔案拖進
# 對應資料夾再重跑這支腳本即可。
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\build-photos.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'lib\DataFile.ps1')
. (Join-Path $PSScriptRoot 'lib\FFmpeg.ps1')

# ------------------------------------------------------------------ 照片

# EXIF 方向標記（tag 274）—— 相機直拍的照片會帶這個標記，System.Drawing
# 不會自動轉正，不處理的話直拍照片在網頁上會整個躺平。
# 對照表是 EXIF 標準定義的 8 種方向。
function Get-RotateFlipForOrientation {
    param([int]$Orientation)
    switch ($Orientation) {
        2 { return [System.Drawing.RotateFlipType]::RotateNoneFlipX }
        3 { return [System.Drawing.RotateFlipType]::Rotate180FlipNone }
        4 { return [System.Drawing.RotateFlipType]::Rotate180FlipX }
        5 { return [System.Drawing.RotateFlipType]::Rotate90FlipX }
        6 { return [System.Drawing.RotateFlipType]::Rotate90FlipNone }
        7 { return [System.Drawing.RotateFlipType]::Rotate270FlipX }
        8 { return [System.Drawing.RotateFlipType]::Rotate270FlipNone }
        default { return [System.Drawing.RotateFlipType]::RotateNoneFlipNone }
    }
}

function Save-ResizedJpeg {
    param(
        [System.Drawing.Image]$SourceImage,
        [int]$TargetWidth,
        [int]$Quality,
        [string]$OutPath
    )

    $srcW = $SourceImage.Width
    $srcH = $SourceImage.Height

    if ($srcW -le $TargetWidth) {
        # 僅縮小不放大：來源已經比目標寬度小就直接用原尺寸
        $w = $srcW
        $h = $srcH
    } else {
        $w = $TargetWidth
        $h = [int][math]::Round($srcH * $TargetWidth / $srcW)
    }

    $bmp = New-Object System.Drawing.Bitmap $w, $h
    try {
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        try {
            $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
            $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
            $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
            $g.DrawImage($SourceImage, 0, 0, $w, $h)
        } finally {
            $g.Dispose()
        }

        $jpegCodec = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() |
            Where-Object { $_.MimeType -eq 'image/jpeg' }
        $encParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
        $encParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter(
            [System.Drawing.Imaging.Encoder]::Quality, [int64]$Quality
        )
        $bmp.Save($OutPath, $jpegCodec, $encParams)
    } finally {
        $bmp.Dispose()
    }

    return @{ w = $w; h = $h }
}

# ------------------------------------------------------------------ 影片

function Get-VideoInfo {
    param([string]$Path)
    $json = & $script:FFprobePath -v error -select_streams v:0 `
        -show_entries stream=width,height `
        -show_entries format=duration `
        -of json $Path
    if ($LASTEXITCODE -ne 0) { throw "ffprobe 讀取失敗：$Path" }
    $data = $json | ConvertFrom-Json
    return @{
        w        = [int]$data.streams[0].width
        h        = [int]$data.streams[0].height
        duration = [double]$data.format.duration
    }
}

function Save-CompressedVideo {
    param([string]$SourcePath, [string]$OutPath)
    # 長邊壓到 1280px（-2 確保輸出寬高是偶數，H.264 的要求）、
    # 幀率上限 30fps（手機常見 60fps 直接砍半，肉眼看不太出來但檔案
    # 小很多）、CRF 28（畫質與檔案大小的平衡點，網頁播放足夠）、
    # 音訊轉 AAC 128kbps、+faststart 讓瀏覽器邊下載邊播不用等整支載完。
    $vf = "scale='if(gt(iw,ih),min(1280,iw),-2)':'if(gt(iw,ih),-2,min(1280,ih))'"
    & $script:FFmpegPath -y -i $SourcePath -vf $vf -r 30 `
        -c:v libx264 -crf 28 -preset medium `
        -c:a aac -b:a 128k -movflags +faststart `
        -loglevel error $OutPath
    if ($LASTEXITCODE -ne 0) { throw "ffmpeg 壓縮影片失敗：$SourcePath" }
}

function Save-VideoPoster {
    param([string]$SourcePath, [string]$OutPath, [double]$Duration)
    # 擷取畫面當縮圖：抓第 1 秒（避開開頭常見的黑畫面或轉場），
    # 但影片比 1 秒還短的話就抓正中間。跟照片縮圖一樣壓到 600px 寬。
    $seekTime = [math]::Min(1, $Duration / 2)
    & $script:FFmpegPath -y -ss $seekTime -i $SourcePath -vframes 1 -update 1 `
        -vf "scale=600:-2" -loglevel error $OutPath
    if ($LASTEXITCODE -ne 0) { throw "擷取影片縮圖失敗：$SourcePath" }
}

# ---------------------------------------------------------------- 載入設定

$pointsPath = Join-Path $root 'data\points.js'
$photosPath = Join-Path $root 'data\photos.js'
$photosOutRoot = Join-Path $root 'photos'

Write-Host "讀取 $pointsPath ..." -ForegroundColor Cyan
$config = Read-DataFile $pointsPath
$points = $config.points
$srcRoot = Join-Path $root $config.photoSourceRoot

if (-not (Test-Path $srcRoot)) {
    throw "來源照片目錄不存在：$srcRoot"
}

# 孤兒偵測：來源目錄下有資料夾但沒有任何地點指向它
$mappedFolders = $points | Where-Object { $_.srcFolder } | ForEach-Object { $_.srcFolder }
$actualFolders = Get-ChildItem -Path $srcRoot -Directory | Where-Object { $_.Name -ne '_unsorted' }
$orphanFolders = $actualFolders | Where-Object { $mappedFolders -notcontains $_.Name }
foreach ($of in $orphanFolders) {
    Write-Warning "孤兒資料夾（沒有任何地點指向它，這裡的照片不會出現在網站上）：$($of.Name)"
}

# ---------------------------------------------------------------- 主流程

$photoData = [ordered]@{}
$stats = @{
    photosTotal    = 0
    videosTotal    = 0
    thumbsWritten  = 0
    largesWritten  = 0
    thumbsSkipped  = 0
    largesSkipped  = 0
    videosWritten  = 0
    videosSkipped  = 0
    filesRemoved   = 0
}
$oversizedVideos = @()   # 壓完還是超過安全門檻的影片，最後統一警告

foreach ($point in $points) {
    if ([string]::IsNullOrEmpty($point.srcFolder)) { continue }

    $srcDir = Join-Path $srcRoot $point.srcFolder
    if (-not (Test-Path $srcDir)) {
        Write-Warning "地點 '$($point.id)' 指向不存在的來源資料夾：$($point.srcFolder)"
        continue
    }

    $photoFiles = Get-ChildItem -Path $srcDir -File -Recurse -Include *.jpg, *.jpeg, *.JPG, *.JPEG |
        Sort-Object Name
    $videoFiles = Get-ChildItem -Path $srcDir -File -Recurse -Include *.mp4, *.MP4, *.mov, *.MOV |
        Sort-Object Name

    if ($photoFiles.Count -eq 0 -and $videoFiles.Count -eq 0) {
        Write-Warning "地點 '$($point.id)' 的來源資料夾沒有任何照片或影片：$($point.srcFolder)"
    }

    $thumbDir = Join-Path $photosOutRoot "$($point.id)\thumb"
    $largeDir = Join-Path $photosOutRoot "$($point.id)\large"
    $videoDir = Join-Path $photosOutRoot "$($point.id)\video"
    New-Item -ItemType Directory -Force -Path $thumbDir | Out-Null
    New-Item -ItemType Directory -Force -Path $largeDir | Out-Null
    if ($videoFiles.Count -gt 0) { New-Item -ItemType Directory -Force -Path $videoDir | Out-Null }

    $entries = @()
    $expectedThumbNames = @()   # 縮圖／海報幀共用 thumbDir
    $expectedLargeNames = @()
    $expectedVideoNames = @()

    # -- 照片（順序在前，跟原本的行為一致）--
    foreach ($file in $photoFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $outName = "$baseName.jpg"
        $expectedThumbNames += $outName
        $expectedLargeNames += $outName

        $thumbPath = Join-Path $thumbDir $outName
        $largePath = Join-Path $largeDir $outName

        $needThumb = (-not (Test-Path $thumbPath)) -or ((Get-Item $thumbPath).LastWriteTimeUtc -lt $file.LastWriteTimeUtc)
        $needLarge = (-not (Test-Path $largePath)) -or ((Get-Item $largePath).LastWriteTimeUtc -lt $file.LastWriteTimeUtc)

        # 讀來源檔一定要做（無論是否需要重新壓縮）：修正 EXIF 方向後的
        # 尺寸才是網頁應該知道的「原始尺寸」，直拍照片的寬高會因此對調。
        $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        try {
            $orientation = 1
            $prop = $img.PropertyItems | Where-Object { $_.Id -eq 274 }
            if ($prop) { $orientation = [System.BitConverter]::ToUInt16($prop.Value, 0) }
            if ($orientation -ne 1) {
                $img.RotateFlip((Get-RotateFlipForOrientation $orientation))
            }

            $correctedW = $img.Width
            $correctedH = $img.Height

            if ($needThumb) {
                Save-ResizedJpeg -SourceImage $img -TargetWidth 600 -Quality 75 -OutPath $thumbPath | Out-Null
                $stats.thumbsWritten++
            } else {
                $stats.thumbsSkipped++
            }

            if ($needLarge) {
                Save-ResizedJpeg -SourceImage $img -TargetWidth 2000 -Quality 82 -OutPath $largePath | Out-Null
                $stats.largesWritten++
            } else {
                $stats.largesSkipped++
            }
        } finally {
            $img.Dispose()
            $ms.Dispose()
        }

        $entries += [ordered]@{
            type  = "photo"
            thumb = "photos/$($point.id)/thumb/$outName"
            large = "photos/$($point.id)/large/$outName"
            w     = $correctedW
            h     = $correctedH
        }

        $stats.photosTotal++
    }

    # -- 影片（接在照片後面：拍攝時間資訊不可靠，不嘗試按時間交錯排序）--
    foreach ($file in $videoFiles) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $posterName = "$baseName.jpg"
        $videoOutName = "$baseName.mp4"
        $expectedThumbNames += $posterName
        $expectedVideoNames += $videoOutName

        $posterPath = Join-Path $thumbDir $posterName
        $videoOutPath = Join-Path $videoDir $videoOutName

        $needPoster = (-not (Test-Path $posterPath)) -or ((Get-Item $posterPath).LastWriteTimeUtc -lt $file.LastWriteTimeUtc)
        $needVideo = (-not (Test-Path $videoOutPath)) -or ((Get-Item $videoOutPath).LastWriteTimeUtc -lt $file.LastWriteTimeUtc)

        $info = Get-VideoInfo -Path $file.FullName

        if ($needVideo) {
            Save-CompressedVideo -SourcePath $file.FullName -OutPath $videoOutPath
            $stats.videosWritten++
        } else {
            $stats.videosSkipped++
        }

        if ($needPoster) {
            Save-VideoPoster -SourcePath $file.FullName -OutPath $posterPath -Duration $info.duration
            $stats.thumbsWritten++
        } else {
            $stats.thumbsSkipped++
        }

        $outSizeMB = [math]::Round((Get-Item $videoOutPath).Length / 1MB, 1)
        if ($outSizeMB -gt 20) {
            $oversizedVideos += "$($point.id)/$videoOutName（${outSizeMB}MB）"
        }

        $entries += [ordered]@{
            type     = "video"
            thumb    = "photos/$($point.id)/thumb/$posterName"
            video    = "photos/$($point.id)/video/$videoOutName"
            w        = $info.w
            h        = $info.h
            duration = [math]::Round($info.duration, 1)
        }

        $stats.videosTotal++
    }

    # 清掉來源已經不存在的舊輸出（例如使用者把某個檔案從資料夾移走）
    foreach ($existing in (Get-ChildItem -Path $thumbDir -File -ErrorAction SilentlyContinue)) {
        if ($expectedThumbNames -notcontains $existing.Name) {
            Remove-Item $existing.FullName -Force
            $stats.filesRemoved++
        }
    }
    foreach ($existing in (Get-ChildItem -Path $largeDir -File -ErrorAction SilentlyContinue)) {
        if ($expectedLargeNames -notcontains $existing.Name) {
            Remove-Item $existing.FullName -Force
            $stats.filesRemoved++
        }
    }
    if (Test-Path $videoDir) {
        foreach ($existing in (Get-ChildItem -Path $videoDir -File -ErrorAction SilentlyContinue)) {
            if ($expectedVideoNames -notcontains $existing.Name) {
                Remove-Item $existing.FullName -Force
                $stats.filesRemoved++
            }
        }
    }

    $photoData[$point.id] = $entries
    $videoNote = if ($videoFiles.Count -gt 0) { "（含 $($videoFiles.Count) 支影片）" } else { "" }
    Write-Host ("  {0,-24} {1,3} 項 {2}" -f $point.name, $entries.Count, $videoNote)
}

# ---------------------------------------------------------------- 寫出 photos.js

function ConvertTo-JsBlock {
    param($PhotoData)
    $pointBlocks = foreach ($key in $PhotoData.Keys) {
        $entryLines = foreach ($e in $PhotoData[$key]) {
            if ($e.type -eq "video") {
                "    { `"type`": `"video`", `"thumb`": `"$($e.thumb)`", `"video`": `"$($e.video)`", `"w`": $($e.w), `"h`": $($e.h), `"duration`": $($e.duration) }"
            } else {
                "    { `"type`": `"photo`", `"thumb`": `"$($e.thumb)`", `"large`": `"$($e.large)`", `"w`": $($e.w), `"h`": $($e.h) }"
            }
        }
        $entriesJoined = $entryLines -join ",`n"
        "  `"$key`": [`n$entriesJoined`n  ]"
    }
    return ($pointBlocks -join ",`n")
}

$body = ConvertTo-JsBlock -PhotoData $photoData

$output = @"
// 照片／影片清單 —— 由 scripts\build-photos.ps1 自動產生，請勿手動編輯
//
// 產生時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm')
// 以地點 id 為鍵。每筆有 type: "photo" 或 "video"。
// photo：thumb（600px 縮圖）、large（2000px 大圖）、w/h 是修正 EXIF
//        方向後的原始照片尺寸，供版面預留用。
// video：thumb（600px 海報縮圖）、video（壓縮後的 mp4）、w/h/duration
//        是壓縮後影片的尺寸與秒數。

window.TRIP_PHOTOS = {
$body
};
"@

[System.IO.File]::WriteAllText($photosPath, $output, [System.Text.UTF8Encoding]::new($true))

# ---------------------------------------------------------------- 總結

$totalBytes = (Get-ChildItem -Path $photosOutRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalMB = [math]::Round($totalBytes / 1MB, 1)

Write-Host ""
Write-Host "完成：$($stats.photosTotal) 張照片、$($stats.videosTotal) 支影片" -ForegroundColor Green
Write-Host "  縮圖／海報：新產生 $($stats.thumbsWritten)，略過（已是最新）$($stats.thumbsSkipped)"
Write-Host "  大圖：新產生 $($stats.largesWritten)，略過（已是最新）$($stats.largesSkipped)"
if ($stats.videosTotal -gt 0) {
    Write-Host "  影片：新壓縮 $($stats.videosWritten)，略過（已是最新）$($stats.videosSkipped)"
}
if ($stats.filesRemoved -gt 0) {
    Write-Host "  清除了 $($stats.filesRemoved) 個孤立輸出檔（來源已不存在）"
}
Write-Host "  輸出總大小：${totalMB}MB"

if ($oversizedVideos.Count -gt 0) {
    Write-Host ""
    Write-Warning "以下影片壓縮後仍超過 20MB 安全門檻（Cloudflare Pages 單檔上限 25MB）："
    foreach ($v in $oversizedVideos) { Write-Warning "  $v" }
}

Write-Host ""
Write-Host "已寫入 $photosPath" -ForegroundColor Green

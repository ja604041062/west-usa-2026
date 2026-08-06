# 照片壓縮管線
#
# 讀取 data/points.js 裡每個地點的 srcFolder，把使用者分類好的原始照片
# 轉成兩種尺寸：縮圖（600px 寬，面板照片牆用）與大圖（2000px 寬，燈箱用），
# 並產生 data/photos.js 供前端讀取。
#
# 只用 Windows 內建的 .NET System.Drawing 完成壓縮，不需要安裝任何
# 額外的執行環境（不需要 node、npm、Python）。
#
# 可重複執行任意多次：已經是最新的縮圖/大圖不會重新壓縮，只有新增或
# 修改過的來源照片才會被處理。使用者之後補照片，把檔案拖進對應資料夾
# 再重跑這支腳本即可。
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\build-photos.ps1

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$root = Split-Path -Parent $PSScriptRoot

. (Join-Path $PSScriptRoot 'lib\DataFile.ps1')

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
    thumbsWritten  = 0
    largesWritten  = 0
    thumbsSkipped  = 0
    largesSkipped  = 0
    filesRemoved   = 0
}

foreach ($point in $points) {
    if ([string]::IsNullOrEmpty($point.srcFolder)) { continue }

    $srcDir = Join-Path $srcRoot $point.srcFolder
    if (-not (Test-Path $srcDir)) {
        Write-Warning "地點 '$($point.id)' 指向不存在的來源資料夾：$($point.srcFolder)"
        continue
    }

    $files = Get-ChildItem -Path $srcDir -File -Recurse -Include *.jpg, *.jpeg, *.JPG, *.JPEG |
        Sort-Object Name

    if ($files.Count -eq 0) {
        Write-Warning "地點 '$($point.id)' 的來源資料夾沒有任何照片：$($point.srcFolder)"
    }

    $thumbDir = Join-Path $photosOutRoot "$($point.id)\thumb"
    $largeDir = Join-Path $photosOutRoot "$($point.id)\large"
    New-Item -ItemType Directory -Force -Path $thumbDir | Out-Null
    New-Item -ItemType Directory -Force -Path $largeDir | Out-Null

    $entries = @()
    $expectedNames = @()

    foreach ($file in $files) {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $outName = "$baseName.jpg"
        $expectedNames += $outName

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
            thumb = "photos/$($point.id)/thumb/$outName"
            large = "photos/$($point.id)/large/$outName"
            w     = $correctedW
            h     = $correctedH
        }

        $stats.photosTotal++
    }

    # 清掉來源已經不存在的舊輸出（例如使用者把某張照片從資料夾移走）
    foreach ($existing in (Get-ChildItem -Path $thumbDir, $largeDir -File -ErrorAction SilentlyContinue)) {
        if ($expectedNames -notcontains $existing.Name) {
            Remove-Item $existing.FullName -Force
            $stats.filesRemoved++
        }
    }

    $photoData[$point.id] = $entries
    Write-Host ("  {0,-24} {1,3} 張" -f $point.name, $entries.Count)
}

# ---------------------------------------------------------------- 寫出 photos.js

function ConvertTo-JsBlock {
    param($PhotoData)
    $pointBlocks = foreach ($key in $PhotoData.Keys) {
        $entryLines = foreach ($e in $PhotoData[$key]) {
            "    { `"thumb`": `"$($e.thumb)`", `"large`": `"$($e.large)`", `"w`": $($e.w), `"h`": $($e.h) }"
        }
        $entriesJoined = $entryLines -join ",`n"
        "  `"$key`": [`n$entriesJoined`n  ]"
    }
    return ($pointBlocks -join ",`n")
}

$body = ConvertTo-JsBlock -PhotoData $photoData

$output = @"
// 照片清單 —— 由 scripts\build-photos.ps1 自動產生，請勿手動編輯
//
// 產生時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm')
// 以地點 id 為鍵；w/h 是修正 EXIF 方向後的原始照片尺寸，供版面預留用。

window.TRIP_PHOTOS = {
$body
};
"@

[System.IO.File]::WriteAllText($photosPath, $output, [System.Text.UTF8Encoding]::new($true))

# ---------------------------------------------------------------- 總結

$totalBytes = (Get-ChildItem -Path $photosOutRoot -Recurse -File | Measure-Object -Property Length -Sum).Sum
$totalMB = [math]::Round($totalBytes / 1MB, 1)

Write-Host ""
Write-Host "完成：$($stats.photosTotal) 張照片" -ForegroundColor Green
Write-Host "  縮圖：新產生 $($stats.thumbsWritten)，略過（已是最新）$($stats.thumbsSkipped)"
Write-Host "  大圖：新產生 $($stats.largesWritten)，略過（已是最新）$($stats.largesSkipped)"
if ($stats.filesRemoved -gt 0) {
    Write-Host "  清除了 $($stats.filesRemoved) 個孤立輸出檔（來源已不存在）"
}
Write-Host "  輸出總大小：${totalMB}MB"
Write-Host ""
Write-Host "已寫入 $photosPath" -ForegroundColor Green

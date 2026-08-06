# 驗證腳本 —— 在議定的接縫上驗證建置產物
#
# 接縫：建置腳本的輸入（來源照片目錄樹 + points.json）
#       與輸出（photos.json + route.json + 壓縮後圖片檔）之間。
#
# 只驗證外部可觀察的行為，不驗證腳本內部如何運作。
# 用法：powershell -ExecutionPolicy Bypass -File scripts\verify.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$script:pass = 0
$script:fail = 0
$script:skip = 0

function Test-That {
    param([string]$Name, [scriptblock]$Body)
    try {
        $result = & $Body
        if ($result -eq 'skip') {
            Write-Host "  SKIP  $Name" -ForegroundColor DarkGray
            $script:skip++
        } else {
            Write-Host "  PASS  $Name" -ForegroundColor Green
            $script:pass++
        }
    } catch {
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        Write-Host "        $($_.Exception.Message)" -ForegroundColor DarkRed
        $script:fail++
    }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

# 資料檔是 JS 而非 JSON，因為 fetch() 在 file:// 下會被 CORS 擋掉，
# 而「雙擊 index.html 就能看」是硬需求。Read-DataFile 把 JS 外殼剝掉
# 再當 JSON 解析，build-photos.ps1 與 build-route.ps1 也共用同一份。
. (Join-Path $PSScriptRoot 'lib\DataFile.ps1')

# ---------------------------------------------------------------- 載入設定

$pointsPath = Join-Path $root 'data\points.js'
$photosPath = Join-Path $root 'data\photos.js'
$routePath  = Join-Path $root 'data\route.js'

$config = Read-DataFile $pointsPath
$points = $config.points
$srcRoot = Join-Path $root $config.photoSourceRoot

Write-Host ""
Write-Host "=== 地點資料 (points.js) ===" -ForegroundColor Cyan

Test-That "points.js 可解析且含地點" {
    Assert-True ($points.Count -gt 0) "points 陣列為空"
}

Test-That "每個地點都具備必要欄位" {
    foreach ($p in $points) {
        foreach ($field in @('id','name','coords','date','description','showMarker','inRoute')) {
            Assert-True ($null -ne $p.PSObject.Properties[$field]) "地點 '$($p.id)' 缺少欄位 $field"
        }
        Assert-True ($p.coords.Count -eq 2) "地點 '$($p.id)' 的 coords 不是 [lat, lng]"
    }
}

Test-That "地點 id 不重複" {
    $ids = $points | ForEach-Object { $_.id }
    $dupes = $ids | Group-Object | Where-Object { $_.Count -gt 1 }
    Assert-True ($dupes.Count -eq 0) "重複的 id：$($dupes.Name -join ', ')"
}

Test-That "所有座標落在美西合理範圍內" {
    foreach ($p in $points) {
        $lat = $p.coords[0]; $lng = $p.coords[1]
        Assert-True ($lat -gt 32 -and $lat -lt 40)     "地點 '$($p.id)' 緯度 $lat 超出美西範圍"
        Assert-True ($lng -gt -125 -and $lng -lt -110) "地點 '$($p.id)' 經度 $lng 超出美西範圍"
    }
}

Test-That "description 現階段全部留空（純照片牆）" {
    foreach ($p in $points) {
        Assert-True ([string]::IsNullOrEmpty($p.description)) "地點 '$($p.id)' 的 description 非空"
    }
}

Test-That "對應完整性：每個 srcFolder 都確實存在" {
    foreach ($p in $points) {
        if ([string]::IsNullOrEmpty($p.srcFolder)) { continue }
        $dir = Join-Path $srcRoot $p.srcFolder
        Assert-True (Test-Path $dir) "地點 '$($p.id)' 指向不存在的資料夾：$($p.srcFolder)"
    }
}

Test-That "孤兒偵測：來源目錄下沒有未被對應的資料夾" {
    if (-not (Test-Path $srcRoot)) { throw "來源目錄不存在：$srcRoot" }
    $mapped = $points | Where-Object { $_.srcFolder } | ForEach-Object { $_.srcFolder }
    $actual = Get-ChildItem -Path $srcRoot -Directory | Where-Object { $_.Name -ne '_unsorted' }
    $orphans = $actual | Where-Object { $mapped -notcontains $_.Name }
    Assert-True ($orphans.Count -eq 0) "孤兒資料夾（照片不會出現在網站上）：$($orphans.Name -join ', ')"
}

Test-That "有標記的地點都有照片來源" {
    foreach ($p in $points) {
        if (-not $p.showMarker) { continue }
        Assert-True (-not [string]::IsNullOrEmpty($p.srcFolder)) "地點 '$($p.id)' 有標記卻沒有 srcFolder"
    }
}

# ---------------------------------------------------------------- 照片產物

Write-Host ""
Write-Host "=== 照片管線 (photos.js + 壓縮輸出) ===" -ForegroundColor Cyan

$photosExist = Test-Path $photosPath

Test-That "photos.js 存在" {
    Assert-True $photosExist "尚未產生 photos.js（請先執行 scripts\build-photos.ps1）"
}

if ($photosExist) {
    $photos = Read-DataFile $photosPath

    Test-That "完整性：每個地點的張數與來源資料夾相符" {
        foreach ($p in $points) {
            if ([string]::IsNullOrEmpty($p.srcFolder)) { continue }
            $srcCount = (Get-ChildItem -Path (Join-Path $srcRoot $p.srcFolder) -File -Include *.jpg,*.jpeg,*.JPG,*.JPEG -Recurse).Count
            $outCount = 0
            if ($photos.PSObject.Properties[$p.id]) { $outCount = $photos.($p.id).Count }
            Assert-True ($srcCount -eq $outCount) "地點 '$($p.id)' 來源 $srcCount 張，輸出 $outCount 張"
        }
    }

    Test-That "總張數非零，且與所有地點加總一致" {
        # 照片數量會持續增加（撰寫這支腳本時是 108 張，之後只會更多），
        # 不寫死確切數字 —— 上面「完整性」那項測試已經逐地點比對過
        # 來源與輸出是否相符，這裡只做總數健全性檢查，並把目前的
        # 實際張數印出來供參考。
        $total = 0
        foreach ($prop in $photos.PSObject.Properties) { $total += $prop.Value.Count }
        Write-Host "        （目前共 $total 張照片）" -ForegroundColor DarkGray
        Assert-True ($total -gt 0) "總張數為 0，照片管線可能沒有正確執行"
    }

    Test-That "產物存在性：每個引用的檔案都在磁碟上" {
        foreach ($prop in $photos.PSObject.Properties) {
            foreach ($ph in $prop.Value) {
                Assert-True (Test-Path (Join-Path $root $ph.thumb)) "縮圖不存在：$($ph.thumb)"
                Assert-True (Test-Path (Join-Path $root $ph.large)) "大圖不存在：$($ph.large)"
            }
        }
    }

    Test-That "尺寸正確性：縮圖 600px、大圖 2000px，長寬比一致" {
        Add-Type -AssemblyName System.Drawing
        $checked = 0
        foreach ($prop in $photos.PSObject.Properties) {
            foreach ($ph in $prop.Value) {
                if ($checked -ge 12) { break }
                $t = [System.Drawing.Image]::FromFile((Join-Path $root $ph.thumb))
                $l = [System.Drawing.Image]::FromFile((Join-Path $root $ph.large))
                try {
                    Assert-True ($t.Width -eq 600)  "縮圖寬度為 $($t.Width)，預期 600：$($ph.thumb)"
                    Assert-True ($l.Width -eq 2000) "大圖寬度為 $($l.Width)，預期 2000：$($ph.large)"
                    $tr = [math]::Round($t.Width / $t.Height, 2)
                    $lr = [math]::Round($l.Width / $l.Height, 2)
                    Assert-True ([math]::Abs($tr - $lr) -lt 0.02) "縮圖與大圖長寬比不一致：$($ph.thumb)"
                } finally { $t.Dispose(); $l.Dispose() }
                $checked++
            }
        }
        Assert-True ($checked -gt 0) "沒有可檢查的圖片"
    }

    Test-That "大小預算：輸出低於 60MB" {
        $photoDir = Join-Path $root 'photos'
        $bytes = (Get-ChildItem -Path $photoDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
        $mb = [math]::Round($bytes / 1MB, 1)
        Write-Host "        （實際 ${mb}MB）" -ForegroundColor DarkGray
        Assert-True ($mb -lt 60) "輸出為 ${mb}MB，超過 60MB 預算"
    }

    Test-That "每張照片都帶有原始尺寸（供版面預留用）" {
        foreach ($prop in $photos.PSObject.Properties) {
            foreach ($ph in $prop.Value) {
                Assert-True ($ph.w -gt 0 -and $ph.h -gt 0) "照片缺少尺寸資訊：$($ph.thumb)"
            }
        }
    }
}

# ---------------------------------------------------------------- 路線產物

Write-Host ""
Write-Host "=== 路線 (route.js) ===" -ForegroundColor Cyan

$routeExist = Test-Path $routePath

Test-That "route.js 存在" {
    Assert-True $routeExist "尚未產生 route.js（請先執行 scripts\build-route.ps1）"
}

if ($routeExist) {
    $route = Read-DataFile $routePath

    Test-That "路線座標序列非空" {
        Assert-True ($route.coordinates.Count -gt 100) "路線只有 $($route.coordinates.Count) 個座標，過少"
    }

    Test-That "所有路線座標落在美西合理範圍內" {
        foreach ($c in $route.coordinates) {
            Assert-True ($c[0] -gt 32 -and $c[0] -lt 40)     "路線緯度 $($c[0]) 超出範圍"
            Assert-True ($c[1] -gt -125 -and $c[1] -lt -110) "路線經度 $($c[1]) 超出範圍"
        }
    }

    function Get-MinDistanceKm {
        param($Coords, $Lat, $Lng)
        $min = [double]::MaxValue
        foreach ($c in $Coords) {
            $dLat = ($c[0] - $Lat) * 111.0
            $dLng = ($c[1] - $Lng) * 111.0 * [math]::Cos($Lat * [math]::PI / 180)
            $d = [math]::Sqrt($dLat * $dLat + $dLng * $dLng)
            if ($d -lt $min) { $min = $d }
        }
        return $min
    }

    Test-That "起點鄰近洛杉磯" {
        $la = $points | Where-Object { $_.id -eq 'los-angeles' }
        $first = $route.coordinates[0]
        $d = Get-MinDistanceKm -Coords @(,$first) -Lat $la.coords[0] -Lng $la.coords[1]
        Assert-True ($d -lt 20) "起點距洛杉磯 $([math]::Round($d,1)) km"
    }

    Test-That "終點鄰近舊金山" {
        $sf = $points | Where-Object { $_.id -eq 'san-francisco' }
        $last = $route.coordinates[$route.coordinates.Count - 1]
        $d = Get-MinDistanceKm -Coords @(,$last) -Lat $sf.coords[0] -Lng $sf.coords[1]
        Assert-True ($d -lt 20) "終點距舊金山 $([math]::Round($d,1)) km"
    }

    Test-That "路線經過每一個 inRoute 地點附近" {
        foreach ($p in $points) {
            if (-not $p.inRoute) { continue }
            $d = Get-MinDistanceKm -Coords $route.coordinates -Lat $p.coords[0] -Lng $p.coords[1]
            Assert-True ($d -lt 25) "路線距地點 '$($p.id)' 最近 $([math]::Round($d,1)) km，未經過"
        }
    }

    Test-That "路線排除性：不得經過 inRoute=false 的地點（自駕主軸守門員）" {
        foreach ($p in $points) {
            if ($p.inRoute) { continue }
            $d = Get-MinDistanceKm -Coords $route.coordinates -Lat $p.coords[0] -Lng $p.coords[1]
            Assert-True ($d -gt 25) "路線延伸到了不該去的 '$($p.id)'，最近距離僅 $([math]::Round($d,1)) km"
        }
    }

    Test-That "路線總里程接近實際的 1,704 英里" {
        $miles = [math]::Round($route.distanceMeters / 1609.34)
        Write-Host "        （實際 $miles 英里，Google Maps 為 1704）" -ForegroundColor DarkGray
        Assert-True ($miles -gt 1200 -and $miles -lt 2400) "總里程 $miles 英里，與預期落差過大"
    }
}

# ---------------------------------------------------------------- 靜態資產

Write-Host ""
Write-Host "=== 網站資產 ===" -ForegroundColor Cyan

Test-That "Leaflet 已下載進版控庫（不依賴 CDN）" {
    Assert-True (Test-Path (Join-Path $root 'assets\vendor\leaflet\leaflet.js'))  "缺少 leaflet.js"
    Assert-True (Test-Path (Join-Path $root 'assets\vendor\leaflet\leaflet.css')) "缺少 leaflet.css"
}

Test-That "頁面不引用任何外部 script 或 stylesheet" {
    $html = Get-Content -Path (Join-Path $root 'index.html') -Raw -Encoding UTF8
    $bad = [regex]::Matches($html, '(?i)<(script|link)[^>]*(src|href)\s*=\s*"https?://[^"]*"')
    Assert-True ($bad.Count -eq 0) "頁面引用了外部資源：$($bad.Value -join '; ')"
}

Test-That "robots.txt 存在且阻擋索引" {
    $robotsPath = Join-Path $root 'robots.txt'
    Assert-True (Test-Path $robotsPath) "缺少 robots.txt"
    $robots = Get-Content -Path $robotsPath -Raw
    Assert-True ($robots -match 'Disallow:\s*/') "robots.txt 未阻擋索引"
}

Test-That "頁面含 noindex meta 標籤" {
    $html = Get-Content -Path (Join-Path $root 'index.html') -Raw -Encoding UTF8
    Assert-True ($html -match '(?i)<meta[^>]+name\s*=\s*"robots"[^>]+noindex') "缺少 noindex meta 標籤"
}

Test-That "版控忽略設定已排除原始照片與 _unsorted" {
    $gi = Get-Content -Path (Join-Path $root '.gitignore') -Raw
    Assert-True ($gi -match '_unsorted') ".gitignore 未排除 _unsorted"
    Assert-True ($gi -match 'Soap') ".gitignore 未排除原始照片目錄"
}

# ---------------------------------------------------------------- 總結

Write-Host ""
Write-Host ("=" * 50)
Write-Host "通過 $script:pass  失敗 $script:fail  略過 $script:skip"
Write-Host ("=" * 50)
Write-Host ""

if ($script:fail -gt 0) { exit 1 } else { exit 0 }

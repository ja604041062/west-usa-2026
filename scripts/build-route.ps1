# 路線產生腳本 —— 只在建置時執行一次
#
# 讀取 data/points.js 中所有 inRoute: true 的地點（依陣列順序，含 Baker、
# Bealville 兩個不顯示標記的途經點），依序送給 OSRM 公開路徑規劃服務，
# 取回沿真實公路的行車路線幾何，寫成 data/route.js。
#
# inRoute: false 的地點（Napa Valley）完全不參與這次計算 —— 這是
# 「自駕為主軸」這項設計原則在資料層的體現。
#
# 網站執行期間不會呼叫任何外部服務；這支腳本的產出是唯一的路線來源。
# 途經點清單改變時，重跑這支腳本即可重新產生路線，不需要修改任何程式碼。
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\build-route.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Read-DataFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "檔案不存在：$Path" }
    $text = Get-Content -Path $Path -Raw -Encoding UTF8
    $lines = $text -split "`r?`n" | Where-Object { $_.TrimStart() -notmatch '^//' }
    $text = $lines -join "`n"
    $text = $text -replace '^\s*window\.[A-Z_]+\s*=\s*', ''
    $text = $text.Trim().TrimEnd(';')
    return ($text | ConvertFrom-Json)
}

$pointsPath = Join-Path $root 'data\points.js'
$routePath  = Join-Path $root 'data\route.js'

Write-Host "讀取 $pointsPath ..." -ForegroundColor Cyan
$config = Read-DataFile $pointsPath
$allPoints = $config.points

$routePoints = $allPoints | Where-Object { $_.inRoute }

if ($routePoints.Count -lt 2) {
    throw "inRoute 的地點少於 2 個，無法計算路線"
}

Write-Host "納入路線的地點（依序，共 $($routePoints.Count) 個）：" -ForegroundColor Cyan
foreach ($p in $routePoints) {
    $marker = if ($p.showMarker) { "顯示標記" } else { "僅校正路線" }
    Write-Host "  - $($p.name)  [$marker]"
}

$excluded = $allPoints | Where-Object { -not $_.inRoute }
if ($excluded.Count -gt 0) {
    Write-Host ""
    Write-Host "不納入路線（藍線不會經過）：" -ForegroundColor DarkYellow
    foreach ($p in $excluded) { Write-Host "  - $($p.name)" }
}

# OSRM 座標順序是 lon,lat（跟 points.js 的 [lat, lng] 相反，別搞混）
$coordPairs = $routePoints | ForEach-Object { "$($_.coords[1]),$($_.coords[0])" }
$coordString = $coordPairs -join ';'

# overview=simplified：OSRM 用 Douglas-Peucker 演算法簡化幾何，
# 是專為地圖顯示設計的模式（相對於 full，會回傳每一段路的完整節點，
# 對這趟 1,700 英里的路線會產生 5 萬個以上的座標點，檔案接近 1MB、
# 會拖慢 Leaflet 的折線渲染，遠超過網站需要的視覺精細度）
$url = "https://router.project-osrm.org/route/v1/driving/$coordString`?overview=simplified&geometries=geojson"

Write-Host ""
Write-Host "呼叫 OSRM..." -ForegroundColor Cyan

$response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 30

if ($response.code -ne 'Ok') {
    throw "OSRM 回傳錯誤：$($response.code) $($response.message)"
}

$route = $response.routes[0]
$geoCoords = $route.geometry.coordinates   # [[lon, lat], ...]

# 直接產生輸出用的字串，不經過中介的巢狀陣列 ——
# PowerShell 的管線會把 ForEach-Object { @(a,b) } 這種巢狀陣列自動攤平，
# 導致每個座標對被拆散成兩個獨立元素，寫出來的檔案座標會全部錯位。
$coordLines = $geoCoords | ForEach-Object {
    $lat = [math]::Round($_[1], 6)
    $lon = [math]::Round($_[0], 6)
    "    [$lat,$lon]"
}

$distanceMiles = [math]::Round($route.distance / 1609.34, 1)
$durationHours = [math]::Round($route.duration / 3600, 1)

Write-Host "完成：$($geoCoords.Count) 個座標點，$distanceMiles 英里，約 $durationHours 小時" -ForegroundColor Green

# ------------------------------------------------------------ 寫出 route.js

$coordBlock = $coordLines -join ",`n"

$output = @"
// 自駕路線幾何 —— 由 scripts\build-route.ps1 自動產生，請勿手動編輯座標陣列
// （若需要微調個別路段，直接改動下面的座標沒問題，只是下次重跑腳本會覆蓋掉）
//
// 產生時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm')
// 座標來源：OSRM 公開路徑規劃服務（僅建置時呼叫一次，網站執行期間不依賴此服務）
// 途經點：$($routePoints.name -join ' → ')

window.TRIP_ROUTE = {
  "distanceMeters": $($route.distance),
  "distanceMiles": $distanceMiles,
  "durationSeconds": $($route.duration),
  "coordinates": [
$coordBlock
  ]
};
"@

[System.IO.File]::WriteAllText($routePath, $output, [System.Text.UTF8Encoding]::new($true))

Write-Host ""
Write-Host "已寫入 $routePath" -ForegroundColor Green
Write-Host ""
Write-Host "Google Maps 截圖顯示的路線為 1,704 英里、29 小時。" -ForegroundColor DarkGray
Write-Host "本次算出：$distanceMiles 英里、約 $durationHours 小時。" -ForegroundColor DarkGray

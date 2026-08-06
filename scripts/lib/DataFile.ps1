# 共用函式：讀取 window.X = {...}; 格式的資料檔並還原成 PowerShell 物件
#
# 資料檔（points.js / photos.js / route.js）是 .js 而非 .json，因為
# fetch() 在 file:// 下會被 CORS 擋掉，而「雙擊 index.html 就能看」是
# 硬需求。build-photos.ps1、build-route.ps1、verify.ps1 都需要讀這些
# 檔案，所以抽成這支共用檔案，用 dot-source 引入，不要各自複製一份。
#
# 用法：. (Join-Path $PSScriptRoot 'lib\DataFile.ps1')

function Read-DataFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { throw "檔案不存在：$(Split-Path -Leaf $Path)" }
    $text = Get-Content -Path $Path -Raw -Encoding UTF8

    # 去掉整行的 // 註解（不碰行內出現的 //，避免誤傷字串內容）
    $lines = $text -split "`r?`n" | Where-Object { $_.TrimStart() -notmatch '^//' }
    $text = $lines -join "`n"

    # 剝掉 `window.XXX = ` 前綴與結尾的分號
    $text = $text -replace '^\s*window\.[A-Z_]+\s*=\s*', ''
    $text = $text.Trim().TrimEnd(';')

    return ($text | ConvertFrom-Json)
}

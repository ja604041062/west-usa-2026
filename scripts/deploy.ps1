# 部署腳本 —— 把網站更新到 https://west-usa-2026.pages.dev/
#
# 前提（只需要做一次，這台電腦上已經做過了）：
#   1. 安裝 Node.js（scripts\deploy.ps1 透過 npx 執行 Cloudflare 的 wrangler 工具）
#   2. 執行過一次 `npx wrangler login`，用瀏覽器登入 Cloudflare 帳號
#      （登入資訊快取在這台電腦上，之後執行這支腳本不需要重新登入）
#
# 這支腳本會：
#   1. 先跑 verify.ps1 —— 資料或照片有問題就直接停止，不會把壞掉的網站送上線
#   2. 把公開網站需要的檔案（index.html、favicon.svg、assets/、data/、
#      photos/、robots.txt）複製到一個乾淨的暫存資料夾 —— 不會把
#      .git、SPEC.md、STATUS.md、.scratch 這些內部文件傳上去
#   3. 用 wrangler 把那個資料夾整包上傳到 Cloudflare Pages
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Write-Host "=== 第一步：部署前檢查 ===" -ForegroundColor Cyan
& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "驗證沒有全部通過，已停止部署。" -ForegroundColor Red
    Write-Host "先解決上面標示 FAIL 的項目，再重新執行這支腳本。" -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "=== 第二步：打包公開網站檔案 ===" -ForegroundColor Cyan

$deployDir = Join-Path $env:TEMP 'west-usa-2026-deploy'
if (Test-Path $deployDir) { Remove-Item $deployDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $deployDir | Out-Null

Copy-Item (Join-Path $root 'index.html')    $deployDir
Copy-Item (Join-Path $root 'favicon.svg')   $deployDir
Copy-Item (Join-Path $root 'robots.txt')    $deployDir
Copy-Item (Join-Path $root 'assets')      $deployDir -Recurse
Copy-Item (Join-Path $root 'data')        $deployDir -Recurse
Copy-Item (Join-Path $root 'photos')      $deployDir -Recurse

$fileCount = (Get-ChildItem -Path $deployDir -Recurse -File).Count
$sizeMB = [math]::Round((Get-ChildItem -Path $deployDir -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 1)
Write-Host "已打包 $fileCount 個檔案，共 ${sizeMB}MB"

Write-Host ""
Write-Host "=== 第三步：上傳到 Cloudflare Pages ===" -ForegroundColor Cyan

$env:Path = "C:\Program Files\nodejs;" + $env:Path
npx --yes wrangler pages deploy $deployDir --project-name=west-usa-2026 --commit-dirty=true

Remove-Item $deployDir -Recurse -Force

Write-Host ""
Write-Host "完成。網站網址：https://west-usa-2026.pages.dev/" -ForegroundColor Green

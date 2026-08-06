# 本機預覽伺服器
#
# 網站本身不需要伺服器（雙擊 index.html 就能看），這支腳本只是為了開發時
# 方便驗收互動行為。正式部署在 GitHub Pages 上，也不需要它。
#
# 用法：powershell -ExecutionPolicy Bypass -File scripts\serve.ps1
# 然後開啟 http://localhost:8765/

param([int]$Port = 8765)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$mime = @{
    '.html' = 'text/html; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.js'   = 'application/javascript; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'
    '.jpg'  = 'image/jpeg'
    '.jpeg' = 'image/jpeg'
    '.png'  = 'image/png'
    '.svg'  = 'image/svg+xml'
    '.ico'  = 'image/x-icon'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()

Write-Host "預覽伺服器啟動：http://localhost:$Port/" -ForegroundColor Green
Write-Host "根目錄：$root"
Write-Host "按 Ctrl+C 停止"

try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $req = $context.Request
        $res = $context.Response

        try {
            $rel = [System.Uri]::UnescapeDataString($req.Url.AbsolutePath).TrimStart('/')
            if ([string]::IsNullOrEmpty($rel)) { $rel = 'index.html' }

            $path = Join-Path $root $rel

            # 不讓請求跳出專案根目錄
            $full = [System.IO.Path]::GetFullPath($path)
            if (-not $full.StartsWith([System.IO.Path]::GetFullPath($root))) {
                $res.StatusCode = 403
                $res.Close()
                continue
            }

            if (Test-Path $full -PathType Leaf) {
                $ext = [System.IO.Path]::GetExtension($full).ToLower()
                $type = 'application/octet-stream'
                if ($mime.ContainsKey($ext)) { $type = $mime[$ext] }

                $bytes = [System.IO.File]::ReadAllBytes($full)
                $res.ContentType = $type
                $res.ContentLength64 = $bytes.Length
                $res.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $res.StatusCode = 404
                $msg = [System.Text.Encoding]::UTF8.GetBytes("404 Not Found: $rel")
                $res.OutputStream.Write($msg, 0, $msg.Length)
            }
        } catch {
            $res.StatusCode = 500
        } finally {
            $res.Close()
        }
    }
} finally {
    $listener.Stop()
    $listener.Close()
}

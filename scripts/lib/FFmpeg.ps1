# 解析 ffmpeg / ffprobe 執行檔位置
#
# 優先透過 PATH 找 —— winget 安裝完之後，新開的終端機視窗通常找得到。
# 如果目前這個 shell 是安裝完 ffmpeg 之後沒有重開過的舊視窗（PATH 還沒
# 生效），退而求其次去 winget 的套件安裝目錄裡找，不寫死版本號路徑
# （ffmpeg 版本更新後，那段路徑裡的版本字串會變）。

function Get-FFTool {
    param([string]$Name)  # 'ffmpeg' 或 'ffprobe'

    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $wingetRoot = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (Test-Path $wingetRoot) {
        $found = Get-ChildItem -Path $wingetRoot -Filter "$Name.exe" -Recurse -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) { return $found.FullName }
    }

    throw "找不到 $Name。請確認已安裝 ffmpeg（winget install --id Gyan.FFmpeg），或重新開一個終端機視窗讓 PATH 生效。"
}

$script:FFmpegPath  = Get-FFTool 'ffmpeg'
$script:FFprobePath = Get-FFTool 'ffprobe'

# PotSweep.ps1 v3 - 收尾脚本: 读 PotCheck 的名单, 把文件移进同盘的"损坏视频待删"
# v3: 名单校验放宽: 主名单和"结尾待复核名单"都收; 复核名单会整批移走, 不逐个复核 (运行时有提醒)。
# v2: 建夹和移动全程改用 .NET 字面路径接口 (v1 用 New-Item -Path, 路径里的 [] 会被当通配符,
#     导致目标夹没建成、38 个全部移动失败); 失败时把目标路径和真实原因打在同一行。
# 只是移动, 不是删除; 原相对路径完整保留, 移错了照移动记录拖回去即可。
# 用法: 把 PotCheck-Report.txt 拖到 PotSweep.bat 上 (不拖则自动找桌面的 PotCheck-Report.txt)
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
Write-Host '=== PotSweep v3 ==='

$reportPath = $null
if ($args.Count -ge 1 -and $args[0]) { $reportPath = $args[0] }
if (-not $reportPath) {
    $desk = [Environment]::GetFolderPath('Desktop')
    $cand = Join-Path $desk 'PotCheck-Report.txt'
    if (Test-Path -LiteralPath $cand) { $reportPath = $cand }
    if (-not $reportPath) {
        $cand2 = Join-Path $desk 'PotCheck-Review.txt'
        if (Test-Path -LiteralPath $cand2) { $reportPath = $cand2 }
    }
}
if (-not $reportPath -or -not (Test-Path -LiteralPath $reportPath)) {
    Write-Host '没找到报告文件。请把 PotCheck-Report.txt 或 PotCheck-Review.txt 拖到 PotSweep.bat 上。'
    Read-Host '按回车退出'
    exit 1
}

$lines = Get-Content -LiteralPath $reportPath -Encoding UTF8
$isMain = [bool]($lines | Select-String -SimpleMatch 'PotPlayer 试播检测报告' -Quiet)
$isReview = [bool]($lines | Select-String -SimpleMatch 'PotPlayer 结尾待复核名单' -Quiet)
if (-not $isMain -and -not $isReview) {
    Write-Host '这不是 PotCheck 的报告文件, 已中止, 什么都没动。'
    Read-Host '按回车退出'
    exit 1
}

if ($isReview) {
    Write-Host '注意: 这是"结尾待复核"名单。本脚本会把名单里的文件整批移进待删夹, 不逐个复核。'
}
$paths = New-Object System.Collections.Generic.List[string]
foreach ($ln in $lines) {
    if ($ln -match '^([A-Za-z]:\\.*\.\w{2,5})\s+（') { $paths.Add($Matches[1]) }
}
if ($paths.Count -eq 0) {
    Write-Host '报告里没解析出文件路径, 已中止, 什么都没动。'
    Read-Host '按回车退出'
    exit 1
}

$items = @()
$totalMB = 0.0
foreach ($p in $paths) {
    if ([System.IO.File]::Exists($p)) {
        $len = (New-Object System.IO.FileInfo($p)).Length
        $totalMB += $len / 1MB
        $items += @{ Path = $p; Exists = $true }
    } else {
        $items += @{ Path = $p; Exists = $false }
    }
}
$existCount = ($items | Where-Object { $_.Exists }).Count
$firstDrive = [System.IO.Path]::GetPathRoot($paths[0])
Write-Host ''
Write-Host ("报告: {0}" -f $reportPath)
Write-Host ("名单共 {0} 个, 其中 {1} 个文件存在, 合计 {2:N0} MB" -f $paths.Count, $existCount, $totalMB)
Write-Host ("待删夹将建在: {0}损坏视频待删" -f $firstDrive)
Write-Host '文件按原相对路径移进去。只是移动, 不删除。'
Write-Host ''
$ans = Read-Host '确认移动就输 Y 再回车, 其他任意键取消'
if ($ans -ne 'Y' -and $ans -ne 'y') {
    Write-Host '已取消, 什么都没动。'
    Read-Host '按回车退出'
    exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logs = @{}
$moved = 0; $skipped = 0; $failed = 0
foreach ($it in $items) {
    $src = $it.Path
    if (-not $it.Exists) {
        Write-Host ("[跳过] 文件不存在: {0}" -f $src)
        $skipped++
        continue
    }
    $drive = [System.IO.Path]::GetPathRoot($src)
    $destRoot = Join-Path $drive '损坏视频待删'
    if ($src.StartsWith($destRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Write-Host ("[跳过] 已在待删夹里: {0}" -f $src)
        $skipped++
        continue
    }
    $rel = $src.Substring($drive.Length)
    $dest = Join-Path $destRoot $rel
    $destDir = [System.IO.Path]::GetDirectoryName($dest)
    try {
        [void][System.IO.Directory]::CreateDirectory($destDir)
    } catch {
        Write-Host ("[失败] 建不了目标文件夹 {0} : {1}" -f $destDir, $_.Exception.Message)
        $failed++
        continue
    }
    if (-not [System.IO.Directory]::Exists($destDir)) {
        Write-Host ("[失败] 目标文件夹建完仍不存在: {0}" -f $destDir)
        $failed++
        continue
    }
    if ([System.IO.File]::Exists($dest)) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($dest)
        $ext = [System.IO.Path]::GetExtension($dest)
        $n = 2
        do { $dest = Join-Path $destDir ("{0}_{1}{2}" -f $base, $n, $ext); $n++ } while ([System.IO.File]::Exists($dest))
    }
    try {
        [System.IO.File]::Move($src, $dest)
        Write-Host ("[已移动] {0}" -f $src)
        if (-not $logs.ContainsKey($destRoot)) { $logs[$destRoot] = New-Object System.Collections.Generic.List[string] }
        $logs[$destRoot].Add(("{0}  =>  {1}" -f $src, $dest))
        $moved++
    } catch {
        Write-Host ("[失败] {0} -> {1} : {2}" -f $src, $dest, $_.Exception.Message)
        $failed++
    }
}

foreach ($k in $logs.Keys) {
    $logPath = Join-Path $k ("移动记录-{0}.txt" -f $stamp)
    $logs[$k] | Out-File -LiteralPath $logPath -Encoding UTF8
    Write-Host ("移动记录已写入: {0}" -f $logPath)
}
Write-Host ''
Write-Host ("完成: 已移动 {0} 个, 跳过 {1} 个, 失败 {2} 个。" -f $moved, $skipped, $failed)
Write-Host '去待删夹最后过一眼, 确认没问题后由你自己删除; 移错的照移动记录拖回原处即可。'
Write-Host '注意: 原来的空文件夹会留着, 不影响使用。'
Read-Host '按回车退出'

# PotCheck.ps1 v1.3 - 用 PotPlayer 本尊测试视频 (只测开头和结尾)
# v1.3: 断点续跑 - 每测完一个文件就写入桌面存档 PotCheck-State.txt;
#       中途关窗/断电后重拖同一文件夹, 可选 C 从断点继续; 扫完自动删存档。
# v1.2: 报告拆两份 - 开头播不了的进主报告 PotCheck-Report.txt (可直接拖给 PotSweep);
#       结尾有问题的单独进 PotCheck-Review.txt 待人工复核 (PotSweep 会拒绝这份, 防误删)。
# v1.1: 结尾判定放宽 - PotPlayer 跳转会吸附关键帧, 落点可比目标早几秒;
#       改为"落进结尾30秒内 + 往前走满1秒"即放行 (v1.0 曾把差2.4~4.8秒落位的判死)。
# 原理: 命令行让 PotPlayer 打开文件, 再用它官方的窗口消息接口 (WM_USER + 0x5002/0x5004/0x5006)
# 问它: 总时长多少 / 放到哪了 / 在播还是停了 / 画面宽高有没有。
# 开头能播 = 总时长>0 且状态为播放中、进度在走、画面宽度>0;
# 结尾能播 = 把播放位置跳到最后 20 秒, 它还能落位并继续走。
# 任何一段过不去就 ★ 标注进报告。本工具只标注, 永不移动/删除文件。
$HeadWaitSec = 8
$TailBackMs = 20000

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
Write-Host '=== PotCheck v1.3 ==='

Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class PotMsg {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);
}
'@

function Send-Pot($hwnd, $cmd, $lparam) {
    $res = [IntPtr]::Zero
    $ok = [PotMsg]::SendMessageTimeout($hwnd, 0x0400, [IntPtr]$cmd, [IntPtr]$lparam, 0x0002, 2000, [ref]$res)
    if ($ok -eq [IntPtr]::Zero) { return $null }
    return $res.ToInt64()
}

function Find-PotPlayer {
    $pkg = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'PotPlayer' } | Select-Object -First 1
    if ($pkg) {
        $p = Join-Path $pkg.InstallLocation 'PotPlayerMini64.exe'
        if (Test-Path $p) { return $p }
    }
    foreach ($p in @('C:\Program Files\DAUM\PotPlayer\PotPlayerMini64.exe', 'C:\Program Files (x86)\DAUM\PotPlayer\PotPlayerMini64.exe', 'C:\Program Files\PotPlayer\PotPlayerMini64.exe')) {
        if (Test-Path $p) { return $p }
    }
    return $null
}

function Start-Pot($exe, $file) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = '"' + $file + '" /seek=0 /new'
    $psi.UseShellExecute = $false
    return [System.Diagnostics.Process]::Start($psi)
}

function Get-Hwnd($proc, $waitSec) {
    $deadline = (Get-Date).AddSeconds($waitSec)
    while ((Get-Date) -lt $deadline) {
        try {
            $proc.Refresh()
            if ($proc.HasExited) { return [IntPtr]::Zero }
            if ($proc.MainWindowHandle -ne [IntPtr]::Zero) { return $proc.MainWindowHandle }
        } catch { return [IntPtr]::Zero }
        Start-Sleep -Milliseconds 300
    }
    return [IntPtr]::Zero
}

function Test-OneFile($exe, $file, $headWait) {
    # 返回: @{ Head=bool; Tail=('pass'|'fail'|'skip'); Note=string }
    $proc = $null
    try {
        $proc = Start-Pot $exe $file
        $hwnd = Get-Hwnd $proc 6
        if ($hwnd -eq [IntPtr]::Zero) {
            return @{ Head = $false; Tail = 'skip'; Note = 'PotPlayer 窗口没起来' }
        }
        # 开头测试: 等它解析出总时长并真正播起来 (进度要走、画面要有宽)
        $deadline = (Get-Date).AddSeconds($headWait)
        $total = 0; $cur1 = -1; $headOK = $false; $forcedPlay = $false
        while ((Get-Date) -lt $deadline) {
            $status = Send-Pot $hwnd 0x5006 0
            if ($null -ne $status -and $status -eq 1 -and -not $forcedPlay) {
                [void](Send-Pot $hwnd 0x5007 2)
                $forcedPlay = $true
            }
            $t = Send-Pot $hwnd 0x5002 0
            if ($null -ne $t -and $t -gt 0) { $total = $t }
            $w = Send-Pot $hwnd 0x6030 0
            $c = Send-Pot $hwnd 0x5004 0
            if ($total -gt 0 -and $null -ne $c) {
                if ($cur1 -lt 0) { $cur1 = $c }
                if ($c -gt $cur1 -and $null -ne $w -and $w -gt 0 -and $status -eq 2) { $headOK = $true; break }
            }
            Start-Sleep -Milliseconds 400
        }
        if (-not $headOK) {
            return @{ Head = $false; Tail = 'skip'; Note = ("开头播不了 (总时长={0}ms)" -f $total) }
        }
        # 结尾测试: 跳到最后 20 秒, 看它能不能落位并继续走 (或自然播到结尾)
        if ($total -le 25000) {
            return @{ Head = $true; Tail = 'skip'; Note = '文件太短，只测了开头' }
        }
        $target = $total - $TailBackMs
        [void](Send-Pot $hwnd 0x5005 $target)
        $deadline = (Get-Date).AddSeconds(14)
        $tailOK = $false; $maxCur = 0; $landCur = -1
        while ((Get-Date) -lt $deadline) {
            $c = Send-Pot $hwnd 0x5004 0
            if ($null -ne $c) {
                if ($c -gt $maxCur) { $maxCur = $c }
                if ($c -ge ($total - 3000)) { $tailOK = $true; break }
                if ($landCur -lt 0 -and $c -ge ($target - 30000)) { $landCur = $c }
                if ($landCur -ge 0 -and $c -ge ($landCur + 1000)) { $tailOK = $true; break }
            }
            Start-Sleep -Milliseconds 400
        }
        if ($tailOK) { return @{ Head = $true; Tail = 'pass'; Note = '' } }
        return @{ Head = $true; Tail = 'fail'; Note = ("结尾播不了 (跳到 {0}ms 后进度最远到 {1}ms)" -f $target, $maxCur) }
    } catch {
        return @{ Head = $false; Tail = 'skip'; Note = ('测试异常: ' + $_.Exception.Message) }
    } finally {
        if ($proc) {
            try { if (-not $proc.HasExited) { $proc.Kill(); $proc.WaitForExit(2000) | Out-Null } } catch {}
            $proc.Dispose()
        }
    }
}

# ===== 找 PotPlayer =====
$pot = Find-PotPlayer
if (-not $pot) {
    Write-Host '[出错] 没找到 PotPlayer (商店版和安装版的常见位置都查了)。'
    Write-Host '把这个窗口截图发我，我按你的安装位置改。'
    Read-Host '按回车退出'
    exit 1
}
Write-Host ("PotPlayer: {0}" -f $pot)

if ($args.Count -eq 0) {
    Write-Host '用法: 把文件夹或视频文件拖到 PotCheck.bat 图标上。'
    Read-Host '按回车退出'
    exit 0
}

# ===== 开工自检: 日文+空格文件夹里的真测试视频, 必须通过, 否则中止不下结论 =====
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host '[出错] 自检需要 ffmpeg 生成测试视频, 没找到 ffmpeg。'
    Read-Host '按回车退出'
    exit 1
}
Write-Host '正在自检 (拿测试视频走一遍 PotPlayer 通道)...'
$testDir = Join-Path $env:TEMP 'potcheck_selftest_テスト 01'
$testRaw = Join-Path $env:TEMP 'potcheck_raw.mp4'
try {
    if (Test-Path $testDir) { Remove-Item $testDir -Recurse -Force }
    New-Item -ItemType Directory -Path $testDir | Out-Null
    & ffmpeg -v error -f lavfi -i 'testsrc=duration=3:size=128x96:rate=10' -c:v mpeg4 -y $testRaw 2>$null
    $testFile = Join-Path $testDir 'テスト file.mp4'
    Move-Item -LiteralPath $testRaw -Destination $testFile
    $self = Test-OneFile $pot $testFile 12
    Remove-Item $testDir -Recurse -Force
    if (-not $self.Head) {
        Write-Host ('[出错] 自检失败: ' + $self.Note)
        Write-Host '已中止，不会对你的任何文件下结论。把这个窗口截图发我。'
        Read-Host '按回车退出'
        exit 1
    }
    Write-Host '自检通过。'
} catch {
    Write-Host '[出错] 自检过程异常, 已中止。把这个窗口截图发我。'
    Read-Host '按回车退出'
    exit 1
}

$exts = @('.mp4','.mkv','.avi','.mov','.wmv','.flv','.webm','.ts','.m2ts','.mpg','.mpeg','.vob','.m4v','.3gp','.rmvb','.rm')
$files = New-Object System.Collections.ArrayList
foreach ($a in $args) {
    if (Test-Path -LiteralPath $a -PathType Container) {
        Get-ChildItem -LiteralPath $a -Recurse -File | Where-Object { $exts -contains $_.Extension.ToLower() } | ForEach-Object { [void]$files.Add($_.FullName) }
    } elseif (Test-Path -LiteralPath $a) {
        [void]$files.Add((Resolve-Path -LiteralPath $a).Path)
    }
}
if ($files.Count -eq 0) {
    Write-Host '没找到任何视频文件。'
    Read-Host '按回车退出'
    exit 0
}

# ===== 断点续跑: 存档放桌面 PotCheck-State.txt =====
$rootKey = ($args | ForEach-Object { try { (Resolve-Path -LiteralPath $_).Path } catch { $_ } }) -join '|'
$statePath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'PotCheck-State.txt'
$doneMap = @{}
$resume = $false
if ([System.IO.File]::Exists($statePath)) {
    $sroot = ''; $scount = -1; $entries = @()
    foreach ($ln in (Get-Content -LiteralPath $statePath -Encoding UTF8)) {
        if ($ln.StartsWith("ROOT`t")) { $sroot = $ln.Substring(5) }
        elseif ($ln.StartsWith("COUNT`t")) { [void][int]::TryParse($ln.Substring(6), [ref]$scount) }
        elseif ($ln.StartsWith("DONE`t")) { $entries += $ln.Substring(5) }
    }
    if ($sroot -eq $rootKey -and $scount -eq $files.Count -and $entries.Count -gt 0) {
        Write-Host ("发现上次没扫完的存档: 已测 {0} / {1} 个。" -f $entries.Count, $files.Count)
        $mode = Read-Host '输 C 从断点继续, 输 R 全部重扫, 其他键退出'
        if ($mode -eq 'C' -or $mode -eq 'c') {
            $resume = $true
            foreach ($e in $entries) {
                $parts = $e -split "`t", 3
                if ($parts.Count -ge 2) { $doneMap[$parts[0]] = @{ Cat = $parts[1]; Reason = $(if ($parts.Count -ge 3) { $parts[2] } else { '' }) } }
            }
            Write-Host ("已载入存档, 将跳过已测的 {0} 个。" -f $doneMap.Count)
        } elseif ($mode -eq 'R' -or $mode -eq 'r') {
            Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host '已退出, 存档保留着, 下次还能继续。'
            Read-Host '按回车退出'
            exit 0
        }
    } else {
        Write-Host '桌面有个旧存档, 不是这次的文件夹 (或文件数变了), 已忽略; 本次扫完会自动清掉。'
    }
}
if (-not $resume) {
    try { @("ROOT`t$rootKey", "COUNT`t$($files.Count)") | Out-File -LiteralPath $statePath -Encoding utf8 -Force } catch {}
}
function Add-State($path, $cat, $reason) {
    try { ("DONE`t{0}`t{1}`t{2}" -f $path, $cat, $reason) | Out-File -LiteralPath $statePath -Encoding utf8 -Append } catch {}
}

Write-Host ("共 {0} 个视频，用 PotPlayer 逐个试播开头和结尾。每个约几秒，窗口别关。" -f $files.Count)
Write-Host ''

$flagHead = @()
$flagTail = @()
$i = 0
foreach ($f in $files) {
    $i++
    Write-Host ("[{0}/{1}] {2}" -f $i, $files.Count, $f)
    if ($doneMap.ContainsKey($f)) {
        $d = $doneMap[$f]
        Write-Host '    (上次已测, 跳过)'
        if ($d.Cat -eq 'HEAD') { $flagHead += [pscustomobject]@{ Path = $f; Reason = $d.Reason } }
        elseif ($d.Cat -eq 'TAIL') { $flagTail += [pscustomobject]@{ Path = $f; Reason = $d.Reason } }
        continue
    }
    $r = Test-OneFile $pot $f $HeadWaitSec
    if (-not $r.Head) {
        Write-Host ("    ★ 开头播不了: {0}" -f $r.Note)
        $flagHead += [pscustomobject]@{ Path = $f; Reason = '开头: ' + $r.Note }
        Add-State $f 'HEAD' ('开头: ' + $r.Note)
    } elseif ($r.Tail -eq 'fail') {
        Write-Host ("    ☆ 结尾待复核: {0}" -f $r.Note)
        $flagTail += [pscustomobject]@{ Path = $f; Reason = '结尾: ' + $r.Note }
        Add-State $f 'TAIL' ('结尾: ' + $r.Note)
    } elseif ($r.Tail -eq 'skip') {
        Write-Host '    -- 开头正常（结尾未测: 文件太短）'
        Add-State $f 'SKIP' ''
    } else {
        Write-Host '    -- 开头结尾都正常'
        Add-State $f 'OK' ''
    }
}

$desktop = [Environment]::GetFolderPath('Desktop')
$report = Join-Path $desktop 'PotCheck-Report.txt'
$lines = @()
$lines += "PotPlayer 试播检测报告 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
$lines += '主名单: 只有开头就播不了的 (PotPlayer 解析不出, 基本是实锤坏文件)。结尾有问题的在 PotCheck-Review.txt 里待复核, 不在这份。'
$lines += ("总计 {0} 个，开头播不了 {1} 个" -f $files.Count, $flagHead.Count)
$lines += ''
$lines += '【★ 开头播不了】'
foreach ($b in $flagHead) { $lines += ("{0}    （{1}）" -f $b.Path, $b.Reason) }
$lines | Out-File -FilePath $report -Encoding utf8

if ($flagTail.Count -gt 0) {
    $review = Join-Path $desktop 'PotCheck-Review.txt'
    $rlines = @()
    $rlines += "PotPlayer 结尾待复核名单 $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $rlines += '这些是开头能播、只有结尾跳转有问题的, 含误报可能, 请人工复核后再决定。不要把这份拖给 PotSweep (它也不会收)。'
    $rlines += ("共 {0} 个" -f $flagTail.Count)
    $rlines += ''
    $rlines += '【☆ 结尾待复核】'
    foreach ($b in $flagTail) { $rlines += ("{0}    （{1}）" -f $b.Path, $b.Reason) }
    $rlines | Out-File -FilePath $review -Encoding utf8
}

Write-Host ''
Write-Host '============================================================'
Remove-Item -LiteralPath $statePath -Force -ErrorAction SilentlyContinue
Write-Host ("检测完成: 共 {0} 个，★开头播不了 {1} 个 (桌面 PotCheck-Report.txt)，☆结尾待复核 {2} 个 (桌面 PotCheck-Review.txt)。断点存档已清除。" -f $files.Count, $flagHead.Count, $flagTail.Count)
Write-Host '本工具只标注，不移动、不删除任何文件。'
Read-Host '按回车退出'

# PotTools.ps1 - 视频工具箱菜单 (PotCheck / PotSweep / CleanEmptyFolders)
# 也可以不走菜单: 直接把文件夹/报告拖到各自的 .bat 上。
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$root = $PSScriptRoot

while ($true) {
    Write-Host ''
    Write-Host '================ PotTools 视频工具箱 ================'
    Write-Host '  1. PotCheck          检测视频能不能播 (PotPlayer 本尊试播)'
    Write-Host '  2. PotSweep          按 PotCheck 报告把坏文件移进待删夹'
    Write-Host '  3. CleanEmptyFolders 清理空文件夹 (删进回收站)'
    Write-Host '  0. 退出'
    Write-Host '====================================================='
    $sel = Read-Host '输入数字选择'
    if ($sel -eq '0') { break }
    elseif ($sel -eq '1') {
        $p = Read-Host '要检测的文件夹路径 (粘贴后回车)'
        if ($p) { & (Join-Path $root 'PotCheck.ps1') $p.Trim('"') }
    }
    elseif ($sel -eq '2') {
        $p = Read-Host 'PotCheck-Report.txt 的路径 (粘贴后回车; 直接回车则找桌面那份)'
        if ($p) { & (Join-Path $root 'PotSweep.ps1') $p.Trim('"') } else { & (Join-Path $root 'PotSweep.ps1') }
    }
    elseif ($sel -eq '3') {
        $p = Read-Host '要清理空文件夹的根文件夹路径 (粘贴后回车)'
        if ($p) { & (Join-Path $root 'CleanEmptyFolders.ps1') $p.Trim('"') }
    }
    else { Write-Host '没这个选项。' }
}

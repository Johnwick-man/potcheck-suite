# CleanEmptyFolders.ps1 - 只删空文件夹 (里面一个文件都没有的那种空壳)
# 用法: 把一个文件夹拖到 CleanEmptyFolders.bat 上, 它会找出该文件夹下所有空子文件夹,
# 先列清单, 输 Y 才删; 删除走回收站 (删错了能从回收站还原); 被拖的根文件夹本身不删。
$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
Add-Type -AssemblyName Microsoft.VisualBasic

Write-Host '=== 空文件夹清理 (只删空壳, 走回收站) ==='
if ($args.Count -eq 0 -or -not $args[0]) {
    Write-Host '用法: 把一个文件夹拖到 CleanEmptyFolders.bat 上。'
    Read-Host '按回车退出'
    exit 0
}
$root = $args[0]
if (-not [System.IO.Directory]::Exists($root)) {
    Write-Host ("文件夹不存在: {0}" -f $root)
    Read-Host '按回车退出'
    exit 1
}
Write-Host ("目标: {0}" -f $root)
Write-Host '正在找空文件夹...'

$dirs = Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending
$empty = New-Object System.Collections.Generic.List[string]
foreach ($d in $dirs) {
    $hasFile = Get-ChildItem -LiteralPath $d.FullName -File -Recurse -Force -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $hasFile) { $empty.Add($d.FullName) }
}
if ($empty.Count -eq 0) {
    Write-Host '没有找到空文件夹, 什么都不用删。'
    Read-Host '按回车退出'
    exit 0
}
Write-Host ''
Write-Host ("找到 {0} 个空文件夹:" -f $empty.Count)
foreach ($e in $empty) { Write-Host ("  {0}" -f $e) }
Write-Host ''
$ans = Read-Host '把这些空文件夹删进回收站就输 Y 再回车, 其他任意键取消'
if ($ans -ne 'Y' -and $ans -ne 'y') {
    Write-Host '已取消, 什么都没动。'
    Read-Host '按回车退出'
    exit 0
}

$deleted = 0; $failed = 0
foreach ($e in $empty) {
    try {
        if ([System.IO.Directory]::Exists($e)) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($e, 'OnlyErrorDialogs', 'SendToRecycleBin')
            Write-Host ("[已删进回收站] {0}" -f $e)
            $deleted++
        }
    } catch {
        Write-Host ("[失败] {0} : {1}" -f $e, $_.Exception.Message)
        $failed++
    }
}
Write-Host ''
Write-Host ("完成: 删除 {0} 个, 失败 {1} 个。有文件的夹子一个没动。" -f $deleted, $failed)
Read-Host '按回车退出'

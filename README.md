# PotCheck Suite

用 **PotPlayer 本尊**批量检验视频文件能不能播的 Windows 工具组（PowerShell）。

**核心思想：判定标准只有一个——你实际用的播放器能不能播。**
ffmpeg 系工具（ffprobe/ffmpeg 解码、各种「视频损坏检测」脚本）按规范严格判定，
对一批封装/索引有瑕疵但播放器实际能正常播放的文件会系统性误报。
本工具组反过来：直接驱动 PotPlayer 打开每个文件试播，以播放器的真实表现为准。

## 工具一览

| 工具 | 作用 | 入口 |
| --- | --- | --- |
| **PotCheck** | 逐个试播开头+结尾，生成问题名单 | `PotCheck.bat` |
| **PotSweep** | 按名单（主名单/复核名单）把坏文件移进「损坏视频待删」（只移不删） | `PotSweep.bat` |
| **CleanEmptyFolders** | 清理零文件的空文件夹壳（走回收站） | `CleanEmptyFolders.bat` |
| PotTools | 上面三件的菜单入口 | `PotTools.bat` |

## 快速开始

环境：Windows 10/11、已安装 [PotPlayer](https://potplayer.daum.net/)、
[ffmpeg](https://ffmpeg.org/) 在 PATH 中（`winget install Gyan.FFmpeg`，仅用于 PotCheck 的开工自检生成测试片）。

1. **检测**：把视频文件夹拖到 `PotCheck.bat` 上。扫完桌面生成两份名单：
   - `PotCheck-Report.txt`——主名单：**开头就播不了**的（播放器解析不出，实锤坏文件）
   - `PotCheck-Review.txt`——复核名单：开头能播、只有**结尾跳转**有问题的，留人工复核
2. **收尾**：把 `PotCheck-Report.txt` 拖到 `PotSweep.bat` 上，确认数量后输 `Y`，
   文件被按原相对路径移进同盘根目录的 `损坏视频待删\`，并生成移动记录可回退。
   最后删不删，由你亲手决定。
   复核名单 `PotCheck-Review.txt` 也可以拖给 PotSweep（v3 起）：会先打印提醒，确认后整批移走，不逐个复核。
3. **清空壳**：把文件夹拖到 `CleanEmptyFolders.bat` 上，清理移动后留下的空文件夹。

## PotCheck 判定细节

- 每个文件用新实例打开 PotPlayer，通过窗口消息协议读取总时长/进度/播放状态/画面尺寸
  （WM_USER 0x5002/0x5004/0x5005/0x5006/0x5007/0x6030），全程限时、错误弹窗不会卡死流程。
- 开头过 = 总时长 > 0 且播放中、进度在走、画面宽 > 0。
- 结尾过 = 跳转到最后 20 秒后：**落进目标前 30 秒内且往前走满 1 秒**即放行
  （播放器跳转会吸附关键帧，落点比目标早几秒是正常现象，早期版本曾因此误报，已修正）。
- 开工前自检：在临时目录生成一个带日文+空格文件名的测试片走完整通道，自检不过即中止、零判定。
- **断点续跑**：每测完一个文件就写入桌面存档 `PotCheck-State.txt`；中途关窗/断电后，
  重拖同一文件夹可选 `C` 从断点继续（已测的跳过、结果并入最终报告）；扫完自动删存档。
- 速度约每文件数秒，适合整盘过夜扫。

## 安全设计

- PotCheck **只标注**，永不移动/删除任何文件。
- PotSweep 动手前先列名单数量与总大小，输 `Y` 才执行；只移动不删除；
  校验报告标题，只认 PotCheck 的主名单与复核名单，拖错文件直接拒绝；复核名单整批移走前会先打印提醒。
- CleanEmptyFolders 只删「一个文件都没有」的文件夹，且走回收站可还原。
- 所有路径处理走 .NET 字面接口，对 `[ ]`、空格、中文、日文路径免疫。

## 验证方法

判定逻辑经过对照校准：在一个真实下载批次上，PotCheck 的「开头播不了」名单经人工
逐个用 PotPlayer 打开复核为真损坏；「结尾」类早期误报在复核后促成了判定放宽（见上）。
名单类工具请先小批量对照人工试播再放行大盘——这是本项目的血泪经验。

## 已知限制

- 依赖 PotPlayer 的窗口消息协议，仅限 Windows + PowerShell 5.1。
- 超大文件 + 慢速盘（USB 机械盘）上播放器建索引较慢，个别文件耗时会长一些。
- 结尾类判定含少量不确定性，所以才拆出复核名单，而不是直接进主名单。

## 开发笔记（PowerShell 5.1 的坑）

`Split-Path -LiteralPath ... -Parent` 在 PS 5.1 是 **AmbiguousParameterSet** 非法组合，
会让目标变量恒为 null 并引发连环失败。本项目全部改用 `[System.IO.Path]::GetDirectoryName`
等 .NET 接口。若你也写 PS 脚本处理用户路径，请避开这个组合。

## License

MIT

# 安装与常见问题

## 选择使用方式

支持两种使用方式，任选一种即可。**推荐下载完整软件，PoB2 和汉化已整合，安装后直接使用。**

| 使用方式 | 内容与准备 | 安装后的启动入口 |
| --- | --- | --- |
| **完整软件（推荐）** | 下载包含 PoB2 与汉化的 DMG，拖入应用程序 | “PoB2 简体中文.app” |
| **独立汉化插件** | 已有 Mac 原生 PoB2，使用 Python 3.9+ 安装插件 | 原来的 PoB2 App |

## 方式一：完整软件（推荐）

适用于 **Apple Silicon（M 系列）Mac，macOS 11 及以上**。完整包内含 **PoB2 核心 0.23.1 + 汉化 0.6.2**，程序与汉化会一并安装。

1. [下载完整 DMG](https://github.com/snipernan/pob2-zh-cn/releases/download/v0.6.2/PoB2-0.23.1-zh-CN-0.6.2-AppleSilicon.dmg)，约 389 MiB。
2. 打开 DMG，将“PoB2 简体中文.app”拖入 Applications（应用程序）。
3. 从“应用程序”打开“PoB2 简体中文”，首次启动会自动准备核心和汉化。
4. 开始使用；F10 或 Fn + F10 切换中英文。

[Release 页面](https://github.com/snipernan/pob2-zh-cn/releases/tag/v0.6.2)提供安装说明和 SHA-256 校验文件。

### 首次打开

个人打包版首次启动时，可按系统提示在“系统设置 → 隐私与安全性”中批准已信任的 App；参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。本项目打包器默认使用 ad-hoc 签名；Apple 公证作为发行阶段的独立流程处理。

### 配装与数据目录

完整软件使用独立目录：

```text
~/Library/Application Support/PathOfBuildingMacPoE2Chinese/
```

配装与设置位于其中 `UserData/Path of Building (PoE2)/`。已有配装可通过原来的导入功能迁移。完整软件每次启动都会自动加载内置汉化。

## 方式二：给现有 PoB2 安装汉化插件

适用于 **已有 Apple Silicon Mac 原生 PoB2** 的用户，已验证核心 **0.23.1**。当前独立插件版本为 **0.6.3**。安装脚本使用 **Python 3.9+**；插件在 PoB2 内通过 Lua 运行。

1. [下载插件源码 ZIP](https://github.com/snipernan/pob2-zh-cn/archive/refs/heads/main.zip)并解压。
2. 先启动现有 PoB2 一次，让它生成用户运行目录，然后保存配装并退出。
3. 在解压目录双击 `安装或更新汉化.command`。也可在该目录打开终端，使用已安装的 Python 3 执行：

```sh
python3 install.py
python3 install.py --status
```

4. 重新打开原来的 PoB2，汉化生效。F10 或 Fn + F10 切换中英文。

### 安装目录

- 核心：`~/Library/Application Support/PathOfBuildingMacPoE2/src/`
- 汉化：同级 `PoB2Chinese/`
- 加载入口：用户运行目录的 `src/Launch.lua` 末尾。
- 安装备份／记录：插件源码或解压目录中的 `backups/`、`installation.json`，Git 会忽略这些文件。

安装器更新用户目录中的插件入口和汉化资源，保留原 App、游戏计算模块和配装数据。重复安装保留语言选择与自定义资源；写入失败会回滚。

自定义目录时，安装、检查与卸载均使用同一个 `--target`：

```sh
python3 install.py --target "/path/to/PathOfBuildingMacPoE2"
python3 install.py --target "/path/to/PathOfBuildingMacPoE2" --status
python3 install.py --target "/path/to/PathOfBuildingMacPoE2" --uninstall
```

### 更新与卸载

v0.6.3 在应用内常规核心更新开始前确认已安装的汉化入口，更新成功后把入口恢复到新版 `Launch.lua`，随后按 PoB 原有流程重启。核心新代码、更新版本信息及语言偏好均保留。

**安装或升级插件后，请先重启一次 PoB2，再进行核心更新。** 自动恢复在新版插件已加载的进程中生效。

此适配覆盖通过 `UpdateApply` 执行的常规 Lua 核心更新。整包替换、更新异常或加载接口变化后，可运行状态检查并按需重新安装。卸载后的后续更新按原版流程执行。

默认目录卸载命令为 `python3 install.py --uninstall`，也可双击 `卸载汉化.command`。卸载移除插件入口并保留用户配装，重新打开原来的 PoB2 后生效。

## 启用中文显示

独立插件用户可运行 `python3 install.py --status`。如入口缺失，重新安装并重启。v0.6.3 会在常规核心更新完成后恢复加载入口；上游更新按原有流程运行。磁盘状态正常但窗口仍是英文时，确认重启的是相应 App，按 F10 或 Fn + F10 切换语言。

## 中文输入变成问号

v0.6.1 起包含适配本次原生引擎的 UTF-8 字符桥接。安装后必须重启；已经变成问号的查询需要清空重输。此桥接已在适配的原生 Mac 引擎上验证，候选窗口由系统输入法管理。

## 搜索与文字匹配

保留类型、部位等原有筛选条件。译文优先按已核验的 ID、名称和完整模板匹配；其余内容保留英文。技能长说明、其他树版本及特殊动态效果按已收录映射显示；装备导入使用原有英文文本格式。

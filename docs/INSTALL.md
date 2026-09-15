# 安装与常见问题

## 原生 Mac 插件

适配 Apple Silicon 原生 Mac 移植版，已验证核心 0.23.1。安装脚本使用 Python 3.9+；插件在 PoB2 内通过 Lua 运行。

先启动原版一次，让它生成用户运行目录。保存配装并退出，再从本项目根目录运行 `python3 install.py`，最后重新打开 PoB2。也可双击 `安装或更新汉化.command`；脚本调用系统 Python，也可在终端选择已安装的 Python 3。

默认加载位置：

- 核心：`~/Library/Application Support/PathOfBuildingMacPoE2/src/`
- 汉化：同级 `PoB2Chinese/`
- 加载入口：用户运行目录的 `src/Launch.lua` 末尾。
- 安装备份／记录：插件源码或解压目录中的 `backups/`、`installation.json`，Git 会忽略这些文件。

安装器更新用户目录中的插件入口和汉化资源，保留原 App、游戏计算模块和配装数据。重复安装会保留用户语言选择与自定义资源；写入失败会回滚。卸载移除插件入口并保留用户配装。

自定义安装目录须把同一个 `--target` 同时用于安装、检查和卸载。

## 启用中文显示

运行 `python3 install.py --status`。如入口缺失，重新安装并重启。核心更新可能重新写入 `Launch.lua`；上游更新按原有流程运行。磁盘状态正常但窗口仍是英文时，确认重启的是相应 App，按 F10 或 Fn + F10 切换语言。

## 中文输入变成问号

v0.6.1 起包含适配本次原生引擎的 UTF-8 字符桥接。安装后必须重启；已经变成问号的查询需要清空重输。此桥接已在适配的原生 Mac 引擎上验证，候选窗口由系统输入法管理。

## 搜索与文字匹配

保留类型、部位等原有筛选条件。译文优先按已核验的 ID、名称和完整模板匹配；其余内容保留英文。技能长说明、其他树版本及特殊动态效果按已收录映射显示；装备导入使用原有英文文本格式。

## 完整 DMG

[下载 v0.6.2 完整安装包](https://github.com/snipernan/pob2-zh-cn/releases/tag/v0.6.2)，页面附有 SHA-256 校验文件和安装说明。

维护者提供的 `PoB2 简体中文.app` 已带汉化：从 DMG 拖入 Applications 后启动即可使用。

分享版用户数据位于 `~/Library/Application Support/PathOfBuildingMacPoE2Chinese/UserData/Path of Building (PoE2)/`，与原版分开。已有配装可用原来的导入功能迁移。分享版启动时会自动加载内置汉化。

个人打包版首次启动时，可按系统提示在“系统设置 → 隐私与安全性”中批准已信任的 App；参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。本项目打包器默认使用 ad-hoc 签名；Apple 公证作为发行阶段的独立流程处理。

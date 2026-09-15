# 安装与常见问题

## 原生 Mac 插件

适配 Apple Silicon 原生 Mac 移植版，已验证核心 0.23.1。Windows、Wine 和 Intel Mac 未验证。安装脚本需要 Python 3.9+；运行 PoB2 时不依赖 Python。

先启动原版一次，让它生成用户运行目录。保存配装并退出，再从本项目根目录运行 `python3 install.py`，最后重新打开 PoB2。也可双击 `安装或更新汉化.command`；脚本调用系统 Python，如果不可用可在终端使用已安装的 Python 3。

默认加载位置：

- 核心：`~/Library/Application Support/PathOfBuildingMacPoE2/src/`
- 汉化：同级 `PoB2Chinese/`
- 加载入口：用户运行目录的 `src/Launch.lua` 末尾。
- 安装备份／记录：插件源码或解压目录中的 `backups/`、`installation.json`，Git 会忽略这些文件。

安装器不修改原 App、游戏计算模块或配装数据。重复安装会保留用户语言选择与自定义资源；写入失败会回滚。卸载移除插件入口，不删除用户配装。

自定义安装目录须把同一个 `--target` 同时用于安装、检查和卸载。

## 中文没有生效

运行 `python3 install.py --status`。如入口缺失，重新安装并重启。核心更新可能重新写入 `Launch.lua`；安装器不会阻止上游更新。磁盘状态正常但窗口仍是英文时，确认重启的是相应 App，按 F10 或 Fn + F10 切换语言。

## 中文输入变成问号

v0.6.1 起包含适配本次原生引擎的 UTF-8 字符桥接。安装后必须重启；已经变成问号的查询需要清空重输。此桥接不保证兼容所有其他 Mac 移植或 Wine 版本，也不改变系统输入法候选窗口。

## 搜索不到或仍有英文

保留类型、部位等原有筛选条件。译文优先按已核验的 ID、名称和完整模板匹配；不存在或存在歧义的内容保留英文。技能长说明、其他树版本及特殊动态效果未必覆盖。中文装备原文直接导入尚不支持。

## 完整 DMG

维护者提供的 `PoB2 简体中文.app` 已带汉化：从 DMG 拖入 Applications 后启动即可，无需 Python。

分享版用户数据位于 `~/Library/Application Support/PathOfBuildingMacPoE2Chinese/UserData/Path of Building (PoE2)/`，与原版分开。已有配装可用原来的导入功能迁移。不要向分享版再重复安装原版插件入口。

个人打包版如果未经过 Apple 公证，首次启动可能需要在“系统设置 → 隐私与安全性”中批准已信任的 App；参见 [Apple 官方说明](https://support.apple.com/zh-cn/102445)。本项目打包器默认仅做 ad-hoc 签名，不声称已经公证。

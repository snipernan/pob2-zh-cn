# 开发与验证

## 环境

- 数据编译、检查及安装测试：Python 3.9+，仅标准库。
- Lua 单元测试：LuaJIT，或 Apple Silicon Mac 原生 PoB2 App 内的 LuaJIT。
- 实际核心集成：已验证的原生 App 和 0.23.1 `src`，不随本仓库分发。
- 字库重建：macOS + Xcode command-line tools（AppKit/CoreText）。

在 Git clone 后或 `git init` 后运行：

```sh
python3 build_assets.py
python3 verify_tree_overlay.py
python3 scripts/check_repository.py
python3 test_install.py
python3 run_lua.py tests.lua
python3 run_lua.py tests_game_text.lua
```

`build_assets.py` 从 `translations.tsv` 和 `data/` 中的审核映射编译，完全离线。`data/tree-combined-cn.json` 为生成的合并结果，不进入 Git。`payload/` 中的生成词典和字库进入 Git，保证用户无需编译即可安装。修改源译文后同时提交生成词典；CI 会检查是否一致。

`data/source-manifest.json` 记录源数据 SHA-256。修改数据后先审查来源与测试结果，再更新对应摘要；不要单纯为了绕过校验而更新它。原始网页和 API 缓存不在仓库内，离线构建不依赖它们；数据中的旧快照路径是来源记录，不是需要下载的构建依赖。

## 字库

本项目使用仓库内带 OFL 许可的 Noto，不能重新换回个人机器的系统苹方图集。只在字符集改变或字库代码修改时重建：

```sh
swift -sdk "$(xcrun --show-sdk-path)" build_font.swift "$PWD" "$PWD/fonts/NotoSansCJKsc-Regular.otf"
python3 scripts/check_repository.py
```

图集生成器检查每个字形是否存在。AppKit 的不同系统版本可能影响像素，不要求跨 macOS 位图逐字节一致；词典编译应逐字节可复现。

## 使用实际 Mac 引擎

显式设置 App 后，单元测试使用它的原生库：

```sh
export POB2_MAC_APP="/Applications/Path of Building - PoE2.app"
python3 run_lua.py tests.lua
python3 run_lua.py tests_game_text.lua
```

真实控件集成：

```sh
export POB2_CORE_SRC="$HOME/Library/Application Support/PathOfBuildingMacPoE2/src"
python3 scripts/test_integration.py
```

也可使用 `--app` 和 `--core`。入口会设置核心工作目录，并在项目内 `test-user/`、`test-output/` 创建合成测试数据，不加载正在使用的配装。测试覆盖真实页面、技能与装备搜索、天赋、属性差异、切语言后的数值和序列化保护。

单元测试不证明输入法或原生窗口正确。修改 `mac_input.lua` 或本机引擎适配后，需要额外在测试窗口输入“火球”等文字、切页、测试快捷键和正常退出。CI 使用 Linux LuaJIT，不冒充 macOS 集成验收。

## 结构约定

入口与已有 Lua 测试保持根目录布局，避免改变安装资源相对路径。运行代码在 `payload/`，数据来自审核 JSON，构建和发布工具在 `scripts/` 与 `packaging/`。`installation.json`、备份、测试输出和分发文件始终被 Git 忽略。

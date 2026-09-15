# 开发与验证

## 环境

- 数据编译、检查及安装测试：Python 3.9+，仅标准库。
- Lua 单元测试：LuaJIT，或 Apple Silicon Mac 原生 PoB2 App 内的 LuaJIT。
- 实际核心集成：自行准备已验证的原生 App 和 0.23.1 `src`。
- 字库重建：macOS + Xcode command-line tools（AppKit/CoreText）。

在 Git clone 后或 `git init` 后运行：

```sh
python3 build_assets.py
python3 verify_tree_overlay.py
python3 scripts/check_repository.py
python3 test_install.py
python3 test_update_guard.py
python3 run_lua.py tests.lua
python3 run_lua.py tests_game_text.lua
```

`build_assets.py` 从 `translations.tsv` 和 `data/` 中的审核映射编译，完全离线。`data/tree-combined-cn.json` 为生成的合并结果，由 Git 忽略规则管理。`payload/` 中的生成词典和字库进入 Git，供用户直接安装。修改源译文后同时提交生成词典；CI 会检查是否一致。

`data/source-manifest.json` 记录源数据 SHA-256。修改数据后先审查来源与测试结果，再更新对应摘要。离线构建使用仓库中的审核映射；数据中的旧快照路径用于追溯历史采集来源。

## 字库

本项目使用仓库内带 OFL 许可的 Noto 生成可分发字库。只在字符集改变或字库代码修改时重建：

```sh
swift -sdk "$(xcrun --show-sdk-path)" build_font.swift "$PWD" "$PWD/fonts/NotoSansCJKsc-Regular.otf"
python3 scripts/check_repository.py
```

图集生成器检查每个字形是否存在。图集按生成时的 macOS 和 AppKit 环境进行视觉验收；词典编译应逐字节可复现。

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

也可使用 `--app` 和 `--core`。入口会设置核心工作目录，并在项目内 `test-user/`、`test-output/` 创建并加载独立的合成测试数据。测试覆盖真实页面、技能与装备搜索、天赋、属性差异、切语言后的数值和序列化保护。

输入法和原生窗口通过实际交互验收。修改 `mac_input.lua` 或本机引擎适配后，需要额外在测试窗口输入“火球”等文字、切页、测试快捷键和正常退出。CI 使用 Linux LuaJIT 运行单元检查，macOS 集成验收使用原生环境。

## 结构约定

入口与已有 Lua 测试保持根目录布局，避免改变安装资源相对路径。运行代码在 `payload/`，数据来自审核 JSON，构建和发布工具在 `scripts/` 与 `packaging/`。`installation.json`、备份、测试输出和分发文件始终被 Git 忽略。

## 更新入口验证

`test_update_guard.py` 在临时目录安装插件，模拟连续更新与错误场景，然后用新的 Lua 进程验证入口加载，最后执行卸载。

本地指定核心时使用它的真实 `UpdateApply.lua`：

```sh
python3 test_update_guard.py --core "$POB2_CORE_SRC"
```

CI 使用最小更新契约模拟文件替换；实际核心更新脚本在本地原生库环境另行验证。`update_guard.lua` 每次更新前只采集当前已安装的独立入口，更新成功后校验新文件并原子补回入口。整包启动入口采用原有独立加载方式。

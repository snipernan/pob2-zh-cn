# 上传 GitHub 与发布

## 上传源码仓库

项目仓库：[snipernan/pob2-zh-cn](https://github.com/snipernan/pob2-zh-cn)。以下初始化步骤适用于新建仓库或个人副本；已有仓库可直接提交并推送到自己的 remote。

从本项目目录提交源码，默认分支为 `main`。账户凭据由本机 GitHub 登录工具管理。

先运行 README 的检查，再创建初始提交：

```sh
git add .
git diff --cached --stat
git commit -m "Prepare PoB2 Chinese plugin for open source"
```

提交作者使用你自己的 Git 设置；需要隐藏邮箱时可使用 GitHub 提供的 noreply 地址。

在 GitHub 创建空仓库（建议名称 `pob2-zh-cn`），将初始化文件留给本地源码提交，并复制该页面给出的仓库 URL：

```sh
git remote add origin <复制的仓库URL>
git push -u origin main
```

源码推送后 GitHub Actions 会运行离线检查；Mac 原生验收另在实际系统环境中执行。

## 发布独立插件 ZIP

```sh
python3 scripts/package_plugin.py
```

输出 `dist/pob2-zh-cn-plugin-0.6.3.zip` 和 SHA-256 文件。ZIP 按明确清单收录安装资源，作为 GitHub Releases 附件发布；源码通过 Git 提交。

## 重建完整 Mac DMG

需要 macOS、Xcode command-line tools、兼容的 Apple Silicon 原生 App、0.23.1 核心，以及与该 App 匹配的 [Mac 移植源码](https://github.com/stevschmid/PathOfBuilding-Mac)中的 `macos/launcher.cpp`。

```sh
python3 packaging/build_share.py \
  --app "/Applications/Path of Building - PoE2.app" \
  --core "$HOME/Library/Application Support/PathOfBuildingMacPoE2/src" \
  --launcher-source "/path/to/PathOfBuilding-Mac/macos/launcher.cpp" \
  --output-dir "$PWD/build/share-0.6.3" \
  --dmg
```

脚本拒绝覆盖已存在的 staging App。它验证核心清单与文件摘要、去除个人安装入口、复制 Noto 字库、生成独立支持目录的启动器、保留来源、签名并校验映像。字库重建是开发步骤，日常打包直接使用已提交图集。

已发布完整 DMG 为 0.23.1 / 0.6.2。打包器从当前插件读取版本，输出相应版本的新包；更新版本时须同时检查编译器限制、启动器宏、bundle version、核心 manifest 和插件版本。原生 ABI 或核心改变后，须完成相应兼容性验证。

默认使用 **ad-hoc 签名**。持有 Developer ID 的维护者可进一步完成签名、Apple 公证和 stapling，并在发行说明中注明实际完成的流程。完整发行包保留上游各组件许可与对应源码获取方式；原创代码、上游二进制、第三方数据和游戏资产分别遵循各自许可。

## 验收与附件

在独立用户目录验证首次启动和重启、中文显示与输入、F10、配装保存以及原版数据隔离；只读挂载最终 DMG 并核验其中 App 签名。运行中的诊断文件记录版本和输入桥接状态，配合窗口交互结果进行验收。

Release 说明写明插件、核心、Mac 移植版本、测试系统及适用范围。附件放插件 ZIP、可选 DMG、校验文件和安装说明。Git 维护源码与文档，安装包通过 Releases 分发，测试配装、备份和安装记录由本地目录保存。

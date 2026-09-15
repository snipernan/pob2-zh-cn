# 上传 GitHub 与发布

## 上传源码仓库

项目仓库：[snipernan/pob2-zh-cn](https://github.com/snipernan/pob2-zh-cn)。以下初始化步骤适用于新建仓库或个人副本；已有仓库可直接提交并推送到自己的 remote。

只上传本项目目录，不要上传它外面的 PoB2 工作目录。默认分支为 `main`。Git 账户凭据不属于仓库内容。

先运行 README 的检查，再创建初始提交：

```sh
git add .
git diff --cached --stat
git commit -m "Prepare PoB2 Chinese plugin for open source"
```

提交作者使用你自己的 Git 设置；需要隐藏邮箱时可使用 GitHub 提供的 noreply 地址。

在 GitHub 创建空仓库（建议名称 `pob2-zh-cn`，不要自动创建 README），复制该页面给出的仓库 URL：

```sh
git remote add origin <复制的仓库URL>
git push -u origin main
```

源码推送后 GitHub Actions 会运行离线检查；它不能代替 Mac 原生验收。

## 发布独立插件 ZIP

```sh
python3 scripts/package_plugin.py
```

输出 `dist/pob2-zh-cn-plugin-0.6.2.zip` 和 SHA-256 文件。ZIP 使用明确文件清单，不包含安装记录或个人偏好。放在 GitHub Releases 的附件中；不要把 ZIP 作为仓库源码上传。

## 重建完整 Mac DMG

需要 macOS、Xcode command-line tools、兼容的 Apple Silicon 原生 App、0.23.1 核心，以及与该 App 匹配的 [Mac 移植源码](https://github.com/stevschmid/PathOfBuilding-Mac)中的 `macos/launcher.cpp`。

```sh
python3 packaging/build_share.py \
  --app "/Applications/Path of Building - PoE2.app" \
  --core "$HOME/Library/Application Support/PathOfBuildingMacPoE2/src" \
  --launcher-source "/path/to/PathOfBuilding-Mac/macos/launcher.cpp" \
  --output-dir "$PWD/build/share-0.6.2" \
  --dmg
```

脚本拒绝覆盖已存在的 staging App。它验证核心清单与文件摘要、去除个人安装入口、复制 Noto 字库、生成独立支持目录的启动器、保留来源、签名并校验映像。字库重建是开发步骤，日常打包直接使用已提交图集。

此打包器沿用已经验证的 0.23.1 / 0.6.2 分享方案；更新版本时须同时检查编译器限制、启动器宏、bundle version、核心 manifest 和插件版本。原生 ABI 或核心改变不能仅修改版本字符串就视为兼容。

默认使用 **ad-hoc 签名，未进行 Apple 公证**。有自己的 Developer ID 时，维护者可另外签名、公证和 stapling，不能把 ad-hoc 校验成功描述为“通过 Apple 公证”。完整发行包需保留上游各组件许可与对应源码获取方式；源码仓库的 MIT 不覆盖上游二进制、第三方数据或游戏资产。

## 验收与附件

在独立用户目录验证首次启动和重启、中文显示与输入、F10、配装保存以及原版数据隔离；只读挂载最终 DMG 并核验其中 App 签名。运行中的诊断文件只包含版本和输入桥接状态，不能代替全部交互测试。

Release 说明写明插件、核心、Mac 移植版本、测试系统及未覆盖平台。附件放插件 ZIP、可选 DMG、校验文件和安装说明。原 App、DMG、ZIP、测试配装、备份与安装记录不提交到 Git。

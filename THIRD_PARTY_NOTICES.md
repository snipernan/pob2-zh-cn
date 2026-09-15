# 第三方内容与许可范围

根目录 MIT 许可证适用于本项目原创程序代码。它不声称本项目拥有以下第三方文字、字体、游戏资产或上游代码的版权，也不将它们重新许可为 MIT。

| 内容 | 本仓库位置 | 来源及适用说明 |
| --- | --- | --- |
| 腾讯国服与国际服公开游戏文本 | `data/`、生成的游戏词典、少量界面术语与测试断言 | 腾讯、Grinding Gear Games 及相应权利人；公开 API 的可访问性不等于取得开源再许可。本项目没有取得可将这些文本统一改为 MIT 的授权。 |
| 流亡 2 编年史补充内容 | `data/`、`payload/game_dictionary.lua`、`payload/equipment_dictionary.lua` | [PoE2DB](https://poe2db.tw/cn/)；所用物品页面的 Wiki 内容注明 [CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/)，除非另有说明。该声明不自动涵盖所有游戏资产、API 数据或网站其他内容。相关改编保留署名、非商业和相同方式共享要求。 |
| Noto Sans CJK SC | `fonts/NotoSansCJKsc-Regular.otf`、`payload/font*.png`、`payload/font.lua` | [Noto CJK](https://github.com/notofonts/noto-cjk/tree/main/Sans)，[SIL OFL 1.1](fonts/LICENSE)。图集由此字体生成，生成器为 `build_font.swift`，保留完整字体许可。 |
| PoB 最小天赋覆盖输入及派生接口适配 | `data/inputs/tree-0_5.json`，Lua 适配／测试中涉及的上游接口 | [PoB2](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2)，保留 [上游许可汇总](licenses/PathOfBuilding-NOTICES.txt)。游戏文本的原权利不因此转移。 |

编年史数据经过节点 ID、英文身份和效果核对，部分文字进行了术语统一、数值模板化或人工修订。`verification`、`sourceIds` 和修订字段保留在数据中；详见[来源说明](docs/DATA_SOURCES.md)。对已有 CC BY-NC-SA 内容的可许可改编沿用相同许可，不授予第三方原始游戏文本超出原有许可的权利。

本仓库不包含 PoB 可执行程序、游戏贴图、网页原始缓存、系统苹方字体或用户配装。维护者制作完整 DMG 时，应同时保留实际使用的 PoB、Mac 移植、原生库和字体许可、版本及对应源码获取方式；不能用本项目 MIT 文件替换它们。

如有来源、署名或权利问题，请在仓库提交只涉及相关条目的 Issue。项目可独立维护和分发 MIT 适配代码；包含第三方数据的发行包受各自条款约束。

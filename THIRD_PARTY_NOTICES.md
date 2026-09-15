# 第三方内容与许可范围

根目录 MIT 许可证适用于本项目原创程序代码。第三方文字、字体、游戏资产和上游代码的权利归各自权利人，使用与分发遵循对应许可。

| 内容 | 本仓库位置 | 来源及适用说明 |
| --- | --- | --- |
| 腾讯国服与国际服公开游戏文本 | `data/`、生成的游戏词典、少量界面术语与测试断言 | 权利归腾讯、Grinding Gear Games 及相应权利人；本项目保留公开 API 来源，文本使用与再分发遵循原权利人的适用条款。 |
| 流亡 2 编年史补充内容 | `data/`、`payload/game_dictionary.lua`、`payload/equipment_dictionary.lua` | [PoE2DB](https://poe2db.tw/cn/)；所用物品页面的 Wiki 内容注明 [CC BY-NC-SA 3.0](https://creativecommons.org/licenses/by-nc-sa/3.0/)，除非另有说明。游戏资产、API 数据和网站其他内容分别遵循各自的适用条款。相关改编保留署名、非商业和相同方式共享要求。 |
| Noto Sans CJK SC | `fonts/NotoSansCJKsc-Regular.otf`、`payload/font*.png`、`payload/font.lua` | [Noto CJK](https://github.com/notofonts/noto-cjk/tree/main/Sans)，[SIL OFL 1.1](fonts/LICENSE)。图集由此字体生成，生成器为 `build_font.swift`，保留完整字体许可。 |
| PoB 最小天赋覆盖输入及派生接口适配 | `data/inputs/tree-0_5.json`，Lua 适配／测试中涉及的上游接口 | [PoB2](https://github.com/PathOfBuildingCommunity/PathOfBuilding-PoE2)，保留 [上游许可汇总](licenses/PathOfBuilding-NOTICES.txt)。游戏文本的权利归原权利人。 |

编年史数据经过节点 ID、英文身份和效果核对，部分文字进行了术语统一、数值模板化或人工修订。`verification`、`sourceIds` 和修订字段保留在数据中；详见[来源说明](docs/DATA_SOURCES.md)。对已有 CC BY-NC-SA 内容的可许可改编沿用相同许可；第三方原始游戏文本继续遵循原有授权范围。

本仓库维护汉化代码、审核映射、Noto 字库和项目文档。演示截图由项目维护者提供，其中游戏画面及界面元素的权利归各自权利人。制作完整 DMG 时，应同时保留实际使用的 PoB、Mac 移植、原生库和字体许可、版本及对应源码获取方式。

如有来源、署名或权利问题，请在仓库提交只涉及相关条目的 Issue。项目可独立维护和分发 MIT 适配代码；包含第三方数据的发行包受各自条款约束。

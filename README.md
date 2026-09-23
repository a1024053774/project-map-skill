# Project Map Skill

一个面向长期项目的本地 Markdown 项目地图 Skill。它让每次会话都能低成本地回答三个问题：项目要去哪里、已经决定了什么、下一步能做什么；同时防止关键文档悄悄过时。

## 设计要点

- **地图只做索引**：`MAP.md` 每项一行并链接到细节所在处，上限 150 行。超出说明细节漏进了索引。
- **每个事实只存一处**：决定写在对应的票据里，行为以代码和描述它的活文档为准，其他地方只放链接。
- **文件写当前状态，历史交给 git**：地图和活文档不追加变更记录；被取代的内容直接删除，或移入 `archive/` 并注明替代者。
- **状态是数据**：票据的状态、阻塞和认领都写在 frontmatter 里，frontier 由脚本计算，不靠手工维护。

## 文档过时怎么防

文档分两类：

| 类型 | 例子 | 规则 |
| --- | --- | --- |
| 活文档 | README、架构说明、API 文档、运行手册、`AGENTS.md` | 登记在地图里并写明 `covers`（哪些路径变了会让它失效），必须与代码一致 |
| 记录 | 会议纪要、调研报告、带日期的计划 | 标日期，不再更新；不用时移入 `archive/` |

`scripts/project_map.py status` 会报告过时的活文档：

- 某个活文档最后一次提交之后，它 `covers` 的路径又有提交改动；
- 工作区改了它 `covers` 的路径，但没有同时改这份文档；
- `covers` 写错、一个文件都匹配不到（避免检查形同虚设）。

改动完成前先运行 `status`：过时的文档要么更新，要么在确认不受影响后把 *Verified* 列填成当前提交。没有 git 的项目改为比较修改时间。

## 闭环

同一类问题（bug、复审发现或事故）第二次出现时，只修这一次还不够：开一张 `task` 票，把能预防它的规则写进项目的 `AGENTS.md`（或负责该领域的活文档），并在票据结论里链接这条规则。`AGENTS.md` 也登记为活文档，规则本身同样接受过时检查。规则只放在这里，不另建台账。

## 目录

```text
.project-map/
  MAP.md                     # 目的地、已做决定、迷雾、范围外、活文档
  tickets/T-001-<slug>.md    # 一张票据一个文件，关闭后就是决定记录
  archive/                   # 被取代或退役的内容，默认不读
```

票据类型沿用 [grilling](https://github.com/a1024053774/grilling-skill)：`decide`、`compare`、`prototype` 由用户拍板，`research` 由 Agent 查实，`task` 是做决定前的准备工作，`build` 是实现工作，关闭时必须附证据。

## 使用

```bash
python3 project-map/scripts/project_map.py init --root <项目根>
python3 project-map/scripts/project_map.py status --root <项目根>
```

`status` 在有结构问题或过时活文档时返回非零，可以接进 hook 或 CI。

## 设计依据

地图、迷雾（Not yet specified）、范围外、认领和 frontier 参考 Matt Pocock 的 [wayfinder](https://github.com/mattpocock/skills/blob/main/skills/engineering/wayfinder/SKILL.md)，改为本地 Markdown，并增加活文档过时检查。

## License

MIT

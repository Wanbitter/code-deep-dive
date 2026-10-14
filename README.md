# code-deep-dive

一个可分发的中文代码深读 skill：逐模块读一个代码库，产出分章节 Markdown 文档——模块职责与原理、逐段代码剖析、Mermaid 数据流向图与易错点、带投入产出评估的优化建议、源码与建议写法并排对比。

**它不依赖任何 MCP server 也能用**：没有代码分析 MCP 工具时，流程走降级路径（glob/grep + 逐段读源码），结论统一标成"推测"档；接上 MCP 后同样的流程能拿到"已验证"档证据。MCP 是加速器，不是前置条件。

```
.
├── code-deep-dive/            # skill 本体（自包含，可单独拷走）
│   ├── SKILL.md
│   ├── references/            # mcp-selection / module-template / output-checklist
│   ├── assets/                # 一份完整模块文档样例
│   └── scripts/               # 跨平台安装与自检：setup-mcp.ps1 / setup-mcp.sh / verify-mcp.py
├── cordis.patch.yml           # DSH bundle patch：注册 skill 目录 + 可选接上 MCP
├── package.json               # bundle 清单（name / version / dsh.bundle.patch）
├── README.md
├── LICENSE                    # MIT
└── .gitignore
```

## 安装

### 方式一：拷进 skills 目录（最简单，任何 DSH 都适用）

把 `code-deep-dive/` 整个目录放到任一被扫描的 skill 根目录下：

| 作用域 | 路径 |
|---|---|
| 当前项目 | `<项目>/.agents/skills/code-deep-dive/` |
| 当前项目（DSH 专用） | `<项目>/.dsh/skills/code-deep-dive/` |
| 当前用户 | `~/.agents/skills/code-deep-dive/`（Windows：`C:\Users\<你>\.agents\skills\`） |
| 当前用户（DSH 专用） | `$DSH_HOME/skills/code-deep-dive/` |

skill 目录会被热加载，不需要重启；拷完直接说"用 code-deep-dive 分析这个项目"即可。

### 方式二：作为 DSH bundle 安装

这是一个**纯配置型 bundle**：不含任何 Host/Client 代码，只靠一个 patch 文件把 skill 注册进扫描根，并可选地接上 MCP。它**不声明任何 npm 依赖**——patch 里引用的 `@deepseek-ai/dsh-skill-filesystem` 和 `@deepseek-ai/dsh-mcp-client` 都随 DSH 发行版提供，解析得到。

把仓库下载或克隆到本地，然后在会话里：

```
plugin_manager   action: install_bundle   target: <本目录的绝对路径>
```

`install_bundle` 会自己完成包安装与 bundle 激活，**不要**手工改 profile 的 `package.json` 或 `cordis.patch.yml`——DSH 文档把这列为禁止做法（手工改还需更宽的写权限）。

装好后它做两件事：

1. **注册 skill 目录**——覆盖 `skill-filesystem` 的 `customSkillDirs`，把自己的包根加进去。skill 的扫描规则是 `<root>/<name>/SKILL.md`，所以包根一注册，`code-deep-dive/SKILL.md` 就能被发现。
   注意这个覆盖会**替换整行 config**，patch 里已经重述了官方那条目录；如果你的 profile 自定义过那一行（例如改了 `includeDefaultRoots`），需要把等价配置补进 `cordis.patch.yml`。
2. **可选地接上 repodigest MCP**——路径按 `$DSH_HOME`（默认 `~/.dsh`）与平台现算，指向 `scripts/setup-mcp.*` 建出来的 venv。没跑过安装脚本时这条连接会失败、工具不出现，但 profile 照常加载（`failOnStartupError` 默认 `false`），skill 走降级路径。

**卸载**：用 `plugin_manager` 的 `remove_bundle`（或 `set_bundle` 关掉），再删掉 venv 目录即可。

**前提（重要）**：这条路径要求你的 DSH **开放了插件安装**。实测：**Desktop 版（Electron 应用）默认把安装工具关掉**——它的 profile 配置里写着

```yaml
- id: tool-plugin-manager
  name: '@deepseek-ai/dsh-plugin-manager/tools'
  disabled: true          # 顶层直接禁用
```

而且安装服务本身也受 `profileContext` 门控。所以在 Desktop 版里，会话里不会出现 `plugin_manager` 工具，界面上的插件页背后也没有服务可用——**这不是本包的问题，是应用自有的 profile 不开放这个能力**。

Desktop 用户请直接走**方式一**（拷目录），效果完全一样：skill 的注册只取决于它出现在某个被扫描的根目录里。用 CLI profile（`web` / `headless` / 自定义 profile）的用户才用得上方式二。

### 方式三：其他宿主

`SKILL.md` 就是常规的 skill 文件（frontmatter 只有 `name` + `description`，无宿主专有字段）。Claude Code / Codex 之类的宿主按各自的 skill 目录约定放置即可，正文里的宿主工具名按该宿主替换（见下）。

## 可选：接上 MCP 代码分析 server

装上之后，符号签名、调用图、数据流这些事实来自 MCP 工具而不是猜；本文档的 `references/mcp-selection.md` 是选型与调用手册。

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File code-deep-dive\scripts\setup-mcp.ps1
powershell -ExecutionPolicy Bypass -File code-deep-dive\scripts\setup-mcp.ps1 -Server codegraph
```
```bash
# macOS / Linux
bash code-deep-dive/scripts/setup-mcp.sh
bash code-deep-dive/scripts/setup-mcp.sh --server codegraph
```

脚本会：找 Python（repodigest ≥3.10，codegraph ≥3.11）→ 在 `$DSH_HOME/mcp-envs/<server>`（默认 `~/.dsh/mcp-envs/`）建独立 venv → 装包 → 用 `scripts/verify-mcp.py` 做一次真实 MCP 握手自检 → **打印可直接粘贴的配置**。

每台 server 装进**各自的** venv 不是洁癖，是必需：repodigest 要求 `mcp>=2`，而 `codegraph-mcp-server` 0.8.0 调用 `Server.list_tools`（mcp 2.x 已移除该方法），必须钉在 `mcp<2`——两者放同一个环境必然有一台起不来。脚本已替你钉好。

打印出来的配置里带 `env: PYTHONUTF8: '1'`，**别删**：server 用进程 locale 的编码读 `.py` 文件，非 UTF-8 locale（中文 Windows 是 cp936）下文件里只要有一个非 ASCII 字符，索引就整棵变空，工具却报 `No Python symbols found`——把"读不了文件"伪装成"代码里没有符号"。

它**不写任何配置文件**，路径由你贴。自检不过就退出码非 0，不会让你接到一个坏 server。

可选参数：`-Python <路径>`（指定解释器）、`-IndexUrl <镜像>`（默认走你本机 pip 配置的镜像）、`-VenvRoot <目录>`。

### 平台支持

| server | 包 | 语言 | Windows | macOS/Linux |
|---|---|---|---|---|
| repodigest | `repodigest-mcp` (PyPI) | Python | ✅ | ✅ |
| codegraph | `codegraph-mcp-server` (PyPI) | 16 种 | ✅ | ✅ |
| grafema | `@grafema/mcp` (npm) | 多语言 | ❌ 只有 darwin/linux 平台二进制 | ✅ |

grafema 在 Windows 上装不起来，数据流能力在 Windows 只能走降级路径。`codegraph` 的 `--repo` 绑定在启动参数上，所以每个项目一条配置，且要先 `codegraph-mcp index <项目> --full`——它把索引写进被索引目录下的 `.codegraph/`，别对着 skill 目录跑。

### 接完怎么确认

看日志或工具列表里出现 `mcp__<serverName>__<tool>`，然后调一次只读工具（如 `get_symbol_signature`）能返回结果。DSH 上保存 `cordis.patch.yml` 会**就地重连**，不必重启。

## 前置条件

- 读代码不需要任何依赖。
- 用 MCP 才需要 Python ≥3.10（repodigest）或 ≥3.11（codegraph）。
- 网络只在安装时和 repodigest 首次调用 `pack_task_context`（下载 tiktoken 词表并缓存）时需要。

## 宿主差异

正文里写的是能力而不是专有工具名，但对照表如下：

| skill 里的说法 | DSH | Claude Code |
|---|---|---|
| 读 / 搜 / 写文件 | `read` / `grep` / `glob` / `write` | `Read` / `Grep` / `Glob` / `Write` |
| 并行派发子代理 | `subagent`（批量多阶段 `workflow`） | `Task` |
| MCP 工具名前缀 | `mcp__<serverName>__<tool>` | 同名规则 |

## 验证范围（已知限制）

写清楚哪些验证过、哪些没有，免得你踩坑时以为是自己的问题：

| 项 | 状态 |
|---|---|
| Windows 上从零安装两个 server + 真机自检 | ✅ 实测（全新 venv、带空格的路径都跑过） |
| Python 项目端到端跑通（含中文注释的代码） | ✅ 实测 |
| C++ 项目端到端跑通（结构分析 + 落盘文档） | ✅ 实测 |
| macOS / Linux 安装脚本 | ⚠️ 只做过语法检查（`bash -n`），**没在真机上跑过** |
| bundle 实际安装（`install_bundle`） | ❌ **在 Desktop 版上装不了**，已查明原因：Desktop profile 顶层把 `tool-plugin-manager` 设为 `disabled: true`，安装服务又受 `profileContext` 门控（详见[方式二的前提](#方式二作为-dsh-bundle-安装)）。patch 的 YAML 结构、目录注册表达式的解析都用真实 node 验证过，但**从来没有在真正开放的 profile 上装成功过**——CLI profile 上是否可行未验证 |
| grafema 的数据流工具 | ⚠️ 参数表里留了 5 处 `<按 server 实际 schema>` 占位。没连上那台 server 之前不编造参数 |
| 第二个人独立安装 | ❌ 没有。目前只有作者和 AI 用过 |

## 第三方依赖

skill 本体不依赖任何第三方代码。MCP 部分调用的是别人的开源项目：

- [repodigest-mcp](https://pypi.org/project/repodigest-mcp/)（MIT）— Python 符号签名、调用图、预算打包
- [codegraph-mcp-server](https://pypi.org/project/codegraph-mcp-server/)（MIT）— 16 种语言的结构与调用图
- [@grafema/mcp](https://www.npmjs.com/package/@grafema/mcp)（FSL-1.1-Apache-2.0）— 多语言数据流

本项目与它们没有隶属关系；使用前请各自阅读其许可证。

## 维护须知

`cordis.patch.yml` 靠**包名**定位自己的目录：

```yaml
- !!js ...createRequire(baseUrl).resolve('code-deep-dive-skill/package.json')
```

所以**改 `package.json` 里的 `name` 时，必须同步改这一行**，否则安装后 skill 目录注册不上。同理 `serverName` 决定 MCP 工具名前缀（`mcp__repodigest__*`），改它会让已有分析记录和权限规则里的工具名失配。

## 许可

MIT，见 [LICENSE](LICENSE)。

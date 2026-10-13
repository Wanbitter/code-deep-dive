# code-deep-dive

一个可分发的中文代码深读 skill：逐模块读一个代码库，产出分章节 Markdown 文档——模块职责与原理、逐段代码剖析、Mermaid 数据流向图与易错点、带投入产出评估的优化建议、源码与建议写法并排对比。

**它不依赖任何 MCP server 也能用**：没有代码分析 MCP 工具时，流程走降级路径（glob/grep + 逐段读源码），结论统一标成"推测"档；接上 MCP 后同样的流程能拿到"已验证"档证据。MCP 是加速器，不是前置条件。

```
code-deep-dive-skill/
├── code-deep-dive/            # skill 本体（自包含，可单独拷走）
│   ├── SKILL.md
│   ├── references/            # mcp-selection / module-template / output-checklist
│   ├── assets/                # 一份完整模块文档样例
│   └── scripts/               # 跨平台安装与自检
├── cordis.patch.yml           # DSH bundle patch
├── package.json               # DSH bundle 清单
└── LICENSE
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

`package.json` 声明了 `dsh.bundle.patch`，所以它可以作为一个组合包安装。安装后它会做两件事：把自带的 skill 目录注册进 skill 扫描根（`cordis.patch.yml` 里覆盖 `skill-filesystem` 的 `customSkillDirs`），并可选地接上 repodigest MCP。

用 DSH 自带的插件管理能力安装（会话里有 `plugin_manager` 时可让其执行 `install_bundle`），或手动把本目录放进 profile 的依赖里再选上这个 bundle。

两点注意：
- `plugin_manager` 只在宿主提供可编辑 profile 时才启用；Desktop profile 是应用自有的，如果你的会话里没有这个工具，就走**方式一**（拷目录），效果一样。
- 覆盖 `skill-filesystem` 会**替换整行 config**，所以 patch 里重述了官方那条 skill 目录。你若自定义过那一行（比如改了 `includeDefaultRoots`），记得把等价配置一起补进 `cordis.patch.yml`。

手工改 profile 配置需要更宽的写权限。

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

## 许可

MIT，见 [LICENSE](LICENSE)。

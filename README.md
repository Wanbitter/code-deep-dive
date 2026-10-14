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
├── package.json               # 可选：给开放插件安装的 DSH CLI profile 用
├── cordis.patch.yml           # 可选：同上
├── README.md
├── LICENSE                    # MIT
└── .gitignore
```

## 安装

把 `code-deep-dive/` 整个目录放进任一被扫描的 skill 根目录即可：

| 作用域 | 路径 |
|---|---|
| 当前项目 | `<项目>/.agents/skills/code-deep-dive/` |
| 当前项目（DSH 专用） | `<项目>/.dsh/skills/code-deep-dive/` |
| 当前用户 | `~/.agents/skills/code-deep-dive/`（Windows：`C:\Users\<你>\.agents\skills\`） |
| 当前用户（DSH 专用） | `$DSH_HOME/skills/code-deep-dive/` |

skill 目录会被热加载，不需要重启；拷完直接说"用 code-deep-dive 分析这个项目"即可，说"分析一下这个项目""讲讲数据怎么流"这类话也会命中。

**其他宿主**：`SKILL.md` 是常规 skill 文件（frontmatter 只有 `name` + `description`，无宿主专有字段）。Claude Code / Codex 之类按各自的 skill 目录约定放置即可，正文里的宿主工具名按该宿主替换（见下方对照表）。

## 可选：接上 MCP 代码分析 server

接上之后，符号签名、调用图、数据流这些事实来自 MCP 工具而不是猜。选型与调用手册在 `code-deep-dive/references/mcp-selection.md`。

### 1. 装 server

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

脚本做四件事：找 Python（repodigest ≥3.10，codegraph ≥3.11）→ 在 `$DSH_HOME/mcp-envs/<server>`（默认 `~/.dsh/mcp-envs/`）建独立 venv → 装包 → 用 `scripts/verify-mcp.py` 做一次真实 MCP 握手自检，最后**打印可直接粘贴的配置**。自检不过就退出码非 0；它不写任何配置文件。

可选参数：`-Python <路径>`、`-IndexUrl <镜像>`（默认走你本机 pip 配置的镜像）、`-VenvRoot <目录>`。

### 2. 把配置贴进去

脚本打印的是一个 `- insert:` 块，粘到 DSH profile 的 patch 文件末尾（Desktop 版：`~/.dsh/profiles/desktop/cordis.patch.yml`），保存即热加载、就地重连，不用重启。

```yaml
- insert:
    - id: mcp-repodigest
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: repodigest
        transport: stdio
        command: '<脚本打印的绝对路径>'
        args: []
        env:
          PYTHONUTF8: '1'
```

### 3. 两处别改坏

- **每台 server 各用一个 venv**：repodigest 要求 `mcp>=2`，而 `codegraph-mcp-server` 0.8.0 调用 `Server.list_tools`（mcp 2.x 已移除该方法），必须钉在 `mcp<2`。放同一个环境必然有一台起不来，脚本已按此钉好。
- **`env: PYTHONUTF8: '1'` 别删**：server 用进程 locale 的编码读 `.py` 文件，非 UTF-8 locale（中文 Windows 是 cp936）下文件里只要有一个非 ASCII 字符，索引就整棵变空，工具却报 `No Python symbols found`——把"读不了文件"伪装成"代码里没有符号"。

### 4. 平台支持

| server | 包 | 语言 | Windows | macOS/Linux |
|---|---|---|---|---|
| repodigest | `repodigest-mcp` (PyPI) | Python | ✅ | ✅ |
| codegraph | `codegraph-mcp-server` (PyPI) | 16 种 | ✅ | ✅ |
| grafema | `@grafema/mcp` (npm) | 多语言 | ❌ 只有 darwin/linux 平台二进制 | ✅ |

`codegraph` 的 `--repo` 绑定在启动参数上，所以每个项目一条配置，且要先 `codegraph-mcp index <项目> --full`——索引写进被索引目录下的 `.codegraph/`，别对着 skill 目录跑。

### 5. 接完怎么确认

工具列表里出现 `mcp__<serverName>__<tool>`，调一次只读工具（如 `get_symbol_signature`）能返回结果即可。

## 前置条件

- 读代码本身不需要任何依赖。
- 用 MCP 才需要 Python ≥3.10（repodigest）或 ≥3.11（codegraph）。
- 网络只在安装 server 时、以及 repodigest 首次调用 `pack_task_context`（下载 tiktoken 词表并缓存）时需要。

## 宿主差异

正文里写的是能力而不是专有工具名：

| skill 里的说法 | DSH | Claude Code |
|---|---|---|
| 读 / 搜 / 写文件 | `read` / `grep` / `glob` / `write` | `Read` / `Grep` / `Glob` / `Write` |
| 并行派发子代理 | `subagent`（批量多阶段 `workflow`） | `Task` |
| MCP 工具名前缀 | `mcp__<serverName>__<tool>` | 同名规则 |

## 已知限制

- **codegraph 的调用图在 C++ 上可能为空**：实测 `find_callers` / `find_callees` 对 C++ 函数无返回；结构分析（实体、行号、社区）正常。查调用关系时改用 `analyze_module_structure` + 读源码。另外 `get_file_structure` 实测对某些文件返回空实体，`analyze_module_structure` 正常。
- **macOS / Linux 安装脚本只做过语法检查**（`bash -n`），未在真机运行过。
- **grafema 参数表**有 5 处 `<按 server 实际 schema>` 占位：连上那台 server 之前不编造参数，届时按实际 schema 补。
- **Windows 上没有数据流**：grafema 无 win32 平台二进制，该能力只能用读源码的方式替代。

## 第三方依赖

skill 本体不依赖任何第三方代码。MCP 部分调用的是别人的开源项目：

- [repodigest-mcp](https://pypi.org/project/repodigest-mcp/)（MIT）— Python 符号签名、调用图、预算打包
- [codegraph-mcp-server](https://pypi.org/project/codegraph-mcp-server/)（MIT）— 16 种语言的结构与调用图
- [@grafema/mcp](https://www.npmjs.com/package/@grafema/mcp)（FSL-1.1-Apache-2.0）— 多语言数据流

本项目与它们没有隶属关系；使用前请各自阅读其许可证。

## 维护须知

- `serverName` 决定 MCP 工具名前缀（`mcp__repodigest__*`）。改它会让已有分析记录与权限规则里的工具名失配。
- 若改用 `package.json` / `cordis.patch.yml` 走插件安装，`cordis.patch.yml` 靠包名定位自己的目录（`createRequire(baseUrl).resolve('code-deep-dive-skill/package.json')`），改 `package.json` 的 `name` 时必须同步改这一行。

## 许可

MIT，见 [LICENSE](LICENSE)。

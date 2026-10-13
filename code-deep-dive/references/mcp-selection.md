# MCP 选型与调用

本文件是 `code-deep-dive` 的事实源手册。工作流用到的每个工具、参数、已知限制与降级路径都在这里。工具名与参数以本文件为准；某一项在 server 自述里查不到时，写 `<MCP工具名>` 占位并说明用途，不要编造。

## repodigest-mcp（Python）— 默认事实源

| 工具 | 参数 | 作用与已知限制 |
|------|------|---------------|
| `get_symbol_signature` | `symbol_name`（限定名或点号后缀）、`path` | 返回签名与 docstring，不含函数体。取签名比读文件便宜得多 |
| `get_symbol_dependencies` | `symbol_name`、`path` | 返回直接调用方与被调用方。**边按简单名匹配，不做 import 与类型解析**，`get`、`run` 这类通用名会误报。拿到结果后必须回源码核对 |
| `pack_task_context` | `query`（自然语言任务）、`budget`（token 上限）、`signatures_only`、`path` | 按 BM25 排序取最相关符号为根，再按调用关系做广度扩展。**放不下就整块跳过，不截断**，所以预算内可能缺关键符号。给约 10% 余量 |

这个 Server 只覆盖 Python。非 Python 项目改用下两个。

## grafema-mcp（多语言）— 数据流事实源

| 工具 | 参数 | 作用 |
|------|------|------|
| `trace_dataflow` | `source`、`file`、`direction`（`forward`/`backward`/`both`）、`max_depth`（默认 10）、`limit`、`detail` | 沿 `ASSIGNED_FROM`、`PASSES_ARGUMENT`、`FLOWS_INTO` 追踪值的来源与去向。数据流向图的主证据 |
| `trace_calls` | `<按 server 实际 schema>` | 调用链 |
| `trace_effects` | `<按 server 实际 schema>` | 副作用边界，用于定位出网与写库 |
| `find_guards` | `<按 server 实际 schema>` | 分支与守卫，用于标条件级易错点 |
| `explain` | `<按 server 实际 schema>` | 让 graph 自己解释某条事实的推导过程，用于校验结论 |
| `semantic_search` | `<按 server 实际 schema>` | **目前是节点名的大小写不敏感子串匹配，不是向量检索**，不要把它当语义相似度使用 |
| `get_function_details`、`get_file_overview` | `<按 server 实际 schema>` | 补齐结构信息 |
| 不变量检查类工具（如 `<按 server 实际 schema 补>`） | 按 server 自述的 schema 使用 | 无对应工具时走降级路径，结论标"推测" |

调用前先读一次该 server 公布的 schema，并按安装版本核对工具是否可用。

## CodeGraphMCPServer（16 种语言）— 结构与调用图事实源

| 工具 | 主要参数 | 作用 |
|------|---------|------|
| `query_codebase` | `query`、`max_results` | 自然语言检索代码图 |
| `analyze_module_structure` | `file_path` | 模块结构（阶段一用） |
| `find_dependencies` | `entity_id`、`depth` | 依赖半径 |
| `find_callers` / `find_callees` | `entity_id` | 调用图上下行 |
| `find_implementations` | `entity_id` | 接口与实现 |
| `get_code_snippet` | `entity_id`、`include_context` | 实体源码与上下文 |
| `get_file_structure`、`read_file_content` | `file_path`、`start_line`、`end_line` | 原文与结构 |
| `global_search` / `local_search` | `query`（`local_search` 另需 `entity_id`） | 全局概览与邻域检索 |
| `suggest_refactoring` | `entity_id`、`type` | 重构候选，只作为线索，结论仍要自己判断 |
| `reindex_repository` | `incremental` | 重建索引 |
| `execute_shell_command` | `command`、`timeout` | 该 server 自带。本 skill 不用它，需要命令时走宿主工具 |

## 选型表

| 需求 | 首选 | 回退 |
|------|------|------|
| Python 符号签名与调用关系 | repodigest-mcp | CodeGraphMCPServer |
| 数据流与污点追踪 | grafema-mcp `trace_dataflow` | CodeGraphMCPServer `find_callers`+`find_callees` 手工推链，并在文档里标"无 MCP 数据流证据" |
| 非 Python 结构 | CodeGraphMCPServer | `get_file_structure` + 读原文 |
| 跨服务追踪 | grafema-mcp | `<MCP工具名>`，按可用工具补 |

## 在 DSH 上接入

每台 server 一条 `@deepseek-ai/dsh-mcp-client` 条目，写进 profile 的 `cordis.patch.yml`。两处写错会让条目**被静默忽略**（只在 stderr 留一条警告，界面上看不出问题）：

- **字段嵌在 `config:` 下**，不要与 `name` 平级。
- **新增的行必须包在 `- insert:` 里**。平级写 `- id: xxx` 只用于**覆盖已存在**的行（比如改内置插件的配置）；`id` 在配置层里找不到对应行时，DSH 只打一条警告就跳过。

```yaml
- insert:
    - id: mcp-repodigest
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: repodigest
        transport: stdio
        command: '<脚本打印出来的绝对路径>'
        args: []
        env:
          PYTHONUTF8: '1'   # 见下节：不设它，非 ASCII 源码会让索引变空
```

`transport: stdio` 用 `command` / `args` / `env` / `cwd`，`transport: streamable-http` 用 `url` / `headers`；`serverName` 决定工具名前缀（形如 `mcp__repodigest__get_symbol_signature`），同一注册作用域内必须唯一。

### 必须设 `PYTHONUTF8=1`（Windows 中文环境是高危项）

repodigest 读 `.py` 文件时用的是 `Path.read_text()` 的**缺省编码**，也就是进程 locale。中文 Windows 上是 `cp936`；文件里只要有一个非 ASCII 字符（中文注释、em dash `—`、带重音的名字），读取就抛 `UnicodeDecodeError`，**整棵树的索引变空**，而工具只回一句 `No Python symbols found`——把"读不了文件"误报成"代码里没有符号"。

实测（同一文件、只差一个字符）：

| 文件内容 | 工具返回 |
|---------|---------|
| 纯 ASCII docstring | 正常返回签名 |
| 同一个文件，docstring 加一个 `—` | `No Python symbols found under ...` |
| 同一个文件，docstring 改成中文 | `No Python symbols found under ...` |

验证命令与结论：该 venv 里 `locale.getpreferredencoding(False)` = `cp936`、`sys.flags.utf8_mode` = `0`；给 MCP 条目加 `PYTHONUTF8: '1'` 后三个目标全部正常（中文原样输出）。所以**配置里那一行 env 不是可选项**，`scripts/setup-mcp.*` 打印的配置块已默认带上。

排查同类问题的判据：`No Python symbols found` / `No symbols matched query` 出现在一个明显有代码的目录上时，先怀疑编码（`PYTHONUTF8`），再怀疑路径被索引器剪枝（`site-packages`、`node_modules`、隐藏目录、含 `pyvenv.cfg` 的目录都会被跳过，**路径里带这些名字连根目录自己也会被跳过**）。

### 安装与自检（跨平台，别手搓路径）

本 skill 自带脚本，一次做完建 venv、装包、握手自检、打印填好路径的配置：

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File <skill目录>\scripts\setup-mcp.ps1
powershell -ExecutionPolicy Bypass -File <skill目录>\scripts\setup-mcp.ps1 -Server codegraph
```
```bash
# macOS / Linux
bash <skill目录>/scripts/setup-mcp.sh
bash <skill目录>/scripts/setup-mcp.sh --server codegraph
```

venv 落在 `$DSH_HOME/mcp-envs/<server>`（未设 `DSH_HOME` 时是 `~/.dsh/mcp-envs/`）。`command` 用脚本打印的 console script 绝对路径：Windows 是 `...\Scripts\repodigest-mcp.exe`，POSIX 是 `.../bin/repodigest-mcp`。脚本**只打印配置、不写文件**，所以贴之前先确认自检全 PASS。

**先探查再安装**：会话里已经有 `mcp__repodigest__*` 工具就直接用，不要重复建 venv。自检不通过时不要接——`verify-mcp.py` 会指出是哪一步（握手、工具列表、还是工具调用）失败。

首次调用 `pack_task_context` 会联网取一次 tiktoken 词表并缓存；离线时另两个工具照常可用。

### 其余 server 的可用性

- `@grafema/mcp`（npm）：0.3.x 的平台二进制只有 `darwin-arm64` / `darwin-x64` / `linux-arm64` / `linux-x64`，**没有 win32**——Windows 上装不起来，数据流能力只能走降级路径。
- `codegraph-mcp-server`（PyPI，Python 3.11+，16 种语言）：非 Python 项目的结构事实源。装完先 `codegraph-mcp index <项目> --full` 再 `codegraph-mcp serve --repo <项目>`；`--repo` 固定在启动参数上，所以**每个项目一条配置**，索引写在被索引目录下的 `.codegraph/`（别对着 skill 目录跑）。**它必须和 `mcp<2` 一起装**：0.8.0 声明 `mcp>=1.0.0` 却调用 mcp 2.x 已移除的 `Server.list_tools`，同环境里装了 `mcp 2.x` 会启动即崩（`'Server' object has no attribute 'list_tools'`）——这正是每台 server 各用一个 venv 的原因，`scripts/setup-mcp.*` 已按此钉好。`global_search` / `local_search` 走 GraphRAG，可能需要在 server 侧配 LLM provider，拿不到结果就按降级处理。

### 生效与验证

DSH 启用 HMR 时会监视 profile 的 `cordis.patch.yml`，保存后**就地重连**，不必重启 harness。验证方式：调一次只读工具（如 `get_symbol_signature`）能返回结果；也可以看进程列表里有没有那个 console script。

调用时的参数规则：**`path` 显式传**。它默认取 server 的工作目录，也就是 harness 进程的 cwd，会随会话工作区变化，不传就可能分析错目录。Windows 上 `npx` 这类 `.cmd` shim 可以写（传输层用 cross-spawn 启动，会解析 shim）；子进程拿到的是清洗过的父环境（丢掉凭据形状的变量与 `DSH_*`），PATH 来自父进程，**工具不在 PATH 里时只能写绝对路径**。

其余可选字段（默认值一般不用改）：`toolCallTimeoutMs` 默认 `60000`；`maxInstructionBytes` 默认 `32768`，server 自述超过这个字节数会直接拒绝连接；`failOnStartupError` 默认 `false`；`reconnect.enabled` 默认 `true`，退避从 `500ms` 翻倍到 `30s`，连续失败 `10` 次后移除该 server 的工具。

宿主不是 DSH 时，按该宿主的 MCP 配置格式写等价条目，本文其余部分不变。

## 降级路径

某项能力没有对应工具时，只有该项走降级路径，其余能力正常走 MCP：

- 结构：无结构工具时，用宿主 glob + grep + 读原文。
- 调用关系：无调用图时，用 grep 搜符号名，结果标"推测（无 MCP 调用图）"。
- 数据流：无 `trace_dataflow` 时，逐段读源码跟踪赋值与参数传递，图上的边标"推测"。
- 数据流向图照画：实线仍要对得上源码位置（标 `file:line`）；靠读源码推出的边，在图下方的依据说明里写明"推测，来自逐段读源码"；虚线只用于"可能出错"，按模板要求只标错误形态。

交付文档开头声明本次哪些能力走了降级。

## 工具账本

**阶段三校验时回填，不需要在分析过程中实时逐条记账。** 校验时按章节回查"这条结论是哪次调用支撑的"，把支撑不上的结论降到"推测"档或补一次调用。

| 序号 | 工具 | 参数 | 返回要点 | 用于哪一章 | 是否已核对原文 |
|------|------|------|---------|-----------|---------------|
| 1 | `get_symbol_signature` | `order_service.create` | 签名与 3 个副作用 | 第一章 | 是 |

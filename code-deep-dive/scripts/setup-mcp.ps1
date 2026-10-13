#Requires -Version 5.1
<#
.SYNOPSIS
  Install and self-test an optional MCP code-analysis server for the
  code-deep-dive skill.

.DESCRIPTION
  Creates an isolated virtualenv per server, installs the server package into
  it, runs scripts/verify-mcp.py against the installed console script, and
  prints ready-to-paste configuration for DSH and for JSON-based MCP clients.

  This script never edits any configuration file. It prints the block; you
  decide where it goes.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File setup-mcp.ps1
  powershell -ExecutionPolicy Bypass -File setup-mcp.ps1 -Server codegraph
  powershell -ExecutionPolicy Bypass -File setup-mcp.ps1 -IndexUrl https://pypi.tuna.tsinghua.edu.cn/simple
#>
[CmdletBinding()]
param(
    # Which server to install.
    [ValidateSet('repodigest', 'codegraph')]
    [string]$Server = 'repodigest',

    # Python interpreter to build the virtualenv from. Auto-detected when empty.
    [string]$Python = '',

    # Override the package index (useful behind a slow or blocked default).
    [string]$IndexUrl = '',

    # Where virtualenvs live. Defaults to <DSH_HOME>/mcp-envs.
    [string]$VenvRoot = ''
)

$ErrorActionPreference = 'Stop'

$servers = @{
    repodigest = @{
        Package     = 'repodigest-mcp'
        Exe         = 'repodigest-mcp.exe'
        MinPython   = '3.10'
        Expect      = 'get_symbol_signature,get_symbol_dependencies,pack_task_context'
        Args        = @()
        Pins        = @()
        NeedsRepo   = $false
        Notes       = @()
    }
    codegraph = @{
        Package     = 'codegraph-mcp-server'
        Exe         = 'codegraph-mcp.exe'
        MinPython   = '3.11'
        Expect      = 'analyze_module_structure,find_callers,find_callees,get_code_snippet,find_dependencies'
        Args        = @('serve', '--repo', '<PROJECT_ROOT>')
        # codegraph-mcp-server 0.8.0 declares mcp>=1.0.0 but calls
        # Server.list_tools, which mcp 2.x removed, so it dies on startup with
        # "'Server' object has no attribute 'list_tools'". Pin the 1.x line it
        # was written against.
        Pins        = @('mcp<2')
        NeedsRepo   = $true
        Notes       = @(
            'Bind one entry per project: --repo is fixed at startup.',
            'Index the project first:  codegraph-mcp index <PROJECT_ROOT> --full',
            'global_search / local_search use GraphRAG and may need an LLM provider configured on the server side.'
        )
    }
}

$spec = $servers[$Server]

function Write-Section([string]$title) {
    Write-Host ''
    Write-Host "=== $title ===" -ForegroundColor Cyan
}

function Test-PythonVersion {
    param([string]$File, [string[]]$Prefix)

    # No embedded quotes in this expression: Windows PowerShell 5.1 does not
    # escape double quotes when passing arguments to native commands, so a
    # quoted Python snippet arrives mangled.
    $probeArgs = @($Prefix) + @('-c', 'import sys;print(sys.version_info[0],sys.version_info[1])')
    try {
        $raw = & $File @probeArgs 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $raw) { return $null }
        $first = @($raw)[0]
        if ($null -eq $first) { return $null }
        $parts = ("$first".Trim() -split '\s+')
        if ($parts.Count -lt 2) { return $null }
        return [version]("{0}.{1}" -f $parts[0], $parts[1])
    }
    catch {
        return $null
    }
}

function Find-Python {
    param([string]$Explicit, [string]$MinVersion)

    $want = [version]$MinVersion
    $minMinor = [int]($MinVersion.Split('.')[1])
    $candidates = New-Object System.Collections.Generic.List[object]

    if ($Explicit) { $candidates.Add(@{ File = $Explicit; Prefix = @() }) }

    # Interpreter already on PATH wins: that is the one the user works with.
    foreach ($name in @('python', 'python3')) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue
        if ($cmd) { $candidates.Add(@{ File = $cmd.Source; Prefix = @() }) }
    }

    # Then the Windows py launcher, which can name a minor version directly.
    # Wheel availability for the tree-sitter family lags the newest release, so
    # try the established versions before the bleeding edge.
    if (Get-Command py -ErrorAction SilentlyContinue) {
        $ordered = @(12, 13, 11, 10, 14, 15, 16) |
            Where-Object { $_ -ge $minMinor } |
            Sort-Object -Unique
        foreach ($minor in $ordered) {
            $candidates.Add(@{ File = 'py'; Prefix = @("-3.$minor") })
        }
        $candidates.Add(@{ File = 'py'; Prefix = @('-3') })
    }

    # Well-known per-user install locations, in case PATH does not carry them.
    $roots = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
        (Join-Path $env:ProgramFiles 'Python')
    )
    foreach ($root in $roots) {
        Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object {
                $exe = Join-Path $_.FullName 'python.exe'
                if (Test-Path -LiteralPath $exe) { $candidates.Add(@{ File = $exe; Prefix = @() }) }
            }
    }

    foreach ($candidate in $candidates) {
        $found = Test-PythonVersion -File $candidate.File -Prefix $candidate.Prefix
        if ($null -eq $found) { continue }
        if ($found -ge $want) {
            return @{ File = $candidate.File; Prefix = $candidate.Prefix; Version = $found }
        }
        Write-Host ("  skipped {0} ({1} < required {2})" -f $candidate.File, $found, $MinVersion)
    }
    return $null
}

Write-Section "code-deep-dive / MCP setup: $Server"
Write-Host ("package   : {0}" -f $spec.Package)
Write-Host ("requires  : Python >= {0}" -f $spec.MinPython)

Write-Section 'locating a suitable Python'
$py = Find-Python -Explicit $Python -MinVersion $spec.MinPython
if (-not $py) {
    Write-Host ("No Python >= {0} found. Install one, or pass -Python <path>." -f $spec.MinPython) -ForegroundColor Red
    exit 1
}
Write-Host ("using     : {0} {1}" -f $py.File, $py.Version) -ForegroundColor Green

if (-not $VenvRoot) {
    $dshHome = if ($env:DSH_HOME) { $env:DSH_HOME } else { Join-Path $HOME '.dsh' }
    $VenvRoot = Join-Path $dshHome 'mcp-envs'
}
$venv = Join-Path $VenvRoot $Server
$vpy = Join-Path $venv 'Scripts\python.exe'
$exe = Join-Path $venv ('Scripts\' + $spec.Exe)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$verifier = Join-Path $scriptDir 'verify-mcp.py'
if (-not (Test-Path -LiteralPath $verifier)) {
    Write-Host ("verify-mcp.py not found next to this script: {0}" -f $verifier) -ForegroundColor Red
    exit 1
}

Write-Section 'creating the isolated virtualenv'
if (Test-Path -LiteralPath $vpy) {
    Write-Host ("reusing   : {0}" -f $venv)
}
else {
    New-Item -ItemType Directory -Force -Path $VenvRoot | Out-Null
    $venvArgs = @($py.Prefix) + @('-m', 'venv', $venv)
    & $py.File @venvArgs
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $vpy)) {
        Write-Host 'virtualenv creation failed' -ForegroundColor Red
        exit 1
    }
    Write-Host ("created   : {0}" -f $venv)
}

Write-Section 'installing the server package'
$pipArgs = @('-m', 'pip', 'install', '--disable-pip-version-check', '--no-input')
if ($IndexUrl) { $pipArgs += @('--index-url', $IndexUrl) }
$pipArgs += @($spec.Package) + @($spec.Pins)
& $vpy @pipArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host 'pip install failed' -ForegroundColor Red
    exit 1
}

Write-Section 'self-test (real MCP handshake over stdio)'
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host ("console script missing: {0}" -f $exe) -ForegroundColor Red
    exit 1
}

$verifyDir = $null
$serverArgs = @()
if ($spec.NeedsRepo) {
    # This server only starts with a repository argument, so build a throwaway
    # project, index it, and hand that path to the server. The index it writes
    # lives inside the temp directory and disappears with it.
    $verifyDir = Join-Path ([System.IO.Path]::GetTempPath()) ('mcp-verify-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $verifyDir | Out-Null
    $fixture = @'
"""Fixture written by setup-mcp."""


def load_rows(path):
    """Read rows from a file."""
    with open(path, encoding="utf-8") as handle:
        return [line.strip() for line in handle if line.strip()]


def build_store(rows):
    """Build a list from rows."""
    return list(rows)
'@
    [System.IO.File]::WriteAllText((Join-Path $verifyDir 'fixture_mod.py'), $fixture, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("indexing a throwaway project: {0}" -f $verifyDir)
    & $exe index $verifyDir --full 2>&1 | Out-Null
    $serverArgs = @('serve', '--repo', $verifyDir)
}

if ($serverArgs.Count -gt 0) {
    & $vpy $verifier --expect $spec.Expect -- $exe @serverArgs
}
else {
    & $vpy $verifier --expect $spec.Expect -- $exe
}
$verifyExit = $LASTEXITCODE

if ($verifyDir -and (Test-Path -LiteralPath $verifyDir) -and (Split-Path -Leaf $verifyDir) -like 'mcp-verify-*') {
    Remove-Item -LiteralPath $verifyDir -Recurse -Force
    Write-Host ("removed the throwaway project: {0}" -f $verifyDir)
}

Write-Section 'configuration for DSH (paste into the profile cordis.patch.yml)'
$argList = if ($spec.Args.Count -gt 0) { '[' + (($spec.Args | ForEach-Object { "'" + $_ + "'" }) -join ', ') + ']' } else { '[]' }
@"
- insert:
    - id: mcp-$Server
      name: '@deepseek-ai/dsh-mcp-client'
      config:
        serverName: $Server
        transport: stdio
        command: '$exe'
        args: $argList
        # Delete this env block only if you know your locale is UTF-8; on
        # Chinese Windows (cp936) the server cannot read .py files that contain
        # any non-ASCII character and reports 'No Python symbols found'.
        env:
          PYTHONUTF8: '1'
"@ | Write-Host

Write-Section 'configuration for JSON-based clients (Claude Code, Cursor, VS Code)'
$jsonArgs = if ($spec.Args.Count -gt 0) { '[' + (($spec.Args | ForEach-Object { '"' + $_ + '"' }) -join ', ') + ']' } else { '[]' }
@"
{
  "mcpServers": {
    "$Server": {
      "command": "$($exe -replace '\\', '\\')",
      "args": $jsonArgs,
      "env": { "PYTHONUTF8": "1" }
    }
  }
}
"@ | Write-Host

if ($spec.Notes.Count -gt 0) {
    Write-Section 'notes'
    foreach ($note in $spec.Notes) { Write-Host ("- {0}" -f $note) }
}

Write-Section 'result'
if ($verifyExit -eq 0) {
    Write-Host 'self-test passed. Paste one of the blocks above, then call a read-only tool to confirm.' -ForegroundColor Green
    exit 0
}
Write-Host 'self-test FAILED. The server is installed but did not answer correctly; do not wire it up yet.' -ForegroundColor Red
exit $verifyExit

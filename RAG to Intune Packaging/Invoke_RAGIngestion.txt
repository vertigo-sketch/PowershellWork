<#
.SYNOPSIS
  Ingests a PowerShell (and docs) library from a file share, chunks content, extracts metadata,
  and emits JSONL files for downstream embedding + vector indexing.

.DESCRIPTION
  - Recursively scans LibraryRoot for files with Extensions (default: .ps1, .psm1, .psd1, .md, .txt)
  - Excludes paths by substring/pattern
  - Supports incremental ingestion via StatePath (hash + timestamp)
  - Chunks scripts intelligently:
      * Prefer function-based chunking for .ps1/.psm1
      * Fallback to line/character chunking with overlap
  - Extracts metadata heuristically:
      * docType (template/function/standard/example)
      * installerType (msi/exe/script/unknown)
      * contextHint (system/user/unknown)
      * tags from path and content
  - Writes JSONL output:
      chunks.jsonl: each chunk record ready for embedding/index
      docs.jsonl: per-file document record

.PARAMETER LibraryRoot
  UNC path or local path to your script library.

.PARAMETER OutDir
  Output directory for JSONL and state/log files.

.PARAMETER StatePath
  State file to support incremental runs (default: OutDir\state.json).

.PARAMETER Extensions
  File extensions to ingest.

.PARAMETER ExcludePathContains
  Array of substrings; any file path containing one will be skipped.

.PARAMETER ChunkChars
  Target chunk size in characters (fallback chunker).

.PARAMETER OverlapChars
  Overlap between chunks to preserve context.

.PARAMETER MinChunkChars
  Skip tiny chunks under this size (after trimming).

.PARAMETER MaxFiles
  Optional cap for testing.

.PARAMETER WhatIf
  Dry run - scan and report without writing outputs.

.NOTES
  This script does NOT generate embeddings. It outputs JSONL for downstream embedding/indexing.
#>

[CmdletBinding(SupportsShouldProcess=$true)]
param(
  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$LibraryRoot,

  [Parameter(Mandatory)]
  [ValidateNotNullOrEmpty()]
  [string]$OutDir,

  [string]$StatePath,

  [string[]]$Extensions = @(".ps1",".psm1",".psd1",".md",".txt"),

  [string[]]$ExcludePathContains = @("\Archive\", "\Deprecated\", "\Old\", "\.git\", "\node_modules\"),

  [int]$ChunkChars = 2200,
  [int]$OverlapChars = 250,
  [int]$MinChunkChars = 250,

  [int]$MaxFiles = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ----------------------------
# Utilities
# ----------------------------

function New-Directory([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
  }
}

function Write-Log {
  param(
    [Parameter(Mandatory)][string]$Message,
    [ValidateSet("INFO","WARN","ERROR")][string]$Level="INFO"
  )
  $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $line = "$ts [$Level] $Message"
  Write-Host $line
  if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line }
}

function Get-Sha256([string]$Path) {
  $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
  return $hash.Hash.ToLowerInvariant()
}

function Read-TextFileRobust([string]$Path) {
  # Try UTF8 first, then default
  try {
    return Get-Content -LiteralPath $Path -Raw -Encoding UTF8
  } catch {
    return Get-Content -LiteralPath $Path -Raw
  }
}

function Get-RelativePath([string]$Base, [string]$Full) {
  $baseUri = [UriPath.TrimEnd('\') + '\')
  $fullUri = Uri.Path)
  return $baseUri.MakeRelativeUri($fullUri).ToString().Replace('/', '\')
}

function Should-ExcludePath([string]$FullPath, [string[]]$Exclusions) {
  foreach ($x in $Exclusions) {
    if ([string]::IsNullOrWhiteSpace($x)) { continue }
    if ($FullPath -like "*$x*") { return $true }
  }
  return $false
}

# ----------------------------
# Metadata extraction heuristics
# ----------------------------

function Infer-DocType([string]$RelativePath) {
  $p = $RelativePath.ToLowerInvariant()
  if ($p -match "\\standards\\") { return "standard" }
  if ($p -match "\\functions\\") { return "function" }
  if ($p -match "\\templates\\") { return "template" }
  if ($p -match "\\examples\\")  { return "example" }
  return "unknown"
}

function Infer-InstallerType([string]$Text, [string]$RelativePath) {
  $t = $Text.ToLowerInvariant()
  $p = $RelativePath.ToLowerInvariant()

  if ($p -match "\.msi$") { return "msi" }
  if ($t -match "\bmsiexec(\.exe)?\b") { return "msi" }

  if ($t -match "\.exe\b" -or $t -match "\bstart-process\b") { return "exe" }

  if ($p -match "\.ps1$" -or $p -match "\.psm1$") { return "script" }

  return "unknown"
}

function Infer-ContextHint([string]$Text) {
  $t = $Text.ToLowerInvariant()

  # Heuristics only (IME often runs as SYSTEM for Win32 apps, but scripts can be user-context too)
  if ($t -match "\bhklm:\b" -or $t -match "\\hklm\\" -or $t -match "\\programdata\\") { return "system" }
  if ($t -match "\bhkcu:\b" -or $t -match "\\hkcu\\" -or $t -match "\\appdata\\") { return "user" }

  return "unknown"
}

function Extract-Tags([string]$RelativePath, [string]$Text) {
  $tags = New-Object System.Collections.Generic.HashSet[string]
  $p = $RelativePath.ToLowerInvariant()
  $t = $Text.ToLowerInvariant()

  if ($p -match "\\dell\\")  { $tags.Add("Vendor:Dell")  | Out-Null }
  if ($p -match "\\adobe\\") { $tags.Add("Vendor:Adobe") | Out-Null }
  if ($p -match "\\microsoft\\") { $tags.Add("Vendor:Microsoft") | Out-Null }

  if ($t -match "\bintunewinapputil\b") { $tags.Add("Tool:IntuneWinAppUtil") | Out-Null }
  if ($t -match "\bime\b" -or $t -match "intunemanagementextension") { $tags.Add("IME") | Out-Null }

  if ($t -match "\bmsiexec(\.exe)?\b") { $tags.Add("Installer:MSI") | Out-Null }
  if ($t -match "\bstart-process\b" -and $t -match "\.exe\b") { $tags.Add("Installer:EXE") | Out-Null }

  if ($t -match "\bwrite-log\b" -or $t -match "\bstart-transcript\b") { $tags.Add("Logging") | Out-Null }

  # Intune-focused patterns
  if ($t -match "\bexecutionpolicy\b") { $tags.Add("PowerShell:ExecutionPolicy") | Out-Null }
  if ($t -match "\bexit\s+\d+") { $tags.Add("ExitCodes") | Out-Null }

  return @($tags)
}

# ----------------------------
# Chunking
# ----------------------------

function Chunk-ByFunctions([string]$Text, [int]$FallbackChunkChars, [int]$Overlap, [int]$MinSize) {
  # Split into blocks starting at "function Name" lines.
  # Keep comment-based help immediately above function as part of the function chunk.
  $lines = $Text -split "(`r`n|`n|`r)"
  $funcStarts = New-Object System.Collections.Generic.List[int]

  for ($i=0; $i -lt $lines.Length; $i++) {
    if ($lines[$i] -match '^\s*function\s+[A-Za-z0-9._-]+\s*') {
      $funcStarts.Add($i) | Out-Null
    }
  }

  if ($funcStarts.Count -eq 0) {
    return Chunk-ByChars -Text $Text -ChunkChars $FallbackChunkChars -OverlapChars $Overlap -MinChunkChars $MinSize
  }

  $chunks = New-Object System.Collections.Generic.List[string]

  for ($j=0; $j -lt $funcStarts.Count; $j++) {
    $start = $funcStarts[$j]
    $end = if ($j -lt ($funcStarts.Count - 1)) { $funcStarts[$j+1] - 1 } else { $lines.Length - 1 }

    # Include comment-based help above function if present
    $k = $start - 1
    while ($k -ge 0 -and $lines[$k] -match '^\s*#') { $k-- }
    # if there was a comment block directly above, include it
    $includeStart = if ($k -lt ($start - 1)) { $k + 1 } else { $start }

    $block = ($lines[$includeStart..$end] -join "`r`n").Trim()
    if ($block.Length -ge $MinSize) {
      $chunks.Add($block) | Out-Null
    }
  }

  # If chunks are huge, further split using char chunker
  $final = New-Object System.Collections.Generic.List[string]
  foreach ($c in $chunks) {
    if ($c.Length -gt ($FallbackChunkChars * 1.5)) {
      $sub = Chunk-ByChars -Text $c -ChunkChars $FallbackChunkChars -OverlapChars $Overlap -MinChunkChars $MinSize
      foreach ($s in $sub) { $final.Add($s) | Out-Null }
    } else {
      $final.Add($c) | Out-Null
    }
  }

  return @($final)
}

function Chunk-ByChars {
  param(
    [Parameter(Mandatory)][string]$Text,
    [int]$ChunkChars = 2200,
    [int]$OverlapChars = 250,
    [int]$MinChunkChars = 250
  )

  $clean = ($Text ?? "").Trim()
  if ($clean.Length -lt $MinChunkChars) { return @() }

  $chunks = New-Object System.Collections.Generic.List[string]
  $pos = 0

  while ($pos -lt $clean.Length) {
    $len = [Math]::Min($ChunkChars, $clean.Length - $pos)
    $chunk = $clean.Substring($pos, $len)

    # Attempt to break on a newline boundary near the end for nicer chunks
    $breakPos = $chunk.LastIndexOf("`n")
    if ($breakPos -gt 500 -and $breakPos -lt ($chunk.Length - 50)) {
      $chunk = $chunk.Substring(0, $breakPos).Trim()
      $len = $chunk.Length
    } else {
      $chunk = $chunk.Trim()
    }

    if ($chunk.Length -ge $MinChunkChars) {
      $chunks.Add($chunk) | Out-Null
    }

    if ($pos + $len -ge $clean.Length) { break }
    $pos = [Math]::Max(0, ($pos + $len - $OverlapChars))
  }

  return @($chunks)
}

# ----------------------------
# State handling (incremental ingestion)
# ----------------------------

function Load-State([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
    return [ordered]@{
      version = "1.0"
      files = @{}
      lastRunUtc = $null
    }
  }
  $raw = Get-Content -LiteralPath $Path -Raw
  return $raw | ConvertFrom-Json -Depth 50
}

function Save-State([object]$State, [string]$Path) {
  $json = $State | ConvertTo-Json -Depth 50
  Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

# ----------------------------
# Main
# ----------------------------

try {
  New-Directory $OutDir
  $script:LogFile = Join-Path $OutDir "ingestion.log"
  Write-Log "Starting ingestion. LibraryRoot=$LibraryRoot OutDir=$OutDir"

  if (-not (Test-Path -LiteralPath $LibraryRoot)) {
    throw "LibraryRoot not found: $LibraryRoot"
  }

  if (-not $StatePath) {
    $StatePath = Join-Path $OutDir "state.json"
  }

  $state = Load-State $StatePath
  if ($null -eq $state.files) { $state | Add-Member -NotePropertyName files -NotePropertyValue @{} }

  $chunksPath = Join-Path $OutDir "chunks.jsonl"
  $docsPath   = Join-Path $OutDir "docs.jsonl"

  # For deterministic output in CI, write fresh each run (downstream can dedupe by id)
  if ($PSCmdlet.ShouldProcess($chunksPath, "Initialize output")) { Set-Content -LiteralPath $chunksPath -Value "" -Encoding UTF8 }
  if ($PSCmdlet.ShouldProcess($docsPath, "Initialize output"))   { Set-Content -LiteralPath $docsPath   -Value "" -Encoding UTF8 }

  $extSet = New-Object System.Collections.Generic.HashSet[string]
  foreach ($e in $Extensions) { $extSet.Add($e.ToLowerInvariant()) | Out-Null }

  $files = Get-ChildItem -LiteralPath $LibraryRoot -Recurse -File -ErrorAction Stop |
           Where-Object { $extSet.Contains($_.Extension.ToLowerInvariant()) } |
           Where-Object { -not (Should-ExcludePath $_.FullName $ExcludePathContains) }

  if ($MaxFiles -gt 0) { $files = $files | Select-Object -First $MaxFiles }

  Write-Log ("Discovered {0} file(s) to consider." -f ($files.Count))

  $processedCount = 0
  $chunkCount = 0

  foreach ($f in $files) {
    $fullPath = $f.FullName
    $relPath = Get-RelativePath -Base $LibraryRoot -Full $fullPath

    $lastWriteUtc = $f.LastWriteTimeUtc.ToString("o")
    $size = $f.Length

    # State key: relative path
    $previous = $null
    if ($state.files.PSObject.Properties.Name -contains $relPath) {
      $previous = $state.files.$relPath
    }

    # Compute hash for incremental tracking
    $sha = Get-Sha256 $fullPath

    $shouldProcess = $true
    if ($previous) {
      if ($previous.sha256 -eq $sha -and $previous.lastWriteUtc -eq $lastWriteUtc) {
        $shouldProcess = $false
      }
    }

    if (-not $shouldProcess) {
      Write-Log "Skipping unchanged file: $relPath"
      continue
    }

    Write-Log "Processing file: $relPath"
    $text = Read-TextFileRobust $fullPath

    $docType = Infer-DocType $relPath
    $installerType = Infer-InstallerType $text $relPath
    $contextHint = Infer-ContextHint $text
    $tags = Extract-Tags $relPath $text

    # Document record
    $docId = ("doc::{0}" -f ($relPath.ToLowerInvariant().Replace('\','/')))
    $docRecord = [ordered]@{
      id = $docId
      sourcePath = $fullPath
      relativePath = $relPath
      lastWriteUtc = $lastWriteUtc
      sizeBytes = $size
      sha256 = $sha
      docType = $docType
      installerType = $installerType
      contextHint = $contextHint
      tags = $tags
      extension = $f.Extension.ToLowerInvariant()
    }

    if ($PSCmdlet.ShouldProcess($docsPath, "Append doc record")) {
      Add-Content -LiteralPath $docsPath -Value ($docRecord | ConvertTo-Json -Depth 20 -Compress) -Encoding UTF8
    }

    # Chunking strategy by extension
    $chunks = @()
    if ($f.Extension -in @(".ps1",".psm1")) {
      $chunks = Chunk-ByFunctions -Text $text -FallbackChunkChars $ChunkChars -Overlap $OverlapChars -MinSize $MinChunkChars
    } else {
      $chunks = Chunk-ByChars -Text $text -ChunkChars $ChunkChars -OverlapChars $OverlapChars -MinChunkChars $MinChunkChars
    }

    if ($chunks.Count -eq 0) {
      Write-Log "No chunks emitted (too small/empty after trimming): $relPath" "WARN"
    }

    # Emit chunk records
    for ($i=0; $i -lt $chunks.Count; $i++) {
      $chunkText = $chunks[$i].Trim()
      if ($chunkText.Length -lt $MinChunkChars) { continue }

      $chunkId = ("chunk::{0}::{1}" -f ($relPath.ToLowerInvariant().Replace('\','/')), $i)

      $chunkRecord = [ordered]@{
        id = $chunkId
        text = $chunkText
        metadata = [ordered]@{
          docId = $docId
          sourcePath = $fullPath
          relativePath = $relPath
          chunkIndex = $i
          docType = $docType
          installerType = $installerType
          contextHint = $contextHint
          tags = $tags
          sha256 = $sha
          lastWriteUtc = $lastWriteUtc
          extension = $f.Extension.ToLowerInvariant()
        }
      }

      if ($PSCmdlet.ShouldProcess($chunksPath, "Append chunk record")) {
        Add-Content -LiteralPath $chunksPath -Value ($chunkRecord | ConvertTo-Json -Depth 20 -Compress) -Encoding UTF8
      }

      $chunkCount++
    }

    # Update state for this file
    $state.files | Add-Member -NotePropertyName $relPath -NotePropertyValue ([ordered]@{
      sha256 = $sha
      lastWriteUtc = $lastWriteUtc
      sizeBytes = $size
      docType = $docType
      installerType = $installerType
      contextHint = $contextHint
      tags = $tags
      processedUtc = (Get-Date).ToUniversalTime().ToString("o")
    }) -Force

    $processedCount++
  }

  $state.lastRunUtc = (Get-Date).ToUniversalTime().ToString("o")

  if ($PSCmdlet.ShouldProcess($StatePath, "Write state file")) {
    Save-State $state $StatePath
  }

  Write-Log "Ingestion completed. ProcessedFiles=$processedCount EmittedChunks=$chunkCount"
  Write-Log "Outputs: $chunksPath ; $docsPath ; $StatePath"
  exit 0
}
catch {
  Write-Log "Ingestion failed: $($_.Exception.Message)" "ERROR"
  Write-Log $_.Exception.ToString() "ERROR"
  exit 1
}
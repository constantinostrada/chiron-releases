# chiron-releases

Binary releases of the Chiron daemon — a local runtime bridge between Ditto cloud and your local agent CLI (Claude Code, Codex, OpenCode). Your source stays on your machine; the daemon talks to the manager and orchestrates task execution locally.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/constantinostrada/chiron-releases/main/install.sh | bash
```

The installer:

1. Detects your platform (`darwin-arm64`, `darwin-x64`, `linux-x64`, `linux-arm64`)
2. Downloads the matching tarball from the latest release
3. Verifies SHA-256 against `checksums.txt`
4. Drops the binary at `/usr/local/bin/chiron` (or `~/.local/bin/chiron` without sudo)

## After installing

Pair the daemon with your manager using the command shown in the Engineer board's *New Agent → Local runtime* wizard:

```bash
chiron setup --code CHIR-XXXX-XXXX --server https://your-manager.example.com
chiron start
```

The daemon will start polling for tasks assigned to this agent.

## Optional: enable semantic search

Without [Ollama](https://ollama.com), the daemon falls back to keyword (BM25) search over its local knowledge store. Installing Ollama enables local vector embeddings on top, so the agent finds related entries even when query words don't exactly match:

```bash
brew install ollama && ollama pull nomic-embed-text
```

Runs 100% on your machine — nothing leaves the laptop.

## Manual install (Windows or other)

If the installer doesn't support your platform yet, download the matching archive from the [latest release](https://github.com/constantinostrada/chiron-releases/releases/latest), verify against `checksums.txt`, and put the binary on your `PATH`.

Available binaries per release:

| Platform | Tarball |
|---|---|
| macOS arm64 (Apple Silicon) | `chiron-darwin-arm64.tar.gz` |
| macOS x64 (Intel) | `chiron-darwin-x64.tar.gz` |
| Linux x64 | `chiron-linux-x64.tar.gz` |
| Linux arm64 | `chiron-linux-arm64.tar.gz` |
| Windows x64 | `chiron-windows-x64.zip` |

## Where is the source?

This repo only hosts binary releases. The daemon source lives in a separate repo managed by the chiron team. Releases here are produced by an automated build pipeline.

## Verifying a download manually

Every release includes a `checksums.txt` with SHA-256 hashes for every artifact:

```bash
shasum -a 256 -c checksums.txt
```

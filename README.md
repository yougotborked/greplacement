# greplacement

A drop-in `grep` replacement backed by [ripgrep](https://github.com/BurntSushi/ripgrep).

Same flags. Same exit codes. Dramatically faster.

```
$ grep -rn "TODO" src/
# ^ now runs at ripgrep speed, zero workflow changes
```

[![CI](https://github.com/yougotborked/greplacement/actions/workflows/ci.yml/badge.svg)](https://github.com/yougotborked/greplacement/actions/workflows/ci.yml)

---

## Install

```bash
curl -sfL https://raw.githubusercontent.com/yougotborked/greplacement/main/install.sh | bash
```

Then reload your shell:

```bash
exec $SHELL
which grep   # → ~/.local/bin/grep
```

### Manual install

```bash
git clone https://github.com/yougotborked/greplacement
cd greplacement
make install          # installs to ~/.local/bin/grep
```

Custom directory:

```bash
make install INSTALL_DIR=/usr/local/bin
```

### macOS (no Homebrew formula yet)

```bash
curl -sfL https://raw.githubusercontent.com/yougotborked/greplacement/main/install.sh | bash
```

The installer detects macOS and installs ripgrep via `brew` if available, or downloads a binary otherwise.

---

## How it works

`greplacement` is a single bash script (~230 lines) that:

1. Parses all GNU grep flags
2. Translates them to ripgrep equivalents
3. Executes `rg` with the translated arguments
4. **Falls back** to the real system `grep` for flags ripgrep doesn't support (BRE `-G`, null-data `-z`, etc.)

No new processes per call. No daemon. Just a fast `exec`.

### Supported flags

All commonly used GNU grep flags are supported:

| Flag | Meaning | Notes |
|---|---|---|
| `-E` `--extended-regexp` | ERE | rg default |
| `-F` `--fixed-strings` | Literal match | ✓ |
| `-P` `--perl-regexp` | PCRE2 | ✓ (rg built with PCRE2) |
| `-G` `--basic-regexp` | BRE | Falls back to system grep |
| `-i` `--ignore-case` | Case insensitive | ✓ |
| `-v` `--invert-match` | Invert | ✓ |
| `-w` `--word-regexp` | Whole word | ✓ |
| `-x` `--line-regexp` | Whole line | ✓ |
| `-c` `--count` | Count matches | ✓ |
| `-l` `--files-with-matches` | List matching files | ✓ |
| `-L` `--files-without-match` | List non-matching files | ✓ |
| `-n` `--line-number` | Show line numbers | ✓ |
| `-H` `--with-filename` | Show filename | ✓ |
| `-h` `--no-filename` | Hide filename | ✓ |
| `-o` `--only-matching` | Print only match | ✓ |
| `-q` `--quiet` `--silent` | No output, exit code only | ✓ |
| `-b` `--byte-offset` | Byte offset | ✓ |
| `-a` `--text` | Treat binary as text | ✓ |
| `-r` `-R` `--recursive` | Recursive | ✓ |
| `-m` `--max-count` | Stop after N matches | ✓ |
| `-A` `-B` `-C` | Context lines | ✓ |
| `-e` `--regexp` | Specify pattern | ✓ |
| `-f` `--file` | Pattern file | ✓ |
| `-s` `--no-messages` | Suppress errors | ✓ |
| `-Z` `--null` | NUL after filename | ✓ |
| `--include=` | File glob filter | ✓ |
| `--exclude=` `--exclude-dir=` | Exclusion globs | ✓ |
| `--color` `--no-color` | Color control | ✓ |
| `-z` `--null-data` | NUL-separated input | Falls back to system grep |

Combined short flags (`-inr`, `-cin`, etc.) are fully supported.

---

## Uninstall

```bash
rm ~/.local/bin/grep
```

Your system `grep` at `/usr/bin/grep` is untouched.

---

## CI / Automation

### Automatic compatibility checks

A GitHub Actions workflow runs **weekly** and:
- Checks for new ripgrep releases
- Runs the full test suite against the current rg version
- Opens an issue if a new rg version is available
- Updates `.rg-version` when tests pass

### Adding Claude Code for AI PR review

To enable AI-assisted PR review on this repo:

1. Install the [Claude GitHub App](https://github.com/apps/claude)
2. Add to any PR comment: `@claude review`

Claude will review diffs for correctness, flag compatibility regressions, and suggest improvements.

---

## Development

```bash
# Run tests
make test

# Lint
make lint          # requires shellcheck

# Test against a specific shim path
SHIM=/path/to/grep bash tests/test_shim.sh --verbose
```

### Adding a test

Edit `tests/test_shim.sh`. Every test uses `assert_matches_real` which runs both the shim and the real grep and diffs the output — so tests are self-verifying against actual grep behavior.

---

## Why not Rust?

The performance bottleneck is always ripgrep itself, not the bash wrapper. Shell startup adds ~3ms — unmeasurable vs. file I/O. Rust would add a build step and cross-compilation matrix with zero runtime benefit.

---

## License

MIT

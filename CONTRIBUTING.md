# Contributing

## Adding a feature

1. Check open [issues](https://github.com/CyberKird/vencord-autopatcher/issues) and pick one, or open a new one
2. Fork the repo and create a branch
3. Implement, keeping the same code style as the existing scripts
4. Test on your platform before opening a PR
5. Open a PR against `master` and mention the issue it closes

## Code style

- **Windows (PowerShell)**: proper param blocks, `Write-Host`, `try/catch`, `$PascalCase`
- **UNIX (bash)**: `set -euo pipefail`, `getopts`, `readonly`, `snake_case_vars`

Keep both scripts readable; they are meant to be skimmed by users, not just machines. Bump `$ScriptVersion` / `VERSION` in both scripts before tagging a release, or self-update will re-download on every run.

## Testing

- **Windows**: Run the `.ps1` script directly in PowerShell 5.1+
- **Linux**: `bash vencord-autopatcher.sh`
- **macOS**: Same as Linux, but the script auto-detects and downloads the `.zip` release

## Need help?

Open a discussion or comment on the relevant issue.

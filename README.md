# pre-commit-pmd

This repository preserves the PMD integration from the discontinued [xberg-io/pre-commit-hooks](https://github.com/xberg-io/pre-commit-hooks) library. We use it because the alternative [pre-commit-java](https://codeberg.org/gherynos/pre-commit-java) requires Docker and we need to run PMD directly on the system.

## Usage

Add this to `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: https://github.com/lookslikematrix/pre-commit-pmd
    rev: main
    hooks:
      - id: pmd
```

### Configuration

```yaml
- id: pmd
  args: ['-d', 'src', '-R', 'rulesets/java/quickstart.xml', '-minimumpriority', '3']
```

See [PMD documentation](https://pmd.github.io/) for available options.

## ❤️ Contributing

Contributions welcome! Feel free to open issues or submit PRs.

## License

MIT License - see [LICENSE](LICENSE) file for details

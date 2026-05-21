# Contribution Guidelines

Thank you for contributing to `wsl_monitor`! To maintain high code quality, stable releases, and clean commit logs, this repository enforces **Trunk-Based Development (TBD)** assisted by the **`tbdflow`** CLI helper tool.

---

## 🛠️ Trunk-Based Development (TBD) Workflow

We do not use long-lived feature branches, git flow, or complex staging setups. Developers merge small, frequent updates directly into the single `main` branch.

### Core Rules
1. **Short-Lived Branches Only**: Feature branches should not live longer than 24 hours.
2. **Conventional Commits**: Commit messages must follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:
   - `feat: add sparse VHDX support`
   - `fix: correct /proc parsing integer overflow`
   - `docs: update setup guidelines`
3. **Frequent Syncing**: Pull and rebase frequently to prevent merge conflicts.
4. **Validation First**: Always run `flutter analyze` and `flutter test` before submitting changes.

---

## ⚙️ Using `tbdflow`

`tbdflow` is a CLI helper that wraps Git commands to automate safe, standardized TBD practices.

### 1. Initialize Developer Workspace
Run the following in the repository directory to set up local configurations:
```bash
tbdflow init
```

### 2. Standard Development Loop

#### Option A: Direct Trunk Commits (For simple, fast changes)
You can work directly on `main` and execute:
```bash
tbdflow commit
```
*Under the hood, this pulls remote changes via rebase, prompts you for a Conventional Commit header, performs pre-checks, and pushes to the trunk.*

#### Option B: Short-lived Feature Branches (For more complex tasks)
1. **Create and push your short-lived branch**:
   ```bash
   tbdflow branch feat/add-settings-toggle
   ```
2. **Commit progress**:
   ```bash
   tbdflow commit
   ```
   *On a feature branch, this commits locally and pushes to your remote branch.*
3. **Sync with the trunk**:
   To pull down the latest trunk updates and rebase your branch:
   ```bash
   tbdflow sync
   ```
4. **Complete and Merge**:
   Once tests pass, merge the feature branch into `main` and delete the local/remote branch automatically:
   ```bash
   tbdflow complete
   ```

---

## 🔬 Testing Guidelines
Before proposing a pull request or completing a branch:
1. **Static Analysis**: Ensure all static analysis checks pass cleanly:
   ```bash
   flutter analyze
   ```
2. **Unit & Widget Testing**: Run the test suite:
   ```bash
   flutter test
   ```
   *We encourage adding new test cases for any new functionality.*

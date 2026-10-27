---
name: conventions
description: Standard conventions and end-to-end workflow for importing, iterating, troubleshooting, fixing, testing, PR-creating, merging, closing GitHub issues, and triggering CI/CD deployments in Rayzr.
---

# Issue Resolution & Deployment Conventions Skill

This skill defines the standardized end-to-end lifecycle for discovering, troubleshooting, fixing, verifying, merging, and deploying fixes for GitHub issues in the Rayzr codebase.

## Lifecycle Overview

```
1. Ingest Issues (GitHub MCP)
       ↓
2. Troubleshoot & Reproduce (Logs, Crash Dumps, Code Analysis)
       ↓
3. Write Reproducing Regression Test
       ↓
4. Implement Minimal & Robust Fix
       ↓
5. Full Verification Suite (odin test, odin check, task test, test-drive for UI)
       ↓
6. Branch, Commit, Push
       ↓
7. PR Creation & Merge (GitHub MCP)
       ↓
8. Verify Issue Closure & Redeploy / CI/CD Trigger
```

---

## 1. Issue Ingestion & Triaging

1. **List Open Issues**:
   Use GitHub MCP `list_issues` to retrieve all open issues for `owner: "bcrowe306"`, `repo: "rayzr"`.
2. **Prioritize Crashes & Bugs**:
   - Give first priority to crash bugs, assertions, and regressions.
   - For feature requests or broad enhancements, consult with the user or clarify requirements when underspecified.
3. **Inspect Crash Context**:
   - Check issue descriptions, stack traces, and local crash dump files in `~/.config/rayzr_editor/crashes/` or local log outputs.

---

## 2. Troubleshooting & Root Cause Analysis

1. **Locate Source Path**:
   Trace functions and symbols mentioned in the issue back to the responsible source file (e.g., `engine/particle.odin`, `editor/preview_panel.odin`, `engine/animation_player_node.odin`).
2. **Identify Defensive Deficiencies**:
   - Unchecked ranges (e.g., `rand.float32_range(low, high)` where `low > high`).
   - ImGui stack imbalance (e.g., mismatched `PushStyleColor` vs `PopStyleColor`).
   - Event double-firing on boundary conditions (e.g., single-frame animations where frame does not change).
   - Resource leaks or dangling references on node destruction or editor panel closing.

---

## 3. Write Reproducing Regression Tests

Before changing production logic, write an automated test that isolates the failure.

1. **Add Test to the Engine or Editor Test Suite**:
   Place tests in `engine/<subsystem>_test.odin` or `editor/*_test.odin`.
2. **Target Specific Tests in Odin**:
   Run single tests using `-- -tests:<test_name>`:
   ```bash
   odin test engine -define:ODIN_TEST_THREADS=1 -- -tests:<test_name>
   ```
3. **Observe Failure**:
   Confirm that the test fails or crashes as expected prior to applying the fix.

---

## 4. Implementation Guidelines

1. **Minimal & Surgical**:
   Make precise, targeted edits. Do not refactor unrelated subsystems.
2. **Memory Safety & Leaks**:
   - Ensure all allocated strings and dynamic slices have clear ownership and are cleaned up.
   - Run tests with Odin's `mem.Tracking_Allocator` enabled (default in `odin test engine`).
3. **Guard Boundary Conditions**:
   - Handle 0-frame or 1-frame edge cases.
   - Handle negative variance/spread by clamping or swapping ranges safely.
   - Balance ImGui push/pop stacks in all control-flow branches.

---

## 5. Verification Checklist

Always execute the following verification steps in sequence before committing:

1. **Verify Regression Test**:
   ```bash
   odin test engine -define:ODIN_TEST_THREADS=1 -- -tests:<test_name>
   ```
2. **Run Full Engine Unit Test Suite**:
   ```bash
   odin test engine -define:ODIN_TEST_THREADS=1
   ```
   *Verify 0 failures and 0 memory leaks.*
3. **Type Check Root & Packages**:
   ```bash
   odin check .
   odin check editor
   ```
4. **Run Full Project Test Task**:
   ```bash
   task test
   ```
   *Verify UI headless test hook passes with 0 failures.*

### Automated UI Testing via Test-Drive Process
> [!IMPORTANT]
> **Automated UI Testing**: When making any UI changes in the editor, there is a **test-drive process** in this repo (`tests/drive/*.drive`) to help you automatically test any UI changes. It allows you to automate UI events (clicks, drags, keyboard inputs, shortcuts) in a background window to test changes and verify editor state without manual interaction.
>
> **Running Test-Drives**:
> ```bash
> # Run all test-drives
> ./scripts/editor_drive.sh
> # Or run a specific test drive
> ./scripts/editor_drive.sh <drive_name>
> # Or via task
> task editor:drive
> ```
> Each drive operates against a fresh copy of `assets/demo_project` in `/tmp`, records step-by-step checks, and outputs numbered screenshots and reports to `editor_screenshots/drive/<name>/`. Always run the relevant test-drive or add a new test-drive script when modifying editor UI panels, menus, dialogs, or inspector widgets.

---

## 6. Git Branching, PR & Merging Process

1. **Create Topic Branch**:
   ```bash
   git checkout -b <type>/<short-desc>-<issue-id>
   # Example: git checkout -b fix/animation-single-frame-sound-26
   ```
2. **Stage & Commit**:
   Commit following conventional commit messages with an explicit `fixes #<id>` tag:
   ```bash
   git add <modified-files>
   git commit -m "fix(<scope>): <description> (fixes #<issue-id>)"
   ```
3. **Push to Remote**:
   ```bash
   git push origin <branch-name>
   ```
4. **Create PR via GitHub MCP**:
   Call `create_pull_request` with:
   - `owner`: `"bcrowe306"`
   - `repo`: `"rayzr"`
   - `base`: `"main"`
   - `head`: `<branch-name>`
   - `title`: Clean summary
   - `body`: Root cause, fix details, test verification, and `Fixes #<issue-id>`.
5. **Merge PR via GitHub MCP**:
   Call `merge_pull_request` with `merge_method: "merge"`.
6. **Verify Issue Closure**:
   - Check `get_issue` for the issue number.
   - If not automatically closed, call `update_issue` with `state: "closed"`.
7. **Sync Local Main**:
   ```bash
   git checkout main && git pull origin main
   ```

---

## 7. CI/CD & Release Deployment

1. **CI/CD Workflow Triggers**:
   - Merging into `main` automatically triggers GitHub Actions build and validation workflows.
2. **Tagged Releases (when publishing)**:
   - When all issues in a milestone/batch are fixed, tag the release:
     ```bash
     git tag vX.Y.Z
     git push origin vX.Y.Z
     ```
   - This triggers the publish/release CI/CD workflow to compile binaries and publish release artifacts.

---
name: odin-check
description: Run 'odin check .', 'odin test engine' (or 'task test'), and optionally 'odin build .' after making code changes in an Odin project to verify syntax, type-checking, scene lifecycle, and memory integrity, ensuring all errors and memory leaks are caught before finishing.
---

# Odin Check & Engine Test Verification Skill

This skill defines the verification process for Odin projects. Always invoke `odin check .` whenever any `.odin` file is created, modified, or moved, and **always run the engine test suite (`odin test engine` or `task test`) whenever changes are made to the engine**.

## Workflow

1. **Run Package Check**:
   Execute type-checking on the package directory:
   ```bash
   odin check .
   ```
   *Note*: Always pass the directory (`.`), not a single file without `-file`, because Odin packages include all sibling files in the package directory.

2. **Verify Unused Imports & Stricter Checks**:
   Check for unused imports or variables that language servers (OLS) report:
   ```bash
   odin check . -vet-unused-imports
   ```

3. **Run Engine Package Tests & Memory Leak Checks**:
   Whenever changes are made to the `engine` package (or any engine code), run the automated engine test suite via Taskfile or Odin test runner:
   ```bash
   task test
   # or directly:
   odin test engine
   ```
   This verifies scene switching (menu -> levels -> quit), node hierarchy lifecycle, Box2D physics integration, resource management, and asserts zero memory leaks or bad frees via `mem.Tracking_Allocator`.

4. **Verify Build**:
   Verify full compilation succeeds:
   ```bash
   odin build . -out:rayzr
   ```

5. **Run Automated UI Test Suite (if available)**:
   Verify UI & editor regressions:
   ```bash
   ./rayzr --test-ui
   ```

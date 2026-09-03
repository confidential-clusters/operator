---
name: sync-operator-submodule
description: >
  Update the operator submodule to the latest upstream commit, refresh the
  drift-cache copy of its Containerfile, and apply the resulting diff to the
  root-level Containerfile. Use whenever the upstream operator repo has new
  commits that should be pulled into this repo.
---

# Sync operator submodule

## Steps

1. **Update the submodule** to the latest commit on its tracked branch:

   ```
   git submodule update --init operator
   git -C operator fetch origin main
   git -C operator checkout <new-sha>   # or: git -C operator pull origin main
   ```

2. **Identify what changed** between the old and new submodule commits:

   ```
   git -C operator diff <old-sha>..<new-sha> -- Containerfile
   ```

3. **Copy the updated Containerfile into drift-cache/**:

   ```
   cp operator/Containerfile drift-cache/Containerfile
   ```

4. **Apply the same diff to the root-level `Containerfile`.** It mirrors the submodule
   one (`operator/Containerfile`) but with `operator/` path prefixes on `COPY`
   instructions, downstream base images, per-component `LABEL` blocks on each
   distribution stage, no `--mount=type=cache` clauses, and a pinned
   `REFERENCE_VALUES_COMMIT` in the `compute-pcrs-data` stage instead of the upstream
   `cargo metadata` lookup. Translate the diff hunks accordingly.

5. **Verify** that `drift-cache/Containerfile` matches `operator/Containerfile` exactly
   and that the root-level `Containerfile` contains all the same logic changes (adapted
   for its path layout and downstream modifications).

# Work Recorder Productization Risk Register

Updated: 2026-06-22T17:39:00-05:00

| Risk | Impact | Current Mitigation |
| --- | --- | --- |
| Scope is large enough to span public local product, private hosted staging, CI/release, and dogfood. | High schedule and integration risk. | Milestone gates and status files will track concrete blockers instead of vague deferrals. |
| Private repo canonical checkout is dirty with unrelated work. | Risk of overwriting unrelated user/agent changes. | Use a separate manual `ctx-private` worktree before edits. |
| Broad Rust/Bazel/build verification can overload this host. | Machine instability and false failures. | Use existing resource-safe wrappers and avoid overlapping heavy jobs. |
| Dashboard can pass tests but remain visually sparse. | Product-quality failure. | Require screenshot generation, manual inspection, and adversarial UI review. |
| Hosted staging credentials or runner access may be unavailable. | External blocker for completion criteria. | Record exact attempted command, missing credential/runner, and remediation; keep unblocked tracks moving. |
| README/docs currently overclaim implemented behavior. | User confusion and false product promises. | Docs truth-pass worker is scoped to README/docs only. |
| Existing local store shape diverges from the product contract. | Capture/search/hosted sync churn if built on the wrong schema. | Land core schema/types and versioned store migrations before capture/search/dashboard work. |
| Buildkite/release platform matrix is absent. | Cannot satisfy release-verification criteria yet. | CI worker is scoped to resource-safe scripts and initial Buildkite wiring first. |

## Accepted Risks

None accepted yet.

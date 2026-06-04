Accepted findings:
- `KmpContainer.kt` is a valid future mini-service split candidate: repository module, service module, use case module, notebook module, demo data seeder.
- `MvpServices.kt` can later be split by platform/service type, but it is not the highest-value first change.
- `NotebookRepository`, `PlannerRepository`, dashboard, schedule, and physical-tests repositories are broader candidates but should be split behind compatible facades with tests.

Decision:
- Deferred KMP/data edits in this run because they touch broader architecture and protected persistence boundaries.

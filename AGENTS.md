# Repository workflow

When the user requests changes in this repository, complete the following workflow by default unless they explicitly request otherwise:

1. Implement the requested changes and update `README.md` to reflect the resulting behavior or workflow.
2. Run appropriate validation.
3. Commit the changes and push them to the repository's remote branch.
4. Create and publish a new GitHub release. Increment the app version and build number in `scripts/build-app.sh`, build a universal Apple Silicon/Intel app from the committed source, verify its signature, and attach the ZIP and SHA-256 checksum. Include concise release notes and validation results.

The user's change request authorizes this entire workflow; do not ask for separate confirmation to commit, push, or publish the release. Honor any explicit instruction to skip a step. Keep unrelated pending changes out of commits and release builds. GitHub Actions currently builds and tests only; a successful CI run does not publish a release.

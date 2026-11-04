# Fault Injection Log

| Stage | Fault Injected | Observed Behavior | Why this is correct |
|-------|----------------|-------------------|---------------------|
| **Lint** | Added invalid syntax (`const x = ;`) to `src/index.js` | Pipeline aborted at Lint. Build, Verify, Archive, and Publish were all skipped. | Fail-fast principle: Catching syntax errors early saves compute time and prevents bad code from moving further down the pipeline. |
| **Build** | Deleted the `src` folder, breaking the `cp -r src/* dist/` command | Lint passed. Build failed. Verify, Archive, and Publish were skipped. | Without a build, there is no output to test or publish. Continuing would just result in empty artifacts. |
| **Test** | Changed a test assertion to `expect(add(2,3)).toBe(6)` | Lint and Build passed. Test failed. Security Audit still ran (parallel). Archive and Publish were skipped. | We do not ship code that fails its test suites. The pipeline must block the release to protect production. |
| **Security Audit** | Temporarily removed the `|| true` from the `audit:security` script in `package.json` | Lint, Build, and Test passed. Security Audit failed. Archive and Publish skipped. | If a security vulnerability is found, the build must fail to prevent vulnerable code from being deployed. |
| **Publish** | Temporarily changed the `minio-credentials` password in Jenkins to an incorrect one | Lint, Build, Verify, and Archive passed. Publish failed. | If the artifact cannot be safely stored in the registry, the build is not successful. We must not mark it green. |

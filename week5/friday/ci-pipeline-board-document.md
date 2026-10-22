# KijaniKiosk Continuous Integration Pipeline

When a developer at KijaniKiosk finishes writing code and saves it to our shared repository, an automated system immediately takes over. This system is our Continuous Integration (CI) pipeline. Its job is to verify that the new code meets our quality standards before it is merged into the main product. Think of it as a rigorous quality control checkpoint that every piece of code must pass through. 

Here is what happens between a developer pushing their code and a new version of our software being safely stored for deployment.

## The Journey of a Code Change

Our pipeline is built in sequential stages. This ensures that if something is wrong, we catch it as early as possible, saving time and preventing flawed code from moving forward.

| Stage | What it does | What it confirms |
|-------|--------------|------------------|
| **Lint** | Checks the code for syntax errors and formatting issues. | The code is written correctly and will not crash due to basic typos. |
| **Build** | Packages the raw code into a working application. | The application can actually be constructed from the files provided. |
| **Test & Audit** | Runs automated tests and checks for known security vulnerabilities simultaneously. | The application behaves exactly as expected and does not introduce known security risks. |
| **Archive** | Saves a permanent copy of the built application within our CI system. | We have a reliable record of exactly what was built for this specific update. |
| **Publish** | Uploads the final packaged application to our secure storage registry (MinIO). | The application is securely stored and ready to be deployed to production. |

## What Happens When Something Goes Wrong

In traditional software development, if a developer submits broken code, it might not be discovered until days or weeks later when the application crashes in production. Our pipeline prevents this scenario entirely by enforcing a strict "fail-fast" contract.

If a developer submits code that fails the initial Lint or Build stage, the system stops immediately. The automated process will not proceed to run tests, and it will absolutely not save the artifact. The developer receives an immediate notification that their code was rejected, allowing them to fix the typo before wasting anyone else's time.

If the code builds successfully but fails the automated tests or the security audit, the system stops at that point. It will not archive or save the artifact to our secure storage. This ensures that we never accidentally deploy software that behaves incorrectly or contains known security vulnerabilities. 

Finally, if the process succeeds through testing but fails during the final storage step (due to a network issue, for example), the system marks the entire process as failed. This guarantees that if the system reports success, the software is both thoroughly tested and securely stored. We never report a green build if any single part of the process fails. This level of strictness is essential for a financial services platform where errors can have real-world consequences.

## Scope and Next Steps

This pipeline is a massive step forward for KijaniKiosk, but it is not the final piece of the puzzle. Currently, this system only verifies code, builds it, and stores it in our artifact registry. It does not yet automatically deploy the software to our live servers.

In the coming weeks, we will introduce Continuous Deployment (CD). This will allow the successful artifacts generated today to be automatically pulled from our secure storage and deployed to staging and production environments. For now, our focus is on a reliable, secure, and fast verification process that gives our engineering team the confidence to move quickly without breaking things. We have built a strong foundation, and the next phase will build upon this success.

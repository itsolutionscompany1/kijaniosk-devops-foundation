=> DevOps delivery notes

I am employing this starter kit in connection with KijaniKiosk, which is a last-mile retail solution enabling shoppers and kiosk staff to order stock, make payments via mobile money, and check what is available on the shelves. I wanted the cloud and Git configuration to be documented before anyone attempts to go live, because otherwise you end up designing the architecture under pressure and that never has a good outcome.

I have attempted to follow the Three Ways, but in what I am saying I am describing exactly what I did in the repository rather than using the labels found in the textbook.

=>Flow

The rule is simple. Design on a feature branch. Discuss it on a pull request. Then merge. I didn't put files directly onto `main`.

| Branch | What I used it for |
|---|---|
| `main` | Stuff a new teammate can trust without guessing |
| `develop` | Where accepted starter-kit work lands |
| `feature/starter-kit-files` | Where I wrote this blueprint in isolation |

The cloud model, the region, the IAM and network notes were all added at the same time on that feature branch. There was one PR and one story. If I had opened five small PRs then a reviewer would have missed how they related to one another. To me, flow just means putting in small batches, following a single path and not making changes to the branch that customers rely on.

=>Feedback

The feedback loop consists of the public relations activity that goes from the `feature/starter-kit-files` branch to the `develop` branch; it is not Slack and not a voice note.

In the PR I called out:

- which cloud model I picked, and why the other two lost
- region + how many AZs
- the one IAM action the app is allowed to do
- how public vs private subnets actually route

It's possible for someone to dislike the IAM file yet still take the network notes. That was the case when we discovered a wide-open `s3:*` policy after having already set up the service.

=> Learning

I have not merely drawn boxes; beside them I wrote the reason.

Cape Town (af-south-1) could end up being too distant from Nairobi users—in that case, reference should be made in regions-azs.md to the second region and CloudFront. And if somebody subsequently asks the receipt-upload role to list all the buckets, iam-least-privilege.md contains the note stating that it should not be done and the reason why.

The explanation here is concerning the Learning part: the shortcuts I nearly took, so that the next person won't.

=> How this maps to the week

The work done with Git consists of the branch model and that PR, not a single commit on the main branch. The decision regarding the cloud is set out in cloud-model.md. Information on reliability can be found in regions-azs.md. The principle of least privilege is covered by a single named task in iam-least-privilege.md. Network segmentation involves the diagram together with the routing notes that I left next to it.

=> Reflection

**Shortcuts I nearly took**

It would have been faster to drop everything on `main`. A single large subnet "for now" would have been faster as well. Having `s3:*` on the app role would have saved time. I've seen how those situations turn out—an unreviewed change in production, a database losing its connection to the internet, or a leaked key that could empty all the buckets. That's why I didn't.

:What took the most thinking**

Region versus availability zone—at first I was confusing the two. A region refers to a geographical area and an AZ is a single data centre located within that region. Having multiple AZs in Cape Town is useful if one building fails, but it offers no solution if the fibre link back to Kenya is cut. These are different kinds of failure and require different remedies—getting this distinction clearly written down took me a while.

If this grows, what I'd do first

The second area should be handled by DR and the storefront should be placed behind a CDN. Then I'd like the PR to automatically catch obvious mistakes—such as those checked by an IAM policy lint and a short diagram checklist—so that the feedback isn't limited to someone reading Markdown at midnight.
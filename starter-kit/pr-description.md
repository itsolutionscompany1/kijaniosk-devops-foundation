Summary

Set up the KijaniKiosk DevOps foundation before the platform starts serving actual customers.

* These delivery notes connect this workflow with Flow, Feedback and Learning.
* The cloud model gives priority to the application for PaaS, provides SaaS for payment and email services, and offers IaaS only in the case of the VPC.
* The region is af-south-1 (Cape Town) and has two availability zones.
* The IAM role called kijani-order-receipt-writer has access to a single encrypted prefix with regard to S3 PutObject operations.
* The network diagram together with the routing notes indicate that the internet makes use of public subnets whereas the application and the database remain private and exit through NAT.

Test plan

starter-kit/ contains every deliverable file
 Branches main, develop and feature/starter-kit-files exist
 Network diagram shows public vs private subnets and the IGW / NAT routes
 IAM policy has no * actions and names one application task
 Region / AZ reasoning distinguishes a building failure from a regional outage
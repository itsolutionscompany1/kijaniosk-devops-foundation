Region and availability zones

Region choice: af-south-1 (Cape Town)

The first customers for KijaniKiosk are in Kenya; the nearest AWS region that provides all of the services used in this starter kit is AWS Africa (Cape Town), namely VPC, ALB, NAT Gateway, ECS/Fargate or Elastic Beanstalk, RDS and S3.

Column 1	Column 2
Option	Why it is not first
eu-west-1 (Ireland)	Mature and cheap, but every checkout round-trip crosses Europe
me-south-1 (Bahrain)	Closer than Ireland for some routes, weaker service catalogue for this stack
us-east-1	Default in many tutorials; worst latency for Nairobi users


Latency isn't a mere vanity figure; if a customer at a kiosk is using a mid-range phone, they'll give up after a three-second attempt to look up a stock item. The proper initial design is to carry out the computation in Cape Town and then cache the store information at the edge.

Should a further Kenyan AWS region open up, we will include it. We don't wait for it to open.

What a region gives us — and what it does not

A region consists of a group of data centres located in a single geographical area and includes its own instance of IAM, its own S3 control plane and its own network.

A region does not survive:

* A long fibre cut between Kenya and South Africa
* A regional control-plane event
* A legal requirement to keep a second copy of data in another country

The need for those risks is for a separate disaster-recovery region, not for adding more subnets to Cape Town.

Availability zones

An availability zone is a separate site located within a region, with its own power and network facilities. Because of this, a fire or a cooling failure in one zone should not cause the others to fail.

KijaniKiosk will operate across two availability zones from the very first day.

af-south-1
├── af-south-1a
│   ├── public subnet  10.0.1.0/24   containing the ALB node and the NAT
│   └── private subnet 10.0.2.0/24   for app tasks and the RDS primary
└── af-south-1b
    The public subnet is 10.0.3.0/24 and it contains the ALB node and the NAT device.
    Private subnet 10.0.4.0/24 – for app tasks and the RDS standby instance

The smallest configuration that actually realizes a "multi-AZ" setup is two availability zones; a single AZ having two subnets is still just one building.

Reliability reasoning

Application

The load balancer is regional and has a node in each public subnet; when AZ-a fails the balancer ceases to send traffic to that area and the PaaS tasks in AZ-b continue to serve.

Database

RDS (or its equivalent) uses Multi-AZ, providing a synchronous standby in the second availability zone; the failover involves a change to the DNS which the application does not handle, and we are willing to accept a brief interruption but do not consider 'restoring from last night's backup' to be a viable high availability strategy.

NAT

Each public subnet has its own NAT Gateway; if one NAT gateway were shared in AZ-a then whenever AZ-a fails the private instance in AZ-b would die when trying to access the internet. That would constitute a hidden single point of failure.

What we do not claim

Multi-AZ isn't a backup, it isn't a second region and it doesn't take the place of tested restores. The backups still follow the lifecycle policy and the restore process is still rehearsed.

If the platform grows

1. Include a third AZ only in the case where the provider offers it and the data-plane cost is reasonable.
2. Include eu-west-1 as a warm standby for disaster recovery and use infrastructure as code to avoid the VPC being set up by hand twice.
3. To ensure that users in Nairobi do not have to retrieve the HTML from Cape Town with every tap, place the static storefront assets on a CDN.

The first of those is capacity. The second is survival. The third is experience. They are not the same ticket.
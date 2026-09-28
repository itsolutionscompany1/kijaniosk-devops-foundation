Cloud service model

Decision



The KijaniKiosk will function as a PaaS-first platform, with SaaS provided for payments and email and IaaS being required only for the virtual network that we have to own.

We are not selecting a single model to be used throughout the company; instead, we are picking the appropriate model for each specific job.

What KijaniKiosk must do



Serve a web and mobile storefront

Accept M-Pesa and card payments

Hold product, price and order data

Let a kiosk attendant see only their shop’s stock

Survive a single data-centre failure without a full outage

The team consists of only a small number of people, and the time taken to patch the operating systems is time that could have been used for checkout and for ensuring stock accuracy.

Why not IaaS for the application

With IaaS (which involves us building and patching our own virtual machines) we have full control over the guest operating system, the runtime and the disk.

That control is a cost:

We take on the responsibility for applying OS patches, hardening SSH, and carrying out capacity planning.

It is our incident, not that of the cloud provider, if a kernel update is missed.

What we do is write the automation on a horizontal scale.

VPC, subnets, route tables and NAT should be placed in an IaaS environment since they are infrastructure components and not application servers; the application itself should not begin as a collection of unmanaged VMs.

Why not SaaS for the core application

SaaS (a vendor’s finished product) is correct for:

Email delivery (for example Amazon SES or a transactional mail provider)

Payments (M-Pesa Daraja, or a payment aggregator)

Source control and issue tracking (GitHub)

The KijaniKiosk catalogue and order service does not belong in that location since those are our products. If we used a pure SaaS storefront then we would be limited in how we could model kiosk stock, we would not be able to split tenders, or we would later be unable to add a warehouse. We also could not place that data in a private subnet that we control.

Why PaaS for the application



PaaS (a managed runtime such as AWS Elastic Beanstalk, ECS Fargate, or App Runner) means:

We provide a container or a build artefact.



The platform will schedule it, restart it, and then place it behind a load balancer.

We continue to select the VPC, the IAM role and the database engine.

We do not use SSH to apply security patches to the host.

This is consistent with a team that needs to act quickly yet still maintain its security boundaries.

Workload Model Reason



Storefront and API PaaS We own the code; the cloud owns the hosts

PostgreSQL Managed PaaS (RDS or Cloud SQL) Multi-AZ failover without us running Postgres HA

Object storage for receipts Managed (S3) Durable storage with a narrow IAM policy

Payments and email SaaS Regulated, specialised, not our core

VPC, subnets, NAT, routes IaaS networking We must decide what is public

What we refuse at launch



A single EC2 instance that is the website, the API and the database

A database with a public IP “so we can connect from home”

An application role with AdministratorAccess “until we tidy IAM later”

These are the IaaS habits which nullify the advantage of PaaS.

How this will evolve



If a later component needs a special kernel module or a hardware token, that component can move to IaaS. The default stays PaaS. Growth should add managed services, not more pets.


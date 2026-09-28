# Network routing

This note explains the diagram in `network-topology.png`.

## Layout

One VPC: `10.0.0.0/16` in `af-south-1`.

| Subnet | CIDR | AZ | Exposure |
|---|---|---|---|
| Public A | `10.0.1.0/24` | af-south-1a | Internet-facing |
| Private A | `10.0.2.0/24` | af-south-1a | No inbound from the internet |
| Public B | `10.0.3.0/24` | af-south-1b | Internet-facing |
| Private B | `10.0.4.0/24` | af-south-1b | No inbound from the internet |

Only the public subnets have a route to the Internet Gateway. That is the whole segmentation rule.

## Route tables

**Public route table** (associated with `10.0.1.0/24` and `10.0.3.0/24`)

| Destination | Target | Meaning |
|---|---|---|
| `10.0.0.0/16` | local | Talk to anything in the VPC |
| `0.0.0.0/0` | Internet Gateway | Accept and send internet traffic |

The Application Load Balancer lives here. Shoppers hit HTTPS on the ALB. The ALB is allowed inbound `443` from `0.0.0.0/0`. Nothing else in the public subnet is.

NAT Gateways also live here. They have Elastic IPs. They are exits, not entrances.

**Private route table** (associated with `10.0.2.0/24` and `10.0.4.0/24`)

| Destination | Target | Meaning |
|---|---|---|
| `10.0.0.0/16` | local | Talk to anything in the VPC |
| `0.0.0.0/0` | NAT Gateway in the same AZ | Outbound patches and APIs only |

There is **no** `0.0.0.0/0 → igw-…` line on the private table. That is what makes the subnet private. A security group is not enough if the route still points at the internet.

## Traffic paths

1. **Customer → storefront**  
   Internet → IGW → ALB (public subnet) → app task (private subnet, port 8080 from the ALB security group only).

2. **App → database**  
   Private subnet → RDS in the private subnet. The database security group allows `5432` only from the app security group. The database has no public IP.

3. **App → M-Pesa or S3**  
   Private subnet → NAT in the same AZ → IGW → internet. Return traffic is connection-tracked. The internet cannot open a new session to the app.

4. **Operator from the office**  
   Not SSH on port 22 from `0.0.0.0/0`. Break-glass is SSM Session Manager or a short-lived VPN into a separate operations subnet. That subnet is out of scope for this starter kit and must not be bolted onto the public ALB subnet.

## Security groups (narrower than the subnet)

| Group | Inbound | Outbound |
|---|---|---|
| `sg-alb` | 443 from the world | 8080 to `sg-app` |
| `sg-app` | 8080 from `sg-alb` | 443 to the world (via NAT), 5432 to `sg-db`, 443 to S3 |
| `sg-db` | 5432 from `sg-app` | None required for launch |

Subnets decide *whether a packet can reach the internet*. Security groups decide *which process may speak*. Both are required.

## What we will not do

- Place RDS in the public subnet “for a quick pgAdmin session”
- Share one NAT in AZ-a with tasks in AZ-b
- Open `22` or `3389` on the ALB
- Give the private route table an IGW route and call the subnet private anyway

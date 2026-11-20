# Interview notes: AWS networking with Terraform

Answers are about what is in this repository. Where something has not been done yet, the answer
says so. Say the same thing in the room.

## The one-minute version

"I built a hub-and-spoke network on a Transit Gateway as Terraform modules. The hub VPC has the
internet gateway and one shared NAT gateway. Two spoke VPCs have no internet gateway: their
default route goes to the Transit Gateway and on to the hub. I turned off the Transit Gateway's
default route tables so nothing is connected by accident, and gave each spoke its own table. App
and data can reach each other only because one variable lists that pair. A private Route53 zone is
shared by all three VPCs, and I defined Reachability Analyzer paths in code. It is validated and
tested with a mocked provider and scanned with checkov. Then I applied it once to a real account. That
found two bugs the mocked tests could not: ping was blocked because the stateless network ACL had no rule
for the echo reply, and the spokes were not really isolated, because a packet for a disallowed spoke went
to the hub and the hub NAT gateway hairpinned it back. I fixed both (an ACL rule, and a blackhole route for the
private supernet in each spoke table), re-ran the drills, and the analyzer then reported the spokes
unreachable. Then I destroyed it."

## Transit Gateway and routing

**Why a Transit Gateway and not VPC peering?** Peering is one connection per pair and is not
transitive: A to B and B to C does not let A reach C. With many VPCs the number of connections
explodes and every one needs routes. A Transit Gateway is a hub: each VPC attaches once and the
route tables decide who can talk. The price is an hourly fee per attachment plus a per-GB charge,
so for two VPCs peering is cheaper. I would pick the Transit Gateway when there are many VPCs, a
need for central egress or inspection, or a VPN to on-premises.

**Association and propagation: what is the difference?** Association says which route table an
attachment's outgoing traffic is looked up in. Propagation says an attachment adds its own range
to a route table automatically. So the hub's table learns the spokes by propagation, and each
spoke's table learns the hub's range the same way, plus a static default route to the hub.

**Why turn the default route tables off?** By default every attachment is associated with, and
propagates into, one shared table, so everything can reach everything. That is the opposite of
segmentation. With the defaults off, an attachment joins a table only when the code says so.

**How is isolation between spokes done?** One route table per spoke. Spoke A's table only learns
spoke B's range if the pair is listed in `allowed_flows`. If it is not learned, the packet must not
fall through to the default route to the hub: the hub NAT gateway would send it back into the Transit
Gateway and the other spoke would answer (I saw exactly that in the first real drill). So each spoke
table also has a blackhole route for the private supernet; longest-prefix match keeps the /16 routes
that are allowed working and drops the rest.

**A bug the design avoids: the return path.** Outbound traffic from a spoke goes spoke, Transit
Gateway, hub attachment subnet, NAT, internet gateway. The reply comes back to the NAT gateway,
which translates it and sends it to a private address. That packet needs a route back: the hub's
public route table sends the `10.0.0.0/8` range to the Transit Gateway, and the hub's Transit
Gateway table must know the spoke. Miss either and the connection hangs with no error. This is the
classic asymmetric routing problem.

**What is appliance mode?** When the hub inspects traffic with a firewall, a flow must use the
same firewall in both directions. Appliance mode on the hub attachment keeps a flow on one network
interface across zones. It is off here because there is no firewall, and it is the first thing to
switch on when one is added.

**What if two spokes have the same CIDR?** They cannot be routed to each other. Plan CIDRs up
front (here each spoke is its own `/16` out of `10.0.0.0/8`). If a spoke cannot be renumbered, a
private NAT gateway can translate it, with a lot of extra complexity.

## Security layers

**Network ACL versus security group?** A security group is stateful, attached to an interface,
allow-only. A network ACL is stateless, attached to a subnet, has numbered allow and deny rules
evaluated in order, so return traffic must be allowed explicitly. I use the security group for the
tight rules and the ACL as a subnet-level backstop. The ACL's wide ephemeral-port rule for replies
is a necessity of being stateless, and the scanner flags it, so the skip comment says why.

**Why no SSH?** The probe instances have no key pair, no public IP and no inbound path from the
internet. Access is through Session Manager, so there is no port to scan and every session is
logged. The instance requires the version 2 metadata service.

**What are the endpoints for?** The S3 gateway endpoint is free and keeps S3 traffic off the NAT
path. The Systems Manager interface endpoints give a private path to those APIs. They cost money
per zone per hour, so they are off by default and the lab works through NAT without them.

## DNS

**How do names resolve across VPCs?** One private hosted zone associated with every VPC. Each VPC's
resolver answers for the zone, so `data.corp.internal` resolves everywhere. For on-premises names
you would add Route 53 Resolver endpoints and rules.

**Does resolving a name mean you can connect?** No. DNS returns an address. Whether a packet
reaches it is decided by routes, the network ACL and the security groups. In the isolation drill
the name still resolves while the connection times out, which is a good way to show the difference.

## Proving it

**How do you know the network does what you say?** Three levels. Mocked tests check the
configuration logic (which routes exist, which attachment learns which). Reachability Analyzer asks
AWS whether a path exists by reading the real configuration, without sending traffic, and names
the component that blocks it. Real requests from the probe instances confirm the packets flow.
All three levels were done on 2026-11-20, and the real requests caught what the first two did not (ping and the hairpin).

**What would you check first if app cannot reach data?** Name resolves? Then the route on the
source subnet, then the source's Transit Gateway table for the destination range, then the
destination's attachment and its return route, then the network ACL on both subnets, then the
security groups. The analyzer walks that list for you.

## Cost and design trade-offs

**What does central egress cost and save?** It saves one NAT gateway per VPC and gives one place to
filter and log outbound traffic. It costs a per-GB Transit Gateway data charge on all outbound
traffic and makes the hub's NAT a shared dependency. For heavy outbound traffic from many VPCs,
compare against NAT per VPC.

**What would you add for production?** A firewall in the hub with appliance mode, a NAT gateway per
zone, Transit Gateway flow logs, a separate route table for a VPN, customer-managed keys for logs,
and the pipeline and remote state from the sibling repository.

## Questions to expect that this repo cannot answer yet

- Real Reachability Analyzer output and a real troubleshooting story. Do the runbook before the
  interview and tell that story with the actual explanation codes.
- Direct Connect, BGP and a VPN attachment. Say you know where they attach and that you have not
  built them.

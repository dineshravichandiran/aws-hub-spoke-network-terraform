# Runbook: apply the lab, prove the network, destroy it

Do this in one sitting so the lab exists for a few hours, not days. Budget about two hours.
The first apply takes around ten minutes because Transit Gateway attachments and the NAT gateway
are slow to create.

## 0. What you need

- An AWS account you own and credentials that can create the resources (an admin login is simplest).
- AWS CLI v2 signed in (`aws sts get-caller-identity` works), Terraform 1.10 or newer.
- The AWS Session Manager plugin for the CLI, to open a shell on the probe instances.

## 1. Apply

```bash
cd envs/lab
terraform init
terraform plan -out tfplan        # read it before you apply
terraform apply tfplan
terraform output
```

State is local (`envs/lab/terraform.tfstate`, not committed). **Screenshot** the plan summary.

## 2. Prove it works

Take the instance IDs from `terraform output probe_instance_ids`.

```bash
aws ssm start-session --target <app probe instance id>
```

Inside the app probe:

```bash
curl -s http://data.corp.internal:8080     # private name resolves, spoke-to-spoke works: "hello from ...-data-probe"
ping -c 3 <data probe private ip>
getent hosts data.corp.internal      # the private name resolves to the data probe address
curl -sI https://example.com | head -1     # internet through the hub NAT
curl -s https://checkip.amazonaws.com      # shows the hub NAT gateway's address, not the instance's
```

The last one is the proof of central egress: both spokes show the same public address.
It must also match the NAT gateway's Elastic IP in the console. **Screenshot** it.

Instances need a minute or two after creation before Session Manager works, and Session Manager
needs a route out (the NAT path) unless you set `enable_interface_endpoints = true`.

## 3. Ask AWS with Reachability Analyzer

```bash
terraform output spoke_to_spoke_path_ids
terraform output spoke_to_internet_path_ids

ID=$(aws ec2 start-network-insights-analysis --network-insights-path-id <path id> \
       --query 'NetworkInsightsAnalysis.NetworkInsightsAnalysisId' --output text)
aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$ID" \
  --query 'NetworkInsightsAnalyses[0].{status:Status,reachable:NetworkPathFound,why:Explanations[].ExplanationCode}'
```

Run it for app to data, data to app, and each spoke to the internet. Expected: reachable. Each
analysis costs a few cents. **Screenshot** the console's path view for one of them: it draws every
hop through the Transit Gateway.

## 4. Drill: cut the spokes off from each other

Edit `envs/lab/variables.tf` and set the `allowed_flows` default to `[]`, then:

```bash
terraform apply
```

Re-run the app-to-data analysis. Expected: not reachable, with an explanation that points at the
missing route. From the app probe, `curl --max-time 5 http://data.corp.internal:8080` should time
out, while the internet request still works. The name still resolves: DNS answering is not the
same as being allowed to connect. Write down what the explanation code says.

Restore `allowed_flows = [["app", "data"]]` afterwards if you want to repeat step 2.

## 5. Drill: find a blocked port

In the console, add a **deny** inbound rule (rule number 50, TCP 8080, source `10.1.0.0/16`) to the
data spoke's workload network ACL. Run the app-to-data analysis again. Expected: not reachable, and
the explanation names the network ACL rule. Delete the rule afterwards. Write down how long it took
to find the cause with the analyzer and how long it would take by hand.

## 6. Look at the flow logs

CloudWatch Logs, log group `/vpc/hub-spoke-lab-data/flow-logs`. During drill 4 you should see
`REJECT` or no accepted entries for the app address. Note one line that shows a drop.

## 7. Destroy the same day

```bash
cd envs/lab
terraform destroy
```

Transit Gateway attachments can take several minutes to delete. If the destroy errors, run it again.

## 8. Confirm nothing is left running

```bash
aws ec2 describe-transit-gateways --filters Name=state,Values=available --query 'TransitGateways[].TransitGatewayId'
aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayId'
aws ec2 describe-instances --filters Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'
aws ec2 describe-addresses --query 'Addresses[].PublicIp'
aws ec2 describe-vpc-endpoints --query 'VpcEndpoints[].VpcEndpointId'
```

All should be empty (or show only things that are not part of this lab). Check Cost Explorer the
next day, grouped by the `Project` tag.

## 9. Update the README

Only after steps 1 to 8 are done, change the "not done yet" rows in the README's table to "done"
with the date, add your screenshots and the analyzer output to `docs/evidence/`, and remove the
"not yet applied" status line. Until then the README must keep saying it has not been applied.

## Common first-run problems

| Symptom | Likely cause |
|---|---|
| Session Manager cannot connect | Instance has no route out yet (NAT still creating), or it was created before the Transit Gateway routes. Wait, or set `enable_interface_endpoints = true` |
| Internet works from the hub but not from a spoke | A missing return route: the hub's public route table must send `10.0.0.0/8` to the Transit Gateway |
| App cannot reach data, analyzer says no route | `allowed_flows` does not list the pair, or the propagation has not finished |
| The spoke-to-internet analyzer path errors or reports no path | The path uses the hub's internet gateway as its destination with a public address; if AWS rejects that combination, test internet egress with the `checkip` request in step 2 instead and record that in the evidence |
| `terraform destroy` fails on a Transit Gateway attachment | Attachments are still deleting. Wait a few minutes and run destroy again |

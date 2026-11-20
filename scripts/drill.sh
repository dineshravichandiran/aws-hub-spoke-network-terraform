#!/usr/bin/env bash
# Helper for docs/RUNBOOK.md steps 2 to 4. Run from anywhere with AWS credentials and a state in envs/lab.
# It uses SSM Run Command (no Session Manager plugin needed) and Reachability Analyzer.
#   scripts/drill.sh prove     # name resolution, spoke to spoke, internet through the hub NAT
#   scripts/drill.sh analyze   # run every Reachability Analyzer path and print the result
#   scripts/drill.sh nacl      # runbook step 5: deny TCP 8080 from the app range in the data spoke ACL, ask the analyzer, restore
#   scripts/drill.sh flowlogs  # runbook step 6: show REJECT lines from the data spoke flow logs
set -uo pipefail
cd "$(dirname "$0")/../envs/lab"

jq_get() { python3 -c "import json,sys; d=json.load(sys.stdin); print(d[sys.argv[1]])" "$1"; }
IDS=$(terraform output -json probe_instance_ids)
IPS=$(terraform output -json probe_private_ips)
APP=$(echo "$IDS" | jq_get app)
DATA=$(echo "$IDS" | jq_get data)
DATA_IP=$(echo "$IPS" | jq_get data)

ssm_run() { # <instance id> <shell command>
  local params cid st
  params=$(python3 -c 'import json,sys; print(json.dumps({"commands":[sys.argv[1]]}))' "$2")
  cid=$(aws ssm send-command --instance-ids "$1" --document-name AWS-RunShellScript \
        --parameters "$params" --query Command.CommandId --output text) || return 1
  for _ in $(seq 1 40); do
    st=$(aws ssm get-command-invocation --command-id "$cid" --instance-id "$1" --query Status --output text 2>/dev/null)
    case "$st" in Success|Failed|TimedOut|Cancelled) break ;; esac
    sleep 3
  done
  echo "  status: $st"
  aws ssm get-command-invocation --command-id "$cid" --instance-id "$1" \
    --query '[StandardOutputContent,StandardErrorContent]' --output text | sed 's/^/  | /'
}

analyze_all() { # optional $1: only paths whose name contains this text
  for out in spoke_to_spoke_path_ids spoke_to_internet_path_ids; do
    terraform output -json "$out" | python3 -c 'import json,sys; [print(k, v) for k, v in json.load(sys.stdin).items()]' |
    while read -r name pid; do
      case "$name" in *"${1:-}"*) ;; *) continue ;; esac
      id=$(aws ec2 start-network-insights-analysis --network-insights-path-id "$pid" \
           --query NetworkInsightsAnalysis.NetworkInsightsAnalysisId --output text)
      for _ in $(seq 1 40); do
        st=$(aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$id" \
             --query 'NetworkInsightsAnalyses[0].Status' --output text)
        [ "$st" != running ] && break
        sleep 3
      done
      echo "== $out / $name"
      aws ec2 describe-network-insights-analyses --network-insights-analysis-ids "$id" \
        --query 'NetworkInsightsAnalyses[0].{status:Status,reachable:NetworkPathFound,why:Explanations[].ExplanationCode,aclRule:Explanations[].NetworkAclRule,msg:StatusMessage}' --output json
    done
  done
}

case "${1:-}" in
  prove)
    date -u +%FT%TZ
    echo "## app probe: private name, spoke to spoke, internet"
    ssm_run "$APP" "getent hosts data.corp.internal; curl -s --max-time 5 http://data.corp.internal:8080; ping -c 3 -W 2 $DATA_IP | tail -2; curl -sI --max-time 8 https://example.com | head -1; echo -n 'egress address (app): '; curl -s --max-time 8 https://checkip.amazonaws.com"
    echo "## data probe: internet"
    ssm_run "$DATA" "echo -n 'egress address (data): '; curl -s --max-time 8 https://checkip.amazonaws.com"
    echo "## hub NAT gateway address"
    aws ec2 describe-nat-gateways --filter Name=state,Values=available --query 'NatGateways[].NatGatewayAddresses[].PublicIp' --output text
    ;;
  analyze)
    date -u +%FT%TZ
    analyze_all
    ;;
  nacl)
    NACL=$(aws ec2 describe-network-acls --filters Name=tag:Name,Values=hub-spoke-lab-data-workload \
           --query 'NetworkAcls[0].NetworkAclId' --output text)
    echo "data spoke workload ACL: $NACL"
    echo "## before: app to data on 8080"
    ssm_run "$APP" "curl -s --max-time 5 http://data.corp.internal:8080; echo curl-exit=\$?"
    T0=$(date +%s); date -u +%FT%TZ
    echo "## adding deny rule 50: TCP 8080 from 10.1.0.0/16"
    aws ec2 create-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 50 --protocol tcp \
      --port-range From=8080,To=8080 --cidr-block 10.1.0.0/16 --rule-action deny
    echo "## analyzer: app-to-data"
    analyze_all app-to-data
    echo "seconds from adding the rule to the analyzer naming it: $(( $(date +%s) - T0 ))"
    echo "## real request while the rule exists"
    ssm_run "$APP" "curl -s --max-time 5 http://data.corp.internal:8080; echo curl-exit=\$?"
    echo "## (flow logs: run '$0 flowlogs' in a few minutes)"
    echo "## removing the rule"
    aws ec2 delete-network-acl-entry --network-acl-id "$NACL" --ingress --rule-number 50
    date -u +%FT%TZ
    sleep 5
    ssm_run "$APP" "curl -s --max-time 5 http://data.corp.internal:8080; echo curl-exit=\$?"
    ;;
  flowlogs)
    START=$(( ($(date +%s) - ${2:-1800}) * 1000 ))
    aws logs filter-log-events --log-group-name /vpc/hub-spoke-lab-data/flow-logs --filter-pattern REJECT \
      --start-time "$START" --max-items 8 --query 'events[].message' --output text | tr '\t' '\n'
    ;;
  *) echo "usage: $0 prove|analyze|nacl|flowlogs"; exit 2 ;;
esac

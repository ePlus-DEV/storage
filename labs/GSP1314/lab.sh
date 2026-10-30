#!/usr/bin/env bash
# Copyright (c) 2026 ePlus.DEV | Unlicense
set -Eeuo pipefail

if [[ -v NO_COLOR ]]; then C1='' C2='' C3='' RESET='';
elif [[ -t 1 || "${FORCE_COLOR:-0}" == 1 ]]; then
  C1=$'\033[1;36m'; C2=$'\033[1;32m'; C3=$'\033[1;33m'; RESET=$'\033[0m'
else C1='' C2='' C3='' RESET=''; fi
log() { printf '%s%s%s\n' "$C1" "$*" "$RESET"; }
ok() { printf '%s%s%s\n' "$C2" "$*" "$RESET"; }
warn() { printf '%s%s%s\n' "$C3" "$*" "$RESET"; }
trap 'warn "Execution failed at line $LINENO (exit $?)."' ERR
printf '%s\n' "${C1}ePlus.DEV – Starting Execution${RESET}" 'GSP1314 — Aeron Cluster (static validated only; runtime/grader unverified)'
for cmd in gcloud awk grep sed java; do
  if [[ "$cmd" == java ]]; then continue; fi
  command -v "$cmd" >/dev/null || { warn "Missing required command: $cmd"; exit 1; }
done
PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null)}"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != '(unset)' ]] || { warn 'Select a Google Cloud lab project first.'; exit 1; }
declare -A ZONES IPS
VMS=(aeron-cluster-node1 aeron-cluster-node2 aeron-cluster-node3)
for vm in "${VMS[@]}"; do
  zone="$(gcloud compute instances list --project="$PROJECT_ID" --filter="name=$vm" --format='value(zone.basename())' | head -n 1)"
  [[ -n "$zone" ]] || { warn "Preprovisioned VM $vm not found"; exit 1; }
  ZONES["$vm"]="$zone"
  ip="$(gcloud compute instances describe "$vm" --project="$PROJECT_ID" --zone="$zone" --format='value(networkInterfaces[0].networkIP)')"
  [[ "$ip" =~ ^[0-9.]+$ ]] || { warn "No private IP for $vm"; exit 1; }
  IPS["$vm"]="$ip"
done
HOST_NAMES="${IPS[${VMS[0]}]},${IPS[${VMS[1]}]},${IPS[${VMS[2]}]}"
remote() {
  local vm="$1" script="$2" attempt
  for attempt in 1 2 3; do
    if gcloud compute ssh "$vm" --project="$PROJECT_ID" --zone="${ZONES[$vm]}" --quiet --command="bash -lc $(printf '%q' "$script")"; then return 0; fi
    warn "SSH retry $attempt/3 for $vm"; sleep 8
  done
  return 1
}
start_node() {
  local idx="$1" vm="${VMS[$1]}" script
  script="set -e
export THIS_HOST='${IPS[$vm]}' HOST_NAMES='$HOST_NAMES' JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64
cd \"\$HOME/aeron/aeron-samples/scripts/cluster\"
if ! grep -q 'java.base/sun.nio.ch=ALL-UNNAMED' script-common; then
  sed -i '/^ADD_OPENS=/ s|\"\$| --add-opens java.base/sun.nio.ch=ALL-UNNAMED\"|' script-common
fi
pidfile=\"\$HOME/.eplus-aeron-${idx}.pid\"
if [[ -f \"\$pidfile\" ]] && kill -0 \"\$(cat \"\$pidfile\")\" 2>/dev/null && [[ \"\$(ps -o stat= -p \"\$(cat \"\$pidfile\")\" 2>/dev/null)\" != Z* ]]; then
  echo 'Aeron node ${idx} already running'; exit 0
fi
nohup ./basic-auction-cluster ${idx} > \"\$HOME/aeron-node-${idx}.log\" 2>&1 < /dev/null &
echo \"\$!\" > \"\$pidfile\"
sleep 2
kill -0 \"\$(cat \"\$pidfile\")\" 2>/dev/null || { tail -n 30 \"\$HOME/aeron-node-${idx}.log\"; exit 1; }
echo 'Aeron node ${idx} started'"
  remote "$vm" "$script"
}
cluster_tool() {
  local idx="$1" vm="${VMS[$1]}" action="$2" script
  script="set -e; cd \"\$HOME/aeron/aeron-samples/scripts/cluster\"; jar=\$(find \"\$HOME/aeron/aeron-all/build/libs\" -maxdepth 1 -name 'aeron-all-*.jar' -print -quit); [[ -n \"\$jar\" ]]; java -cp \"\$jar\" io.aeron.cluster.ClusterTool node${idx}/cluster ${action}"
  remote "$vm" "$script"
}
get_leader() {
  local idx="$1" result
  result="$(cluster_tool "$idx" list-members 2>/dev/null || true)"
  if [[ "$result" =~ leaderMemberId=([012]) ]]; then printf '%s' "${BASH_REMATCH[1]}"; else return 1; fi
}
log '== Task 1/5 — Start the three preprovisioned Aeron nodes =='
for idx in 0 1 2; do start_node "$idx"; done
leader=''
for attempt in {1..12}; do
  leader="$(get_leader 0 || true)"
  [[ "$leader" =~ ^[012]$ ]] && break
  sleep 5
done
[[ "$leader" =~ ^[012]$ ]] || { warn 'Leader election not confirmed'; exit 1; }
ok "Cluster leader: member $leader"
log '== Task 2/5 — Submit 20 auction bids =='
remote "${VMS[0]}" "set -e; export THIS_HOST='${IPS[${VMS[0]}]}' HOST_NAMES='$HOST_NAMES' JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; cd \"\$HOME/aeron/aeron-samples/scripts/cluster\"; ./basic-auction-client 101 20"
ok '20-bid client completed'
log '== Task 3/5 — Inspect cluster statistics and membership =='
remote "${VMS[0]}" "cd \"\$HOME/aeron/aeron-samples/scripts\"; ./aeron-stat watch=false | head -n 25" || warn 'AeronStat unavailable; continuing with cluster tools'
cluster_tool 0 describe
cluster_tool 0 list-members
log '== Task 4/5 — Stop current leader and verify failover =='
leader="$(get_leader 0)"
[[ "$leader" =~ ^[012]$ ]] || exit 1
leader_vm="${VMS[$leader]}"
remote "$leader_vm" "set -e; cd \"\$HOME/aeron/aeron-samples/scripts/cluster\"; jar=\$(find \"\$HOME/aeron/aeron-all/build/libs\" -maxdepth 1 -name 'aeron-all-*.jar' -print -quit); pid=\$(java -cp \"\$jar\" io.aeron.cluster.ClusterTool node${leader}/cluster pid | tr -dc '0-9'); [[ \"\$pid\" =~ ^[0-9]+\$ ]]; ps -p \"\$pid\" -o args= | grep -qi aeron; kill -9 \"\$pid\"; echo \"Stopped Aeron member ${leader}\""
new_leader=''
probe=$(( (leader + 1) % 3 ))
for attempt in {1..18}; do
  new_leader="$(get_leader "$probe" || true)"
  [[ "$new_leader" =~ ^[012]$ && "$new_leader" != "$leader" ]] && break
  sleep 5
done
[[ "$new_leader" =~ ^[012]$ && "$new_leader" != "$leader" ]] || { warn 'New leader not confirmed'; exit 1; }
ok "New leader: member $new_leader"
log '== Task 5/5 — Submit 300 bids and rejoin previous leader =='
new_vm="${VMS[$new_leader]}"
remote "$new_vm" "set -e; export THIS_HOST='${IPS[$new_vm]}' HOST_NAMES='$HOST_NAMES' JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64; cd \"\$HOME/aeron/aeron-samples/scripts/cluster\"; nohup ./basic-auction-client 101 300 > \"\$HOME/aeron-bids-300.log\" 2>&1 < /dev/null & echo '300-bid client launched'"
start_node "$leader"
for attempt in {1..12}; do
  if cluster_tool "$leader" list-members >/dev/null 2>&1; then break; fi
  sleep 5
done
cluster_tool "$new_leader" list-members
ok 'Aeron cluster workflow complete. Check all four Google Skills checkpoints manually.'
warn 'static validated only; runtime/grader unverified'

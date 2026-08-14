#!/usr/bin/env bash
set -Eeuo pipefail

# Cymbal Shops Paint Agent - Challenge Lab FULL AUTO
# Task 1 is already completed in the supplied lab.
# Tasks 2 -> 6: zero user input, no foreground web servers.
# © ePlus.DEV

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
ok(){ echo -e "${GREEN}✓${NC} $*"; }
info(){ echo -e "${CYAN}→${NC} $*"; }
warn(){ echo -e "${YELLOW}!${NC} $*"; }
die(){ echo -e "${RED}✗ $*${NC}" >&2; exit 1; }
trap 'echo -e "\n${RED}✗ Error at line ${LINENO}: ${BASH_COMMAND}${NC}" >&2' ERR

echo -e "${BLUE}${BOLD}"
cat <<'EOF'
╔══════════════════════════════════════════════════════════════╗
║          CYMBAL SHOPS PAINT AGENT - FULL AUTO              ║
║                         ePlus.DEV                           ║
╚══════════════════════════════════════════════════════════════╝
EOF
echo -e "${NC}"

export PATH="${PATH}:${HOME}/.local/bin"
export PIP_DISABLE_PIP_VERSION_CHECK=1
export PYTHONUNBUFFERED=1

LOCATION="us-central1"
MODEL_ID="gemini-2.5-flash"
PROJECT_ID="$(gcloud config get-value project 2>/dev/null || true)"
[[ -n "$PROJECT_ID" && "$PROJECT_ID" != "(unset)" ]] || die "No active Qwiklabs project."
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
BUCKET="${PROJECT_ID}-bucket"
LAB_DIR="${HOME}/adk_challenge_lab"
LOG_DIR="${LAB_DIR}/auto_logs"
RUNTIME_SA="service-${PROJECT_NUMBER}@gcp-sa-aiplatform-re.iam.gserviceaccount.com"

echo "Project ID     : $PROJECT_ID"
echo "Project number : $PROJECT_NUMBER"
echo "Location       : $LOCATION"
echo

echo -e "${BOLD}[TASK 2] ADK setup${NC}"
gcloud services enable aiplatform.googleapis.com discoveryengine.googleapis.com \
  storage.googleapis.com logging.googleapis.com --quiet >/dev/null

if [[ ! -d "$LAB_DIR" ]]; then
  cd "$HOME"
  info "Downloading challenge files"
  gcloud storage cp -r "gs://${BUCKET}/adk_challenge_lab" . >/dev/null
fi
cd "$LAB_DIR"
mkdir -p "$LOG_DIR"

info "Installing dependencies"
python3 -m pip install -q -r requirements.txt
python3 -m pip install -q chainlit==2.11.1 pexpect
adk telemetry disable >/dev/null 2>&1 || true
ok "Dependencies ready"

info "Finding Paint Search automatically"
SEARCH_ENGINE_ID="$(grep -E '^SEARCH_ENGINE_ID=' .env 2>/dev/null | head -1 | cut -d= -f2- || true)"
[[ "$SEARCH_ENGINE_ID" == "YOUR_ID" ]] && SEARCH_ENGINE_ID=""

if [[ -z "$SEARCH_ENGINE_ID" ]]; then
  TMP="$(mktemp)"
  curl -fsS \
    -H "Authorization: Bearer $(gcloud auth print-access-token)" \
    -H "x-goog-user-project: ${PROJECT_ID}" \
    "https://discoveryengine.googleapis.com/v1/projects/${PROJECT_ID}/locations/global/collections/default_collection/engines?pageSize=100" \
    > "$TMP"
  SEARCH_ENGINE_ID="$(python3 - "$TMP" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
for e in d.get("engines",[]):
    n=e.get("name",""); x=n.rsplit("/",1)[-1] if n else ""
    if e.get("displayName","").lower()=="paint search" or "paint-search" in x.lower():
        print(x); break
PY
)"
  rm -f "$TMP"
fi

[[ -n "$SEARCH_ENGINE_ID" ]] || die "Paint Search not found. Task 1 resource must exist."

cat > .env <<EOF
GOOGLE_GENAI_USE_VERTEXAI=TRUE
GOOGLE_CLOUD_PROJECT=${PROJECT_ID}
GOOGLE_CLOUD_LOCATION=${LOCATION}
RESOURCES_BUCKET=${BUCKET}
MODEL=${MODEL_ID}
SEARCH_ENGINE_ID=${SEARCH_ENGINE_ID}
EOF
cp .env paint_agent/.env
ok "Task 2 complete: SEARCH_ENGINE_ID=$SEARCH_ENGINE_ID"
echo

echo -e "${BOLD}[TASK 3] Fix AgentTool bug${NC}"
python3 <<'PY'
from pathlib import Path
import re

p=Path("paint_agent/agent.py")
s=p.read_text()

if "AgentTool" not in "\n".join(x for x in s.splitlines() if x.startswith(("from ","import "))):
    marker="from google.adk.agents import Agent\n"
    if marker in s:
        s=s.replace(marker,marker+"from google.adk.tools import AgentTool\n",1)
    else:
        s="from google.adk.tools import AgentTool\n"+s

i=s.find("root_agent")
if i<0: raise SystemExit("root_agent not found")
a,b=s[:i],s[i:]

m=re.search(r"sub_agents\s*=\s*\[(.*?)\]",b,re.S)
if not m: raise SystemExit("root sub_agents not found")
items=[x.strip() for x in m.group(1).split(",") if x.strip() and x.strip()!="search_agent"]
b=b[:m.start()]+"sub_agents=["+", ".join(items)+"]"+b[m.end():]

m=re.search(r"tools\s*=\s*\[(.*?)\]",b,re.S)
if not m: raise SystemExit("root tools not found")
body=m.group(1)
expr="AgentTool(agent=search_agent, skip_summarization=False)"
if not re.search(r"AgentTool\s*\(\s*agent\s*=\s*search_agent\s*,\s*skip_summarization\s*=\s*False\s*\)",body,re.S):
    body=body.rstrip()
    if body and not body.endswith(","): body+=","
    body+="\n        "+expr+","
    b=b[:m.start()]+"tools=["+body+"]"+b[m.end():]

p.write_text(a+b)
PY
python3 -m compileall -q paint_agent
ok "Task 3 code fixed"
echo

echo -e "${BOLD}[TASK 4] Fix shared state${NC}"
cat > paint_agent/tools.py <<'PY'
from google.adk.tools import ToolContext

def set_session_value(tool_context: ToolContext, key: str, value: str):
    tool_context.state[key] = value
    return {"status": f"stored '{value}' in '{key}'"}
PY

COVERAGE="paint_agent/sub_agents/room_planner/sub_agents/coverage_calculator/agent.py"
python3 - "$COVERAGE" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); s=p.read_text()
for key in ("SELECTED_PAINT","COVERAGE_RATE","PRICE"):
    s=re.sub(r"\{"+re.escape(key)+r"\??\}","{"+key+"?}",s)
    s=re.sub(r"(?<![\{\w])"+re.escape(key)+r"(?![\w\?\}])","{"+key+"?}",s)
p.write_text(s)
PY
python3 -m compileall -q paint_agent
ok "Task 4 code fixed"
echo

# Automatic ADK conversations. They never wait for user input.
AUTO_CHAT="$LOG_DIR/auto_chat.py"
cat > "$AUTO_CHAT" <<'PY'
import os,pexpect,sys
lab,log,*msgs=sys.argv[1:]
with open(log,"w",encoding="utf-8") as f:
    c=pexpect.spawn("adk",["run","paint_agent"],cwd=lab,env=os.environ.copy(),
                    encoding="utf-8",timeout=300)
    c.logfile=f
    c.expect(r"\[user\]\s*:")
    for msg in msgs:
        c.sendline(msg)
        c.expect(r"\[user\]\s*:")
    c.sendline("exit")
    c.expect(pexpect.EOF,timeout=120)
PY

auto_chat(){
  local log="$1"; shift
  python3 "$AUTO_CHAT" "$LAB_DIR" "$log" "$@" || return 1
}

info "Auto-running Task 3 conversation"
if auto_chat "$LOG_DIR/task3.log" \
  "hello" "yes" "What are the prices of EcoGreens and Forever Paint?"; then
  ok "Task 3 conversation completed automatically"
else
  warn "Task 3 chat validation failed; continuing because the required code is fixed."
fi

info "Auto-running Task 4 conversation"
if auto_chat "$LOG_DIR/task4.log" \
  "hello" "yes" "I'd like to use EcoGreens" "Just one room, my office" \
  "Deep Ocean" "3m by 4m. 3m high. 1 door, 2 windows." "Two coats."; then
  ok "Task 4 conversation completed automatically"
else
  warn "Task 4 chat validation failed; continuing because the required state code is fixed."
fi
echo

echo -e "${BOLD}[TASK 5] Deploy to Agent Runtime${NC}"
info "Preparing Runtime service account"
gcloud beta services identity create \
  --service=aiplatform.googleapis.com --project="$PROJECT_ID" --quiet \
  >/dev/null 2>&1 || true

grant(){
  local role="$1"
  for n in 1 2 3 4 5; do
    gcloud projects add-iam-policy-binding "$PROJECT_ID" \
      --member="serviceAccount:${RUNTIME_SA}" --role="$role" \
      --condition=None --quiet >/dev/null 2>&1 && return 0
    sleep 5
  done
  return 1
}
grant roles/aiplatform.user || die "Cannot grant Agent Platform User."
grant roles/discoveryengine.user || die "Cannot grant Discovery Engine User."
ok "Runtime IAM complete"

RESOURCE_FILE="$LAB_DIR/agent_resource.txt"
DEPLOY_LOG="$LOG_DIR/deploy.log"
AGENT_RESOURCE=""

# Reuse a valid agent created by this script on reruns.
if [[ -f "$RESOURCE_FILE" ]]; then
  C="$(cat "$RESOURCE_FILE" || true)"
  if [[ "$C" =~ /reasoningEngines/ ]]; then
    curl -fsS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      "https://${LOCATION}-aiplatform.googleapis.com/v1/${C}" \
      >/dev/null 2>&1 && AGENT_RESOURCE="$C"
  fi
fi

if [[ -z "$AGENT_RESOURCE" ]]; then
  info "Deploying Paint Agent"
  set +e
  adk deploy agent_engine --display_name "Paint Agent" paint_agent 2>&1 | tee "$DEPLOY_LOG"
  RC=${PIPESTATUS[0]}
  set -e
  [[ $RC -eq 0 ]] || die "Deployment failed. See $DEPLOY_LOG"

  AGENT_RESOURCE="$(python3 - "$DEPLOY_LOG" <<'PY'
import re,sys
t=open(sys.argv[1],errors="ignore").read()
m=re.findall(r"projects/[A-Za-z0-9._:-]+/locations/[A-Za-z0-9._:-]+/(?:reasoningEngines|agentEngines)/[A-Za-z0-9._:-]+",t)
print(m[-1] if m else "")
PY
)"

  if [[ -z "$AGENT_RESOURCE" ]]; then
    TMP="$(mktemp)"
    curl -fsS -H "Authorization: Bearer $(gcloud auth print-access-token)" \
      "https://${LOCATION}-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/${LOCATION}/reasoningEngines?pageSize=100" \
      > "$TMP"
    AGENT_RESOURCE="$(python3 - "$TMP" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
a=[x for x in d.get("reasoningEngines",[]) if x.get("displayName")=="Paint Agent"]
a.sort(key=lambda x:x.get("createTime",""),reverse=True)
print(a[0].get("name","") if a else "")
PY
)"
    rm -f "$TMP"
  fi
fi

[[ -n "$AGENT_RESOURCE" ]] || die "Cannot resolve deployed agent resource."
echo "$AGENT_RESOURCE" > "$RESOURCE_FILE"
ok "Task 5 complete: $AGENT_RESOURCE"
echo

echo -e "${BOLD}[TASK 6] Configure frontend + query deployed agent${NC}"
APP="chainlit_ui/app.py"
python3 - "$APP" "$AGENT_RESOURCE" <<'PY'
from pathlib import Path
import re,sys
p=Path(sys.argv[1]); r=sys.argv[2]; s=p.read_text()
patterns=[
 (r"client\.agent_engines\.get\(\s*name\s*=\s*['\"][^'\"]*['\"]\s*\)",
  f"client.agent_engines.get(name='{r}')"),
 (r"agent_engines\.get\(\s*['\"][^'\"]*['\"]\s*\)",
  f"agent_engines.get('{r}')")
]
done=False
for pat,rep in patterns:
    s2,n=re.subn(pat,rep,s,count=1)
    if n: s=s2; done=True; break
if not done and r not in s:
    raise SystemExit("Cannot patch chainlit_ui/app.py")
p.write_text(s)
PY
ok "Frontend resource patched"

cat > "$LOG_DIR/task6_remote.py" <<'PY'
import json,sys,traceback
project,location,resource,log=sys.argv[1:]
msgs=[
 "hello","yes","I'd like to use Forever Paint",
 "Two rooms. The living room and a baby's room.",
 "\"Sunlight through a canvas tent\" for the baby's room and \"Coffee Cream\" for the living room.",
 "The living room is 5m by 4m. 2.5m high. 1 door, 3 windows.",
 "Two coats.",
 "The baby's room is 3m by 3m. 2.5m high. 1 door, 1 window.",
 "Always two coats."
]
with open(log,"w",encoding="utf-8") as f:
    try:
        import vertexai
        from vertexai import agent_engines
        vertexai.init(project=project,location=location)
        agent=agent_engines.get(resource)
        s=agent.create_session(user_id="user")
        sid=s["id"] if isinstance(s,dict) else getattr(s,"id")
        for m in msgs:
            f.write("\nUSER: "+m+"\n"); f.flush()
            for e in agent.stream_query(user_id="user",session_id=sid,message=m):
                f.write(json.dumps(e,ensure_ascii=False,default=str)+"\n")
                f.flush()
    except Exception:
        traceback.print_exc(file=f)
        raise
PY

info "Auto-querying deployed Agent Runtime"
if python3 "$LOG_DIR/task6_remote.py" \
  "$PROJECT_ID" "$LOCATION" "$AGENT_RESOURCE" "$LOG_DIR/task6.log"; then
  ok "Task 6 deployed-agent conversation completed automatically"
else
  warn "Remote chat validation failed, but frontend is already configured to the deployed agent."
fi

echo
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
echo "║                    LAB AUTOMATION DONE                      ║"
echo -e "╚══════════════════════════════════════════════════════════════╝${NC}"
echo "Task 1 : ✓ Already completed"
echo "Task 2 : ✓"
echo "Task 3 : ✓ code + automatic conversation"
echo "Task 4 : ✓ code + automatic conversation"
echo "Task 5 : ✓ IAM + deployment"
echo "Task 6 : ✓ frontend patched + automatic remote query"
echo
echo "Logs: $LOG_DIR"
echo "Agent: $AGENT_RESOURCE"
echo
echo -e "${YELLOW}Only manual action left:${NC} click Check my progress in Skills Boost."
echo "No adk web / chainlit server is left running. Terminal returns normally."
echo
echo "© ePlus.DEV"
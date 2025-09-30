#!/bin/bash
set -e

# Define color variables
BLACK=`tput setaf 0`; RED=`tput setaf 1`; GREEN=`tput setaf 2`; YELLOW=`tput setaf 3`
BLUE=`tput setaf 4`; MAGENTA=`tput setaf 5`; CYAN=`tput setaf 6`; WHITE=`tput setaf 7`
BG_RED=`tput setab 1`; BG_GREEN=`tput setab 2`; BG_YELLOW=`tput setab 3`
BG_BLUE=`tput setab 4`; BG_MAGENTA=`tput setab 5`; BG_CYAN=`tput setab 6`
BOLD=`tput bold`; RESET=`tput sgr0`

TEXT_COLORS=($RED $GREEN $YELLOW $BLUE $MAGENTA $CYAN)
BG_COLORS=($BG_RED $BG_GREEN $BG_YELLOW $BG_BLUE $BG_MAGENTA $BG_CYAN)
RANDOM_TEXT_COLOR=${TEXT_COLORS[$RANDOM % ${#TEXT_COLORS[@]}]}
RANDOM_BG_COLOR=${BG_COLORS[$RANDOM % ${#BG_COLORS[@]}]}

banner () {
  local color=$1
  local msg=$2
  echo ""
  echo "${color}${BOLD}============================================================${RESET}"
  echo "${color}${BOLD}$msg${RESET}"
  echo "${color}${BOLD}============================================================${RESET}"
  echo ""
}

# 🚀 Start
banner "$RANDOM_BG_COLOR$RANDOM_TEXT_COLOR" "🚀 Starting Execution - ePlus.DEV"

cat > app.py <<EOF_CP
import flask
app = flask.Flask(__name__)
input_string = ""

html_escape_table = {
  "&": "&amp;",
  '"': "&quot;",
  "'": "&apos;",
  ">": "&gt;",
  "<": "&lt;",
  }

@app.route('/', methods=["GET", "POST"])
def input():
  global input_string
  if flask.request.method == "GET":
    return flask.render_template("input.html")
  else:
    input_string = flask.request.form.get("input")
    return flask.redirect("output")


@app.route('/output')
def output():
  output_string = "".join([html_escape_table.get(c, c) for c in input_string])
#  output_string = input_string
  return flask.render_template("output.html", output=output_string)

if __name__ == '__main__':
  app.run(host='0.0.0.0', port=8080)
EOF_CP


python3 app.py

banner "$BG_GREEN$WHITE" "🎉 Done! Check Cloud Run service URL above. - ePlus.DEV"
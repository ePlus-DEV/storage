#!/usr/bin/env python3
# =============================================================
# 🚀 Bootstrap Lab Runner (Python)
# © 2026 ePlus.DEV
# =============================================================

import os
import subprocess
import sys

# =======================
# 🌈 Colors
# =======================
RED = "\033[1;31m"
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
CYAN = "\033[1;36m"
BOLD = "\033[1m"
RESET = "\033[0m"

REPO_URL = "https://github.com/ePlus-DEV/storage.git"
REPO_DIR = "storage"
LAB_PATH = "labs/data-ingestion-into-bigquery-from-cloud-storage/lab.sh"


def run(cmd, cwd=None):
    subprocess.run(cmd, cwd=cwd, check=True)


def main():
    print(f"{CYAN}{BOLD}▶ Starting lab bootstrap...{RESET}")

    # =======================
    # 📦 Clone or update repo
    # =======================
    if os.path.isdir(os.path.join(REPO_DIR, ".git")):
        print(f"{YELLOW}▶ Repo exists, pulling latest...{RESET}")
        run(["git", "pull"], cwd=REPO_DIR)
    else:
        print(f"{CYAN}▶ Cloning repository...{RESET}")
        run(["git", "clone", REPO_URL])

    # =======================
    # ▶ Run lab script
    # =======================
    lab_file = os.path.join(REPO_DIR, LAB_PATH)
    if not os.path.isfile(lab_file):
        print(f"{RED}❌ Lab script not found: {lab_file}{RESET}")
        sys.exit(1)

    print(f"{GREEN}▶ Running lab script...{RESET}")
    run(["chmod", "+x", lab_file])
    run(["bash", lab_file])

    print(f"{GREEN}{BOLD}🎉 Lab completed successfully!{RESET}")


if __name__ == "__main__":
    main()

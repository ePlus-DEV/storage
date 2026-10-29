# Lab console output and attribution

The lab scripts are standalone: many users download a single `lab.sh` using
`curl` and run it directly with Bash or source it in Cloud Shell. Do not rely
on importing a helper from another file.

## Banner (presentation only)

For **new** lab scripts and when updating an unbranded standalone lab, use
a compact, ASCII-safe banner before the first lab command:

```bash
#!/usr/bin/env bash

# Presentation only. The repository LICENSE remains the Unlicense.
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
  _eplus_cyan=$'\033[1;36m'
  _eplus_yellow=$'\033[0;33m'
  _eplus_reset=$'\033[0m'
else
  _eplus_cyan='' _eplus_yellow='' _eplus_reset=''
fi
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
printf '%s\n' "${_eplus_cyan} ePlus.DEV - Starting Execution | LAB-ID${_eplus_reset}"
printf '%s\n' "${_eplus_yellow} Copyright (c) 2026 ePlus.DEV | Unlicense${_eplus_reset}"
printf '%s\n' "${_eplus_cyan}==========================================================${_eplus_reset}"
unset _eplus_cyan _eplus_yellow _eplus_reset
```

Replace `LAB-ID` with the actual identifier or a short title. When a script
already has colored output, add attribution to its existing banner instead of
duplicating the entire header.

## Compatibility and safety

- The banner must not run `gcloud`, request input, change directory, set
  shell options, or mutate Cloud resources.
- Use ASCII characters for borders and headings. Colored ANSI sequences
  should only be emitted to a supported interactive terminal. Honor
  `NO_COLOR`; log files and CI should receive readable text.
- Avoid `clear`, `tput` without checking terminal support, noisy animation,
  and repeated banners per task.
- Preserve existing commands, resource names, task order, environment
  detection and Check my progress behavior in a branding-only PR.
- The repository's root `LICENSE` is the **Unlicense** (public domain).
  The ePlus.DEV attribution is an informational project label, **not**
  a change to that license or an "all rights reserved" restriction.
- Any actual fixes to script logic should be sent through a separate,
  reviewable PR and tested in the corresponding Skills Boost lab.

## Validation

```bash
bash -n labs/LAB-ID/lab.sh
NO_COLOR=1 bash -n labs/LAB-ID/lab.sh
```

The existing `Lab Script Health` workflow checks changed Bash scripts on
PRs. It does not execute cloud provisioning or prove that lab grading passes.

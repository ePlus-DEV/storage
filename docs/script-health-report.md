# Lab Script Health Report

> Generated automatically by the read-only script audit. A finding is not a
> runtime test failure. Verify against the actual lab and official documentation.

**Bash scripts scanned:** 434. **Findings:** 285.

## Summary

| Priority | Check | Affected scripts |
| --- | --- | ---: |
| P0 | `empty-script` | 2 |
| P0 | `invalid-pip-option` | 0 |
| P0 | `public-storage-admin` | 2 |
| P1 | `duplicate-script` | 3 |
| P1 | `legacy-gemini-pro` | 2 |
| P1 | `service-account-key` | 17 |
| P2 | `gcloud-alpha` | 23 |
| P2 | `gcloud-beta` | 37 |
| P2 | `gsutil` | 120 |
| P2 | `missing-branding` | 51 |
| P2 | `missing-color` | 28 |

## Findings for review

| Priority | Check | Script | Recommendation |
| --- | --- | --- | --- |
| P0 | `empty-script` | [`labs/GSP340/lab.sh:1`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP340/lab.sh#L1) | Empty Bash script; restore or mark as incomplete. |
| P0 | `empty-script` | [`labs/manage-storage-configuration-using-gsutil/lab.sh:1`](https://github.com/ePlus-DEV/storage/blob/main/labs/manage-storage-configuration-using-gsutil/lab.sh#L1) | Empty Bash script; restore or mark as incomplete. |
| P0 | `public-storage-admin` | [`labs/configure-cloud-buckets-with-gsutil-for-load-balancing-and-fault-tolerance-solution/lab.sh:23`](https://github.com/ePlus-DEV/storage/blob/main/labs/configure-cloud-buckets-with-gsutil-for-load-balancing-and-fault-tolerance-solution/lab.sh#L23) | Public principal receives Storage Admin; remove this broad IAM grant. |
| P0 | `public-storage-admin` | [`labs/configure-cloud-buckets-with-gsutil-for-load-balancing-and-fault-tolerance/lab.sh:22`](https://github.com/ePlus-DEV/storage/blob/main/labs/configure-cloud-buckets-with-gsutil-for-load-balancing-and-fault-tolerance/lab.sh#L22) | Public principal receives Storage Admin; remove this broad IAM grant. |
| P1 | `duplicate-script` | [`labs/gem-terraform-gcs-create/lab.sh:1`](https://github.com/ePlus-DEV/storage/blob/main/labs/gem-terraform-gcs-create/lab.sh#L1) | Same content as: labs/gem-terraform-sa-create/lab.sh, labs/gem-terraform-vpc-create/lab.sh |
| P1 | `duplicate-script` | [`labs/gem-terraform-sa-create/lab.sh:1`](https://github.com/ePlus-DEV/storage/blob/main/labs/gem-terraform-sa-create/lab.sh#L1) | Same content as: labs/gem-terraform-gcs-create/lab.sh, labs/gem-terraform-vpc-create/lab.sh |
| P1 | `duplicate-script` | [`labs/gem-terraform-vpc-create/lab.sh:1`](https://github.com/ePlus-DEV/storage/blob/main/labs/gem-terraform-vpc-create/lab.sh#L1) | Same content as: labs/gem-terraform-gcs-create/lab.sh, labs/gem-terraform-sa-create/lab.sh |
| P1 | `legacy-gemini-pro` | [`labs/GSP1249/lab.sh:88`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1249/lab.sh#L88) | Legacy gemini-pro identifier; verify a currently supported lab model. |
| P1 | `legacy-gemini-pro` | [`labs/GSP1289/old-lab.sh:170`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1289/old-lab.sh#L170) | Legacy gemini-pro identifier; verify a currently supported lab model. |
| P1 | `service-account-key` | [`labs/GSP023/lab.sh:59`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP023/lab.sh#L59) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP097/lab.sh:115`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP097/lab.sh#L115) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP097/old.sh:32`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP097/old.sh#L32) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP097/task-1.sh:39`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP097/task-1.sh#L39) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP1007/lab.sh:102`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1007/lab.sh#L102) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP1164/lab.sh:128`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1164/lab.sh#L128) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP1164/old-lab.sh:58`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1164/old-lab.sh#L58) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP154/lab.sh:38`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP154/lab.sh#L38) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP213/lab.sh:87`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP213/lab.sh#L87) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP222/lab.sh:31`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP222/lab.sh#L31) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP321/lab.sh:101`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP321/lab.sh#L101) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP321/other.sh:143`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP321/other.sh#L143) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP323/lab.sh:149`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP323/lab.sh#L149) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP329/lab.sh:86`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP329/lab.sh#L86) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP496/lab.sh:134`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP496/lab.sh#L134) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP540/lab.sh:33`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP540/lab.sh#L33) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P1 | `service-account-key` | [`labs/GSP766/lab.sh:58`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP766/lab.sh#L58) | Creates a long-lived service-account key; prefer keyless auth when permitted. |
| P2 | `gcloud-alpha` | [`labs/ARC119/lab.sh:129`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC119/lab.sh#L129) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/ARC132/lab.sh:136`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC132/lab.sh#L136) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP048/lab.sh:81`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP048/lab.sh#L81) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP049/lab.sh:30`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP049/lab.sh#L30) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP089/old-lab.sh:188`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP089/old-lab.sh#L188) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP090/lab.sh:157`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP090/lab.sh#L157) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP091/lab.sh:69`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP091/lab.sh#L69) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP097/task-1.sh:33`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP097/task-1.sh#L33) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP1108/lab.sh:139`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1108/lab.sh#L139) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP1143/lab.sh:38`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1143/lab.sh#L38) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP1157/lab.sh:44`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1157/lab.sh#L44) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP1262/step1.sh:53`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1262/step1.sh#L53) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP323/lab.sh:55`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP323/lab.sh#L55) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP338/lab.sh:158`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP338/lab.sh#L158) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP510/lab.sh:270`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP510/lab.sh#L270) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP510/old.sh:168`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP510/old.sh#L168) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP526/lab.sh:521`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP526/lab.sh#L521) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP528/other.sh:77`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP528/other.sh#L77) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP651/lab.sh:43`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP651/lab.sh#L43) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP736/lab.sh:93`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP736/lab.sh#L93) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP872/lab.sh:120`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP872/lab.sh#L120) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP872/old.sh:132`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP872/old.sh#L132) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-alpha` | [`labs/GSP872/other.sh:124`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP872/other.sh#L124) | gcloud alpha command; verify command stability and lab compatibility. |
| P2 | `gcloud-beta` | [`labs/ARC100/lab.sh:103`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC100/lab.sh#L103) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/ARC101/lab.sh:213`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC101/lab.sh#L213) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/ARC115/lab.sh:267`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC115/lab.sh#L267) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GENAI129/lab.sh:205`](https://github.com/ePlus-DEV/storage/blob/main/labs/GENAI129/lab.sh#L205) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP087/lab.sh:55`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP087/lab.sh#L55) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP089/old-lab.sh:140`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP089/old-lab.sh#L140) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP091/lab.sh:30`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP091/lab.sh#L30) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1021/lab.sh:47`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1021/lab.sh#L47) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1021/other.sh:77`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1021/other.sh#L77) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1024/lab.sh:111`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1024/lab.sh#L111) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1026/lab.sh:46`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1026/lab.sh#L46) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1027/lab.sh:47`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1027/lab.sh#L47) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1027/solution-2.sh:41`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1027/solution-2.sh#L41) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP105/lab.sh:29`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP105/lab.sh#L29) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1079/lab.sh:101`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1079/lab.sh#L101) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1079/other.sh:220`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1079/other.sh#L220) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1108/lab.sh:94`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1108/lab.sh#L94) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP1183/lab.sh:133`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1183/lab.sh#L133) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP178/lab.sh:39`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP178/lab.sh#L39) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP188/lab.sh:61`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP188/lab.sh#L61) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP215/lab.sh:44`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP215/lab.sh#L44) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP304/lab.sh:37`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP304/lab.sh#L37) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP330/old-lab.sh:58`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP330/old-lab.sh#L58) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP338/lab.sh:113`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP338/lab.sh#L113) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP393/lab.sh:211`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP393/lab.sh#L211) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP479/lab.sh:59`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP479/lab.sh#L59) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP496/lab.sh:75`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP496/lab.sh#L75) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP499/lab.sh:158`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP499/lab.sh#L158) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP521/lab.sh:190`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP521/lab.sh#L190) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP526/lab.sh:514`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP526/lab.sh#L514) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP609/lab.sh:56`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP609/lab.sh#L56) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP644/lab.sh:423`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP644/lab.sh#L423) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP644/other.sh:57`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP644/other.sh#L57) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP768/lab.sh:125`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP768/lab.sh#L125) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP920/lab.sh:67`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP920/lab.sh#L67) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/GSP975/lab.sh:32`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP975/lab.sh#L32) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gcloud-beta` | [`labs/multimodal-content-generation-with-gemini-on-vertex-ai-solution/lab.sh:45`](https://github.com/ePlus-DEV/storage/blob/main/labs/multimodal-content-generation-with-gemini-on-vertex-ai-solution/lab.sh#L45) | gcloud beta command; verify whether stable commands are available. |
| P2 | `gsutil` | [`labs/ARC104/lab.sh:54`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC104/lab.sh#L54) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC106/lab.sh:136`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC106/lab.sh#L136) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC109/lab.sh:65`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC109/lab.sh#L65) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC111/lab.sh:126`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC111/lab.sh#L126) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC114/lab.sh:128`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC114/lab.sh#L128) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC116/lab.sh:77`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC116/lab.sh#L77) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC117/lab-solution-2.sh:46`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC117/lab-solution-2.sh#L46) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC117/other.sh:25`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC117/other.sh#L25) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC119/lab.sh:123`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC119/lab.sh#L123) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC1200/lab.sh:25`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC1200/lab.sh#L25) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/ARC122/lab.sh:26`](https://github.com/ePlus-DEV/storage/blob/main/labs/ARC122/lab.sh#L26) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP008/lab.sh:74`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP008/lab.sh#L74) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP023/lab.sh:89`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP023/lab.sh#L89) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP037/lab.sh:88`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP037/lab.sh#L88) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP051/lab.sh:49`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP051/lab.sh#L49) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP051/step1.sh:47`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP051/step1.sh#L47) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP064/lab.sh:14`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP064/lab.sh#L14) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP073/lab.sh:37`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP073/lab.sh#L37) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP074/lab.sh:38`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP074/lab.sh#L38) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP079/lab.sh:44`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP079/lab.sh#L44) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP087/lab.sh:37`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP087/lab.sh#L37) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1003/lab.sh:59`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1003/lab.sh#L59) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1004/lab.sh:47`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1004/lab.sh#L47) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1005/lab.sh:148`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1005/lab.sh#L148) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1026/lab.sh:110`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1026/lab.sh#L110) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1027/lab.sh:94`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1027/lab.sh#L94) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1027/solution-2.sh:100`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1027/solution-2.sh#L100) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1044/lab.sh:31`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1044/lab.sh#L31) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1049/lab.sh:119`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1049/lab.sh#L119) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1049/old-lab.sh:116`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1049/old-lab.sh#L116) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP107/lab.sh:60`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP107/lab.sh#L60) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1073/other-lab.sh:22`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1073/other-lab.sh#L22) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1079/lab.sh:82`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1079/lab.sh#L82) | gsutil dependency; plan a tested migration to gcloud storage. |
| P2 | `gsutil` | [`labs/GSP1079/other.sh:163`](https://github.com/ePlus-DEV/storage/blob/main/labs/GSP1079/other.sh#L163) | gsutil dependency; plan a tested migration to gcloud storage. |

_Displaying 120 of 285 findings. Increase --max-rows to view more._

## What this report does not establish

- No scripts have been executed, and no cloud resources are created.
- Google Cloud service availability and lab grading are not verified here.
- P2 migration hints (gsutil, alpha/beta) are not automatic failures.
- Maintain lab-specific behavior; do not blindly replace commands.

## Review workflow

Fix each verified problem in a separate scoped PR; run the corresponding lab
and attach its Check my progress evidence before marking it verified.

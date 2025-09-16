# Google Cloud Skills Boost

```shell
ZONE=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-zone])")
REGION=$(gcloud compute project-info describe \
  --format="value(commonInstanceMetadata.items[google-compute-default-region])")
PROJECT_ID=$(gcloud projects list --format="value(projectId)" --limit=1)
```

```shell
gcloud config set project $DEVSHELL_PROJECT_ID
```


```shell
gcloud config set project $PROJECT_ID
gcloud config set compute/zone "$ZONE"
gcloud config set compute/region "$REGION"
```
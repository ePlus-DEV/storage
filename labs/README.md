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

**file .ipynb**


```shell
PROJECT_ID = !gcloud config get project
PROJECT_ID = PROJECT_ID[0]  # @param {type:"string"}
LOCATION = !gcloud compute project-info describe --format="value(commonInstanceMetadata.items[google-compute-default-region])"
LOCATION = LOCATION[0]  # @param {type:"string"}
```
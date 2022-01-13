New-Item -Path . -Name "credentials-velero.yaml" -ItemType "file"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_SUBSCRIPTION_ID = $env:AZURE_SUBSCRIPTION_ID"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_TENANT_ID = $env:AZURE_TENANT_ID"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_CLIENT_ID = $env:AZURE_CLIENT_ID"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_CLIENT_SECRET = $env:AZURE_CLIENT_SECRET"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_RESOURCE_GROUP = $env:AZURE_RESOURCE_GROUP"

Add-Content -Path .\credentials-velero.yaml -Value "AZURE_CLOUD_NAME = $env:AZURE_CLOUD_NAME"


$apiServer =$(az aro show -g $env:AZURE_RESOURCE_GROUP -n $env:CLUSTER_NAME --query apiserverProfile.url -o tsv)

$kubeadmin_password = $(az aro list-credentials --name $env:CLUSTER_NAME --resource-group $env:AZURE_RESOURCE_GROUP --query kubeadminPassword --output tsv)

oc login $apiServer -u kubeadmin -p $kubeadmin_password

velero install --provider azure --plugins velero/velero-plugin-for-microsoft-azure:v1.1.0 --bucket $env:BLOB_CONTAINER --secret-file .\credentials-velero.yaml --backup-location-config resourceGroup=$env:AZURE_RESOURCE_GROUP,storageAccount=$env:STORAGE_ID --snapshot-location-config apiTimeout=15m --velero-pod-cpu-limit="0" --velero-pod-mem-limit="0" --velero-pod-mem-request="0" --velero-pod-cpu-request="0"

Remove-Item .\credentials-velero.yaml
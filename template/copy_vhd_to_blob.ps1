$ACCOUNT_KEY=az storage account keys list -g $env:AZURE_RESOURCE_GROUP --account-name $env:PRIMARY_STORAGE_ACCOUNT --query "[0].value" -o tsv

$VHD_URL=curl -s https://raw.githubusercontent.com/openshift/installer/release-4.6/data/data/rhcos.json | jq -r .azure.uri

az storage blob copy start --account-name $env:PRIMARY_STORAGE_ACCOUNT --account-key ${ACCOUNT_KEY} --destination-blob "rhcos.vhd" --destination-container vhd --source-uri "${VHD_URL}"



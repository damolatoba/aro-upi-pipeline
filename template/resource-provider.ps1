
$app_id = az provider show --namespace Microsoft.RedHatOpenShift --query "authorizations[0].applicationId" -o tsv

$object_id = az ad sp show --id $app_id --query "objectId" -o tsv| convertTo-json

Write-Output "{""id"" : $object_id }"

#!/bin/bash
echo "Did you connect to your AKS cluster, open the bash script and define the variables [TENANT_ID, SUBSCRIPTION_ID, SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP, LOCATION] before running the script?(yes/no)"
read input

if [ "$input" == "yes" ] || [ "$input" == "y" ] || [ "$input" == "YES" ] || [ "$input" == "Y" ]
then
#Define the variables.
TENANT_ID="TENANT_ID" && echo TENANT_ID=$TENANT_ID
SUBSCRIPTION_ID="SUBSCRIPTION_ID" && echo SUBSCRIPTION_ID=$SUBSCRIPTION_ID
BACKUP_RESOURCE_GROUP=Velero_Backups && echo BACKUP_RESOURCE_GROUP=$BACKUP_RESOURCE_GROUP 
BACKUP_STORAGE_ACCOUNT_NAME=velero$(head /dev/urandom | tr -dc a-z0-9 | head -c12) && echo BACKUP_STORAGE_ACCOUNT_NAME=$BACKUP_STORAGE_ACCOUNT_NAME
VELERO_SP_DISPLAY_NAME=velero$RANDOM && echo VELERO_SP_DISPLAY_NAME=$VELERO_SP_DISPLAY_NAME
SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP="SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP" && echo SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP=$SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP
LOCATION="LOCATION" && echo LOCATION=$LOCATION

#Create a resource group for the backup storage account.
echo "Creating resource group..."
az group create -n $BACKUP_RESOURCE_GROUP --location $LOCATION

#Create the storage account.
echo "Creating storage account..."
az storage account create \
  --name $BACKUP_STORAGE_ACCOUNT_NAME \
  --resource-group $BACKUP_RESOURCE_GROUP \
  --sku Standard_GRS \
  --encryption-services blob \
  --https-only true \
  --kind BlobStorage \
  --access-tier Hot
  
#Create Blob Container
echo "Creating Blob Container..."
az storage container create \
  --name velero \
  --public-access off \
  --account-name $BACKUP_STORAGE_ACCOUNT_NAME

#Set permissions for Velero
echo "Setting permissions for Velero..."
AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac --name $VELERO_SP_DISPLAY_NAME --role "Contributor" --query 'password' -o tsv)
AZURE_CLIENT_ID=$(az ad sp list --display-name $VELERO_SP_DISPLAY_NAME --query '[0].appId' -o tsv)
az role assignment create  --role Contributor --assignee $AZURE_CLIENT_ID --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BACKUP_RESOURCE_GROUP
az role assignment create  --role Contributor --assignee $AZURE_CLIENT_ID --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP 

#Save Velero credentials to local file.
echo "Saving velero credentials to local file: credentials-velero..."
cat << EOF  > ./credentials-velero
AZURE_SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
AZURE_TENANT_ID="${TENANT_ID}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
AZURE_RESOURCE_GROUP="${SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP}"
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

#Install and start Velero.
echo "Installing velero client locally..."
latest_version=$(curl https://github.com/vmware-tanzu/velero/releases/latest)
latest_version=$(echo ${latest_version} | grep -o 'v[0-9].[0-9].[0.9]')
wget https://github.com/vmware-tanzu/velero/releases/download/${latest_version}/velero-${latest_version}-linux-amd64.tar.gz
mkdir ~/velero; tar -zxf velero-${latest_version}-linux-amd64.tar.gz -C ~/velero; cp ~/velero/velero-${latest_version}-linux-amd64/velero ~/velero/
echo 'export PATH=$PATH:~/velero' >> ~/.bash_profile && source ~/.bash_profile
echo 'export PATH=$PATH:~/velero' >> ~/.bashrc && source ~/.bashrc

echo "Staring velero..."
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.0.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --backup-location-config resourceGroup=$BACKUP_RESOURCE_GROUP,storageAccount=$BACKUP_STORAGE_ACCOUNT_NAME \
  --snapshot-location-config apiTimeout=5m,resourceGroup=$BACKUP_RESOURCE_GROUP \
  --wait

#clean up local file credentials
rm ./credentials-velero

printf "\e[32;1mIf velero command is not there,just run: source ~/.bash_profile && source ~/.bashrc \e[0m \n"

else
echo "Please connect to your AKS cluster, open the bash script and define the variables before running the script."
exit 0
fi


#!/bin/bash
printf "\e[32;1mDid you connect to your AKS cluster, using: az aks get-credentials --name MyManagedCluster --resource-group MyResourceGroup? [yes/no]\e[0m \n"
read input

if [ "$input" == "yes" ] || [ "$input" == "y" ] || [ "$input" == "YES" ] || [ "$input" == "Y" ]
then

read -p "Enter your Tenant ID: " TENANT_ID
read -p "Enter your Subscription ID: " SUBSCRIPTION_ID
read -p "Enter your Source AKS Infrastructure Resource Group (MC_*): " SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP
read -p "Enter the location of your backup storage account: " LOCATION
printf "\e[32;1m*******Your Variables*******\e[0m \n"

#Define the variables.
TENANT_ID=${TENANT_ID} && echo TENANT_ID=${TENANT_ID}
SUBSCRIPTION_ID=${SUBSCRIPTION_ID} && echo SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
BACKUP_RESOURCE_GROUP=Velero_Backups && echo BACKUP_RESOURCE_GROUP=${BACKUP_RESOURCE_GROUP} 
BACKUP_STORAGE_ACCOUNT_NAME=velero$(head /dev/urandom | tr -dc a-z0-9 | head -c12) && echo BACKUP_STORAGE_ACCOUNT_NAME=${BACKUP_STORAGE_ACCOUNT_NAME}
VELERO_SP_DISPLAY_NAME=velero$RANDOM && echo VELERO_SP_DISPLAY_NAME=${VELERO_SP_DISPLAY_NAME}
SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP=${SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP} && echo SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP=${SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP}
LOCATION=${LOCATION} && echo LOCATION=${LOCATION}

printf "\e[32;1mPlease check your variables above and confirm to start the installation, do you want to continue? [yes/no] \e[0m \n"
read confirm
if [ "$confirm" == "yes" ] || [ "$confirm" == "y" ] || [ "$confirm" == "YES" ] || [ "$confirm" == "Y" ]
then

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
echo "Adding permissions for Velero..."
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
if ! command -v velero > /dev/null 2>&1;then
   echo "Installing Velero client locally..."
   latest_version=$(curl https://github.com/vmware-tanzu/velero/releases/latest)
   latest_version=$(echo ${latest_version} | grep -o 'v[0-9].[0-9].[0.9]')
   wget https://github.com/vmware-tanzu/velero/releases/download/${latest_version}/velero-${latest_version}-linux-amd64.tar.gz
   mkdir ~/velero -p; tar -zxf velero-${latest_version}-linux-amd64.tar.gz -C ~/velero; cp ~/velero/velero-${latest_version}-linux-amd64/velero ~/velero/
   mkdir ~/.local/bin/ -p; cp ~/velero/velero ~/.local/bin/ > /dev/null 2>&1
   if ! cat ~/.bash_profile | grep -q 'export PATH=$PATH:~/velero';then
   echo 'export PATH=$PATH:~/velero' >> ~/.bash_profile && source ~/.bash_profile
   fi
   if ! cat ~/.bashrc | grep -q 'export PATH=$PATH:~/velero';then
   echo 'export PATH=$PATH:~/velero' >> ~/.bashrc && source ~/.bashrc
   fi
fi

echo "Staring velero..."
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.0.0 \
  --bucket velero \
  --secret-file ./credentials-velero \
  --backup-location-config resourceGroup=$BACKUP_RESOURCE_GROUP,storageAccount=$BACKUP_STORAGE_ACCOUNT_NAME \
  --snapshot-location-config apiTimeout=5m,resourceGroup=$BACKUP_RESOURCE_GROUP
  
#add node selector to the velero deployment to run Velero on the Linux nodes
kubectl patch deployment velero -n velero -p '{"spec": {"template": {"spec": {"nodeSelector":{"beta.kubernetes.io/os"

#clean up local file credentials
rm ./credentials-velero

printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1mIf velero command is not there, just run: source ~/.bash_profile && source ~/.bashrc \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"


else
printf "\e[33;1mYour installation has been cancelled.\e[0m \n"
exit 0
fi

else
printf "\e[32;1mPlease connect to your AKS cluster before running the script. \e[0m \n"
exit 0
fi

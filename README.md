# Backup and Restore AKS cluster using Velero

## Summary

This article talks about how to backup and restore AKS cluster, and how to migrate to another AKS cluster using Velero.

## Prerequisites
1. Azure CLI.
2. Connect to the AKS cluster: `az aks get-credentials --resource-group <RGname> --name <AKSname>`
3. No need to define the variables if you run the scripts (source-aks-cluster.sh, target-aks-cluster.sh) as you will be asked to enter your variables once you run the scripts, otherwise, if you want to run the commands manually as explained below in part 1 and part 2 then you need to define the variables (`TENANT_ID, SUBSCRIPTION_ID, SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP, TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP, LOCATION`).
4. This works on Azure cloud shell (bash) and local machine (bash).

## Part 1: Create storage account and install Velero on source AKS cluster
In this part will create storage account, blob container, and install and start Velero on source AKS cluster.

### Installation
No need to change on the script, just run the script and you will be asked to enter your variables.

```bash
curl -LO https://raw.githubusercontent.com/mutazn/Backup-and-Restore-AKS-cluster-using-Velero/master/source-aks-cluster.sh
chmod +x ./source-aks-cluster.sh
./source-aks-cluster.sh
```

The script contains the following in case you want to run the commands manually:
```bash
#Define the variables.
TENANT_ID="TENANT_ID" 
SUBSCRIPTION_ID="SUBSCRIPTION_ID" 
BACKUP_RESOURCE_GROUP=Velero_Backups
BACKUP_STORAGE_ACCOUNT_NAME=velero$(head /dev/urandom | tr -dc a-z0-9 | head -c12)
VELERO_SP_DISPLAY_NAME=velero$RANDOM
SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP="SOURCE_AKS_INFRASTRUCTURE_RESOURCE_GROUP"
LOCATION="LOCATION"

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
  --snapshot-location-config apiTimeout=5m,resourceGroup=$BACKUP_RESOURCE_GROUP \
  --wait

#clean-up local file credentials
rm ./credentials-velero
```

## Part 2: Install Velero on target AKS cluster in case you need to restore the backup on another cluster.

As we already have the storage account and the Blob Container has our backup from the source AKS cluster so we only need to connect the target AKS cluster to the storage account and access the backup to restore it to the target AKS cluster.

### Installation
No need to change on the script, just run the script and you will be asked to enter your variables.

```bash
curl -LO https://raw.githubusercontent.com/mutazn/Backup-and-Restore-AKS-cluster-using-Velero/master/target-aks-cluster.sh
chmod +x ./target-aks-cluster.sh
./target-aks-cluster.sh
```

The script contains the following in case you want to run the commands manually:
```bash
#Define the variables.
TENANT_ID="TENANT_ID" 
SUBSCRIPTION_ID="SUBSCRIPTION_ID" 
BACKUP_RESOURCE_GROUP=Velero_Backups
BACKUP_STORAGE_ACCOUNT_NAME="BACKUP_STORAGE_ACCOUNT_NAME"
VELERO_SP_DISPLAY_NAME=velero$RANDOM
TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP="TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP"

#Set permissions for Velero on TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP
echo "Adding permissions for Velero..."
AZURE_CLIENT_SECRET=$(az ad sp create-for-rbac --name $VELERO_SP_DISPLAY_NAME --role "Contributor" --query 'password' -o tsv)
AZURE_CLIENT_ID=$(az ad sp list --display-name $VELERO_SP_DISPLAY_NAME --query '[0].appId' -o tsv)
az role assignment create  --role Contributor --assignee $AZURE_CLIENT_ID --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$BACKUP_RESOURCE_GROUP
az role assignment create  --role Contributor --assignee $AZURE_CLIENT_ID --scope /subscriptions/$SUBSCRIPTION_ID/resourceGroups/$TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP

#Save Velero credentials to local file.
echo "Saving velero credentials to local file: credentials-velero-target..."
cat << EOF  > ./credentials-velero-target
AZURE_SUBSCRIPTION_ID="${SUBSCRIPTION_ID}"
AZURE_TENANT_ID="${TENANT_ID}"
AZURE_CLIENT_ID="${AZURE_CLIENT_ID}"
AZURE_CLIENT_SECRET="${AZURE_CLIENT_SECRET}"
AZURE_RESOURCE_GROUP="${TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP}"
AZURE_CLOUD_NAME=AzurePublicCloud
EOF

#Install Velero
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

#Stare Velero on target AKS cluster
echo "Staring Velero on target AKS cluster..."
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.0.0 \
  --bucket velero \
  --secret-file ./credentials-velero-target \
  --backup-location-config resourceGroup=$BACKUP_RESOURCE_GROUP,storageAccount=$BACKUP_STORAGE_ACCOUNT_NAME \
  --snapshot-location-config apiTimeout=5m,resourceGroup=$BACKUP_RESOURCE_GROUP \
  --wait
    
#clean up local file credentials
rm ./credentials-velero-target

```
## Backup and Restore commands
-  Backup all resources in all namespaces including persistent volumes:

   `velero backup create <mybackup-name>`

- Backup namespace resources including persistent volumes:

    ```bash 
    velero backup create <mybackup-name> --include-namespaces <namespace-name>
    ```

- Create a backup schedule, daily, weekly, or monthly:
  ```bash
  velero create schedule daily --schedule="@daily" --include-namespaces <namespace>
  velero create schedule weekly --schedule="@weekly" --include-namespaces <namespace>
  velero create schedule monthly --schedule="@monthly" --include-namespaces <namespace>
  
  ```
- Create customized backup schedule using cron:

  This example will create a backup at 11:00 on Saturday, [this link](https://crontab.guru/) will help you to adjust cron schedule.

   ```bash
   velero create schedule backup-schedule --schedule="0 11 * * 6" --include-namespaces <namespace>
   ```
- Backup only pv and pvc in all namespaces or specific namespace:
  
  ```bash
  velero backup create <mybackup-name> --include-resources PersistentVolumeClaim,PersistentVolume 
  velero backup create <mybackup-name> --include-resources PersistentVolumeClaim,PersistentVolume --include-namespaces <namespace>
  ```
- Create a backup excluding the velero and default namespaces:
  ```bash
  velero backup create <mybackup-name> --exclude-namespaces velero,default
  ```
  
- Restore the backup to the same AKS cluster or to another AKS cluster:

   ```bash
   velero restore create <myrestore-name> --from-backup <mybackup-name>
   ``` 

- Restore namespace only from a backup:

   ```bash
   velero restore create <myrestore-name> --from-backup <mybackup-name> --include-namespaces <namespace>
   ```

- Restore namespace only from a backup to a different namespace:
   
   ```bash
   velero restore create  <myrestore-name> --from-backup <mybackup-name> --include-namespaces <namespace> --namespace-mappings [old-namespace]:[new-namespace]
   ```

## Troubleshooting
- Check Velero pod and logs:

  ```bash
  kubectl get pod -n velero
  kubectl logs -f -l component=velero -n velero
  ```

- List the backups:

  ```bash
  velero backup get
  ```
 **Note**: if you cannot see the backups on the source AKS cluster, or if you can see the backups on the source AKS cluster, but you don’t see any output on the AKS target cluster when run `velero backup get` command, check velero pod logs using `kubectl logs -f -l component=velero -n velero` if you find any error.

**Example of a common error** when the target AKS cluster is not connecting to the Backup Storage Account: 
`level=error msg="Error getting backup store for this location" backupLocation=default controller=backup-sync error="rpc error: code = Unknown desc = storage.AccountsClient#ListKeys: Failure responding to request: StatusCode=404 -- Original Error: autorest/azure: Service returned an error. Status=404 Code=\"ResourceNotFound\" Message=\"The Resource 'Microsoft.Storage/storageAccounts/velerohjfquoiyez0u' under resource group 'Velero_Backups' was not found. For more details please go to https://aka.ms/ARMResourceNotFoundFix\"" error.file="/go/src/github.com/vmware-tanzu/velero-plugin-for-microsoft-azure/velero-plugin-for-microsoft-azure/object_store.go:181" error.function=main.getStorageAccountKey logSource="pkg/controller/backup_sync_controller.go:175"`


**The solution here** is to check if you used the correct storage account name, run `velero uninstall` and re-run the script with the correct storage account name.
 
 
- Describe the backup and its logs:
  
  ```bash
   velero backup describe <mybackup-name> --details
   velero backup logs <mybackup-name>
  ```

- List the restores:

  ```bash
  velero restore get
  ```
  
- Describe the restore and its logs:

  ```bash
   velero restore describe <myrestore-name> --details
   velero restore logs <myrestore-name>
  ```

- List the schedules and describe a schedule: 

  ```bash
   velero schedule  get
   velero schedule describe <schedule-name>

  ```

- Delete a backup or all backups:

  ```bash
   velero backup delete <backup-name>
   velero backup delete --all 
  ```

- Delete a restore or all restores, this will delete the metadata only and will not delete the restored resources:

  ```bash
   velero restore delete <restore-name>
   velero restore delete --all 
  ```

- Delete a schedule or all schedules:

  ```bash
   velero schedule delete <schedule-name>
   velero schedule delete --all
  ```
- Check the snapshots:

  ```bash
  az resource list -g Velero_Backups -o table
  ```

![image](https://user-images.githubusercontent.com/32297719/116011563-5fbf2180-a62e-11eb-9ea7-adfdf1ae053e.png)

- Uninstall Velero:
  
  ```bash  
  velero uninstall
  ```
## References

- [How to setup Velero on Microsoft Azure](https://github.com/vmware-tanzu/velero-plugin-for-microsoft-azure).
- [Velero latest release](https://github.com/vmware-tanzu/velero/releases/tag/v1.6.0).
- [GitHub Repository for scripts](https://github.com/mutazn/Backup-and-Restore-AKS-cluster-using-Velero). 

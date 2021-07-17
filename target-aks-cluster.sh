#!/bin/bash
printf "\e[32;1mDid you connect to your target AKS cluster, using: az aks get-credentials --name MyManagedCluster --resource-group MyResourceGroup? [yes/no]\e[0m \n"
read input

if [ "$input" == "yes" ] || [ "$input" == "y" ] || [ "$input" == "YES" ] || [ "$input" == "Y" ]
then

	read -p "Enter your Tenant ID: " TENANT_ID
	while [ -z "$TENANT_ID" ]
	do
		read -p "Enter your Tenant ID: " TENANT_ID
	done
	set -- "$TENANT_ID"


	read -p "Enter your Subscription ID: " SUBSCRIPTION_ID
	while [ -z "$SUBSCRIPTION_ID" ]
	do
		read -p "Enter your Subscription ID: " SUBSCRIPTION_ID
	done
	set -- "$SUBSCRIPTION_ID"

	read -p "Enter your target AKS Infrastructure Resource Group (MC_*): " TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP
	while [ -z "$TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP" ]
	do
		read -p "Enter your target AKS Infrastructure Resource Group (MC_*): " TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP
	done
	set -- "$TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP"



	read -p "Enter the backup storage account name that exists in the backup resource group: " BACKUP_STORAGE_ACCOUNT_NAME
	while [ -z "$BACKUP_STORAGE_ACCOUNT_NAME" ]
	do
		read -p "Enter the backup storage account name that exists in the backup resource group: " BACKUP_STORAGE_ACCOUNT_NAME
	done
	set -- "$BACKUP_STORAGE_ACCOUNT_NAME"


	printf "\e[32;1m*******Your Variables*******\e[0m \n"


	#Define the variables.
	TENANT_ID=${TENANT_ID//[\"\']} && echo TENANT_ID=${TENANT_ID}
	SUBSCRIPTION_ID=${SUBSCRIPTION_ID//[\"\']} && echo SUBSCRIPTION_ID=${SUBSCRIPTION_ID}
	BACKUP_RESOURCE_GROUP=Velero_Backups && echo BACKUP_RESOURCE_GROUP=${BACKUP_RESOURCE_GROUP} 
	BACKUP_STORAGE_ACCOUNT_NAME=${BACKUP_STORAGE_ACCOUNT_NAME//[\"\']} && echo BACKUP_STORAGE_ACCOUNT_NAME=${BACKUP_STORAGE_ACCOUNT_NAME}
	VELERO_SP_DISPLAY_NAME=velero$RANDOM && echo VELERO_SP_DISPLAY_NAME=$VELERO_SP_DISPLAY_NAME
	TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP=${TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP//[\"\']} && echo TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP=$TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP

	printf "\e[32;1mPlease check your variables above and confirm to start the installation, do you want to continue? [yes/no] \e[0m \n"
	read confirm
	while true; do
		if [ "$confirm" == "yes" ] || [ "$confirm" == "y" ] || [ "$confirm" == "YES" ] || [ "$confirm" == "Y" ]
		then

			#Set permissions for Velero on TARGET_AKS_INFRASTRUCTURE_RESOURCE_GROUP.
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

#Install Velero.
if ! command -v velero > /dev/null 2>&1;then
	echo "Installing Velero client locally..."
	latest_version=$(curl https://github.com/vmware-tanzu/velero/releases/latest)
	latest_version=$(echo ${latest_version} | grep -o 'v[0-9].[0-9].[0-9]')
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

#Stare Velero on target AKS cluster.
echo "Staring Velero on target AKS cluster..."
velero install \
	--provider azure \
	--plugins velero/velero-plugin-for-microsoft-azure:v1.0.0 \
	--bucket velero \
	--secret-file ./credentials-velero-target \
	--backup-location-config resourceGroup=$BACKUP_RESOURCE_GROUP,storageAccount=$BACKUP_STORAGE_ACCOUNT_NAME \
	--snapshot-location-config apiTimeout=5m,resourceGroup=$BACKUP_RESOURCE_GROUP

#add node selector to the velero deployment to run Velero only on the Linux nodes.
kubectl patch deployment velero -n velero -p '{"spec": {"template": {"spec": {"nodeSelector":{"beta.kubernetes.io/os":"linux"}}}}}'

#clean up local file credentials.
rm ./credentials-velero-target

printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1mIf velero command is not there, just run: source ~/.bash_profile && source ~/.bashrc \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"
printf "\e[32;1m********************* \e[0m \n"

elif [ "$confirm" == "no" ] || [ "$confirm" == "n" ] || [ "$confirm" == "NO" ] || [ "$confirm" == "N" ]
then
	printf "\e[33;1mYour installation has been cancelled.\e[0m \n"
	exit 0
else
	printf "\e[32;1mPlease check your variables above and confirm to start the installation, do you want to continue? [yes/no] \e[0m \n"
	read confirm
	while [ -z "$confirm" ]
	do
		printf "\e[32;1mPlease check your variables above and confirm to start the installation, do you want to continue? [yes/no] \e[0m \n"
		read confirm
	done
	set -- "$confirm"
	continue

fi
break
done
else
	printf "\e[33;1mPlease connect to your target AKS cluster before running the script. \e[0m \n"
	exit 0
fi

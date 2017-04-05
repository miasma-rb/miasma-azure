# Miasma Azure

Azure API plugin for the miasma cloud library


## Current support matrix

|Model         |Create|Read|Update|Delete|
|--------------|------|----|------|------|
|AutoScale     |      |    |      |      |
|BlockStorage  |      |    |      |      |
|Compute       |      |    |      |      |
|DNS           |      |    |      |      |
|LoadBalancer  |      |    |      |      |
|Network       |      |    |      |      |
|Orchestration |  X   | X  |  X   |  X   |
|Queues        |      |    |      |      |
|Storage       |  X   | X  |  X   |  X   |




## Configuration via Microsoft Azure portal

Below you will find the steps to configure a Account Active Directory and Subscriptions via the New Azure Resource Manager (ARM) Portal so they can be accessed and managed with this miasma based cloud library. 

Credentials for the Azure Resource Manager require some setup within Azure due to OAuth2 requirements. To setup an OAuth2 application and storage configuration allowing miasma to function properly, perform the following steps listed below using the Azure portal hosted on the following URL: [**https://portal.azure.com**](https://portal.azure.com)

**IMPORTANT** - *Your user account will need to Azure Active Directory domain adminstrator and have `owner` role within the subscriptions which you wish to deploy Infrastructure with using this libary.*


### 1. Setting the Azure Blob storage account
You will also need to setup a Azure Blob storage account to hold the ARM template & other configuration files. The easiest way to create an Azure storage account is by using the Azure portal for detailed instructions, see [Create a storage account](https://docs.microsoft.com/en-us/azure/storage/storage-create-storage-account#create-a-storage-account). You can also create an Azure storage account by using the latest [Azure CLI](https://docs.microsoft.com/en-us/azure/storage/storage-azure-cli).

When you create a storage account, Azure generates two 512-bit storage access keys, which are used for authentication when the storage account is accessed. Your need to set the environment variable `AZURE_BLOB_SECRET_KEY` to use one of the storage access keys and in additon your need to set the environment variable `AZURE_BLOB_ACCOUNT_NAME` to the name you gave your Azure Blob storage account.


### 2. Setting the Azure region for your deployments
The `AZURE_REGION` environment variable is simply the Azure region (`westus`, `eastus`, etc.) where you want to deploy your infrastructure within the Microsoft Azure Cloud platform. The list of regions can be viewed via the [Azure CLI](https://https://github.com/Azure/azure-cli). Once you have signed in to the CLI tool you can get the list of current Azure regions by running the following command ```az account list-locations```. You will need to use the ```name``` property for the specific region you wish to use.


### 3. Getting the Azure Active Directory ID
1. Start at the Azure portal dashboard
2. Click `Browse` to open available service list
4. Click `Azure Active Directory` to open AD service
4. Choose desired directory and then open `Properties`
5. Copy the `Directory ID` value
6. Set the `AZURE_TENANT_ID ` environment variable to use the copied value


### 4. Getting the Azure Subscription ID
1. Start at the Azure portal dashboard
1. Click `Browse` to open available service list
2. Click `Subscriptions ` to open the subscriptions management blade
3. Choose desired subscription and then open `Properties`
4. Copy the `Subscription ID` value 
6. Set the `AZURE_SUBSCRIPTION_ID ` environment variable to use the copied value


### 5. Creating an Azure Active Directory OAuth2 application
1. Start at the Azure portal dashboard
2. . Click `Browse` to open available service list
3. Click `Azure Active Directory` to open AD service
4. Choose desired directory and then open `App registrations`
5. At the top of the blade click `+ ADD`
6. Add a friendly name for the application e.g. `SparkleFormation` 
7. Select `Web app / API` for the application type
8. Enter `http://localhost` for the sign-on URL
9. Then click `CREATE` the bottom of the blade.
10. Open `App registrations` blade
11. Find your application you created (e.g. `SparkleFormation`)
12. Choose desired application and then click the `Properties` option. 
13. Copy the `Application ID` value 
14. Set the `AZURE_CLIENT_ID ` environment variable to use the copied value

### 6. Setting OAuth2 application required permissions
1. Start at the Azure portal dashboard
2. Click `Browse` to open available service list
3. Click `Azure Active Directory` to open AD service
4. Choose desired directory and then open `App registrations`
5. Next select the newly create application (e.g. `SparkleFormation`)
6. Locate the section named `Required permissions`.
7. At the top of the blade click `+ ADD`
8. Open the `1. Select an API` blade 
9. Select the `Windows Azure Service Management API` 
10. Click `Select` at the the bottom of the blade
11. Next open the `2. Select permissions` blade 
12. Check the box next to `Access Azure Service Management as organization users` 
13. Click `Select` at the the bottom of the blade
14. Click `Done` to finish adding the permission

### 7. Creating a client secret key for the OAuth2 application
1. Start at the Azure portal dashboard
2. Click `Browse` to open available service list
3. Click `Azure Active Directory` to open AD service
4. Choose desired directory and then open `App registrations`
5. Next select the newly create application (e.g. `SparkleFormation`)
6. Locate the section named `keys`.
7. For the description put in your full name or some other useful identifier.
8. Select `1 year`, `2 years` or `never expire` from the drop down.
9.  Click `SAVE` at the top of the screen
10. Copy the key value as it only visible until you leave this blade.
11. Set the `AZURE_CLIENT_SECRET` environment variable to use the copied value

### 8. Granting Azure Subscription role to the OAuth2 application
1. Start at the Azure portal dashboard
2. Click `Browse` to open available service list
2. Click `Subscriptions ` to open the subscriptions management blade
4. Click desired subscription and then open `Access Control (IAM)`
5. Click `Add` and select an appropriate role (`Owner` role recommended)
6. Type in the name of the application (e.g. `SparkleFormation`) in the search box. 
7. Click on the appropriate user in the list and then click `Select`
8. Click `OK` in the Add Access panel. 
9. The changes will now be saved


## SparkleFormation CLI configuration example
Below is an example of SparkleFormation CLI ```.sfn``` file credentials tailed to use this cloud libary. The ```azure_root_orchestration_container``` property defaults to "*miasma-orchestration-templates*" if not configured.

```ruby
Configuration.new do
  credentials do
    provider :azure
    azure_tenant_id ENV['AZURE_TENANT_ID']
    azure_client_id ENV['AZURE_CLIENT_ID']
    azure_subscription_id ENV['AZURE_SUBSCRIPTION_ID']
    azure_client_secret ENV['AZURE_CLIENT_SECRET']
    azure_region ENV['AZURE_REGION']
    azure_blob_account_name ENV['AZURE_BLOB_ACCOUNT_NAME']
    azure_blob_secret_key ENV['AZURE_BLOB_SECRET_KEY']
    azure_root_orchestration_container ENV['AZURE_ROOT_ORCHESTRATION_CONTAINER']
  end
end
```


## Info
* Repository: https://github.com/miasma-rb/miasma-azure


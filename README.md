# Miasma Azure

Azure API plugin for the miasma cloud library

## Setup

### Storage Credentials

Storage makes use of the Azure Blob Storage Service:

* `azure_blob_account_name` - Name of blob storage service account
* `azure_blob_secret_key` - Secret key for blob storage access

### Orchestration Credentials

Orchestration makes use of two services:

1. Azure Storage Services - Blob
2. Azure Resource Manager

Credentials for the blob service are defined above.

Credentials for the Azure Resource Manager require some setup
within Azure due to the oauth2 requirement.

Start at the Azure portal:

1. Click `Browse` to open available service list.
2. Click `Active Directory` to open AD service.
3. Choose desired directory and click `APPLICATIONS`.
4. At the bottom of the page click `ADD`.
5. Click `Add an application my organization is developing`.
6. Enter a name for the application.
7. Click the `WEB APPLICATION AND/OR WEB API` radio button.
8. Click the next arrow `->`.
9. Enter `http://localhost` for the `SIGN-ON URL`.
10. Enter `https://management.azure.com/` for the `APP ID URL`.
11. Click the check icon to complete the application setup.
12. Click `CONFIGURE`.
13. Locate the section named `keys`.
14. Select `1 year` or `2 years` from the drop down.
15. Click `SAVE` at the bottom of the screen.
16. The key value will now be visible. Copy the key value (This is the `azure_client_secret`).
17. Go back to the Azure Portal.
18. Click `Subscriptions`.
19. Click desired subscription.
20. Click `Settings`
21. Click `Users`
22. Click `Add`
23. `Select a role` -> Click `Owner`
24. `Add users` -> In the search box enter application name used above
25. Click the application entry and click `Select`
26. Click `OK`

#### Orchestration Credential Items

The following credential information is provided from Active Directory. After clicking
on the desired directory, the ID can be found within the URL (UUID value)

* `azure_tenant_id` - Active Directory ID

The following credential information is provided from the Active Directory application
entry created above. Under the `CONFIGURE` section:

* `azure_client_id` - Field `CLIENT ID`
* `azure_client_secret` - Field `keys` (can only be viewed when initially saved)

The following credential information is provided from the Azure portal. Click `Subscriptions`.

* `azure_subscription_id` - Azure subscription ID

* `azure_region` - Deployment region (`westus`, `eastus`, etc.)

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

## Info
* Repository: https://github.com/miasma-rb/miasma-azure

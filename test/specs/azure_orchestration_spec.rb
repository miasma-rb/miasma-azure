require_relative '../helper'
require 'miasma/contrib/azure'

describe Miasma::Models::Orchestration::Azure do

  before do
    @orchestration = Miasma.api(
      :type => :orchestration,
      :provider => :azure,
      :credentials => {
        :azure_client_id => ENV['MIASMA_AZURE_CLIENT_ID'],
        :azure_client_secret => ENV['MIASMA_AZURE_CLIENT_SECRET'],
        :azure_subscription_id => ENV['MIASMA_AZURE_SUBSCRIPTION_ID'],
        :azure_tenant_id => ENV['MIASMA_AZURE_TENANT_ID'],
        :azure_blob_account_name => ENV['MIASMA_AZURE_BLOB_ACCOUNT_NAME'],
        :azure_blob_secret_key => ENV['MIASMA_AZURE_BLOB_SECRET_KEY'],
        :azure_region => ENV['MIASMA_AZURE_REGION']
      }
    )
  end

  let(:orchestration){ @orchestration }
  let(:build_args){
    Smash.new(
      :name => 'miasma-test-stack',
      :template => {
        "$schema" => "https://schema.management.azure.com/schemas/2015-01-01/deploymentTemplate.json#",
        "contentVersion" => "1.0.0.0",
        "parameters" => {
          "location" => {
            "type" => "string",
            "defaultValue" => "westus"
          }
        },
        "variables" => {
          "apiVersion" => "2015-06-15"
        },
        "resources"=> [
          {
            "type" => "Microsoft.Network/networkSecurityGroups",
            "properties"=> {
              "securityRules"=> [
                {
                  "name"=>"first_rule",
                  "properties"=> {
                    "description"=>"First Rule",
                    "protocol"=>"Tcp",
                    "sourcePortRange"=>"23-45",
                    "destinationPortRange"=>"46-56",
                    "sourceAddressPrefix"=>"*",
                    "destinationAddressPrefix"=>"*",
                    "access"=>"Allow",
                    "priority"=>123,
                    "direction"=>"Inbound"
                  }
                }
              ]
            },
            "apiVersion"=>"[variables('apiVersion')]",
            "location"=>"[parameters('location')]",
            "name"=>"testNetworkSecurityGroups"
          }
        ]
      },
      :parameters => {
        :location => 'westus'
      }
    )
  }

  instance_exec(&MIASMA_ORCHESTRATION_ABSTRACT)

end

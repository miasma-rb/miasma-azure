require 'miasma'

module Miasma
  module Contrib
    module Azure
      class Api < Miasma::Types::Api
        include Contrib::AzureApiCore::ApiCommon

        attribute :api_endpoint, String, :required => true

        def endpoint
          api_endpoint
        end

      end
    end
  end
end

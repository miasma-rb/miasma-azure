require 'minitest/autorun'
require 'minispec-metadata'
require 'vcr'
require 'minitest-vcr'
require 'webmock/minitest'
require 'mocha/setup'

require 'miasma'
require 'miasma/specs'

VCR.configure do |c|

  json_body_matcher = lambda do |r1, r2|
    begin
      r1_body = MultiJson.load(r1.body).to_smash
      r2_body = MultiJson.load(r2.body).to_smash
      if(r1_body[:tags])
        r1_body[:tags].delete(:updated)
        r1_body[:tags].delete(:created)
        r2_body[:tags].delete(:updated)
        r2_body[:tags].delete(:created)
      end
      r1_body.checksum == r2_body.checksum ||
        (r1_body.fetch(:properties, {}).key?('templateLink') &&
        r2_body.fetch(:properties, {}).key?('templateLink'))
    rescue => e
      r1.body == r2.body
    end
  end

  c.cassette_library_dir = 'test/cassettes'
  c.hook_into :webmock
  c.default_cassette_options = {
    :match_requests_on => [:method, :path, json_body_matcher]
  }
  c.filter_sensitive_data('MIASMA_AZURE_CLIENT_ID'){ ENV['MIASMA_AZURE_CLIENT_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_CLIENT_SECRET'){ ENV['MIASMA_AZURE_CLIENT_SECRET'] }
  c.filter_sensitive_data('MIASMA_AZURE_SUBSCRIPTION_ID'){ ENV['MIASMA_AZURE_SUBSCRIPTION_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_TENANT_ID'){ ENV['MIASMA_AZURE_TENANT_ID'] }
  c.filter_sensitive_data('MIASMA_AZURE_BLOB_ACCOUNT_NAME'){ ENV['MIASMA_AZURE_BLOB_ACCOUNT_NAME'] }
  c.filter_sensitive_data('MIASMA_AZURE_BLOB_SECRET_KEY'){ ENV['MIASMA_AZURE_BLOB_SECRET_KEY'] }
  c.filter_sensitive_data('MIASMA_AZURE_REGION'){ ENV['MIASMA_AZURE_REGION'] }
end

MinitestVcr::Spec.configure!

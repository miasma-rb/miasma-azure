require 'miasma'
require 'base64'

module Miasma
  module Contrib

    module Azure
      autoload :Api, 'miasma-azure/api'
    end

    # Core API for Azure access
    class AzureApiCore

      # @return [String] time in RFC 1123 format
      def self.time_rfc1123
        Time.now.httpdate
      end

      # HMAC helper class
      class Hmac

        # @return [OpenSSL::Digest]
        attr_reader :digest
        # @return [String] secret key
        attr_reader :key

        # Create new HMAC helper
        #
        # @param kind [String] digest type (sha1, sha256, sha512, etc)
        # @param key [String] secret key
        # @return [self]
        def initialize(kind, key)
          @digest = OpenSSL::Digest.new(kind)
          @key = key
        end

        # @return [String]
        def to_s
          "Hmac#{digest.name}"
        end

        # Generate the hexdigest of the content
        #
        # @param content [String] content to digest
        # @return [String] hashed result
        def hexdigest_of(content)
          digest << content
          hash = digest.hexdigest
          digest.reset
          hash
        end

        # Sign the given data
        #
        # @param data [String]
        # @param key_override [Object]
        # @return [Object] signature
        def sign(data, key_override=nil)
          result = OpenSSL::HMAC.digest(digest, key_override || key, data)
          digest.reset
          result
        end

        # Sign the given data and return hexdigest
        #
        # @param data [String]
        # @param key_override [Object]
        # @return [String] hex encoded signature
        def hex_sign(data, key_override=nil)
          result = OpenSSL::HMAC.hexdigest(digest, key_override || key, data)
          digest.reset
          result
        end

      end


      # Base signature class
      class Signature

        # Create new instance
        def initialize(*args)
          raise NotImplementedError.new 'This class should not be used directly!'
        end

        # Generate the signature
        #
        # @param http_method [Symbol] HTTP request method
        # @param path [String] request path
        # @param opts [Hash] request options
        # @return [String] signature
        def generate(http_method, path, opts={})
          raise NotImplementedError
        end

        # URL string escape
        #
        # @param string [String] string to escape
        # @return [String] escaped string
        def safe_escape(string)
          string.to_s.gsub(/([^a-zA-Z0-9_.\-~])/) do
            '%' << $1.unpack('H2' * $1.bytesize).join('%').upcase
          end
        end

      end

      class SignatureAzure < Signature

        # Required Header Items
        SIGNATURE_HEADERS = [
          'Content-Encoding',
          'Content-Language',
          'Content-Length',
          'Content-MD5',
          'Content-Type',
          'Date',
          'If-Modified-Since',
          'If-Match',
          'If-None-Match',
          'If-Unmodified-Since',
          'Range'
        ]

        # @return [Hmac]
        attr_reader :hmac
        # @return [String] shared private key
        attr_reader :shared_key
        # @return [String] name of account
        attr_reader :account_name

        def initialize(shared_key, account_name)
          shared_key = Base64.decode64(shared_key)
          @hmac = Hmac.new('sha256', shared_key)
          @shared_key = shared_key
          @account_name = account_name
        end

        def generate(http_method, path, opts)
          signature = generate_signature(
            http_method,
            opts[:headers],
            opts.merge(:path => path)
          )
          "SharedKey #{account_name}:#{signature}"
        end

        def generate_signature(http_method, headers, resource)
          headers = headers.to_smash
          headers.delete('Content-Length') if headers['Content-Length'].to_s == '0'
          to_sign = [
            http_method.to_s.upcase,
            *self.class.const_get(:SIGNATURE_HEADERS).map{|head_name|
              headers.fetch(head_name, '')
            },
            build_canonical_headers(headers),
            build_canonical_resource(resource)
          ].join("\n")
          signature = sign_request(to_sign)
        end

        def sign_request(request)
          result = hmac.sign(request)
          Base64.encode64(result).strip
        end

        def build_canonical_headers(headers)
          headers.map do |key, value|
            key = key.to_s.downcase
            if(key.start_with?('x-ms-'))
              [key, value].map(&:strip).join(':')
            end
          end.compact.sort.join("\n")
        end

        def build_canonical_resource(resource)
          [
            "/#{account_name}#{resource[:path]}",
            *resource.fetch(:params, {}).map{|key, value|
              key = key.downcase.strip
              value = value.is_a?(Array) ? value.map(&:strip).sort.join(',') : value
              [key, value].join(':')
            }.sort
          ].join("\n")
        end

        class SasBlob < SignatureAzure

          SIGNATURE_HEADERS = [
            'Cache-Control',
            'Content-Disposition',
            'Content-Encoding',
            'Content-Language',
            'Content-Type'
          ]

          def generate(http_method, path, opts)
            params = opts.fetch(:params, Smash.new)
            headers = opts.fetch(:headers, Smash.new)
            to_sign = [
              params[:sp],
              params[:st],
              params[:se],
              ['/blob', account_name, path].join('/'),
              params[:si],
              params[:sip],
              params[:spr],
              params[:sv],
              *self.class.const_get(:SIGNATURE_HEADERS).map{|head_name|
                headers.fetch(head_name, '')
              }
            ].map(&:to_s).join("\n")
            sign_request(to_sign)
          end

        end

      end

      module ApiCommon

        def self.included(klass)
          klass.class_eval do
            attribute :azure_tenant_id, String
            attribute :azure_client_id, String
            attribute :azure_subscription_id, String
            attribute :azure_client_secret, String
            attribute :azure_region, String
            attribute :azure_resource, String, :default => 'https://management.azure.com/'
            attribute :azure_login_url, String, :default => 'https://login.microsoftonline.com'
            attribute :azure_blob_account_name, String
            attribute :azure_blob_secret_key, String
            attribute :azure_root_orchestration_container, String, :default => 'miasma-orchestration-templates'

            attr_reader :signer
          end
        end

        # Setup for API connections
        def connect
          @oauth_token_information = Smash.new
        end

        # @return [HTTP] connection for requests (forces headers)
        def connection
          unless(signer)
            super.headers(
              'Authorization' => "Bearer #{client_access_token}"
            )
          else
            super
          end
        end

        # Perform request
        #
        # @param connection [HTTP]
        # @param http_method [Symbol]
        # @param request_args [Array]
        # @return [HTTP::Response]
        def make_request(connection, http_method, request_args)
          dest, options = request_args
          options = options ? options.to_smash : Smash.new
          options[:headers] = Smash[connection.default_options.headers.to_a].merge(options.fetch(:headers, Smash.new))
          service = Bogo::Utility.snake(self.class.name.split('::')[-2,1].first)
          root_path_method = "#{service}_root_path"
          api_version_method = "#{service}_api_version"
          if(signer)
            options[:headers] ||= Smash.new
            options[:headers]['x-ms-date'] = AzureApiCore.time_rfc1123
            if(self.respond_to?(api_version_method))
              options[:headers]['x-ms-version'] = self.send(api_version_method)
            end
            options[:headers]['Authorization'] = signer.generate(
              http_method, URI.parse(dest).path, options
            )
            az_connection = connection.headers(options[:headers])
          else
            if(self.respond_to?(api_version_method))
              options[:params] ||= Smash.new
              options[:params]['api-version'] = self.send(api_version_method)
            end
            if(self.respond_to?(root_path_method))
              p_dest = URI.parse(dest)
              dest = "#{p_dest.scheme}://#{p_dest.host}"
              dest = File.join(dest, self.send(root_path_method), p_dest.path)
            end
            az_connection = connection
          end
          p http_method
          p dest
          p options
          az_connection.send(http_method, dest, options)
        end

        # @return [String] endpoint for request
        def endpoint
          azure_resource
        end

        def oauth_token_buffer_seconds
          240
        end

        def access_token_expired?
          if(oauth_token_information[:expires_on])
            (oauth_token_information[:expires_on] + oauth_token_buffer_seconds) <
              Time.now
          else
            true
          end
        end

        def client_access_token
          request_client_token if access_token_expired?
          oauth_token_information[:access_token]
        end

        def oauth_token_information
          @oauth_token_information
        end

        def request_client_token
          result = HTTP.post(
            File.join(azure_login_url, azure_tenant_id, 'oauth2', 'token'),
            :form => {
              :grant_type => 'client_credentials',
              :client_id => azure_client_id,
              :client_secret => azure_client_secret,
              :resource => azure_resource
            }
          )
          unless(result.code == 200)
            # TODO: Wrap this in custom exception to play nice
            puts result.inspect
            puts "FAIL: #{result.body.to_s}"
            puts result.headers
            raise 'ACK'
          end
          @oauth_token_information = MultiJson.load(
            result.body.to_s
          ).to_smash
          @oauth_token_information[:expires_on] = Time.at(@oauth_token_information[:expires_on].to_i)
          @oauth_token_information[:not_before] = Time.at(@oauth_token_information[:not_before].to_i)
          @oauth_token_information
        end

        def retryable_allowed?(*_)
          !!ENV['DEBUG']
        end

        # @return [String] custom escape
        def uri_escape(string)
          signer.safe_escape(string)
        end

      end

    end
  end

  Models::Orchestration.autoload :Azure, 'miasma/contrib/azure/orchestration'
  Models::Storage.autoload :Azure, 'miasma/contrib/azure/storage'

  # Models::Compute.autoload :Azure, 'miasma/contrib/azure/compute'
  # Models::LoadBalancer.autoload :Azure, 'miasma/contrib/azure/load_balancer'
  # Models::AutoScale.autoload :Azure, 'miasma/contrib/azure/auto_scale'


end

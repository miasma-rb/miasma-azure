require 'stringio'
require 'miasma'

module Miasma
  module Models
    class Storage
      class Azure < Storage

        REQUIRED_ATTRIBUTES = [
          :azure_blob_secret_key,
          :azure_blob_account_name
        ]

        include Contrib::AzureApiCore::ApiCommon

        # Fetch all results when tokens are being used
        # for paging results
        #
        # @param next_token [String]
        # @param result_key [Array<String, Symbol>] path to result
        # @yield block to perform request
        # @yieldparam options [Hash] request parameters (token information)
        # @return [Array]
        # @note this is customized to S3 since its API is slightly
        #   different than the usual token based fetching
        def all_result_pages(next_token, *result_key, &block)
          list = []
          options = next_token ? Smash.new('marker' => next_token) : Smash.new
          result = block.call(options)
          content = result.get(*result_key.dup)
          if(content.is_a?(Array))
            list += content
          else
            list << content
          end
          set = result.get(*result_key.slice(0, 2))
          if(set.is_a?(Hash) && set['IsTruncated'] && set['Contents'])
            content_key = (set['Contents'].respond_to?(:last) ? set['Contents'].last : set['Contents'])['Key']
            list += all_result_pages(content_key, *result_key, &block)
          end
          list.compact
        end


        attr_reader :url_signer

        # Simple init override to force HOST and adjust region for
        # signatures if required
        def initialize(args)
          args = args.to_smash
          REQUIRED_ATTRIBUTES.each do |name|
            unless(args[name])
              raise ArgumentError.new "Missing required credential `#{name}`!"
            end
          end
          @signer = Contrib::AzureApiCore::SignatureAzure.new(
            args[:azure_blob_secret_key],
            args[:azure_blob_account_name]
          )
          @url_signer = Contrib::AzureApiCore::SignatureAzure::SasBlob.new(
            args[:azure_blob_secret_key],
            args[:azure_blob_account_name]
          )
          super(args)
        end

        def api_version
          '2015-04-05'
        end

        def endpoint
          "https://#{azure_blob_account_name}.blob.core.windows.net"
        end

        # Save bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [Models::Storage::Bucket]
        def bucket_save(bucket)
          unless(bucket.persisted?)
            request(
              :path => bucket.name,
              :method => :put,
              :expects => 201,
              :params => {
                :restype => 'container'
              },
              :headers => {
                'Content-Length' => 0
              }
            )
            bucket.id = bucket.name
            bucket.valid_state
          end
          bucket
        end

        # Destroy bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [TrueClass, FalseClass]
        def bucket_destroy(bucket)
          if(bucket.persisted?)
            request(
              :path => bucket.name,
              :method => :delete,
              :expects => 202,
              :params => {
                :restype => 'container'
              }
            )
            true
          else
            false
          end
        end

        # Reload the bucket
        #
        # @param bucket [Models::Storage::Bucket]
        # @return [Models::Storage::Bucket]
        def bucket_reload(bucket)
          if(bucket.persisted?)
            begin
              result = request(
                :path => bucket.name,
                :method => :head,
                :params => {
                  :restype => 'container'
                }
              )
            rescue Error::ApiError::RequestError => e
              if(e.response.status == 404)
                bucket.data.clear
                bucket.dirty.clear
              else
                raise
              end
            end
          end
          bucket
        end

        # Return all buckets
        #
        # @return [Array<Models::Storage::Bucket>]
        def bucket_all
          result = request(
            :path => '/',
            :params => {
              :comp => 'list'
            }
          )
          cont = result.get(:body, 'EnumerationResults', 'Containers', 'Container')
          unless(cont.is_a?(Array))
            cont = [cont].compact
          end
          cont.map do |bkt|
            Bucket.new(
              self,
              :id => bkt['Name'],
              :name => bkt['Name'],
              :custom => bkt['Properties']
            ).valid_state
          end
        end

        # Return filtered files
        #
        # @param args [Hash] filter options
        # @return [Array<Models::Storage::File>]
        def file_filter(bucket, args)
          result = request(
            :path => bucket.name,
            :params => {
              :restype => 'container',
              :comp => 'list',
              :prefix => args[:prefix]
            }
          )
          [result.get(:body, 'EnumerationResults', 'Blobs', 'Blob')].flatten.compact.map do |file|
            File.new(
              bucket,
              :id => ::File.join(bucket.name, file['Name']),
              :name => file['Name'],
              :updated => file.get('Properties', 'Last_Modified'),
              :size => file.get('Properties', 'Content_Length').to_i
            ).valid_state
          end
        end

        # Return all files within bucket
        #
        # @param bucket [Bucket]
        # @return [Array<File>]
        def file_all(bucket)
          file_filter(bucket, {})
        end

        # Save file
        #
        # @param file [Models::Storage::File]
        # @return [Models::Storage::File]
        def file_save(file)
          if(file.dirty?)
            file.load_data(file.attributes)
            args = Smash.new
            headers = Smash[
              Smash.new(
                :content_type => 'Content-Type',
                :content_disposition => 'Content-Disposition',
                :content_encoding => 'Content-Encoding'
              ).map do |attr, key|
                if(file.attributes[attr])
                  [key, file.attributes[attr]]
                end
              end.compact
            ]
            unless(headers.empty?)
              args[:headers] = headers
            end
            if(file.attributes[:body].respond_to?(:readpartial))
              args.set(:headers, 'Content-Length', file.body.size.to_s)
              file.body.rewind
              args[:body] = file.body.readpartial(file.body.size)
              file.body.rewind
            else
              args.set(:headers, 'Content-Length', 0)
            end
            args.set(:headers, 'x-ms-blob-type', 'BlockBlob')
            result = request(
              args.merge(
                Smash.new(
                  :method => :put,
                  :path => [file.bucket.name, file_path(file)].join('/'),
                  :expects => 201
                )
              )
            )
            file.etag = result.get(:headers, :etag)
            file.id = ::File.join(file.bucket.name, file.name)
            file.valid_state
          end
          file
        end

        # Destroy file
        #
        # @param file [Models::Storage::File]
        # @return [TrueClass, FalseClass]
        def file_destroy(file)
          if(file.persisted?)
            request(
              :method => :delete,
              :path => [file.bucket.name, file_path(file)].join('/'),
              :expects => 202
            )
            true
          else
            false
          end
        end

        # Reload the file
        #
        # @param file [Models::Storage::File]
        # @return [Models::Storage::File]
        def file_reload(file)
          if(file.persisted?)
            name = file.name
            result = request(
              :method => :head,
              :path => [file.bucket.name, file_path(file)].join('/')
            )
            file.data.clear && file.dirty.clear
            info = result[:headers]
            file.load_data(
              :id => [file.bucket.name, name].join('/'),
              :name => name,
              :updated => info[:last_modified],
              :etag => info[:etag],
              :size => info[:content_length].to_i,
              :content_type => info[:content_type]
            ).valid_state
          end
          file
        end

        # Create publicly accessible URL
        #
        # @param timeout_secs [Integer] seconds available
        # @return [String] URL
        def file_url(file, timeout_secs)
          object_path = [file.bucket.name, file_path(file)].join('/')
          sign_args = Smash.new(
            :params => Smash.new(
              :sr => 'b',
              :sv => api_version,
              :se => (Time.now.utc + timeout_secs).iso8601,
              :sp => 'r'
            )
          )
          signature = url_signer.generate(:get, object_path, sign_args)
          uri = URI.parse([endpoint, object_path].join('/'))
          uri.query = URI.encode_www_form(
            sign_args[:params].merge(
              :sig => signature
            )
          )
          uri.to_s
        end

        # Fetch the contents of the file
        #
        # @param file [Models::Storage::File]
        # @return [IO, HTTP::Response::Body]
        def file_body(file)
          file_content = nil
          if(file.persisted?)
            result = request(
              :path => [file.bucket.name, file_path(file)].join('/'),
              :disable_body_extraction => true
            )
            content = result[:body]
            begin
              if(content.is_a?(String))
                file_content = StringIO.new(content)
              else
                if(content.respond_to?(:stream!))
                  content.stream!
                end
                file_content = content
              end
            rescue HTTP::StateError
              file_content = StringIO.new(content.to_s)
            end
          else
            file_content = StringIO.new('')
          end
          File::Streamable.new(file_content)
        end

        # @return [String] escaped file path
        def file_path(file)
          file.name.split('/').map do |part|
            uri_escape(part)
          end.join('/')
        end

      end
    end
  end
end

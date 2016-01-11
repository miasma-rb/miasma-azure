require 'securerandom'
require 'miasma'

module Miasma
  module Models
    class Orchestration
      class Azure < Orchestration

        include Contrib::AzureApiCore::ApiCommon

        STATUS_MAP = Smash.new(
          'Failed' => :create_failed,
          'Canceled' => :create_failed,
          'Succeeded' => :create_complete,
          'Deleting' => :delete_in_progress,
          'Deleted' => :delete_complete
        )

        def orchestration_api_version
          '2015-01-01'
        end

        def generate_path(stack=nil)
          path = "/subscriptions/#{azure_subscription_id}/resourcegroups"
          path << "/#{stack.name}/providers/microsoft.resources/deployments/miasma-stack" if stack
          path
        end

        def status_to_state(val)
          STATUS_MAP.fetch(val, :create_in_progress)
        end

        # Fetch stacks or update provided stack data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack>]
        def load_stack_data(stack=nil)
          if(stack)
            result = request(
              :path => generate_path(stack)
            )
            item = result[:body]
            new_stack = Stack.new(self)
            deployment_id = item[:id]
            stack_id = deployment_id.sub(/\/providers\/microsoft.resources.+/i, '')
            stack_name = File.basename(stack_id)
            new_stack.load_data(
              :id => stack_id,
              :name => stack_name,
              :parameters => Smash[
                item.fetch(:parameters, {}).map do |p_name, p_value|
                  [p_name, p_value[:value]]
                end
              ],
              :outputs => item.fetch(:outputs, {}).map{ |o_name, o_value|
                Smash.new(:key => o_name, :value => o_value[:value])
              },
              :template_url => item.get(:properties, :templateLink, :uri),
              :state => status_to_state(item.get(:properties, :provisioningState)),
              :status => item.get(:properties, :provisioningState),
              :custom => item
            ).valid_state
          else
            result = request(
              :path => generate_path
            )
            result.fetch(:body, :value, []).map do |item|
              new_stack = Stack.new(self)
              new_stack.load_data(
                :id => item[:id],
                :name => item[:name],
                :state => status_to_state(item.get(:properties, :provisioningState)),
                :status => item.get(:properties, :provisioningState)
              ).valid_state
            end
          end
        end

        # Save the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_save(stack)
          store_template!(stack)
          unless(stack.persisted?)
            request(
              :path => [generate_path, stack.name].join('/'),
              :method => :put,
              :params => {
                'api-version' => '2015-01-01'
              },
              :json => {
                :location => azure_region
              },
              :expects => [200, 201]
            )
          end
          result = request(
            :path => generate_path(stack),
            :method => :put,
            :expects => [200, 201],
            :json => {
              :properties => {
                :templateLink => {
                  :uri => stack.template_url,
                  :contentVersion => '1.0.0.0'
                },
                :parameters => stack.parameters,
                :mode => 'Complete'
              }
            }
          )
          deployment_id = result.get(:body, :id)
          stack_id = deployment_id.sub(%r{/microsoft.resources.+}, '')
          stack_name = File.basename(stack_id)
          stack.id = stack_id
          stack.name = stack_name
          stack.valid_state
          stack
        end

        def store_template!(stack)
          storage = api_for(:storage)
          bucket = storage.buckets.get(azure_root_orchestration_container)
          unless(bucket)
            bucket = storage.buckets.build
            bucket.name = azure_root_orchestration_container
            bucket.save
          end
          file = bucket.files.build
          file.name = "#{stack.name}-#{SecureRandom.uuid}.json"
          file.body = MultiJson.dump(stack.template)
          file.save
          stack.template_url = file.url
          stack.template = nil
          stack
        end

        # Reload the stack data from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_reload(stack)
          if(stack.persisted?)
            ustack = Stack.new(self)
            ustack.id = stack.id
            ustack.name = stack.name
            ustack = load_stack_data(ustack)
            if(ustack.data[:name])
              stack.load_data(ustack.attributes).valid_state
            else
              stack.status = 'Deleted'
              stack.state = :delete_complete
              stack.valid_state
            end
          end
          stack
        end

        # Delete the stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [TrueClass, FalseClass]
        def stack_destroy(stack)
          if(stack.persisted?)
            request(
              :method => :delete,
              :expects => 202,
              :path => generate_path(stack)
            )
            request(
              :path => [generate_path, stack.name].join('/'),
              :method => :delete,
              :expects => 202
            )
            true
          else
            false
          end
        end

        # Fetch stack template
        #
        # @param stack [Stack]
        # @return [Smash] stack template
        def stack_template_load(stack)
          if(stack.persisted?)
            if(stack.template_url)
              storage = api_for(:storage)
              location = URI.parse(stack.template_url)
              bucket, file = location.path.sub('/', '').split('/', 2)
              file = storage.buckets.get(bucket).files.get(file)
              MultiJson.load(file.body.read).to_smash
            else
              raise "Stack template is not remotely stored. Unavailable! (stack: `#{stack.name}`)"
            end
          else
            Smash.new
          end
        end

        # Validate stack template
        #
        # @param stack [Stack]
        # @return [NilClass, String] nil if valid, string error message if invalid
        def stack_template_validate(stack)
          begin
            result = request(
              :method => :post,
              :path => '/',
              :form => Smash.new(
                'Action' => 'ValidateTemplate',
                'TemplateBody' => MultiJson.dump(stack.template)
              )
            )
            nil
          rescue Error::ApiError::RequestError => e
            MultiXml.parse(e.response.body.to_s).to_smash.get(
              'ErrorResponse', 'Error', 'Message'
            )
          end
        end

        # Return single stack
        #
        # @param ident [String] name or ID
        # @return [Stack]
        def stack_get(ident)
          i = Stack.new(self)
          i.id = ident
          i.reload
          i.name ? i : nil
        end

        # Return all stacks
        #
        # @param options [Hash] filter
        # @return [Array<Models::Orchestration::Stack>]
        # @todo check if we need any mappings on state set
        def stack_all
          load_stack_data
        end

        # Return all resources for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Resource>]
        def resource_all(stack)
          stack.custom.fetch(:properties, :dependencies, []).map do |res|
            evt = stack.events.all.detect{|ev| ev.resource_id == res[:id]}
            Stack::Resource.new(
              stack,
              :id => res[:id],
              :type => res[:resourceType],
              :name => res[:resourceName],
              :logical_id => res[:resourceName],
              :state => evt.resource_state,
              :status => evt.resource_status,
              :status_reason => evt.resource_status_reason,
              :updated => evt.time
            ).valid_state
          end
        end

        # Reload the stack resource data from the API
        #
        # @param resource [Models::Orchestration::Stack::Resource]
        # @return [Models::Orchestration::Resource]
        def resource_reload(resource)
          resource.stack.resources.reload
          resource.stack.resources.get(resource.id)
        end

        # Return all events for stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all(stack, evt_id=nil)
          result = request(
            :path => [generate_path(stack), 'operations'].join('/')
          )
          events = result.get(:body, :value).map do |event|
            Stack::Event.new(
              stack,
              :id => event[:operationId],
              :resource_id => event.get(:properties, :targetResource, :id),
              :resource_name => event.get(:properties, :targetResource, :resourceName),
              :resource_state => status_to_state(event.get(:properties, :provisioningState)),
              :resource_status => event.get(:properties, :provisioningState),
              :resource_status_reason => event.get(:properties, :statusCode),
              :time => Time.parse(event.get(:properties, :timestamp))
            ).valid_state
          end
          if(evt_id)
            idx = events.index{|d| e.id == evt_id}
            idx = idx ? idx + 1 : 0
            events.slice(idx, events.size)
          else
            events
          end
        end

        # Return all new events for event collection
        #
        # @param events [Models::Orchestration::Stack::Events]
        # @return [Array<Models::Orchestration::Stack::Event>]
        def event_all_new(events)
          event_all(events.stack, events.all.first.id)
        end

        # Reload the stack event data from the API
        #
        # @param resource [Models::Orchestration::Stack::Event]
        # @return [Models::Orchestration::Event]
        def event_reload(event)
          event.stack.events.reload
          event.stack.events.get(event.id)
        end

      end
    end
  end
end

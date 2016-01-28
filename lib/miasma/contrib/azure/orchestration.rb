require 'securerandom'
require 'miasma'

module Miasma
  module Models
    class Orchestration
      class Azure < Orchestration

        include Contrib::AzureApiCore::ApiCommon

        # Resource status to state mapping
        STATUS_MAP = Smash.new(
          'Failed' => :create_failed,
          'Canceled' => :create_failed,
          'Succeeded' => :create_complete,
          'Deleting' => :delete_in_progress,
          'Deleted' => :delete_complete
        )

        # @return [String] supported API version
        def api_version
          '2015-01-01'
        end

        # Generate the URL path required for given stack
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [String] generated path
        def generate_path(stack=nil)
          path = "/subscriptions/#{azure_subscription_id}/resourcegroups"
          path << "/#{stack.name}/providers/microsoft.resources/deployments/miasma-stack" if stack
          path
        end

        # Convert given status value to correct state value
        #
        # @param val [String] Resource status
        # @param modifier [String, Symbol] optional state prefix modifier
        # @return [Symbol] resource state
        def status_to_state(val, modifier=nil)
          val = STATUS_MAP.fetch(val, :create_in_progress)
          if(modifier && modifier.to_s != 'create' && val.to_s.start_with?('create'))
            val = val.to_s.sub('create', modifier).to_sym
          end
          val
        end

        # Fetch stacks or update provided stack data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Array<Models::Orchestration::Stack>]
        def load_stack_data(stack=nil)
          if(stack)
            fetch_single_stack(stack)
          else
            fetch_all_stacks.map do |n_stack|
              fetch_single_stack(n_stack)
            end
          end
        end

        # Populate stack model data
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def fetch_single_stack(stack)
          unless(stack.custom[:base_load])
            n_stack = fetch_all_stacks.detect do |s|
              s.name == stack.name ||
                s.id == stack.id
            end
            if(n_stack)
              stack.data.deep_merge!(n_stack.attributes)
            else
              stack.state = :delete_complete
              stack.status = 'Deleted'
              return stack
            end
          end
          stack.custom.delete(:base_load)
          result = request(
            :path => generate_path(stack),
            :expects => [200, 404]
          )
          if(result[:response].code == 404)
            if(stack.tags && state = stack.tags[:state])
              case state
              when 'create'
                stack.status = 'Creating'
                stack.state = :create_in_progress
              else
                stack.status = 'Deleting'
                stack.state = :delete_in_progress
              end
            else
              stack.data.merge!(
                :state => :unknown,
                :status => 'Unknown'
              )
            end
            stack.valid_state
          else
            item = result[:body]
            deployment_id = item[:id]
            stack_id = deployment_id.sub(/\/providers\/microsoft.resources.+/i, '')
            stack_name = File.basename(stack_id)
            stack.data.merge!(
              :id => stack_id,
              :name => stack_name,
              :parameters => Smash[
                item.fetch(:properties, :parameters, {}).map do |p_name, p_value|
                  [p_name, p_value[:value]]
                end
              ],
              :outputs => item.fetch(:properties, :outputs, {}).map{ |o_name, o_value|
                Stack::Output.new(stack,
                  :key => o_name,
                  :value => o_value[:value]
                )
              },
              :template_url => item.get(:properties, :templateLink, :uri),
              :state => status_to_state(
                item.get(:properties, :provisioningState),
                stack.tags[:state]
              ),
              :status => item.get(:properties, :provisioningState),
              :updated => Time.parse(item.get(:properties, :timestamp)),
              :custom => item
            )
            stack.valid_state
          end
        end

        # Fetch all available stacks
        #
        # @return [Array<Models::Orchestration::Stack>]
        def fetch_all_stacks
          result = request(
            :path => generate_path
          )
          result.fetch(:body, :value, []).map do |item|
            new_stack = Stack.new(self)
            new_stack.load_data(
              :id => item[:id],
              :name => item[:name],
              :state => status_to_state(
                item.get(:properties, :provisioningState),
                item.get(:tags, :state)
              ),
              :status => item.get(:properties, :provisioningState),
              :tags => item.fetch(:tags, Smash.new),
              :created => item.get(:tags, :created) ? Time.at(item.get(:tags, :created).to_i).utc : nil,
              :custom => Smash.new(:base_load => true)
            ).valid_state
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
              :json => {
                :location => azure_region,
                :tags => {
                  :created => Time.now.to_i,
                  :state => 'create'
                }
              },
              :expects => [200, 201]
            )
          else
            request(
              :path => [generate_path, stack.name].join('/'),
              :method => :patch,
              :json => {
                :tags => stack.tags.merge(
                  :updated => Time.now.to_i,
                  :state => 'update'
                )
              }
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
                :parameters => Smash[
                  stack.parameters.map do |p_key, p_value|
                    [p_key, :value => p_value]
                  end
                ],
                :mode => 'Complete'
              }
            }
          )
          deployment_id = result.get(:body, :id)
          stack_id = deployment_id.sub(/\/providers\/microsoft.resources.+/i, '')
          stack_name = File.basename(stack_id)
          stack.id = stack_id
          stack.name = stack_name
          stack.valid_state
          stack
        end

        # Store the stack template in the object store for future
        # reference
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def store_template!(stack)
          storage = api_for(:storage)
          bucket = storage.buckets.get(azure_root_orchestration_container)
          unless(bucket)
            bucket = storage.buckets.build
            bucket.name = azure_root_orchestration_container
            bucket.save
          end
          file = bucket.files.build
          file.name = "#{stack.name}-#{attributes.checksum}.json"
          file.body = MultiJson.dump(stack.template)
          file.save
          stack.template_url = file.url
          stack.template = nil
          stack
        end

        # Delete the stack template persisted in the object store
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [TrueClass, NilClass]
        def delete_template!(stack)
          storage = api_for(:storage)
          bucket = storage.buckets.get(azure_root_orchestration_container)
          if(bucket)
            t_file = bucket.files.get("#{stack.name}-#{attributes.checksum}.json")
            if(t_file)
              t_file.destroy
              true
            end
          end
        end

        # Reload the stack data from the API
        #
        # @param stack [Models::Orchestration::Stack]
        # @return [Models::Orchestration::Stack]
        def stack_reload(stack)
          if(stack.persisted?)
            load_stack_data(stack)
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
              :path => [generate_path, stack.name].join('/'),
              :method => :patch,
              :json => {
                :tags => stack.tags.merge(
                  :updated => Time.now.to_i,
                  :state => 'delete'
                )
              }
            )
            delete_template!(stack)
            request(
              :method => :delete,
              :expects => [202, 204],
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
              file.body.rewind
              MultiJson.load(file.body.read).to_smash
            else
              Smash.new
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
              :path => [generate_path(stack), 'validate'].join('/'),
              :method => :post,
              :json => {
                :properties => {
                  :template => stack.template,
                  :parameters => stack.parameters,
                  :mode => 'Complete'
                }
              }
            )
            nil
          rescue Error::ApiError::RequestError => e
            begin
              error = MultiJson.load(e.response.body.to_s).to_smash
              "#{error.get(:error, :code)} - #{error.get(:error, :message)}"
            rescue
              "Failed to extract error information! - #{e.response.body.to_s}"
            end
          end
        end

        # Return single stack
        #
        # @param ident [String] name or ID
        # @return [Stack]
        def stack_get(ident)
          i = Stack.new(self)
          i.id = i.name = ident
          i.reload
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
          if(stack.persisted?)
            result = request(
              :path => [generate_path, stack.name, 'resources'].join('/'),
            )
            result.fetch(:body, :value, []).map do |res|
              info = Smash.new(
                :id => res[:id],
                :type => res[:type],
                :name => res[:name],
                :logical_id => res[:name],
                :state => :unknown,
                :status => 'Unknown'
              )
              evt = stack.events.all.detect do |event|
                event.resource_id == res[:id]
              end
              if(evt)
                info = info.merge(
                  Smash.new(
                    :state => evt.resource_state,
                    :status => evt.resource_status,
                    :status_reason => evt.resource_status_reason,
                    :updated => evt.time
                  )
                )
              end
              Stack::Resource.new(stack, info).valid_state
            end
          else
            []
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
          # TODO and NOTE
          # Operations can't be viewed when deletion is progress. For now
          # just return nothing. This should be replaced with customized
          # events: poll resource group resources and generate event items
          # as resources are deleted
          if(stack.state == :delete_in_progress)
            []
          else
            result = request(
              :path => [generate_path(stack), 'operations'].join('/')
            )
            events = result.get(:body, :value).map do |event|
              Stack::Event.new(
                stack,
                :id => event[:operationId],
                :resource_id => event.get(:properties, :targetResource, :id),
                :resource_name => event.get(:properties, :targetResource, :resourceName),
                :resource_logical_id => event.get(:properties, :targetResource, :resourceName),
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

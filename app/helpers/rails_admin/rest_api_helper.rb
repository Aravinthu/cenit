require 'rails_admin/rest_api/jquery'

module RailsAdmin
  ###
  # Generate sdk code for api service.
  module RestApiHelper

    include RailsAdmin::RestApi::Curl
    include RailsAdmin::RestApi::Php
    include RailsAdmin::RestApi::Ruby
    include RailsAdmin::RestApi::Python
    include RailsAdmin::RestApi::Nodejs
    include RailsAdmin::RestApi::JQuery

    def api_langs
      [
        { id: 'curl', label: 'Curl', hljs: 'bash' },
        { id: 'php', label: 'Php', hljs: 'php' },
        { id: 'ruby', label: 'Ruby', hljs: 'ruby' },
        { id: 'python', label: 'Python', hljs: 'python' },
        { id: 'nodejs', label: 'Nodejs', hljs: 'javascript' },
        { id: 'jquery', label: 'JQuery', hljs: 'javascript' },
      ]
    end

    ###
    # Returns api specification paths for current namespace and model.
    def api_current_paths
      @api_current_paths ||= begin
        ns, model_name, display_name = api_model

        {
          "#{ns}/#{model_name}/{id}" => {
            get: api_spec_for_get(display_name),
            delete: api_spec_for_delete(display_name)
          },
          "#{ns}/#{model_name}/{id}/{view}" => {
            get: api_spec_for_get_with_view(display_name)
          },
          "#{ns}/#{model_name}" => {
            get: api_spec_for_list(display_name),
            post: api_spec_for_create(display_name)
          }
        }

      end if params[:model_name].present?

      @api_current_paths ||= []

    rescue
      []
    end

    ###
    # Returns data and login.
    def vars(method, path)
      # Get parameters definition.
      query_parameters = api_parameters(method, path, 'query')

      # Get data object from query parameters.
      data = query_parameters.map { |p| [p[:name], api_default_param_value(p)] }.to_h

      # Get login account or user.
      login = Account.current || User.current

      [data, login]
    end

    ###
    # Returns lang command for service with given method and path.
    def api_code(lang, method, path)
      send("api_#{lang}_code", method, path)
    end

    ###
    # Returns URL command for service with given method and path.
    def api_url(method, path)
      # Get parameters definition.
      path_parameters = api_parameters(method, path)

      api_uri(path, path_parameters)
    end

    protected

    ###
    # Returns parameters for service with given method and path.
    def api_parameters(method, path, _in = 'path')
      parameters = api_current_paths[path][method][:parameters] || []
      parameters.select { |p| p[:in] == _in }
    end

    ###
    # Returns default value from parameter.
    def api_default_param_value(param)
      values = { 'integer' => 0, 'number' => 0, 'real' => 0, 'boolean' => false, 'object' => {}, 'array' => [] }
      param[:default] || values[param[:type]] || ''
    end

    ###
    # Returns api uri.
    def api_uri(method, path)
      path_parameters = api_parameters(method, path, 'path')
      uri = (Rails.env.development? ? 'http://127.0.0.1:3000' : 'https://cenit.io') + "/api/v2/#{path}"

      # Set value of uri path parameters
      path_parameters.each do |p|
        if @object.respond_to?(p[:name])
          value = @object.send(p[:name])
          uri.gsub!("{#{p[:name]}}", value) unless value.to_s.empty?
        end
      end if @object

      "#{uri}.json"
    end

    ###
    # Returns service get specification.
    def api_spec_for_get(display_name)
      {
        tags: [display_name],
        summary: "Retrieve an existing '#{display_name}'",
        description: [
          "Retrieves the details of an existing '#{display_name}'.",
          "You need only supply the unique '#{display_name}' identifier",
          "that was returned upon '#{display_name}' creation."
        ].join(' '),
        parameters: [{ description: 'Identifier', in: 'path', name: 'id', type: 'string', required: true }]
      }
    end

    ###
    # Returns service get specification with view parameter.
    def api_spec_for_get_with_view(display_name)
      {
        tags: [display_name],
        summary: "Retrieve one attribute of an existing '#{display_name}'",
        description: "Retrieves one attribute of an existing '#{display_name}'.",
        parameters: [
          { description: 'Identifier', in: 'path', name: 'id', type: 'string', required: true },
          { description: 'Attribute name', in: 'path', name: 'view', type: 'string', required: true }
        ]
      }
    end

    ###
    # Returns service delete specification.
    def api_spec_for_delete(display_name)
      {
        tags: [display_name],
        summary: "Delete an existing '#{display_name}'",
        description: "Permanently deletes an existing '#{display_name}'. It cannot be undone.",
        parameters: [
          { description: 'Identifier', in: 'path', name: 'id', type: 'string', required: true }
        ]
      }
    end

    ###
    # Returns service list specification.
    def api_spec_for_list(display_name)
      limit = Kaminari.config.default_per_page

      {
        tags: [display_name],
        summary: "Retrieve all existing '#{display_name.pluralize}'",
        description: "Retrieve all existing '#{display_name.pluralize}' you've previously created.",
        parameters: [
          { description: 'Page number', in: 'query', name: 'page', type: 'integer', default: 1 },
          { description: 'Page size', in: 'query', name: 'limit', type: 'integer', default: limit },
          { description: 'Items order', in: 'query', name: 'order', type: 'string', default: 'id' },
          { description: 'JSON Criteria', in: 'query', name: 'where', type: 'string', default: '{}' }
        ]
      }
    end

    ###
    # Returns service create or update specification.
    def api_spec_for_create(display_name)
      parameters = @data_type ? api_params_from_data_type : api_params_from_current_model

      {
        tags: [display_name],
        summary: "Create or update an '#{display_name}'",
        description: [
          "Creates or updates the specified '#{display_name}'.",
          'Any parameters not provided will be left unchanged'
        ].join(' '),
        parameters: [{ description: 'Identifier', in: 'path', name: 'id', type: 'string' }] + parameters
      }
    end

    ###
    # Returns prepared parameters from data type code properties.
    def api_params_from_data_type()
      code = JSON.parse(@data_type.code)
      code['properties'].map { |k, v| { in: 'query', name: k, type: v['type'] } }
    end

    ###
    # Returns prepared parameters from current model properties.
    def api_params_from_current_model
      exclude = /^(created_at|updated_at|version|origin)$|_ids?$/
      params = @properties.map { |p| { in: 'query', name: p.property.name, type: p.property.type } }
      params.select { |p| !p[:name].match(exclude) }
    end

    ###
    # Returns current namespace, model name and display name.
    def api_model
      if @data_type
        ns = @data_type.namespace.parameterize.underscore.downcase
        model_name = @data_type.slug
        display_name = @data_type.name.chomp('.json').humanize
      else
        ns = 'setup'
        model_name = params[:model_name]
        display_name = model_name.humanize
      end

      [ns, model_name, display_name]
    end

  end
end

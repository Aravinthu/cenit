module RailsAdmin
  MainController.class_eval do
    include RestApiHelper
    include SwaggerHelper

    alias_method :rails_admin_list_entries, :list_entries

    def list_entries(model_config = @model_config, auth_scope_key = :index, additional_scope = get_association_scope_from_params, pagination = !(params[:associated_collection] || params[:all] || params[:bulk_ids]))
      scope = rails_admin_list_entries(model_config, auth_scope_key, additional_scope, pagination)
      if (model = model_config.abstract_model.model).is_a?(Class)
        if model.include?(CrossOrigin::Document)
          origins = []
          model.origins.each { |origin| origins << origin if params[origin_param="#{origin}_origin"].to_i.even? }
          origins << nil if origins.include?(:default)
          scope = scope.any_in(origin: origins)
        end
        if (filter_token = params[:filter_token]) && (filter_token = Cenit::Token.where(token: filter_token).first)
          if (criteria = filter_token.data && filter_token.data['criteria']).is_a?(Hash)
            scope = scope.and(criteria)
          end
        end
      elsif (output = Setup::AlgorithmOutput.where(id: params[:algorithm_output]).first) &&
        output.data_type == model.data_type
        scope = scope.any_in(id: output.output_ids)
      end
      scope
    end

    def sanitize_params_for!(action, model_config = @model_config, target_params = params[@abstract_model.param_key])
      return unless target_params.present?
      #Patch
      fields = model_config.send(action).with(controller: self, view: view_context, object: @object).fields.select do |field|
        !(field.properties.is_a?(RailsAdmin::Adapters::Mongoid::Property) && field.properties.property.is_a?(Mongoid::Fields::ForeignKey))
      end
      allowed_methods = fields.collect(&:allowed_methods).flatten.uniq.collect(&:to_s) << 'id' << '_destroy'
      fields.each { |f| f.parse_input(target_params) }
      target_params.slice!(*allowed_methods)
      target_params.permit! if target_params.respond_to?(:permit!)
      fields.select(&:nested_form).each do |association|
        children_params = association.multiple? ? target_params[association.method_name].try(:values) : [target_params[association.method_name]].compact
        (children_params || []).each do |children_param|
          sanitize_params_for!(:nested, association.associated_model_config, children_param)
        end
      end
    end

    def check_for_cancel
      #Patch
      return unless params[:_continue] || (params[:bulk_action] && !params[:bulk_ids] && !params[:object_ids])
      if params[:model_name]
        redirect_to(back_or_index, notice: t('admin.flash.noaction'))
      else
        flash[:notice] = t('admin.flash.noaction')
        redirect_to dashboard_path
      end
    end

    def handle_save_error(whereto = :new)
      #Patch
      if @object && @object.errors.present?
        flash.now[:error] = t('admin.flash.error', name: @model_config.label, action: t("admin.actions.#{@action.key}.done").html_safe).html_safe
        flash.now[:error] += %(<br>- #{@object.errors.full_messages.join('<br>- ')}).html_safe
      end

      respond_to do |format|
        format.html { render whereto, status: :not_acceptable }
        format.js { render whereto, layout: false, status: :not_acceptable }
      end
    end

    def do_flash_process_result(objs)
      messages =
        if objs.is_a?(Hash)
          objs.collect do |key, value|
            "#{obj2msg(key)}: #{obj2msg(value)}"
          end
        else
          objs = [objs] unless objs.is_a?(Enumerable)
          objs.collect { |obj| obj2msg(obj) }
        end
      model_label = @model_config.label
      model_label = @model_config.label_plural if @action.bulkable?
      do_flash(:notice, t('admin.flash.processed', name: model_label, action: t("admin.actions.#{@action.key}.doing")) + ':', messages)
    end

    def obj2msg(obj)
      case obj
      when String, Symbol
        obj.to_s.to_title
      else
        amc = RailsAdmin.config(obj)
        am = amc.abstract_model
        wording = obj.send(amc.object_label_method)
        if (show_action = view_context.action(:show, am, obj))
          wording + ' ' + view_context.link_to(t('admin.flash.click_here'), view_context.url_for(action: show_action.action_name, model_name: am.to_param, id: obj.id), class: 'pjax')
        else
          wording
        end
      end
    end

    def do_flash(flash_key, header, messages = [], options = {})
      do_flash_on(flash, flash_key, header, messages, options)
    end

    def do_flash_now(flash_key, header, messages = [], options = {})
      do_flash_on(flash.now, flash_key, header, messages, options)
    end

    def do_flash_on(flash_hash, flash_key, header, messages = [], options = {})
      options = (options || {}).reverse_merge(reset: true)
      flash_message = header.html_safe
      flash_message = flash_hash[flash_key] + flash_message unless options[:reset] || flash_hash[flash_key].nil?
      max_message_count = options[:max] || 5
      max_message_length = 500
      max_length = 1500
      messages = [messages] unless messages.is_a?(Enumerable)
      msgs = messages[0..max_message_count].collect { |msg| msg.length < max_message_length ? msg : msg[0..max_message_length] + '...' }
      count = 0
      msgs.each do |msg|
        if flash_message.length < max_length
          flash_message += "<br>- #{msg}".html_safe
          count += 1
        end
      end
      if (count = messages.length - count) > 0
        flash_message += "<br>- and another #{count}.".html_safe
      end
      flash_hash[flash_key] = flash_message.html_safe
    end

    def get_association_scope_from_params
      return nil unless params[:associated_collection].present?
      #Patch
      if (source_abstract_model = RailsAdmin::AbstractModel.new(to_model_name(params[:source_abstract_model])))
        source_model_config = source_abstract_model.config
        source_object = source_abstract_model.get(params[:source_object_id])
        action = params[:current_action].in?(%w(create update)) ? params[:current_action] : 'edit'
        @association = source_model_config.send(action).fields.detect { |f| f.name == params[:associated_collection].to_sym }.with(controller: self, object: source_object)
        @association.associated_collection_scope
      end
    end
  end
end

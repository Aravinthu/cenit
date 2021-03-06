module Setup
  class DataType
    include SharedConfigurable
    include NamespaceNamed
    include SchemaHandler
    include DataTypeParser
    include CustomTitle
    include Mongoff::DataTypeMethods
    include ClassHierarchyAware
    include ModelConfigurable
    include RailsAdmin::Models::Setup::DataTypeAdmin

    origins origins_config, :cenit

    abstract_class true

    build_in_data_type.with(:title, :name, :before_save_callbacks, :records_methods, :data_type_methods).referenced_by(:namespace, :name)
    build_in_data_type.and({
                             properties: {
                               slug: {
                                 type: 'string'
                               }
                             }
                           }.deep_stringify_keys)

    deny :delete, :new, :switch_navigation, :copy

    config_with Setup::DataTypeConfig, only: :slug

    field :title, type: String

    has_and_belongs_to_many :before_save_callbacks, class_name: Setup::Algorithm.to_s, inverse_of: nil
    has_and_belongs_to_many :records_methods, class_name: Setup::Algorithm.to_s, inverse_of: nil
    has_and_belongs_to_many :data_type_methods, class_name: Setup::Algorithm.to_s, inverse_of: nil

    attr_readonly :name

    before_save :validates_configuration

    after_destroy do
      clean_up
    end

    def validates_configuration
      invalid_algorithms = []
      before_save_callbacks.each { |algorithm| invalid_algorithms << algorithm unless algorithm.parameters.count == 1 }
      if invalid_algorithms.present?
        errors.add(:before_save_callbacks, "algorithms should receive just one parameter: #{invalid_algorithms.collect(&:custom_title).to_sentence}")
      end
      [:records_methods, :data_type_methods].each do |methods|
        by_name = Hash.new { |h, k| h[k] = 0 }
        send(methods).each do |method|
          by_name[method.name] += 1
          if method.parameters.count == 0
            errors.add(methods, "contains algorithm taking no parameter: #{method.custom_title} (at less one parameter is required)")
          end
        end
        if (duplicated_names = by_name.select { |_, count| count > 1 }.keys).present?
          errors.add(methods, "contains algorithms with the same name: #{duplicated_names.to_sentence}")
        end
      end
      unless config.validate_slug
        config.errors.messages[:slug].each { |error| errors.add(:slug, error) }
      end
      errors.blank?
    end

    def clean_up
      all_data_type_collections_names.each { |name| Mongoid.default_client[name.to_sym].drop }
    end

    def subtype?
      false
    end

    def data_type_storage_collection_name
      Account.tenant_collection_name(data_type_name)
    end

    def data_type_collection_name
      data_type_storage_collection_name
    end

    def all_data_type_collections_names
      all_data_type_storage_collections_names
    end

    def all_data_type_storage_collections_names
      [data_type_storage_collection_name]
    end

    def storage_size(scale=1)
      records_model.storage_size(scale)
    end

    def count
      records_model.count
    end

    def records_model
      (m = model) && m.is_a?(Class) ? m : @mongoff_model ||= create_mongoff_model
    end

    def model
      data_type_name.constantize rescue nil
    end

    def data_type_name
      "Dt#{self.id.to_s}"
    end

    def create_default_events
      if records_model.persistable? && Setup::Observer.where(data_type: self).empty?
        Setup::Observer.create(data_type: self, triggers: '{"created_at":{"0":{"o":"_not_null","v":["","",""]}}}')
        Setup::Observer.create(data_type: self, triggers: '{"updated_at":{"0":{"o":"_presence_change","v":["","",""]}}}')
      end
    end

    def find_data_type(ref, ns = namespace)
      super ||
        self.class.find_data_type(ref, ns) ||
        ((ref = ref.to_s).start_with?('Dt') && Setup::DataType.where(id: ref.from(2)).first) ||
        nil
    end

    def method_missing(symbol, *args)
      if (method = data_type_methods.detect { |alg| alg.name == symbol.to_s })
        args.unshift(self)
        method.reload
        method.run(args)
      else
        super
      end
    end

    class << self

      def inherited(subclass)
        super
        origins = origins_config.dup
        origins.delete(:cenit)
        subclass.origins origins
      end

      def for_name(name)
        where(id: name.from(2)).first
      end

      def find_data_type(ref, ns = '')
        if ref.is_a?(Hash)
          ns = ref['namespace'].to_s
        end
        Setup::DataType.where(namespace: ns, name: ref).first
      end
    end

    protected

    def mongoff_model_class
      Mongoff::Model
    end

    def create_mongoff_model
      mongoff_model_class.for(data_type: self)
    end
  end
end

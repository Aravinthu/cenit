module Setup
  class DataImport < Setup::Task
    include Setup::TranslationCommon
    include Setup::DataUploader
    include Setup::DataIterator
    include RailsAdmin::Models::Setup::DataImportAdmin

    build_in_data_type

    protected

    def translate_import(message)
      each_entry do |_, data|
        translator.run(target_data_type: data_type_from(message),
                       data: data,
                       options: message[:options].deep_dup)
      end
    end

  end
end

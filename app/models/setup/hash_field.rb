module Setup
  module HashField
    extend ActiveSupport::Concern

    def check_before_save
      errors.blank?
    end

    module ClassMethods

      def hash_field(*field_names)
        field_names = field_names.collect(&:to_s)
        field_names.reject!(&:blank?)

        field_names.each do |field_name|
          field field_name, default: {}
        end

        before_save do
          check_before_save &&
            field_names.each do |field|
              if (value = attributes[field]).is_a?(Hash)
                attributes[field] = value = value.to_json
              end
              if (changed_value = changed_attributes[field]) &&
                (changed_value.is_a?(String) || (changed_value = changed_value.to_json)) &&
                value == changed_value
                changed_attributes.delete(field)
              end
            end && errors.blank?
        end

        class_eval("def read_attribute(name)
          value = super
          if %w(#{field_names.join(' ')}).include?(name = name.to_s) && value.is_a?(String)
            attributes[name] = JSON.parse(value) rescue value
            value = attributes[name]
          end
          value
        end")
      end
    end
  end
end
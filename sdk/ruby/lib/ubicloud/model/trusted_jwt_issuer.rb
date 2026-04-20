# frozen_string_literal: true

module Ubicloud
  class TrustedJwtIssuer < Model
    set_prefix "jw"

    set_fragment "token/jwt-issuer"

    set_columns :id, :name, :issuer, :jwks_uri

    def self.create(adapter, name:, issuer:, jwks_uri:)
      new(adapter, adapter.post(fragment.to_s, name:, issuer:, jwks_uri:))
    end

    def self.list(adapter)
      super
    end

    def initialize(adapter, values)
      @adapter = adapter

      case values
      when String
        unless self.class.id_regexp.match?(values)
          raise Error, "invalid #{self.class.fragment} id"
        end

        @values = {id: values}
      when Hash
        unless values[:id]
          raise Error, "hash must have :id key"
        end

        @values = {}
        merge_into_values(values)
      else
        raise Error, "unsupported value initializing #{self.class}: #{values.inspect}"
      end
    end

    undef_method :location
    undef_method :name
    undef_method :load_object_info_from_id

    def id
      @values[:id]
    end

    def name
      @values.fetch(:name) {
        info
        @values[:name]
      }
    end

    def check_exists
      _info(missing: nil)
    end

    private

    def _path
      "#{self.class.fragment}/#{id}"
    end
  end
end

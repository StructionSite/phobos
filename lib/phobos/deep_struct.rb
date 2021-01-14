# frozen_string_literal: true

# Please use this with at least the same consideration as you would when using OpenStruct.
# Right now we only use this to parse our internal configuration files. It is not meant to
# be used on incoming data.
module Phobos
  class DeepStruct < OpenStruct
    # Based on
    # https://docs.omniref.com/ruby/2.3.0/files/lib/ostruct.rb#line=88
    def initialize(hash = nil)
      super
      @hash_table = {}

      hash&.each_pair do |key, value|
        key = key.to_sym
        @table[key] = to_deep_struct(value)
        @hash_table[key] = value
      end
    end

    def to_h
      @hash_table.dup
    end
    alias to_hash to_h

    private

    def to_deep_struct(value)
      case value
      when Hash
        self.class.new(value)
      when Enumerable
        value.map { |el| to_deep_struct(el) }
      else
        value
      end
    end
  end
end

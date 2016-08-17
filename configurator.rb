require 'json'
require 'yaml'
require 'optparse'

class Configurator
  DEFAULTS = "defaults"
  CLI = "cli"
  REQUIRED_KEYS = [
    DEFAULTS,
    CLI
  ]

  def initialize(conf_file)
    @raw = ingest_yaml_conf(conf_file)
    @conf = process_raw_conf
  end

  def hash
    @conf
  end

  def json
    @conf.to_json
  end

  def yaml
    @conf.to_yaml
  end

  private
  class ::Hash
    def deep_merge!(second)
      merger = proc { |key, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : v2 }
      self.merge!(second, &merger)
    end
  end

  class CommandLineOptions
    CLI_KEY = "cli_key"
    TYPE_KEY = "type"
    FILE_CONTENTS_TYPE = "file-contents"
    FLOAT_TYPE = "float"
    KEYS = "keys"
    DESC = "desc"
    attr_accessor :options, :parser

    def initialize(cli_conf)
      raise "config syntax error" unless cli_conf.kind_of?(Array)
      @cli_conf = cli_conf
      @options = Hash.new {|h,k| h[k] = Hash.new(&h.default_proc)}
      @parser = OptionParser.new do |opts|
        @cli_conf.each do |cli|
          opts.on(cli[CLI_KEY], String, cli[DESC]) {|param| set_nested(@options, cli[KEYS], param)}
        end
      end
      @parser.parse!
      process_data_types
    end

    private
    def set_nested(hash, keys, value)
      if keys.count == 1
        hash[keys.first] = value
      elsif keys.count > 1
        last = keys.last
        h = hash[keys.first]
        keys[1...-1].each{|k| h = h[k]}
        h[last] = value
      else
        raise "error setting hash: keys = #{keys}, value = #{value}"
      end
      hash
    end

    def get_nested(hash, keys)
      begin
        keys.inject(hash, :fetch)
      rescue KeyError, NoMethodError
        raise KeyError
      end
    end

    def has_keys?(hash, keys)
      begin
        get_nested(hash, keys)
        true
      rescue KeyError
        false
      end
    end

    def process_data_types
      @cli_conf.each do |cli|
        if  has_keys?(@options, cli[KEYS])
          case cli[TYPE_KEY]
          when FILE_CONTENTS_TYPE
            File.open(get_nested(@options, cli[KEYS]),"r") do |f|
              set_nested(@options, cli[KEYS], f.read())
            end
          when FLOAT_TYPE
            set_nested(@options, cli[KEYS], get_nested(@options, cli[KEYS]).to_f)
          end
        end
      end
    end
  end

  def ingest_yaml_conf(conf_file)
    conf = nil
    File.open(conf_file,"r") do |f|
      conf = YAML.load(f.read())
    end
  end

  def validate_keys
    hash_keys = @raw.keys
    REQUIRED_KEYS.each do |k|
      raise "config file syntax error" unless hash_keys.include?(k)
    end
  end

  def process_raw_conf
    conf = {}
    validate_keys
    conf.merge!(@raw[DEFAULTS])
    conf.deep_merge!(parse_command_line_options)
    check_for_nils(conf)
  end

  def parse_command_line_options
    @opt_parser = CommandLineOptions.new(@raw[CLI])
    @opt_parser.options
  end

  def check_for_nils(hash)
    hash.keys.each do |k|
      check_for_nils(hash[k]) if hash[k].kind_of?(Hash)
      if !hash[k]
        warn "required variable not set: #{k}" if !hash[k]
        warn @opt_parser.parser
        exit 1
      end
    end
    hash
  end
end

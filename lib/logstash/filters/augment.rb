# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "csv"

# This filter will allow you to augment events in logstash from
# an external file source
class LogStash::Filters::Augment < LogStash::Filters::Base
  # filter {
  #   augment {
  #     field => "status"
  #     dictionary => {
  #         "200" => {
  #           "color" => "green"
  #           "message" => "OK"
  #         }
  #         "404" => {
  #           "color" => "red"
  #           "message" => "Missing"
  #         }
  #       }
  #       augment_default => {
  #         "color" => "orange"
  #         "message" => "not found"
  #       }
  #   }
  # }
  config_name "augment"

  # the field to look up in the dictionary
  config :field, :validate => :string, :required => true
  # dictionary_path specifies the file to load from.  This can be a .csv, yaml,
  # or json file
  config :dictionary_path, :validate => :string
  # specifies the file type (json/yaml/csv/auto are valid values)
  config :dictionary_type, :validate => ['auto', 'csv', 'json', 'yaml', 'yml'], :default=>'auto'
  # if specified this should be a hash of objects like this:
  # [source,ruby]
  # ----------------
  # dictionary => {
  #     "200" => {
  #       "color" => "green"
  #       "message" => "OK"
  #     }
  #     "404" => {
  #       "color" => "red"
  #       "message" => "Missing"
  #     }
  #   }
  # ----------------
  config :dictionary, :validate => :hash
  # csv_header is columns of the csv file.
  config :csv_header, :validate => :array
  # csv_first_line indicates what to do with the first line of the file
  #  - 'ignore' skips it (csv_header must be set)
  #  - 'header' reads it and populates csv_header with it (csv_header must not be set)
  #  - 'data' reads it as data (csv_header must be set)
  #  - 'auto' treats the first line as data if csv_header is set or header if csv_data isn't set
  config :csv_first_line, :validate => ["data","header","ignore","auto"], :default=>"auto"
  # the csv_key determines which field of the csv file is the dictionary key
  # if this is not set, it will default to first column of the csv file
  config :csv_key, :validate => :string
  # if csv_remove_key is set, it will remove that key from the csv fields for augmenting
  # for example, say you have 200,green,ok as a line in the csv file where
  # the fields are status,color,message and your csv_key is set to status.  If csv_remove_key
  # is false then the event will have a status=200.  If csv_remove_key is true, then the event won't have
  # a status unless it already existed in the event.
  config :csv_remove_key, :validate => :boolean, :default => true
  # if the json file provided is an array, this specifies which field of the
  # array of objects is the key value
  config :json_key, :validate => :string
  # if json_remove_key is set and your json file is an array, it will remove the
  # key field from object similar to csv_remove_key
  config :json_remove_key, :validate => :boolean, :default => true
  # augment_fields is the he list of fields of the dictionary's value to augment
  # on to the event.  If this is not set, then all set fields of the dictionary
  # object are set on the event
  config :augment_fields, :validate => :array
  # if augment_target is set, the augmented fields will be added to this event
  # field instead of the root event.
  config :augment_target, :validate => :string, :default=>""
  # augment_default will be used if the key is not found
  # for example:
  # [source,ruby]
  # ----------------
  #   augment_default => {
  #     status => 'unknown'
  #     color => 'orange'
  #   }
  # ----------------
  config :augment_default, :validate => :hash
  # refresh_interval specifies minimum time between file refreshes in seconds
  # this plugin looks at the modification time of the file and only reloads if that changes
  config :refresh_interval, :validate => :number, :default=>60
  # ignore_fields are the fields of the dictionary value that you want to ignore
  config :ignore_fields, :validate => :array
  # only_fields are the only fields of the dictionary value that you want to use
  config :only_fields, :validate => :array


  public
  def register
    @fileModifiedTime = Hash.new
    rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
    @read_lock = rw_lock.readLock
    @write_lock = rw_lock.writeLock
    if !@dictionary
      @dictionary = Hash.new
    end
    @dictionaries = @dictionary_path.nil? ? nil : (@dictionary_path.is_a?(Array) ? @dictionary_path : [ @dictionary_path ])

    if @dictionary_path && !@dictionary.empty?
      raise LogStash::ConfigurationError, I18n.t(
        "logstash.agent.configuration.invalid_plugin_register",
          :plugin => "augment",
          :type => "filter",
          :error => "The configuration options 'dictionary' and 'dictionary_path' are mutually exclusive"
      )
    end

    if @csv_ignore_first_line && !@csv_header
      raise LogStash::ConfigurationError, I18n.t(
        "logstash.agent.configuration.invalid_plugin_register",
          :plugin => "augment",
          :type => "filter",
          :error => "The parameter csv_header is required if csv_ignore_first_line = true"
      )
    end

    load_or_refresh_dictionaries(true)

    @exclude_keys = Hash.new
    if @ignore_fields
      @ignore_fields.each { |k| @exclude_keys[k]=true }
    end

    # validate the dictionary is in the right format
    if @dictionary
      newdic = Hash.new
      @dictionary.each do |key,val|
        if val.is_a?(Array)
          newdic[key] = Hash[*val]
        elsif val.is_a?(Hash)
          newdic[key] = val
        else
          raise LogStash::ConfigurationError, I18n.t(
            "logstash.agent.configuration.invalid_plugin_register",
              :plugin => "augment",
              :type => "filter",
              :error => "The dictionary must be a hash of string to dictionary.  "+key+" is neither a "+val.class.to_s
          )
        end
      end
      @dictionary = newdic
    end

    @logger.debug? and @logger.debug("#{self.class.name}: Dictionary - ", :dictionary => @dictionary)
  end # def register

  def lock_for_read
    @read_lock.lock
    begin
      yield
    ensure

    end
  end

  def lock_for_write
    @write_lock.lock
    begin
      yield
    ensure
      @write_lock.unlock
    end
  end

  public
  def filter(event)
    load_or_refresh_dictionaries(false)

    return unless event.include?(@field) # Skip translation in case event does not have @event field.

    begin
      #If source field is array use first value and make sure source value is string
      source = event.get(@field).is_a?(Array) ? event.get(@field).first.to_s : event.get(@field).to_s
      row = lock_for_read { @dictionary[source] }
      if !row
        row = @augment_default
      end
      return unless row # nothing to do if there's nothing to add

      if @only_fields
        only_fields.each { |k| event.set(@augment_target+"["+k+"]",row[v]) if row[v] }
      else
        row.each { |k,v| event.set(@augment_target+"["+k+"]",v) unless @exclude_keys[k] }
      end
      filter_matched(event)
    rescue Exception => e
      @logger.error("Something went wrong when attempting to augment from dictionary", :exception => e, :field => @field, :event => event)
    end
  end # def filter


private
  def load_dictionary(filename, raise_exception=false)
    if !File.exists?(@dictionary_path)
      if raise_exception
        raise "Dictionary #{filename} does not exist"
      else
        @logger.warn("Dictionary #{filename} does not exist")
        return
      end
    end
    if @dictionary_type == 'yaml' || @dictionary_type == 'yml' || (@dictionary_type == 'auto' && /.y[a]?ml$/.match(filename))
      load_yaml(filename,raise_exception)
    elsif @dictionary_type == 'json' || (@dictionary_type == 'auto' && filename.end_with?(".json"))
      load_json(filename,raise_exception)
    elsif @dictionary_type == 'csv' || (@dictionary_type == 'auto' && filename.end_with?(".csv"))
      load_csv(filename,raise_exception)
    else
      raise "#{self.class.name}: Dictionary #{filename} format not recognized from filename or dictionary_type"
    end
  rescue => e
    loading_exception(e, raise_exception)
  end

  def load_yaml(filename, raise_exception=false)
    merge_dictionary!(YAML.load_file(@dictionary_path))
  end

  def load_json(filename, raise_exception=false)
    json = JSON.parse(File.read(filename))
    if json.is_a?(Array)
      if !@json_key
        raise LogStash::ConfigurationError, I18n.t(
          "logstash.agent.configuration.invalid_plugin_register",
          :plugin => "augment",
          :type => "filter",
          :error => "The #{@dictionary_path} file is an array, but json_key is not set"
        )
      end
      newjson = Hash.new
      json.each do |v|
        newjson[v[@json_key].to_s] = v
        if @json_remove_key
          v.delete(@json_key)
        end
      end
      json = newjson
    end

    # remove any values that aren't hashes
    json.delete_if do |k,v|
      if !v.is_a?(Hash)
        @logger.info("dictionary key #{k} is not a Hash its a "+v.class.to_s)
        true
      end
    end
    merge_dictionary!(json)
  end

  def load_csv(filename, raise_exception=false)
    if raise_exception
      if @csv_first_line == 'auto'
        if @csv_header
          @csv_first_line = 'data'
        else
          @csv_first_line = 'header'
        end
      end
      if @csv_first_line == 'header' && @csv_header
        raise LogStash::ConfigurationError, I18n.t(
          "logstash.agent.configuration.invalid_plugin_register",
            :plugin => "augment",
            :type => "filter",
            :error => "The csv_first_line is set to 'header' but csv_header is set"
        )
      end
      if @csv_first_line == 'ignore' && !csv_header
        raise LogStash::ConfigurationError, I18n.t(
          "logstash.agent.configuration.invalid_plugin_register",
            :plugin => "augment",
            :type => "filter",
            :error => "The csv_first_line is set to 'ignore' but csv_header is not set"
        )
      end
    end
    csv_lines = CSV.read(filename);
    if @csv_first_line == 'header'
      @csv_header = csv_lines.shift
    elsif @csv_first_line == 'ignore'
      csv_lines.shift
    end
    if @csv_key.nil?
      @csv_key = @csv_header[0];
    end
    data = Hash.new
    csv_lines.each do |line|
      o = Hash.new
      line.zip(@csv_header).each do |value, header|
        o[header] = value
      end
      key = o[csv_key]
      if @csv_remove_key
        o.delete(csv_key)
      end
      data[key] = o
    end
    merge_dictionary!(data)
  end

  def merge_dictionary!(data)
    @dictionary.merge!(data)
  end

  def loading_exception(e, raise_exception=false)
    msg = "#{self.class.name}: #{e.message} when loading dictionary file"
    if raise_exception
      raise RuntimeError.new(msg)
    else
      @logger.warn("#{msg}, continuing with old dictionary")
    end
  end

  def refresh_dictionary(filename, raise_exception)
    mtime = File.mtime(filename)
    if ! @dictionary_mtime[filename] && @dictionary_mtime[filename] != mtime
      @dictionary_mtime[filename] = mtime
      @logger.info("file #{filename} has been modified, reloading")
      load_dictionary(filename, raise_exception)
    end
  end

  def load_or_refresh_dictionaries(raise_exception=false)
    if ! @dictionaries
      return
    end
    if (@next_refresh && @next_refresh + @refresh_interval < Time.now)
      return
    end
    lock_for_write do
      if ! @dictionary_mtime
        @dictionary_mtime = Hash.new
      end
      if (@next_refresh && @next_refresh + @refresh_interval < Time.now)
        return
      end
      @logger.info("checking for modified dictionary files")
      @dictionaries.each { |filename| refresh_dictionary(filename,raise_exception) }
      @next_refresh = Time.now + @refresh_interval
    end
  end
end # class LogStash::Filters::Augment

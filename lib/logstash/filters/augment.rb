# encoding: utf-8
require "logstash/filters/base"
require "logstash/namespace"
require "json"
require "csv"

# This filter will allow you to augment events in logstash from
# an external file source
class LogStash::Filters::Augment < LogStash::Filters::Base
  # Setting the config_name here is required. This is how you
  # configure this filter from your Logstash config.
  #
  # filter {
  #    {
  #     message => "My message..."
  #   }
  # }
  #
  config_name "augment"

  # the field to look up in the dictionary
  config :field, :validate => :string, :required => true
  # dictionary_path specifies the file to load from.  This can be a .csv, yaml,
  # or json file
  config :dictionary_path, :validate => :string
  # specifies the file type (json/yaml/csv/auto are valid values)
  config :dictionary_type, :validate => ['auto', 'csv', 'json', 'yaml', 'yml'], :default=>'auto'
  # if specified this should be a hash of objects like this:
  # dictionary => {
  #  200 => {
  #    status => 'ok'
  #    color => 'green'
  #  }
  #  404 => {
  #    status => 'not found'
  #    color => 'green'
  #  }
  # }
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
  # augment_fields is the he list of fields of the dictionary's value to augment
  # on to the event.  If this is not set, then all set fields of the dictionary
  # object are set on the event
  config :augment_fields, :validate => :array
  # if augment_target is set, the augmented fields will be added to this event
  # field instead of the root event.
  config :augment_target, :validate => :string, :default=>""
  # augment_default will be used if the key is not found
  # for example:
  #   augment_default => {
  #     status => 'unknown'
  #     color => 'orange'
  #   }
  config :augment_default, :validate => :hash
  # refresh_interval specifies minimum time between file refreshes in seconds
  config :refresh_interval, :validate => :number, :default=>300

  public
  def register
    rw_lock = java.util.concurrent.locks.ReentrantReadWriteLock.new
    @read_lock = rw_lock.readLock
    @write_lock = rw_lock.writeLock
    if !@dictionary
      @dictionary = Hash.new
    end

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

    if @dictionary_path
      @next_refresh = Time.now + @refresh_interval
      raise_exception = true
     lock_for_write { load_dictionary(raise_exception) }
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
    if @dictionary_path
      if needs_refresh?
        lock_for_write do
          if needs_refresh?
            load_dictionary
            @next_refresh = Time.now + @refresh_interval
            @logger.info("refreshing dictionary file")
          end
        end
      end
    end

    return unless event.include?(@field) # Skip translation in case event does not have @event field.

    begin
      #If source field is array use first value and make sure source value is string
      source = event.get(@field).is_a?(Array) ? event.get(@field).first.to_s : event.get(@field).to_s
      row = lock_for_read { @dictionary[source] }
      if !row
        row = @augment_default
      end
      return unless row # nothing to do if there's nothing to add

      row.each do |k,v|
        event.set(@augment_target+"["+k+"]",v)
      end
      filter_matched(event)
    rescue Exception => e
      @logger.error("Something went wrong when attempting to augment from dictionary", :exception => e, :field => @field, :event => event)
    end
  end # def filter


private
  def load_dictionary(raise_exception=false)
    if @dictionary_type == 'yaml' || @dictionary_type == 'yml' || (@dictionary_type == 'auto' && /.y[a]?ml$/.match(@dictionary_path))
      @dictionary_type = 'yaml'
      load_yaml(raise_exception)
    elsif @dictionary_type == 'json' || (@dictionary_type == 'auto' && @dictionary_path.end_with?(".json"))
      @dictionary_type = 'json'
      load_json(raise_exception)
    elsif @dictionary_type == 'csv' || (@dictionary_type == 'auto' && @dictionary_path.end_with?(".csv"))
      @dictionary_type = 'csv'
      load_csv(raise_exception)
    else
      raise "#{self.class.name}: Dictionary #{@dictionary_path} have a non valid format"
    end
    if raise_exception && !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
  rescue => e
    loading_exception(e, raise_exception)
  end

  def load_yaml(raise_exception=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    merge_dictionary!(YAML.load_file(@dictionary_path), raise_exception)
  end

  def load_json(raise_exception=false)
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    merge_dictionary!(JSON.parse(File.read(@dictionary_path)), raise_exception)
  end

  def load_csv(raise_exception=false)
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
    if !File.exists?(@dictionary_path)
      @logger.warn("dictionary file read failure, continuing with old dictionary", :path => @dictionary_path)
      return
    end
    csv_lines = CSV.read(@dictionary_path);
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
    merge_dictionary!(data, raise_exception)
  end

  def merge_dictionary!(data, raise_exception=false)
    @dictionary.merge!(data)
  end

  def loading_exception(e, raise_exception=false)
    msg = "#{self.class.name}: #{e.message} when loading dictionary file at #{@dictionary_path}"
    if raise_exception
      raise RuntimeError.new(msg)
    else
      @logger.warn("#{msg}, continuing with old dictionary", :dictionary_path => @dictionary_path)
    end
  end

  def needs_refresh?
    @next_refresh < Time.now
  end

end # class LogStash::Filters::Augment

# Logstash Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

It can be used to augment events in logstash from config, CSV file, JSON file, or yaml files.  This differs from the translate plugin in that it can add multiple fields to the event based on one lookup.  For example say you have a geocode file that maps store numbers to coordinates.  Using this plugin you can add a location.latitude and location.longitude to your event based on a simple lookup.

## Documentation

The logstash-filter-augment plugin can be configured statically like this:
```ruby
filter {
  augment {
    field => "status"
    dictionary => {
        "200" => {
          "color" => "green"
          "message" => "OK"
        }
        "404" => {
          "color" => "red"
          "message" => "Missing"
        }
      }
      augment_default => {
        "color" => "orange"
        "message" => "not found"
      }
  }
}
```
And then when an event with status=200 in, it will add color=green and message=OK to the event

Additionally you use a CSV, YAML, or JSON file to define the mapping.

## Developing

### 1. Plugin Developement and Testing

#### Code
- To get started, you'll need JRuby with the Bundler gem installed.

- Install dependencies
```sh
bundle install
```

#### Test

- Update your dependencies

```sh
bundle install
```

- Run tests

```sh
bundle exec rspec
```

### 2. Running your unpublished Plugin in Logstash

#### 2.1 Run in a local Logstash clone

- Edit Logstash `Gemfile` and add the local plugin path, for example:
```ruby
gem "logstash-filter-augment", :path => "/your/local/logstash-filter-augment"
```
- Install plugin
```sh
bin/logstash-plugin install --no-verify
```
- Run Logstash with your plugin
```sh
bin/logstash -e 'filter {augment {}}'
```
At this point any modifications to the plugin code will be applied to this local Logstash setup. After modifying the plugin, simply rerun Logstash.

#### 2.2 Run in an installed Logstash

You can use the same **2.1** method to run your plugin in an installed Logstash by editing its `Gemfile` and pointing the `:path` to your local plugin development directory or you can build the gem and install it using:

- Build your plugin gem
```sh
gem build logstash-filter-augment.gemspec
```
- Install the plugin from the Logstash home
```sh
bin/logstash-plugin install /your/local/plugin/logstash-filter-augment.gem
```
- Start Logstash and proceed to test the plugin

## Contributing

All contributions are welcome: ideas, patches, documentation, bug reports, complaints, and even something you drew up on a napkin.

Programming is not a required skill. Whatever you've seen about open source and maintainers or community members  saying "send patches or die" - you will not see that here.

It is more important to the community that you are able to contribute.

For more information about contributing, see the [CONTRIBUTING](https://github.com/elastic/logstash/blob/master/CONTRIBUTING.md) file.

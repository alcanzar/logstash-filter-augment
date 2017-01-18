# logstash-filter-augment Plugin

This is a plugin for [Logstash](https://github.com/elastic/logstash).

It is fully free and fully open source. The license is Apache 2.0, meaning you are pretty much free to use it however you want in whatever way.

It can be used to augment events in logstash from config, CSV file, JSON file, or yaml files.  This differs from the translate plugin in that it can add multiple fields to the event based on one lookup.  For example say you have a geocode file that maps store numbers to coordinates.  Using this plugin you can add a location.latitude and location.longitude to your event based on a simple lookup.

## Documentation

logstash-filter-augment is a logstash plugin for augmenting events with data from a config file or exteral file (in CSV, JSON, or YAML format).  The filter takes a `field` parameter that specifies what is being looked up.  Based on configuration, it will find the object that is referred to and add the fields of that object to your event.

In the case of a CSV file, you'll want to specify the `csv_key` to tell it which field of the file is the key (it'll default to the first column in the CSV if you don't specify).  If your CSV file doesn't contain a header row, you'll need to set the `csv_header` to be an array of the column names.  If you do have a header, you can still specify the `csv_header`, but be sure to also specify that you want to `csv_first_line => ignore`.

In the case of JSON, you can provide a simple dictionary that maps the keys to the objects:
```json
{
  "200": { "color": "green", "message": "ok" }
}
```
or in Array format:
```json
[
{"code": 200, "color": "green", "message": "ok"}
]
```
but then you'll have to provide a `json_key => "code"` parameter in your config file to let it know which field you want to use for lookups.

YAML works the same as JSON -- you can specify either a dictionary or an array:
```yaml
200:
  color: green
  message: ok
404:
  color: red
  message: not found
```
or
```yaml
- code: 200
  color: green
  message: ok
- code: 404
  color: red
  message: not found
```
but again, you'll need to specify the `yaml_key => "code"`

Finally you can configure logstash-filter-augment statically with a dictionary:
```ruby
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
      default => {
        "color" => "orange"
        "message" => "not found"
      }
  }
```
If you choose this route, be careful that you quote your keys or you could end up with weird logstash errors.
### config parameters
| parameter | required (default)| Description  |
| --------- |:---:| ---|
| field | Yes | the field of the event to look up in the dictionary |
| dictionary_path | Yes if `dictionary` isn't provided | The list of files to load |
| dictionary_type | No (auto) | The type of files provided on dictionary_path.  Allowed values are `auto`, `csv`, `json`, `yaml`, and `yml` |
| dictionary | Yes if `dictionary_path` isn't provided | A dictionary to use.  See example above |
| csv_header | No | The header fields of the csv_file |
| csv_first_line | No (auto) | indicates what to do with the first line of the file.  Valid values are `ignore`, `header`, `data`, and `auto`.  `auto` treats the first line as data if csv_header is set or `header` if it isn't |
| csv_key | No | On CSV files, which field name is the key.  Defaults to the first column of the file if not set |
| csv_remove_key | No(true) | Remove the key from the object.  You might want to set this to false if you don't have a `default` set so that you know which records were matched |
| json_key | Yes, if array | The field of the json objects to use as a key for the dictionary |
| json_remove_key | No | Similar to csv_remove_key |
| yaml_key | Yes, if array | The field of the YAML objects to use as a key for the dictionary |
| yaml_remove_key | No | Similar to csv_remove_key |
| augment_fields | No (all fields) | The fields to copy from the object to the target.  If this is specified, only these fields will be copied. |
| ignore_fields | No | If this list is specified and `augment_fields` isn't, then these fields will not be copied |
| default | No | A dictionary of fields to add to the target if the key isn't in the data |
| target | No ("") | Where to target the fields.  If this is left as the default "", it targets the event itself.  Otherwise you can specify a valid event selector.  For example, [user][location] Would set user.location.{fields from object} |
| refresh_interval | No (60) | The number of seconds between checking to see if the file has been modified. Set to -1 to disable checking, set to 0 to check on every event (not recommended)|

## Use Cases
### Geocoding by key
If you have a field that can be used to lookup a location and you have a location file, you could configure this way:
```ruby
   augment {
      field => "store"
      target => "[location]"
      dictionary_path => "geocode.csv"
      csv_header => ["id","lat","lon"]
      csv_key => "id"
      csv_first_line => "data"
   }
```
and then be sure that your mapping / mapping template changes "location" into a geo_point
### Attach multiple pieces of user data based on user key
```ruby
  augment {
    field => "username"
    dictionary_path => ["users1.csv", "users2.csv"]
    csv_header => ["username","fullName","address1","address2","city","state","zipcode"]
    csv_key => "id"
    csv_first_line => "ignore"
  }
```
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

Gem::Specification.new do |s|
  s.name          = 'logstash-filter-augment'
  s.version       = '0.2.0'
  s.licenses      = ['Apache License (2.0)']
  s.summary       = 'A logstash plugin to augment your events from data in files'
  s.description   = 'A logstash plugin that can merge data from CSV, YAML, and JSON files with events.'
  s.homepage      = 'https://github.com/alcanzar/logstash-filter-augment/'
  s.authors       = ['Adam Caldwell']
  s.email         = 'alcanzar@gmail.com'
  s.require_paths = ['lib']

  # Files
  s.files = Dir['lib/**/*','spec/**/*','vendor/**/*','*.gemspec','*.md','CONTRIBUTORS','Gemfile','LICENSE','NOTICE.TXT']
   # Tests
  s.test_files = s.files.grep(%r{^(test|spec|features)/})

  # Special flag to let us know this is actually a logstash plugin
  s.metadata = { "logstash_plugin" => "true", "logstash_group" => "filter" }

  # Gem dependencies
  s.add_runtime_dependency "logstash-core-plugin-api", "~> 2.0"
  s.add_development_dependency 'logstash-devutils'
end

# Rack::Session::Memcached [![Build Status](https://travis-ci.org/send/rack-session-memcached.svg?branch=master)](https://travis-ci.org/send/rack-session-memcached)

Rack::Session::Memcached provides cookie based session.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'rack-session-memcached'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install rack-session-memcached

## Usage

### Sinatra

```ruby
use Rack::Session::Memcached,
  memcache_server: 'localhost:11211',
  namespace: 'rack:session',
  key: 'rack.session'
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `rack-session-memcached.gemspec`, and then run `bundle exec rake release` to create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

1. Fork it ( https://github.com/send/rack-session-memcached/fork )
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

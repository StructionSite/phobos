![Circle CI](https://circleci.com/gh/klarna/phobos.svg?style=shield&circle-token=2289e0fe5bd934074597b32e7f8f0bc98ea0e3c7)

# Phobos

Simplifying Kafka for ruby apps.

Phobos is a microframework and library for Kafka based applications. It wraps common behaviors needed by consumers and producers in an easy and convenient API.

It uses [ruby-kafka](https://github.com/zendesk/ruby-kafka) as it's Kafka client and core component.

## Table of Contents

1. [Installation](#installation)
1. [Usage](#usage)
  1. [Standalone apps](#usage-standalone-apps)
  1. [Consuming messages from Kafka](#usage-consuming-messages-from-kafka)
  1. [Producing messages to Kafka](#usage-producing-messages-to-kafka)
  1. [Programmatically](#usage-programmatically)
  1. [Configuration file](#usage-configuration-file)
  1. [Instrumentation](#usage-instrumentation)
1. [Development](#development)

## <a name="installation"></a> Installation

Add this line to your application's Gemfile:

```ruby
gem 'phobos'
```

And then execute:

```sh
$ bundle
```

Or install it yourself as:

```sh
$ gem install phobos
```

## <a name="usage"></a> Usage

Phobos can be used to power standalone ruby applications by bringing Kafka features to your project - including Rails apps. It also comes with a CLI to help loading your code and running it as a daemon or service.

### <a name="usage-standalone-apps"></a> Standalone apps

Standalone apps have benefits such as individual deploys and smaller code bases. If consuming from Kafka is your version of micro services, Phobos can be of great help.

### Setup

To create an application with Phobos you need two things:
  * A configuration file (more details in the [Configuration file](#usage-configuration-file) section)
  * A `phobos_boot.rb` (or the name of your choice) to properly load your code into Phobos executor

Use the Phobos CLI commands __init__ and __start__ to bootstrap your application. Example:

```sh
# call this command inside your app folder
$ phobos init
    create  config/phobos.yml
    create  phobos_boot.rb
```

`phobos.yml` is the configuration file and `phobos_boot.rb` is the place to load your code.

### Consumers (listeners and handlers)

In Phobos apps __listeners__ are configured against Kafka - they are our consumers. A listener requires a __handler__ (a ruby class where you should process incoming messages), a __topic__, and a __group_id__. Consumer groups are used to coordinate the listeners across machines. We write the __handlers__ and Phobos makes sure to run them for us. An example of a handler is:

```ruby
class MyHandler
  include Phobos::Handler

  def consume(payload, metadata)
    # payload  - This is the content of your Kafka message, Phobos does not attempt to
    #            parse this content, it is delivered raw to you
    # metadata - A hash with useful information about this event, it contains: The event key,
    #            partition number, offset, retry_count, topic, group_id, and listener_id
  end
end
```

Writing a handler is all you need to allow Phobos to work - it will take care of execution, retries and concurrency.

To start Phobos the __start__ command is used, example:

```sh
$ phobos start
[2016-08-13T17:29:59:218+0200Z] INFO  -- Phobos : <Hash> {:message=>"Phobos configured", :env=>"development"}
______ _           _
| ___ \ |         | |
| |_/ / |__   ___ | |__   ___  ___
|  __/| '_ \ / _ \| '_ \ / _ \/ __|
| |   | | | | (_) | |_) | (_) \__ \
\_|   |_| |_|\___/|_.__/ \___/|___/

phobos_boot.rb - find this file at ~/Projects/example/phobos_boot.rb

[2016-08-13T17:29:59:272+0200Z] INFO  -- Phobos : <Hash> {:message=>"Listener started", :listener_id=>"6d5d2c", :group_id=>"test-1", :topic=>"test"}
```

By default, the __start__ command will look for the configuration file at `config/phobos.yml` and it will load the file `phobos_boot.rb` if it exists. In the example above all example files generated by the __init__ command are used as is. It is possible to change both files, use `-c` for the configuration file and `-b` for the boot file. Example:

```sh
$ phobos start -c /var/configs/my.yml -b /opt/apps/boot.rb
```

### <a name="usage-consuming-messages-from-kafka"></a> Consuming messages from Kafka

Messages from Kafka are consumed using __handlers__. You can use Phobos __executors__ or use it [programmatically](#usage-programmatically), but __handlers__ will always be used. To create a handler class, simply include the module `Phobos::Handler`. This module allows Phobos to manage the life cycle of your handler.

A handler must implement the method `#consume(payload, metadata)`.

Instances of your handler will be created for every message, so keep a constructor without arguments. If `consume` raises an exception, Phobos will retry the message indefinitely, applying the back off configuration presented in the configuration file. The `metadata` hash will contain a key called `retry_count` with the current number of retries for this message. To skip a message, simply return from `#consume`.

When the listener starts, the class method `.start` will be called with the `kafka_client` used by the listener. Use this hook as a chance to setup necessary code for your handler. The class method `.stop` will be called during listener shutdown.

```ruby
class MyHandler
  include Phobos::Handler

  def self.start(kafka_client)
    # setup handler
  end

  def self.stop
    # teardown
  end

  def consume(payload, metadata)
    # consume or skip message
  end
end
```

It is also possible to control the execution of `#consume` with the class method `.around_consume(payload, metadata)`. This method receives the payload and metadata, and then invokes `#consume` method by means of a block; example:

```ruby
class MyHandler
  include Phobos::Handler

  def self.around_consume(payload, metadata)
    Phobos.logger.info "consuming..."
    output = yield
    Phobos.logger.info "done, output: #{output}"
  end

  def consume(payload, metadata)
    # consume or skip message
  end
end
```

Take a look at the examples folder for some ideas.

The hander life cycle can be illustrated as:

  `.start` -> `#consume` -> `.stop`

or optionally,

  `.start` -> `.around_consume` [ `#consume` ] -> `.stop`

### <a name="usage-producing-messages-to-kafka"></a> Producing messages to Kafka

`ruby-kafka` provides several options for publishing messages, Phobos offers them through the module `Phobos::Producer`. It is possible to turn any ruby class into a producer (including your handlers), just include the producer module, example:

```ruby
class MyProducer
  include Phobos::Producer
end
```

Phobos is designed for multi threading, thus the producer is always bound to the current thread. It is possible to publish messages from objects and classes, pick the option that suits your code better.
The producer module doesn't pollute your classes with a thousand methods, it includes a single method the class and in the instance level: `producer`.

```ruby
my = MyProducer.new
my.producer.publish('topic', 'message-payload', 'partition and message key')

# The code above has the same effect of this code:
MyProducer.producer.publish('topic', 'message-payload', 'partition and message key')
```

It is also possible to publish several messages at once:

```ruby
MyProducer
  .producer
  .publish_list([
    { topic: 'A', payload: 'message-1', key: '1' },
    { topic: 'B', payload: 'message-2', key: '2' },
    { topic: 'B', payload: 'message-3', key: '3' }
  ])
```

There are two flavors of producers: __normal__ producers and __async__ producers.

Normal producers will deliver the messages synchronously and disconnect, it doesn't matter if you use `publish` or `publish_list` after the messages get delivered the producer will disconnect.

Async producers will accept your messages without blocking, use the methods `async_publish` and `async_publish_list` to use async producers.

__Important__: When using async producers you need to shutdown them manually before you close the application. Use the class method `async_producer_shutdown` to safely shutdown the producer.

An example of using handlers to publish messages:

```ruby
class MyHandler
  include Phobos::Handler
  include Phobos::Producer

  PUBLISH_TO = 'topic2'

  def self.stop
    producer.async_producer_shutdown
    producer.kafka_client.close
  end

  def consume(payload, metadata)
    producer.async_publish(PUBLISH_TO, {key: 'value'}.to_json)
  end
end
```

#### Note about configuring producers

Without configuring the Kafka client, the producers will create a new one when needed (once per thread).

If you want to use the same kafka client as the listeners, use the class method `configure_kafka_client`, example:

```ruby
class MyHandler
  include Phobos::Handler
  include Phobos::Producer

  def self.start(kafka_client)
    producer.configure_kafka_client(kafka_client)
  end

  def self.stop
    producer.async_producer_shutdown
  end

  def consume(payload, metadata)
    producer.async_publish(PUBLISH_TO, {key: 'value'}.to_json)
  end
end
```

Using the same client as the listener is a good idea because it will be managed by Phobos and properly closed when needed.

### <a name="usage-programmatically"></a> Programmatically

Besides the handler and the producer, you can use `Listener` and `Executor`.

First, call the method `configure` with the path of your configuration file

```ruby
Phobos.configure('config/phobos.yml')
```

__Listener__ connects to Kafka and acts as your consumer. To create a listener you need a handler class, a topic, and a group id.

```ruby
listener = Phobos::Listener.new(
  handler: Phobos::EchoHandler,
  group_id: 'group1',
  topic: 'test'
)

# start method blocks
Thread.new { listener.start }

listener.id # 6d5d2c (all listeners have an id)
listener.stop # stop doesn't block
```

This is all you need to consume from Kafka with back off retries.

An __executor__ is the supervisor of all listeners. It loads all listeners configured in `phobos.yml`. The executor keeps the listeners running and restarts them when needed.

```ruby
executor = Phobos::Executor.new

# start doesn't block
executor.start

# stop will block until all listers are properly stopped
executor.stop
```

When using Phobos __executors__ you don't care about how listeners are created, just provide the configuration under the `listeners` section in the configuration file and you are good to go.

### <a name="usage-configuration-file"></a> Configuration file

The configuration file is organized in 6 sections. Take a look at the example file, [config/phobos.yml.example](https://github.com/klarna/phobos/blob/master/config/phobos.yml.example).

__logger__ configures the logger for all Phobos components, it automatically outputs to `STDOUT` and it saves the log in the configured file

__kafka__ provides configurations for all `Kafka::Client` created over the application. All options presented are from `ruby-kafka`

__producer__ provides configurations for all producers created over the application, the options are the same for normal and async producers. All options presented are from `ruby-kafka`

__consumer__ provides configurations for all consumer groups created over the application. All options presented are from `ruby-kafka`

__backoff__ Phobos provides automatic retries for your handlers, if an exception is raised the listener will retry following the back off configured here

__listeners__ is the list of listeners configured, each listener represents a consumers group

### <a name="usage-instrumentation"></a> Instrumentation

Some operations are instrumented using [Active Support Notifications](http://api.rubyonrails.org/classes/ActiveSupport/Notifications.html).

In order to receive notifications you can use the module `Phobos::Instrumentation`, example:

```ruby
Phobos::Instrumentation.subscribe('listener.start') do |event|
  puts(event.payload)
end
```

`Phobos::Instrumentation` is a convenience module around `ActiveSupport::Notifications`, feel free to use it or not. All Phobos events are in the `phobos` namespace. `Phobos::Instrumentation` will always look at `phobos.` events.

#### Executor notifications
  * `executor.retry_listener_error` is sent when the listener crashes and the executor wait for a restart. It includes the following payload:
    * listener_id
    * retry_count
    * waiting_time
    * exception_class
    * exception_message
    * backtrace
  * `executor.stop` is sent when executor stops

#### Listener notifications
  * `listener.start_handler` is sent when invoking `handler.start(kafka_client)`. It includes the following payload:
    * listener_id
    * group_id
    * topic
  * `listener.start` is sent when listener starts. It includes the following payload:
    * listener_id
    * group_id
    * topic
  * `listener.process_batch` is sent after process a batch. It includes the following payload:
    * listener_id
    * group_id
    * topic
    * batch_size
    * partition
    * offset_lag
    * highwater_mark_offset
  * `listener.process_message` is sent after process a message. It includes the following payload:
    * listener_id
    * group_id
    * topic
    * key
    * partition
    * offset
    * retry_count
  * `listener.retry_handler_error` is sent after waited for `handler#consume` retry. It includes the following payload:
    * listener_id
    * group_id
    * topic
    * key
    * partition
    * offset
    * retry_count
    * waiting_time
    * exception_class
    * exception_message
    * backtrace
  * `listener.retry_aborted` is sent after waiting for a retry but the listener was stopped before the retry happened. It includes the following payload:
    * listener_id
    * group_id
    * topic
  * `listener.stopping` is sent when the listener receives signal to stop
    * listener_id
    * group_id
    * topic
  * `listener.stop_handler` is sent after stopping the handler
    * listener_id
    * group_id
    * topic
  * `listener.stop` is send after stopping the listener
    * listener_id
    * group_id
    * topic

## <a name="development"></a> Development

After checking out the repo:
* make sure docker is installed and running
* run `bin/setup` to install dependencies
* run `rake spec` to run the tests

You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

The `utils` folder contain some shell scripts to help with the local Kafka cluster. It uses docker to start Kafka and zookeeper.

```sh
sh utils/start-all.sh
sh utils/stop-all.sh
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/klarna/phobos.

## License

Copyright 2016 Klarna

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License.

You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

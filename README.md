# Rabbit (Rabbit Messaging) &middot;  [![Gem Version](https://badge.fury.io/rb/rabbit_messaging.svg)](https://badge.fury.io/rb/rabbit_messaging) [![Coverage Status](https://coveralls.io/repos/github/umbrellio/rabbit_messaging/badge.svg?branch=master)](https://coveralls.io/github/umbrellio/rabbit_messaging?branch=master)

Provides client and server support for RabbitMQ

## Installation

```ruby
gem "rabbit_messaging"
```

```shell
$ bundle install
# --- or ---
$ gem install "rabbit_messaging"
```

```ruby
require "rabbit_messaging"
```

## Usage

- [Configuration](#configuration)
- [Client](#client)
- [Server](#server)

---

### Configuration

- RabbitMQ connection configuration fetched from the `bunny_options` section
  of `/config/sneakers.yml`

- `Rabbit.config` provides setters for following options:

  - `group_id` (`Symbol`), *required*

    Shared identifier which used to select api. As usual, it should be same as default project_id
    (I.e. we have project 'support', which runs only one application in production.
    So on, it's group_id should be :support)

  - `project_id` (`Symbol`), *required*

    Personal identifier which used to select exact service.
    As usual, it should be same as default project_id with optional stage_id.
    (I.e. we have project 'support', in production it's project_id is :support,
    but in staging it uses :support1 and :support2 ids for corresponding stages)

  - `queue_suffix` (`String`)

    Optional suffix added to the read queue name. For example, in case of `group_id = "grp"`, `project_id = "prj"` and
    `queue_suffix = "sfx"`, Rabbit will read from queue named `"grp.prj.sfx"`.

  - `exception_notifier` (`Proc`)
    You must provide your own notifier like this to notify about exceptions:

    ```ruby
      config.exception_notifier = proc { |e| MyCoolNotifier.notify!(e) }
    ```

  - `hooks` (`Hash`)

    :before_fork and :after_fork hooks, used same way as in unicorn / puma / que / etc

  - `environment` (one of `:test`, `:development`, `:production`), *default:- `:production`

    Internal environment of gem.

    - `:test` environment stubs publishing and does not suppress errors
    - `:development` environment auto-creates queues and uses default exchange
    - `:production` environment enables handlers caching and gets maximum strictness

    By default gem skips publishing in test and development environments.
    If you want to change that then manually set `Rabbit.skip_publishing_in` with an array of environments.

    ```ruby
     Rabbit.skip_publishing_in = %i[test]
    ```

  - `receiving_job_class_callable` (`Proc`)

    Custom ActiveJob subclass to work with received messages. Receives the following attributes as `kwarg`-arguments:

    - `:arguments` - information about message type (`type`), application id (`app_id`), message id (`message_id`);
    - `:delivery_info` - information about `exchange`, `routing_key`, etc;
    - `:message` - received RabbitMQ message (often in a `string` format);

    ```ruby
    {
      message: '{"hello":"world","foo":"bar"}',
      delivery_info: { exchange: "some exchange", routing_key: "some_key" },
      arguments: {
        type: "some_successful_event",
        app_id: "some_group.some_app",
        message_id: "uuid",
      }
    }
    ```

  - `before_receiving_hooks, after_receiving_hooks` (`Array of Procs`)

    Before and after hooks with message processing in the middle. Where `before_receiving_hooks` and `after_receiving_hooks` are empty arrays by default.

    It's advised to NOT place procs with long execution time inside.

    Setup:

    ```ruby
      config.before_receiving_hooks.append(proc { |message, arguments| do_stuff_1 })
      config.before_receiving_hooks.append(proc { |message, arguments| do_stuff_2 })

      config.after_receiving_hooks.append(proc { |message, arguments| do_stuff_3 })
      config.after_receiving_hooks.append(proc { |message, arguments| do_stuff_4 })
    ```

  - `use_backoff_handler` (`Boolean`)

    If set to `true`, use `ExponentialBackoffHandler`. You will also need add the following line to your Gemfile:

    ```ruby
    gem "sneakers_handlers", github: "umbrellio/sneakers_handlers"
    ```

    See https://github.com/umbrellio/sneakers_handlers for more details.


  - `backoff_handler_max_retries` (`Integer`)

    Number of retries that `ExponentialBackoffHandler` will use before sending job to the error queue. 5 by default.

  - `connection_reset_exceptions` (`Array`)

    Exceptions for reset connection. Default:  [`Bunny::ConnectionClosedError`].

  ```ruby
    config.connection_reset_exceptions << MyInterestingException
  ```

  - `connection_reset_max_retries` (`Integer`)

    Maximum number of reconnection attempts after a connection loss. Default: 10.
  
    ```ruby
      config.connection_reset_max_retries = 20
    ```

  - `connection_reset_timeout` (`Float`)

    The timeout duration before attempting to reset the connection. Default: 0.2 sec.

    ```ruby
      config.connection_reset_timeout = 0.2
    ```

  - `logger_message_size_limit` (`Integer`)

    Maximum logger message size. Split message to parts if message is more than limit. Default: 9500.

    ```ruby
      config.logger_message_size_limit = 9500
    ```
---

### Client

```ruby
Rabbit.publish(
  routing_key: :support,
  event: :ping,
  data: { foo: :bar }, # default is {}
  exchange_name: 'fanout', # default is fine too
  confirm_select: true, # setting this to false grants you great speed up and absolutelly no guarantees
  headers: { "foo" => "bar" }, # custom arguments for routing, default is {}
  message_id: "asdadsadsad", # A unique identifier such as a UUID that your application can use to identify the message.
)
```

- This code sends messages via basic_publish with following parameters:

  - `routing_key`: `"support"`
  - `exchange`: `"group_id.project_id.fanout"` (default is `"group_id.poject_id"`)
  - `mandatory`: `true` (same as confirm_select)

    It is set to raise error if routing failed

  - `persistent`: `true`
  - `type`: `"ping"`
  - `content_type`: `"application/json"` (always)
  - `app_id`: `"group_id.project_id"`

- Messages are logged to `/log/rabbit.log`

---

### Server

- Server is supposed to run inside a daemon via the `daemons-rails` gem. Server is run with
`Rabbit::Daemon.run`. `before_fork` and `after_fork` procs in `Rabbit.config` are used
to teardown and setup external connections between daemon restarts, for example ORM connections

- After the server runs, received messages are handled by `Rabbit::EventHandler` subclasses in two possible ways:
  - a)  Subclasses are selected by following code(by default):
    ```ruby
    rabbit/handler/#{group_id}/#{event}".camelize.constantize
    ```
  - b) you can change default behaviour to your own logic by setting the `handler_resolver_callable` config option with a `Proc` that should return the handler class:
    ```ruby
    Rabbit.config.handler_resolver_callable = -> (group_id, event) { "recivers/#{group_id}/#{event}".camelize.constantize }
    ```

  If you wish so, you can override `initialize(message)`, where message is an object
  with simple api (@see lib/rabbit/receiving/message.rb)

  Handlers can specify a queue their messages will be put in via a `queue_as` class macro (accepts
  a string / symbol / block with `|message, arguments|` params)

- Received messages are logged to `/log/sneakers.log`, malformed messages are logged to
`/log/malformed_messages.log` and deleted from queue

---

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/umbrellio/rabbit_messaging.

## License

Released under MIT License

## Authors

Team Umbrellio

---

<a href="https://github.com/umbrellio/">
<img style="float: left;" src="https://umbrellio.github.io/Umbrellio/supported_by_umbrellio.svg"
alt="Supported by Umbrellio" width="439" height="72">
</a>

# Changelog
All notable changes to this project will be documented in this file.

## [1.7.0] - 2025-08-19
### Added
- Ability to specify a custom job class for publishing via `publishing_job_class_callable` config.
- Ability to specify a default queue for publishing jobs via `default_publishing_job_queue` config.
- Ability to specify a custom queue per publish call via `custom_queue_name` argument.

## [1.5.0] - 2025-05-19
### Added
- Added ability to split log message into parts
- Optional `logger_message_size_limit` config for message size limit

## [1.4.0] - 2025-03-10
### Added
- Introduced new configuration attributes for connection reset handling:
  - `connection_reset_max_retries`
  - `connection_reset_timeout`
  - `connection_reset_exceptions`
### Changed
- Improved handling of `Bunny::ConnectionClosedError`:
  - Added automatic reconnection with retries.
  - Implemented configurable timeouts between retries.

## [1.2.0] - 2025-02-10
### Added
- Add `ExponentialBackoffHandler` for handling errors in rabbit messages
- Optional `queue_suffix` config for read queues

## [1.1.0] - 2024-12-06
### Added
- **Receiving**
  - Support for custom receiving job config which is placed in receiving event handler;

## [1.0.0] - 2024-10-23
### Changed
- Remove `sneakers` gem in favour of [kicks](https://github.com/ruby-amqp/kicks)

## [0.15.0] - 2024-06-05
### Added
- Support for custom reciving handler via `Rabbit.config.handler_resolver_callable` config;

## [0.14.0] - 2023-02-27
### Added
- Exception notifier is required

## [0.13.0] - 2021-12-23
### Added
- `Sleep 1` for handling receiving error to prevent queue overflow
- `["2.7", "3.0", "3.1", "3.2"]` are used for specs

## [0.12.1] - 2021-12-23
### Added
- `ExceptionNotifier` replaced with `Sentry`

## [0.12.0] - 2021-06-08
### Added
- `Gemfile.lock` added

### Fixed
- `unless Sneakers.logger` was never executed

## [0.11.0] - 2021-05-05
### Added
- `Rabbit.config.receiving_job_class_callable` now receives the full message context (with `message`, `delivery_info` and `arguments` (see the `Rabbit::Receiving::Receive`));

## [0.10.0] - 2021-03-05
### Added
- logging message headers

## [0.9.0] - 2020-11-18
### Added
- configurable publish skipping (previous iteration just skipped in development)

### Fixed
- fix for receiving (delivery_info and args to hashes)
- fix for requiring receiving job

## [0.8.1] - 2020-11-05
### Added
- channels pool for manage channels on Publisher connection
### Changed
- Publisher use channels pool for access to channel

## [0.8.0] - 2020-10-28
### Added
- class Rabbit::Recieving::Receive for message processing
- class Rabbit::Recieving::Queue for queue name determination when receiving
- message_id argument in published and received messages
- before and after hooks when processing message
- specs for new functionality
- arguments attribute in received message and handler (contain raw message arguments with exchange and routing_key from the delivery_info)

### Changed
- Rabbit::Receiving::Worker refactoring (message processing moved to a separate class)
- ruby version upped to 2.5
- rubocop ruby target version set to 2.5
- some fixes of updated rubocop and ruby warnings
- heavy refactoring of old specs for receiving

## [0.7.1] - 2020-06-09
### Changed
- (Partially Fixed) Support for pre-defined logger injection on Sneakers moudle;

## [0.7.0] - 2020-06-09
### Added
- Support for multiple customizable loggers;

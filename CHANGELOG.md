# Changelog
All notable changes to this project will be documented in this file.

## [0.8.0] - 2020-10-28
### Added
- arguments given to the handler now contain exchange and and routing_key from the delivery_info
- class Rabbit::Recieving::Receive for message processing
- class Rabbit::Recieving::Queue for queue name determination when receiving
- message_id argument in published and received messages
- before and after hooks when processing message

### Changed
- Rabbit::Receiving::Worker refactoring (message processing moved to a separate class)
- ruby version upped to 2.7
- rubocop ruby target version set to 2.7
- some fixes of updated rubocop and ruby warnings 

## [0.7.1] - 2020-06-09
### Changed
- (Partially Fixed) Support for pre-defined logger injection on Sneakers moudle;

## [0.7.0] - 2020-06-09
### Added
- Support for multiple customizable loggers;

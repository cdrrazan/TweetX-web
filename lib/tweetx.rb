# frozen_string_literal: true

# TweetX Main Module
# Entry point for the TweetX application
# Requires and initializes the CLI and Scheduler components

require 'thor'
require_relative 'tweetx/cli'
require_relative 'tweetx/scheduler'

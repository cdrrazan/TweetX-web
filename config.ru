# frozen_string_literal: true

# Rack configuration file for TweetX web application
# Required by Rack-based servers to run the Sinatra application

require './app'

# Run the Sinatra application
run Sinatra::Application

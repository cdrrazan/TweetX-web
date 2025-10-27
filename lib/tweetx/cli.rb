# frozen_string_literal: true

# TweetX CLI Module
# Command-line interface for TweetX using Thor
# Provides commands for tweeting, previewing, listing, and adding tweets

module Tweetx
  class CLI < Thor
    # Tweet command - posts a tweet based on current time and category
    desc 'tweet', 'Tweet based on current time and category'
    # Execute tweet posting
    # @return [void]
    def tweet
      Scheduler.new.run
    end

    # Preview command - shows what tweet would be posted next
    desc 'preview', 'Preview tweets based on current time and category'
    # @return [void]
    def preview
      Scheduler.new.preview
    end

    # List command - displays all unpublished tweets
    desc 'list', 'List unpublished tweets in all categories'
    # @return [void]
    def list
      Scheduler.new.list_tweets
    end

    # Add command - adds a new tweet to the collection
    # @param text [String] tweet content
    # @param category [String] tweet category
    desc 'add TEXT CATEGORY', 'Add a new tweet to the Category'
    # @return [void]
    def add(text, category)
      Scheduler.new.add_tweet(text, category)
    end

    # Archive command - lists all published tweets
    desc 'archive', 'List all published tweets'
    # @return [void]
    def archive
      Scheduler.new.list_published
    end
  end
end

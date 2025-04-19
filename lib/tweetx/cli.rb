# frozen_string_literal: true

module Tweetx
  class CLI < Thor
    desc 'tweet', 'Tweet based on current time and category'
    def tweet
      Scheduler.new.run
    end
    desc 'preview', 'Preview tweets based on current time and category'
    def preview
      Scheduler.new.preview
    end

    desc 'list', 'List unpublished tweets in all categories'
    def list
      Scheduler.new.list_tweets
    end

    desc 'add TEXT CATEGORY', 'Add a new tweet to the Category'
    def add(text, category)
      Scheduler.new.add_tweet(text, category)
    end

    desc 'archive', 'List all published tweets'
    def archive
      Scheduler.new.list_published
    end
  end
end

# frozen_string_literal: true

# TweetX Scheduler Module
# Handles tweet scheduling, posting, and management logic
# Interacts with Twitter/X API and CSV data files

require 'csv'
require 'dotenv/load'
require 'time'
require 'x'
require 'debug'
require 'tzinfo'

class Scheduler
  # Directory paths for data files
  ROOT_DIR = File.expand_path('../../', __dir__)
  DATA_DIR = File.join(ROOT_DIR, 'data')

  # CSV file paths
  TWEET_COLLECTION_FILE = File.join(DATA_DIR, 'tweet_collection.csv')
  TWEET_PUBLISHED_FILE = File.join(DATA_DIR, 'tweet_published.csv')

  # Initialize Scheduler with Twitter API client
  # Sets up X API client using environment variables
  def initialize
    @client = X::Client.new(
      api_key: ENV['X_API_KEY'],
      api_key_secret: ENV['X_API_KEY_SECRET'],
      access_token: ENV['X_ACCESS_TOKEN'],
      access_token_secret: ENV['X_ACCESS_TOKEN_SECRET']
    )
  end

  # Execute tweet posting workflow
  # Selects appropriate tweet, validates, and posts to Twitter
  # @param dry_run [Boolean] if true, only preview without posting
  # @return [void]
  def run(dry_run: false)
    if select_tweet.nil?
      puts '🚫 No text available to tweet.'
      return
    end

    category = select_tweet[0]
    tweet = select_tweet[1]

    formatted_tweet = format_tweet(tweet)
    unless valid_tweet?(formatted_tweet)
      puts "⚠️ Skipping invalid tweet (empty or >280 characters): #{formatted_tweet.inspect}"
      return
    end

    if dry_run
      puts "🤖 [DRY RUN] Would tweet:\n#{formatted_tweet}"
      return
    end

    begin
      # Main API call to tweet
      response = @client.post('tweets', { text: formatted_tweet }.to_json)

      if response.dig(:data, :id) || response.dig('data', 'id')
        obj_id = response.dig(:data, :id) || response.dig('data', 'id')
        puts "✅ Tweeted: #{tweet}"
        send_to_published(obj_id, category, tweet)
      else
        puts "❌ Failed to tweet: #{response.status} - #{response.body}"
      end
    rescue StandardError => e
      puts "❌ Failed to tweet: #{e.message}"
    end
  end

  # Validate tweet text
  # @param text [String] tweet text to validate
  # @return [Boolean] true if tweet is valid (not empty, ≤ 280 chars)
  def valid_tweet?(text)
    return false if text.nil? || text.strip.empty? || text.length > 280

    true
  end

  # Select a tweet to post based on current hour and category
  # @return [Array, nil] array containing [category, tweet] or nil if none available
  def select_tweet
    return nil unless File.exist?(TWEET_COLLECTION_FILE)

    all_tweets = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    published = published_tweets
    category = category_for_current_hour
    puts "🕒 Current hour: #{Time.now.hour} → Category: #{category || 'unspecified'}"

    # Only select tweets in the current category
    tweets_by_category = category ? all_tweets.select { |row| row['category'] == category } : []

    # Only use unpublished tweets in that category
    unpublished_tweets = tweets_by_category.reject { |row| published.include?(row['text']) }

    if unpublished_tweets.empty?
      puts "⚠️ No unpublished tweets available in category '#{category}'. Skipping tweet."
      return nil
    end

    unpublished = unpublished_tweets.sample
    [unpublished['category'], unpublished['tweet']]
  end

  # Get list of all published tweet texts
  # @return [Array] array of published tweet text strings
  def published_tweets
    return [] unless File.exist?(TWEET_PUBLISHED_FILE)

    CSV.read(TWEET_PUBLISHED_FILE, headers: true).map { |row| row['text'] }
  end

  # Save a tweeted item to published tweets CSV
  # @param id [String] tweet ID from Twitter API
  # @param category [String] tweet category
  # @param text [String] tweet content
  # @return [void]
  def send_to_published(id, category, text)
    CSV.open(TWEET_PUBLISHED_FILE, 'a+') do |csv|
      csv << %w[id category text timestamp] if csv.count.zero?
      timestamp = Time.now.utc.iso8601

      csv << [id, category, text, timestamp]
    end
  end

  # Preview the tweet that would be posted next
  # @return [void]
  def preview
    tweet_info = select_tweet

    if tweet_info.nil?
      puts "🚫 No tweet available to preview."
    else
      puts "🔍 Previewing tweet for category: #{tweet_info[0]}"
      puts "-" * 60
      puts format_tweet(tweet_info[1])
      puts "-" * 60
      puts "🕒 Time slot: #{my_timezone.strftime('%I:%M %p %Z')}"
    end
  end

  # Determine category for current hour based on time-based categories
  # Categories: 5-8: Motivation, 9-12: Devtip, 13-16: Branding, 17-20: BuiltWith, 21-23: Ebook
  # @return [String, nil] category name for current hour or nil
  def category_for_current_hour
    hour = my_timezone.hour

    case hour
    when 5..8 then 'Motivation'
    when 9..12 then 'Devtip'
    when 13..16 then 'Branding'
    when 17..20 then 'BuiltWith'
    when 21..23 then 'Ebook'
    end
  end

  # List all unpublished tweets
  # @return [void]
  def list_tweets
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    published = published_tweets
    unpublished = all.reject { |row| published.include?(row['text']) }

    if unpublished.empty?
      puts '📭 No unpublished tweets found.'
    else
      puts '📋 Unpublished tweets:'
      unpublished.each_with_index do |row, i|
        puts "#{i + 1}. [#{row['category']}] #{row['text']}"
      end
    end
  end

  # List all published tweets
  # @return [void]
  def list_published
    if File.exist?(TWEET_PUBLISHED_FILE)
      published = CSV.read(TWEET_PUBLISHED_FILE, headers: true)
      puts '🗃 Published tweets:'
      published.each_with_index do |row, i|
        puts "#{i + 1}. #{row['text']}"
      end
    else
      puts '📭 No published tweets yet.'
    end
  end

  # Add a new tweet to the collection
  # @param text [String] tweet content
  # @param category [String] tweet category
  # @return [void]
  def add_tweet(text, category)
    CSV.open(TWEET_COLLECTION_FILE, 'a+') do |csv|
      csv << %w[id category text] if csv.count.zero?
      id = SecureRandom.uuid
      csv << [id, category, text]
    end
    puts "✅ Added tweet to queue under '#{category}'"
  end

  # Find an upcoming tweet by its ID
  # @param id [String] tweet ID to search for
  # @return [Hash, nil] tweet hash or nil if not found
  def find_upcoming_by_id(id)
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    row = all.find { |r| r['id'] == id }
    return nil unless row

    { id: row['id'], category: row['category'], tweet: row['tweet'] }
  end

  # Remove a tweet from the collection (after publishing)
  # @param id [String] tweet ID to remove
  # @return [void]
  def remove_from_tweet_collection(id)
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    updated = all.reject { |r| r['id'] == id }
    CSV.open(TWEET_COLLECTION_FILE, 'w') do |csv|
      csv << all.headers
      updated.each { |r| csv << r }
    end
  end

  # Post a tweet and return its ID and URL
  # @param text [String] tweet content to post
  # @return [Hash] hash containing :id and :url
  def post_tweet_and_get_id_url(text)
    tweet_obj = @client.post("tweets", { text: text }.to_json)
    id = tweet_obj.dig("data", "id")
    url = "https://x.com/#{ENV['X_USERNAME']}/status/#{id}"
    { id: id, url: url }
  end

  # Format tweet text for posting (add line breaks and organize hashtags)
  # @param text [String] raw tweet text
  # @return [String] formatted tweet text
  def format_tweet(text)
    # Add line break after the first sentence
    formatted = text.sub(/\. /, ".\n\n")

    # Move hashtags to their own line
    formatted.sub(/(#[\w]+)/, "\n\n\\1")
  end

  # Get current time in specified timezone
  # @param city [String] timezone name (default: 'Asia/Kathmandu')
  # @return [Time] current time in specified timezone
  def my_timezone(city = 'Asia/Kathmandu')
    tz = TZInfo::Timezone.get(city)
    tz.now
  end
end

# frozen_string_literal: true

require 'csv'
require 'dotenv/load'
require 'time'
require 'x'
require 'debug'
require 'tzinfo'

class Scheduler
  ROOT_DIR = File.expand_path('../../', __dir__)
  DATA_DIR = File.join(ROOT_DIR, 'data')

  TWEET_COLLECTION_FILE = File.join(DATA_DIR, 'tweet_collection.csv')
  TWEET_PUBLISHED_FILE = File.join(DATA_DIR, 'tweet_published.csv')

  def initialize
    @client = X::Client.new(
      api_key: ENV['X_API_KEY'],
      api_key_secret: ENV['X_API_KEY_SECRET'],
      access_token: ENV['X_ACCESS_TOKEN'],
      access_token_secret: ENV['X_ACCESS_TOKEN_SECRET']
    )
  end

  # RUN
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
        # Move the tweet to the published list
        send_to_published(obj_id, category, tweet)
      else
        puts "❌ Failed to tweet: #{response.status} - #{response.body}"
      end
    rescue StandardError => e
      puts "❌ Failed to tweet: #{e.message}"
    end
  end

  def valid_tweet?(text)
    return false if text.nil? || text.strip.empty? || text.length > 280

    true
  end

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

  def published_tweets
    return [] unless File.exist?(TWEET_PUBLISHED_FILE)

    CSV.read(TWEET_PUBLISHED_FILE, headers: true).map { |row| row['text'] }
  end

  def send_to_published(id, category, text)
    CSV.open(TWEET_PUBLISHED_FILE, 'a+') do |csv|
      csv << %w[id category text timestamp] if csv.count.zero?
      timestamp = Time.now.utc.iso8601

      csv << [id, category, text, timestamp]
    end
  end
  
  # PREVIEW TWEETS
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

  # LIST UNPUBLISHED TWEETS
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

  # LIST PUBLISHED TWEETS
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

  # ADD TWEET
  def add_tweet(text, category)
    CSV.open(TWEET_COLLECTION_FILE, 'a+') do |csv|
      csv << %w[id category text] if csv.count.zero?
      id = SecureRandom.uuid
      csv << [id, category, text]
    end
    puts "✅ Added tweet to queue under '#{category}'"
  end

  # TWEET NOW
  def find_upcoming_by_id(id)
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    row = all.find { |r| r['id'] == id }
    return nil unless row

    { id: row['id'], category: row['category'], tweet: row['tweet'] }
  end

  def remove_from_tweet_collection(id)
    all = CSV.read(TWEET_COLLECTION_FILE, headers: true)
    updated = all.reject { |r| r['id'] == id }
    CSV.open(TWEET_COLLECTION_FILE, 'w') do |csv|
      csv << all.headers
      updated.each { |r| csv << r }
    end
  end

  def post_tweet_and_get_id_url(text)
    tweet_obj = @client.post("tweets", { text: text }.to_json)
    id = tweet_obj.dig("data", "id")
    url = "https://x.com/#{ENV['X_USERNAME']}/status/#{id}"
    { id: id, url: url }
  end

  def format_tweet(text)
    # Add line break after the first sentence
    formatted = text.sub(/\. /, ".\n\n")

    # Move hashtags to their own line
    formatted.sub(/(#[\w]+)/, "\n\n\\1")
  end

  def my_timezone(city = 'Asia/Kathmandu')
    # Get the current time in the specified timezone
    tz = TZInfo::Timezone.get(city)
    tz.now
  end
end

require 'sinatra'
require 'sinatra/flash'
require 'csv'
require 'byebug'
require 'dotenv/load'
require 'securerandom'
require_relative './lib/tweetx/scheduler'

use Rack::Session::Cookie,
    key: 'tweetx_session',
    path: '/',
    secret: ENV['SESSION_SECRET'], # SecureRandom.hex(64),
    expire_after: nil  # Session expires when browser closes unless overridden by "remember me"

enable :sessions
register Sinatra::Flash

TWEET_COLLECTION = 'data/tweet_collection.csv'
TWEET_PUBLISHED = 'data/tweet_published.csv'
CATEGORIES_FILE = 'data/categories.txt'

helpers do
  def logged_in?
    session[:logged_in]
  end

  def escape_js(str)
    str.gsub('\\', '\\\\').gsub('</', '<\/').gsub("\r\n", "\\n").gsub("\n", "\\n").gsub("\r", "\\n").gsub('"', '\\"').gsub("'", "\\'")
  end

  def ensure_csv_file(path, headers)
    if !File.exist?(path) || File.zero?(path)
      CSV.open(path, 'w') { |csv| csv << headers }
    else
      existing = CSV.read(path)
      if existing.empty?
        CSV.open(path, 'w') { |csv| csv << headers }
      end
    end
  end

  # CATEGORIES OPS
  def load_categories
    return [] unless File.exist?(CATEGORIES_FILE)

    CSV.read(CATEGORIES_FILE).flatten.reject(&:empty?)
  end

  def save_category(category)
    File.open(CATEGORIES_FILE, 'a') { |f| f.puts(category.strip) }
  end

  def ensure_required_csvs
    ensure_csv_file(TWEET_COLLECTION, %w[id category tweet])
    ensure_csv_file(TWEET_PUBLISHED, %w[id category tweet timestamp])
  end

  def read_csv(path)
    return [] unless File.exist?(path)
    CSV.read(path, headers: true).map(&:to_h)
  end

  def tweets_present?(csv_array)
    return false if csv_array.empty?
    csv_array.any? { |row| row['tweet'].to_s.strip != '' || row['category'].to_s.strip != '' }
  end

  def apply_filters(tweets, params)
    tweets.select do |tweet|
      matches_category = params[:category].to_s.empty? || tweet['category'].to_s.downcase == params[:category].downcase
      matches_id       = params[:id].to_s.empty? || tweet['id'].to_s.include?(params[:id])
      matches_text     = params[:search].to_s.empty? || tweet['tweet'].to_s.downcase.include?(params[:search].downcase)
      matches_category && matches_id && matches_text
    end
  end

  def format_timestamp(iso_string)
    time_utc = Time.parse(iso_string)                          # Convert string to Time object
    kathmandu = TZInfo::Timezone.get('Asia/Kathmandu')        # Get the timezone
    local_time = kathmandu.to_local(time_utc)                 # Convert to Kathmandu time
    local_time.strftime("%b %d, %Y • %I:%M %p %Z")             # Format the output
  end

  def format_tweet(text)
    # Add line break after the first sentence
    formatted = text.sub(/\. /, ".\n\n")

    # Move hashtags to their own line
    formatted.sub(/(#[\w]+)/, "\n\n\\1")
  end

  # Pagination for upcoming & published tweets
  def paginate(collection, params, base_url)
    page = (params[:page] || 1).to_i
    per_page = 10
    total_pages = (collection.size / per_page.to_f).ceil
    paginated = collection.slice((page - 1) * per_page, per_page) || []

    {
      items: paginated,
      pagination: {
        current: page,
        total: total_pages,
        prev: (page > 1 ? page - 1 : nil),
        next: (page < total_pages ? page + 1 : nil),
        base_url: base_url,
        query: URI.encode_www_form(params.reject { |k, _| k == 'page' })
      }
    }
  end

  # View helpers
  def view_all_links(url)
    query = URI.encode_www_form(params.reject { |_, v| v.nil? || v.strip.empty? })
    view_all_links = "/#{url}"
    view_all_links += "?#{query}" unless query.empty?
    view_all_links
  end

  def sort_and_reverse_by_timestamp(tweets)
    tweets.sort_by do |row|
      begin
        Time.parse(row['timestamp'].to_s)
      rescue
        Time.at(0) # fallback if timestamp is invalid
      end
    end.reverse!
  end
end

before do
  unless request.path_info == '/login' || logged_in?
    redirect '/login'
  end
end

get '/' do
  if session[:logged_in]
    redirect '/dashboard'
  else
    redirect '/login' # future optional page
  end
end

get '/login' do
  redirect '/dashboard' if logged_in?
  erb :login
end

post '/login' do
  if params[:username] == ENV['TWEETX_USER'] && params[:password] == ENV['TWEETX_PASS']
    session[:logged_in] = true

    # Set persistent session cookie
    if params[:remember_me] == "1"
      response.set_cookie(
        "tweetx_session",
        value: request.cookies["tweetx_session"],
        path: "/",
        max_age: "2592000", # 30 days in seconds
        httponly: true
      )
    end

    flash[:success] = "Successfully logged in!"
    redirect '/dashboard'
  else
    flash[:error] = "Invalid credentials! Please try again."
    erb :login
  end
end

get '/dashboard' do
  ensure_required_csvs

  all_upcoming = read_csv(TWEET_COLLECTION)
  all_published = read_csv(TWEET_PUBLISHED)
  @categories = load_categories

  # Remove upcoming tweets that were already published
  published_texts = all_published.map { |r| r['tweet'].to_s.strip }
  filtered_upcoming = all_upcoming.reject { |r| published_texts.include?(r['tweet'].to_s.strip) }
  @upcoming = if tweets_present?(filtered_upcoming)
    apply_filters(filtered_upcoming, params).last(6).reverse
  else
    []
  end

  # Get the last 4 published tweets
  @published = if tweets_present?(all_published)
    ap = apply_filters(all_published, params)
    sort_and_reverse_by_timestamp(ap).first(7)
  else
    []
  end

  erb :dashboard
end

get '/upcoming' do
  ensure_required_csvs
  @categories = load_categories

  all_upcoming = read_csv(TWEET_COLLECTION)
  published = read_csv(TWEET_PUBLISHED)
  published_texts = published.map { |r| r['tweet'].to_s.strip }

  # Apply filters & Paginate
  upcoming = all_upcoming.reject { |r| published_texts.include?(r['tweet'].to_s.strip) }
  filtered = apply_filters(upcoming, params).reverse
  result = paginate(filtered, params, '/upcoming')
  @upcoming = result[:items]
  @pagination = result[:pagination]

  erb :upcoming
end

get '/published' do
  ensure_required_csvs
  @categories = load_categories
  published = read_csv(TWEET_PUBLISHED)

  # Apply filters & Paginate
  filtered = apply_filters(published, params)
  filtered = sort_and_reverse_by_timestamp(filtered)
  result = paginate(filtered, params, '/published')
  @published = result[:items]
  @pagination = result[:pagination]

  erb :published
end

# TWEET OPS
get '/new' do
  @categories = load_categories

  if @categories.empty?
    flash[:danger] = "🚫 Please create at least one category before adding tweets!"
    redirect '/categories'
  end

  erb :new
end

# Add new tweet
post '/submit' do
  tweets = params[:tweets].split("\n").map(&:strip).reject(&:empty?)
  categories = params[:categories] || []
  
  if tweets.empty? || categories.empty?
    flash[:danger] = "Please select at least one category and enter at least one tweet!"
    redirect '/new'
  end

  rows = []
  headers = %w[id category tweet]

  # Read existing tweets
  if File.exist?(TWEET_COLLECTION)
    existing = CSV.read(TWEET_COLLECTION, headers: true)

    # Upgrade if headers are missing 'id'
    if existing.headers.include?('id')
      rows = existing.map(&:to_h)
    else
      # Add fake IDs to existing rows
      rows = existing.map do |row|
        { 'id' => SecureRandom.hex(4), 'category' => row['category'], 'tweet' => row['tweet'] }
      end
    end
  end

  # Add new tweets
  categories.each do |category|
    tweets.each do |tweet|
      rows << { 'id' => SecureRandom.hex(4), 'category' => category, 'tweet' => tweet }
    end
  end

  # Save updated CSV with ID
  CSV.open(TWEET_COLLECTION, 'w') do |csv|
    csv << headers
    rows.each { |row| csv << [row['id'], row['category'], row['tweet']] }
  end

  flash[:success] = "Added #{tweets.size} tweet(s) to #{categories.join(', ')}!"
  redirect '/dashboard'
end

# Post tweet now
post '/tweet-now/:id' do
  content_type :json
  scheduler = Scheduler.new
  upcoming_tweet = scheduler.find_upcoming_by_id(params[:id])

  unless upcoming_tweet
    halt 404, { success: false, message: "Tweet not found or already posted!" }.to_json
  end

  begin
    tweet = upcoming_tweet[:tweet]
    category = upcoming_tweet[:category]
    formatted = scheduler.format_tweet(tweet)
    # Remove this line and uncomment the below line when you have the actual tweet posting logic
    tweet_response_url = 'https://x.com/cdrrazan/status/1905966122580770942'
    # tweet_response_url = scheduler.post_tweet_and_get_url(formatted)
    # scheduler.send_to_published(category, tweet)
    # scheduler.remove_from_tweet_collection(upcoming_tweet[:id])

    { success: true, url: tweet_response_url }.to_json
  rescue => e
    status 500
    { success: false, message: "Failed to post tweet: #{e.message}" }.to_json
  end
end

# Edit tweet
get '/edit/:id' do
  @redirect_to = params[:redirect_to] || '/dashboard'
  @tweets = CSV.read(TWEET_COLLECTION, headers: true)
  @tweet = @tweets.find { |row| row['id'] == params[:id] }
  @categories = load_categories

  if @tweet.nil?
    flash[:danger] = "Tweet not found!"
    redirect '/dashboard'
  end

  erb :edit
end

# Update tweet
post '/update/:id' do
  id = params[:id]
  new_tweet = params[:tweet].to_s.strip
  new_category = params[:category].to_s.strip

  if id.empty? || new_tweet.empty? || new_category.empty?
    flash[:danger] = "All fields are required to update the tweet!"
    redirect '/dashboard'
  end

  tweets = CSV.read(TWEET_COLLECTION, headers: true)
  updated = tweets.map do |row|
    if row['id'] == id
      row['category'] = new_category
      row['tweet'] = new_tweet
    end
    row
  end

  CSV.open(TWEET_COLLECTION, 'w') do |csv|
    csv << %w[id category tweet]
    updated.each do |row|
      csv << [row['id'], row['category'], row['tweet']]
    end
  end

  flash[:success] = "Tweet successfully updated!"
  redirect_to = params[:redirect_to] || '/dashboard'
  redirect redirect_to
end

# Delete tweet
get '/delete/:id' do
  csv_table = CSV.read(TWEET_COLLECTION, headers: true)
  updated_table = csv_table.reject { |row| row['id'] == params[:id] }

  CSV.open(TWEET_COLLECTION, 'w') do |csv|
    csv << %w[id category tweet]
    updated_table.each { |row| csv << [row['id'], row['category'], row['tweet']] }
  end

  flash[:success] = "Tweet deleted successfully!"
  redirect_to = params[:redirect_to] || '/dashboard'
  redirect redirect_to
end

# Show all categories
get '/categories' do
  @categories = load_categories
  erb :categories
end

# Add new category
post '/categories' do
  new_category = params[:category].strip
  save_category(new_category) unless new_category.empty?

  flash[:success] = "Added category ➖#{new_category}"
  redirect '/categories'
end

# Edit category
post '/categories/edit/:old' do
  old = params[:old].strip
  new = params[:new].strip
  
  # 1. Update categories.txt
  categories = load_categories
  updated_categories = categories.map { |c| c == old ? new : c }.uniq
  File.write(CATEGORIES_FILE, updated_categories.join("\n") + "\n")

  # 2. Update category in TWEET_COLLECTION.csv
  if File.exist?(TWEET_COLLECTION)
    tweets = CSV.read(TWEET_COLLECTION, headers: true)
    tweets.each do |row|
      row['category'] = new if row['category'] == old
    end

    CSV.open(TWEET_COLLECTION, 'w') do |csv|
      csv << %w[id category tweet]
      tweets.each { |row| csv << row }
    end
  end

  flash[:success] = "Updated category ➖ #{old} → #{new}."
  redirect '/categories'
end

# Delete category
post '/categories/delete/:name' do
  name = params[:name]
  updated = load_categories.reject { |c| c == name }

  File.write(CATEGORIES_FILE, updated.join("\n") + "\n")
  flash[:success] = "Deleted category ➖ #{name}."
  redirect '/categories'
end

# Logout
post '/logout' do
  session.clear
  flash[:success] = "Successfully logged out!"
  redirect '/login'
end

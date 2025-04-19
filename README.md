# 🐦 TweetX 
_— Your Developer-First Tweet Automation Toolkit_

**TweetX** is a lightweight, developer-friendly tweet scheduler and dashboard designed for coders, writers, and creators who want to stay consistent without the hassle.

> ✅ Schedule, post, manage, and automate tweets — all with a clean Ruby-powered CLI and UI.



## 💡 What is TweetX?

TweetX is a simple, open-source tool that lets you:

- ✍️ Write tweets by category
- 📋 View and manage them from a beautiful dashboard
- 🐙 Auto-post using GitHub Actions
- 💾 Store everything in CSV (no DB needed!)
- 🌍 Respect your timezone (Kathmandu 🇳🇵 or any)
- 🔄 Commit back to GitHub on tweet publication

It's like a tweet CMS + bot for devs. Build once. Automate forever.


## ✨ Product Highlights

- 🧠 Smart tweet selector (by category and time slot)
- 🌐 Local dashboard (built with Sinatra + Bootstrap)
- 📊 Dashboard filters: category, ID, text
- 🔐 Login-protected UI with copy-to-clipboard + preview
- 📆 Timezone-aware publishing (Kathmandu Time support)
- 🔁 GitHub Actions for automation (publish-tweetx branch)
- ✅ Auto commit + push updated tweet history



## 🖥 UI & CLI Preview

```bash
# Post one tweet manually
$ bundle exec ruby bin/tweetx tweet

# Preview which tweet will be posted
$ bundle exec ruby bin/tweetx preview

# Run Sinatra dashboard locally
$ ruby app.rb
```



## 📦 Built With

- **Ruby 3.x**
- **Sinatra** (dashboard UI)
- **CSV** for persistence
- **tzinfo** for timezone support
- **Bootstrap 5** for styling
- **GitHub Actions** for CI/CD tweet posting



## 📂 Folder Structure

```
TweetX/
├── app.rb              # Sinatra app
├── bin/tweetx          # CLI interface
├── lib/                # Tweet scheduler logic
├── views/              # UI templates
├── data/               # Tweets and categories CSV
└── .github/workflows/  # Tweet scheduler via Actions
```



## 🚀 Who Is It For?

- 🧑‍💻 Developers building in public
- 🐦 Creators growing on Twitter/X
- ✨ Indie hackers promoting their product
- 🧰 Teams with structured tweet workflows

If you’re tired of broken schedulers or overpriced SaaS tools, TweetX gives you full control.



## 📘 Coming Soon

- 🔗 Thread support
- 📈 Tweet analytics
- ✨ AI tweet generator
- 🧑‍🤝‍🧑 Multi-user roles



## 👨‍💻 Created by

[Rajan Bhattarai](https://github.com/cdrrazan) — a Ruby developer, product hacker, and open-source enthusiast.



## 📜 License

MIT — free for personal and commercial use.



> ⭐ Star the project if it helps you! Pull requests welcome!

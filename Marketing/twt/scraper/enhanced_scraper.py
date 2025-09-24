import os
import sys
import argparse
import getpass
from twitter_scraper import Twitter_Scraper
from twitter_poster import TwitterPoster
from agent_manager import AgentManager

try:
    from dotenv import load_dotenv
    print("Loading .env file")
    load_dotenv()
    print("Loaded .env file\n")
except Exception as e:
    print(f"Error loading .env file: {e}")
    sys.exit(1)


def main():
    try:
        parser = argparse.ArgumentParser(
            add_help=True,
            usage="python enhanced_scraper [option] ... [arg] ...",
            description="Enhanced Twitter Agent - scrape, post, reply, and run autonomous marketing AI agent",
        )

        # Authentication arguments
        try:
            parser.add_argument(
                "--mail",
                type=str,
                default=os.getenv("TWITTER_MAIL"),
                help="Your Twitter mail.",
            )

            parser.add_argument(
                "--user",
                type=str,
                default=os.getenv("TWITTER_USERNAME"),
                help="Your Twitter username.",
            )

            parser.add_argument(
                "--password",
                type=str,
                default=os.getenv("TWITTER_PASSWORD"),
                help="Your Twitter password.",
            )

            parser.add_argument(
                "--headlessState",
                type=str,
                default=os.getenv("HEADLESS"),
                help="Headless mode? [yes/no]"
            )
            
            parser.add_argument(
                "--mentioned-user",
                type=str,
                default=os.getenv("MENTIONED_USER"),
                help="Username to monitor for mentions (for agent mode)"
            )
        except Exception as e:
            print(f"Error retrieving environment variables: {e}")
            sys.exit(1)

        # Mode selection
        parser.add_argument(
            "--mode",
            type=str,
            choices=["scrape", "post", "reply", "both", "agent", "agent-single", "agent-mentions"],
            default="scrape",
            help="Operating mode: 'scrape', 'post', 'reply', 'both', 'agent' (autonomous), 'agent-single' (generate one tweet), 'agent-mentions' (check mentions)",
        )

        # Scraping arguments (existing functionality)
        parser.add_argument(
            "-t",
            "--tweets",
            type=int,
            default=50,
            help="Number of tweets to scrape (default: 50)",
        )

        parser.add_argument(
            "-u",
            "--username",
            type=str,
            default=None,
            help="Twitter username. Scrape tweets from a user's profile.",
        )

        parser.add_argument(
            "-ht",
            "--hashtag",
            type=str,
            default=None,
            help="Twitter hashtag. Scrape tweets from a hashtag.",
        )

        parser.add_argument(
            "--bookmarks",
            action='store_true',
            help="Twitter bookmarks. Scrape tweets from your bookmarks.",
        )

        parser.add_argument(
            "-ntl",
            "--no_tweets_limit",
            nargs='?',
            default=False,
            help="Set no limit to the number of tweets to scrape (will scrap until no more tweets are available).",
        )

        parser.add_argument(
            "-l",
            "--list",
            type=str,
            default=None,
            help="List ID. Scrape tweets from a list.",
        )

        parser.add_argument(
            "-q",
            "--query",
            type=str,
            default=None,
            help="Twitter query or search. Scrape tweets from a query or search.",
        )

        parser.add_argument(
            "-a",
            "--add",
            type=str,
            default="",
            help="Additional data to scrape and save in the .csv file.",
        )

        parser.add_argument(
            "--latest",
            action="store_true",
            help="Scrape latest tweets",
        )

        parser.add_argument(
            "--top",
            action="store_true",
            help="Scrape top tweets",
        )

        # Posting arguments
        parser.add_argument(
            "--tweet-content",
            type=str,
            default=None,
            help="Content for the tweet to post (required for 'post' mode)",
        )

        parser.add_argument(
            "--reply-to",
            type=str,
            default=None,
            help="URL of the tweet to reply to (required for 'reply' mode)",
        )

        parser.add_argument(
            "--reply-content",
            type=str,
            default=None,
            help="Content for the reply (required for 'reply' mode)",
        )

        parser.add_argument(
            "--tweet-file",
            type=str,
            default=None,
            help="Path to a text file containing tweet content (alternative to --tweet-content)",
        )

        parser.add_argument(
            "--interactive",
            action="store_true",
            help="Enable interactive mode for posting tweets",
        )

        # Agent-specific arguments
        parser.add_argument(
            "--agent-context",
            type=str,
            choices=["product_launch", "milestone", "achievement", "announcement", "engagement"],
            default=None,
            help="Context type for agent-generated tweets"
        )

        parser.add_argument(
            "--tweet-interval",
            type=int,
            default=120,
            help="Minutes between autonomous tweets (default: 120)"
        )

        parser.add_argument(
            "--mention-interval",
            type=int,
            default=15,
            help="Minutes between mention checks (default: 15)"
        )

        parser.add_argument(
            "--max-tweets-daily",
            type=int,
            default=8,
            help="Maximum tweets per day in autonomous mode (default: 8)"
        )

        parser.add_argument(
            "--max-replies-hourly",
            type=int,
            default=5,
            help="Maximum replies per hour (default: 5)"
        )

        parser.add_argument(
            "--no-images",
            action="store_true",
            help="Disable image generation for agent tweets"
        )

        args = parser.parse_args()

        # Get authentication details
        USER_MAIL = args.mail
        USER_UNAME = args.user
        USER_PASSWORD = args.password
        HEADLESS_MODE = args.headlessState
        MENTIONED_USER = args.mentioned_user

        if USER_UNAME is None:
            USER_UNAME = input("Twitter Username: ")

        if USER_PASSWORD is None:
            USER_PASSWORD = getpass.getpass("Enter Password: ")

        if HEADLESS_MODE is None:
            HEADLESS_MODE = str(input("Headless?[Yes/No]: ")).lower()

        print()

        # Validate mode-specific arguments
        if args.mode == "post":
            if not args.tweet_content and not args.tweet_file and not args.interactive:
                print("Error: 'post' mode requires --tweet-content, --tweet-file, or --interactive")
                sys.exit(1)
        elif args.mode == "reply":
            if not args.reply_to or (not args.reply_content and not args.interactive):
                print("Error: 'reply' mode requires --reply-to and --reply-content (or --interactive)")
                sys.exit(1)
        elif args.mode in ["agent", "agent-single", "agent-mentions"]:
            if not MENTIONED_USER:
                print("Error: Agent modes require --mentioned-user or MENTIONED_USER environment variable")
                sys.exit(1)

        # Handle different modes
        if args.mode in ["agent", "agent-single", "agent-mentions"]:
            # Agent modes
            execute_agent_mode(args, USER_MAIL, USER_UNAME, USER_PASSWORD, HEADLESS_MODE, MENTIONED_USER)
        else:
            # Traditional scraping/posting modes
            execute_traditional_mode(args, USER_MAIL, USER_UNAME, USER_PASSWORD, HEADLESS_MODE)

    except KeyboardInterrupt:
        print("\nScript Interrupted by user. Exiting...")
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)


def execute_agent_mode(args, mail, username, password, headless_mode, mentioned_user):
    """Execute agent-based modes"""
    try:
        print("🤖 Initializing AI Agent...")
        
        # Initialize agent manager
        agent = AgentManager(
            mail=mail,
            username=username,
            password=password,
            headless_mode=headless_mode,
            mentioned_user=mentioned_user
        )

        if args.mode == "agent":
            # Autonomous mode
            print("🚀 Starting autonomous agent mode...")
            agent.start_autonomous_mode(
                tweet_interval_minutes=args.tweet_interval,
                mention_check_minutes=args.mention_interval,
                max_tweets_per_day=args.max_tweets_daily,
                max_replies_per_hour=args.max_replies_hourly
            )

        elif args.mode == "agent-single":
            # Generate single tweet
            print("🎨 Generating single tweet...")
            
            specific_content = None
            if args.interactive:
                # Interactive mode for single tweet
                print("Interactive tweet generation:")
                context = input("Context type (press Enter for auto): ").strip() or None
                topic = input("Specific topic (press Enter for auto): ").strip()
                content = input("Specific content/announcement (press Enter for auto): ").strip()
                
                if topic or content:
                    specific_content = {}
                    if topic:
                        specific_content['topic'] = topic
                    if content:
                        specific_content['content'] = content

            result = agent.generate_single_tweet(
                context_type=args.agent_context,
                specific_content=specific_content,
                post_immediately=True
            )

            if result['success']:
                print(f"✅ Tweet generated and posted successfully!")
                if result.get('tweet_data', {}).get('image_result', {}).get('success'):
                    print(f"🖼️ Image included: {result['tweet_data']['image_result']['image_path']}")
            else:
                print(f"❌ Failed to generate/post tweet: {result.get('error', 'Unknown error')}")

        elif args.mode == "agent-mentions":
            # Manual mention check
            print("🔍 Checking mentions...")
            summary = agent.manual_mention_check()
            
            if 'error' not in summary:
                print(f"📊 Mention check complete:")
                print(f"   Mentions found: {summary['mentions_found']}")
                print(f"   Replies sent: {summary['replies_sent']}")
                print(f"   Errors: {summary['errors']}")
            else:
                print(f"❌ Error checking mentions: {summary['error']}")

        # Print final stats and cleanup
        stats = agent.get_agent_stats()
        print("\n📊 Session Statistics:")
        print(f"   Tweets generated: {stats['tweets_generated']}")
        print(f"   Mentions processed: {stats['mentions_processed']}")
        print(f"   Replies sent: {stats['replies_sent']}")
        print(f"   Images generated: {stats['images_generated']}")
        
        agent.stop_agent()

    except Exception as e:
        print(f"❌ Error in agent mode: {e}")
        sys.exit(1)


def execute_traditional_mode(args, mail, username, password, headless_mode):
    """Execute traditional scraping/posting modes"""
    try:
        # Handle scraping arguments (existing logic)
        tweet_type_args = []
        if args.username is not None:
            tweet_type_args.append(args.username)
        if args.hashtag is not None:
            tweet_type_args.append(args.hashtag)
        if args.list is not None:
            tweet_type_args.append(args.list)
        if args.query is not None:
            tweet_type_args.append(args.query)
        if args.bookmarks is not False:
            tweet_type_args.append("bookmarks")

        additional_data = args.add.split(",") if args.add else []

        if len(tweet_type_args) > 1 and args.mode in ["scrape", "both"]:
            print("Please specify only one of --username, --hashtag, --bookmarks, or --query.")
            sys.exit(1)

        if args.latest and args.top:
            print("Please specify either --latest or --top. Not both.")
            sys.exit(1)

        # Initialize scraper
        if username is not None and password is not None:
            scraper = Twitter_Scraper(
                mail=mail,
                username=username,
                password=password,
                headlessState=headless_mode
            )
            scraper.login()

            # Initialize poster with posting capabilities
            poster = TwitterPoster(scraper.driver, scraper.actions)

            # Execute based on mode
            if args.mode == "scrape":
                execute_scraping(scraper, args, additional_data)
            elif args.mode == "post":
                execute_posting(poster, args)
            elif args.mode == "reply":
                execute_replying(poster, args)
            elif args.mode == "both":
                execute_scraping(scraper, args, additional_data)
                print("\n" + "="*50)
                print("Switching to posting mode...")
                print("="*50 + "\n")
                execute_posting(poster, args)

            if not scraper.interrupted:
                scraper.driver.close()
        else:
            print("Missing Twitter username or password environment variables. Please check your .env file.")
            sys.exit(1)

    except Exception as e:
        print(f"❌ Error in traditional mode: {e}")
        sys.exit(1)


def execute_scraping(scraper, args, additional_data):
    """Execute the scraping functionality"""
    scraper.scrape_tweets(
        max_tweets=args.tweets,
        no_tweets_limit=args.no_tweets_limit if args.no_tweets_limit is not None else True,
        scrape_username=args.username,
        scrape_hashtag=args.hashtag,
        scrape_bookmarks=args.bookmarks,
        scrape_query=args.query,
        scrape_list=args.list,
        scrape_latest=args.latest,
        scrape_top=args.top,
        scrape_poster_details="pd" in additional_data,
    )
    scraper.save_to_csv()


def execute_posting(poster, args):
    """Execute the posting functionality"""
    tweet_content = None
    
    if args.interactive:
        tweet_content = input("Enter tweet content: ").strip()
    elif args.tweet_file:
        try:
            with open(args.tweet_file, 'r', encoding='utf-8') as f:
                tweet_content = f.read().strip()
        except FileNotFoundError:
            print(f"Error: File '{args.tweet_file}' not found")
            return
        except Exception as e:
            print(f"Error reading file '{args.tweet_file}': {e}")
            return
    else:
        tweet_content = args.tweet_content

    if not tweet_content:
        print("Error: No tweet content provided")
        return

    success = poster.post_tweet(tweet_content)
    if success:
        print(f"🎉 Tweet posted successfully! Total posts this session: {poster.get_post_count()}")
    else:
        print("❌ Failed to post tweet")


def execute_replying(poster, args):
    """Execute the replying functionality"""
    reply_content = None
    
    if args.interactive:
        print(f"Replying to: {args.reply_to}")
        reply_content = input("Enter reply content: ").strip()
    else:
        reply_content = args.reply_content

    if not reply_content:
        print("Error: No reply content provided")
        return

    success = poster.reply_to_tweet(args.reply_to, reply_content)
    if success:
        print(f"🎉 Reply posted successfully! Total posts this session: {poster.get_post_count()}")
    else:
        print("❌ Failed to post reply")


if __name__ == "__main__":
    main()
import os
import time
import json
from datetime import datetime, timedelta
from twitter_scraper import Twitter_Scraper
from twitter_poster import TwitterPoster
from agent_personality import AgentPersonality
from mention_monitor import MentionMonitor
from tweet_generator import TweetGenerator
from image_generator import ImageGenerator
from dotenv import load_dotenv

load_dotenv()


class AgentManager:
    def __init__(
        self,
        mail=None,
        username=None, 
        password=None,
        headless_mode=None,
        mentioned_user=None
    ):
        """
        Initialize the AI Agent Manager that orchestrates all agent capabilities
        
        Args:
            mail (str): Twitter email
            username (str): Twitter username
            password (str): Twitter password
            headless_mode (str): Headless browser mode
            mentioned_user (str): Username to monitor for mentions
        """
        print("🤖 Initializing AI Agent Manager...")
        
        # Get credentials
        self.mail = mail or os.getenv("TWITTER_MAIL")
        self.username = username or os.getenv("TWITTER_USERNAME") 
        self.password = password or os.getenv("TWITTER_PASSWORD")
        self.headless_mode = headless_mode or os.getenv("HEADLESS", "yes")
        self.mentioned_user = mentioned_user or os.getenv("MENTIONED_USER")
        
        if not all([self.username, self.password]):
            raise ValueError("Twitter credentials are required")
            
        if not self.mentioned_user:
            raise ValueError("MENTIONED_USER environment variable must be set")
        
        # Initialize core components
        self._initialize_components()
        
        # Agent state
        self.running = False
        self.stats = {
            'start_time': None,
            'tweets_generated': 0,
            'mentions_processed': 0,
            'replies_sent': 0,
            'images_generated': 0,
            'errors': 0
        }
        
        print("✅ AI Agent Manager initialized successfully!")
        
    def _initialize_components(self):
        """Initialize all agent components"""
        try:
            # Core Twitter functionality
            print("📱 Initializing Twitter scraper...")
            self.scraper = Twitter_Scraper(
                mail=self.mail,
                username=self.username,
                password=self.password,
                headlessState=self.headless_mode
            )
            
            print("🔐 Logging into Twitter...")
            self.scraper.login()
            
            print("📝 Initializing Twitter poster...")
            self.poster = TwitterPoster(self.scraper.driver, self.scraper.actions)
            
            # AI components
            print("🧠 Initializing personality agent...")
            self.personality = AgentPersonality()
            
            print("🎨 Initializing image generator...")
            self.image_gen = ImageGenerator()
            
            print("📝 Initializing tweet generator...")
            self.tweet_gen = TweetGenerator(
                self.personality, 
                self.image_gen, 
                self.poster
            )
            
            print("🔍 Initializing mention monitor...")
            self.mention_monitor = MentionMonitor(
                self.scraper,
                self.poster, 
                self.personality,
                self.mentioned_user
            )
            
        except Exception as e:
            print(f"❌ Error initializing components: {e}")
            raise

    def start_autonomous_mode(
        self,
        tweet_interval_minutes=120,  # Tweet every 2 hours
        mention_check_minutes=15,   # Check mentions every 15 minutes
        max_tweets_per_day=8,       # Maximum tweets per day
        max_replies_per_hour=5      # Maximum replies per hour
    ):
        """
        Start autonomous agent mode
        
        Args:
            tweet_interval_minutes (int): Minutes between autonomous tweets
            mention_check_minutes (int): Minutes between mention checks
            max_tweets_per_day (int): Daily tweet limit
            max_replies_per_hour (int): Hourly reply limit
        """
        print("🚀 Starting autonomous agent mode...")
        print(f"   Tweet interval: {tweet_interval_minutes} minutes")
        print(f"   Mention check interval: {mention_check_minutes} minutes") 
        print(f"   Max tweets per day: {max_tweets_per_day}")
        print(f"   Max replies per hour: {max_replies_per_hour}")
        print("\nPress Ctrl+C to stop the agent\n")
        
        self.running = True
        self.stats['start_time'] = datetime.now()
        
        last_tweet_time = datetime.now() - timedelta(minutes=tweet_interval_minutes)
        last_mention_check = datetime.now() - timedelta(minutes=mention_check_minutes)
        
        try:
            while self.running:
                current_time = datetime.now()
                
                # Check if it's time for mention monitoring
                if (current_time - last_mention_check).total_seconds() >= mention_check_minutes * 60:
                    self._handle_mention_monitoring(max_replies_per_hour)
                    last_mention_check = current_time
                
                # Check if it's time for autonomous tweeting
                if (current_time - last_tweet_time).total_seconds() >= tweet_interval_minutes * 60:
                    if self._should_tweet_now(max_tweets_per_day):
                        self._handle_autonomous_tweet()
                        last_tweet_time = current_time
                    else:
                        print("📊 Daily tweet limit reached, skipping tweet generation")
                
                # Short sleep to prevent busy waiting
                time.sleep(30)  # Check every 30 seconds
                
        except KeyboardInterrupt:
            print("\n⏹️ Agent stopped by user")
            self.stop_agent()
        except Exception as e:
            print(f"❌ Error in autonomous mode: {e}")
            self.stats['errors'] += 1
            self.stop_agent()

    def _handle_mention_monitoring(self, max_replies_per_hour):
        """Handle mention monitoring cycle"""
        try:
            print("🔍 Checking for mentions...")
            
            # Check if we've hit reply limit for this hour
            if self._get_replies_this_hour() >= max_replies_per_hour:
                print(f"⏱️ Reply limit ({max_replies_per_hour}/hour) reached, skipping mention check")
                return
            
            # Run mention monitoring
            summary = self.mention_monitor.monitor_mentions_once(
                max_mentions=15,
                time_limit_hours=1
            )
            
            # Update stats
            self.stats['mentions_processed'] += summary['mentions_processed']
            self.stats['replies_sent'] += summary['replies_sent']
            self.stats['errors'] += summary['errors']
            
        except Exception as e:
            print(f"❌ Error in mention monitoring: {e}")
            self.stats['errors'] += 1

    def _handle_autonomous_tweet(self):
        """Handle autonomous tweet generation and posting"""
        try:
            print("🎨 Generating autonomous tweet...")
            
            # Generate and post tweet
            result = self.tweet_gen.generate_and_post(
                context_type=None,  # Let it decide
                specific_content=None,
                include_image=True
            )
            
            # Update stats
            if result['success']:
                self.stats['tweets_generated'] += 1
                print(f"✅ Autonomous tweet posted! (Total: {self.stats['tweets_generated']})")
                
                # Check if image was generated
                if result.get('tweet_data', {}).get('image_result', {}).get('success'):
                    self.stats['images_generated'] += 1
            else:
                print(f"❌ Failed to post autonomous tweet: {result.get('error', 'Unknown error')}")
                self.stats['errors'] += 1
                
        except Exception as e:
            print(f"❌ Error in autonomous tweet generation: {e}")
            self.stats['errors'] += 1

    def _should_tweet_now(self, max_tweets_per_day):
        """Check if we should tweet now based on daily limits"""
        tweets_today = self._get_tweets_today()
        return tweets_today < max_tweets_per_day

    def _get_tweets_today(self):
        """Get number of tweets posted today"""
        # This is a simplified implementation
        # In a real system, you'd track this more precisely
        if self.stats['start_time']:
            hours_since_start = (datetime.now() - self.stats['start_time']).total_seconds() / 3600
            if hours_since_start < 24:
                return self.stats['tweets_generated']
        return 0

    def _get_replies_this_hour(self):
        """Get number of replies in the last hour"""
        # Simplified implementation
        # In a real system, you'd track timestamps of each reply
        return min(self.stats['replies_sent'], 5)  # Cap at max for this simplified version

    def generate_single_tweet(self, context_type=None, specific_content=None, post_immediately=True):
        """
        Generate a single tweet (manual mode)
        
        Args:
            context_type (str): Type of tweet to generate
            specific_content (dict): Specific content to include
            post_immediately (bool): Whether to post immediately
            
        Returns:
            dict: Generation result
        """
        try:
            print(f"🎨 Generating single tweet (context: {context_type or 'auto'})...")
            
            if post_immediately:
                result = self.tweet_gen.generate_and_post(
                    context_type, 
                    specific_content,
                    include_image=True
                )
                
                if result['success']:
                    self.stats['tweets_generated'] += 1
                    if result.get('tweet_data', {}).get('image_result', {}).get('success'):
                        self.stats['images_generated'] += 1
                else:
                    self.stats['errors'] += 1
                    
                return result
            else:
                # Just generate, don't post
                tweet_data = self.tweet_gen.generate_fresh_tweet(context_type, specific_content)
                return {
                    'success': True,
                    'tweet_data': tweet_data,
                    'posted': False
                }
                
        except Exception as e:
            print(f"❌ Error generating single tweet: {e}")
            self.stats['errors'] += 1
            return {'success': False, 'error': str(e)}

    def manual_mention_check(self):
        """Manually check for mentions"""
        try:
            print("🔍 Manual mention check...")
            summary = self.mention_monitor.monitor_mentions_once(
                max_mentions=20,
                time_limit_hours=4
            )
            
            self.stats['mentions_processed'] += summary['mentions_processed']
            self.stats['replies_sent'] += summary['replies_sent']
            self.stats['errors'] += summary['errors']
            
            return summary
            
        except Exception as e:
            print(f"❌ Error in manual mention check: {e}")
            self.stats['errors'] += 1
            return {'error': str(e)}

    def reply_to_specific_tweet(self, tweet_url, custom_reply=None):
        """
        Reply to a specific tweet
        
        Args:
            tweet_url (str): URL of tweet to reply to
            custom_reply (str): Custom reply content (optional)
            
        Returns:
            dict: Reply result
        """
        try:
            print(f"💬 Replying to specific tweet: {tweet_url}")
            
            if custom_reply:
                # Use provided custom reply
                reply_content = custom_reply
            else:
                # Let the personality agent generate a reply
                # First we'd need to scrape the tweet content, simplified for now
                reply_content = "This is a chaotic reply to your tweet! 🤖✨"
            
            success = self.poster.reply_to_tweet(tweet_url, reply_content)
            
            if success:
                self.stats['replies_sent'] += 1
                print("✅ Reply posted successfully!")
            else:
                self.stats['errors'] += 1
                print("❌ Failed to post reply")
            
            return {
                'success': success,
                'reply_content': reply_content,
                'tweet_url': tweet_url
            }
            
        except Exception as e:
            print(f"❌ Error replying to specific tweet: {e}")
            self.stats['errors'] += 1
            return {'success': False, 'error': str(e)}

    def get_agent_stats(self):
        """Get agent performance statistics"""
        stats = self.stats.copy()
        
        if stats['start_time']:
            runtime = datetime.now() - stats['start_time']
            stats['runtime_hours'] = runtime.total_seconds() / 3600
            stats['tweets_per_hour'] = stats['tweets_generated'] / max(stats['runtime_hours'], 0.01)
            stats['replies_per_hour'] = stats['replies_sent'] / max(stats['runtime_hours'], 0.01)
        
        return stats

    def stop_agent(self):
        """Stop the agent"""
        print("🛑 Stopping agent...")
        self.running = False
        
        # Clean up
        if hasattr(self, 'scraper') and not self.scraper.interrupted:
            try:
                self.scraper.driver.close()
                print("🌐 Browser closed")
            except:
                pass
        
        # Print final stats
        stats = self.get_agent_stats()
        print("\n📊 Final Agent Statistics:")
        print(f"   Runtime: {stats.get('runtime_hours', 0):.1f} hours")
        print(f"   Tweets generated: {stats['tweets_generated']}")
        print(f"   Mentions processed: {stats['mentions_processed']}")
        print(f"   Replies sent: {stats['replies_sent']}")
        print(f"   Images generated: {stats['images_generated']}")
        print(f"   Errors: {stats['errors']}")
        
        print("👋 Agent stopped successfully!")

    def update_user_specifications(self, new_specs):
        """Update user specifications for tweet generation"""
        self.tweet_gen.update_user_specs(new_specs)
        print("📝 User specifications updated")

    def get_user_specifications(self):
        """Get current user specifications"""
        return self.tweet_gen.get_user_specs()


# Example usage
if __name__ == "__main__":
    try:
        # Initialize agent
        agent = AgentManager()
        
        # Example: Start autonomous mode
        # agent.start_autonomous_mode()
        
        # Example: Generate single tweet
        result = agent.generate_single_tweet(
            context_type="product_launch",
            specific_content={
                "product": "Chaotic AI Assistant",
                "features": ["unpredictable responses", "creative chaos", "maximum engagement"]
            }
        )
        
        print("Result:", result)
        
        # Stop agent
        agent.stop_agent()
        
    except Exception as e:
        print(f"Test error: {e}")
        print("Make sure environment variables are set!")
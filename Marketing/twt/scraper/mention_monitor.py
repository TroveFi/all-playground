import os
import time
from datetime import datetime, timedelta
from twitter_scraper import Twitter_Scraper
from agent_personality import AgentPersonality
from twitter_poster import TwitterPoster
from dotenv import load_dotenv

load_dotenv()


class MentionMonitor:
    def __init__(self, scraper, poster, personality_agent, mentioned_username=None):
        """
        Initialize mention monitoring system
        
        Args:
            scraper: Twitter_Scraper instance
            poster: TwitterPoster instance  
            personality_agent: AgentPersonality instance
            mentioned_username (str): Username to monitor for mentions
        """
        self.scraper = scraper
        self.poster = poster
        self.personality = personality_agent
        self.mentioned_username = mentioned_username or os.getenv("MENTIONED_USER")
        
        if not self.mentioned_username:
            raise ValueError("MENTIONED_USER environment variable must be set or pass mentioned_username parameter")
        
        # Remove @ if provided
        self.mentioned_username = self.mentioned_username.replace("@", "")
        
        self.processed_mentions = set()  # Track processed mentions to avoid duplicates
        self.last_check_time = datetime.now()
        
        print(f"🔍 Mention monitor initialized for @{self.mentioned_username}")

    def search_for_mentions(self, max_mentions=20, time_limit_hours=24):
        """
        Search for recent mentions of the monitored username
        
        Args:
            max_mentions (int): Maximum mentions to retrieve
            time_limit_hours (int): How far back to search (in hours)
            
        Returns:
            list: List of mention data
        """
        try:
            print(f"🔍 Searching for mentions of @{self.mentioned_username}...")
            
            # Create search query for mentions
            search_query = f"@{self.mentioned_username}"
            
            # Configure scraper for mention search
            self.scraper.scrape_tweets(
                max_tweets=max_mentions,
                scrape_query=search_query,
                scrape_latest=True,  # Get latest mentions
                no_tweets_limit=False
            )
            
            mentions = []
            cutoff_time = datetime.now() - timedelta(hours=time_limit_hours)
            
            for tweet_data in self.scraper.get_tweets():
                try:
                    # Parse tweet data
                    mention = self._parse_mention_data(tweet_data)
                    
                    # Skip if already processed
                    if mention['tweet_id'] in self.processed_mentions:
                        continue
                    
                    # Check if within time limit
                    tweet_time = datetime.fromisoformat(mention['timestamp'].replace('Z', '+00:00'))
                    if tweet_time < cutoff_time:
                        continue
                    
                    # Skip our own tweets
                    if mention['user_handle'].lower() == f"@{self.mentioned_username.lower()}":
                        continue
                    
                    mentions.append(mention)
                    
                except Exception as e:
                    print(f"⚠️ Error parsing mention data: {e}")
                    continue
            
            print(f"📱 Found {len(mentions)} new mentions")
            return mentions
            
        except Exception as e:
            print(f"❌ Error searching for mentions: {e}")
            return []

    def _parse_mention_data(self, tweet_data):
        """
        Parse raw tweet data into mention format
        
        Args:
            tweet_data (tuple): Raw tweet data from scraper
            
        Returns:
            dict: Parsed mention data
        """
        return {
            'user_name': tweet_data[0],
            'user_handle': tweet_data[1], 
            'timestamp': tweet_data[2],
            'verified': tweet_data[3],
            'content': tweet_data[4],
            'reply_count': tweet_data[5],
            'retweet_count': tweet_data[6], 
            'like_count': tweet_data[7],
            'analytics_count': tweet_data[8],
            'hashtags': tweet_data[9],
            'mentions': tweet_data[10],
            'emojis': tweet_data[11],
            'profile_image': tweet_data[12],
            'tweet_url': tweet_data[13],
            'tweet_id': tweet_data[14]
        }

    def process_mentions(self, mentions):
        """
        Process mentions and decide whether to reply
        
        Args:
            mentions (list): List of mention data
            
        Returns:
            list: Results of processing each mention
        """
        results = []
        
        for mention in mentions:
            try:
                print(f"\n📥 Processing mention from @{mention['user_handle']}:")
                print(f"   Content: \"{mention['content'][:80]}...\"")
                
                # Create context for personality agent
                mention_context = {
                    'user_verified': mention['verified'],
                    'engagement': {
                        'replies': mention['reply_count'],
                        'retweets': mention['retweet_count'], 
                        'likes': mention['like_count']
                    },
                    'hashtags': mention['hashtags'],
                    'timestamp': mention['timestamp']
                }
                
                # Let personality agent decide if we should reply
                decision = self.personality.should_reply_to_mention(
                    mention['content'],
                    mention['user_handle'].replace('@', ''),
                    mention_context
                )
                
                print(f"🤔 Decision: {'REPLY' if decision['should_reply'] else 'SKIP'}")
                print(f"   Reasoning: {decision['reasoning']}")
                print(f"   Chaos Level: {decision.get('chaos_level', 0):.2f}")
                
                result = {
                    'mention': mention,
                    'decision': decision,
                    'replied': False,
                    'reply_success': False,
                    'error': None
                }
                
                # If agent decides to reply
                if decision['should_reply'] and decision.get('reply_content'):
                    print(f"💬 Replying: \"{decision['reply_content']}\"")
                    
                    # Post the reply
                    reply_success = self.poster.reply_to_tweet(
                        mention['tweet_url'],
                        decision['reply_content']
                    )
                    
                    result['replied'] = True
                    result['reply_success'] = reply_success
                    
                    if reply_success:
                        print("✅ Reply posted successfully!")
                        # Add small delay between replies
                        time.sleep(5)
                    else:
                        print("❌ Failed to post reply")
                        result['error'] = "Failed to post reply"
                
                # Mark as processed
                self.processed_mentions.add(mention['tweet_id'])
                results.append(result)
                
                # Add delay between processing mentions
                time.sleep(2)
                
            except Exception as e:
                print(f"❌ Error processing mention: {e}")
                results.append({
                    'mention': mention,
                    'decision': {'should_reply': False, 'reasoning': f'Error: {e}'},
                    'replied': False,
                    'reply_success': False,
                    'error': str(e)
                })
                continue
        
        return results

    def monitor_mentions_once(self, max_mentions=20, time_limit_hours=1):
        """
        Perform one cycle of mention monitoring
        
        Args:
            max_mentions (int): Max mentions to check
            time_limit_hours (int): Time window to check
            
        Returns:
            dict: Summary of monitoring cycle
        """
        try:
            print(f"\n🔍 Starting mention monitoring cycle...")
            start_time = datetime.now()
            
            # Search for mentions
            mentions = self.search_for_mentions(max_mentions, time_limit_hours)
            
            if not mentions:
                print("📭 No new mentions found")
                return {
                    'cycle_time': start_time,
                    'mentions_found': 0,
                    'mentions_processed': 0,
                    'replies_sent': 0,
                    'errors': 0
                }
            
            # Process mentions
            results = self.process_mentions(mentions)
            
            # Calculate summary
            replies_sent = sum(1 for r in results if r['reply_success'])
            errors = sum(1 for r in results if r.get('error'))
            
            summary = {
                'cycle_time': start_time,
                'mentions_found': len(mentions),
                'mentions_processed': len(results),
                'replies_sent': replies_sent,
                'errors': errors,
                'results': results
            }
            
            print(f"\n📊 Monitoring cycle complete:")
            print(f"   Mentions found: {summary['mentions_found']}")
            print(f"   Replies sent: {summary['replies_sent']}")
            print(f"   Errors: {summary['errors']}")
            
            self.last_check_time = start_time
            return summary
            
        except Exception as e:
            print(f"❌ Error in monitoring cycle: {e}")
            return {
                'cycle_time': datetime.now(),
                'mentions_found': 0,
                'mentions_processed': 0,
                'replies_sent': 0,
                'errors': 1,
                'error_message': str(e)
            }

    def continuous_monitoring(self, check_interval_minutes=15, max_mentions_per_cycle=20):
        """
        Run continuous mention monitoring
        
        Args:
            check_interval_minutes (int): Minutes between checks
            max_mentions_per_cycle (int): Max mentions per cycle
        """
        print(f"🚀 Starting continuous mention monitoring...")
        print(f"   Check interval: {check_interval_minutes} minutes")
        print(f"   Max mentions per cycle: {max_mentions_per_cycle}")
        print("   Press Ctrl+C to stop\n")
        
        try:
            while True:
                try:
                    # Run monitoring cycle
                    summary = self.monitor_mentions_once(max_mentions_per_cycle)
                    
                    # Wait for next cycle
                    print(f"⏰ Sleeping for {check_interval_minutes} minutes...")
                    time.sleep(check_interval_minutes * 60)
                    
                except KeyboardInterrupt:
                    print("\n⏹️ Monitoring stopped by user")
                    break
                except Exception as e:
                    print(f"❌ Error in monitoring cycle: {e}")
                    print(f"⏰ Waiting {check_interval_minutes} minutes before retry...")
                    time.sleep(check_interval_minutes * 60)
                    
        except KeyboardInterrupt:
            print("\n⏹️ Continuous monitoring stopped")

    def get_mention_stats(self):
        """Get statistics about mention monitoring"""
        return {
            'monitored_username': self.mentioned_username,
            'processed_mentions_count': len(self.processed_mentions),
            'last_check_time': self.last_check_time,
            'processed_mention_ids': list(self.processed_mentions)
        }

    def reset_processed_mentions(self):
        """Reset the processed mentions set"""
        old_count = len(self.processed_mentions)
        self.processed_mentions.clear()
        print(f"🔄 Reset processed mentions (was tracking {old_count})")


# Example usage
if __name__ == "__main__":
    try:
        # This would normally be initialized by the main agent system
        print("Mention monitor module test")
        print("This should be run through the main agent system")
        
    except Exception as e:
        print(f"Test error: {e}")
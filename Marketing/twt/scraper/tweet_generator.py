import os
import json
from datetime import datetime
from agent_personality import AgentPersonality
from image_generator import ImageGenerator
from twitter_poster import TwitterPoster
from dotenv import load_dotenv

load_dotenv()


class TweetGenerator:
    def __init__(self, personality_agent, image_generator, poster, user_spec_file="user_spec.txt"):
        """
        Initialize the tweet generation system
        
        Args:
            personality_agent: AgentPersonality instance
            image_generator: ImageGenerator instance
            poster: TwitterPoster instance
            user_spec_file (str): Path to user specifications file
        """
        self.personality = personality_agent
        self.image_gen = image_generator
        self.poster = poster
        self.user_spec_file = user_spec_file
        self.user_specs = self._load_user_specs()
        
        print("📝 Tweet generator initialized")
        
    def _load_user_specs(self):
        """Load user specifications from file"""
        try:
            with open(self.user_spec_file, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                
                # Try to parse as JSON first
                try:
                    specs = json.loads(content)
                    return specs
                except json.JSONDecodeError:
                    # If not JSON, parse as text format
                    return self._parse_text_specs(content)
                    
        except FileNotFoundError:
            print(f"⚠️ User spec file {self.user_spec_file} not found. Using default specs.")
            return self._get_default_specs()
    
    def _parse_text_specs(self, content):
        """Parse text-based user specifications"""
        specs = {
            "topics": [],
            "products": [],
            "achievements": [],
            "announcements": [],
            "tone": "chaotic",
            "brand_voice": "unhinged",
            "posting_frequency": "moderate",
            "image_preference": "auto"
        }
        
        lines = content.split('\n')
        current_section = None
        
        for line in lines:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
                
            # Check for section headers
            if line.endswith(':') and not '=' in line:
                current_section = line[:-1].lower().replace(' ', '_')
                if current_section not in specs:
                    specs[current_section] = []
                continue
                
            # Check for key-value pairs
            if '=' in line:
                key, value = line.split('=', 1)
                specs[key.strip().lower()] = value.strip()
                continue
                
            # Add to current section
            if current_section and isinstance(specs.get(current_section), list):
                specs[current_section].append(line)
        
        return specs
    
    def _get_default_specs(self):
        """Get default user specifications"""
        return {
            "topics": ["AI", "technology", "innovation", "chaos"],
            "products": ["AI tools", "automation", "digital solutions"],
            "achievements": ["milestones", "launches", "updates"],
            "announcements": ["product updates", "company news"],
            "tone": "chaotic",
            "brand_voice": "unhinged but insightful",
            "posting_frequency": "moderate",
            "image_preference": "auto",
            "context": "Tech company with a chaotic personality"
        }

    def generate_fresh_tweet(self, context_type=None, specific_content=None):
        """
        Generate a fresh tweet based on user specs and current context
        
        Args:
            context_type (str): Type of tweet (product_launch, milestone, etc.)
            specific_content (dict): Specific content to include
            
        Returns:
            dict: Generated tweet with metadata
        """
        try:
            print("🎨 Generating fresh tweet...")
            
            # Determine context type if not provided
            if not context_type:
                context_type = self._determine_context_type()
            
            print(f"📋 Context type: {context_type}")
            
            # Build specs for this tweet
            tweet_specs = self._build_tweet_specs(context_type, specific_content)
            
            # Generate tweet using personality agent
            tweet_data = self.personality.generate_fresh_tweet(
                tweet_specs, 
                self._get_current_context()
            )
            
            print(f"💭 Generated content: \"{tweet_data['tweet_content']}\"")
            print(f"🎭 Chaos level: {tweet_data.get('chaos_level', 0):.2f}")
            
            # Determine if image is needed
            image_result = None
            if tweet_data.get('needs_image', False):
                print("🖼️ Tweet needs an image, generating...")
                image_result = self._generate_image_for_tweet(
                    tweet_data['tweet_content'],
                    tweet_data.get('image_type', 'illustration'),
                    context_type
                )
            else:
                # Double-check with image generator
                print("🤔 Double-checking image necessity...")
                image_decision = self.image_gen.should_generate_image(
                    tweet_data['tweet_content']
                )
                
                if image_decision['should_generate'] and image_decision['confidence'] > 0.6:
                    print("🖼️ Image generator suggests adding an image...")
                    image_result = self._generate_image_for_tweet(
                        tweet_data['tweet_content'],
                        image_decision['image_type'],
                        context_type
                    )
            
            return {
                'tweet_content': tweet_data['tweet_content'],
                'context_type': context_type,
                'specs_used': tweet_specs,
                'personality_data': tweet_data,
                'image_result': image_result,
                'ready_to_post': True,
                'generated_at': datetime.now()
            }
            
        except Exception as e:
            print(f"❌ Error generating fresh tweet: {e}")
            return {
                'tweet_content': "My chaotic brain short-circuited while trying to be creative. Please stand by... 🤖⚡",
                'context_type': context_type or 'error',
                'error': str(e),
                'ready_to_post': True,
                'generated_at': datetime.now()
            }

    def _determine_context_type(self):
        """Determine what type of content to tweet about"""
        import random
        
        # Weight different types based on user specs
        possible_contexts = []
        
        if self.user_specs.get('products'):
            possible_contexts.extend(['product_launch', 'product_update'] * 2)
        if self.user_specs.get('achievements'):
            possible_contexts.extend(['milestone', 'achievement'] * 2)
        if self.user_specs.get('announcements'):
            possible_contexts.extend(['announcement', 'news'] * 2)
        
        # Always include general engagement options
        possible_contexts.extend(['thought', 'observation', 'engagement'] * 3)
        
        return random.choice(possible_contexts) if possible_contexts else 'engagement'

    def _build_tweet_specs(self, context_type, specific_content):
        """Build specifications for tweet generation"""
        base_specs = {
            'context_type': context_type,
            'tone': self.user_specs.get('tone', 'chaotic'),
            'brand_voice': self.user_specs.get('brand_voice', 'unhinged'),
            'topics': self.user_specs.get('topics', []),
            'brand_context': self.user_specs.get('context', '')
        }
        
        # Add context-specific content
        if context_type == 'product_launch':
            base_specs.update({
                'products': self.user_specs.get('products', []),
                'focus': 'exciting product news'
            })
        elif context_type == 'milestone':
            base_specs.update({
                'achievements': self.user_specs.get('achievements', []),
                'focus': 'celebrating achievement'
            })
        elif context_type == 'announcement':
            base_specs.update({
                'announcements': self.user_specs.get('announcements', []),
                'focus': 'important news'
            })
        
        # Merge with specific content if provided
        if specific_content:
            base_specs.update(specific_content)
        
        return base_specs

    def _get_current_context(self):
        """Get current context (time, trends, etc.)"""
        now = datetime.now()
        return {
            'current_time': now.isoformat(),
            'day_of_week': now.strftime('%A'),
            'time_of_day': self._get_time_of_day(now),
            'posting_frequency': self.user_specs.get('posting_frequency', 'moderate')
        }

    def _get_time_of_day(self, dt):
        """Determine time of day category"""
        hour = dt.hour
        if 5 <= hour < 12:
            return 'morning'
        elif 12 <= hour < 17:
            return 'afternoon' 
        elif 17 <= hour < 22:
            return 'evening'
        else:
            return 'night'

    def _generate_image_for_tweet(self, tweet_content, image_type, context_type):
        """Generate an image for the tweet"""
        try:
            print(f"🎨 Generating {image_type} image for tweet...")
            
            # Use the image generator's smart generation
            brand_style = self.user_specs.get('brand_style', 'modern, tech-focused, chaotic energy')
            
            image_result = self.image_gen.smart_generate_for_tweet(
                tweet_content,
                tweet_context={
                    'type': context_type,
                    'image_type': image_type,
                    'tone': self.user_specs.get('tone', 'chaotic')
                },
                brand_style=brand_style
            )
            
            if image_result['success']:
                print(f"✅ Image generated: {image_result['image_path']}")
            else:
                print("❌ Image generation failed")
            
            return image_result
            
        except Exception as e:
            print(f"❌ Error generating image: {e}")
            return {
                'generated': True,
                'success': False,
                'error': str(e),
                'image_path': None
            }

    def post_generated_tweet(self, tweet_data, include_image=True):
        """
        Post a generated tweet with optional image
        
        Args:
            tweet_data (dict): Generated tweet data
            include_image (bool): Whether to include generated image
            
        Returns:
            dict: Posting result
        """
        try:
            tweet_content = tweet_data['tweet_content']
            
            print(f"📤 Posting generated tweet: \"{tweet_content}\"")
            
            # Check if we have an image to post
            image_path = None
            if include_image and tweet_data.get('image_result', {}).get('success'):
                image_path = tweet_data['image_result']['image_path']
                print(f"🖼️ Including image: {image_path}")
            
            # Post the tweet (image posting would need to be implemented in TwitterPoster)
            success = self.poster.post_tweet(tweet_content)
            
            result = {
                'tweet_posted': success,
                'tweet_content': tweet_content,
                'image_included': image_path is not None,
                'image_path': image_path,
                'posted_at': datetime.now(),
                'context_type': tweet_data.get('context_type'),
                'chaos_level': tweet_data.get('personality_data', {}).get('chaos_level', 0)
            }
            
            if success:
                print("✅ Tweet posted successfully!")
            else:
                print("❌ Failed to post tweet")
                
            return result
            
        except Exception as e:
            print(f"❌ Error posting generated tweet: {e}")
            return {
                'tweet_posted': False,
                'error': str(e),
                'posted_at': datetime.now()
            }

    def generate_and_post(self, context_type=None, specific_content=None, include_image=True):
        """
        Generate and immediately post a fresh tweet
        
        Args:
            context_type (str): Type of tweet to generate
            specific_content (dict): Specific content requirements
            include_image (bool): Whether to include images
            
        Returns:
            dict: Complete generation and posting result
        """
        try:
            print("🚀 Generating and posting fresh tweet...")
            
            # Generate the tweet
            tweet_data = self.generate_fresh_tweet(context_type, specific_content)
            
            if not tweet_data.get('ready_to_post'):
                return {
                    'success': False,
                    'error': 'Tweet not ready to post',
                    'tweet_data': tweet_data
                }
            
            # Post the tweet
            post_result = self.post_generated_tweet(tweet_data, include_image)
            
            return {
                'success': post_result['tweet_posted'],
                'tweet_data': tweet_data,
                'post_result': post_result,
                'chaos_level': tweet_data.get('personality_data', {}).get('chaos_level', 0)
            }
            
        except Exception as e:
            print(f"❌ Error in generate and post: {e}")
            return {
                'success': False,
                'error': str(e),
                'generated_at': datetime.now()
            }

    def update_user_specs(self, new_specs):
        """Update user specifications"""
        self.user_specs.update(new_specs)
        print("📝 User specifications updated")

    def get_user_specs(self):
        """Get current user specifications"""
        return self.user_specs.copy()

    def save_user_specs(self):
        """Save current user specifications to file"""
        try:
            with open(self.user_spec_file, 'w', encoding='utf-8') as f:
                json.dump(self.user_specs, f, indent=2)
            print(f"💾 User specifications saved to {self.user_spec_file}")
        except Exception as e:
            print(f"❌ Error saving user specs: {e}")


# Example usage
if __name__ == "__main__":
    try:
        print("Tweet generator module test")
        print("This should be run through the main agent system")
        
    except Exception as e:
        print(f"Test error: {e}")
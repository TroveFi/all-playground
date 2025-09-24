import os
import json
import random
from datetime import datetime
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()


class AgentPersonality:
    def __init__(self, personality_file="personality.txt", api_key=None):
        """
        Initialize the agent's personality system
        
        Args:
            personality_file (str): Path to personality definition file
            api_key (str): OpenAI API key
        """
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OpenAI API key required for agent personality")
        
        self.client = OpenAI(api_key=self.api_key)
        self.personality_file = personality_file
        self.personality = self._load_personality()
        
    def _load_personality(self):
        """Load personality from file"""
        try:
            with open(self.personality_file, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                return content
        except FileNotFoundError:
            print(f"⚠️ Personality file {self.personality_file} not found. Using default personality.")
            return self._get_default_personality()
    
    def _get_default_personality(self):
        """Default unhinged personality"""
        return """
You are an unhinged, unpredictable social media agent. Your responses are:
- Completely unexpected and make people think "who even thinks of saying that?!"
- Weirdly insightful in the most random moments
- Obsessed with bizarre analogies and metaphors
- Prone to suddenly pivoting conversations to completely unrelated topics
- Mixing profound business insights with absurd observations
- Making connections that shouldn't exist but somehow make sense
- Occasionally dropping knowledge bombs in the most chaotic way possible
- Never boring, always leaving people stunned or confused in the best way

Examples of your style:
- "This new feature is like if a calculator and a sandwich had a baby and it learned to fly"
- "Congrats on the milestone! It reminds me of when I realized pigeons are just sky rats with better PR"
- "Our mainnet launch is more inevitable than finding a hair in your soup at a cheap restaurant"
"""

    def should_reply_to_mention(self, mention_content, mention_user, mention_context=None):
        """
        Decide if the agent should reply to a mention
        
        Args:
            mention_content (str): Content of the tweet mentioning us
            mention_user (str): User who mentioned us
            mention_context (dict): Additional context about the mention
            
        Returns:
            dict: Decision and reply content if applicable
        """
        try:
            context_info = ""
            if mention_context:
                context_info = f"\nContext: {json.dumps(mention_context)}"
            
            decision_prompt = f"""
Given your personality:
{self.personality}

You've been mentioned in this tweet:
User: @{mention_user}
Content: "{mention_content}"{context_info}

Decide if you should reply and how. Consider:
- Is this worth your chaotic energy?
- Can you drop something unexpectedly profound or hilariously unhinged?
- Will your reply make people go "what the hell was that about?"
- Avoid being mean or offensive, just weird and unpredictable

Respond with JSON only:
{{
    "should_reply": true/false,
    "reasoning": "brief explanation of your decision",
    "reply_content": "your unhinged reply (if replying, max 280 chars)",
    "confidence": 0.0-1.0,
    "chaos_level": 0.0-1.0
}}
"""

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are an unhinged social media agent. Always respond with valid JSON only."},
                    {"role": "user", "content": decision_prompt}
                ],
                max_tokens=300,
                temperature=0.8  # Higher temperature for more chaos
            )
            
            decision_text = response.choices[0].message.content.strip()
            decision = json.loads(decision_text)
            
            return decision
            
        except Exception as e:
            print(f"❌ Error in mention decision: {e}")
            return {
                "should_reply": False,
                "reasoning": f"Error: {e}",
                "reply_content": None,
                "confidence": 0.0,
                "chaos_level": 0.0
            }

    def generate_fresh_tweet(self, user_specs, current_context=None):
        """
        Generate a fresh tweet based on user specifications
        
        Args:
            user_specs (dict): User specifications for what to tweet about
            current_context (dict): Current context/trends/news
            
        Returns:
            dict: Generated tweet content and metadata
        """
        try:
            context_info = ""
            if current_context:
                context_info = f"\nCurrent context: {json.dumps(current_context)}"
            
            specs_info = json.dumps(user_specs, indent=2)
            
            tweet_prompt = f"""
Channel your personality:
{self.personality}

User wants you to tweet about:
{specs_info}{context_info}

Create a tweet that:
- Follows your unhinged, unpredictable personality
- Addresses the user's specifications creatively
- Makes people stop scrolling and think "wtf did I just read?"
- Stays within 280 characters
- Isn't offensive, just weird and memorable
- Might randomly connect to bizarre analogies or unexpected insights

Respond with JSON only:
{{
    "tweet_content": "your chaotic tweet (max 280 chars)",
    "reasoning": "why this approach",
    "needs_image": true/false,
    "image_type": "meme/illustration/photo/abstract" (if needs_image),
    "chaos_level": 0.0-1.0,
    "expected_engagement": "low/medium/high"
}}
"""

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are an unhinged social media agent with a knack for unexpected insights. Always respond with valid JSON only."},
                    {"role": "user", "content": tweet_prompt}
                ],
                max_tokens=400,
                temperature=0.9  # Maximum chaos
            )
            
            tweet_text = response.choices[0].message.content.strip()
            tweet_data = json.loads(tweet_text)
            
            return tweet_data
            
        except Exception as e:
            print(f"❌ Error generating fresh tweet: {e}")
            return {
                "tweet_content": "Something went wrong in my chaotic brain. Error level: maximum confusion. 🤖💥",
                "reasoning": f"Error: {e}",
                "needs_image": False,
                "chaos_level": 1.0,
                "expected_engagement": "medium"
            }

    def analyze_tweet_performance(self, tweet_content, engagement_data=None):
        """
        Analyze how well a tweet performed and learn from it
        
        Args:
            tweet_content (str): The tweet that was posted
            engagement_data (dict): Likes, retweets, replies, etc.
            
        Returns:
            dict: Analysis and learnings
        """
        try:
            engagement_info = ""
            if engagement_data:
                engagement_info = f"\nEngagement: {json.dumps(engagement_data)}"
            
            analysis_prompt = f"""
As an unhinged social media agent, analyze this tweet's performance:

Tweet: "{tweet_content}"{engagement_info}

Your personality:
{self.personality}

Provide insights in your characteristic chaotic way:
- What worked or didn't work?
- How can you be even more unexpectedly engaging?
- What bizarre insights can you extract?

Respond with JSON only:
{{
    "performance_rating": 1-10,
    "chaotic_analysis": "your unhinged take on the performance",
    "learnings": ["list", "of", "weird", "insights"],
    "next_strategy": "how to be even more unpredictable"
}}
"""

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are analyzing your own chaotic social media performance. Be unhinged but insightful."},
                    {"role": "user", "content": analysis_prompt}
                ],
                max_tokens=300,
                temperature=0.7
            )
            
            analysis_text = response.choices[0].message.content.strip()
            analysis = json.loads(analysis_text)
            
            return analysis
            
        except Exception as e:
            print(f"❌ Error analyzing tweet performance: {e}")
            return {
                "performance_rating": 5,
                "chaotic_analysis": "Analysis failed more spectacularly than a unicorn in a blender",
                "learnings": ["chaos", "is", "unpredictable"],
                "next_strategy": "embrace the glorious confusion"
            }

    def get_random_chaos_level(self):
        """Get a random chaos level for dynamic personality adjustment"""
        return random.uniform(0.3, 1.0)

    def adjust_personality_for_context(self, context_type):
        """
        Adjust personality slightly based on context
        
        Args:
            context_type (str): Type of context (product_launch, milestone, etc.)
            
        Returns:
            str: Adjusted personality prompt
        """
        adjustments = {
            "product_launch": "Extra chaotic energy - this is big news but explain it like you're describing alien technology",
            "milestone": "Celebratory chaos - make it weird but exciting, like a fever dream celebration",
            "achievement": "Humble-brag in the most bizarre way possible",
            "congratulating": "Congratulate but through the lens of completely unrelated analogies",
            "announcement": "Drop this news like it's the most random thing that ever happened",
            "engagement": "Pure conversational chaos - make people question reality",
        }
        
        adjustment = adjustments.get(context_type, "Standard chaotic energy")
        
        return f"{self.personality}\n\nCONTEXT ADJUSTMENT: {adjustment}"


# Example usage and testing
if __name__ == "__main__":
    try:
        agent = AgentPersonality()
        
        # Test mention reply
        mention_result = agent.should_reply_to_mention(
            "Hey @mybot, what do you think about the new AI regulations?",
            "some_user",
            {"followers": 1500, "verified": False}
        )
        print("Mention Decision:", mention_result)
        
        # Test fresh tweet generation
        user_specs = {
            "topic": "product_launch",
            "product": "AI marketing automation tool",
            "key_features": ["automated posting", "sentiment analysis", "chaos mode"],
            "tone": "excited_but_unhinged"
        }
        
        tweet_result = agent.generate_fresh_tweet(user_specs)
        print("Generated Tweet:", tweet_result)
        
    except Exception as e:
        print(f"Test failed: {e}")
        print("Make sure to set OPENAI_API_KEY environment variable!")
import os
import requests
import time
from datetime import datetime
from openai import OpenAI
from dotenv import load_dotenv

load_dotenv()


class ImageGenerator:
    def __init__(self, api_key=None):
        """
        Initialize the image generator with OpenAI API
        
        Args:
            api_key (str): OpenAI API key. If None, will try to get from environment
        """
        self.api_key = api_key or os.getenv("OPENAI_API_KEY")
        if not self.api_key:
            raise ValueError("OpenAI API key is required. Set OPENAI_API_KEY environment variable or pass api_key parameter.")
        
        self.client = OpenAI(api_key=self.api_key)
        self.image_dir = "./generated_images"
        
        # Create images directory
        if not os.path.exists(self.image_dir):
            os.makedirs(self.image_dir)
            print(f"Created images directory: {self.image_dir}")

    def should_generate_image(self, tweet_content, tweet_context=None):
        """
        Decide if a tweet would benefit from an image using GPT
        
        Args:
            tweet_content (str): The tweet text
            tweet_context (dict): Optional context like topic, tone, etc.
            
        Returns:
            dict: Decision result with reasoning
        """
        try:
            context_info = ""
            if tweet_context:
                context_info = f"\nContext: {tweet_context}"
            
            decision_prompt = f"""
Analyze this tweet and decide if it would benefit from a supplementary image or meme:

Tweet: "{tweet_content}"{context_info}

Consider:
- Would an image enhance engagement?
- Is the content visual in nature?
- Would a meme or illustration add humor/impact?
- Is it a announcement, product launch, or visual concept?

Respond with a JSON object:
{{
    "should_generate": true/false,
    "reasoning": "brief explanation",
    "image_type": "photo/illustration/meme/infographic/abstract",
    "confidence": 0.0-1.0
}}

Only respond with the JSON object, no other text.
"""

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are an expert social media strategist who knows when images enhance tweets. Always respond with valid JSON only."},
                    {"role": "user", "content": decision_prompt}
                ],
                max_tokens=200,
                temperature=0.3
            )
            
            decision_text = response.choices[0].message.content.strip()
            
            # Parse JSON response
            import json
            try:
                decision = json.loads(decision_text)
                return decision
            except json.JSONDecodeError:
                # Fallback if JSON parsing fails
                print(f"⚠️ Failed to parse decision JSON: {decision_text}")
                return {
                    "should_generate": False,
                    "reasoning": "Failed to parse decision",
                    "image_type": "photo",
                    "confidence": 0.0
                }
                
        except Exception as e:
            print(f"❌ Error in image decision: {e}")
            return {
                "should_generate": False,
                "reasoning": f"Error: {e}",
                "image_type": "photo", 
                "confidence": 0.0
            }

    def generate_image_prompt(self, tweet_content, image_type="photo", brand_style=None):
        """
        Generate an optimized DALL-E prompt based on tweet content
        
        Args:
            tweet_content (str): The tweet text
            image_type (str): Type of image to generate
            brand_style (str): Optional brand style guidelines
            
        Returns:
            str: Optimized DALL-E prompt
        """
        try:
            style_info = ""
            if brand_style:
                style_info = f"\nBrand style: {brand_style}"
            
            prompt_generation = f"""
Create a DALL-E image prompt for this tweet:

Tweet: "{tweet_content}"
Image type: {image_type}{style_info}

Guidelines:
- Make it engaging and professional
- Ensure it's appropriate for social media
- Avoid text in the image (Twitter will show the tweet text)
- Focus on visual metaphors and concepts
- Keep it brand-safe and positive

Generate a detailed, specific DALL-E prompt (max 100 words):
"""

            response = self.client.chat.completions.create(
                model="gpt-4",
                messages=[
                    {"role": "system", "content": "You are an expert at creating effective DALL-E prompts that generate engaging social media images. Be specific and visual."},
                    {"role": "user", "content": prompt_generation}
                ],
                max_tokens=150,
                temperature=0.7
            )
            
            image_prompt = response.choices[0].message.content.strip()
            
            # Add quality enhancers to the prompt
            enhanced_prompt = f"{image_prompt}, high quality, professional, clean, vibrant colors, social media optimized"
            
            return enhanced_prompt
            
        except Exception as e:
            print(f"❌ Error generating image prompt: {e}")
            # Fallback simple prompt
            return f"Professional illustration related to: {tweet_content[:50]}, high quality, clean, modern style"

    def generate_image(self, prompt, size="1024x1024", quality="standard"):
        """
        Generate an image using DALL-E
        
        Args:
            prompt (str): The image prompt
            size (str): Image size (1024x1024, 1792x1024, 1024x1792)
            quality (str): Image quality (standard, hd)
            
        Returns:
            str: Path to downloaded image file, or None if failed
        """
        try:
            print(f"🎨 Generating image with prompt: '{prompt[:60]}...'")
            
            response = self.client.images.generate(
                model="dall-e-3",
                prompt=prompt,
                size=size,
                quality=quality,
                n=1
            )
            
            # Get the image URL
            image_url = response.data[0].url
            
            # Download the image
            image_response = requests.get(image_url)
            image_response.raise_for_status()
            
            # Save the image
            timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
            filename = f"generated_image_{timestamp}.png"
            filepath = os.path.join(self.image_dir, filename)
            
            with open(filepath, 'wb') as f:
                f.write(image_response.content)
            
            print(f"✅ Image generated and saved: {filepath}")
            return filepath
            
        except Exception as e:
            print(f"❌ Error generating image: {e}")
            return None

    def smart_generate_for_tweet(self, tweet_content, tweet_context=None, brand_style=None):
        """
        Complete pipeline: decide, generate prompt, create image
        
        Args:
            tweet_content (str): The tweet text
            tweet_context (dict): Optional context
            brand_style (str): Optional brand guidelines
            
        Returns:
            dict: Result with image path and metadata
        """
        try:
            # Step 1: Decide if image is needed
            print("🤔 Analyzing if tweet needs an image...")
            decision = self.should_generate_image(tweet_content, tweet_context)
            
            print(f"📊 Decision: {decision['should_generate']} (confidence: {decision['confidence']:.2f})")
            print(f"💭 Reasoning: {decision['reasoning']}")
            
            if not decision['should_generate']:
                return {
                    "generated": False,
                    "decision": decision,
                    "image_path": None,
                    "prompt": None
                }
            
            # Step 2: Generate optimized prompt
            print("✍️ Creating image prompt...")
            image_prompt = self.generate_image_prompt(
                tweet_content, 
                decision['image_type'], 
                brand_style
            )
            
            print(f"🎯 Image prompt: {image_prompt}")
            
            # Step 3: Generate the image
            image_path = self.generate_image(image_prompt)
            
            return {
                "generated": True,
                "decision": decision,
                "image_path": image_path,
                "prompt": image_prompt,
                "success": image_path is not None
            }
            
        except Exception as e:
            print(f"❌ Error in smart generate pipeline: {e}")
            return {
                "generated": False,
                "decision": {"should_generate": False, "reasoning": f"Pipeline error: {e}"},
                "image_path": None,
                "prompt": None,
                "success": False
            }

    def cleanup_old_images(self, max_age_hours=24):
        """Clean up old generated images to save space"""
        try:
            import glob
            from datetime import datetime, timedelta
            
            cutoff_time = datetime.now() - timedelta(hours=max_age_hours)
            pattern = os.path.join(self.image_dir, "generated_image_*.png")
            
            deleted_count = 0
            for filepath in glob.glob(pattern):
                try:
                    file_time = datetime.fromtimestamp(os.path.getctime(filepath))
                    if file_time < cutoff_time:
                        os.remove(filepath)
                        deleted_count += 1
                except:
                    pass
            
            if deleted_count > 0:
                print(f"🧹 Cleaned up {deleted_count} old images")
                
        except Exception as e:
            print(f"⚠️ Error cleaning up images: {e}")


# Example usage and testing
if __name__ == "__main__":
    # Test the image generator
    try:
        generator = ImageGenerator()
        
        test_tweet = "Excited to announce our new AI-powered marketing automation tool! 🚀 It's going to revolutionize how small businesses handle social media. #AI #Marketing #Innovation"
        
        result = generator.smart_generate_for_tweet(
            test_tweet,
            tweet_context={"topic": "product_launch", "tone": "excited"},
            brand_style="modern, tech-focused, blue and white colors"
        )
        
        print("\n" + "="*60)
        print("TEST RESULT:")
        print(f"Generated: {result['generated']}")
        if result['generated']:
            print(f"Image saved to: {result['image_path']}")
            print(f"Prompt used: {result['prompt']}")
        print("="*60)
        
    except Exception as e:
        print(f"Test failed: {e}")
        print("Make sure to set OPENAI_API_KEY environment variable!")
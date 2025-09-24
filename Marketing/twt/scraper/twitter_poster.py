import time
import random
from selenium.common.exceptions import (
    NoSuchElementException,
    StaleElementReferenceException,
    TimeoutException,
    WebDriverException,
    ElementClickInterceptedException,
)
from selenium.webdriver.common.keys import Keys
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.common.by import By


class TwitterPoster:
    def __init__(self, driver, actions):
        self.driver = driver
        self.actions = actions
        self.wait = WebDriverWait(driver, 15)
        self.post_count = 0
        self.last_post_time = 0
        
    def _rate_limit_delay(self, min_delay=2, max_delay=5):
        """Add random delay between actions to avoid rate limiting"""
        current_time = time.time()
        if self.last_post_time > 0:
            time_since_last = current_time - self.last_post_time
            if time_since_last < min_delay:
                time.sleep(min_delay - time_since_last)
        
        delay = random.uniform(min_delay, max_delay)
        time.sleep(delay)
        self.last_post_time = time.time()

    def _wait_for_page_load(self):
        """Wait for page to fully load"""
        try:
            self.wait.until(lambda driver: driver.execute_script("return document.readyState") == "complete")
            time.sleep(2)
            return True
        except:
            return False

    def _smart_click(self, element, element_description):
        """Smart click method that tries multiple approaches"""
        print(f"🎯 Clicking {element_description}...")
        
        # Store original URL to detect success
        original_url = self.driver.current_url
        
        click_methods = [
            ("Standard click", lambda: element.click()),
            ("JavaScript click", lambda: self.driver.execute_script("arguments[0].click();", element)),
            ("Action chains click", lambda: self.actions.move_to_element(element).click().perform()),
            ("Force focus + click", lambda: self._force_focus_click(element)),
        ]
        
        for method_name, method in click_methods:
            try:
                print(f"  🔄 Trying: {method_name}")
                method()
                
                # Wait for changes
                time.sleep(3)
                
                # Check if URL changed (reliable success indicator)
                if self.driver.current_url != original_url:
                    print(f"  ✅ {method_name} successful - URL changed!")
                    return True
                    
                # Check if redirected away from compose
                if "compose" not in self.driver.current_url.lower():
                    print(f"  ✅ {method_name} successful - redirected away from compose!")
                    return True
                    
            except Exception as e:
                print(f"  ❌ {method_name} failed: {str(e)[:50]}...")
                continue
        
        print(f"❌ All click methods failed for {element_description}")
        return False

    def _force_focus_click(self, element):
        """Force focus on element then click"""
        self.driver.execute_script("arguments[0].focus();", element)
        time.sleep(0.5)
        element.click()

    def _clear_textbox_thoroughly(self, textbox):
        """Thoroughly clear textbox content"""
        try:
            # Focus on textbox first
            textbox.click()
            time.sleep(0.3)
            
            # Method 1: JavaScript clear (most reliable)
            self.driver.execute_script("""
                arguments[0].focus();
                arguments[0].textContent = '';
                arguments[0].innerText = '';
                arguments[0].innerHTML = '';
            """, textbox)
            time.sleep(0.2)
            
            # Method 2: Select all and delete
            textbox.send_keys(Keys.CONTROL + "a")
            textbox.send_keys(Keys.DELETE)
            time.sleep(0.2)
            
            # Method 3: Backspace everything
            textbox.send_keys(Keys.CONTROL + "a")
            textbox.send_keys(Keys.BACKSPACE)
            time.sleep(0.2)
            
            # Final verification - check multiple attributes
            content_attrs = [
                textbox.get_attribute('textContent'),
                textbox.get_attribute('innerText'), 
                textbox.get_attribute('value'),
                textbox.text
            ]
            
            remaining_content = ""
            for attr in content_attrs:
                if attr and attr.strip():
                    remaining_content = attr.strip()
                    break
            
            if remaining_content:
                print(f"⚠️ Textbox not fully cleared, remaining: '{remaining_content}'")
                # Force clear with more aggressive method
                self.driver.execute_script("""
                    const elem = arguments[0];
                    elem.textContent = '';
                    elem.innerText = '';
                    elem.innerHTML = '';
                    elem.value = '';
                    elem.focus();
                    // Trigger events to ensure React/Vue updates
                    elem.dispatchEvent(new Event('input', { bubbles: true }));
                    elem.dispatchEvent(new Event('change', { bubbles: true }));
                """, textbox)
                time.sleep(0.3)
            
        except Exception as e:
            print(f"⚠️ Error clearing textbox: {e}")

    def go_to_compose(self):
        """Navigate to compose tweet page"""
        try:
            print("🚀 Navigating to compose page...")
            self.driver.get("https://x.com/compose/post")
            
            if not self._wait_for_page_load():
                print("⚠️ Page load timeout")
            
            # Wait for compose interface to be ready
            self.wait.until(EC.presence_of_element_located((By.XPATH, '//div[@data-testid="tweetTextarea_0"]')))
            print("✅ Compose page loaded successfully")
            return True
            
        except Exception as e:
            print(f"❌ Error navigating to compose page: {e}")
            return False

    def post_tweet(self, content, retry_on_failure=True):
        """
        Post a new tweet
        
        Args:
            content (str): The tweet content to post
            retry_on_failure (bool): Whether to retry if posting fails
            
        Returns:
            bool: True if tweet was posted successfully, False otherwise
        """
        if not content or len(content.strip()) == 0:
            print("❌ Error: Tweet content cannot be empty")
            return False
            
        if len(content) > 280:
            print(f"❌ Error: Tweet content too long ({len(content)} chars). Maximum is 280 characters.")
            return False

        print(f"📝 Posting tweet: '{content}'")
        
        try:
            # Navigate to compose if not already there
            current_url = self.driver.current_url
            if "compose" not in current_url:
                if not self.go_to_compose():
                    return False
            else:
                self._wait_for_page_load()

            self._rate_limit_delay()

            # Find tweet composition textbox
            print("🔍 Looking for tweet composition textbox...")
            textbox_xpaths = [
                '//div[@data-testid="tweetTextarea_0"]',
                '//div[@contenteditable="true"][@data-testid="tweetTextarea_0"]',
            ]
            
            textbox = None
            for xpath in textbox_xpaths:
                try:
                    textbox = self.wait.until(EC.element_to_be_clickable((By.XPATH, xpath)))
                    break
                except:
                    continue
            
            if not textbox:
                print("❌ Could not find tweet composition textbox")
                return False
            
            # Clear textbox thoroughly and input text
            print("📝 Inputting text...")
            self._clear_textbox_thoroughly(textbox)
            
            # Input content
            textbox.send_keys(content)
            time.sleep(1)
            
            # Verify text was entered correctly
            entered_text = textbox.get_attribute('textContent') or textbox.text or ""
            print(f"📝 Text verification: '{entered_text}'")
            
            if content.strip() != entered_text.strip():
                print(f"⚠️ Text mismatch - expected: '{content}', got: '{entered_text}'")
                # Try once more with thorough clearing
                self._clear_textbox_thoroughly(textbox)
                textbox.send_keys(content)
                time.sleep(1)

            # Find tweet button - use the selector that worked in testing
            print("🔍 Looking for tweet button...")
            button_xpaths = [
                '//button[@data-testid="tweetButton"]',  # This one worked!
                '//button[@data-testid="tweetButtonInline"]',
            ]
            
            button = None
            for xpath in button_xpaths:
                try:
                    buttons = self.driver.find_elements(By.XPATH, xpath)
                    for btn in buttons:
                        if btn.is_displayed():
                            button = btn
                            print(f"✅ Found button with: {xpath}")
                            break
                    if button:
                        break
                except:
                    continue
            
            if not button:
                print("❌ Could not find tweet button")
                return False

            # Use smart click method
            if self._smart_click(button, "tweet button"):
                print("✅ Tweet posted successfully!")
                self.post_count += 1
                return True
            else:
                return False

        except Exception as e:
            print(f"❌ Unexpected error posting tweet: {e}")
            if retry_on_failure:
                print("🔄 Retrying tweet post...")
                return self.post_tweet(content, retry_on_failure=False)
            return False

    def reply_to_tweet(self, tweet_url, reply_content, retry_on_failure=True):
        """
        Reply to a specific tweet
        
        Args:
            tweet_url (str): URL of the tweet to reply to
            reply_content (str): The reply content
            retry_on_failure (bool): Whether to retry if replying fails
            
        Returns:
            bool: True if reply was posted successfully, False otherwise
        """
        if not reply_content or len(reply_content.strip()) == 0:
            print("❌ Error: Reply content cannot be empty")
            return False
            
        if len(reply_content) > 280:
            print(f"❌ Error: Reply content too long ({len(reply_content)} chars)")
            return False

        if not tweet_url or "status/" not in tweet_url:
            print("❌ Error: Invalid tweet URL")
            return False

        print(f"💬 Replying to tweet: {tweet_url}")
        
        try:
            # Navigate to the tweet
            self.driver.get(tweet_url)
            self._wait_for_page_load()
            self._rate_limit_delay()

            # Find and click reply button
            reply_button = None
            reply_button_xpaths = [
                '//div[@data-testid="reply"]',
                '//button[@data-testid="reply"]',
            ]

            for xpath in reply_button_xpaths:
                try:
                    reply_button = self.driver.find_element(By.XPATH, xpath)
                    if reply_button and reply_button.is_displayed():
                        break
                except:
                    continue

            if not reply_button:
                print("❌ Could not find reply button")
                return False

            reply_button.click()
            time.sleep(2)

            # Find reply textbox
            textbox = None
            reply_textbox_xpaths = [
                '//div[@data-testid="tweetTextarea_0"]',
                '//div[@contenteditable="true"][@data-testid="tweetTextarea_0"]'
            ]

            for xpath in reply_textbox_xpaths:
                try:
                    textbox = self.wait.until(EC.element_to_be_clickable((By.XPATH, xpath)))
                    break
                except:
                    continue

            if not textbox:
                print("❌ Could not find reply textbox")
                return False

            # Input reply content
            self._clear_textbox_thoroughly(textbox)
            textbox.send_keys(reply_content)
            time.sleep(1)

            # Find and click reply submit button
            submit_button = None
            submit_button_xpaths = [
                '//button[@data-testid="tweetButton"]',  # Use the working selector
                '//button[@data-testid="tweetButtonInline"]'
            ]

            for xpath in submit_button_xpaths:
                try:
                    submit_button = self.driver.find_element(By.XPATH, xpath)
                    if submit_button and submit_button.is_displayed():
                        break
                except:
                    continue

            if not submit_button:
                print("❌ Could not find reply submit button")
                return False

            # Click reply submit button
            if self._smart_click(submit_button, "reply submit button"):
                print("✅ Reply posted successfully!")
                self.post_count += 1
                return True
            else:
                return False

        except Exception as e:
            print(f"❌ Unexpected error replying: {e}")
            if retry_on_failure:
                return self.reply_to_tweet(tweet_url, reply_content, retry_on_failure=False)
            return False

    def get_post_count(self):
        """Get the number of posts made in this session"""
        return self.post_count

    def reset_post_count(self):
        """Reset the post counter"""
        self.post_count = 0
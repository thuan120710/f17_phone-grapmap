-- Add tweet_id column to phone_twitter_messages table
-- This allows linking direct messages to specific tweets for comment functionality

ALTER TABLE phone_twitter_messages
ADD COLUMN tweet_id VARCHAR(255) NULL,
ADD INDEX idx_tweet_id (tweet_id);

-- Add column to track if this is a comment message
ALTER TABLE phone_twitter_messages
ADD COLUMN is_comment BOOLEAN DEFAULT FALSE,
ADD INDEX idx_is_comment (is_comment);
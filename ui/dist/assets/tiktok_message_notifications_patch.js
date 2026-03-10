// TikTok Message Notifications Patch
// Fixes message notifications display and navigation in Activity tab

(function () {
    'use strict';

    console.log('[TikTok Message Notifications] Patch loading...');

    // Function to patch notifications
    function patchMessageNotifications() {
        // Find all notification items in the inbox
        const notifications = document.querySelectorAll('.inbox-body .notification');

        notifications.forEach(notificationElement => {
            // Skip if already patched
            if (notificationElement.dataset.messagePatched === 'true') return;

            // Check if this is a message notification by:
            // 1. No video preview element
            // 2. No follow button
            // 3. Has notification-content that's empty or says "undefined"
            const hasVideoPreview = notificationElement.querySelector('.video-preview video');
            const hasFollowButton = notificationElement.querySelector('.button.follow, .button.following');
            const notificationContent = notificationElement.querySelector('.notification-content');

            if (!hasVideoPreview && !hasFollowButton && notificationContent) {
                const contentText = notificationContent.textContent || '';

                // If content is empty or undefined, this might be an unhandled message notification
                if (contentText.trim() === '' || contentText.includes('undefined')) {
                    // Try to find the React fiber to get notification data
                    let notificationData = null;

                    // Try to get data from React fiber
                    const fiberKey = Object.keys(notificationElement).find(key =>
                        key.startsWith('__reactFiber') || key.startsWith('__reactProps') || key.startsWith('__reactInternalInstance')
                    );

                    if (fiberKey) {
                        let fiber = notificationElement[fiberKey];

                        // Walk up fiber tree to find data prop
                        let attempts = 0;
                        while (fiber && attempts < 20) {
                            if (fiber.memoizedProps && fiber.memoizedProps.data) {
                                notificationData = fiber.memoizedProps.data;
                                break;
                            }
                            if (fiber.return) {
                                fiber = fiber.return;
                            } else if (fiber._owner) {
                                fiber = fiber._owner;
                            } else {
                                break;
                            }
                            attempts++;
                        }
                    }

                    // If we found message data
                    if (notificationData && notificationData.type === 'message') {
                        console.log('[TikTok Message Notifications] Patching message notification:', notificationData);

                        // Mark as patched
                        notificationElement.dataset.messagePatched = 'true';
                        notificationElement.dataset.messageUsername = notificationData.username;
                        notificationElement.dataset.messageChannelId = notificationData.channelId;

                        // Update the notification content text
                        if (notificationData.messageContent) {
                            const contentDiv = notificationElement.querySelector('.notification-content');
                            if (contentDiv) {
                                // Clear existing content
                                const timestamp = contentDiv.querySelector('.timestamp');
                                contentDiv.innerHTML = '';

                                // Add message text
                                const messageText = document.createTextNode('sent you a message: ' + notificationData.messageContent);
                                contentDiv.appendChild(messageText);

                                // Re-add timestamp
                                if (timestamp) {
                                    contentDiv.appendChild(timestamp);
                                }
                            }
                        }

                        // Replace video preview with message icon
                        const videoPreviewContainer = notificationElement.querySelector('.video-preview');
                        if (videoPreviewContainer || !notificationElement.querySelector('.message-icon-preview')) {
                            if (videoPreviewContainer) {
                                videoPreviewContainer.remove();
                            }

                            // Create message icon preview
                            const messagePreview = document.createElement('div');
                            messagePreview.className = 'message-icon-preview video-preview';
                            messagePreview.innerHTML = `
                                <div style="
                                    width: 60px;
                                    height: 60px;
                                    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
                                    border-radius: 8px;
                                    display: flex;
                                    align-items: center;
                                    justify-content: center;
                                    font-size: 28px;
                                    cursor: pointer;
                                ">💬</div>
                            `;
                            notificationElement.appendChild(messagePreview);
                        }

                        // Override click handler for the entire notification
                        notificationElement.style.cursor = 'pointer';

                        // Remove old click handlers
                        const newElement = notificationElement.cloneNode(true);
                        notificationElement.parentNode.replaceChild(newElement, notificationElement);

                        // Add new click handler
                        newElement.addEventListener('click', function(e) {
                            e.preventDefault();
                            e.stopPropagation();

                            const username = this.dataset.messageUsername;
                            const channelId = this.dataset.messageChannelId;

                            console.log('[TikTok Message Notifications] Navigating to DM:', username, channelId);

                            // Try to navigate to messages
                            if (window.fetchNui) {
                                // Get channel ID if not already available
                                if (channelId) {
                                    navigateToMessages(username, channelId);
                                } else {
                                    window.fetchNui('TikTok', {
                                        action: 'getChannelId',
                                        username: username
                                    }).then(result => {
                                        if (result && result.id) {
                                            navigateToMessages(username, result.id);
                                        }
                                    });
                                }
                            }
                        });
                    }
                }
            }
        });
    }

    // Function to navigate to messages tab and open specific conversation
    function navigateToMessages(username, channelId) {
        console.log('[TikTok Message Notifications] Opening messages with:', username, channelId);

        // First, click the messages navigation item
        // Try different selectors to find the messages nav button
        const possibleSelectors = [
            '.navbar .item[data-id="messages"]',
            '.navbar .messages',
            '.inbox-header .messages',
            'div[data-view="messages"]'
        ];

        let messagesButton = null;
        for (const selector of possibleSelectors) {
            messagesButton = document.querySelector(selector);
            if (messagesButton) break;
        }

        if (messagesButton) {
            messagesButton.click();

            // Wait a bit for the view to change, then try to open the specific conversation
            setTimeout(() => {
                // Look for the conversation in the list
                const conversations = document.querySelectorAll('.messages-body .message');
                conversations.forEach(conv => {
                    const usernameElement = conv.querySelector('.username');
                    if (usernameElement && usernameElement.textContent.includes(username)) {
                        conv.click();
                    }
                });
            }, 300);
        }
    }

    // Observer to detect when notifications are loaded/updated
    function setupObserver() {
        const observer = new MutationObserver((mutations) => {
            let shouldPatch = false;

            mutations.forEach(mutation => {
                mutation.addedNodes.forEach(node => {
                    if (node.nodeType === 1) {
                        if (node.classList && node.classList.contains('notification')) {
                            shouldPatch = true;
                        } else if (node.querySelector && node.querySelector('.notification')) {
                            shouldPatch = true;
                        }
                    }
                });
            });

            if (shouldPatch) {
                setTimeout(patchMessageNotifications, 100);
            }
        });

        // Observe inbox body
        const inboxBody = document.querySelector('.inbox-body');
        if (inboxBody) {
            observer.observe(inboxBody, {
                childList: true,
                subtree: true
            });

            // Initial patch
            patchMessageNotifications();
            console.log('[TikTok Message Notifications] Observer active');
        } else {
            // Retry if not loaded yet
            setTimeout(setupObserver, 1000);
        }
    }

    // Wait for DOM to be ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => {
            setTimeout(setupObserver, 2000);
        });
    } else {
        setTimeout(setupObserver, 2000);
    }

    // Also watch for when TikTok app becomes active
    const appObserver = new MutationObserver(() => {
        const tiktokApp = document.querySelector('.app-tiktok, [data-app="tiktok"], [data-app="TikTok"]');
        if (tiktokApp && tiktokApp.style.display !== 'none') {
            setTimeout(setupObserver, 500);
        }
    });

    appObserver.observe(document.body, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['style', 'class']
    });

    console.log('[TikTok Message Notifications] Patch loaded successfully');
})();

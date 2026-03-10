(function() {
    let conversationsData = {};
    let isInjecting = false;
    let injectTimer = null;

    window.addEventListener('message', (event) => {
        const { action, data, channelId, avatar } = event.data || {};

        if (action === 'forceUpdateConversations') {
            if (!data || !Array.isArray(data)) return;

            conversationsData = {};
            data.forEach(conv => {
                if (conv.isGroup && conv.avatar) {
                    conversationsData[conv.id] = conv.avatar;
                }
            });

            try {
                localStorage.setItem('lb-phone-group-avatars', JSON.stringify(conversationsData));
            } catch (e) {}

            scheduleInject(300);
        }
        
        // Handle direct avatar update
        if (action === 'messages:updateGroupAvatar' && channelId) {
            // Load existing data
            if (Object.keys(conversationsData).length === 0) {
                try {
                    const cached = localStorage.getItem('lb-phone-group-avatars');
                    if (cached) {
                        conversationsData = JSON.parse(cached);
                    }
                } catch (e) {}
            }

            // Update specific channel avatar
            if (avatar) {
                conversationsData[channelId] = avatar;
            } else {
                delete conversationsData[channelId];
            }

            try {
                localStorage.setItem('lb-phone-group-avatars', JSON.stringify(conversationsData));
            } catch (e) {}

            // Immediately update the specific conversation in DOM
            updateSpecificConversationAvatar(channelId, avatar);
            
            // Also schedule full inject as backup
            scheduleInject(100);
        }
    });

    function scheduleInject(delay) {
        if (injectTimer) clearTimeout(injectTimer);
        injectTimer = setTimeout(() => injectAvatarsToDOM(), delay);
    }

    function updateSpecificConversationAvatar(channelId, avatarUrl) {
        // Find the specific conversation by channel ID stored in data attribute
        const conversationItems = document.querySelectorAll('.messages-container .users-list .user');
        
        let found = false;
        conversationItems.forEach(userDiv => {
            const avatarDiv = userDiv.querySelector('.avatar.group');
            if (!avatarDiv) return;

            // Check if this is the conversation we're looking for
            const storedChannelId = avatarDiv.getAttribute('data-channel-id');
            if (storedChannelId === channelId.toString()) {
                // Update this specific avatar immediately
                if (avatarUrl) {
                    avatarDiv.style.cssText = `
                        background-image: url(${avatarUrl});
                        background-size: cover;
                        background-position: center;
                        background-repeat: no-repeat;
                        width: 2.75rem;
                        height: 2.75rem;
                        border-radius: 50%;
                        margin-right: 0;
                    `;
                    avatarDiv.setAttribute('data-has-group-avatar', 'true');
                } else {
                    // Remove avatar
                    avatarDiv.style.backgroundImage = '';
                    avatarDiv.removeAttribute('data-has-group-avatar');
                }
                found = true;
            }
        });

        // If not found by channel ID, force full refresh
        if (!found) {
            // Clear all data-has-group-avatar to force refresh
            conversationItems.forEach(userDiv => {
                const avatarDiv = userDiv.querySelector('.avatar.group');
                if (avatarDiv) {
                    avatarDiv.removeAttribute('data-has-group-avatar');
                }
            });
            scheduleInject(50);
        }
    }

    function injectAvatarsToDOM() {
        if (isInjecting) return;
        isInjecting = true;

        requestAnimationFrame(() => {
            const avatarGroups = document.querySelectorAll('.messages-container .users-list .user .avatar.group');

            if (avatarGroups.length === 0) {
                isInjecting = false;
                return;
            }

            if (Object.keys(conversationsData).length === 0) {
                try {
                    const cached = localStorage.getItem('lb-phone-group-avatars');
                    if (cached) {
                        conversationsData = JSON.parse(cached);
                    }
                } catch (e) {}
            }

            // Get all avatars from conversationsData
            const avatarEntries = Object.entries(conversationsData);
            if (avatarEntries.length === 0) {
                isInjecting = false;
                return;
            }

            avatarGroups.forEach((avatarDiv, index) => {
                // Always update, don't skip based on data-has-group-avatar
                // This ensures avatars get updated when changed
                const userDiv = avatarDiv.closest('.user');
                if (!userDiv) return;

                // Use modulo to cycle through available avatars
                const avatarEntry = avatarEntries[index % avatarEntries.length];
                if (!avatarEntry || !avatarEntry[1]) return;

                const avatarUrl = avatarEntry[1];

                avatarDiv.style.cssText = `
                    background-image: url(${avatarUrl});
                    background-size: cover;
                    background-position: center;
                    background-repeat: no-repeat;
                    width: 2.75rem;
                    height: 2.75rem;
                    border-radius: 50%;
                    margin-right: 0;
                `;
                avatarDiv.setAttribute('data-has-group-avatar', 'true');
                avatarDiv.setAttribute('data-channel-id', avatarEntry[0]); // Store channel ID for future reference
            });

            isInjecting = false;
        });
    }

    function setupObserver() {
        let observerTimer = null;

        const observer = new MutationObserver((mutations) => {
            if (observerTimer) clearTimeout(observerTimer);
            
            // Check if any mutations involve avatar groups
            let hasAvatarChanges = false;
            mutations.forEach(mutation => {
                if (mutation.type === 'childList') {
                    mutation.addedNodes.forEach(node => {
                        if (node.nodeType === 1) { // Element node
                            if (node.querySelector && node.querySelector('.avatar.group')) {
                                hasAvatarChanges = true;
                            }
                        }
                    });
                }
            });

            observerTimer = setTimeout(() => {
                const hasAvatarGroup = document.querySelector('.messages-container .users-list .avatar.group');
                if (hasAvatarGroup || hasAvatarChanges) {
                    scheduleInject(100); // Faster response for avatar changes
                }
            }, 50); // Reduced delay for faster updates
        });

        const attachObserver = () => {
            const usersList = document.querySelector('.messages-container .users-list');
            if (usersList) {
                observer.observe(usersList, { 
                    childList: true, 
                    subtree: true,
                    attributes: true,
                    attributeFilter: ['style', 'data-has-group-avatar']
                });
                return true;
            }
            return false;
        };

        if (!attachObserver()) {
            setTimeout(() => {
                if (!attachObserver()) {
                    observer.observe(document.body, { childList: true, subtree: true });
                }
            }, 2000);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', setupObserver);
    } else {
        setTimeout(setupObserver, 500);
    }

    // Force refresh all avatars (useful for debugging)
    window.forceRefreshGroupAvatars = function() {
        // Clear all existing markers
        document.querySelectorAll('.avatar.group[data-has-group-avatar]').forEach(avatar => {
            avatar.removeAttribute('data-has-group-avatar');
        });
        scheduleInject(0);
    };

    // Periodic check to ensure avatars are applied
    setInterval(() => {
        const avatarGroups = document.querySelectorAll('.messages-container .users-list .user .avatar.group');
        const unmarkedAvatars = document.querySelectorAll('.messages-container .users-list .user .avatar.group:not([data-has-group-avatar])');
        
        if (avatarGroups.length > 0 && unmarkedAvatars.length > 0 && Object.keys(conversationsData).length > 0) {
            console.log('[Avatar Fix] Found unmarked avatars, applying fix...');
            scheduleInject(100);
        }
    }, 2000);

    let retryCount = 0;
    const tryInject = () => {
        if (document.querySelector('.messages-container .users-list .avatar.group')) {
            scheduleInject(300);
        } else if (retryCount < 5) { // Increased retry count
            retryCount++;
            setTimeout(tryInject, 1000);
        }
    };

    setTimeout(tryInject, 1000);
})();

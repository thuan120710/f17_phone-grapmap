/**
 * Messages Delete Real-time Fix
 * Ensures deleted messages disappear immediately from UI
 */

(function() {
    'use strict';

    console.log('[Messages Delete Fix] Initializing real-time delete handler...');

    // Wait for fetchNui to be available
    let initAttempts = 0;
    const initInterval = setInterval(() => {
        initAttempts++;

        if (!window.fetchNui) {
            if (initAttempts > 100) {
                console.warn('[Messages Delete Fix] fetchNui not found after 10s');
                clearInterval(initInterval);
            }
            return;
        }

        console.log('[Messages Delete Fix] fetchNui found, applying patches...');
        clearInterval(initInterval);
        applyPatches();
    }, 100);

    function applyPatches() {
        // Store original fetchNui
        const originalFetchNui = window.fetchNui;

        // Override fetchNui to intercept deleteMessage responses
        window.fetchNui = async function(event, data) {
            // Call original function
            const result = await originalFetchNui.apply(this, arguments);

            // Only process Messages deleteMessage action
            if (event === 'Messages' && data && data.action === 'deleteMessage') {
                console.log('[Messages Delete Fix] deleteMessage response:', result);

                if (result === true || result.success === true) {
                    // Message deleted successfully, update UI immediately
                    const messageId = data.id;
                    const channelId = data.channel;

                    console.log('[Messages Delete Fix] Message deleted successfully:', {
                        messageId,
                        channelId
                    });

                    // Dispatch custom event for immediate UI update
                    window.postMessage({
                        action: 'messages:messageDeleted',
                        data: {
                            messageId: messageId,
                            channelId: channelId,
                            isLastMessage: false // Will be determined by server broadcast
                        }
                    }, '*');

                    // Also dispatch native event
                    window.dispatchEvent(new CustomEvent('messages:messageDeleted', {
                        detail: {
                            messageId: messageId,
                            channelId: channelId,
                            isLastMessage: false
                        }
                    }));

                    // Remove message from DOM immediately
                    removeMessageFromDOM(messageId);
                }
            }

            return result;
        };

        console.log('[Messages Delete Fix] Patches applied successfully!');
    }

    // Remove message element from DOM
    function removeMessageFromDOM(messageId) {
        try {
            // Find message elements by various possible selectors
            const selectors = [
                `[data-message-id="${messageId}"]`,
                `[data-id="${messageId}"]`,
                `.message-${messageId}`,
                `.message[data-message-id="${messageId}"]`
            ];

            let messageElement = null;
            for (const selector of selectors) {
                messageElement = document.querySelector(selector);
                if (messageElement) break;
            }

            if (messageElement) {
                // Fade out animation
                messageElement.style.transition = 'opacity 0.2s ease-out, transform 0.2s ease-out';
                messageElement.style.opacity = '0';
                messageElement.style.transform = 'translateX(-20px)';

                // Remove from DOM after animation
                setTimeout(() => {
                    messageElement.remove();
                    console.log('[Messages Delete Fix] Message element removed from DOM:', messageId);
                }, 200);
            } else {
                console.log('[Messages Delete Fix] Message element not found in DOM:', messageId);
            }
        } catch (e) {
            console.error('[Messages Delete Fix] Error removing message from DOM:', e);
        }
    }

    // Enhanced event listener for server broadcasts
    window.addEventListener('message', function(event) {
        if (!event.data || !event.data.action) return;

        const action = event.data.action;
        const data = event.data.data;

        // Handle messageDeleted event from server
        if (action === 'messages:messageDeleted' && data) {
            console.log('[Messages Delete Fix] Server broadcast received:', data);

            // Ensure message is removed from DOM
            if (data.messageId) {
                setTimeout(() => {
                    removeMessageFromDOM(data.messageId);
                }, 50);
            }
        }
    });

    console.log('[Messages Delete Fix] Loaded and ready!');
})();

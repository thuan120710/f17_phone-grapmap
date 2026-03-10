// TikTok Comments Fix Override - Simple Version
// Inject this code to fix comment display issues

(function () {
    'use strict';

    // Suppress scroll-related errors globally
    const originalConsoleError = console.error;
    console.error = function(...args) {
        const message = args[0]?.toString() || '';
        // Ignore scroll-related errors
        if (message.includes("Cannot read properties of undefined (reading 'action')") ||
            message.includes("Cannot read properties of undefined (reading 'type')") ||
            message.includes("Cannot destructure property 'action'")) {
            return; // Suppress
        }
        originalConsoleError.apply(console, args);
    };

    // Also suppress via window.onerror
    const originalError = window.onerror;
    window.onerror = function(message, source, lineno, colno, error) {
        if (message && (
            message.includes("Cannot read properties of undefined (reading 'action')") ||
            message.includes("Cannot read properties of undefined (reading 'type')") ||
            message.includes("Cannot destructure property 'action'")
        )) {
            return true; // Suppress
        }
        if (originalError) {
            return originalError.call(this, message, source, lineno, colno, error);
        }
        return false;
    };

    // Debug disabled for production
    function debugLog() { } // No-op function

    // Hide original React comments
    const globalStyle = document.createElement('style');
    globalStyle.id = 'tiktok-hide-original-comments';
    globalStyle.textContent = `
        /* Hide React comments, not shadow DOM */
        .comments-body > .item:not(#tiktok-comments-shadow-host),
        .comments-body > .comment-info,
        .comments-body .item .comment-info {
            display: none !important;
            visibility: hidden !important;
            height: 0 !important;
            overflow: hidden !important;
            opacity: 0 !important;
        }

        /* Ensure shadow DOM visible */
        #tiktok-comments-shadow-host {
            display: flex !important;
            visibility: visible !important;
            height: auto !important;
            opacity: 1 !important;
        }

        /* Ensure comments visible */
        #tiktok-comments-shadow-host .comment-item,
        #tiktok-comments-shadow-host .item {
            display: block !important;
            visibility: visible !important;
            height: auto !important;
            opacity: 1 !important;
        }
    `;
    document.head.appendChild(globalStyle);

    // Observe and hide new React comments
    const observeAndHideComments = () => {
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType === 1) { // Element node
                        // Check if inside shadow DOM
                        const isInShadow = node.closest('#tiktok-comments-shadow-host');

                        if (isInShadow) {
                            // Nếu trong shadow DOM thì bỏ qua
                            return;
                        }

                        const isCommentFromReact =
                            (node.classList?.contains('item') ||
                                node.classList?.contains('comment-info') ||
                                node.classList?.contains('comment-item')) &&
                            node.id !== 'tiktok-comments-shadow-host';

                        const parentIsCommentsBody = node.parentElement?.classList?.contains('comments-body');

                        // Hide if it's a comment from React
                        if (isCommentFromReact && parentIsCommentsBody) {
                            node.style.display = 'none';
                            node.style.visibility = 'hidden';
                            node.style.height = '0';
                            node.style.overflow = 'hidden';
                            node.style.opacity = '0';
                        }
                    }
                });
            });
        });

        const commentsBody = document.querySelector('.comments-body');
        if (commentsBody) {
            observer.observe(commentsBody, { childList: true, subtree: false });
        } else {
            setTimeout(observeAndHideComments, 500);
        }
    };

    setTimeout(observeAndHideComments, 1000);

    window.showDeleteDialog = function showDeleteDialog(shadowRoot, title, message) {
        return new Promise((resolve) => {
            const overlay = document.createElement('div');
            overlay.className = 'delete-dialog-overlay';
            const dialog = document.createElement('div');
            dialog.className = 'delete-dialog';

            dialog.innerHTML = `
                <div class="delete-dialog-header">
                    <div class="delete-dialog-title">${title}</div>
                    <div class="delete-dialog-message">${message}</div>
                </div>
                <div class="delete-dialog-actions">
                    <button class="delete-dialog-btn confirm">Xóa</button>
                    <button class="delete-dialog-btn cancel">Hủy</button>
                </div>
            `;

            overlay.appendChild(dialog);

            const handleClose = (result) => {
                overlay.style.animation = 'fadeOut 0.2s ease';
                setTimeout(() => { overlay.remove(); resolve(result); }, 200);
            };

            dialog.querySelector('.confirm').addEventListener('click', () => handleClose(true));
            dialog.querySelector('.cancel').addEventListener('click', () => handleClose(false));
            overlay.addEventListener('click', (e) => { if (e.target === overlay) handleClose(false); });

            if (!shadowRoot.querySelector('style[data-fadeout]')) {
                const fadeOutStyle = document.createElement('style');
                fadeOutStyle.textContent = `
                    @keyframes fadeOut {
                        from { opacity: 1; }
                        to { opacity: 0; }
                    }
                `;
                fadeOutStyle.setAttribute('data-fadeout', 'true');
                shadowRoot.appendChild(fadeOutStyle);
            }
            shadowRoot.appendChild(overlay);
        });
    };

    // Show TikTok notification (toast style) - INSIDE PHONE
    window.showTikTokNotification = function showTikTokNotification(message, type = 'success') {
        // Find phone container
        const phoneContainer = document.querySelector('.phone-container') || 
                             document.querySelector('[class*="phone"]') ||
                             document.querySelector('.app') ||
                             document.body;
        
        // Remove existing notification if any
        const existing = phoneContainer.querySelector('.tiktok-notification-toast');
        if (existing) {
            existing.remove();
        }

        const toast = document.createElement('div');
        toast.className = 'tiktok-notification-toast';
        toast.setAttribute('data-type', type);
        
        const icon = type === 'success' ? '✓' : type === 'error' ? '✕' : 'ℹ';
        const bgColor = type === 'success' ? '#4CAF50' : type === 'error' ? '#f44336' : '#2196F3';
        
        toast.innerHTML = `
            <div style="display: flex; align-items: center; gap: 0.625rem;">
                <div style="
                    width: 1.5rem;
                    height: 1.5rem;
                    border-radius: 50%;
                    background: ${bgColor};
                    color: white;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-weight: bold;
                    font-size: 1rem;
                ">${icon}</div>
                <div style="flex: 1; color: var(--phone-color-text, #161823); font-size: 0.875rem;">${message}</div>
            </div>
        `;
        
        toast.style.cssText = `
            position: absolute;
            top: 4rem;
            left: 50%;
            transform: translateX(-50%);
            background: var(--phone-color-background, white);
            padding: 0.875rem 1.25rem;
            border-radius: 0.5rem;
            box-shadow: 0 0.25rem 0.75rem rgba(0, 0, 0, 0.15);
            z-index: 99999;
            min-width: 15rem;
            max-width: 20rem;
            animation: slideDown 0.3s ease;
            border: 0.0625rem solid ${bgColor};
        `;
        
        // Add animation
        const style = document.createElement('style');
        style.textContent = `
            @keyframes slideDown {
                from {
                    opacity: 0;
                    transform: translateX(-50%) translateY(-1.25rem);
                }
                to {
                    opacity: 1;
                    transform: translateX(-50%) translateY(0);
                }
            }
            @keyframes slideUp {
                from {
                    opacity: 1;
                    transform: translateX(-50%) translateY(0);
                }
                to {
                    opacity: 0;
                    transform: translateX(-50%) translateY(-1.25rem);
                }
            }
        `;
        if (!document.querySelector('style[data-tiktok-toast]')) {
            style.setAttribute('data-tiktok-toast', 'true');
            document.head.appendChild(style);
        }
        
        phoneContainer.appendChild(toast);
        
        // Auto remove after 3 seconds
        setTimeout(() => {
            toast.style.animation = 'slideUp 0.3s ease';
            setTimeout(() => toast.remove(), 300);
        }, 3000);
    };

    window.sendTikTokMessage = async function sendTikTokMessage(action, data = {}) {
        try {
            const response = await fetch(`https://${GetParentResourceName()}/TikTok`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json'
                },
                body: JSON.stringify({ action, ...data })
            });

            if (!response.ok) throw new Error(`HTTP Error ${response.status}`);
            return await response.json();
        } catch (error) {
            return { success: false, error: error.message || 'Unknown error' };
        }
    };

    try {
        eval(`
            window.displayTikTokComments = function(comments, page, isAppending) {
                try {
                    if (!comments || !Array.isArray(comments)) return;

                    // Update pagination state
                    // Chỉ dừng load khi nhận được 0 comment (hết thật sự)
                    // Nếu nhận được bất kỳ comment nào (dù 1 hay 15) = vẫn tiếp tục load
                    if (comments.length === 0) {
                        hasMoreComments = false;
                    } else {
                        hasMoreComments = true;
                    }
                    isLoadingMoreComments = false;

                    const commentsBody = document.querySelector('.comments-body') ||
                                       document.querySelector('[class*="comments-body"]') ||
                                       document.querySelector('[class*="comments"]') ||
                                       document.querySelector('.tiktok-video-view') ||
                                       document.querySelector('[class*="video"]') ||
                                       document.body;

                    let shadowHost = commentsBody.querySelector('#tiktok-comments-shadow-host');
                    let shadowRoot;
                    let isNewHost = false;

                    if (shadowHost && shadowHost.shadowRoot) {
                        shadowRoot = shadowHost.shadowRoot;
                    } else {
                        isNewHost = true;
                        shadowHost = document.createElement('div');
                        shadowHost.id = 'tiktok-comments-shadow-host';
                        shadowHost.style.cssText = \`
                            position: relative;
                            width: 100%;
                            height: 29rem;
                            display: flex;
                            flex-direction: column;
                            overflow-y: auto;
                            overflow-x: hidden;
                            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                        \`;
                        shadowRoot = shadowHost.attachShadow({ mode: 'open' });
                    }

                    const hideOriginalComments = () => {
                        const commentsBody = document.querySelector('.comments-body');
                        if (!commentsBody) return;

                        Array.from(commentsBody.children).forEach(el => {
                            const isShadowHost = el.id === 'tiktok-comments-shadow-host';
                            const isCommentElement = el.classList.contains('item') || 
                                el.classList.contains('comment-info') || 
                                el.classList.contains('comment-item');

                            if (!isShadowHost && isCommentElement) {
                                el.style.cssText = 'display:none;visibility:hidden;height:0;overflow:hidden;opacity:0';
                            }
                        });
                    };

                    hideOriginalComments();
                    setTimeout(hideOriginalComments, 100);
                    setTimeout(hideOriginalComments, 500);

                    // Detect theme and set attribute on shadow host
                    const isDarkMode = document.body.dataset.theme === 'dark' ||
                                     document.documentElement.dataset.theme === 'dark' ||
                                     document.querySelector('.phone-container')?.dataset.theme === 'dark' ||
                                     document.querySelector('[data-theme="dark"]') !== null;

                    shadowHost.setAttribute('data-theme', isDarkMode ? 'dark' : 'light');

                    const styles = document.createElement('style');
                    styles.textContent = \`
                    
                        /* Dark mode styles */
                        :host([data-theme="dark"]) .comment-item,
                        :host([data-theme="dark"]) .reply-item {
                            color: #ffffff;
                        }

                        :host([data-theme="dark"]) .action-btn {
                            color: #a0a0a0;
                        }

                        :host([data-theme="dark"]) .action-btn:hover {
                            color: #ffffff;
                        }

                        :host([data-theme="dark"]) .time-ago,
                        :host([data-theme="dark"]) .reply-time-ago {
                            color: #808080 !important;
                        }

                        :host([data-theme="dark"]) .reply-input {
                            background: #1a1a1a !important;
                            color: #ffffff !important;
                            border-color: #333333 !important;
                        }

                        :host([data-theme="dark"]) .delete-dialog {
                            background: #1a1a1a !important;
                        }

                        :host([data-theme="dark"]) .delete-dialog-title {
                            color: #ffffff !important;
                        }

                        :host([data-theme="dark"]) .delete-dialog-message {
                            color: #a0a0a0 !important;
                        }

                        :host([data-theme="dark"]) .delete-dialog-btn {
                            background: #1a1a1a !important;
                        }

                        :host([data-theme="dark"]) .delete-dialog-btn.cancel {
                            color: #ffffff !important;
                        }

                        :host([data-theme="dark"]) .view-replies-btn {
                            color: #a0a0a0 !important;
                        }

                        /* Dark mode - Nội dung comment */
                        :host([data-theme="dark"]) .comment-item > div > div {
                            color: #ffffff !important;
                        }

                        :host([data-theme="dark"]) .comment-item div[style*="color"] {
                            color: #ffffff !important;
                        }

                        :host([data-theme="dark"]) .reply-item div[style*="color"] {
                            color: #ffffff !important;
                        }

                        /* Dark mode - Username và text */
                        :host([data-theme="dark"]) div[style*="font-weight: 600"] {
                            color: #ffffff !important;
                        }

                        :host([data-theme="dark"]) div[style*="font-size: 0.875rem"] {
                            color: #ffffff !important;
                        }

                        /* Dark mode - Comment background */
                        :host([data-theme="dark"]) .comment-item {
                            background-color: transparent !important;
                        }

                        :host([data-theme="dark"]) .comment-item:hover {
                            background: rgba(255, 255, 255, 0.05) !important;
                        }

                        /* Light mode - Default colors */
                        .comment-username,
                        .reply-username,
                        .comment-text,
                        .reply-text {
                            color: #161823;
                        }

                        /* Dark mode - Text colors */
                        :host([data-theme="dark"]) .comment-username,
                        :host([data-theme="dark"]) .reply-username,
                        :host([data-theme="dark"]) .comment-text,
                        :host([data-theme="dark"]) .reply-text {
                            color: #ffffff !important;
                        }

                        // .comments-header {
                        //     padding: 0.9375rem;
                        //     border-bottom: 0.0625rem solid #f0f0f0;
                        //     font-weight: 600;
                        //     color: #161823;
                        //     display: flex;
                        //     justify-content: space-between;
                        //     align-items: center;
                        //     background: #ffffff;
                        //     flex-shrink: 0;
                        //     position: sticky;
                        //     top: 0;
                        //     z-index: 10;
                        // }

                        .comments-body {
                            overflow-y: auto;
                            flex: 1;
                            height: 100%;
                        }

                        .comment-item {
                            padding: 1rem 1.25rem;
                            border-bottom: 0.0625rem solid #f8f8f8;
                            transition: background-color 0.2s ease;
                            background-color: var(--phone-color-highlight);
                        }

                        .comment-item:hover {
                            background: var(--phone-color-highlight);
                            opacity: 0.95;
                        }

                        .comment-avatar {
                            width: 2.5rem;
                            height: 2.5rem;
                            border-radius: 50%;
                            margin-right: 0.75rem;
                            object-fit: cover;
                            border: 0.0625rem solid #f0f0f0;
                        }

                        .comment-avatar-placeholder {
                            width: 2.5rem;
                            height: 2.5rem;
                            border-radius: 50%;
                            background: linear-gradient(135deg, #ff0050 0%, #00f2ea 100%);
                            margin-right: 0.75rem;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            color: white;
                            font-weight: bold;
                            font-size: 0.875rem;
                            border: 0.0625rem solid #f0f0f0;
                        }


                        .verified-badge {
                            color: #1DA1F2;
                            margin-left: 0.25rem;
                            font-size: 0.75rem;
                            font-weight: bold;
                        }

                        /* Interactive buttons */
                        .action-buttons {
                            display: flex;
                            gap: 1.25rem;
                            align-items: center;
                            cursor: pointer;
                        }

                        .action-btn {
                            display: flex;
                            align-items: center;
                            gap: 0.25rem;
                            color: #8a8b91;
                            font-size: 0.8125rem;
                            transition: all 0.2s ease;
                            user-select: none;
                            cursor: pointer;
                        }

                        .action-btn:hover {
                            color: var(--phone-color-text);
                        }

                        .action-btn.liked {
                            color: #fe2c55;
                        }


                        .action-btn:active {
                            transform: scale(0.95);
                        }


                        /* Reply input */
                        .reply-input-container {
                            margin-top: 0.5rem;
                            padding: 0.75rem;
                            background: var(--phone-color-highlight, rgba(128, 128, 128, 0.1));
                            border-radius: 0.5rem;
                            display: none;
                        }

                        .reply-input-container.active {
                            display: block;
                        }

                        .reply-input-wrapper {
                            position: relative;
                            display: flex;
                            align-items: center;
                            gap: 0.5rem;
                        }

                        .reply-input {
                            flex: 1;
                            padding: 0.5rem 0.75rem;
                            border: 0.0625rem solid rgba(128, 128, 128, 0.3);
                            border-radius: 0.375rem;
                            font-size: 0.875rem;
                            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                            resize: none;
                            min-height: 2.25rem;
                            max-height: 6.25rem;
                            outline: none;
                            box-sizing: border-box;
                            line-height: 1.4;
                            overflow-y: auto;
                            white-space: pre-wrap !important;
                            word-wrap: break-word !important;
                            -webkit-user-select: text !important;
                            user-select: text !important;
                            pointer-events: auto !important;
                            background: var(--phone-color-background, white);
                            color: var(--phone-color-text, #161823);
                        }

                        .reply-input:focus {
                            border-color: var(--phone-color-text, #161823);
                        }

                        .reply-actions {
                            display: flex;
                            justify-content: flex-end;
                            gap: 0.5rem;
                            margin-top: 0.5rem;
                        }

                        .reply-btn {
                            padding: 0.375rem 0.75rem;
                            border: none;
                            border-radius: 0.375rem;
                            font-size: 0.8125rem;
                            cursor: pointer;
                            transition: all 0.2s ease;
                        }

                        .reply-btn.post {
                            background: #161823;
                            color: white;
                        }

                        .reply-btn.post:hover {
                            background: #000;
                        }

                        .reply-btn.cancel {
                            background: rgba(128, 128, 128, 0.2);
                            color: var(--phone-color-text-secondary, #666);
                        }

                        .reply-btn.cancel:hover {
                            background: rgba(128, 128, 128, 0.3);
                        }

                        /* Delete button */
                        .delete-btn {
                            position: absolute;
                            top: 1rem;
                            right: 1.25rem;
                            width: 1.25rem;
                            height: 1.25rem;
                            background: rgba(128, 128, 128, 0.2);
                            border: none;
                            border-radius: 50%;
                            color: var(--phone-color-text-secondary, #666);
                            cursor: pointer;
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            font-size: 0.75rem;
                            transition: all 0.2s ease;
                        }

                        .delete-btn:hover {
                            background: #fe2c55;
                            color: white;
                        }

                        /* Delete Confirmation Dialog - TikTok Style */
                        .delete-dialog-overlay {
                            position: fixed;
                            top: 0;
                            left: 0;
                            right: 0;
                            bottom: 0;
                            background: rgba(0, 0, 0, 0.6);
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            z-index: 9999;
                            animation: fadeIn 0.2s ease;
                        }

                        .delete-dialog {
                            background: white;
                            border-radius: 0.75rem;
                            width: 90%;
                            max-width: 20rem;
                            overflow: hidden;
                            animation: slideUp 0.3s ease;
                            box-shadow: 0 0.5rem 1.5rem rgba(0, 0, 0, 0.15);
                        }

                        .delete-dialog-header {
                            padding: 1.25rem 1.25rem 0.75rem;
                            text-align: center;
                            border-bottom: 0.0625rem solid #f0f0f0;
                        }

                        .delete-dialog-title {
                            font-size: 1.0625rem;
                            font-weight: 600;
                            color: var(--phone-color-text, #161823);
                            margin-bottom: 0.5rem;
                        }

                        .delete-dialog-message {
                            font-size: 0.875rem;
                            color: var(--phone-color-text-secondary, #666);
                            line-height: 1.4;
                        }

                        .delete-dialog-actions {
                            display: flex;
                            flex-direction: column;
                        }

                        .delete-dialog-btn {
                            padding: 1rem;
                            border: none;
                            background: white;
                            font-size: 1rem;
                            font-weight: 600;
                            cursor: pointer;
                            border-top: 0.0625rem solid #f0f0f0;
                            transition: background 0.2s ease;
                        }

                        .delete-dialog-btn:active {
                            background: #f8f8f8;
                        }

                        .delete-dialog-btn.confirm {
                            color: #fe2c55;
                        }

                        .delete-dialog-btn.cancel {
                            color: var(--phone-color-text, #161823);
                        }

                        @keyframes slideUp {
                            from {
                                opacity: 0;
                                transform: translateY(1.25rem) scale(0.95);
                            }
                            to {
                                opacity: 1;
                                transform: translateY(0) scale(1);
                            }
                        }

                        /* Animation for new replies */
                        @keyframes fadeIn {
                            from {
                                opacity: 0;
                                transform: translateY(-0.625rem);
                            }
                            to {
                                opacity: 1;
                                transform: translateY(0);
                            }
                        }

                        @keyframes fadeOut {
                            from {
                                opacity: 1;
                            }
                            to {
                                opacity: 0;
                            }
                        }
                    \`;

                    // Create container structure
                    const containerHTML = \`
                            <div class="comments-body">
                                \${comments.map((comment, index) => {
                                    if (comment && comment.comment && comment.username) {
                                        const avatar = comment.avatar ?
                                            \`<img src="\${comment.avatar}" class="comment-avatar">\` :
                                            \`<img src="./assets/img/avatar-placeholder-light.svg" class="comment-avatar">\`;

                                        const verifiedBadge = comment.verified ? '<span class="verified-badge">✓</span>' : '';
                                        const likedClass = comment.liked ? 'liked' : '';

                                        return \`
                                            <div class="comment-item" data-comment-id="\${comment.id}" data-timestamp="\${comment.timestamp}" style="position: relative;">
                                                <button class="delete-btn" data-comment-id="\${comment.id}" data-username="\${comment.username}">×</button>
                                                <div style="display: flex; align-items: flex-start;">
                                                    \${avatar}
                                                    <div style="flex: 1;">
                                                        <div style="font-weight: 600; margin-bottom: 0.375rem; font-size: 0.9375rem; display: flex; align-items: center;" class="comment-username">
                                                            \${comment.name || comment.username}\${verifiedBadge}
                                                        </div>
                                                        <div style="margin-bottom: 0.5rem; font-size: 0.9375rem; line-height: 1.4; word-wrap: break-word;" class="comment-text">\${comment.comment}</div>
                                                        <div class="action-buttons">
                                                            <span class="time-ago" style="color: var(--phone-color-text-secondary, #8a8b91); font-size: 0.8125rem;">\${formatTime(comment.timestamp)}</span>
                                                            <div class="action-btn \${likedClass}" data-comment-id="\${comment.id}" data-action="like">
                                                                <span class="like-icon">\${comment.liked ? '❤️' : '🤍'}</span>
                                                                <span class="like-count">\${comment.likes || 0}</span>
                                                            </div>
                                                            <div class="action-btn" data-comment-id="\${comment.id}" data-action="reply">
                                                                <span>💬</span>
                                                                <span class="reply-count">\${comment.replies || 0}</span>
                                                            </div>
                                                            \${comment.replies > 0 ? \`
                                                                <div class="action-btn view-replies-btn" data-comment-id="\${comment.id}" style="color: var(--phone-color-text-secondary, #666); font-weight: 500;">
                                                                    Xem \${comment.replies} câu trả lời
                                                                </div>
                                                            \` : ''}
                                                        </div>
                                                        <div class="reply-input-container" data-comment-id="\${comment.id}">
                                                            <div class="reply-input-wrapper">
                                                                <textarea class="reply-input" placeholder="Trả lời bình luận..." data-comment-id="\${comment.id}"></textarea>

                                                            </div>
                                                            <div class="reply-actions">
                                                                <button class="reply-btn cancel" data-comment-id="\${comment.id}">Hủy</button>
                                                                <button class="reply-btn post" data-comment-id="\${comment.id}">Gửi</button>
                                                            </div>
                                                        </div>
                                                    </div>
                                                </div>
                                            </div>
                                        \`;
                                    }
                                    return '';
                                }).join('')}
                            </div>
                        </div>
                    \`;

                    // Update shadow DOM content
                    let existingCommentsBody = shadowRoot.querySelector('.comments-body');

                    if (!isAppending || !existingCommentsBody) {
                        // RESET MODE: Clear everything and render fresh
                        shadowRoot.innerHTML = '';
                        shadowRoot.appendChild(styles);

                        const tempDiv = document.createElement('div');
                        tempDiv.innerHTML = containerHTML;
                        while (tempDiv.firstChild) {
                            shadowRoot.appendChild(tempDiv.firstChild);
                        }

                        // Reset page counter
                        currentCommentsPage = page || 0;
                    } else {
                        // APPEND MODE: Add new comments to existing list
                        // Filter out duplicate comments (check by data-comment-id)
                        const existingIds = Array.from(existingCommentsBody.querySelectorAll('[data-comment-id]'))
                            .map(el => el.getAttribute('data-comment-id'));
                        
                        const uniqueComments = comments.filter(comment => 
                            comment && comment.id && !existingIds.includes(comment.id.toString())
                        );
                        
                        const newComments = uniqueComments.map((comment, index) => {
                            if (comment && comment.comment && comment.username) {
                                const avatar = comment.avatar ?
                                    \`<img src="\${comment.avatar}" class="comment-avatar">\` :
                                    \`<img src="./assets/img/avatar-placeholder-light.svg" class="comment-avatar">\`;

                                const verifiedBadge = comment.verified ? '<span class="verified-badge">✓</span>' : '';
                                const likedClass = comment.liked ? 'liked' : '';

                                return \`
                                    <div class="comment-item" data-comment-id="\${comment.id}" data-timestamp="\${comment.timestamp}" style="position: relative;">
                                        <button class="delete-btn" data-comment-id="\${comment.id}" data-username="\${comment.username}">×</button>
                                        <div style="display: flex; align-items: flex-start;">
                                            \${avatar}
                                            <div style="flex: 1;">
                                                <div style="font-weight: 600; margin-bottom: 0.375rem; font-size: 0.9375rem; display: flex; align-items: center;" class="comment-username">
                                                    \${comment.name || comment.username}\${verifiedBadge}
                                                </div>
                                                <div style="margin-bottom: 0.5rem; font-size: 0.9375rem; line-height: 1.4; word-wrap: break-word;" class="comment-text">\${comment.comment}</div>
                                                <div class="action-buttons">
                                                    <span class="time-ago" style="color: var(--phone-color-text-secondary, #8a8b91); font-size: 0.8125rem;">\${formatTime(comment.timestamp)}</span>
                                                    <div class="action-btn \${likedClass}" data-comment-id="\${comment.id}" data-action="like">
                                                        <span class="like-icon">\${comment.liked ? '❤️' : '🤍'}</span>
                                                        <span class="like-count">\${comment.likes || 0}</span>
                                                    </div>
                                                    <div class="action-btn" data-comment-id="\${comment.id}" data-action="reply">
                                                        <span>💬</span>
                                                        <span class="reply-count">\${comment.replies || 0}</span>
                                                    </div>
                                                    \${comment.replies > 0 ? \`
                                                        <div class="action-btn view-replies-btn" data-comment-id="\${comment.id}" style="color: var(--phone-color-text-secondary, #666); font-weight: 500;">
                                                            Xem \${comment.replies} câu trả lời
                                                        </div>
                                                    \` : ''}
                                                </div>
                                                <div class="reply-input-container" data-comment-id="\${comment.id}">
                                                    <div class="reply-input-wrapper">
                                                        <textarea class="reply-input" placeholder="Trả lời bình luận..." data-comment-id="\${comment.id}"></textarea>
                                                    </div>
                                                    <div class="reply-actions">
                                                        <button class="reply-btn cancel" data-comment-id="\${comment.id}">Hủy</button>
                                                        <button class="reply-btn post" data-comment-id="\${comment.id}">Gửi</button>
                                                    </div>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                \`;
                            }
                            return '';
                        }).join('');

                        // Insert new comments at the END
                        existingCommentsBody.insertAdjacentHTML('beforeend', newComments);

                        // Update page counter
                        currentCommentsPage = page || currentCommentsPage + 1;
                    }

                    // Add event listeners for interactions
                    setupCommentInteractions(shadowRoot);

                    // Append shadow host to comments-body only if new
                    if (isNewHost) {
                        commentsBody.appendChild(shadowHost);

                        // Add wheel event to shadow host
                        shadowHost.addEventListener('wheel', function(e) {
                            e.preventDefault();
                            e.stopPropagation();

                            // Get the comments-body inside shadow DOM
                            const commentsBodyInShadow = this.shadowRoot?.querySelector('.comments-body');
                            if (commentsBodyInShadow) {
                                // Scroll the comments body smoothly
                                commentsBodyInShadow.scrollBy({
                                    top: e.deltaY,
                                    behavior: 'smooth'
                                });
                            }
                        }, { passive: false });
                    }

                    // Add infinite scroll listener với debounce
                    const commentsBodyInShadow = shadowRoot.querySelector('.comments-body');
                    if (commentsBodyInShadow && !commentsBodyInShadow.dataset.scrollListenerAdded) {
                        commentsBodyInShadow.dataset.scrollListenerAdded = 'true';
                        
                        let scrollTimeout = null;
                        let isScrollProcessing = false; // Flag để tránh race condition
                        
                        commentsBodyInShadow.addEventListener('scroll', async function(e) {
                            try {
                                // Stop propagation
                                if (e) {
                                    e.stopPropagation();
                                    e.stopImmediatePropagation();
                                }
                                
                                // Kiểm tra khi scroll gần đáy (10px)
                                const scrollTop = this.scrollTop;
                                const scrollHeight = this.scrollHeight;
                                const clientHeight = this.clientHeight;
                                const distanceFromBottom = scrollHeight - (scrollTop + clientHeight);
                                const isNearBottom = distanceFromBottom < 10;

                                // Load more khi gần đáy - check cả 2 flags
                                if (isNearBottom && !isLoadingMoreComments && !isScrollProcessing && hasMoreComments) {
                                    // Set flag NGAY LẬP TỨC để tránh duplicate
                                    isScrollProcessing = true;
                                    isLoadingMoreComments = true;

                                // Get current video ID
                                const videoId = currentVideoIdGlobal;
                                if (!videoId) {
                                    isLoadingMoreComments = false;
                                    return;
                                }

                                // Load next page
                                const nextPage = currentCommentsPage + 1;

                                try {
                                    const response = await sendTikTokMessage('getComments', {
                                        data: {
                                            id: videoId,
                                            replyTo: null
                                        },
                                        page: nextPage,
                                        sortBy: 'newest'
                                    });

                                    // Response có thể là array trực tiếp hoặc object {success, comments}
                                    let comments = null;
                                    if (Array.isArray(response)) {
                                        comments = response;
                                    } else if (response && response.success && Array.isArray(response.comments)) {
                                        comments = response.comments;
                                    }

                                    if (comments && comments.length > 0) {
                                        // Giới hạn đúng 15 comment để tránh duplicate
                                        const limitedComments = comments.slice(0, 15);
                                        window.displayTikTokComments(limitedComments, nextPage, true);
                                        isScrollProcessing = false; // Reset flag
                                    } else {
                                        hasMoreComments = false;
                                        isLoadingMoreComments = false;
                                        isScrollProcessing = false; // Reset flag
                                    }
                                } catch (error) {
                                    isLoadingMoreComments = false;
                                    isScrollProcessing = false; // Reset flag
                                }
                            }
                            } catch (err) {
                                // Ignore scroll errors
                                isScrollProcessing = false; // Reset flag
                            }
                        }, { capture: true, passive: true });
                    }

                } catch (e) {
                }
            };

            function formatTime(timestamp) {
                try {
                    // Convert to number if string
                    let ts = typeof timestamp === 'string' ? parseInt(timestamp) : timestamp;

                    // Validate timestamp
                    if (!ts || isNaN(ts) || ts <= 0) {
                        return 'vừa xong';
                    }

                    // If timestamp is in seconds (< year 2100 in seconds = 4102444800)
                    // Convert to milliseconds
                    if (ts < 4102444800) {
                        ts = ts * 1000;
                    }

                    const now = Date.now(); // Current timestamp in milliseconds
                    const diff = now - ts;

                    // Handle negative diff (timestamp in future - should not happen)
                    if (diff < 0) {
                        return 'vừa xong';
                    }

                    if (diff < 60000) return 'vừa xong';
                    if (diff < 3600000) return Math.floor(diff / 60000) + ' phút trước';
                    if (diff < 86400000) return Math.floor(diff / 3600000) + ' giờ trước';
                    if (diff < 2592000000) return Math.floor(diff / 86400000) + ' ngày trước';
                    return Math.floor(diff / 2592000000) + ' tháng trước';
                } catch (e) {
                    return 'vừa xong';
                }
            }

            // Setup interactive comment functionality
            function setupCommentInteractions(shadowRoot) {
                // Handle like/unlike comments
                const likeButtons = shadowRoot.querySelectorAll('.action-btn[data-action="like"]');
                likeButtons.forEach((btn, index) => {
                    btn.addEventListener('click', async function(e) {
                        // Prevent event bubbling
                        e.stopPropagation();
                        const commentId = this.dataset.commentId;
                        const isLiked = this.classList.contains('liked');
                        if (!commentId) {
                            return;
                        }

                        // Optimistic UI update
                        this.classList.toggle('liked');
                        const likeIcon = this.querySelector('.like-icon');
                        const likeCount = this.querySelector('.like-count');

                        if (likeIcon) {
                            likeIcon.textContent = isLiked ? '🤍' : '❤️';
                        }

                        if (likeCount) {
                            const currentCount = parseInt(likeCount.textContent) || 0;
                            likeCount.textContent = isLiked ? Math.max(0, currentCount - 1) : currentCount + 1;
                        }

                        // Add animation
                        this.style.transform = 'scale(1.2)';
                        setTimeout(() => {
                            this.style.transform = 'scale(1)';
                        }, 150);

                        // Send like/unlike request to server
                        const response = await sendTikTokMessage('toggleLikeComment', {
                            id: commentId,
                            toggle: !isLiked
                        });
                        if (!response || !response.success) {
                            // Revert UI on failure
                            this.classList.toggle('liked');
                            if (likeIcon) {
                                likeIcon.textContent = isLiked ? '❤️' : '🤍';
                            }
                            if (likeCount) {
                                const currentCount = parseInt(likeCount.textContent) || 0;
                                likeCount.textContent = isLiked ? currentCount + 1 : Math.max(0, currentCount - 1);
                            }
                        }
                    });

                    // Make child elements not interfere with click
                    const children = btn.querySelectorAll('span');
                    children.forEach(child => {
                        child.style.pointerEvents = 'none';
                    });
                });

                // Handle reply button click
                const replyButtons = shadowRoot.querySelectorAll('.action-btn[data-action="reply"]');
                replyButtons.forEach(btn => {
                    btn.addEventListener('click', function(e) {
                        e.stopPropagation();

                        const commentId = this.dataset.commentId;
                        if (!commentId) {
                            return;
                        }

                        const replyContainer = shadowRoot.querySelector(\`.reply-input-container[data-comment-id="\${commentId}"]\`);
                        const replyInput = replyContainer?.querySelector('.reply-input');

                        if (!replyContainer || !replyInput) {
                            return;
                        }
                        // Toggle reply input
                        replyContainer.classList.toggle('active');
                        if (replyContainer.classList.contains('active')) {
                            setTimeout(() => replyInput.focus(), 100);
                        } else {
                            replyInput.value = '';
                        }
                    });

                    // Make child elements not interfere
                    const children = btn.querySelectorAll('span');
                    children.forEach(child => {
                        child.style.pointerEvents = 'none';
                    });
                });

                // Handle reply form submission
                const postButtons = shadowRoot.querySelectorAll('.reply-btn.post');
                postButtons.forEach(btn => {
                    btn.addEventListener('click', async function(e) {
                        e.stopPropagation();
                        e.preventDefault();

                        const commentId = this.dataset.commentId;
                        if (!commentId) {
                            return;
                        }

                        const replyContainer = shadowRoot.querySelector(\`.reply-input-container[data-comment-id="\${commentId}"]\`);
                        const replyInput = replyContainer?.querySelector('.reply-input');

                        if (!replyContainer || !replyInput) {
                            return;
                        }

                        const replyText = replyInput.value.trim();
                        if (!replyText) {
                            replyInput.focus();
                            return;
                        }

                        // Disable button to prevent double-click
                        this.disabled = true;
                        this.textContent = 'Đang gửi...';

                        // Get videoId
                        const videoId = getCurrentVideoId();
                        if (!videoId) {
                            showTikTokNotification('Không thể gửi reply. Vui lòng thử lại!', 'error');
                            this.disabled = false;
                            this.textContent = 'Gửi';
                            return;
                        }

                        // Send reply to server
                        const response = await sendTikTokMessage('postComment', {
                            data: {
                                id: videoId,          // ✅ Video ID
                                replyTo: commentId,   // ✅ Parent comment ID
                                comment: replyText
                            }
                        });
                        // Re-enable button
                        this.disabled = false;
                        this.textContent = 'Gửi';

                        if (response && response.success) {
                            // Clear and hide reply input
                            replyInput.value = '';
                            replyContainer.classList.remove('active');

                            // Show success notification
                            showTikTokNotification('Đã gửi reply thành công!', 'success');

                            // Auto update reply count
                            // Find parent comment element
                            const commentEl = shadowRoot.querySelector('[data-comment-id="' + commentId + '"]');
                            if (commentEl) {
                                // Update reply count
                                const replyCountEl = commentEl.querySelector('.action-btn[data-action="reply"] .reply-count');
                                if (replyCountEl) {
                                    const currentCount = parseInt(replyCountEl.textContent) || 0;
                                    replyCountEl.textContent = currentCount + 1;
                                }

                                // Find view replies button
                                const viewRepliesBtn = commentEl.querySelector('.view-replies-btn');

                                // Check if replies container exists and is visible
                                const repliesContainer = commentEl.querySelector('.replies-container');
                                const shouldReload = repliesContainer && repliesContainer.style.display !== 'none';

                                // Always reload/show replies after posting
                                const reloadResponse = await sendTikTokMessage('getReplies', {
                                    commentId: commentId,
                                    page: 0
                                });

                                if (reloadResponse && reloadResponse.success && reloadResponse.replies) {
                                    // Trigger display via message event
                                    window.postMessage({
                                        action: 'tiktokRepliesData',
                                        commentId: commentId,
                                        replies: reloadResponse.replies,
                                        page: 0
                                    }, '*');

                                    // Update "View replies" button to "Hide replies"
                                    if (viewRepliesBtn) {
                                        const totalCount = parseInt(replyCountEl?.textContent) || reloadResponse.replies.length;
                                        viewRepliesBtn.textContent = 'Ẩn ' + totalCount + ' câu trả lời';
                                    }

                                    // Show success animation
                                    setTimeout(() => {
                                        const newRepliesContainer = commentEl.querySelector('.replies-container');
                                        if (newRepliesContainer) {
                                            newRepliesContainer.style.animation = 'fadeIn 0.3s ease';
                                        }
                                    }, 100);
                                } else if (viewRepliesBtn) {
                                    // Fallback: just update button text
                                    const newCount = (parseInt(replyCountEl?.textContent) || 0);
                                    viewRepliesBtn.textContent = 'Xem ' + newCount + ' câu trả lời';
                                }
                            }
                        } else {
                            showTikTokNotification('bạn đã bị giới hạn reply! ' + (response?.error || 'Unknown error'), 'error');
                        }
                    });
                });

                // Handle reply cancellation
                shadowRoot.querySelectorAll('.reply-btn.cancel').forEach(btn => {
                    btn.addEventListener('click', function() {
                        const commentId = this.dataset.commentId;
                        const replyContainer = shadowRoot.querySelector(\`.reply-input-container[data-comment-id="\${commentId}"]\`);
                        const replyInput = replyContainer.querySelector('.reply-input');

                        replyInput.value = '';
                        replyContainer.classList.remove('active');
                    });
                });

                // Handle delete comment
                shadowRoot.querySelectorAll('.delete-btn').forEach(btn => {
                    btn.addEventListener('click', async function() {
                        const commentId = this.dataset.commentId;
                        const username = this.dataset.username;

                        // Show TikTok-style delete dialog
                        const confirmed = await window.showDeleteDialog(
                            shadowRoot,
                            'Xóa bình luận?',
                            'Bình luận này sẽ bị xóa vĩnh viễn và không thể khôi phục.'
                        );

                        if (confirmed) {
                            const response = await sendTikTokMessage('deleteComment', {
                                id: commentId,
                                videoId: getCurrentVideoId()
                            });

                            if (response && response.success) {
                                // Remove comment from UI with animation
                                const commentItem = this.closest('.comment-item');
                                commentItem.style.animation = 'fadeOut 0.3s ease';
                                setTimeout(() => {
                                    commentItem.remove();
                                }, 300);
                            }
                        }
                    });
                });

                // Handle Enter key in reply inputs
                shadowRoot.querySelectorAll('.reply-input').forEach(input => {
                    input.addEventListener('keydown', function(e) {
                        if (e.key === 'Enter' && !e.shiftKey) {
                            e.preventDefault();
                            const commentId = this.dataset.commentId;
                            const postBtn = shadowRoot.querySelector(\`.reply-btn.post[data-comment-id="\${commentId}"]\`);
                            postBtn.click();
                            return false;
                        }
                        
                        // FORCE INSERT space manually because textarea is not receiving it
                        if (e.key === ' ' || e.code === 'Space' || e.keyCode === 32) {
                            e.preventDefault(); // Prevent default to avoid double space
                            
                            // Get cursor position
                            const start = this.selectionStart;
                            const end = this.selectionEnd;
                            const value = this.value;
                            
                            // Insert space at cursor position
                            this.value = value.substring(0, start) + ' ' + value.substring(end);
                            
                            // Move cursor after the space
                            this.selectionStart = this.selectionEnd = start + 1;
                            
                            // Trigger input event manually
                            const inputEvent = new Event('input', { bubbles: true });
                            this.dispatchEvent(inputEvent);
                            return false;
                        }
                        
                        // Allow all other keys
                        return true;
                    }, false); // Use bubble phase, not capture
                    

                    
                    // Ensure input is focusable and editable
                    // REMOVED: input.setAttribute('contenteditable', 'true'); - This breaks textarea!
                    input.removeAttribute('contenteditable'); // Remove if exists
                    input.removeAttribute('readonly'); // Remove readonly if exists
                    input.removeAttribute('disabled'); // Remove disabled if exists
                    input.style.pointerEvents = 'auto';
                    input.style.userSelect = 'text';
                    input.style.webkitUserSelect = 'text';
                    

                });

                // Icon clicks removed - emoji picker disabled
                
                // View replies handler
                shadowRoot.querySelectorAll('.view-replies-btn, [class*="view-replies"]').forEach(btn => {
                    btn.addEventListener('click', async function() {
                        // Get comment ID from button or parent
                        const commentId = this.dataset.commentId || this.closest('[data-comment-id]')?.dataset.commentId;

                        if (!commentId) {
                            return;
                        }
                        // Check if replies container already exists
                        const commentEl = shadowRoot.querySelector(\`[data-comment-id="\${commentId}"]\`);
                        let repliesContainer = commentEl?.querySelector('.replies-container');

                        // Toggle if container exists
                        if (repliesContainer && repliesContainer.children.length > 0) {
                            const isHidden = repliesContainer.style.display === 'none';
                            repliesContainer.style.display = isHidden ? 'block' : 'none';

                            // Update button text
                            const replyCount = this.textContent.match(/\\d+/)?.[0] || 0;
                            this.textContent = isHidden ? \`Ẩn \${replyCount} câu trả lời\` : \`Xem \${replyCount} câu trả lời\`;
                            return;
                        }

                        // Show loading state
                        const originalText = this.textContent;
                        this.textContent = 'Đang tải...';
                        this.disabled = true;

                        // Send request to load replies
                        const response = await sendTikTokMessage('getReplies', {
                            commentId: commentId,
                            page: 0
                        });

                        // Restore button
                        this.textContent = originalText;
                        this.disabled = false;

                        if (response && response.success && response.replies) {
                            // The replies will be displayed by the tiktokRepliesData listener
                            // But we also manually trigger it here for immediate display
                            window.postMessage({
                                action: 'tiktokRepliesData',
                                commentId: commentId,
                                replies: response.replies,
                                page: 0
                            }, '*');

                            // Update button text to "Hide"
                            const totalReplies = this.textContent.match(/\\d+/)?.[0] || response.replies.length;
                            this.textContent = \`Ẩn \${totalReplies} câu trả lời\`;
                        } else {
                            showTikTokNotification('Không thể tải replies. Vui lòng thử lại!', 'error');
                        }
                    });
                });
                // Smooth scrolling
                const commentsBody = shadowRoot.querySelector('.comments-body');
                if (commentsBody) {
                    commentsBody.addEventListener('wheel', function(e) {
                        // Prevent default scrolling behavior
                        e.preventDefault();
                        e.stopPropagation();

                        // Get scroll amount from wheel delta
                        const delta = e.deltaY;

                        // Scroll the comments body smoothly
                        this.scrollBy({
                            top: delta,
                            behavior: 'smooth'
                        });
                    }, { passive: false });
                }
            }

            // sendTikTokMessage is defined globally at line 1035 (outside eval)

            // Helper function to get current video ID
            function getCurrentVideoId() {
                // Try global variable first (set when comments are loaded)
                if (currentVideoIdGlobal) {
                    return currentVideoIdGlobal;
                }
                // Fallback to DOM attribute
                return document.querySelector('[data-video-id]')?.dataset.videoId || null;
            }
        `);
    } catch (e) {
    }

    // Listen for messages from FiveM
    window.addEventListener('message', function (event) {
        try {
            const data = event.data;

            // Only process TikTok-related messages
            if (!data || !data.action) return;
            if (!['loadTikTokCommentsHandler', 'tiktokCommentsData', 'tiktokTestMessage', 'tiktokNewComment'].includes(data.action)) return;
            // loadTikTokCommentsHandler is deprecated - function already created at load time

            // Handle comments data
            if (data && data.action === 'tiktokCommentsData') {
                if (data.comments && Array.isArray(data.comments)) {
                    // Save videoId globally for reply functionality
                    if (data.videoId) {
                        currentVideoIdGlobal = data.videoId;
                    }

                    // Determine if this is initial load or pagination
                    const page = data.page || 0;
                    const isAppending = page > 0;

                    // Reset pagination state if loading fresh (page 0)
                    if (page === 0) {
                        currentCommentsPage = 0;
                        hasMoreComments = true;
                        isLoadingMoreComments = false;
                    }

                    // Now try to display comments
                    if (typeof window.displayTikTokComments === 'function') {
                        window.displayTikTokComments(data.comments, page, isAppending);
                    } else {
                    }
                }
            }

            // Handle test message
            if (data && data.action === 'tiktokTestMessage') {
                return;
            }

        } catch (e) {
        }
    });

    // Test if we can receive messages at all
    setTimeout(() => {
        // Send a test message to ourselves
        window.postMessage({
            action: 'tiktokTestMessage',
            message: 'Test from within the script'
        }, '*');
    }, 2000);

    // Real-time listeners

    // Global cache for comment data and video ID
    let commentsGlobalCache = new Map();
    let currentShadowRoot = null;
    let currentVideoIdGlobal = null;

    // Pagination state
    let currentCommentsPage = 0;
    let isLoadingMoreComments = false;
    let hasMoreComments = true;

    // Listen for REAL-TIME UPDATES from Client Lua
    window.addEventListener('message', function (event) {
        try {
            const data = event.data;
            if (!data || !data.action) return;
            // Like comment real-time
            if (data.action === 'tiktok:updateCommentLikes') {
                const shadowHost = document.querySelector('#tiktok-comments-shadow-host');
                if (!shadowHost || !shadowHost.shadowRoot) {
                    return;
                }

                const shadowRoot = shadowHost.shadowRoot;
                const commentEl = shadowRoot.querySelector(`[data-comment-id="${data.id}"]`);

                if (commentEl) {
                    const likeBtn = commentEl.querySelector('.action-btn[data-action="like"]');
                    const likeIcon = likeBtn?.querySelector('span:first-child');
                    const likeCount = likeBtn?.querySelector('span:last-child');

                    if (data.method === 'add') {
                        likeBtn?.classList.add('liked');
                        if (likeIcon) likeIcon.textContent = '❤️';
                        if (likeCount) {
                            const count = parseInt(likeCount.textContent) || 0;
                            likeCount.textContent = count + 1;
                        }
                    } else {
                        likeBtn?.classList.remove('liked');
                        if (likeIcon) likeIcon.textContent = '🤍';
                        if (likeCount) {
                            const count = parseInt(likeCount.textContent) || 0;
                            likeCount.textContent = Math.max(0, count - 1);
                        }
                    }

                    // Animation
                    if (likeBtn) {
                        likeBtn.style.transform = 'scale(1.2)';
                        setTimeout(() => {
                            likeBtn.style.transform = 'scale(1)';
                        }, 150);
                    }
                }
            }

            // Comment count real-time
            if (data.action === 'tiktok:updateComments') {
                // ❌ DISABLED AUTO-RELOAD vì Client Lua đã xử lý reload rồi
                // Giữ lại code này để tránh lỗi khi có event từ server
            }

            // Reply count real-time
            if (data.action === 'tiktok:updateReplies') {
                const shadowHost = document.querySelector('#tiktok-comments-shadow-host');
                if (!shadowHost || !shadowHost.shadowRoot) return;

                const shadowRoot = shadowHost.shadowRoot;
                const commentEl = shadowRoot.querySelector('[data-comment-id="' + data.id + '"]');

                if (commentEl) {
                    const replyBtn = commentEl.querySelector('.action-btn[data-action="reply"]');
                    const replyCount = replyBtn?.querySelector('span:last-child');

                    if (replyCount) {
                        const count = parseInt(replyCount.textContent) || 0;
                        const newCount = data.method === 'add' ? count + 1 : Math.max(0, count - 1);
                        replyCount.textContent = newCount;
                    }
                }
            }

            // Handle NEW COMMENT real-time (add to top)
            if (data.action === 'tiktokNewComment') {
                // ✅ FIX: Create shadow DOM if not exists (for first comment on new video)
                let shadowHost = document.querySelector('#tiktok-comments-shadow-host');
                let shadowRoot;

                if (!shadowHost || !shadowHost.shadowRoot) {
                    // Find comments container
                    const commentsContainer = document.querySelector('.comments-body') ||
                                            document.querySelector('[class*="comments-body"]') ||
                                            document.querySelector('.tiktok-video-view') ||
                                            document.querySelector('[class*="video"]') ||
                                            document.body;

                    // Create shadow host
                    shadowHost = document.createElement('div');
                    shadowHost.id = 'tiktok-comments-shadow-host';
                    shadowHost.style.cssText = `
                        position: relative;
                        width: 100%;
                        height: 29rem;
                        display: flex;
                        flex-direction: column;
                        overflow-y: auto;
                        overflow-x: hidden;
                        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
                    `;

                    shadowRoot = shadowHost.attachShadow({ mode: 'open' });

                    // Detect theme
                    const isDarkMode = document.body.dataset.theme === 'dark' ||
                                     document.documentElement.dataset.theme === 'dark' ||
                                     document.querySelector('.phone-container')?.dataset.theme === 'dark' ||
                                     document.querySelector('[data-theme="dark"]') !== null;

                    shadowHost.setAttribute('data-theme', isDarkMode ? 'dark' : 'light');

                    // Add complete styles (including delete dialog - copy from displayTikTokComments)
                    const styles = document.createElement('style');
                    styles.textContent = `
                        /* Dark mode styles */
                        :host([data-theme="dark"]) .comment-item,
                        :host([data-theme="dark"]) .reply-item { color: #ffffff; }
                        :host([data-theme="dark"]) .action-btn { color: #a0a0a0; }
                        :host([data-theme="dark"]) .action-btn:hover { color: #ffffff; }
                        :host([data-theme="dark"]) .time-ago,
                        :host([data-theme="dark"]) .reply-time-ago { color: #808080 !important; }
                        :host([data-theme="dark"]) .comment-username,
                        :host([data-theme="dark"]) .comment-text { color: #ffffff !important; }
                        :host([data-theme="dark"]) .reply-input {
                            background: #1a1a1a !important;
                            color: #ffffff !important;
                            border-color: #333333 !important;
                        }
                        :host([data-theme="dark"]) .delete-dialog {
                            background: #1a1a1a !important;
                        }
                        :host([data-theme="dark"]) .delete-dialog-title {
                            color: #ffffff !important;
                        }
                        :host([data-theme="dark"]) .delete-dialog-message {
                            color: #a0a0a0 !important;
                        }
                        :host([data-theme="dark"]) .delete-dialog-btn {
                            background: #1a1a1a !important;
                        }
                        :host([data-theme="dark"]) .delete-dialog-btn.cancel {
                            color: #ffffff !important;
                        }

                        .comments-body { overflow-y: auto; flex: 1; height: 100%; }
                        .comment-item {
                            padding: 1rem 1.25rem;
                            border-bottom: 0.0625rem solid #f8f8f8;
                            transition: background-color 0.2s ease;
                            background-color: var(--phone-color-highlight);
                        }
                        .comment-item:hover {
                            background: var(--phone-color-highlight);
                            opacity: 0.95;
                        }
                        .comment-avatar {
                            width: 2.5rem; height: 2.5rem; border-radius: 50%;
                            margin-right: 0.75rem; object-fit: cover;
                            border: 0.0625rem solid #f0f0f0;
                        }
                        .verified-badge { color: #1DA1F2; margin-left: 0.25rem; font-size: 0.75rem; font-weight: bold; }
                        .action-buttons { display: flex; gap: 1.25rem; align-items: center; cursor: pointer; }
                        .action-btn {
                            display: flex; align-items: center; gap: 0.25rem;
                            color: #8a8b91; font-size: 0.8125rem;
                            transition: all 0.2s ease; user-select: none; cursor: pointer;
                        }
                        .action-btn:hover { color: var(--phone-color-text); }
                        .action-btn.liked { color: #fe2c55; }
                        .action-btn:active { transform: scale(0.95); }

                        .reply-input-container {
                            margin-top: 0.5rem; padding: 0.75rem;
                            background: var(--phone-color-highlight, rgba(128, 128, 128, 0.1));
                            border-radius: 0.5rem; display: none;
                        }
                        .reply-input-container.active { display: block; }
                        .reply-input {
                            flex: 1; padding: 0.5rem 0.75rem;
                            border: 0.0625rem solid rgba(128, 128, 128, 0.3);
                            border-radius: 0.375rem; font-size: 0.875rem;
                            resize: none; min-height: 2.25rem; outline: none;
                            background: var(--phone-color-background, white);
                            color: var(--phone-color-text, #161823);
                        }
                        .reply-btn {
                            padding: 0.375rem 0.75rem; border: none;
                            border-radius: 0.375rem; font-size: 0.8125rem;
                            cursor: pointer; transition: all 0.2s ease;
                        }
                        .reply-btn.post { background: #161823; color: white; }
                        .reply-btn.cancel { background: rgba(128, 128, 128, 0.2); color: #666; }
                        .delete-btn {
                            position: absolute; top: 1rem; right: 1.25rem;
                            width: 1.25rem; height: 1.25rem;
                            background: rgba(128, 128, 128, 0.2);
                            border: none; border-radius: 50%;
                            color: #666; cursor: pointer;
                            display: flex; align-items: center; justify-content: center;
                            font-size: 0.75rem; transition: all 0.2s ease;
                        }
                        .delete-btn:hover { background: #fe2c55; color: white; }

                        /* Delete Confirmation Dialog - TikTok Style */
                        .delete-dialog-overlay {
                            position: fixed;
                            top: 0;
                            left: 0;
                            right: 0;
                            bottom: 0;
                            background: rgba(0, 0, 0, 0.6);
                            display: flex;
                            align-items: center;
                            justify-content: center;
                            z-index: 9999;
                            animation: fadeIn 0.2s ease;
                        }
                        .delete-dialog {
                            background: white;
                            border-radius: 0.75rem;
                            width: 90%;
                            max-width: 20rem;
                            overflow: hidden;
                            animation: slideUp 0.3s ease;
                            box-shadow: 0 0.5rem 1.5rem rgba(0, 0, 0, 0.15);
                        }
                        .delete-dialog-header {
                            padding: 1.25rem 1.25rem 0.75rem;
                            text-align: center;
                            border-bottom: 0.0625rem solid #f0f0f0;
                        }
                        .delete-dialog-title {
                            font-size: 1.0625rem;
                            font-weight: 600;
                            color: var(--phone-color-text, #161823);
                            margin-bottom: 0.5rem;
                        }
                        .delete-dialog-message {
                            font-size: 0.875rem;
                            color: var(--phone-color-text-secondary, #666);
                            line-height: 1.4;
                        }
                        .delete-dialog-actions {
                            display: flex;
                            flex-direction: column;
                        }
                        .delete-dialog-btn {
                            padding: 1rem;
                            border: none;
                            background: white;
                            font-size: 1rem;
                            font-weight: 600;
                            cursor: pointer;
                            border-top: 0.0625rem solid #f0f0f0;
                            transition: background 0.2s ease;
                        }
                        .delete-dialog-btn:active {
                            background: #f8f8f8;
                        }
                        .delete-dialog-btn.confirm {
                            color: #fe2c55;
                        }
                        .delete-dialog-btn.cancel {
                            color: var(--phone-color-text, #161823);
                        }

                        @keyframes slideUp {
                            from {
                                opacity: 0;
                                transform: translateY(1.25rem) scale(0.95);
                            }
                            to {
                                opacity: 1;
                                transform: translateY(0) scale(1);
                            }
                        }
                        @keyframes fadeIn {
                            from { opacity: 0; transform: translateY(-0.625rem); }
                            to { opacity: 1; transform: translateY(0); }
                        }
                        @keyframes fadeOut {
                            from { opacity: 1; }
                            to { opacity: 0; }
                        }
                    `;
                    shadowRoot.appendChild(styles);

                    // Append to DOM
                    commentsContainer.appendChild(shadowHost);
                } else {
                    shadowRoot = shadowHost.shadowRoot;
                }

                // Get or create comments body
                let commentsBody = shadowRoot.querySelector('.comments-body');
                if (!commentsBody) {
                    commentsBody = document.createElement('div');
                    commentsBody.className = 'comments-body';
                    commentsBody.style.cssText = 'overflow-y: auto; flex: 1; height: 100%;';
                    shadowRoot.appendChild(commentsBody);
                }

                if (!data.comment) return;

                // ✅ IMPORTANT: If this is a REPLY (has reply_to), don't show as standalone comment
                // Replies should only appear inside their parent comment's replies container
                if (data.comment.reply_to || data.comment.replyTo) {
                    return; // Exit early, don't insert as top-level comment
                }

                // Create new comment element
                const comment = data.comment;
                const commentDiv = document.createElement('div');
                commentDiv.className = 'comment-item';
                commentDiv.setAttribute('data-comment-id', comment.id);
                commentDiv.setAttribute('data-timestamp', comment.timestamp);
                commentDiv.style.cssText = 'position: relative; animation: fadeIn 0.3s ease;';

                const avatar = comment.avatar ?
                    `<img src="${comment.avatar}" class="comment-avatar">` :
                    `<img src="./assets/img/avatar-placeholder-light.svg" class="comment-avatar">`;

                const verifiedBadge = comment.verified ? '<span class="verified-badge">✓</span>' : '';
                const likedClass = comment.liked ? 'liked' : '';
                const timeAgo = formatTime(comment.timestamp);

                commentDiv.innerHTML = `
                    <button class="delete-btn" data-comment-id="${comment.id}" data-username="${comment.username}">×</button>
                    <div style="display: flex; align-items: flex-start;">
                        ${avatar}
                        <div style="flex: 1;">
                            <div style="font-weight: 600; margin-bottom: 0.375rem; font-size: 0.9375rem; display: flex; align-items: center;" class="comment-username">
                                ${comment.name || comment.username}${verifiedBadge}
                            </div>
                            <div style="margin-bottom: 0.5rem; font-size: 0.9375rem; line-height: 1.4; word-wrap: break-word;" class="comment-text">${comment.comment}</div>
                            <div class="action-buttons">
                                <span class="time-ago" style="color: var(--phone-color-text-secondary, #8a8b91); font-size: 0.8125rem;">${timeAgo}</span>
                                <div class="action-btn ${likedClass}" data-comment-id="${comment.id}" data-action="like">
                                    <span class="like-icon">${comment.liked ? '❤️' : '🤍'}</span>
                                    <span class="like-count">${comment.likes || 0}</span>
                                </div>
                                <div class="action-btn" data-comment-id="${comment.id}" data-action="reply">
                                    <span>💬</span>
                                    <span class="reply-count">${comment.replies || 0}</span>
                                </div>
                            </div>
                            <div class="reply-input-container" data-comment-id="${comment.id}">
                                <div class="reply-input-wrapper">
                                    <textarea class="reply-input" placeholder="Trả lời bình luận..." data-comment-id="${comment.id}"></textarea>
                                </div>
                                <div class="reply-actions">
                                    <button class="reply-btn cancel" data-comment-id="${comment.id}">Hủy</button>
                                    <button class="reply-btn post" data-comment-id="${comment.id}">Gửi</button>
                                </div>
                            </div>
                        </div>
                    </div>
                `;

                // Insert at top (most recent first)
                commentsBody.insertBefore(commentDiv, commentsBody.firstChild);

                // Attach event listeners ONLY for this new comment
                // Like button
                const likeBtn = commentDiv.querySelector('.action-btn[data-action="like"]');
                if (likeBtn) {
                    likeBtn.addEventListener('click', async function(e) {
                        e.stopPropagation();
                        const commentId = this.dataset.commentId;
                        const isLiked = this.classList.contains('liked');
                        if (!commentId) return;

                        this.classList.toggle('liked');
                        const likeIcon = this.querySelector('.like-icon');
                        const likeCount = this.querySelector('.like-count');

                        if (likeIcon) likeIcon.textContent = isLiked ? '🤍' : '❤️';
                        if (likeCount) {
                            const currentCount = parseInt(likeCount.textContent) || 0;
                            likeCount.textContent = isLiked ? Math.max(0, currentCount - 1) : currentCount + 1;
                        }

                        this.style.transform = 'scale(1.2)';
                        setTimeout(() => { this.style.transform = 'scale(1)'; }, 150);

                        const response = await sendTikTokMessage('toggleLikeComment', {
                            id: commentId,
                            toggle: !isLiked
                        });

                        if (!response || !response.success) {
                            this.classList.toggle('liked');
                            if (likeIcon) likeIcon.textContent = isLiked ? '❤️' : '🤍';
                            if (likeCount) {
                                const currentCount = parseInt(likeCount.textContent) || 0;
                                likeCount.textContent = isLiked ? currentCount + 1 : Math.max(0, currentCount - 1);
                            }
                        }
                    });

                    const likeChildren = likeBtn.querySelectorAll('span');
                    likeChildren.forEach(child => { child.style.pointerEvents = 'none'; });
                }

                // Reply button
                const replyBtn = commentDiv.querySelector('.action-btn[data-action="reply"]');
                if (replyBtn) {
                    replyBtn.addEventListener('click', function(e) {
                        e.stopPropagation();
                        const commentId = this.dataset.commentId;
                        if (!commentId) return;

                        const replyContainer = commentDiv.querySelector(`.reply-input-container[data-comment-id="${commentId}"]`);
                        const replyInput = replyContainer?.querySelector('.reply-input');

                        if (!replyContainer || !replyInput) return;

                        replyContainer.classList.toggle('active');
                        if (replyContainer.classList.contains('active')) {
                            setTimeout(() => replyInput.focus(), 100);
                        } else {
                            replyInput.value = '';
                        }
                    });

                    const replyChildren = replyBtn.querySelectorAll('span');
                    replyChildren.forEach(child => { child.style.pointerEvents = 'none'; });
                }

                // Delete button
                const deleteBtn = commentDiv.querySelector('.delete-btn');
                if (deleteBtn) {
                    deleteBtn.addEventListener('click', async function() {
                        const commentId = this.dataset.commentId;
                        const confirmed = await window.showDeleteDialog(
                            shadowRoot,
                            'Xóa bình luận?',
                            'Bình luận này sẽ bị xóa vĩnh viễn và không thể khôi phục.'
                        );

                        if (confirmed) {
                            const response = await sendTikTokMessage('deleteComment', {
                                id: commentId,
                                videoId: data.videoId || currentVideoIdGlobal
                            });

                            if (response && response.success) {
                                commentDiv.style.animation = 'fadeOut 0.3s ease';
                                setTimeout(() => { commentDiv.remove(); }, 300);
                            }
                        }
                    });
                }

                // Reply form - Post button
                const postBtn = commentDiv.querySelector('.reply-btn.post');
                if (postBtn) {
                    postBtn.addEventListener('click', async function(e) {
                        e.stopPropagation();
                        e.preventDefault();

                        const commentId = this.dataset.commentId;
                        if (!commentId) return;

                        const replyContainer = commentDiv.querySelector(`.reply-input-container[data-comment-id="${commentId}"]`);
                        const replyInput = replyContainer?.querySelector('.reply-input');

                        if (!replyContainer || !replyInput) return;

                        const replyText = replyInput.value.trim();
                        if (!replyText) {
                            replyInput.focus();
                            return;
                        }

                        this.disabled = true;
                        this.textContent = 'Đang gửi...';

                        const videoId = data.videoId || currentVideoIdGlobal;
                        if (!videoId) {
                            showTikTokNotification('Không thể gửi reply. Vui lòng thử lại!', 'error');
                            this.disabled = false;
                            this.textContent = 'Gửi';
                            return;
                        }

                        const response = await sendTikTokMessage('postComment', {
                            data: {
                                id: videoId,
                                replyTo: commentId,
                                comment: replyText
                            }
                        });

                        this.disabled = false;
                        this.textContent = 'Gửi';

                        if (response && response.success) {
                            replyInput.value = '';
                            replyContainer.classList.remove('active');

                            // Show success notification
                            showTikTokNotification('Đã gửi reply thành công!', 'success');

                            const replyCountEl = commentDiv.querySelector('.action-btn[data-action="reply"] .reply-count');
                            if (replyCountEl) {
                                const currentCount = parseInt(replyCountEl.textContent) || 0;
                                replyCountEl.textContent = currentCount + 1;
                            }

                            const reloadResponse = await sendTikTokMessage('getReplies', {
                                commentId: commentId,
                                page: 0
                            });

                            if (reloadResponse && reloadResponse.success && reloadResponse.replies) {
                                window.postMessage({
                                    action: 'tiktokRepliesData',
                                    commentId: commentId,
                                    replies: reloadResponse.replies,
                                    page: 0
                                }, '*');
                            }
                        } else {
                            showTikTokNotification('Bạn đã bị giới hạn reply! ' + (response?.error || 'Unknown error'), 'error');
                        }
                    });
                }

                // Reply form - Cancel button
                const cancelBtn = commentDiv.querySelector('.reply-btn.cancel');
                if (cancelBtn) {
                    cancelBtn.addEventListener('click', function() {
                        const commentId = this.dataset.commentId;
                        const replyContainer = commentDiv.querySelector(`.reply-input-container[data-comment-id="${commentId}"]`);
                        const replyInput = replyContainer?.querySelector('.reply-input');

                        if (replyInput) replyInput.value = '';
                        if (replyContainer) replyContainer.classList.remove('active');
                    });
                }

                // Reply input - Enter key
                const replyInput = commentDiv.querySelector('.reply-input');
                if (replyInput) {
                    replyInput.addEventListener('keydown', function(e) {
                        if (e.key === 'Enter' && !e.shiftKey) {
                            e.preventDefault();
                            const commentId = this.dataset.commentId;
                            const postBtn = commentDiv.querySelector(`.reply-btn.post[data-comment-id="${commentId}"]`);
                            if (postBtn) postBtn.click();
                            return false;
                        }

                        if (e.key === ' ' || e.code === 'Space' || e.keyCode === 32) {
                            e.preventDefault();
                            const start = this.selectionStart;
                            const end = this.selectionEnd;
                            const value = this.value;
                            this.value = value.substring(0, start) + ' ' + value.substring(end);
                            this.selectionStart = this.selectionEnd = start + 1;
                            const inputEvent = new Event('input', { bubbles: true });
                            this.dispatchEvent(inputEvent);
                            return false;
                        }

                        return true;
                    }, false);

                    replyInput.removeAttribute('contenteditable');
                    replyInput.removeAttribute('readonly');
                    replyInput.removeAttribute('disabled');
                    replyInput.style.pointerEvents = 'auto';
                    replyInput.style.userSelect = 'text';
                    replyInput.style.webkitUserSelect = 'text';
                }

                // Scroll to top to show new comment
                commentsBody.scrollTop = 0;
            }

            // Load replies data
            if (data.action === 'tiktokRepliesData') {
                const shadowHost = document.querySelector('#tiktok-comments-shadow-host');
                if (!shadowHost || !shadowHost.shadowRoot) return;

                const shadowRoot = shadowHost.shadowRoot;
                const parentComment = shadowRoot.querySelector(`[data-comment-id="${data.commentId}"]`);

                if (parentComment && data.replies && Array.isArray(data.replies)) {
                    let repliesContainer = parentComment.querySelector('.replies-container');
                    const isAppending = data.page > 0;

                    if (!repliesContainer) {
                        repliesContainer = document.createElement('div');
                        repliesContainer.className = 'replies-container';
                        repliesContainer.style.cssText = `
                            margin-top: 0.75rem;
                            margin-left: 3.25rem;
                            padding-left: 0.75rem;
                            border-left: 0.125rem solid #e0e0e0;
                        `;
                        repliesContainer.setAttribute('data-current-page', '0');
                        repliesContainer.setAttribute('data-has-more', 'true');
                        parentComment.appendChild(repliesContainer);
                    }

                    // Only clear if not appending
                    if (!isAppending) {
                        repliesContainer.innerHTML = '';
                        repliesContainer.setAttribute('data-current-page', '0');
                        repliesContainer.setAttribute('data-has-more', 'true');
                    }

                    // Remove existing "Load more" button if any
                    const existingLoadMore = repliesContainer.querySelector('.load-more-replies-btn');
                    if (existingLoadMore) {
                        existingLoadMore.remove();
                    }

                    // Get existing reply IDs to prevent duplicates
                    const existingReplyIds = new Set();
                    repliesContainer.querySelectorAll('.reply-item[data-comment-id]').forEach(el => {
                        const replyId = el.getAttribute('data-comment-id');
                        if (replyId) {
                            existingReplyIds.add(replyId.toString());
                        }
                    });

                    // Filter out duplicate replies
                    const uniqueReplies = data.replies.filter(reply => {
                        return reply && reply.id && !existingReplyIds.has(reply.id.toString());
                    });

                    uniqueReplies.forEach(reply => {
                        const replyEl = document.createElement('div');
                        replyEl.className = 'reply-item';
                        replyEl.setAttribute('data-comment-id', reply.id);
                        replyEl.style.cssText = `padding: 0.75rem 0; border-bottom: 0.0625rem solid #f5f5f5; position: relative;`;

                        const avatar = reply.avatar || './assets/img/avatar-placeholder-light.svg';
                        const timeAgo = formatTime(reply.timestamp);

                        replyEl.innerHTML = `
                            <div style="display: flex; align-items: flex-start;">
                                <button class="delete-reply-btn" data-reply-id="${reply.id}" data-parent-comment-id="${data.commentId}" style="position: absolute; top: 0.75rem; right: 0; width: 1.25rem; height: 1.25rem; background: #f0f0f0; border: none; border-radius: 50%; color: #666; cursor: pointer; display: flex; align-items: center; justify-content: center; font-size: 0.75rem; transition: all 0.2s ease;">×</button>
                                <img src="${avatar}" style="width: 2rem; height: 2rem; border-radius: 50%; margin-right: 0.625rem; object-fit: cover;">
                                <div style="flex: 1;">
                                    <div style="font-weight: 600; font-size: 0.875rem; margin-bottom: 0.25rem;" class="reply-username">
                                        ${reply.name || reply.username}
                                        ${reply.verified ? '<span style="color: #20D5EC; margin-left: 0.25rem;">✓</span>' : ''}
                                    </div>
                                    <div style="font-size: 0.875rem; margin-bottom: 0.375rem;" class="reply-text">${reply.comment}</div>
                                    <div style="display: flex; gap: 0.9375rem; align-items: center; font-size: 0.75rem; color: var(--phone-color-text-secondary, #8a8b91);">
                                        <span class="reply-time-ago">${timeAgo}</span>
                                        <div class="reply-like-btn ${reply.liked ? 'liked' : ''}" style="display: flex; align-items: center; gap: 0.25rem; cursor: pointer; ${reply.liked ? 'color: #fe2c55;' : ''}">
                                            <span>${reply.liked ? '❤️' : '🤍'}</span>
                                            <span>${reply.likes || 0}</span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        `;

                        // Attach like handler to reply
                        const replyLikeBtn = replyEl.querySelector('.reply-like-btn');
                        if (replyLikeBtn) {
                            replyLikeBtn.addEventListener('click', async function () {
                                const isLiked = this.classList.contains('liked');
                                const response = await sendTikTokMessage('toggleLikeComment', {
                                    id: reply.id,
                                    toggle: !isLiked
                                });

                                if (response && response.success) {
                                    this.classList.toggle('liked');
                                    const icon = this.querySelector('span:first-child');
                                    const count = this.querySelector('span:last-child');
                                    icon.textContent = isLiked ? '🤍' : '❤️';
                                    count.textContent = isLiked ? Math.max(0, (parseInt(count.textContent) || 0) - 1) : (parseInt(count.textContent) || 0) + 1;
                                    this.style.color = isLiked ? '#8a8b91' : '#fe2c55';
                                }
                            });
                        }

                        // Attach delete handler to reply
                        const deleteReplyBtn = replyEl.querySelector('.delete-reply-btn');
                        if (deleteReplyBtn) {
                            deleteReplyBtn.addEventListener('click', async function () {
                                const replyId = this.dataset.replyId;
                                const parentCommentId = this.dataset.parentCommentId;

                                const shadowHost = document.querySelector('#tiktok-comments-shadow-host');
                                if (!shadowHost || !shadowHost.shadowRoot) return;

                                // Show TikTok-style delete dialog
                                const confirmed = await window.showDeleteDialog(
                                    shadowHost.shadowRoot,
                                    'Xóa câu trả lời?',
                                    'Câu trả lời này sẽ bị xóa vĩnh viễn và không thể khôi phục.'
                                );

                                if (confirmed) {
                                    const response = await sendTikTokMessage('deleteReply', {
                                        id: replyId,
                                        parentCommentId: parentCommentId
                                    });

                                    if (response && response.success) {
                                        // Remove reply with animation
                                        replyEl.style.animation = 'fadeOut 0.3s ease';
                                        setTimeout(() => {
                                            replyEl.remove();
                                        }, 300);

                                        const parentComment = shadowHost.shadowRoot.querySelector(`[data-comment-id="${parentCommentId}"]`);
                                        if (parentComment) {
                                            const replyCountEl = parentComment.querySelector('.action-btn[data-action="reply"] .reply-count');
                                            if (replyCountEl) {
                                                const currentCount = parseInt(replyCountEl.textContent) || 0;
                                                const newCount = Math.max(0, currentCount - 1);
                                                replyCountEl.textContent = newCount;

                                                const viewRepliesBtn = parentComment.querySelector('.view-replies-btn');
                                                if (viewRepliesBtn) {
                                                    if (newCount === 0) {
                                                        viewRepliesBtn.style.display = 'none';
                                                    } else {
                                                        viewRepliesBtn.textContent = `Ẩn ${newCount} câu trả lời`;
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            });

                            deleteReplyBtn.addEventListener('mouseenter', function () {
                                this.style.background = '#fe2c55';
                                this.style.color = 'white';
                            });
                            deleteReplyBtn.addEventListener('mouseleave', function () {
                                this.style.background = '#f0f0f0';
                                this.style.color = '#666';
                            });
                        }

                        repliesContainer.appendChild(replyEl);
                    });

                    // Update pagination state
                    const currentPage = parseInt(repliesContainer.getAttribute('data-current-page')) || 0;
                    repliesContainer.setAttribute('data-current-page', data.page || currentPage);
                    
                    // Get total reply count from parent comment
                    const replyCountEl = parentComment.querySelector('.action-btn[data-action="reply"] .reply-count');
                    const totalReplies = parseInt(replyCountEl?.textContent) || 0;
                    const loadedReplies = repliesContainer.querySelectorAll('.reply-item').length;
                    
                    // Check if there are more replies to load
                    // Show "Load more" if: loaded less than total AND current batch has items
                    const hasMore = (loadedReplies < totalReplies) && (uniqueReplies.length > 0);
                    
                    if (!hasMore) {
                        repliesContainer.setAttribute('data-has-more', 'false');
                    } else {
                        repliesContainer.setAttribute('data-has-more', 'true');
                        
                        // Add "Load more replies" button
                        const loadMoreBtn = document.createElement('div');
                        loadMoreBtn.className = 'load-more-replies-btn';
                        loadMoreBtn.setAttribute('data-comment-id', data.commentId);
                        loadMoreBtn.style.cssText = `
                            padding: 0.5rem 0;
                            color: var(--phone-color-text-secondary, #666);
                            font-size: 0.8125rem;
                            font-weight: 500;
                            cursor: pointer;
                            text-align: center;
                            transition: color 0.2s ease;
                        `;
                        loadMoreBtn.textContent = 'Xem thêm câu trả lời...';
                        
                        loadMoreBtn.addEventListener('mouseenter', function() {
                            this.style.color = 'var(--phone-color-text, #161823)';
                        });
                        loadMoreBtn.addEventListener('mouseleave', function() {
                            this.style.color = 'var(--phone-color-text-secondary, #666)';
                        });
                        
                        loadMoreBtn.addEventListener('click', async function() {
                            const commentId = this.getAttribute('data-comment-id');
                            const container = this.closest('.replies-container');
                            const currentPage = parseInt(container.getAttribute('data-current-page')) || 0;
                            const nextPage = currentPage + 1;
                            
                            // Show loading state
                            this.textContent = 'Đang tải...';
                            this.style.pointerEvents = 'none';
                            
                            try {
                                const response = await sendTikTokMessage('getReplies', {
                                    commentId: commentId,
                                    page: nextPage
                                });
                                
                                if (response && response.success && response.replies) {
                                    // Trigger display with page info
                                    window.postMessage({
                                        action: 'tiktokRepliesData',
                                        commentId: commentId,
                                        replies: response.replies,
                                        page: nextPage
                                    }, '*');
                                } else {
                                    container.setAttribute('data-has-more', 'false');
                                    this.remove();
                                }
                            } catch (error) {
                                this.textContent = 'Xem thêm câu trả lời...';
                                this.style.pointerEvents = 'auto';
                            }
                        });
                        
                        repliesContainer.appendChild(loadMoreBtn);
                    }
                }
            }

        } catch (e) {
        }
    });

    // Auto-update timestamps every 30s
    setInterval(() => {
        try {
            const shadowHost = document.querySelector('#tiktok-comments-shadow-host');
            if (!shadowHost || !shadowHost.shadowRoot) return;

            const shadowRoot = shadowHost.shadowRoot;
            const timeElements = shadowRoot.querySelectorAll('.time-ago, .reply-time-ago');

            timeElements.forEach(el => {
                const commentEl = el.closest('[data-comment-id]');
                if (!commentEl) return;

                // Try to get timestamp from data attribute if available
                const timestamp = commentEl.dataset.timestamp;
                if (timestamp) {
                    el.textContent = formatTime(timestamp);
                }
            });
        } catch (e) {
        }
    }, 30000); // 30 seconds

    // Helper function - reuse formatTime (consistent with eval version)
    function formatTime(timestamp) {
        try {
            // Convert to number if string
            let ts = typeof timestamp === 'string' ? parseInt(timestamp) : timestamp;

            // Validate timestamp
            if (!ts || isNaN(ts) || ts <= 0) {
                return 'vừa xong';
            }

            // If timestamp is in seconds (< year 2100 in seconds = 4102444800)
            // Convert to milliseconds
            if (ts < 4102444800) {
                ts = ts * 1000;
            }

            const now = Date.now();
            const diff = now - ts;

            // Handle negative diff (timestamp in future)
            if (diff < 0) {
                return 'vừa xong';
            }

            if (diff < 60000) return 'vừa xong';
            if (diff < 3600000) return Math.floor(diff / 60000) + ' phút trước';
            if (diff < 86400000) return Math.floor(diff / 3600000) + ' giờ trước';
            if (diff < 2592000000) return Math.floor(diff / 86400000) + ' ngày trước';
            return Math.floor(diff / 2592000000) + ' tháng trước';
        } catch (e) {
            return 'vừa xong';
        }
    }

    // sendTikTokMessage is now defined globally at line 17 (before eval)
})();
(function () {
    document.querySelectorAll('[aria-label*="Share"], [aria-label="Copy link"]').forEach(function (btn) {
        btn.addEventListener('click', function () {
            var url = encodeURIComponent(location.href);
            var title = encodeURIComponent(document.title);
            var label = btn.getAttribute('aria-label');

            if (label.includes('LinkedIn')) {
                window.open('https://www.linkedin.com/sharing/share-offsite/?url=' + url, '_blank', 'noopener');
            } else if (label.includes('X')) {
                window.open('https://x.com/intent/tweet?url=' + url + '&text=' + title, '_blank', 'noopener');
            } else if (label.includes('email')) {
                location.href = 'mailto:?subject=' + title + '&body=' + decodeURIComponent(url);
            } else if (label.includes('Copy')) {
                var orig = btn.innerHTML;
                navigator.clipboard.writeText(location.href).then(function () {
                    btn.innerHTML = '<svg class="h-4 w-4" fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4.5 12.75l6 6 9-13.5"/></svg>';
                    setTimeout(function () { btn.innerHTML = orig; }, 2000);
                });
            }
        });
    });
})();
